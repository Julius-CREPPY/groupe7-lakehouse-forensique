## upload bronze

library(aws.s3)

bucket_name   <- "groupe06-lakehouse-forensique"  # verifiez que c'est le nom exact
fichier_local <- "data/auth.txt.gz"
cle_s3_bronze <- "bronze/auth.txt.gz"

# Verification que le bucket est accessible
if (bucket_exists(bucket_name)) {
  cat("OK : bucket accessible.\n")
} else {
  stop("Bucket inaccessible - verifiez le nom ou vos identifiants.")
}

# Upload du fichier brut (peut prendre du temps vu la taille, 7.6 Go)
cat("Upload en cours, patientez...\n")
put_object(
  file   = fichier_local,
  object = cle_s3_bronze,
  bucket = bucket_name,
  multipart = TRUE  # important pour les gros fichiers, decoupe l'envoi en morceaux
)
cat("Upload termine.\n")

# Verification finale
contenu_bronze <- get_bucket_df(bucket = bucket_name, prefix = "bronze/")
print(contenu_bronze[, c("Key", "Size", "LastModified")])