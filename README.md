# Calendo – suivi des tournées de calendriers

Application web mobile (PWA) pour suivre en temps réel les tournées de calendriers d'une amicale de sapeurs-pompiers : chaque binôme voit ses adresses sur une carte, note son passage, enregistre ses ventes ; l'administrateur suit l'avancement global. Tout le monde voit les mêmes données, mises à jour en direct.

Conçue pour l'amicale de Voiteur-Domblans (Jura), elle est **réutilisable par une autre caserne** : voir [Adapter Calendo pour une autre caserne](#adapter-calendo-pour-une-autre-caserne).

## Fonctionnalités

**Pour les binômes**
- Carte OpenStreetMap ou vue aérienne IGN ; un point par adresse, coloré selon son statut, numéro de rue affiché en zoomant ; regroupement par tournée en vue éloignée.
- Statuts : *À faire*, *Fait*, *Partiellement fait*, *Repasse*, *Refus* (champ de précisions libre, 300 caractères, pour *Partiellement fait* et *Repasse*).
- Ventes multiples par adresse (montant + espèces / chèque / CB), suppression possible.
- Ajout d'une adresse manquante (bouton bleu ＋) avec détection des doublons.
- Position GPS, recherche d'adresse, tableau de bord de la tournée.
- Installable sur l'écran d'accueil ; saisie possible hors connexion (file d'attente envoyée au retour du réseau).
- Un binôme ne modifie que ses tournées ; les autres sont en lecture seule.

**Pour l'administrateur (menu 👥)**
- Affectation des tournées aux binômes (et répartition automatique), création / renommage / suppression de tournées.
- Gestion des adresses : affecter des points à une tournée, déplacer ou supprimer un point.
- Statistiques globales par tournée et par commune.
- Historique des connexions (200 dernières) et utilisateurs connectés en direct.
- **Remise à zéro de la saison** : tous les points repassent à *À faire* et les ventes sont supprimées, **les affectations binômes/tournées sont conservées** ; archivage préalable proposé (conservé en base, export .xlsx).

## Architecture

```
GitHub Pages (fichiers statiques)  ──HTTPS──►  Supabase
 index.html  (toute l'application)             ├─ Auth (email + mot de passe)
 sw.js       (cache hors connexion)            ├─ Postgres + RLS (droits par ligne)
 manifest.webmanifest + icônes (PWA)           ├─ Fonctions RPC (toute écriture)
                                               └─ Realtime (points, ventes, présence)
```

- **Front** : un seul fichier `index.html` (JavaScript sans build), Leaflet 1.9.4, supabase-js 2, SheetJS (export, chargé à la demande). Aucun serveur à maintenir.
- **Back** : Supabase. Les lecteurs passent par RLS ; **toute écriture passe par des fonctions `security definer`** qui vérifient le rôle et la tournée du compte (`supabase/schema.sql`).
- **Comptes** : identifiants simples (`binome1`…, `admin`) transformés en email technique `…@calendrier.local` (constante `DOM` dans `index.html`). Aucun email réel n'est envoyé.
- La clé `sb_publishable_…` présente dans `index.html` est publique par conception : la sécurité repose sur la RLS, jamais sur le secret de cette clé. **Ne mettez jamais la clé `service_role` dans le dépôt.**

### Contenu du dépôt

| Fichier | Rôle |
|---|---|
| `index.html` | Application complète (HTML, CSS, JS) et métadonnées |
| `sw.js` | Service worker : cache de l'application, réseau prioritaire |
| `manifest.webmanifest`, `icon-*.png`, `apple-touch-icon.png` | Installation sur mobile |
| `logo.png`, `bg-login.jpg` | Logo et photo de fond de l'écran de connexion |
| `supabase/schema.sql` | **Modèle de base** : tables, contraintes, index, fonctions, RLS, temps réel |
| `supabase/comments.sql` | Descriptions des tables, colonnes et fonctions (visibles dans Supabase) |
| `supabase/comptes.sql` | Création des comptes binômes et administrateur (mots de passe à renseigner) |
| `data/points.json` | Jeu d'adresses initial de Voiteur-Domblans (tableaux `[fid, numero, suffixe, nom_voie, nom_commune, tournee, lon, lat]`) |
| `data/modele_points.csv` | Modèle de fichier d'adresses à remplir pour une autre caserne |
| `data/importer_points.py` | Convertit un CSV ou GeoJSON en SQL d'import |

### Modèle de données (résumé)

| Table | Contenu |
|---|---|
| `tournees` | Liste des tournées (clé : nom) |
| `utilisateurs` | Comptes et rôle (`admin` / `agent`), alimentée par un trigger à la création du compte |
| `membres` | Affectation binôme ↔ tournée |
| `points` | Adresses : voie, commune, tournée, statut, date, coordonnées, commentaire, dernier auteur |
| `ventes` | Ventes (montant < 10 000 €, mode de paiement, jour, auteur) |
| `historique` | Journal des changements de statut |
| `connexions` | 200 dernières connexions |
| `archives`, `archives_points`, `archives_ventes` | Saisons archivées lors des remises à zéro |

Les descriptions détaillées de chaque colonne et fonction sont dans `supabase/comments.sql` (et dans l'interface Supabase).

## Installation depuis zéro

Prérequis : un compte GitHub et un compte Supabase (offres gratuites suffisantes pour ~20 utilisateurs simultanés).

1. **Dépôt** : forkez ou copiez ce dépôt dans votre compte GitHub.
2. **Projet Supabase** : créez un projet (région proche, ex. Paris/Francfort). Notez l'URL du projet et la clé *publishable* (Project Settings → API Keys).
3. **Authentification** : Authentication → Providers → Email : laissez *Email* activé, **désactivez « Confirm email »** (les comptes utilisent des emails techniques) et désactivez les inscriptions libres (*Allow new users to sign up*) si vous créez tous les comptes vous-même.
4. **Base** : SQL Editor → collez et exécutez `supabase/schema.sql`, puis `supabase/comments.sql`.
5. **Adresses** : préparez vos données (voir ci-dessous), puis exécutez le SQL généré.
6. **Comptes** : éditez les 3 paramètres en tête de `supabase/comptes.sql` (mots de passe, nombre de binômes) et exécutez-le dans le SQL Editor.
7. **Configuration de l'application** : dans `index.html`, remplacez l'URL et la clé de la ligne `const SB = supabase.createClient("…", "…")`.
8. **Publication** : Settings → Pages du dépôt → *Deploy from a branch* → `main` / racine. L'application est servie sur `https://<compte>.github.io/<dépôt>/`.
9. **Premier accès** : connectez-vous avec `admin` ; le menu 👥 permet de répartir les tournées. Après chaque mise à jour du dépôt, rechargez la page (le service worker prend en compte la nouvelle version).

## Adapter Calendo pour une autre caserne

### 1. Vos adresses et vos tournées
- Remplissez une copie de `data/modele_points.csv` (séparateur `;`) : une ligne par adresse, colonnes `numero;suffixe;nom_voie;nom_commune;tournee;lon;lat`. La tournée peut rester vide (adresse non affectée). Coordonnées en WGS84 (longitude, latitude).
- Sources possibles : la [Base Adresse Nationale](https://adresse.data.gouv.fr/data/ban/adresses/latest/csv) (par département), un export QGIS/uMap en GeoJSON, ou vos listes existantes géocodées.
- Générez le SQL : `python3 data/importer_points.py mes_adresses.csv > import.sql` (CSV ou `.geojson`), puis exécutez `import.sql` dans le SQL Editor. L'attribution des adresses aux tournées peut aussi se faire ensuite dans l'application (menu 👥 → Adresses).

### 2. Vos comptes
- `supabase/comptes.sql` crée `admin` et `binome1…binomeN`. Pour d'autres identifiants (noms de véhicules, équipes…), adaptez la boucle ; l'identifiant saisi dans l'application est complété par `@calendrier.local`.
- Changer de domaine technique : modifiez à la fois `const DOM` dans `index.html` et les occurrences de `@calendrier.local` dans `supabase/schema.sql` (fonction `affecter_tournee`) et `comptes.sql`.
- Choisissez des mots de passe forts avant toute utilisation réelle ; ne les écrivez pas dans le dépôt.

### 3. Identité visuelle
- `logo.png` (carré, fond transparent ou blanc) et `icon-192.png`, `icon-512.png`, `icon-maskable-512.png`, `apple-touch-icon.png` (icônes d'installation, la maskable doit laisser ~20 % de marge).
- `bg-login.jpg` : photo de fond de l'écran de connexion (idéalement < 300 Ko).
- Nom : modifiez `<title>`, les balises `<meta>` (description, `og:*`, `author`, `apple-mobile-web-app-title`) dans `index.html`, `name`, `short_name`, `description` dans `manifest.webmanifest`, et le texte alternatif du logo.
- Couleurs : `theme_color` / `background_color` du manifeste et la balise `theme-color`.
- Si vous modifiez des fichiers de l'application, **incrémentez `V`** dans `sw.js` (ex. `calendo-v4`) pour forcer le rafraîchissement du cache.

### 4. Zone géographique
- Centre de départ de la carte : `map.setView([46.77, 5.62], 13)` dans `index.html` (latitude, longitude, zoom).
- Emprise acceptée à la création/déplacement d'une adresse : France métropolitaine (lat 41–52, lon −6–10), contrôlée dans `creer_adresse` et `deplacer_point` du `schema.sql` ; à élargir pour l'outre-mer.
- La recherche d'adresse utilise la géocodeur national (Géoplateforme IGN), valable pour toute la France.

### 5. Règles de gestion à ajuster si besoin
- Plafond d'une vente : `check (montant > 0 and montant < 10000)` (table `ventes`, fonction `ajouter_vente`).
- Modes de paiement : `espèces / chèque / CB` (contrainte de `ventes` et fonction `ajouter_vente`, libellés dans `index.html`).
- Statuts : tableau `ST` dans `index.html` + contrainte `points_statut_check` + `set_statut`.
- Historique de connexions : 200 lignes (`noter_connexion`).

### 6. Vérifier avant la mise en service
- Dans Supabase → Advisors : aucun avertissement de sécurité (RLS actif sur toutes les tables, fonctions non exécutables par `anon`).
- Connectez-vous avec un binôme : il ne doit voir et modifier que ses tournées ; avec `admin` : tout.
- Faites une remise à zéro d'essai *avec archivage* sur des données de test avant la campagne, puis vérifiez que les affectations sont conservées.

## Exploitation

- **Sauvegarde** : Supabase → Database → Backups (selon l'offre) ou `pg_dump` ; l'archivage de saison + export .xlsx sert de sauvegarde métier.
- **Mises à jour de l'application** : modifier les fichiers, commit/push sur `main`, recharger la page sur les téléphones.
- **Modifier le modèle de base** : appliquez la migration sur Supabase puis reportez-la dans `supabase/schema.sql` pour garder le dépôt à jour.
- **Confidentialité** : les données sont des adresses et des ventes ; n'exposez pas l'interface d'administration aux simples binômes (réservée au rôle `admin`), et supprimez les comptes inutilisés après la campagne.

## Licence et données

Fond de carte © contributeurs OpenStreetMap ; vue aérienne © IGN (Géoplateforme) ; adresses de base : Base Adresse Nationale (Licence Ouverte).
