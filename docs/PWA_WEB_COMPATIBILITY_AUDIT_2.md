# Audit de compatibilité Web/PWA — phase 2

Branche auditée : `feature/story-video-post-reshare`

Cet audit est statique : les fichiers ont été consultés sur GitHub. Aucun `flutter analyze`, `flutter build web` ni test navigateur n'a été exécuté.

## Correctifs appliqués pendant cette phase

- `lib/shared/widgets/app_cached_image.dart` est devenu une façade à export conditionnel.
- L'ancienne implémentation native a été conservée dans `app_cached_image_io.dart`.
- `app_cached_image_stub.dart` fournit une implémentation Web sans `dart:io`, avec résolution des clés R2 en URL de lecture et affichage réseau. Le cache fichier natif reste réservé à Android/iOS.
- `account_initialization_service.dart` n'utilise plus `Platform.isAndroid/Platform.isIOS` ni `dart:io`; la plateforme est détectée avec `kIsWeb` et `defaultTargetPlatform`.

## Blocages Web encore identifiés

### Priorité 0 — chaîne média et types de fichiers

Ces fichiers contiennent encore des API de fichiers natifs ou dépendent de types `File` dans des parcours centraux :

- `lib/app/service_global/media_service.dart` — `dart:io`, `File`, `path_provider`, compression/crop basés sur chemins.
- `lib/app/repository_global/storage_repository.dart` — API publique fondée sur `File`.
- `lib/app/repository_global/r2_media_repository.dart` — lecture `File` et déduction du MIME via chemin.
- `lib/modules/module_creation_de_compte/interne/controllers/create_account_controller.dart` — états `Rxn<File>`, import `dart:io`.
- `lib/modules/module_principale/interne/controllers/stories_controller.dart` — cache JSON natif, compression et upload à partir de `File`.
- `lib/modules/module_principale/interne/pages/create_story_screen.dart` et `story_image_editor_screen.dart` — sélection/édition basée sur `File`.
- `lib/modules/module_principale/interne/pages/create_scut_camera_screen.dart` et `scut_sticker_editor_screen.dart` — fichiers locaux et traitement média natif.
- `lib/modules/module_communautes/interne/pages/create_community_post_screen.dart` et `create_community_screen.dart` — fichiers locaux et `Image.file`.
- `lib/modules/module_evenement/interne/controllers/create_event_controller.dart` et `edit_event_controller.dart` — import `dart:io`; écrans associés utilisent `FileImage`.

**Décision d'architecture nécessaire :** faire transiter la sélection et l'upload par `XFile` ou `Uint8List` + nom/MIME, et garder les opérations chemin/compresseur natif derrière des implémentations conditionnelles. Ne pas remplacer seulement les types dans un seul fichier : tous les appelants et les flux d'upload doivent migrer ensemble.

### Priorité 1 — affichage et cache local

- `lib/modules/module_principale/interne/pages/story_viewer_screen.dart` — cache Story avec `File`/répertoires natifs.
- `lib/shared/widgets/media_full_screen_page.dart` — `File.existsSync` et `Image.file` pour les médias locaux.
- `lib/modules/module_discussion_direct/interne/pages/chat_media_viewer_screen.dart` — vérifications `File`, `Image.file`, `VideoPlayerController.file`.
- `lib/shared/widgets/video_full_screen_viewer.dart` — contrôleur vidéo basé sur `File`.
- `lib/shared/widgets/video_trim_screen.dart` — fichiers de sortie et `Image.file`.
- `lib/shared/widgets/app_cached_image.dart` a été traité par séparation native/Web, mais le rendu Web ne peut pas afficher un ancien chemin local natif : ses appelants doivent fournir une URL ou un média navigateur.
- `lib/shared/widgets/cover_avatar_picker.dart` utilise encore `FileImage`; son usage doit être confirmé avant migration.

### Priorité 2 — fonctionnalités natives à adapter ou désactiver proprement sur Web

- `lib/shared/widgets/media_gallery_sheet.dart` — dépend de `PhotoManager` et de la galerie native ; prévoir un sélecteur Web basé sur `ImagePicker`/fichiers navigateur.
- `lib/app/service_global/media_service.dart` — `ImageCropper` et `FlutterImageCompress` doivent avoir une stratégie Web (API navigateur ou fallback sans compression).
- `lib/modules/module_parametre/interne/controllers/bug_report_controller.dart` et `bug_report_screen.dart` — capture jointe stockée comme `File`.
- `lib/modules/module_discussion_direct/interne/controllers/chat_controller.dart` — génération de fichiers temporaires avec `path_provider`; vérifier et brancher l'implémentation Web.

## Ordre de migration recommandé

1. Remplacer le contrat de média partagé par `XFile`/octets/MIME et migrer `R2MediaRepository` + `StorageRepository`.
2. Adapter `MediaService` et la sélection de médias Web.
3. Migrer les contrôleurs de création (compte, Story, Scut, communauté, événement) sans casser les parcours natifs.
4. Séparer les caches et viewers natifs/Web pour Stories, chat et médias plein écran.
5. Lancer `flutter analyze`, `flutter build web`, puis des tests navigateur (sélection, upload, lecture, cache, logout, quota/CORS).

## Point de vigilance

Un import `dart:io` peut rester dans un fichier natif séparé importé conditionnellement. En revanche, un import direct dans un fichier commun atteint par les routes Web empêche la compilation Web, même si le code concerné est protégé par `if (kIsWeb)`.
