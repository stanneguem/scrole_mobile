# Audit du stockage et plan de migration PWA — Scrole

Branche auditée : `feature/story-video-post-reshare`  
Commit de référence : `6abb5d0c122777a6fad174e7cb20d17a96f2ce31`  
Date : 2026-11-17

## 1. Conclusion exécutive

Le dépôt possède déjà une première compatibilité SQLite Web : `database_factory.dart` sélectionne `database_factory_web.dart` avec une importation conditionnelle sur `dart.library.js_interop`, et l'adaptateur Web configure `databaseFactoryFfiWeb`. Les fichiers `web/sqlite3.wasm` et `web/sqflite_sw.js` sont présents.

SQLite n'est donc pas simplement « non compatible Web ». Le vrai travail est de valider cette implémentation (initialisation, migrations, persistance, transactions, multi-onglets et déploiement des ressources WASM), puis de traiter les stockages qui utilisent directement le système de fichiers ou qui ont une implémentation Web vide.

Le dépôt ne contient pas encore, dans `web/`, de service worker PWA applicatif clairement distinct du worker SQLite. `web/sqflite_sw.js` est le worker de la couche SQLite : il ne faut pas le confondre avec un service worker de précache du shell Flutter et des ressources de la PWA.

## 2. Inventaire vérifié

### Base de données structurée

- `lib/app/local_storage/structured/app_cache_database.dart`
  - Base principale `app_local.db`, version de schéma 34 au moment de l'audit.
  - Contient notamment les caches de feed et communauté, messages, notifications, événements, activités, préférences et outbox.
  - Le chemin Web est le nom logique `app_local.db`; les PRAGMA de performance propres au système de fichiers sont évités sur Web.
- `lib/app/local_storage/structured/database_factory.dart`
  - Importation conditionnelle entre le stub mobile et l'adaptateur Web.
- `lib/app/local_storage/structured/database_factory_web.dart`
  - Configure `databaseFactoryFfiWeb` depuis `sqflite_common_ffi_web`.
- `lib/modules/module_communautes/centre/persistence/salon_chat_database.dart`
  - Deuxième base SQLite indépendante : `salon_chat_local.db`.
  - Gère les messages/cursors des salons et utilise également le nom logique Web.
- `lib/modules/module_discussion_direct/centre/persistence/messaging_database.dart`
  - Base distincte de messagerie directe : à auditer en détail avant validation globale.
- DAOs identifiés : `preferences_local_dao.dart`, `activity_local_dao.dart`, `community_local_dao.dart`, `conversations_dao.dart`, `messages_dao.dart`, `social_local_dao.dart`, `evenement_local_dao.dart`.

**Risque à traiter :** plusieurs bases SQLite sont ouvertes par des services différents. Il faut tester leur initialisation, leur persistance et les accès concurrents sur Web, pas seulement l'ouverture de `AppDatabase`.

### Cache rapide Hive

- `lib/app/local_storage/fast/fast_cache_service.dart`
  - Utilise `Hive.initFlutter()` et `Hive.openBox('app_cache')`.
  - Stocke des valeurs dynamiques avec timestamp, expiration facultative, suppression par clé/préfixe et vidage complet.
- `lib/app/local_storage/fast/fast_cache_key.dart`
  - Centralise une partie des clés de cache, dont profils, feed, communautés et activités.
- `main.dart` initialise ce service avant les services qui en dépendent.

**Décision :** conserver Hive derrière un contrat de cache au départ. Ne pas réécrire toutes les clés et tous les consommateurs avant d'avoir validé Hive sur les navigateurs cibles. Vérifier en particulier la portée par utilisateur : certaines clés génériques (par exemple `profile`, `communities`, `activities`) méritent une revue pour éviter les collisions de session.

### Stories et caches JSON

- `StoriesController` utilise `dart:io`, `File`, `path_provider` et un fichier JSON nommé `stories_tray_cache_<userId>.json`.
- Le nettoyage de ce cache est appelé par `SessionService.stopSession()`.
- Ce mécanisme est natif et ne peut pas être utilisé tel quel dans une compilation Web.

**Décision :** déplacer le cache du tray Stories vers le contrat de stockage commun, avec clé explicitement scindée par utilisateur. Préserver la règle de sécurité déjà présente : ne restaurer depuis le cache que les propres stories du compte; les groupes d'autres auteurs doivent être réobtenus depuis le serveur.

### Médias et vidéos

- `ChatMediaCache` utilise `dart:io`, `File`, `Directory`, `path_provider` et un répertoire par utilisateur pour les médias privés.
- `feed_video_cache_io.dart` implémente un cache disque de vidéos progressives (taille max par vidéo 24 MiB, budget global 120 MiB, TTL 7 jours); les flux HLS/DASH et fichiers trop grands sont exclus.
- `scut_video_cache.dart` sélectionne une implémentation IO uniquement quand `dart.library.io` est disponible; son stub retourne des valeurs vides/null et lit les vidéos depuis le réseau.
- `scut_video_cache_io.dart` conserve le manifeste Scut et les signaux de visionnage en fichiers JSON, ainsi que les vidéos en fichiers locaux.
- `MediaService` utilise `File`, `ImageCropper`, `FlutterImageCompress` et `path_provider`.
- `StorageRepository` expose plusieurs uploads avec des paramètres `File`.

**Décision :** pour le Web, introduire des APIs basées sur `XFile`/bytes et `Blob` au niveau des frontières de sélection/upload. Les médias cacheables pourront être stockés dans IndexedDB en Blob, avec URL objet temporaire pour l'affichage. Ne jamais faire passer un chemin de fichier natif comme identifiant persistant Web. Le cache vidéo Scut actuel est volontairement inactif sur Web et devra avoir une vraie stratégie navigateur distincte.

### Session, nettoyage et synchronisation

- `SessionService.stopSession()` nettoie les stories JSON, plusieurs répertoires médias natifs, le cache image mémoire, Hive et les lignes de l'utilisateur dans `AppDatabase`.
- `SyncService` stocke le curseur dans Hive via une clé actuellement globale `sync_cursor`.
- Des outbox SQL existent pour les posts, communautés, notifications et préférences; d'autres files JSON existent pour les signaux de visionnage Scut.
- Le nettoyage actuel des médias référence des répertoires natifs et ne peut pas être réutilisé tel quel sur Web.

**Décision :** centraliser le nettoyage derrière des opérations de portée utilisateur. Avant de supprimer une file hors ligne, distinguer les données régénérables des opérations non synchronisées : celles-ci doivent rester rattachées au compte d'origine et ne jamais être exposées au compte suivant.

### PWA / ressources Web

- `web/index.html` charge `flutter_bootstrap.js` et référence `manifest.json`.
- `web/manifest.json` définit déjà le nom, les icônes et le mode `standalone`.
- `web/sqlite3.wasm` et `web/sqflite_sw.js` existent.
- Aucun fichier de service worker applicatif PWA distinct n'a été identifié dans le dossier source `web/` au moment de cet audit.

**Décision :** ne pas modifier le worker SQLite. Ajouter et tester séparément le cycle de vie du service worker PWA (précache des ressources statiques, versionnement, mise à jour). Ne jamais mettre en cache aveuglément les réponses privées Supabase.

## 3. Matrice de migration

| Domaine | État Web observé | Action |
|---|---|---|
| SQLite principale | Adaptateur WASM configuré | Tests fonctionnels et multi-onglets avant décision |
| SQLite salons | Ouverture Web prévue | Tests d'initialisation et d'isolation |
| SQLite messagerie directe | Base séparée identifiée | Inspecter puis tester |
| Hive | Package utilisé via Hive Flutter | Tester persistance et multi-onglets; envelopper par contrat |
| Stories JSON | Dépendance directe au filesystem | Migrer vers cache structuré |
| Cache médias chat | Filesystem uniquement | Adapter IndexedDB Blob |
| Cache vidéo feed | Implémentation IO | Stratégie Web séparée; réseau/cache navigateur au départ |
| Cache Scut | Stub Web inactif | Implémenter manifeste + signaux + politique vidéo Web |
| Sélection/upload médias | API File/path natives | Frontière bytes/XFile et adaptateurs plateforme |
| Nettoyage session | Nettoyage natif partiel | Centraliser et tester isolation compte |
| PWA service worker | Manifest présent, worker SQLite présent | Ajouter worker applicatif distinct |

## 4. Plan d'implémentation par lots

### Lot 0 — Validation de la plateforme (aucune modification du comportement mobile)
1. Confirmer versions Flutter/Dart et dépendances verrouillées.
2. Exécuter `flutter build web` et corriger uniquement les erreurs de compilation Web bloquantes.
3. Valider chargement WASM/worker SQLite, ouverture des trois bases, migrations et transactions.
4. Tester persistance après refresh, navigation, fermeture/réouverture et deux onglets.
5. Inventorier tous les imports `dart:io` et plugins sans implémentation Web; classer par chemin d'exécution réellement atteint.
6. Ajouter des tests ciblés de stockage et isolation de compte.

### Lot 1 — Contrats de stockage
Introduire des contrats étroits et testables :
- `CacheStore`: get/set/remove/clear/clearPrefix avec TTL.
- `UserScopedStore`: clearUser(userId), namespace obligatoire.
- `MediaStore`: put/get/delete avec bytes/Blob et métadonnées.
- `StructuredStore`: ne pas abstraire prématurément le SQL; garder les DAOs et sélectionner la factory par plateforme.

Les implémentations natives doivent continuer à utiliser Hive/fichiers/SQLite. Les implémentations Web seront ajoutées progressivement. Éviter une migration big-bang.

### Lot 2 — Cache rapide et Stories
1. Envelopper Hive derrière `CacheStore`.
2. Auditer puis corriger les clés globales qui devraient être utilisateur-scopées.
3. Migrer le JSON Stories vers le contrat structuré.
4. Garder le filtrage de sécurité des stories non-own du cache.

### Lot 3 — Médias et Scut
1. Définir des API de média fondées sur bytes/XFile plutôt que File.
2. Implémenter IndexedDB Blob pour les médias privés et URL objet à durée de vie contrôlée.
3. Ajouter budget/quota/LRU et purge par utilisateur.
4. Créer l'adaptateur Web du manifeste et des signaux Scut.
5. Sur Web, conserver le streaming réseau pour les vidéos si le stockage persistant n'est pas fiable; ne pas télécharger systématiquement de gros fichiers.

### Lot 4 — Données structurées, outbox et synchronisation
1. Tester les trois bases SQLite et les DAOs.
2. Garantir l'isolation user_id sur toutes les tables et files.
3. Rendre les écritures idempotentes et les retries robustes.
4. Coordonner les onglets (Web Locks/BroadcastChannel ou stratégie de verrouillage supportée).
5. Préserver les opérations en attente à la déconnexion sans les exposer au prochain compte.

### Lot 5 — PWA et validation finale
1. Ajouter un service worker applicatif distinct du worker SQLite.
2. Précacher seulement shell/assets statiques versionnés.
3. Définir règles réseau pour API Supabase et médias privés.
4. Tester installation, offline, mise à jour et éviction/quota.
5. Tester Android/iOS après chaque lot pour éviter les régressions natives.

## 5. Critères d'acceptation

- Le build Web aboutit.
- Les trois bases SQLite s'ouvrent et persistent les données après refresh.
- Les migrations et transactions SQL passent sur navigateur.
- Les caches Hive/Stories/médias sont persistants selon la politique prévue.
- Les actions hors ligne restent dans une outbox récupérable et isolée.
- Après logout A/login B, aucune donnée privée de A n'est visible.
- Deux onglets ne corrompent pas les données ni ne doublonnent les synchronisations.
- Les vidéos lourdes ne sont pas téléchargées intégralement sans limite.
- Le worker PWA n'intercepte pas les réponses privées Supabase de façon générique.
- Les parcours natifs restent fonctionnels.

## 6. Limites de cet audit

Cet audit est une inspection statique du dépôt GitHub. Aucun build Flutter, test navigateur, test sur appareil, mesure de quota IndexedDB ni inspection des outils développeur du navigateur n'a été exécuté. Les capacités exactes des plugins tiers sur Web restent à confirmer à partir de leurs versions verrouillées et d'un build réel.
