# Documentation du schéma — Zone Bronze
### Groupe 6 — Architecture Lakehouse pour la forensique numérique
### Dataset source : LANL Comprehensive Multi-Source Cyber-Security Events (Los Alamos National Laboratory)

---

## 1. Origine des données

- **Source officielle** : https://csr.lanl.gov/data/cyber1/
- **Description générale** : 58 jours consécutifs de logs d'événements réels, dé-identifiés, collectés sur le réseau interne d'entreprise du Los Alamos National Laboratory.
- **Citation requise (si publication)** :
  > A. D. Kent, "Cybersecurity Data Sources for Dynamic Network Research," in Dynamic Networks in Cybersecurity, 2015.
- **Licence** : CC0 (domaine public)

## 2. Fichiers utilisés pour ce projet

| Fichier | Contenu | Taille compressée | Utilisé ? |
|---|---|---|---|
| `auth.txt.gz` | Événements d'authentification (connexions) | 7,6 Go | ✅ Oui — fichier principal |
| `redteam.txt.gz` | Événements de compromission connus (vérité terrain) | 4,8 Ko | ✅ Oui — validation des anomalies |
| `proc.txt.gz` | Démarrage/arrêt de processus | 2,2 Go | ❌ Non retenu (hors périmètre du TP) |
| `flows.txt.gz` | Flux réseau | 1,1 Go | ❌ Non retenu |
| `dns.txt.gz` | Résolutions DNS | 177 Mo | ❌ Non retenu |

## 3. Schéma détaillé — `auth.txt.gz`

Chaque ligne représente un événement d'authentification, au format CSV (valeurs séparées par des virgules, sans en-tête).

| # | Colonne | Description | Type prévu (zone Silver) | Exemple |
|---|---|---|---|---|
| 1 | `time` | Temps écoulé **en secondes depuis le début de la capture** (epoch=1). Ce n'est **pas** une heure d'horloge réelle. | Entier (integer / bigint) | `1` |
| 2 | `source_user_domain` | Compte utilisateur/machine à l'origine de la connexion, format `user@domain` | Texte (character) | `C625$@DOM1` |
| 3 | `destination_user_domain` | Compte utilisateur/machine visé par la connexion | Texte (character) | `U147@DOM1` |
| 4 | `source_computer` | Machine source | Texte (character) | `C625` |
| 5 | `destination_computer` | Machine de destination | Texte (character) | `C625` |
| 6 | `authentication_type` | Type d'authentification (ex : Negotiate, Kerberos, NTLM) | Facteur / catégorie | `Negotiate` |
| 7 | `logon_type` | Type de connexion (ex : Batch, Service, Network, Interactive) | Facteur / catégorie | `Batch` |
| 8 | `authentication_orientation` | Sens de l'authentification (LogOn / LogOff) | Facteur / catégorie | `LogOn` |
| 9 | `success_failure` | Résultat de la tentative | Facteur / booléen | `Success` |

**Valeurs manquantes** : représentées par un point d'interrogation (`?`) dans les données brutes — à convertir en `NA` lors du nettoyage Silver.

**Particularité importante** : les événements d'échec d'authentification ne sont inclus dans le dataset que pour des utilisateurs ayant eu au moins une connexion réussie ailleurs dans le jeu de données (biais à noter dans l'analyse).

### Exemple de lignes brutes
```
1,C625$@DOM1,U147@DOM1,C625,C625,Negotiate,Batch,LogOn,Success
1,C653$@DOM1,SYSTEM@C653,C653,C653,Negotiate,Service,LogOn,Success
1,C660$@DOM1,SYSTEM@C660,C660,C660,Negotiate,Service,LogOn,Success
```

## 4. Schéma détaillé — `redteam.txt.gz`

Sous-ensemble de `auth.txt.gz` correspondant aux événements de compromission connus (attaques simulées par l'équipe "red team"). Sert de **vérité terrain** pour valider les détections d'anomalies en zone Gold.

| # | Colonne | Description | Exemple |
|---|---|---|---|
| 1 | `time` | Temps en secondes (même référentiel que `auth.txt.gz`) | `151648` |
| 2 | `user_domain` | Compte compromis, format `user@domain` | `U748@DOM1` |
| 3 | `source_computer` | Machine source de l'attaque | `C17693` |
| 4 | `destination_computer` | Machine ciblée | `C728` |

### Exemple de lignes brutes
```
151648,U748@DOM1,C17693,C728
151993,U6115@DOM1,C17693,C1173
153792,U636@DOM1,C17693,C294
```

## 5. Transformation critique à prévoir en zone Silver

La colonne `time` est un **compteur de secondes**, pas une heure de la journée. Pour l'analyse forensique demandée par le TP (détection de connexions à des horaires inhabituels), il faut calculer l'heure du jour à partir de ce compteur :

```r
heure_du_jour <- (time %% 86400) / 3600
# 86400 = nombre de secondes dans une journée
# 3600  = nombre de secondes dans une heure
# Résultat : une valeur entre 0 et 24
```

⚠️ **Limite connue** : cette conversion suppose que le compteur démarre à minuit (heure 0). Ce n'est pas garanti par la documentation officielle — cette hypothèse doit être mentionnée comme limite de l'analyse dans le rapport final.

## 6. Volumétrie observée

- `auth.txt.gz` : **7,6 Go** compressé
- `redteam.txt.gz` : **4,8 Ko** compressé
- Nombre total d'événements dans le dataset complet (les 5 fichiers) : 1 648 275 307, pour 12 425 utilisateurs et 17 684 machines (source : documentation officielle LANL)

## 7. Zone Bronze — état actuel

- [x] `redteam.txt.gz` uploadé vers `s3://groupe06-lakehouse-forensique/bronze/redteam.txt.gz`
- [x] `auth.txt.gz` en cours d'upload vers `s3://groupe06-lakehouse-forensique/bronze/auth.txt.gz` (upload via console AWS suite à un blocage réseau contourné avec VPN)
- Aucune transformation appliquée à ce stade — fichiers strictement identiques à la source, conformément au principe de la zone Bronze (préservation de l'intégrité légale des données)

---

*Document à mettre à jour au fur et à mesure de l'avancement (zones Silver et Gold).*
