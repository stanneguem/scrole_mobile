# Refonte des certifications Scrole — état de livraison

## État actuel
Les cinq migrations listées ci-dessous ont été appliquées au projet Supabase actif et sont présentes dans l'historique distant. Les fichiers du dépôt utilisent désormais exactement les versions d'historique renvoyées par Supabase afin d'éviter de les rejouer comme des migrations en attente.

1. `20261021150026_scrole_certification_entitlements_foundation.sql`
2. `20261021150100_scrole_admin_managed_quotas.sql`
3. `20261021150308_scrole_certification_lifecycle_and_feature_gates.sql`
4. `20261021150602_scrole_certification_lifecycle_finalization.sql`
5. `20261021150748_scrole_event_feature_gate_hardening.sql`

## Objets et fonctions
- `scrole_subscriptions` : registre des abonnements Pro/Premium.
- `event_certifications`, `community_certifications` : certifications indépendantes, provenance, état, validité et lien d'abonnement.
- `profile_certification_entitlements` : suivi distinct des certifications de profil incluses dans l'abonnement.
- `scrole_certification_audit` : historique des changements de formule, attribution, suspension et réactivation.
- `scrole_quota_settings` : paramètres modifiables par l'administration.
- RPC d'administration : `admin_get_scrole_quotas()`, `admin_update_scrole_quota(text, integer)`.
- RPC de cycle de vie : `scrole_change_subscription_plan_v2`, `scrole_renew_subscription`, `scrole_grant_included_certification`, `scrole_grant_included_profile_certification`, `scrole_suspend_expired_subscription_certifications`.
- RPC publique en lecture seule pour le formulaire mobile : `get_scrole_public_quota_settings()`.
- La tâche `pg_cron` `scrole-expire-subscription-certifications` tourne toutes les 15 minutes.

## Quotas initiaux administrables
- Agenda du profil sans certification active : 2 événements, horizon de 2 mois.
- Événement non certifié : horizon de création de 2 mois, durée maximale de 2 jours, 100 ajouts à l'agenda.
- Événement non certifié : 1 cofondateur et 5 membres du personnel.
- Événement certifié : horizon de planification de 6 mois.
- Pro : 1 certification d'événement et 1 de communauté incluses.
- Premium : 4 certifications d'événement et 4 de communauté incluses.

Ces valeurs sont des lignes en base et sont modifiables via l'interface d'administration. Les limites de plage restent imposées pour protéger le système.

## Sécurité
- Les écritures directes de quota et de certifications ne sont pas accordées à `anon` ou `authenticated`.
- Les modifications de quotas passent par une RPC qui vérifie `is_super_admin()` ou la permission `certifications.manage`, et écrit un audit.
- Les attributions/renouvellements d'avantages inclus sont réservés à `service_role`; ils ne doivent être appelés qu'après validation côté serveur du paiement ou de l'abonnement.
- Les certifications achetées séparément ne sont pas rattachées aux entitlements inclus et ne sont pas suspendues avec l'abonnement.
- La certification du profil ou d'une communauté ne certifie pas automatiquement les événements.
- Les statistiques d'événement, les invitations Guest, les sponsors et la billetterie nécessitent une certification d'événement active.

## Points encore nécessaires avant production complète
- Raccorder les RPC de création/attribution/renouvellement au véritable prestataire de paiement et tester ses webhooks.
- Le parcours de création d'un événement à plus de deux mois doit permettre de consommer explicitement une certification incluse ou achetée avant l'insertion initiale; actuellement la création initiale non certifiée est limitée à deux mois.
- Effectuer les tests fonctionnels avec comptes et événements de test, notamment expiration/renouvellement, downgrade Premium → Pro, invitations, billetterie, statistiques et permissions.
- Le build Flutter et le build Vite/TypeScript n'ont pas été exécutés depuis cet environnement.
- Le dépôt local contient encore un sous-ensemble de l'historique de migrations distant; ne pas rejouer l'ensemble des anciennes migrations. Les cinq nouvelles versions sont alignées sur l'historique Supabase distant.
