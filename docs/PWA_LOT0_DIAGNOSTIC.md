# Lot 0 — diagnostic technique PWA (audit statique)

- Dépôt : `stanneguem/scrole_mobile`
- Branche : `feature/story-video-post-reshare`
- Commit audité : `c7b2ca0910bfc7f40a476e2e6ab8d43af6e831b0`
- Date : 2026-11-21
- Méthode : inspection des fichiers et de l'arbre GitHub. Aucun environnement Flutter local n'est disponible dans cet audit ; aucun build, analyze, test d'appareil ou test navigateur n'a été exécuté.

## 1. Résumé exécutif

Le projet possède déjà plusieurs briques multiplateformes réelles : factory SQLite Web/WASM, IndexedDB via `sqflite_common_ffi_web`, cache Hive, contrat `CacheStore`, `MediaAsset` basé sur `XFile`, upload R2 streamé et service Realtime dédié au navigateur.

Le socle n'est cependant pas prêt à être déclaré stable. Les risques les plus importants à traiter avant la migration fonctionnelle sont :

1. **Imports natifs dans des services communs** : `session_service.dart` et `notification_service.dart` importent directement `dart:io`. Le premier manipule aussi `Directory` dans le code partagé ; le second appelle `Platform.isIOS/isAndroid`. Le build Web doit confirmer le comportement réel ; ces responsabilités doivent être déplacées derrière des adaptateurs conditionnels.
2. **Logout destructif pour toutes les bases locales** : `AppDatabase.clearUserData(userId)` désactive les clés étrangères puis vide toutes les tables locales, pas seulement les lignes du compte indiqué. Cela peut effacer les outboxes d'autres comptes et les opérations locales non synchronisées. `SessionService.stopSession()` vide également toute la box Hive `app_cache`.
3. **Push navigateur absent** : `WebRealtimeNotificationService` couvre les notifications in-app via Supabase Realtime, mais le dépôt ne contient pas de `web/firebase-messaging-sw.js` et `WEB_SETUP.md` confirme que Web Push n'est pas configuré.
4. **Capacités médias Web incomplètes** : `MediaService.cropImage()` retourne l'image originale sur Web (aucun recadrage n'est fait) ; plusieurs APIs et méthodes historiques restent File-based.
5. **Validation automatisée absente** : aucun fichier `.github/workflows/` n'existe dans l'arbre du commit et l'API GitHub Actions retourne zéro exécution sur la branche.

## 2. Inventaire vérifié

### Web / démarrage
- `lib/main.dart` appelle `configureDatabaseFactory()` avant le bootstrap.
- `database_factory.dart` sélectionne `database_factory_web.dart` avec `dart.library.js_interop`.
- `database_factory_web.dart` installe `databaseFactoryFfiWeb`.
- `tool/setup_web_sqlite.sh` génère les artefacts avec `dart run sqflite_common_ffi_web:setup`.
- `web/index.html`, `web/manifest.json`, `web/sqlite3.wasm` et `web/sqflite_sw.js` sont présents.
- Le worker SQLite est un composant du moteur SQLite ; il ne constitue pas à lui seul le service worker PWA de l'application.

### Stockage local / base
- `AppDatabase` utilise `app_local.db`, version de schéma 34, avec chemin spécifique Web.
- `SalonChatDatabase` ouvre `salon_chat_local.db` séparément et versionne son schéma indépendamment.
- `MessagingDatabase` délègue à `AppDatabase` et indique partager une connexion unique.
- `FastCacheService` ouvre une box Hive globale `app_cache` et expose `clear()` qui vide toute la box.
- Un contrat `CacheStore` existe déjà.
- Les tables SQLite principales contiennent de nombreuses clés `user_id`, mais le nettoyage actuel ne respecte pas cette granularité.

### Session / logout
- `SessionService` suit un `_activeUserId`, annule le listener Realtime lors d'un changement de compte et vérifie l'utilisateur actif après des lectures asynchrones.
- Le logout supprime le cache Stories du compte, purge les médias, vide la box Hive entière, puis appelle `AppDatabase.clearUserData(uid)`.
- `AppDatabase.clearUserData` sélectionne toutes les tables utilisateur et exécute `DELETE` sans filtre ; son commentaire précise que toutes les lignes sont vidées car certaines tables ne sont pas indexées par utilisateur.
- La base salons a une méthode `clearUserData(userId)` ciblée sur `salon_messages` et `salon_sync_cursors`, mais supprime aussi globalement `salon_cache_metadata`.
- Les pièces jointes sortantes du chat sont dans la box LazyHive `pending_chat_media`, avec des clés qui incluent le userId. Le logout ne la purge pas dans le chemin inspecté : ce comportement doit être couvert par un test d'isolation, sans supprimer les pièces jointes d'un autre compte.

### Médias
- `MediaAsset` expose `XFile`, nom, MIME, taille et `openRead()`, avec support d'un flux persistant.
- `R2MediaRepository.uploadMediaAsset` utilise `StreamedRequest` et `MediaAsset.openRead()`.
- Le chemin legacy `uploadFile` reste File/path-based et lit le fichier complet avec `readAsBytes()`.
- `StorageRepository` expose encore plusieurs méthodes publiques qui acceptent `File`, en parallèle de méthodes `XFile`.
- `MediaService` sélectionne via `XFile`, mais le recadrage Web retourne le fichier inchangé ; il faut rendre cette absence de recadrage explicite dans l'interface et les critères d'acceptation.
- Les exports conditionnels `media_gallery_picker.dart` et `media_image_processor.dart` chargent des implémentations IO ou des stubs. Les stubs Web et leurs comportements doivent être vérifiés parcours par parcours.

### Notifications
- `main.dart` initialise `WebRealtimeNotificationService` sur Web et `NotificationService` / FCM sur les plateformes natives.
- `WebRealtimeNotificationService` s'abonne aux INSERT/UPDATE/DELETE de la table notifications filtrés par userId et persiste les entrées localement.
- Ce service n'affiche pas de notifications système navigateur et le code indique explicitement que Web Push nécessite VAPID et un service worker.
- Aucun fichier `web/firebase-messaging-sw.js` n'est présent dans l'arbre audité.

### Tests / CI
- 27 fichiers de tests Dart sont présents dans `test/` (E2EE, base locale, communautés, événements, profils et utilitaires).
- Aucun workflow GitHub Actions n'est présent sous `.github/workflows/`.
- L'API Actions a retourné `total_count: 0` pour `feature/story-video-post-reshare`.
- `pubspec.lock` est présent. La contrainte SDK du `pubspec.yaml` est `^3.12.2`.
- Ces constats ne prouvent ni que les tests passent ni que toutes les dépendances supportent le Web.

## 3. Risques classés

| Priorité | Sujet | Risque / action requise |
|---|---|---|
| P0 | Imports `dart:io` dans services communs | Isoler les opérations fichiers/Platform dans des implémentations IO et Web conditionnelles ; confirmer par build Web |
| P0 | Logout vide toutes les tables SQLite | Reconcevoir le nettoyage par compte et protéger explicitement les outboxes ; définir la politique pour opérations non synchronisées avant toute modification |
| P0 | Cache Hive global | Remplacer le clear global par namespaces/keys par compte, en conservant les caches publics réellement partagés |
| P1 | SQLite WASM / IndexedDB | Tester ouverture des deux bases, migrations, transactions, fermeture/réouverture, deux onglets et concurrence |
| P1 | Uploads File legacy | Migrer les callsites vers `MediaAsset` / `XFile`, puis supprimer les signatures File-only |
| P1 | Stories/media Web | Vérifier picker, preview, crop, compression, lecture, cache, expiration et upload sur navigateur |
| P1 | Push navigateur | Ajouter configuration Firebase Web/VAPID/service worker et tester permission, token, réception et clic |
| P1 | Pending chat media | Tester quota IndexedDB, fermeture brutale, reprise outbox, logout/login de comptes distincts et nettoyage des orphelins |
| P2 | Cycle de vie PWA | Définir service worker applicatif, cache shell versionné, mise à jour et routes profondes par hébergeur |
| P2 | E2EE WebAssembly | Valider compilation, stockage de clés et scénarios cryptographiques avant activation Web |

## 4. Plan d'exécution proposé pour fermer le lot 0

1. Obtenir un run local reproductible : `flutter --version`, `dart --version`, `flutter pub get`.
2. Lancer séparément `flutter analyze`, `flutter test`, `flutter build web --release` et `flutter build apk --debug`. Conserver la première erreur de chaque commande sans en masquer les suivantes.
3. Corriger d'abord les imports natifs dans les services communs, avec implémentations conditionnelles, sans modifier le comportement Android.
4. Écrire des tests de nettoyage/session : compte A avec données synchronisées et outbox en attente, logout, compte B, puis reconnexion A ; vérifier qu'aucune donnée privée ne fuit et qu'aucune opération en attente n'est perdue silencieusement.
5. Valider les deux bases SQLite sur Chrome : création, migration, transaction, fermeture/réouverture, deux onglets.
6. Réaliser une matrice médias Web : sélection image/vidéo, aperçu, recadrage (ou message explicite), upload R2, annulation, offline/reprise et quota.
7. À la fin seulement, marquer le lot 0 terminé et passer au lot 1.

## 5. Commandes de référence à exécuter localement

```bash
git checkout feature/story-video-post-reshare
git pull origin feature/story-video-post-reshare
flutter --version
dart --version
flutter pub get
bash tool/setup_web_sqlite.sh
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

## 6. Décision

**Lot 0 : audit statique effectué, porte de validation non franchie.**

Les deux corrections prioritaires avant les lots fonctionnels sont :
- isoler les opérations natives et sécuriser le build Web ;
- corriger la politique de logout/cache pour préserver l'isolation des comptes et les opérations offline.

Aucune fonctionnalité n'a été modifiée dans ce lot de diagnostic. Les builds et tests restent à exécuter dans l'environnement Flutter du développeur.
