-- Descriptions (métadonnées) des objets de la base Calendo.
-- Visibles dans le tableau de bord Supabase (Table Editor / Database) et via \d+ en psql.

comment on table public.tournees is 'Liste des tournées (secteurs de distribution). La clé est le nom affiché dans l''application.';
comment on column public.tournees.nom is 'Nom de la tournée (clé primaire, 60 caractères max). Renommer propage le nom aux points et aux affectations.';

comment on table public.utilisateurs is 'Comptes autorisés et leur rôle applicatif. Alimentée automatiquement à chaque création de compte (trigger on_new_user).';
comment on column public.utilisateurs.email is 'Identifiant de connexion en minuscules (ex. binome1@calendrier.local).';
comment on column public.utilisateurs.role is 'admin = gère tournées, comptes, données et remises à zéro ; agent = saisit uniquement sur ses tournées.';

comment on table public.membres is 'Affectation des binômes (comptes) aux tournées. Un binôme peut avoir plusieurs tournées. Conservée lors d''une remise à zéro.';
comment on column public.membres.email is 'Compte affecté (référence logique à utilisateurs.email).';
comment on column public.membres.tournee is 'Tournée affectée (clé étrangère vers tournees.nom, supprimée en cascade).';

comment on table public.points is 'Adresses à visiter (un point = une adresse géolocalisée) avec leur état d''avancement. Table publiée en temps réel.';
comment on column public.points.id is 'Identifiant technique interne.';
comment on column public.points.fid is 'Identifiant d''origine dans le fichier source (BAN / GeoJSON), informatif.';
comment on column public.points.numero is 'Numéro dans la voie (NULL si absent).';
comment on column public.points.suffixe is 'Indice de répétition : bis, ter, A, B… (NULL si absent).';
comment on column public.points.nom_voie is 'Nom de la voie.';
comment on column public.points.nom_commune is 'Commune de l''adresse.';
comment on column public.points.tournee is 'Tournée de rattachement (NULL = non affectée).';
comment on column public.points.statut is 'État du passage : a_faire, fait, partiel (partiellement fait), repasse (à repasser), refus.';
comment on column public.points.date_passage is 'Date (heure de Paris) du dernier passage enregistré.';
comment on column public.points.lon is 'Longitude WGS84 (EPSG:4326).';
comment on column public.points.lat is 'Latitude WGS84 (EPSG:4326).';
comment on column public.points.maj_par is 'Compte ayant effectué la dernière modification.';
comment on column public.points.maj_le is 'Horodatage de la dernière modification.';
comment on column public.points.commentaire is 'Précisions libres (300 caractères max), conservées seulement pour les statuts partiel et repasse.';

comment on table public.historique is 'Journal des changements de statut d''un point (qui, quand, ancien -> nouveau). Lecture réservée à l''administrateur.';
comment on column public.historique.point_id is 'Point concerné (supprimé en cascade avec le point).';
comment on column public.historique.email is 'Compte à l''origine du changement.';
comment on column public.historique.ancien is 'Statut avant le changement.';
comment on column public.historique.nouveau is 'Statut après le changement.';
comment on column public.historique.le is 'Date et heure du changement.';

comment on table public.ventes is 'Ventes de calendriers enregistrées sur un point (plusieurs possibles par adresse). Table publiée en temps réel.';
comment on column public.ventes.id is 'UUID généré côté client : rend l''envoi idempotent lors des reprises hors connexion.';
comment on column public.ventes.point_id is 'Adresse concernée (suppression en cascade).';
comment on column public.ventes.montant is 'Montant en euros, strictement entre 0 et 10 000.';
comment on column public.ventes.mode is 'Mode de paiement : especes, cheque ou cb.';
comment on column public.ventes.jour is 'Jour de la vente (heure de Paris).';
comment on column public.ventes.par is 'Compte ayant saisi la vente.';
comment on column public.ventes.cree_le is 'Horodatage de l''enregistrement.';

comment on table public.connexions is 'Historique des connexions (200 dernières conservées, dédoublonnées sur 5 minutes). Lecture réservée à l''administrateur.';
comment on column public.connexions.email is 'Compte connecté.';
comment on column public.connexions.le is 'Date et heure de la connexion.';
comment on column public.connexions.ua is 'User-agent (appareil / navigateur), tronqué à 300 caractères.';

comment on table public.archives is 'En-têtes des archives de saison créées lors d''une remise à zéro (nom, date, totaux).';
comment on column public.archives.nom is 'Nom donné à l''archive (1 à 80 caractères), ex. « Calendrier 2026 ».';
comment on column public.archives.cree_le is 'Date de création de l''archive.';
comment on column public.archives.cree_par is 'Administrateur ayant archivé.';
comment on column public.archives.nb_points is 'Nombre d''adresses figées dans l''archive.';
comment on column public.archives.nb_traites is 'Nombre d''adresses dont le statut n''était pas a_faire.';
comment on column public.archives.nb_ventes is 'Nombre de ventes archivées.';
comment on column public.archives.total is 'Montant total des ventes archivées (euros).';

comment on table public.archives_points is 'Copie figée des points au moment de l''archivage, avec le binôme affecté à l''époque.';
comment on column public.archives_points.archive_id is 'Archive parente (suppression en cascade).';
comment on column public.archives_points.binome is 'Binôme affecté à la tournée au moment de l''archivage.';

comment on table public.archives_ventes is 'Copie figée des ventes au moment de l''archivage, avec tournée, commune et adresse en clair.';
comment on column public.archives_ventes.archive_id is 'Archive parente (suppression en cascade).';
comment on column public.archives_ventes.adresse is 'Adresse en clair (numéro, suffixe, voie).';

comment on function public.is_admin() is 'Vrai si le compte connecté (JWT) a le rôle admin. Utilisée par les politiques RLS.';
comment on function public.est_actif() is 'Vrai si le compte est admin ou affecté à au moins une tournée. Conditionne la lecture des points, tournées et ventes.';
comment on function public.mes_tournees() is 'Liste des tournées du compte connecté.';
comment on function public.mon_email() is 'Email du compte connecté, en minuscules (extrait du JWT).';
comment on function public.claim_admin() is 'Premier compte à l''appeler quand aucun admin n''existe : devient administrateur. Ensuite, renvoie simplement s''il l''est.';
comment on function public.on_new_user() is 'Trigger sur auth.users : crée la ligne utilisateurs avec le rôle agent.';
comment on function public.noter_connexion(text) is 'Enregistre une connexion (dédoublonnée sur 5 minutes) et ne garde que les 200 plus récentes.';
comment on function public.set_statut(bigint, text) is 'Change le statut d''un point (admin ou binôme de la tournée), journalise dans historique ; efface le commentaire hors partiel/repasse.';
comment on function public.set_commentaire(bigint, text) is 'Enregistre les précisions (300 car. max) d''un point (admin ou binôme de la tournée).';
comment on function public.ajouter_vente(uuid, bigint, numeric, text) is 'Ajoute une vente idempotente (uuid client) ; passe le point à fait sauf s''il est partiel.';
comment on function public.supprimer_vente(uuid) is 'Supprime une vente (admin ou binôme de la tournée).';
comment on function public.creer_adresse(integer, text, text, text, text, double precision, double precision) is 'Crée une adresse manquante (admin ou binôme sur sa tournée) avec contrôle de doublon (clé numéro-suffixe-voie-commune et proximité).';
comment on function public.deplacer_point(bigint, double precision, double precision) is 'Admin : déplace un point sur la carte.';
comment on function public.supprimer_adresse(bigint) is 'Admin : supprime un point ; renvoie le nombre de ventes supprimées avec lui.';
comment on function public.creer_tournee(text) is 'Admin : crée une tournée (nom unique, insensible à la casse).';
comment on function public.renommer_tournee(text, text) is 'Admin : renomme une tournée (propagé aux points et affectations).';
comment on function public.supprimer_tournee(text) is 'Admin : supprime une tournée ; ses points deviennent non affectés.';
comment on function public.affecter_points(bigint[], text) is 'Admin : affecte une liste de points à une tournée (NULL = désaffecter).';
comment on function public.affecter_tournee(text, text) is 'Admin : définit le binôme d''une tournée (identifiant sans @ complété par @calendrier.local ; vide = aucun).';
comment on function public.repartir_tournees() is 'Admin : répartit les tournées sans binôme entre les agents sans tournée, en équilibrant le nombre de points.';
comment on function public.retirer_affectations() is 'Admin : supprime toutes les affectations binôme/tournée.';
comment on function public.remise_a_zero(boolean, text) is 'Admin : remet tous les points à a_faire et supprime les ventes, en archivant d''abord la saison si demandé. Les affectations binôme/tournée sont conservées.';
comment on function public.reinitialiser_points() is 'Ancienne version de la remise à zéro, sans archivage (conservée pour compatibilité).';
comment on function public.importer_adresses(jsonb, text) is 'Admin : import en lot d''adresses (Base Adresse Nationale ou autre), 2000 max par appel ; ignore les doublons (clé numéro-suffixe-voie-commune) et les lignes invalides.';
