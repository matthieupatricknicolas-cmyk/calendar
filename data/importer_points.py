#!/usr/bin/env python3
"""Convertit un fichier d'adresses en SQL d'import pour Calendo.

Entrées acceptées : CSV (séparateur « ; », colonnes de data/modele_points.csv)
ou GeoJSON (Point, propriétés numero, suffixe, nom_voie, nom_commune, tournee ;
alias BAN acceptés : rep, nom_voie, nom_commune, tournee/TOURNEE/NOM).

Usage : python3 data/importer_points.py mes_adresses.csv > import.sql
Collez ensuite import.sql dans Supabase > SQL Editor (découpez si > 1 Mo).
"""
import csv, json, sys

def q(v):
    return "null" if v in (None, "") else "'" + str(v).replace("'", "''") + "'"

def n(v):
    return "null" if v in (None, "") else str(int(float(v)))

def lire(path):
    if path.lower().endswith((".geojson", ".json")):
        for i, f in enumerate(json.load(open(path, encoding="utf-8"))["features"]):
            p, (lon, lat) = f["properties"], f["geometry"]["coordinates"][:2]
            g = lambda *k: next((p[x] for x in k if p.get(x) not in (None, "")), None)
            yield dict(fid=g("fid", "id") or i, numero=g("numero"), suffixe=g("suffixe", "rep"),
                       nom_voie=g("nom_voie"), nom_commune=g("nom_commune"),
                       tournee=g("tournee", "TOURNEE", "NOM"), lon=lon, lat=lat)
    else:
        for i, r in enumerate(csv.DictReader(open(path, encoding="utf-8-sig"), delimiter=";")):
            r["fid"] = i + 1
            yield r

rows = list(lire(sys.argv[1]))
tournees = sorted({r["tournee"] for r in rows if r.get("tournee")})
print("-- Tournées")
for t in tournees:
    print(f"insert into public.tournees (nom) values ({q(t)}) on conflict do nothing;")
print("-- Adresses")
print("insert into public.points (fid, numero, suffixe, nom_voie, nom_commune, tournee, lon, lat) values")
print(",\n".join(
    f"({n(r.get('fid'))},{n(r.get('numero'))},{q(r.get('suffixe'))},{q(r.get('nom_voie'))},"
    f"{q(r.get('nom_commune'))},{q(r.get('tournee'))},{float(r['lon'])},{float(r['lat'])})" for r in rows) + ";")
