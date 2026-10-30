# Calendo

Suivi partagé des tournées de calendriers : carte mobile (Leaflet, fonds OpenStreetMap ou vue aérienne IGN), statuts, ventes et tableau de bord en temps réel. Installable sur mobile (PWA).

- `index.html` : l'application (GitHub Pages) ; `sw.js` + `manifest.webmanifest` + icônes : installation et cache hors-ligne
- `data/points.json` : données sources (fid, numéro, suffixe, voie, commune, tournée, lon, lat)
- Back end : Supabase (Postgres + RLS + fonctions RPC + temps réel)

Statuts : À faire / Fait / Partiellement fait / Repasse / Refus (précisions libres pour les deux derniers cas partiel/repasse).
Connexion par identifiant (`binome1` à `binome20`) et mot de passe ; compte `admin` pour l'administration.
Chaque binôme modifie uniquement ses tournées ; les autres sont visibles en lecture seule.
Administration (👥) : affectation des tournées, gestion des tournées et des adresses, historique des connexions.
