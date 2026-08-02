# Groupe 6 — Architecture Lakehouse pour la forensique numérique

Projet réalisé dans le cadre du Master 1 Cycle Ingénieur Cybersécurité — Semestre 2 (Data Engineering).

## 🎯 Objectif du projet

Construire une architecture **Lakehouse** (Bronze / Silver / Gold) sur AWS S3 pour stocker et analyser des logs de sécurité réels, en garantissant l'intégrité légale des données brutes tout en offrant des données exploitables et interrogeables rapidement en SQL — un besoin central en **forensique numérique**.

Le pipeline s'appuie sur le dataset **LANL Comprehensive Multi-Source Cyber-Security Events** (Los Alamos National Laboratory), et livre un dashboard Power BI capable de détecter des anomalies (ex : connexions à des horaires inhabituels).

## 🏗️ Architecture

```
                ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
  Dataset LANL  │   BRONZE    │      │   SILVER    │      │    GOLD     │      Dashboard
  (auth, ─────► │ Données     │ ───► │ Données     │ ───► │ Tables      │ ───► Power BI
   redteam)     │ brutes,     │      │ nettoyées,  │      │ agrégées,   │
                │ intactes    │      │ typées      │      │ prêtes à    │
                │             │      │ (Parquet)   │      │ l'analyse   │
                └─────────────┘      └─────────────┘      └─────────────┘
                      S3                   S3                   S3
                                            │
                                      Requêtes SQL
                                        (DuckDB)
```

- **Bronze** : données brutes du dataset LANL, jamais modifiées (préservation de l'intégrité légale des preuves)
- **Silver** : données nettoyées, typées, dédupliquées, converties au format Parquet
- **Gold** : tables agrégées prêtes pour l'analyse (par utilisateur, machine, heure)

## 🛠️ Stack technique

| Outil | Rôle |
|---|---|
| **AWS S3** | Stockage des 3 zones (Bronze/Silver/Gold) |
| **R** (`aws.s3`) | Ingestion et transformation des données |
| **DuckDB** | Requêtage SQL des fichiers Parquet directement sur S3 |
| **Power BI** | Dashboard final d'analyse forensique |
| **Git/GitHub** | Versioning du code |

## 📊 Dataset

- **Source** : [csr.lanl.gov/data/cyber1](https://csr.lanl.gov/data/cyber1/)
- **Fichiers utilisés** : `auth.txt.gz` (logs d'authentification, 1 051 430 459 lignes) et `redteam.txt.gz` (événements de compromission connus, vérité terrain)
- Schéma détaillé : voir [`documentation_schema.md`](./documentation_schema.md)
- Diagnostic qualité complet : voir [`rapport_diagnostic_bronze.docx`](./rapport_diagnostic_bronze.docx)

## 🚀 Installation

### Pré-requis
- R + RStudio
- Packages R : `aws.s3`, `duckdb`, `DBI`, `httr`
- Un compte AWS avec accès à un bucket S3
- Power BI Desktop (pour le dashboard final)

### Configuration
1. Cloner ce dépôt :
   ```bash
   git clone https://github.com/Julius-CREPPY/groupe6-lakehouse-forensique.git
   ```
2. Créer un fichier `.Renviron` à la racine du projet (non versionné, voir `.gitignore`) avec vos identifiants AWS :
   ```
   AWS_ACCESS_KEY_ID=votre_access_key_id
   AWS_SECRET_ACCESS_KEY=votre_secret_access_key
   AWS_DEFAULT_REGION=eu-north-1
   ```
3. Installer les dépendances R :
   ```r
   install.packages(c("aws.s3", "duckdb", "DBI", "httr"))
   ```

## 📁 Structure du projet

```
groupe6-lakehouse-forensique/
├── README.md                      # Ce fichier
├── documentation_schema.md        # Documentation du schéma des données brutes
├── rapport_diagnostic_bronze.docx # Rapport de diagnostic qualité (Semaine 1)
├── rapport_nettoyage_silver.docx  # Rapport de nettoyage + difficultés rencontrées (Semaine 2)
├── code.R                         # Script d'ingestion vers la zone Bronze
├── 02_nettoyage_silver.R          # Script de nettoyage -> zone Silver
├── .gitignore                     # Exclut .Renviron et data/
└── data/                          # Fichiers locaux (non versionnés)
```

## 📈 État d'avancement

| Semaine | Tâche | Statut |
|---|---|---|
| 1 | Mise en place S3 (bucket + 3 zones) | ✅ Terminé |
| 1 | Ingestion des données brutes vers Bronze | ✅ Terminé |
| 1 | Exploration et documentation du schéma | ✅ Terminé |
| 2 | Diagnostic qualité exhaustif (1,05 milliard de lignes) | ✅ Terminé |
| 2 | Nettoyage et typage — zone Silver | ✅ Terminé |
| 2 | Export Parquet + upload S3 | ✅ Terminé |
| 3 | Agrégations et requêtes DuckDB — zone Gold | 🔜 À venir |
| 4 | Dashboard Power BI | 🔜 À venir |
| 5 | Finalisation, tests, documentation | 🔜 À venir |

**Dernière mise à jour** : Semaine 2 complétée — zone Silver construite (`auth_silver.parquet`, 7,35 Go, 1 051 430 459 lignes nettoyées) et uploadée vers `s3://groupe06-lakehouse-forensique/silver/`.

### Détails techniques notables (Semaine 2)
- Traitement réalisé avec DuckDB directement sur le fichier compressé source (7,6 Go), sans échantillonnage
- Anomalies corrigées : valeurs manquantes (`?`), variantes tronquées de `authentication_type`, mélange de tickets Kerberos/identifiants utilisateurs dans `destination_computer` (nouvelle colonne `categorie_destination`)
- Optimisations appliquées suite à des contraintes d'espace disque et de performance : lecture via `VIEW` (pas de matérialisation du brut), export direct en Parquet compressé ZSTD — voir [`rapport_nettoyage_silver.docx`](./rapport_nettoyage_silver.docx) pour le détail des difficultés rencontrées et solutions

## 👥 Équipe — Groupe 6

Répartition des tâches :
- Setup infrastructure + zone Bronze
- Zone Silver (nettoyage)
- Zone Silver (formats) → Zone Gold
- Zone Gold + DuckDB
- Dashboard Power BI + documentation
- Présentation finale
