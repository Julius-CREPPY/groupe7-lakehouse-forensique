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
- **Fichiers utilisés** : `auth.txt.gz` (logs d'authentification, 7,6 Go) et `redteam.txt.gz` (événements de compromission connus, vérité terrain)
- Schéma détaillé : voir [`documentation_schema.md`](./documentation_schema.md)

## 🚀 Installation

### Pré-requis
- R + RStudio
- Packages R : `aws.s3`, `duckdb`, `httr`
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
   install.packages(c("aws.s3", "duckdb", "httr"))
   ```

## 📁 Structure du projet

```
groupe6-lakehouse-forensique/
├── README.md                    # Ce fichier
├── documentation_schema.md      # Documentation du schéma des données
├── 01_upload_bronze.R           # Script d'ingestion vers la zone Bronze
├── .gitignore                   # Exclut .Renviron et data/
└── data/                        # Fichiers locaux (non versionnés)
```

## 📈 État d'avancement

| Semaine | Tâche | Statut |
|---|---|---|
| 1 | Mise en place S3 (bucket + 3 zones) | ✅ Terminé |
| 1 | Ingestion des données brutes vers Bronze | ✅ Terminé |
| 1 | Exploration et documentation du schéma | ✅ Terminé |
| 2 | Nettoyage et typage — zone Silver | 🔜 À venir |
| 3 | Agrégations et requêtes DuckDB — zone Gold | 🔜 À venir |
| 4 | Dashboard Power BI | 🔜 À venir |
| 5 | Finalisation, tests, documentation | 🔜 À venir |

**Dernière mise à jour** : Semaine 1 complétée — `auth.txt.gz` (7,1 Go) et `redteam.txt.gz` uploadés avec succès vers `s3://groupe06-lakehouse-forensique/bronze/`.

## 👥 Équipe — Groupe 6

Répartition des tâches :
- Setup infrastructure + zone Bronze
- Zone Silver (nettoyage)
- Zone Silver (formats) → Zone Gold
- Zone Gold + DuckDB
- Dashboard Power BI + documentation
- Présentation finale
