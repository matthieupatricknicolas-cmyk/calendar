-- Lecture des ventes : l'admin voit tout, un binôme ne voit que les ventes des adresses de ses tournées.
-- Ne modifie aucune donnée (ni ventes, ni montants, ni statuts) : seule la règle de lecture change.
drop policy ventes_select on public.ventes;
create policy ventes_select on public.ventes for select to authenticated using (
  public.is_admin() or exists (
    select 1 from public.points p where p.id = point_id and p.tournee in (select public.mes_tournees())));
