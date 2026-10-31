-- =====================================================================
-- Calendo – modèle de base de données (Supabase / PostgreSQL)
-- Reflète exactement la base installée. À exécuter UNE FOIS dans
-- Supabase > SQL Editor sur un projet neuf (puis comments.sql, puis
-- les données : data/ et supabase/comptes.sql).
-- =====================================================================

-- ---------- Tables ----------

create table public.tournees (
  nom text primary key
);

create table public.utilisateurs (
  email text primary key,
  role  text not null default 'agent' check (role in ('admin','agent'))
);

create table public.membres (
  email   text not null,
  tournee text not null references public.tournees(nom) on update cascade on delete cascade,
  primary key (email, tournee)
);

create table public.points (
  id          bigint generated always as identity primary key,
  fid         integer,
  numero      integer,
  suffixe     text,
  nom_voie    text,
  nom_commune text,
  tournee     text references public.tournees(nom) on update cascade on delete set null,
  statut      text not null default 'a_faire'
              constraint points_statut_check check (statut in ('a_faire','fait','partiel','repasse','refus')),
  date_passage date,
  lon         double precision not null,
  lat         double precision not null,
  maj_par     text,
  maj_le      timestamptz,
  commentaire text constraint points_commentaire_len check (commentaire is null or length(commentaire) <= 300)
);
create index points_tournee_idx on public.points (tournee);

create table public.historique (
  id       bigint generated always as identity primary key,
  point_id bigint not null references public.points(id) on delete cascade,
  email    text,
  ancien   text,
  nouveau  text,
  le       timestamptz not null default now()
);

create table public.ventes (
  id       uuid primary key default gen_random_uuid(),
  point_id bigint not null references public.points(id) on delete cascade,
  montant  numeric(8,2) not null check (montant > 0 and montant < 10000),
  mode     text not null check (mode in ('especes','cheque','cb')),
  jour     date not null,
  par      text,
  cree_le  timestamptz not null default now()
);
create index ventes_jour_idx  on public.ventes (jour);
create index ventes_point_idx on public.ventes (point_id);

create table public.connexions (
  id    bigint generated always as identity primary key,
  email text not null,
  le    timestamptz not null default now(),
  ua    text
);
create index connexions_le_idx on public.connexions (le desc);

create table public.archives (
  id         bigint generated always as identity primary key,
  nom        text not null check (length(btrim(nom)) between 1 and 80),
  cree_le    timestamptz not null default now(),
  cree_par   text,
  nb_points  integer not null default 0,
  nb_traites integer not null default 0,
  nb_ventes  integer not null default 0,
  total      numeric(12,2) not null default 0
);

create table public.archives_points (
  archive_id  bigint not null references public.archives(id) on delete cascade,
  point_id    bigint,
  fid         bigint,
  numero      integer,
  suffixe     text,
  nom_voie    text,
  nom_commune text,
  tournee     text,
  binome      text,
  statut      text,
  commentaire text,
  date_passage date,
  maj_par     text,
  maj_le      timestamptz,
  lat         double precision,
  lon         double precision
);
create index archives_points_a_idx on public.archives_points (archive_id);

create table public.archives_ventes (
  archive_id bigint not null references public.archives(id) on delete cascade,
  vente_id   uuid,
  point_id   bigint,
  montant    numeric(8,2),
  mode       text,
  jour       date,
  par        text,
  cree_le    timestamptz,
  tournee    text,
  commune    text,
  adresse    text
);
create index archives_ventes_a_idx on public.archives_ventes (archive_id);

-- ---------- Fonctions utilitaires (utilisées par les politiques RLS) ----------

create or replace function public.mon_email() returns text
language sql stable set search_path to ''
as $$ select lower(auth.jwt() ->> 'email') $$;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path to ''
as $$ select exists (select 1 from public.utilisateurs where email = lower(auth.jwt() ->> 'email') and role = 'admin') $$;

create or replace function public.est_actif() returns boolean
language sql stable security definer set search_path to ''
as $$ select public.is_admin() or exists (select 1 from public.membres where email = lower(auth.jwt() ->> 'email')) $$;

create or replace function public.mes_tournees() returns setof text
language sql stable security definer set search_path to ''
as $$ select tournee from public.membres where email = lower(auth.jwt() ->> 'email') $$;

-- ---------- Fonctions métier (appelées en RPC par l'application) ----------

create or replace function public.claim_admin() returns boolean
language plpgsql security definer set search_path to ''
as $$
declare e text := lower(auth.jwt() ->> 'email');
begin
  if e is null then return false; end if;
  if exists (select 1 from public.utilisateurs where role = 'admin') then
    return public.is_admin();
  end if;
  insert into public.utilisateurs (email, role) values (e, 'admin')
    on conflict (email) do update set role = 'admin';
  return true;
end $$;

create or replace function public.on_new_user() returns trigger
language plpgsql security definer set search_path to ''
as $$
begin
  if new.email is not null then
    insert into public.utilisateurs (email, role) values (lower(new.email), 'agent') on conflict (email) do nothing;
  end if;
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.on_new_user();

create or replace function public.noter_connexion(p_ua text) returns void
language plpgsql security definer set search_path to ''
as $$
declare e text := lower(auth.jwt() ->> 'email');
begin
  if e is null or e = '' then return; end if;
  if exists (select 1 from public.connexions where email = e and le > now() - interval '5 minutes') then return; end if;
  insert into public.connexions (email, le, ua) values (e, now(), left(p_ua, 300));
  -- on ne conserve que les 200 connexions les plus récentes
  delete from public.connexions
   where id in (select id from public.connexions order by le desc, id desc offset 200);
end $$;

create or replace function public.set_statut(p_id bigint, p_statut text) returns void
language plpgsql security definer set search_path to ''
as $$
declare e text := lower(auth.jwt() ->> 'email'); old text; t text;
  jour date := (now() at time zone 'Europe/Paris')::date;
begin
  if p_statut not in ('a_faire','fait','partiel','repasse','refus') then raise exception 'statut invalide'; end if;
  select statut, tournee into old, t from public.points where id = p_id;
  if not found then raise exception 'point introuvable'; end if;
  if not (public.is_admin() or t in (select public.mes_tournees())) then raise exception 'acces refuse'; end if;
  update public.points
     set statut = p_statut, date_passage = jour, maj_par = e, maj_le = now(),
         commentaire = case when p_statut in ('partiel','repasse') then commentaire else null end
   where id = p_id;
  insert into public.historique (point_id, email, ancien, nouveau) values (p_id, e, old, p_statut);
end $$;

create or replace function public.set_commentaire(p_id bigint, p_texte text) returns void
language plpgsql security definer set search_path to ''
as $$
declare e text := lower(auth.jwt() ->> 'email'); t text;
begin
  select tournee into t from public.points where id = p_id;
  if not found then raise exception 'point introuvable'; end if;
  if not (public.is_admin() or t in (select public.mes_tournees())) then raise exception 'acces refuse'; end if;
  update public.points
     set commentaire = nullif(left(btrim(coalesce(p_texte, '')), 300), ''), maj_par = e, maj_le = now()
   where id = p_id;
end $$;

create or replace function public.ajouter_vente(p_id uuid, p_point bigint, p_montant numeric, p_mode text) returns void
language plpgsql security definer set search_path to ''
as $$
declare e text := lower(auth.jwt() ->> 'email'); old text; t text;
  jour date := (now() at time zone 'Europe/Paris')::date;
begin
  if p_mode not in ('especes','cheque','cb') then raise exception 'mode de paiement invalide'; end if;
  if p_montant is null or p_montant <= 0 or p_montant >= 10000 then raise exception 'montant invalide'; end if;
  select statut, tournee into old, t from public.points where id = p_point;
  if not found then raise exception 'point introuvable'; end if;
  if not (public.is_admin() or t in (select public.mes_tournees())) then raise exception 'acces refuse'; end if;
  insert into public.ventes (id, point_id, montant, mode, jour, par) values (p_id, p_point, round(p_montant, 2), p_mode, jour, e)
    on conflict (id) do nothing;
  if old <> 'partiel' then
    update public.points set statut = 'fait', date_passage = jour, maj_par = e, maj_le = now(), commentaire = null where id = p_point;
    if old <> 'fait' then
      insert into public.historique (point_id, email, ancien, nouveau) values (p_point, e, old, 'fait');
    end if;
  else
    update public.points set date_passage = jour, maj_par = e, maj_le = now() where id = p_point;
  end if;
end $$;

create or replace function public.supprimer_vente(p_id uuid) returns void
language plpgsql security definer set search_path to ''
as $$
declare t text;
begin
  select p.tournee into t from public.ventes v join public.points p on p.id = v.point_id where v.id = p_id;
  if not found then return; end if;
  if not (public.is_admin() or t in (select public.mes_tournees())) then raise exception 'acces refuse'; end if;
  delete from public.ventes where id = p_id;
end $$;

create or replace function public.creer_adresse(p_numero integer, p_suffixe text, p_voie text, p_commune text, p_tournee text, p_lon double precision, p_lat double precision)
returns public.points
language plpgsql security definer set search_path to ''
as $$
declare r public.points;
begin
  if not (public.is_admin() or (p_tournee is not null and p_tournee in (select public.mes_tournees()))) then
    raise exception 'acces refuse : choisissez une de vos tournees';
  end if;
  if btrim(coalesce(p_voie, '')) = '' or btrim(coalesce(p_commune, '')) = '' then raise exception 'voie et commune obligatoires'; end if;
  if length(p_voie) > 120 or length(p_commune) > 80 or length(coalesce(p_suffixe, '')) > 10 then raise exception 'texte trop long'; end if;
  if p_numero is not null and (p_numero < 0 or p_numero > 9999) then raise exception 'numero invalide'; end if;
  -- emprise France métropolitaine : à élargir si la caserne est hors métropole
  if p_lat is null or p_lon is null or p_lat not between 41 and 52 or p_lon not between -6 and 10 then raise exception 'position invalide'; end if;
  if p_tournee is not null and not exists (select 1 from public.tournees where nom = p_tournee) then raise exception 'tournee inconnue'; end if;
  if exists (select 1 from public.points x
              where x.numero is not distinct from p_numero
                and lower(coalesce(x.suffixe, '')) = lower(coalesce(nullif(btrim(p_suffixe), ''), ''))
                and lower(btrim(x.nom_voie)) = lower(btrim(p_voie))
                and lower(btrim(x.nom_commune)) = lower(btrim(p_commune))
                and abs(x.lat - p_lat) < 0.00003 and abs(x.lon - p_lon) < 0.00005) then
    raise exception 'doublon : cette adresse existe deja a cet endroit';
  end if;
  insert into public.points (numero, suffixe, nom_voie, nom_commune, tournee, lon, lat)
  values (p_numero, nullif(btrim(coalesce(p_suffixe, '')), ''), btrim(p_voie), btrim(p_commune), p_tournee, p_lon, p_lat)
  returning * into r;
  return r;
end $$;

create or replace function public.deplacer_point(p_id bigint, p_lon double precision, p_lat double precision) returns void
language plpgsql security definer set search_path to ''
as $$
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  if p_lat is null or p_lon is null or p_lat not between 41 and 52 or p_lon not between -6 and 10 then raise exception 'position invalide'; end if;
  update public.points set lon = p_lon, lat = p_lat where id = p_id;
  if not found then raise exception 'point introuvable'; end if;
end $$;

create or replace function public.supprimer_adresse(p_id bigint) returns integer
language plpgsql security definer set search_path to ''
as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  select count(*) into n from public.ventes where point_id = p_id;
  delete from public.points where id = p_id;
  if not found then raise exception 'adresse introuvable'; end if;
  return n;
end $$;

create or replace function public.importer_adresses(p_rows jsonb, p_tournee text default null) returns jsonb
language plpgsql security definer set search_path to ''
as $$
declare n_in integer; n_tot integer;
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  if jsonb_typeof(p_rows) <> 'array' then raise exception 'liste attendue'; end if;
  n_tot := jsonb_array_length(p_rows);
  if n_tot > 2000 then raise exception 'maximum 2000 adresses par envoi'; end if;
  if p_tournee is not null and not exists (select 1 from public.tournees where nom = p_tournee) then raise exception 'tournee inconnue'; end if;
  with src as (
    select distinct on (num, lower(coalesce(suf,'')), lower(voie), lower(com))
           num, suf, voie, com, lon, lat, fid
      from (
        select nullif(r->>'numero','')::integer as num,
               nullif(btrim(r->>'suffixe'),'') as suf,
               btrim(r->>'voie') as voie,
               btrim(r->>'commune') as com,
               (r->>'lon')::double precision as lon,
               (r->>'lat')::double precision as lat,
               nullif(r->>'fid','')::integer as fid
          from jsonb_array_elements(p_rows) r
      ) s
     where voie <> '' and com <> '' and length(voie) <= 120 and length(com) <= 80 and length(coalesce(suf,'')) <= 10
       and (num is null or num between 0 and 9999)
       and lat between 41 and 52 and lon between -6 and 10
  ), ins as (
    insert into public.points (fid, numero, suffixe, nom_voie, nom_commune, tournee, lon, lat)
    select s.fid, s.num, s.suf, s.voie, s.com, p_tournee, s.lon, s.lat
      from src s
     where not exists (select 1 from public.points x
                        where x.numero is not distinct from s.num
                          and lower(coalesce(x.suffixe,'')) = lower(coalesce(s.suf,''))
                          and lower(btrim(x.nom_voie)) = lower(s.voie)
                          and lower(btrim(x.nom_commune)) = lower(s.com))
    returning 1
  )
  select count(*) into n_in from ins;
  return jsonb_build_object('recues', n_tot, 'ajoutees', n_in, 'ignorees', n_tot - n_in);
end $$;

create or replace function public.creer_tournee(p_nom text) returns void
language plpgsql security definer set search_path to ''
as $$
declare n text := btrim(coalesce(p_nom, ''));
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  if n = '' or length(n) > 60 then raise exception 'nom de tournee invalide'; end if;
  if exists (select 1 from public.tournees where lower(nom) = lower(n)) then raise exception 'cette tournee existe deja'; end if;
  insert into public.tournees (nom) values (n);
end $$;

create or replace function public.renommer_tournee(p_ancien text, p_nouveau text) returns void
language plpgsql security definer set search_path to ''
as $$
declare n text := btrim(coalesce(p_nouveau, ''));
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  if n = '' or length(n) > 60 then raise exception 'nom de tournee invalide'; end if;
  if lower(n) <> lower(p_ancien) and exists (select 1 from public.tournees where lower(nom) = lower(n)) then raise exception 'cette tournee existe deja'; end if;
  update public.tournees set nom = n where nom = p_ancien;
  if not found then raise exception 'tournee inconnue'; end if;
end $$;

create or replace function public.supprimer_tournee(p_nom text) returns void
language plpgsql security definer set search_path to ''
as $$
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  delete from public.tournees where nom = p_nom;
  if not found then raise exception 'tournee inconnue'; end if;
end $$;

create or replace function public.affecter_points(p_ids bigint[], p_tournee text) returns integer
language plpgsql security definer set search_path to ''
as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  if p_tournee is not null and not exists (select 1 from public.tournees where nom = p_tournee) then raise exception 'tournee inconnue'; end if;
  update public.points set tournee = p_tournee where id = any(p_ids);
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.affecter_tournee(p_tournee text, p_email text) returns void
language plpgsql security definer set search_path to ''
as $$
declare e text := lower(trim(coalesce(p_email, '')));
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  if not exists (select 1 from public.tournees where nom = p_tournee) then raise exception 'tournee inconnue'; end if;
  delete from public.membres where tournee = p_tournee;
  if e <> '' then
    -- domaine technique des comptes (voir DOM dans index.html)
    if e not like '%@%' then e := e || '@calendrier.local'; end if;
    insert into public.membres (email, tournee) values (e, p_tournee);
  end if;
end $$;

create or replace function public.repartir_tournees() returns integer
language plpgsql security definer set search_path to ''
as $$
declare t record; cible text; n integer := 0;
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  create temp table _charge (email text primary key, pts bigint) on commit drop;
  insert into _charge select u.email, 0 from public.utilisateurs u
    where u.role = 'agent' and not exists (select 1 from public.membres m where m.email = u.email);
  if not exists (select 1 from _charge) then return 0; end if;
  for t in
    select tr.nom, count(p.id) as pts from public.tournees tr left join public.points p on p.tournee = tr.nom
    where not exists (select 1 from public.membres m where m.tournee = tr.nom)
    group by tr.nom order by count(p.id) desc, tr.nom
  loop
    select email into cible from _charge order by pts, length(email), email limit 1;
    insert into public.membres (email, tournee) values (cible, t.nom);
    update _charge set pts = pts + t.pts where email = cible;
    n := n + 1;
  end loop;
  return n;
end $$;

create or replace function public.retirer_affectations() returns integer
language plpgsql security definer set search_path to ''
as $$
declare n integer;
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  delete from public.membres where email is not null;
  get diagnostics n = row_count;
  return n;
end $$;

create or replace function public.remise_a_zero(p_archiver boolean, p_nom text) returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare e text := lower(auth.jwt() ->> 'email'); aid bigint; np int; nv int; nt int; tot numeric;
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  if p_archiver then
    if btrim(coalesce(p_nom, '')) = '' then raise exception 'nom d''archive obligatoire'; end if;
    insert into public.archives (nom, cree_par) values (left(btrim(p_nom), 80), e) returning id into aid;
    insert into public.archives_points (archive_id, point_id, fid, numero, suffixe, nom_voie, nom_commune, tournee, binome, statut, commentaire, date_passage, maj_par, maj_le, lat, lon)
      select aid, p.id, p.fid, p.numero, p.suffixe, p.nom_voie, p.nom_commune, p.tournee, m.email, p.statut, p.commentaire, p.date_passage, p.maj_par, p.maj_le, p.lat, p.lon
        from public.points p left join public.membres m on m.tournee = p.tournee;
    insert into public.archives_ventes (archive_id, vente_id, point_id, montant, mode, jour, par, cree_le, tournee, commune, adresse)
      select aid, v.id, v.point_id, v.montant, v.mode, v.jour, v.par, v.cree_le, p.tournee, p.nom_commune,
             btrim(concat_ws(' ', p.numero::text, p.suffixe, p.nom_voie))
        from public.ventes v left join public.points p on p.id = v.point_id;
    select count(*), count(*) filter (where statut <> 'a_faire') into np, nt from public.archives_points where archive_id = aid;
    select count(*), coalesce(sum(montant), 0) into nv, tot from public.archives_ventes where archive_id = aid;
    update public.archives set nb_points = np, nb_traites = nt, nb_ventes = nv, total = tot where id = aid;
  end if;
  delete from public.ventes where true;
  get diagnostics nv = row_count;
  update public.points
     set statut = 'a_faire', date_passage = null, maj_par = null, maj_le = null, commentaire = null
   where statut <> 'a_faire' or date_passage is not null or maj_par is not null or maj_le is not null or commentaire is not null;
  get diagnostics np = row_count;
  return jsonb_build_object('points', np, 'ventes', nv, 'archive_id', aid);
end $$;

-- Ancienne version sans archivage, conservée pour compatibilité
create or replace function public.reinitialiser_points() returns jsonb
language plpgsql security definer set search_path to 'public'
as $$
declare np int; nv int;
begin
  if not public.is_admin() then raise exception 'acces refuse'; end if;
  delete from public.ventes where true;
  get diagnostics nv = row_count;
  update public.points
     set statut = 'a_faire', date_passage = null, maj_par = null, maj_le = null, commentaire = null
   where statut <> 'a_faire' or date_passage is not null or maj_par is not null or maj_le is not null or commentaire is not null;
  get diagnostics np = row_count;
  return jsonb_build_object('points', np, 'ventes', nv);
end $$;

-- ---------- Droits d'exécution : réservés aux comptes connectés ----------

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p
           where p.pronamespace = 'public'::regnamespace and p.prokind = 'f' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    if f.proname <> 'on_new_user' then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;

-- ---------- Sécurité par ligne (RLS) ----------
-- Aucune politique d'écriture sur points/ventes : toute modification passe par les fonctions ci-dessus.

alter table public.tournees        enable row level security;
alter table public.utilisateurs    enable row level security;
alter table public.membres         enable row level security;
alter table public.points          enable row level security;
alter table public.historique      enable row level security;
alter table public.ventes          enable row level security;
alter table public.connexions      enable row level security;
alter table public.archives        enable row level security;
alter table public.archives_points enable row level security;
alter table public.archives_ventes enable row level security;

create policy tournees_select on public.tournees for select to authenticated using (public.est_actif());
create policy tournees_admin  on public.tournees for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy points_select   on public.points  for select to authenticated using (public.est_actif());
create policy ventes_select   on public.ventes  for select to authenticated using (public.est_actif());
create policy utilisateurs_select on public.utilisateurs for select to authenticated using (public.is_admin() or email = public.mon_email());
create policy utilisateurs_admin  on public.utilisateurs for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy membres_select  on public.membres for select to authenticated using (public.is_admin() or email = public.mon_email());
create policy membres_admin   on public.membres for all    to authenticated using (public.is_admin()) with check (public.is_admin());
create policy historique_admin        on public.historique      for select to authenticated using (public.is_admin());
create policy connexions_admin_select on public.connexions      for select to authenticated using (public.is_admin());
create policy archives_admin_select   on public.archives        for select to authenticated using (public.is_admin());
create policy archives_admin_delete   on public.archives        for delete to authenticated using (public.is_admin());
create policy archives_points_admin_select on public.archives_points for select to authenticated using (public.is_admin());
create policy archives_ventes_admin_select on public.archives_ventes for select to authenticated using (public.is_admin());

-- ---------- Temps réel : avancement partagé entre tous les appareils ----------

alter publication supabase_realtime add table public.points, public.ventes;
