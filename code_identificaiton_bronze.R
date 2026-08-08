## upload bronze
library(aws.s3)
library(httr)

bucket_name   <- "groupe06-lakehouse-forensique"
fichier_local <- "data/auth.txt.gz"
cle_s3_bronze <- "bronze/auth.txt.gz"

if (bucket_exists(bucket_name)) {
  cat("OK : bucket accessible.\n")
} else {
  stop("Bucket inaccessible - verifiez le nom ou vos identifiants.")
}

cat("Upload en cours, patientez...\n")
put_object(
  file      = fichier_local,
  object    = cle_s3_bronze,
  bucket    = bucket_name,
  multipart = TRUE,
  config    = httr::config(connecttimeout = 60, timeout = 3600)
)
cat("Upload termine.\n")

contenu_bronze <- get_bucket_df(bucket = bucket_name, prefix = "bronze/")
print(contenu_bronze[, c("Key", "Size", "LastModified")])


### chargement du fichier redteam

put_object(
  file   = "data/redteam.txt.gz",
  object = "bronze/redteam.txt.gz",
  bucket = bucket_name
)

con <- gzfile("data/auth.txt.gz", "r")
apercu <- readLines(con, n = 10)
close(con)

print(apercu)
?gzfile

###recherche des erreurs

install.packages("duckdb")
install.packages("DBI")
library(duckdb)
library(DBI)

# --------------------------------------------------------------
# 1. Connexion et lecture du fichier brut
# --------------------------------------------------------------
con <- dbConnect(duckdb())

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

cat("=== Fichier charge, debut du diagnostic ===\n\n")

# --------------------------------------------------------------
# 2. Colonnes categorielles : lister TOUTES les valeurs distinctes
# --------------------------------------------------------------
cat("--- authentication_type ---\n")
print(dbGetQuery(con, "
  SELECT authentication_type, COUNT(*) AS nb
  FROM auth_brut GROUP BY authentication_type ORDER BY nb DESC
"))

cat("\n--- logon_type ---\n")
print(dbGetQuery(con, "
  SELECT logon_type, COUNT(*) AS nb
  FROM auth_brut GROUP BY logon_type ORDER BY nb DESC
"))

cat("\n--- authentication_orientation ---\n")
print(dbGetQuery(con, "
  SELECT authentication_orientation, COUNT(*) AS nb
  FROM auth_brut GROUP BY authentication_orientation ORDER BY nb DESC
"))

cat("\n--- success_failure ---\n")
print(dbGetQuery(con, "
  SELECT success_failure, COUNT(*) AS nb
  FROM auth_brut GROUP BY success_failure ORDER BY nb DESC
"))

# --------------------------------------------------------------
# 3. Colonnes "identifiant" : verifier le format attendu (user@domaine)
# --------------------------------------------------------------
cat("\n--- Valeurs qui NE respectent PAS le format 'xxx@xxx' ---\n")

cat("source_user_domain :\n")
print(dbGetQuery(con, "
  SELECT source_user_domain, COUNT(*) AS nb
  FROM auth_brut
  WHERE source_user_domain NOT LIKE '%@%'
  GROUP BY source_user_domain ORDER BY nb DESC LIMIT 20
"))

cat("destination_user_domain :\n")
print(dbGetQuery(con, "
  SELECT destination_user_domain, COUNT(*) AS nb
  FROM auth_brut
  WHERE destination_user_domain NOT LIKE '%@%'
  GROUP BY destination_user_domain ORDER BY nb DESC LIMIT 20
"))

# --------------------------------------------------------------
# 4. Colonnes "machine" : verifier le format attendu (C + chiffres)
# --------------------------------------------------------------
cat("\n--- Machines qui NE respectent PAS le format 'C123' ---\n")

cat("source_computer :\n")
print(dbGetQuery(con, "
  SELECT source_computer, COUNT(*) AS nb
  FROM auth_brut
  WHERE NOT regexp_matches(source_computer, '^C[0-9]+\\$?$')
  GROUP BY source_computer ORDER BY nb DESC LIMIT 20
"))

cat("destination_computer :\n")
print(dbGetQuery(con, "
  SELECT destination_computer, COUNT(*) AS nb
  FROM auth_brut
  WHERE NOT regexp_matches(destination_computer, '^C[0-9]+\\$?$')
  GROUP BY destination_computer ORDER BY nb DESC LIMIT 20
"))

# --------------------------------------------------------------
# 5. Colonne numerique : bornes logiques
# --------------------------------------------------------------
cat("\n--- temps_secondes : min / max / valeurs negatives ---\n")
print(dbGetQuery(con, "
  SELECT
    MIN(temps_secondes) AS min_temps,
    MAX(temps_secondes) AS max_temps,
    SUM(CASE WHEN temps_secondes < 0 THEN 1 ELSE 0 END) AS nb_negatifs,
    COUNT(*) AS nb_total_lignes
  FROM auth_brut
"))

# --------------------------------------------------------------
# 6. Recapitulatif global des '?' colonne par colonne
# --------------------------------------------------------------
cat("\n--- Nombre de '?' par colonne (sur le fichier entier) ---\n")
print(dbGetQuery(con, "
  SELECT
    SUM(CASE WHEN source_user_domain = '?' THEN 1 ELSE 0 END)         AS nb_manquants_source_user,
    SUM(CASE WHEN destination_user_domain = '?' THEN 1 ELSE 0 END)    AS nb_manquants_dest_user,
    SUM(CASE WHEN source_computer = '?' THEN 1 ELSE 0 END)            AS nb_manquants_source_computer,
    SUM(CASE WHEN destination_computer = '?' THEN 1 ELSE 0 END)       AS nb_manquants_dest_computer,
    SUM(CASE WHEN authentication_type = '?' THEN 1 ELSE 0 END)        AS nb_manquants_auth_type,
    SUM(CASE WHEN logon_type = '?' THEN 1 ELSE 0 END)                 AS nb_manquants_logon_type,
    SUM(CASE WHEN authentication_orientation = '?' THEN 1 ELSE 0 END) AS nb_manquants_orientation,
    COUNT(*) AS nb_total_lignes
  FROM auth_brut
"))

cat("\n=== Diagnostic termine ===\n")

# Ne fermez pas la connexion tout de suite si vous voulez enchainer
# directement avec le script de nettoyage (Silver) apres.


###############################################"
###netoyage zone silver 

# ==============================================================
# Groupe 6 - Nettoyage des donnees -> Zone Silver
# Traite les anomalies identifiees dans le rapport de diagnostic
# ==============================================================

library(duckdb)
library(DBI)
library(aws.s3)

dir.create("duckdb_temp", showWarnings = FALSE)

# Chemin absolu plutot que relatif, pour eviter toute ambiguite
chemin_temp <- file.path(getwd(), "duckdb_temp")

con <- dbConnect(duckdb(), config = list(
  "temp_directory" = chemin_temp
))

cat("Dossier temporaire utilise :", chemin_temp, "\n")

# --------------------------------------------------------------
# 1. Chargement complet (une seule fois, avec CREATE TABLE)
# --------------------------------------------------------------
cat("Chargement du fichier brut (patience, plusieurs minutes)...\n")

dbExecute(con, "
  CREATE TABLE auth_brut AS
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
cat("Chargement termine.\n")


library(DBI)
library(duckdb)
library(aws.s3)

dir.create("G:/duckdb/temp", recursive = TRUE, showWarnings = FALSE)

# Connexion EN MEMOIRE (pas de dbdir persistant sur G, pour eviter
# d'ecrire deux fois : une fois pour le brut, une fois pour le nettoye)
con <- dbConnect(duckdb())

dbExecute(con, "SET temp_directory='G:/duckdb/temp'")
dbExecute(con, "SET max_temp_directory_size='100GB'")
dbExecute(con, "SET threads=2")
dbExecute(con, "SET preserve_insertion_order=false")

# VIEW au lieu de TABLE : aucune ecriture, juste une "definition"
# de comment lire le fichier. Rapide, quasi instantane.
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

cat("Vue creee (instantane, aucune ecriture).\n")

# --------------------------------------------------------------
# 2. Nettoyage -> table Silver
# --------------------------------------------------------------
# Ce qu'on corrige, et pourquoi (base sur le rapport de diagnostic) :
#
#   a) NULLIF(colonne, '?')
#      Remplace les valeurs manquantes '?' par de vrais NULL,
#      sur authentication_type et logon_type (55% et 14% de '?').
#
#   b) Regroupement des variantes tronquees
#      Toutes les formes tronquees de MICROSOFT_AUTHENTICATION_PACKAGE_V1_0
#      (ex: 'MICROSOFT_AUTHENTICATION_PACKAG', 'MICROSOFT_AUTHENTICATION_PA'...)
#      sont regroupees en une seule valeur propre, avec LIKE.
#
#   c) categorie_destination
#      Nouvelle colonne qui separe les vraies machines (C+chiffres),
#      des tickets Kerberos (TGT), et des identifiants utilisateurs
#      (U+chiffres) trouves dans destination_computer.
#
#   d) heure_du_jour
#      Conversion du compteur de secondes en heure reelle (0-24).
#
#   e) succes (booleen)
#      Conversion de success_failure en TRUE/FALSE.

dbExecute(con, "
  CREATE TABLE auth_silver AS
  SELECT DISTINCT
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
")

cat("Nettoyage termine.\n")

# --------------------------------------------------------------
# 3. Controle du resultat
# --------------------------------------------------------------
print(dbGetQuery(con, "SELECT COUNT(*) AS nb_lignes FROM auth_silver"))
print(dbGetQuery(con, "SELECT categorie_destination, COUNT(*) AS nb FROM auth_silver GROUP BY categorie_destination ORDER BY nb DESC"))
print(dbGetQuery(con, "SELECT * FROM auth_silver LIMIT 5"))

# --------------------------------------------------------------
# 4. Export en Parquet
# --------------------------------------------------------------
dir.create("data/silver", showWarnings = FALSE)
dbExecute(con, "COPY auth_silver TO 'data/silver/auth_silver.parquet' (FORMAT PARQUET)")

cat("Taille du fichier Parquet (Go) :",
    file.info('data/silver/auth_silver.parquet')$size / 1e9, "\n")

# --------------------------------------------------------------
# 5. Upload vers S3, zone Silver
# --------------------------------------------------------------
bucket_name <- "groupe06-lakehouse-forensique"

put_object(
  file      = "data/silver/auth_silver.parquet",
  object    = "silver/auth_silver.parquet",
  bucket    = bucket_name,
  multipart = TRUE,
  config    = httr::config(connecttimeout = 60, timeout = 3600)
)

cat("Upload vers silver/ termine.\n")
dir.create("C:/DuckDB_temp", showWarnings = FALSE)

DBI::dbExecute(con, "SET max_temp_directory_size='50GB'")
system("dir C:")
dir.create("G:/duckdb/temp", recursive = TRUE, showWarnings = FALSE)
library(DBI)
library(duckdb)

con <- dbConnect(
  duckdb(),
  dbdir = "G:/duckdb/ma_base.duckdb"
)

dbExecute(con, "SET temp_directory='G:/duckdb/temp'")
dbExecute(con, "SET max_temp_directory_size='100GB'")
dbExecute(con, "SET threads=2")
dbExecute(con, "SET preserve_insertion_order=false")




library(DBI)
library(duckdb)
library(aws.s3)

# Nettoyage des anciens fichiers de tentatives precedentes
if (file.exists("G:/duckdb/ma_base.duckdb")) file.remove("G:/duckdb/ma_base.duckdb")
unlink("G:/duckdb/temp", recursive = TRUE)
dir.create("G:/duckdb/temp", recursive = TRUE, showWarnings = FALSE)
dir.create("G:/silver", showWarnings = FALSE)

con <- dbConnect(duckdb())  # en memoire, pas de dbdir persistant

dbExecute(con, "SET temp_directory='G:/duckdb/temp'")
dbExecute(con, "SET max_temp_directory_size='15GB'")  # laisse une marge de securite
dbExecute(con, "SET threads=2")
dbExecute(con, "SET preserve_insertion_order=false")

# VIEW : lecture a la volee, aucune ecriture
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

cat("Vue creee. Debut de l'export direct en Parquet (pas de table intermediaire)...\n")

# COPY directement depuis la VIEW transformee vers un fichier Parquet.
# Aucune table DuckDB creee entre les deux : on ne stocke JAMAIS
# les donnees transformees ailleurs que dans le fichier final,
# ce qui minimise l'espace disque utilise (juste le resultat,
# compresse en plus grace a ZSTD).
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
cat("Taille du fichier Parquet (Go) :",
    file.info("G:/silver/auth_silver.parquet")$size / 1e9, "\n")





bucket_name <- "groupe06-lakehouse-forensique"

put_object(
  file      = "G:/silver/auth_silver.parquet",
  object    = "silver/auth_silver.parquet",
  bucket    = bucket_name,
  multipart = TRUE,
  config    = httr::config(connecttimeout = 60, timeout = 3600)
)

cat("Upload vers silver/ termine.\n")