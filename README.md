# Groupe 7 — Architecture Lakehouse pour la forensique numérique

Projet réalisé dans le cadre du Master 1 Cycle Ingénieur Cybersécurité — Semestre 2 (Data Engineering).

## 🎯 Objectif du projet

Construire une architecture **Lakehouse** (Bronze / Silver / Gold) sur AWS S3 pour stocker et analyser des logs de sécurité réels, en garantissant l'intégrité légale des données brutes tout en offrant des données exploitables et interrogeables rapidement en SQL — un besoin central en **forensique numérique**.

Le pipeline s'appuie sur le dataset **LANL Comprehensive Multi-Source Cyber-Security Events** (Los Alamos National Laboratory), et livre un dashboard Power BI capable de détecter des anomalies (connexions à horaires inhabituels, diversité anormale des machines accédées).

## 🏗️ Architecture

```
                ┌─────────────┐      ┌─────────────┐      ┌─────────────┐
  Dataset LANL  │   BRONZE    │      │   SILVER    │      │    GOLD     │      Dashboard
  (auth, ─────► │ Données     │ ───► │ Données     │ ───► │ 8 tables    │ ───► Power BI
   redteam)     │ brutes,     │      │ nettoyées,  │      │ agrégées    │      (connexion
                │ intactes    │      │ typées      │      │             │       directe S3)
                │             │      │ (Parquet)   │      │ (Parquet)   │
                └─────────────┘      └─────────────┘      └─────────────┘
                      S3                   S3                   S3
                                            │                    │
                                      Requêtes SQL DuckDB (directement sur S3)
```

- **Bronze** : données brutes du dataset LANL, jamais modifiées (préservation de l'intégrité légale des preuves)
- **Silver** : données nettoyées, typées, converties au format Parquet
- **Gold** : 8 tables agrégées répondant chacune à une question forensique précise

## 🛠️ Stack technique

| Outil | Rôle |
|---|---|
| **AWS S3** | Stockage des 3 zones (Bronze/Silver/Gold) |
| **R** (`aws.s3`) | Ingestion et transformation des données |
| **DuckDB** | Requêtage SQL des fichiers Parquet directement sur S3 |
| **Power BI** | Dashboard final, connecté directement à S3 (URL pré-signées + Power Query) |
| **Git/GitHub** | Versioning du code |

## 📊 Dataset

- **Source** : [csr.lanl.gov/data/cyber1](https://csr.lanl.gov/data/cyber1/)
- **Fichiers utilisés** : `auth.txt.gz` (1 051 430 459 lignes) et `redteam.txt.gz` (vérité terrain, 992 événements d'attaque connus)
- Schéma détaillé : [`documentation_schema.md`](./documentation_schema.md)
- Diagnostic qualité Bronze : [`rapport_diagnostic_bronze.docx`](./rapport_diagnostic_bronze.docx)
- Nettoyage Silver : [`rapport_nettoyage_silver.docx`](./rapport_nettoyage_silver.docx)
- Agrégations et validation Gold : [`rapport_gold.docx`](./rapport_gold.docx)
- **Synthèse complète du projet (pour toute l'équipe)** : [`synthese_complete_projet.docx`](./synthese_complete_projet.docx)

## 🚀 Installation

### Pré-requis
- R + RStudio
- Packages R : `aws.s3`, `duckdb`, `DBI`, `httr`
- Un accès au bucket AWS S3 du groupe (demander les identifiants au responsable infrastructure)
- Power BI Desktop (pour ouvrir/modifier le dashboard)

### Configuration
1. Cloner ce dépôt :
   ```bash
   git clone https://github.com/Julius-CREPPY/groupe6-lakehouse-forensique.git
   ```
2. Créer un fichier `.Renviron` à la racine du projet (non versionné, voir `.gitignore`) avec vos identifiants AWS personnels :
   ```
   AWS_ACCESS_KEY_ID=votre_access_key_id
   AWS_SECRET_ACCESS_KEY=votre_secret_access_key
   AWS_DEFAULT_REGION=eu-north-1
   ```
3. Installer les dépendances R :
   ```r
   install.packages(c("aws.s3", "duckdb", "DBI", "httr"))
   ```

⚠️ **Ne jamais commiter de clés AWS ou le fichier `.Renviron`** — déjà exclu par `.gitignore`, à vérifier avec `git status` avant chaque commit.

## 📁 Structure du projet

```
groupe6-lakehouse-forensique/
├── README.md                          # Ce fichier
├── documentation_schema.md            # Documentation du schéma des données brutes
├── rapport_diagnostic_bronze.docx     # Diagnostic qualité (Semaine 1)
├── rapport_nettoyage_silver.docx      # Nettoyage + difficultés rencontrées (Semaine 2)
├── rapport_gold.docx                  # Agrégations + validation croisée redteam (Semaine 3)
├── synthese_complete_projet.docx      # Synthèse complète pour toute l'équipe
├── code.R                             # Script d'ingestion vers la zone Bronze
├── 02_nettoyage_silver.R              # Script de nettoyage -> zone Silver
├── 03_gold_agregations.R              # Script des 8 tables Gold
├── 04_comparaison_criteres.R          # Comparaison des critères de détection
├── dashboard_forensique_groupe6.pbix  # Dashboard Power BI final
├── .gitignore                         # Exclut .Renviron et data/
└── data/                              # Fichiers locaux (non versionnés)
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
| 3 | 8 tables d'agrégation — zone Gold | ✅ Terminé |
| 3 | Validation croisée avec redteam.txt.gz | ✅ Terminé |
| 4 | Connexion Power BI directe aux données Gold (S3) | ✅ Terminé |
| 4 | Dashboard (5 visualisations) | ✅ Terminé |
| 5 | Finalisation, 🔜 En cours |

**Dernière mise à jour** : Semaine 4 complétée — dashboard Power BI opérationnel avec 5 visualisations (top machines, évolution temporelle, top utilisateurs, activité par heure, efficacité des critères de détection), connecté directement aux tables Gold sur S3.

### Résultat clé du projet
La comparaison de plusieurs critères de détection d'anomalies contre les 992 attaques connues du dataset a montré que la **diversité des machines accédées par utilisateur** est le signal le plus efficace (90,73 % de détection), loin devant le critère horaire seul (4,23 %). Combinés, les critères détectent 91,63 % des attaques connues. Détail complet dans [`rapport_gold.docx`](./rapport_gold.docx).

## 👥 Équipe — Groupe 6

Répartition des tâches :
- Setup infrastructure + zone Bronze
- Zone Silver (nettoyage)
- Zone Silver (formats) → Zone Gold
- Zone Gold + DuckDB
- Dashboard Power BI + documentation
- Présentation finale

### Pour rejoindre le projet
1. Accepter l'invitation GitHub reçue par email
2. Cloner le dépôt (voir Installation ci-dessus)
3. Lire ce README puis [`synthese_complete_projet.docx`](./synthese_complete_projet.docx) pour une vue d'ensemble complète
4. **Toujours faire `git pull` avant de commencer à travailler**, pour récupérer le travail des autres membres

## 📅 Prochaine étape

Soutenance dans 2 jours — finalisation de la présentation, répétition, vérification que le pipeline fonctionne de bout en bout pour la démo live.
