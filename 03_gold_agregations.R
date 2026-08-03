# ==============================================================
# Groupe 6 - Architecture Lakehouse Forensique
# Semaine 3 : Zone Gold - Agregations et requetes DuckDB
# Script complet, tout-en-un (traitement sur disque D)
# ==============================================================

library(DBI)
library(duckdb)

# --------------------------------------------------------------
# 1. Preparation du dossier temporaire sur D
# --------------------------------------------------------------
dir.create("D:/duckdb/temp", recursive = TRUE, showWarnings = FALSE)

con <- dbConnect(duckdb())
dbExecute(con, "SET temp_directory='D:/duckdb/temp'")

# Verification immediate que le chemin est bien pris en compte
verif <- dbGetQuery(con, "SELECT current_setting('temp_directory') AS valeur")
cat("Dossier temporaire configure :", verif$valeur, "\n")

dbExecute(con, "SET max_temp_directory_size='15GB'")
dbExecute(con, "SET threads=2")
dbExecute(con, "SET preserve_insertion_order=false")

# --------------------------------------------------------------
# 2. Connexion a S3
# --------------------------------------------------------------
dbExecute(con, "INSTALL httpfs; LOAD httpfs;")
dbExecute(con, "SET s3_region='eu-north-1';")
dbExecute(con, sprintf("SET s3_access_key_id='%s';", Sys.getenv("AWS_ACCESS_KEY_ID")))
dbExecute(con, sprintf("SET s3_secret_access_key='%s';", Sys.getenv("AWS_SECRET_ACCESS_KEY")))

BUCKET <- "groupe06-lakehouse-forensique"
SILVER <- sprintf("s3://%s/silver/auth_silver.parquet", BUCKET)

cat("Configuration terminee. Debut de la creation des tables Gold.\n\n")

# ==============================================================
# TABLE GOLD 1 : Connexions par utilisateur et par heure
# Objectif : profil horaire habituel de chaque utilisateur
# Usage Power BI : graphique "activite par heure"
# ==============================================================
cat("Table 1/8 : connexions_par_utilisateur_heure...\n")
dbExecute(con, sprintf("
  COPY (
    SELECT
      source_user_domain,
      CAST(heure_du_jour AS INTEGER) AS heure,
      COUNT(*) AS nb_connexions,
      SUM(CASE WHEN succes THEN 0 ELSE 1 END) AS nb_echecs
    FROM read_parquet('%s')
    WHERE source_user_domain IS NOT NULL
    GROUP BY source_user_domain, heure
  ) TO 's3://%s/gold/connexions_par_utilisateur_heure.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

# ==============================================================
# TABLE GOLD 2 : Activite par machine
# Objectif : machines les plus sollicitees + leur nature reelle
# Usage Power BI : graphique "top machines"
# ==============================================================
cat("Table 2/8 : activite_par_machine...\n")
dbExecute(con, sprintf("
  COPY (
    SELECT
      destination_computer,
      categorie_destination,
      COUNT(*) AS nb_evenements,
      COUNT(DISTINCT source_user_domain) AS nb_utilisateurs_distincts
    FROM read_parquet('%s')
    WHERE destination_computer IS NOT NULL
    GROUP BY destination_computer, categorie_destination
  ) TO 's3://%s/gold/activite_par_machine.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

# ==============================================================
# TABLE GOLD 3 : Anomalies horaires
# Objectif : connexions en dehors des horaires habituels (<6h ou >22h)
# Usage Power BI : graphique cle "detection d'anomalies"
# ==============================================================
cat("Table 3/8 : anomalies_horaires...\n")
dbExecute(con, sprintf("
  COPY (
    SELECT
      source_user_domain,
      destination_computer,
      heure_du_jour,
      COUNT(*) AS nb_connexions_horaire_inhabituel
    FROM read_parquet('%s')
    WHERE (heure_du_jour < 6 OR heure_du_jour > 22)
      AND source_user_domain IS NOT NULL
    GROUP BY source_user_domain, destination_computer, heure_du_jour
    ORDER BY nb_connexions_horaire_inhabituel DESC
  ) TO 's3://%s/gold/anomalies_horaires.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

# ==============================================================
# TABLE GOLD 4 : Taux d'echec par utilisateur
# Objectif : comptes avec taux d'echec eleve (signal de brute-force)
# Usage Power BI : tableau "utilisateurs a risque"
# ==============================================================
cat("Table 4/8 : taux_echec_par_utilisateur...\n")
dbExecute(con, sprintf("
  COPY (
    SELECT
      source_user_domain,
      COUNT(*) AS total_tentatives,
      SUM(CASE WHEN succes THEN 0 ELSE 1 END) AS nb_echecs,
      ROUND(100.0 * SUM(CASE WHEN succes THEN 0 ELSE 1 END) / COUNT(*), 2) AS taux_echec_pct
    FROM read_parquet('%s')
    WHERE source_user_domain IS NOT NULL
    GROUP BY source_user_domain
    HAVING COUNT(*) >= 10
    ORDER BY taux_echec_pct DESC
  ) TO 's3://%s/gold/taux_echec_par_utilisateur.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

# ==============================================================
# TABLE GOLD 5 : Nombre de machines distinctes par utilisateur
# Objectif : detecter un mouvement lateral potentiel
# Usage Power BI : graphique "diversite des machines par utilisateur"
# ==============================================================
cat("Table 5/8 : machines_distinctes_par_utilisateur...\n")
dbExecute(con, sprintf("
  COPY (
    SELECT
      source_user_domain,
      COUNT(DISTINCT destination_computer) AS nb_machines_distinctes,
      COUNT(*) AS nb_connexions_totales
    FROM read_parquet('%s')
    WHERE source_user_domain IS NOT NULL
      AND categorie_destination = 'machine'
    GROUP BY source_user_domain
    ORDER BY nb_machines_distinctes DESC
  ) TO 's3://%s/gold/machines_distinctes_par_utilisateur.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

# ==============================================================
# TABLE GOLD 6 : Evolution du volume de connexions par jour
# Objectif : reperer des pics d'activite suspects dans le temps
# Usage Power BI : graphique en ligne "evolution temporelle"
# ==============================================================
cat("Table 6/8 : volume_par_jour...\n")
dbExecute(con, sprintf("
  COPY (
    SELECT
      CAST(temps_secondes / 86400 AS INTEGER) AS jour,
      COUNT(*) AS nb_connexions,
      SUM(CASE WHEN succes THEN 0 ELSE 1 END) AS nb_echecs
    FROM read_parquet('%s')
    GROUP BY jour
    ORDER BY jour
  ) TO 's3://%s/gold/volume_par_jour.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

# ==============================================================
# TABLE GOLD 7 : Paires utilisateur-machine rares
# Objectif : connexions n'arrivant qu'une seule fois (plus suspectes)
# Usage Power BI : liste "connexions rares a examiner"
# ==============================================================
cat("Table 7/8 : paires_rares_utilisateur_machine...\n")
dbExecute(con, sprintf("
  COPY (
    SELECT
      source_user_domain,
      destination_computer,
      COUNT(*) AS nb_occurrences
    FROM read_parquet('%s')
    WHERE source_user_domain IS NOT NULL
      AND categorie_destination = 'machine'
    GROUP BY source_user_domain, destination_computer
    HAVING COUNT(*) = 1
  ) TO 's3://%s/gold/paires_rares_utilisateur_machine.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

# ==============================================================
# TABLE GOLD 8 : Croisement avec redteam.txt.gz (validation)
# Objectif : verifier combien de vraies attaques connues sont
#            capturees par nos anomalies horaires (Table 3)
# Usage Power BI : indicateur cle "taux de detection valide"
# ==============================================================
cat("Table 8/8 : validation_redteam...\n")

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

dbExecute(con, sprintf("
  COPY (
    SELECT
      r.temps_secondes,
      r.user_domain,
      r.destination_computer,
      CASE WHEN a.source_user_domain IS NOT NULL THEN TRUE ELSE FALSE END AS detecte_par_anomalie_horaire
    FROM redteam r
    LEFT JOIN read_parquet('s3://%s/gold/anomalies_horaires.parquet') a
      ON r.user_domain = a.source_user_domain
     AND r.destination_computer = a.destination_computer
  ) TO 's3://%s/gold/validation_redteam.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", BUCKET, BUCKET))

cat("\nLes 8 tables Gold ont ete creees avec succes.\n\n")

# --------------------------------------------------------------
# 3. Verification de chaque table (nombre de lignes)
# --------------------------------------------------------------
noms_tables <- c(
  "connexions_par_utilisateur_heure",
  "activite_par_machine",
  "anomalies_horaires",
  "taux_echec_par_utilisateur",
  "machines_distinctes_par_utilisateur",
  "volume_par_jour",
  "paires_rares_utilisateur_machine",
  "validation_redteam"
)

cat("--- Verification : nombre de lignes par table ---\n")
for (nom in noms_tables) {
  chemin <- sprintf("s3://%s/gold/%s.parquet", BUCKET, nom)
  nb <- dbGetQuery(con, sprintf("SELECT COUNT(*) AS n FROM read_parquet('%s')", chemin))
  cat(sprintf("  %-40s : %s lignes\n", nom, format(nb$n, big.mark = " ")))
}

# --------------------------------------------------------------
# 4. Taux de detection global (chiffre cle pour la presentation)
# --------------------------------------------------------------
taux_detection <- dbGetQuery(con, sprintf("
  SELECT
    COUNT(*) AS total_evenements_redteam,
    SUM(CASE WHEN detecte_par_anomalie_horaire THEN 1 ELSE 0 END) AS nb_detectes,
    ROUND(100.0 * SUM(CASE WHEN detecte_par_anomalie_horaire THEN 1 ELSE 0 END) / COUNT(*), 2) AS taux_detection_pct
  FROM read_parquet('s3://%s/gold/validation_redteam.parquet')
", BUCKET))

cat("\n--- Taux de detection des attaques connues (redteam) ---\n")
print(taux_detection)

dbDisconnect(con, shutdown = TRUE)

cat("\n=== Script termine ===\n")



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

# Recreation de la vue redteam
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

# Version rigoureuse : on compare a l'heure EXACTE de l'attaque,
# pas juste "cette paire utilisateur-machine a-t-elle EU une
# anomalie n'importe quand"
taux_detection_rigoureux <- dbGetQuery(con, sprintf("
  SELECT
    COUNT(*) AS total_evenements_redteam,
    SUM(CASE
      WHEN (s.heure_du_jour < 6 OR s.heure_du_jour > 22) THEN 1
      ELSE 0
    END) AS nb_a_horaire_inhabituel,
    ROUND(100.0 * SUM(CASE
      WHEN (s.heure_du_jour < 6 OR s.heure_du_jour > 22) THEN 1
      ELSE 0
    END) / COUNT(*), 2) AS taux_detection_pct
  FROM redteam r
  JOIN read_parquet('%s') s
    ON r.user_domain = s.source_user_domain
   AND r.destination_computer = s.destination_computer
   AND r.temps_secondes = s.temps_secondes
", SILVER))

cat("--- Taux de detection rigoureux (heure exacte de l'attaque) ---\n")
print(taux_detection_rigoureux)

# On met aussi a jour le fichier Gold 8 avec cette version plus juste
dbExecute(con, sprintf("
  COPY (
    SELECT
      r.temps_secondes,
      r.user_domain,
      r.destination_computer,
      s.heure_du_jour,
      CASE WHEN (s.heure_du_jour < 6 OR s.heure_du_jour > 22) THEN TRUE ELSE FALSE END AS detecte_par_anomalie_horaire
    FROM redteam r
    JOIN read_parquet('%s') s
      ON r.user_domain = s.source_user_domain
     AND r.destination_computer = s.destination_computer
     AND r.temps_secondes = s.temps_secondes
  ) TO 's3://%s/gold/validation_redteam.parquet'
  (FORMAT PARQUET, COMPRESSION ZSTD)
", SILVER, BUCKET))

cat("Table 8 mise a jour avec la version rigoureuse.\n")

dbDisconnect(con, shutdown = TRUE)