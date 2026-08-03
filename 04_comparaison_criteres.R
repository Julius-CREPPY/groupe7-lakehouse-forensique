# ==============================================================
# Groupe 6 - Comparaison des criteres de detection
# Objectif : determiner quel(s) critere(s) Gold detectent le
# mieux les vraies attaques connues (redteam), individuellement
# et combines.
# ==============================================================

library(DBI)
library(duckdb)

con <- dbConnect(duckdb())
dbExecute(con, "SET temp_directory='D:/duckdb/temp'")
dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
dbExecute(con, "SET s3_region='eu-north-1';")
dbExecute(con, sprintf("SET s3_access_key_id='%s';", Sys.getenv("AWS_ACCESS_KEY_ID")))
dbExecute(con, sprintf("SET s3_secret_access_key='%s';", Sys.getenv("AWS_SECRET_ACCESS_KEY")))

BUCKET <- "groupe06-lakehouse-forensique"
SILVER <- sprintf("s3://%s/silver/auth_silver.parquet", BUCKET)

dbExecute(con, sprintf("
  CREATE VIEW redteam AS
  SELECT * FROM read_csv(
    's3://%s/bronze/redteam.txt.gz',
    header = false,
    columns = {
      'temps_secondes'        : 'BIGINT',
      'user_domain'           : 'VARCHAR',
      'source_computer'       : 'VARCHAR',
      'destination_computer'  : 'VARCHAR'
    }
  )
", BUCKET))

# --------------------------------------------------------------
# Determination des seuils pour chaque critere, a partir des
# tables Gold deja calculees (approche : seuil = 95e percentile,
# pour reperer les cas "anormalement eleves")
# --------------------------------------------------------------
seuil_echec <- dbGetQuery(con, sprintf("
  SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY taux_echec_pct) AS seuil
  FROM read_parquet('s3://%s/gold/taux_echec_par_utilisateur.parquet')
", BUCKET))$seuil

seuil_machines <- dbGetQuery(con, sprintf("
  SELECT PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY nb_machines_distinctes) AS seuil
  FROM read_parquet('s3://%s/gold/machines_distinctes_par_utilisateur.parquet')
", BUCKET))$seuil

cat("Seuil taux d'echec (95e percentile) :", seuil_echec, "%\n")
cat("Seuil nombre de machines distinctes (95e percentile) :", seuil_machines, "\n\n")

# --------------------------------------------------------------
# Pour chaque evenement redteam, on verifie s'il est capture par
# chaque critere, individuellement et combine (au moins un critere
# declenche = detecte)
# --------------------------------------------------------------
comparaison <- dbGetQuery(con, sprintf("
  WITH evenements AS (
    SELECT
      r.temps_secondes,
      r.user_domain,
      r.destination_computer,
      s.heure_du_jour,
      e.taux_echec_pct,
      m.nb_machines_distinctes,
      p.nb_occurrences AS occurrences_paire
    FROM redteam r
    JOIN read_parquet('%s') s
      ON r.user_domain = s.source_user_domain
     AND r.destination_computer = s.destination_computer
     AND r.temps_secondes = s.temps_secondes
    LEFT JOIN read_parquet('s3://%s/gold/taux_echec_par_utilisateur.parquet') e
      ON r.user_domain = e.source_user_domain
    LEFT JOIN read_parquet('s3://%s/gold/machines_distinctes_par_utilisateur.parquet') m
      ON r.user_domain = m.source_user_domain
    LEFT JOIN read_parquet('s3://%s/gold/paires_rares_utilisateur_machine.parquet') p
      ON r.user_domain = p.source_user_domain
     AND r.destination_computer = p.destination_computer
  ),
  flags AS (
    SELECT *,
      (heure_du_jour < 6 OR heure_du_jour > 22)              AS flag_horaire,
      (taux_echec_pct > %f)                                   AS flag_echec,
      (nb_machines_distinctes > %f)                            AS flag_machines,
      (occurrences_paire = 1)                                  AS flag_paire_rare
    FROM evenements
  )
  SELECT
    COUNT(*) AS total_evenements,
    SUM(CASE WHEN flag_horaire THEN 1 ELSE 0 END)                                      AS detectes_horaire,
    SUM(CASE WHEN flag_echec THEN 1 ELSE 0 END)                                         AS detectes_echec,
    SUM(CASE WHEN flag_machines THEN 1 ELSE 0 END)                                      AS detectes_machines,
    SUM(CASE WHEN flag_paire_rare THEN 1 ELSE 0 END)                                    AS detectes_paire_rare,
    SUM(CASE WHEN flag_horaire OR flag_echec OR flag_machines OR flag_paire_rare
             THEN 1 ELSE 0 END)                                                          AS detectes_au_moins_un
  FROM flags
", SILVER, BUCKET, BUCKET, BUCKET, seuil_echec, seuil_machines))

comparaison$pct_horaire       <- round(100 * comparaison$detectes_horaire / comparaison$total_evenements, 2)
comparaison$pct_echec         <- round(100 * comparaison$detectes_echec / comparaison$total_evenements, 2)
comparaison$pct_machines      <- round(100 * comparaison$detectes_machines / comparaison$total_evenements, 2)
comparaison$pct_paire_rare    <- round(100 * comparaison$detectes_paire_rare / comparaison$total_evenements, 2)
comparaison$pct_au_moins_un   <- round(100 * comparaison$detectes_au_moins_un / comparaison$total_evenements, 2)

cat("=== Comparaison des criteres de detection (base :", comparaison$total_evenements, "evenements redteam) ===\n\n")
cat(sprintf("Critere horaire inhabituel        : %s detectes (%.2f%%)\n", comparaison$detectes_horaire, comparaison$pct_horaire))
cat(sprintf("Critere taux d'echec eleve (>%.1f%%) : %s detectes (%.2f%%)\n", seuil_echec, comparaison$detectes_echec, comparaison$pct_echec))
cat(sprintf("Critere machines distinctes (>%.1f) : %s detectes (%.2f%%)\n", seuil_machines, comparaison$detectes_machines, comparaison$pct_machines))
cat(sprintf("Critere paire rare (1 seule fois)  : %s detectes (%.2f%%)\n", comparaison$detectes_paire_rare, comparaison$pct_paire_rare))
cat(sprintf("\nCOMBINE (au moins un critere)       : %s detectes (%.2f%%)\n", comparaison$detectes_au_moins_un, comparaison$pct_au_moins_un))

# --------------------------------------------------------------
# Sauvegarde du resultat en table Gold pour Power BI / rapport
# --------------------------------------------------------------
dbWriteTable(con, "comparaison_criteres", comparaison, overwrite = TRUE)
dbExecute(con, sprintf("
  COPY comparaison_criteres TO 's3://%s/gold/comparaison_criteres_detection.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", BUCKET))

cat("\nTable comparaison_criteres_detection.parquet sauvegardee dans gold/.\n")

dbDisconnect(con, shutdown = TRUE)
