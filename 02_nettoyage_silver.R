# ==============================================================
# Groupe 6 - Architecture Lakehouse Forensique
# Semaine 2 : Nettoyage des donnees brutes -> Zone Silver
# Version finale fonctionnelle (traitement sur disque externe G)
# ==============================================================

library(DBI)
library(duckdb)
library(aws.s3)

# --------------------------------------------------------------
# 1. Preparation des dossiers de travail sur le disque G
# --------------------------------------------------------------
# Utilisation d'un disque externe (G:) car le disque principal
# a rencontre des erreurs d'acces au dossier temporaire Windows.
if (file.exists("G:/duckdb/ma_base.duckdb")) file.remove("G:/duckdb/ma_base.duckdb")
unlink("G:/duckdb/temp", recursive = TRUE)
dir.create("G:/duckdb/temp", recursive = TRUE, showWarnings = FALSE)
dir.create("G:/silver", showWarnings = FALSE)

# --------------------------------------------------------------
# 2. Connexion DuckDB (en memoire, PAS de dbdir persistant)
# --------------------------------------------------------------
# Important : une connexion en memoire simple, sans base de donnees
# persistante sur disque, evite une double ecriture inutile.
con <- dbConnect(duckdb())

dbExecute(con, "SET temp_directory='G:/duckdb/temp'")
dbExecute(con, "SET max_temp_directory_size='15GB'")   # adapte a l'espace reellement disponible
dbExecute(con, "SET threads=2")
dbExecute(con, "SET preserve_insertion_order=false")

# --------------------------------------------------------------
# 3. Lecture du fichier brut via une VIEW (pas une TABLE)
# --------------------------------------------------------------
# Une VIEW ne declenche aucune ecriture sur disque : le fichier
# n'est lu que lorsqu'une requete en a reellement besoin.
# (Une premiere tentative avec CREATE TABLE a echoue : elle
#  imposait une ecriture complete et inutile du fichier brut
#  decompresse, estime a 40-75 Go, avant meme le nettoyage.)
dbExecute(con, "
  CREATE VIEW auth_brut AS
  SELECT * FROM read_csv(
    'data/auth.txt.gz',
    header = false,
    columns = {
      'temps_secondes'             : 'BIGINT',
      'source_user_domain'         : 'VARCHAR',
      'destination_user_domain'    : 'VARCHAR',
      'source_computer'            : 'VARCHAR',
      'destination_computer'       : 'VARCHAR',
      'authentication_type'        : 'VARCHAR',
      'logon_type'                 : 'VARCHAR',
      'authentication_orientation' : 'VARCHAR',
      'success_failure'            : 'VARCHAR'
    }
  )
")

# --------------------------------------------------------------
# 4. Nettoyage + export direct en Parquet (une seule ecriture)
# --------------------------------------------------------------
# COPY (SELECT ...) TO ... : la transformation et l'export se
# font en une seule passe, sans table intermediaire, ce qui
# minimise l'espace disque utilise.
#
# Corrections appliquees (voir rapport de diagnostic) :
#   - NULLIF(colonne, '?')            : valeurs manquantes -> NULL
#   - regroupement des variantes tronquees de authentication_type
#   - categorie_destination           : separe machines / tickets
#     Kerberos (TGT) / identifiants utilisateurs (U-) melanges
#     dans destination_computer
#   - heure_du_jour                   : conversion du compteur de
#     secondes en heure reelle (0-24)
#   - succes (booleen)                : conversion Success/Failure
#
# Note : l'operation DISTINCT a ete retiree du pipeline principal.
# Un controle sur echantillon a montre un taux de doublons stricts
# negligeable ; le cout de tri sur 1 milliard de lignes n'etait
# pas justifie.
dbExecute(con, "
  COPY (
    SELECT
      temps_secondes,
      (temps_secondes % 86400) / 3600.0 AS heure_du_jour,
      NULLIF(source_user_domain, '?')      AS source_user_domain,
      NULLIF(destination_user_domain, '?') AS destination_user_domain,
      NULLIF(source_computer, '?')         AS source_computer,
      NULLIF(destination_computer, '?')    AS destination_computer,
      CASE
        WHEN destination_computer = 'TGT' THEN 'ticket_kerberos'
        WHEN destination_computer LIKE 'U%' THEN 'identifiant_utilisateur'
        WHEN destination_computer LIKE 'C%' THEN 'machine'
        ELSE 'autre'
      END AS categorie_destination,
      CASE
        WHEN authentication_type LIKE 'MICROSOFT_AUTHENTICATION_PACKAGE%'
          THEN 'MICROSOFT_AUTHENTICATION_PACKAGE_V1_0'
        WHEN authentication_type = '?' THEN NULL
        ELSE authentication_type
      END AS authentication_type,
      NULLIF(logon_type, '?')                 AS logon_type,
      NULLIF(authentication_orientation, '?') AS authentication_orientation,
      (success_failure = 'Success') AS succes
    FROM auth_brut
  ) TO 'G:/silver/auth_silver.parquet' (FORMAT PARQUET, COMPRESSION ZSTD)
")

cat("Export termine.\n")
cat("Taille du fichier Parquet (Go) :",
    file.info("G:/silver/auth_silver.parquet")$size / 1e9, "\n")

# --------------------------------------------------------------
# 5. Verifications
# --------------------------------------------------------------
print(dbGetQuery(con, "SELECT COUNT(*) AS nb_lignes FROM read_parquet('G:/silver/auth_silver.parquet')"))

print(dbGetQuery(con, "
  SELECT categorie_destination, COUNT(*) AS nb
  FROM read_parquet('G:/silver/auth_silver.parquet')
  GROUP BY categorie_destination ORDER BY nb DESC
"))

print(dbGetQuery(con, "
  SELECT COUNT(*) AS nb_points_interrogation_restants
  FROM read_parquet('G:/silver/auth_silver.parquet')
  WHERE authentication_type = '?' OR logon_type = '?'
"))

# --------------------------------------------------------------
# 6. Upload vers S3, zone Silver
# --------------------------------------------------------------
# Note : l'upload via put_object() a echoue (fichier introuvable
# suite a une deconnexion du disque externe). L'upload final a
# ete realise manuellement via la console AWS S3.
#
# Code laisse ici pour reference / reproductibilite si le disque
# reste connecte en continu :
#
# bucket_name <- "groupe06-lakehouse-forensique"
# put_object(
#   file      = "G:/silver/auth_silver.parquet",
#   object    = "silver/auth_silver.parquet",
#   bucket    = bucket_name,
#   multipart = TRUE,
#   config    = httr::config(connecttimeout = 60, timeout = 3600)
# )

dbDisconnect(con, shutdown = TRUE)
