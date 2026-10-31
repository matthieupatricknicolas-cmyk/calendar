-- =====================================================================
-- Calendo – création des comptes (binômes + administrateur)
-- À exécuter dans Supabase > SQL Editor APRÈS schema.sql.
-- ⚠ Modifiez les 3 paramètres ci-dessous AVANT d'exécuter.
-- Les comptes sont créés directement dans auth.users (pas d'email de
-- confirmation). Identifiant de connexion = « binome1 », « admin »…
-- (l'application ajoute @calendrier.local, constante DOM dans index.html).
-- =====================================================================
do $$
declare
  mot_de_passe text := 'CHANGEZ-MOI-8car-min';  -- mot de passe commun initial (à changer ensuite)
  nb_binomes   int  := 20;                       -- nombre de comptes binomeN à créer
  mdp_admin    text := 'CHANGEZ-MOI-ADMIN';      -- mot de passe du compte admin@calendrier.local
  i int; em text; uid uuid;
begin
  if mot_de_passe like 'CHANGEZ%' or mdp_admin like 'CHANGEZ%' then
    raise exception 'Renseignez d''abord les mots de passe en haut du script';
  end if;
  for i in 0..nb_binomes loop
    em := case when i = 0 then 'admin@calendrier.local' else 'binome' || i || '@calendrier.local' end;
    if exists (select 1 from auth.users where email = em) then continue; end if;
    uid := gen_random_uuid();
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
                            raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
                            confirmation_token, recovery_token, email_change, email_change_token_new)
    values ('00000000-0000-0000-0000-000000000000', uid, 'authenticated', 'authenticated', em,
            extensions.crypt(case when i = 0 then mdp_admin else mot_de_passe end, extensions.gen_salt('bf')),
            now(), '{"provider":"email","providers":["email"]}', '{}', now(), now(), '', '', '', '');
    insert into auth.identities (id, user_id, provider_id, provider, identity_data, last_sign_in_at, created_at, updated_at)
    values (gen_random_uuid(), uid, uid::text, 'email',
            jsonb_build_object('sub', uid::text, 'email', em, 'email_verified', true), now(), now(), now());
  end loop;
  -- le trigger on_auth_user_created a créé les lignes « agent » ; on promeut l'admin
  update public.utilisateurs set role = 'admin' where email = 'admin@calendrier.local';
end $$;
