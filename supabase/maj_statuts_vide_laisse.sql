-- Ajout des statuts « vide » et « laissé » (14/11/2026) : à exécuter une fois dans Supabase > SQL Editor
alter table public.points drop constraint points_statut_check;
alter table public.points add constraint points_statut_check check (statut in ('a_faire','fait','partiel','repasse','refus','vide','laisse'));

create or replace function public.set_statut(p_id bigint, p_statut text) returns void
language plpgsql security definer set search_path to ''
as $$
declare e text := lower(auth.jwt() ->> 'email'); old text; t text;
  jour date := (now() at time zone 'Europe/Paris')::date;
begin
  if p_statut not in ('a_faire','fait','partiel','repasse','refus','vide','laisse') then raise exception 'statut invalide'; end if;
  select statut, tournee into old, t from public.points where id = p_id;
  if not found then raise exception 'point introuvable'; end if;
  if not (public.is_admin() or t in (select public.mes_tournees())) then raise exception 'acces refuse'; end if;
  update public.points
     set statut = p_statut, date_passage = jour, maj_par = e, maj_le = now(),
         commentaire = case when p_statut in ('partiel','repasse') then commentaire else null end
   where id = p_id;
  insert into public.historique (point_id, email, ancien, nouveau) values (p_id, e, old, p_statut);
end $$;

comment on column public.points.statut is 'État du passage : a_faire, fait, partiel (partiellement fait), repasse (à repasser), refus, vide (logement vide), laisse (calendrier laissé).';
