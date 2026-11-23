# Profil culturel Scrole — plan de travail

Branche cible : `feature/story-video-post-reshare`

## 1. Décision validée et périmètre

La première version du profil culturel couvre **uniquement les animes et les mangas**. Le fournisseur du catalogue est **Jikan API** (`https://api.jikan.moe/v4`), API non officielle donnant accès aux données de MyAnimeList.

Fonctionnalités prévues :
- recherche et consultation des fiches anime et manga ;
- jusqu'à 5 favoris (Top 5) pour les animes et jusqu'à 5 pour les mangas ;
- jusqu'à 5 titres « En cours » au total, anime et manga confondus ;
- suivi de progression : épisode pour un anime, chapitre et/ou volume pour un manga, selon les données disponibles ;
- historique « Terminés » sans limite artificielle ;
- écran intermédiaire « Éditer mon profil » avec deux choix : informations personnelles et profil culturel ;
- affichage des listes culturelles sur le profil public, dans le respect de la visibilité du profil.

Chaque catégorie peut rester vide. L'utilisateur peut modifier ses listes à tout moment.

Hors périmètre explicite de cette phase :
- films et séries TV ;
- publication Cosplay et sélection de personnages dans les publications ;
- classement des cosplayers ;
- règles d'accès aux communautés fondées sur les goûts culturels.

## 2. Fournisseur et précautions

### Jikan

- API : `https://api.jikan.moe/v4`
- Documentation : `https://docs.api.jikan.moe/`
- Recherche et détails anime/manga via les endpoints Jikan correspondants.
- Normaliser les réponses dans le modèle interne de Scrole.
- Respecter les limites de débit, les conditions d'utilisation et les recommandations de cache de Jikan.
- Jikan est une API non officielle de MyAnimeList : ne pas la présenter comme une API officielle MyAnimeList.
- Les URL d'images fournies par le catalogue ne constituent pas, à elles seules, une garantie de droits de réutilisation. Vérifier les conditions applicables avant l'affichage en production ; prévoir un visuel de remplacement si une image est indisponible ou ne peut pas être utilisée.

Aucune clé secrète ne doit être embarquée dans l'application. Les appels externes passent par le serveur Supabase afin de centraliser validation, cache et limitation de débit.

## 3. Architecture des données

Réutiliser les tables et modèles existants s'ils couvrent déjà tout ou partie du besoin. Ne créer aucune table en doublon avant l'audit du schéma Supabase.

### Catalogue normalisé — proposition

`cultural_media_catalog`
- `id uuid primary key`
- `media_type`: `anime | manga`
- `provider`: `jikan`
- `provider_id text` : identifiant Jikan
- `title`, `original_title`, `synopsis`
- `poster_url text nullable`
- `release_year integer nullable`
- `metadata jsonb` : genres, statut, format, auteurs, volumes, chapitres, épisodes et autres données utiles
- `created_at`, `updated_at`
- unicité sur (`provider`, `media_type`, `provider_id`)

### Listes des utilisateurs — proposition

`user_cultural_media`
- `id uuid primary key`
- `user_id uuid references auth.users`
- `media_id uuid references cultural_media_catalog`
- `list_type`: `top_favorite | watching | completed`
- `rank smallint nullable` : rang 1 à 5 pour les favoris
- `progress_episode integer nullable`
- `progress_chapter integer nullable`
- `progress_volume integer nullable`
- `started_at timestamptz nullable`, `completed_at timestamptz nullable`
- `created_at`, `updated_at`
- unicité adaptée pour empêcher les doublons dans une même liste.

### Règles métier à faire respecter côté base

- maximum 5 favoris anime par utilisateur ;
- maximum 5 favoris manga par utilisateur ;
- maximum 5 titres en cours par utilisateur, tous types confondus ;
- historique terminé sans limite ;
- un même titre ne peut pas être simultanément « En cours » et « Terminé » ;
- rangs Top 5 uniques et compris entre 1 et 5 dans chaque catégorie ;
- progression non négative et cohérente avec le type de média.

Les limites doivent être garanties côté PostgreSQL par des opérations transactionnelles (RPC et/ou trigger avec verrouillage approprié), pas uniquement par l'interface Flutter. Activer RLS sur les tables exposées. Les utilisateurs ne peuvent modifier que leurs propres listes ; la lecture publique doit respecter la visibilité du profil. Vérifier les politiques existantes avant toute modification.

## 4. API serveur Supabase

Créer, après audit des Edge Functions existantes, les fonctions suivantes ou étendre les fonctions déjà présentes :

- `cultural-catalog-search` : valide le type (`anime` ou `manga`) et la requête, appelle Jikan, normalise les résultats et renvoie une liste paginée ;
- `cultural-catalog-details` : récupère les détails d'un titre sélectionné et met à jour le cache catalogue ;
- opérations sécurisées de gestion des listes : ajouter, retirer, réordonner les favoris, passer un titre en cours ou terminé, mettre à jour la progression.

Exigences :
- cache serveur pour réduire les appels à Jikan ;
- limitation de débit et gestion des erreurs/temporisations ;
- déduplication par identifiant Jikan et type de média ;
- validation stricte des entrées ;
- aucune clé ou secret dans Flutter ;
- une panne de Jikan ne doit pas empêcher de consulter les titres déjà enregistrés.

## 5. Parcours et écrans Flutter

### A. Hub d'édition du profil

Au clic sur « Éditer mon profil », ouvrir un écran de choix :
1. « Informations personnelles » : reprend exactement le parcours actuel ;
2. « Profil culturel » : ouvre le nouvel éditeur.

Ne pas régresser l'édition du profil existante.

### B. Éditeur culturel

- Deux sections : Anime et Manga.
- Recherche avec champ de saisie, chargement, états vides et gestion d'erreur.
- Résultats avec affiche, titre, année et résumé disponible.
- Fiche de détail avant ou pendant l'ajout.
- Gestion du Top 5 : ajouter, retirer et réordonner.
- Section transversale « En cours » : maximum 5 titres au total.
- Progression adaptée : épisode pour anime ; chapitre/volume pour manga.
- Section « Terminés » : historique consultable et sans plafond artificiel.
- États de chargement, absence d'image, absence de résultat et indisponibilité réseau.

### C. Profil public

Afficher, selon les réglages de confidentialité :
- Top 5 Anime ;
- Top 5 Manga ;
- titres en cours et leur progression ;
- historique des titres terminés, avec pagination ou chargement progressif.

L'affichage doit rester cohérent avec le thème clair/sombre et le design actuel de Scrole.

## 6. Ordre de réalisation

1. **Audit du projet** : retrouver les routes, écrans, contrôleurs GetX, modèles et composants du profil ; examiner les tables, politiques RLS, RPC et Edge Functions Supabase existantes. Identifier ce qui peut être réutilisé.
2. **Conception finale des données** : valider le schéma après l'audit, écrire les règles de validation et les cas de migration.
3. **Backend Supabase** : migration SQL, index, contraintes, RLS et RPC transactionnelles ; vérifier les accès propriétaire/public.
4. **Intégration Jikan** : Edge Functions de recherche et détail, normalisation, cache, pagination, limitation de débit et tests d'erreurs.
5. **Éditeur Flutter** : hub « Éditer mon profil », sections Anime/Manga, Top 5, En cours et Terminés.
6. **Profil public** : affichage des listes, progression et historique paginé.
7. **Tests et stabilisation** : tests unitaires, intégration Supabase et parcours Web/Android ; corriger les régressions avant livraison.

## 7. Critères d'acceptation

- L'utilisateur peut laisser Anime ou Manga vide.
- Il ne peut pas dépasser 5 favoris dans une catégorie, ni 5 titres en cours au total, y compris en contournant l'interface.
- L'historique terminé n'est pas limité à 5.
- Un titre ne figure pas simultanément dans « En cours » et « Terminé ».
- La progression anime/manga est correctement enregistrée et restaurée.
- Les données persistent après déconnexion/reconnexion et sont synchronisées entre appareils.
- Le profil public respecte les paramètres de confidentialité.
- Une panne de Jikan ne masque pas les titres déjà enregistrés.
- Aucun secret serveur n'est présent dans le code Flutter.
- Les images indisponibles ou non autorisées ont un affichage de remplacement.
- Les parcours fonctionnent sur Android et sur le Web.

## 8. Première étape à exécuter

Commencer par l'audit du profil Flutter et du schéma Supabase sur la branche cible. À cette étape, ne pas modifier les écrans ni la base : produire l'inventaire des composants réutilisables, des tables et des fonctions existantes, puis arrêter les choix de schéma définitifs avant la migration.
