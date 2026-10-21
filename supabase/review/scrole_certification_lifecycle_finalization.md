# Lifecycle finalisation

- Ajoute le quota administrable `certified_event_horizon_months` (valeur initiale 6 mois).
- Le compte Pro/Premium ne certifie pas automatiquement les événements créés : l'événement doit posséder sa propre certification.
- Ajoute `scrole_grant_included_certification`, accessible uniquement à `service_role`, pour attribuer une certification incluse après validation du paiement/abonnement.
- Remplace la fonction d'expiration pour journaliser les suspensions et programme son exécution toutes les 15 minutes via pg_cron.
- L'index partiel garantit au plus un abonnement actif par utilisateur.

Avant production, tester la fonction de renouvellement et le flux de paiement avec le prestataire réel. La fonction de grant ne remplace pas la vérification du paiement; elle est délibérément réservée au backend de confiance.
