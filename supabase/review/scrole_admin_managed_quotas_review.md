# Scrole — quotas administrables et application serveur

## Migration
`20261021210000_scrole_admin_managed_quotas.sql` (additive, à valider avant application).

## Quotas initialisés
- Agenda d'un compte sans certification de profil active : 2 événements, horizon de 2 mois.
- Événement non certifié : horizon de 2 mois, durée maximale de 2 jours, 100 ajouts à l'agenda.
- Événement non certifié : 1 cofondateur maximum (en plus du fondateur), 5 membres du personnel maximum.
- Pro : 1 événement certifié et 1 communauté certifiée inclus.
- Premium : 4 événements certifiés et 4 communautés certifiées inclus.

Les valeurs sont des lignes dans `scrole_quota_settings`, pas des constantes front-end. Elles sont modifiables via l'interface d'administration et les RPC protégées.

## Sécurité
- Table RLS activée, aucun accès direct anon/authenticated.
- Lecture des quotas via `admin_get_scrole_quotas()`, écriture via `admin_update_scrole_quota(key,value)`.
- RPC autorisées seulement aux super-admins ou administrateurs possédant `certifications.manage`.
- Toute modification est enregistrée dans `scrole_certification_audit`.
- Des triggers serveur appliquent les limites agenda, date/durée des événements et équipe, même si un client contourne l'interface.

## Hypothèses à valider
1. « Compte certifié » pour la limite de l'agenda signifie une certification de profil active dans `user_certifications`. La certification d'un événement reste indépendante.
2. Un événement ou une communauté certifié(e) est détecté(e) dans les nouvelles tables `event_certifications` / `community_certifications` préparées par la migration précédente.
3. Un événement non certifié est créé dans la fenêtre autorisée, puis peut être prolongé après certification. Le trigger réévalue le statut à chaque modification des dates.
4. Les limites de personnel/cofondateurs sont appliquées aux invitations en attente et aux membres acceptés, afin d'éviter de dépasser le quota via plusieurs invitations simultanées.
5. Les limites de sponsors, invités, statistiques, billetterie, et toutes les actions communautaires doivent encore être raccordées à leurs RPC dédiées avant que l'ensemble de la refonte soit considéré comme complet. Cette migration n'active pas encore ces autres gates.

## Validation obligatoire en environnement isolé
- Appliquer d'abord la migration des entitlements puis cette migration.
- Tester les 11 valeurs initiales et le changement d'une valeur depuis l'interface admin.
- Vérifier qu'un compte sans certification ne peut ajouter un 3e événement ou un événement au-delà de l'horizon, et qu'un compte certifié peut dépasser ces limites.
- Vérifier les 100 ajouts par événement non certifié, les limites durée/horizon et équipe.
- Vérifier qu'un événement certifié ne subit plus les limites d'événement non certifié.
- Tester que non-admin et admin sans permission reçoivent une erreur de permission.
- Vérifier le journal d'audit, les mises à jour concurrentes et l'absence de régression des RPC existantes.
