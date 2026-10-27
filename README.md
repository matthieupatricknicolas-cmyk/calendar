# Calendrier 2026

Carte mobile des points de distribution par tournée (Leaflet + OpenStreetMap), données et statuts dans Supabase.

- `index.html` : l'application (hébergée sur GitHub Pages)
- `data/points.json` : données sources (fid, numéro, suffixe, voie, commune, tournée, lon, lat), converties en WGS84

Statuts : à faire / fait / repassé / refus. Connexion par lien magique (e-mail). Le premier utilisateur connecté devient administrateur ; il affecte ensuite les agents aux tournées via le bouton 👥.
Un agent ne voit que les points de ses tournées (règles RLS côté Supabase).
