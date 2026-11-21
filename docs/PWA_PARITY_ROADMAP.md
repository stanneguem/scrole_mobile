# Scrole — feuille de route de parité Mobile / Web PWA

- Dépôt : `stanneguem/scrole_mobile` (projet Scrole)
- Branche de référence : `feature/story-video-post-reshare`
- Snapshot inspecté : `e3a78c174385ca2d07c8ba036623d2b73c74288a`
- Nature de l'audit : inspection statique GitHub. Aucun build, test navigateur ou test appareil n'a été exécuté dans cet audit.

## 1. Objectif

Obtenir une PWA qui couvre les mêmes parcours métier que les applications Android/iOS, avec des adaptations explicites quand le navigateur ne fournit pas une capacité native.

Règle d'architecture :
- logique métier, règles d'accès, contrats de données et états d'interface partagés ;
- implémentations de stockage, fichiers, médias, notifications et capacités système adaptées à la plateforme ;
- sélection des implémentations dans une couche plateforme, pas des branches `kIsWeb` dispersées dans les écrans ;
- Supabase reste la source de vérité distante ; le stockage local est un cache et/ou une file d'attente, jamais une seconde source de vérité concurrente.

## 2. Constat initial

### Déjà présent dans le dépôt
- Sélection conditionnelle de la factory SQLite Web avec `sqflite_common_ffi_web`, SQLite/WASM et IndexedDB.
- Service Hive rapide partagé et box dédiée `pending_chat_media`.
- Façades/implémentations conditionnelles pour plusieurs caches de médias, images et stories.
- Upload multiplateforme via `XFile` / `MediaAsset` dans une partie du pipeline R2.
- Stockage des pièces jointes sortantes de chat en chunks Hive, avec reprise via outbox.
- Manifest PWA, icônes, worker SQLite et fichier WASM.
- Service de notifications Realtime Web distinct du service de notifications natives.

### Incomplet, à confirmer ou explicitement documenté comme limite
- Plusieurs parcours de sélection, prévisualisation, édition et upload utilisent encore `File`, `Image.file`, `FileImage` ou des APIs natives.
- Le cache Stories historique et certains caches Scut/médias ont encore des chemins natifs ou des stubs Web limités.
- Le cache vidéo feed natif est un cache fichier ; le Web lit la source distante et ne possède pas encore une politique équivalente de cache média persistant.
- Les bases SQLite multiples (principale, salons, messagerie directe) nécessitent des tests Web réels : migrations, transactions, refresh, multi-onglets et concurrence.
- Les clés Hive et curseurs de synchronisation doivent être vérifiés pour leur isolation par utilisateur.
- Les opérations hors ligne et leur nettoyage au logout doivent être validés sans perdre une outbox légitime ni exposer les données du compte précédent.
- Les notifications push navigateur ne sont pas configurées selon `WEB_SETUP.md`.
- Le moteur Rust/OpenMLS E2EE doit être compilé et validé en WebAssembly avant d'activer le chiffrement sur navigateur.
- Les routes profondes nécessitent les règles de réécriture de l'hébergeur.
- Le worker SQLite ne remplace pas un service worker PWA applicatif. Le cycle de vie PWA (précache, versions, mises à jour) reste à concevoir et tester.
- Certaines fonctions natives (caméra, galerie complète, crop/trim, sauvegarde/partage, scanner QR, appels éventuels) devront avoir une alternative Web ou un état d'indisponibilité explicite.

## 3. Architecture cible

### Contrats transversaux
1. `PlatformCapabilities` : capacités disponibles (sélection fichier, caméra, notifications push, partage, stockage persistant, etc.).
2. `CacheStore` : get/set/remove/clear/préfixe/TTL.
3. `UserScopedStore` : namespace et purge explicite par compte.
4. `MediaStore` : bytes/stream + nom + MIME + taille + métadonnées ; aucune API publique dépendante de `dart:io File`.
5. `MediaPicker/MediaProcessor` : sélection, aperçu, crop, compression et conversion avec résultat explicite (pas de faux succès si une opération n'est pas effectuée).
6. `OfflineQueue/SyncCoordinator` : outbox durable, idempotence, retry, ordre et isolation par utilisateur.
7. `NotificationGateway` : Realtime commun côté métier, push natif ou Web Push côté plateforme.
8. `DatabasePlatformFactory` : conserve les DAO et le schéma communs, sélectionne seulement le moteur/factory.

### Politique de stockage
- Données définitives : Supabase.
- Données structurées locales : SQLite derrière les DAO existants, après validation du moteur Web.
- Cache clé/valeur : contrat commun, Hive conservé tant que ses garanties Web sont validées.
- Pièces jointes en attente : stockage binaire durable et segmenté, isolé par utilisateur, avec quota et collecte des orphelins.
- Médias téléchargés : fichiers natifs sur mobile ; Cache Storage/IndexedDB/Blob URL sur Web selon taille, confidentialité et quota.
- Secrets/clefs : stockage sécurisé natif et stratégie Web explicitement revue pour XSS et contraintes navigateur.
- Ne jamais mettre en cache génériquement les réponses privées/authentifiées de Supabase dans le service worker PWA.

## 4. Ordre de travail — un lot validé avant le suivant

| Ordre | Fonctionnalité / lot | Résultat attendu | Priorité |
|---|---|---|---|
| 0 | Socle plateforme et diagnostic | Build Web de référence, inventaire imports/plugins, capacités et tests de base | Bloquant |
| 1 | Stockage, cache et session | Cache commun, isolation compte, purge/logout, multi-onglets, persistance | Bloquant |
| 2 | Stories | Lecture, images/vidéos, création, édition, vues, cache, expiration, reprise | Très haute |
| 3 | Fil d'actualité et publications | Pagination, cache 15 cartes, images/vidéos, création, réactions, commentaires, partage/repost | Très haute |
| 4 | Profil | Avatar/couverture, édition, posts, abonnements, cache-first et refresh | Haute |
| 5 | Messagerie directe | Texte, images, vidéos, audio, pièces jointes, outbox/offline, E2EE Web | Très haute |
| 6 | Communautés | Découverte, adhésion, rôles, publications, médias, chat et cache | Haute |
| 7 | Événements et activités | Création/édition, médias, inscriptions, QR, check-in, statistiques | Haute |
| 8 | Notifications | In-app Realtime, Web Push, permissions, clics et navigation | Haute |
| 9 | Découverte, recherche et navigation | Recherche, suggestions, liens profonds, routes directes et historique | Moyenne |
| 10 | Paramètres et fonctions appareil | Préférences, langue, confidentialité, rapports, partage, téléchargements | Moyenne |
| 11 | PWA production | Installation, offline shell, mises à jour, cache versionné, observabilité et déploiement | Final |

Les fonctionnalités peuvent être réordonnées selon les blocages révélés au lot 0, mais le socle de stockage/session doit être validé avant de multiplier les caches par module.

## 5. Méthode obligatoire pour chaque fonctionnalité

Chaque lot suit exactement ce cycle :

1. **Référence mobile** : relever le parcours Flutter, contrôleurs, services, repositories, modèles, règles métier et comportement attendu.
2. **État Web réel** : relever les implémentations conditionnelles, APIs indisponibles, stubs et différences.
3. **Contrat commun** : décider ce qui doit être mutualisé et définir les frontières plateforme.
4. **Plan court** : fichiers touchés, risques, migrations de données et critères d'acceptation.
5. **Implémentation** : petites étapes cohérentes, sans réécriture globale.
6. **Tests** : tests unitaires/DAO, build Web, parcours navigateur et régression Android/iOS.
7. **Clôture** : noter les limites restantes, commit, preuve de validation et passage au lot suivant.

Une fonctionnalité n'est pas « terminée » parce que l'écran s'affiche. Elle est terminée quand ses parcours nominaux, erreurs, permissions, cache, mode hors ligne pertinent, reprise de session et isolation des comptes ont été testés.

## 6. Porte de validation du lot 0

Avant la première migration fonctionnelle :
- relever la version Flutter/Dart et les dépendances verrouillées ;
- exécuter `flutter analyze`, tests existants, `flutter build web --release` et un build Android de contrôle ;
- ouvrir les trois bases locales, vérifier migrations, transactions, refresh et deux onglets ;
- dresser la liste complète des imports `dart:io`, `File`, `Image.file`, `FileImage`, plugins sans support Web et stubs Web ;
- tester logout compte A puis login compte B ;
- vérifier routes profondes, chargement WASM et persistance après fermeture/réouverture ;
- consigner chaque échec avec fichier, stack trace, reproductibilité et plateforme.

Aucun résultat de ces commandes n'est présumé dans ce document : ils doivent être exécutés dans l'environnement de développement.

## 7. Estimation initiale

Estimation de planification, à confirmer après le lot 0 :
- socle et audit exécutable : 3–5 jours ;
- stockage/cache/session : 4–7 jours ;
- stories et feed/publications : 1–2 semaines ;
- profil, chat et communautés : 2–3 semaines ;
- événements, notifications et fonctions appareil : 1–2 semaines ;
- PWA production, tests multi-navigateurs et stabilisation : 1–2 semaines.

Ordre de grandeur global : 6–10 semaines pour un développeur principal expérimenté, si les services backend sont prêts et si les blocages E2EE/natifs restent maîtrisables. Les tests réels peuvent modifier cette estimation. Ce n'est pas une promesse de délai.

## 8. Suivi

- [ ] Lot 0 — socle plateforme et diagnostic
- [ ] Lot 1 — stockage, cache et session
- [ ] Lot 2 — stories
- [ ] Lot 3 — feed et publications
- [ ] Lot 4 — profil
- [ ] Lot 5 — messagerie directe
- [ ] Lot 6 — communautés
- [ ] Lot 7 — événements et activités
- [ ] Lot 8 — notifications
- [ ] Lot 9 — découverte et navigation
- [ ] Lot 10 — paramètres et fonctions appareil
- [ ] Lot 11 — PWA production

Chaque case ne sera cochée qu'après validation documentée.
