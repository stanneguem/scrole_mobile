# Profil culturel Scrole — préparation de l'implémentation

Branche cible : `feature/story-video-post-reshare`

## Décision de périmètre

Cette première phase livre uniquement le catalogue culturel et le profil culturel :
- recherche et sélection d'animes, mangas, films et séries ;
- jusqu'à 5 favoris (Top 5) par catégorie : anime, manga, film, série ;
- jusqu'à 5 titres en cours au total, avec saison/épisode pour les séries lorsque disponibles ;
- historique terminé sans limite artificielle ;
- écran intermédiaire « Éditer mon profil » avec deux entrées : informations du profil et profil culturel ;
- affichage public des listes culturelles sur le profil.

Hors périmètre de cette phase : publication Cosplay, classement des cosplayers et règles d'accès communautaires.

## Fournisseurs et licences

### Anime et manga
Jikan (API non officielle MyAnimeList) : `https://api.jikan.moe/v4`.
Utiliser les endpoints de recherche et de détail pour anime, manga et personnages. Mettre en cache les réponses et appliquer une limitation côté serveur. Jikan n'est pas une source de droits sur les visuels : conserver les URL d'images comme références du fournisseur, sous réserve de ses conditions applicables.

### Films et séries
Ne pas utiliser la licence développeur gratuite TMDB dans Scrole : TMDB précise qu'elle est réservée aux usages non commerciaux et qu'un projet commercial doit obtenir un accord séparé.
Piste privilégiée à contractualiser : TheTVDB, qui propose des clés API licenciées pour les projets commerciaux et des tarifs/contrats selon l'usage. Attention : la licence API ne donne pas automatiquement les droits sur les images, bandes-annonces ou programmes ; les droits des visuels doivent être vérifiés séparément.
TVmaze est une solution alternative pour les séries TV : son offre Startup indique une licence CC BY avec attribution, mais elle ne couvre pas à elle seule le catalogue de films.
Ne pas activer de fournisseur films/séries en production tant que les conditions écrites, l'attribution, les droits d'images et le tarif applicables à Scrole ne sont pas validés.

## Architecture proposée

### Modèle unifié

Une table catalogue normalisée permet de ne pas lier les listes utilisateur à un fournisseur particulier.

`cultural_media_catalog`
- `id uuid primary key`
- `media_type`: `anime | manga | movie | tv_series`
- `provider`: `jikan | thetvdb | tvmaze | wikidata | manual`
- `provider_id text`
- `title`, `original_title`, `synopsis`
- `poster_url` nullable, `poster_rights_status` nullable
- `release_year`, `metadata jsonb`
- `created_at`, `updated_at`
- contrainte unique (`provider`, `media_type`, `provider_id`)

`user_cultural_media`
- `id uuid primary key`
- `user_id uuid references auth.users`
- `media_id uuid references cultural_media_catalog`
- `list_type`: `top_favorite | watching | completed`
- `rank smallint nullable` (1 à 5 uniquement pour Top 5)
- `season_number integer nullable`
- `episode_number integer nullable`
- `started_at timestamptz nullable`, `completed_at timestamptz nullable`
- `created_at`, `updated_at`
- unicité utilisateur/média/liste ; index sur utilisateur, liste et rang.

Contraintes métier :
- maximum 5 entrées `top_favorite` par utilisateur et par `media_type` ;
- maximum 5 entrées `watching` par utilisateur, tous types confondus ;
- aucune limite de nombre pour `completed` ;
- un titre ne peut pas être simultanément `watching` et `completed` ;
- le rang Top 5 est unique dans une catégorie pour un utilisateur.

Les limites doivent être imposées dans PostgreSQL (fonction transactionnelle/trigger avec verrouillage par utilisateur ou RPC dédiée), pas uniquement dans Flutter. Les règles RLS doivent limiter la modification aux lignes du propriétaire et autoriser la lecture publique selon la visibilité du profil.

### Recherche catalogue

Créer une couche serveur Supabase Edge Functions :
- `cultural-catalog-search` : valide le type et la requête, interroge le fournisseur autorisé, normalise les résultats ;
- `cultural-catalog-details` : récupère/complète les détails d'un titre sélectionné ;
- cache serveur des réponses et limitation de débit ;
- clés API conservées dans les secrets Supabase, jamais dans l'application ;
- identifiants fournisseur conservés pour permettre migration et déduplication ;
- ne pas aspirer massivement les catalogues : recherche à la demande et cache borné.

### Interface Flutter

1. Transformer l'action « Éditer mon profil » en écran de choix :
   - « Informations personnelles » : ouvre le parcours existant sans régression ;
   - « Profil culturel » : ouvre le nouvel éditeur.
2. Éditeur culturel avec onglets/sections Anime, Manga, Films, Séries.
3. Dans chaque catégorie : recherche, résultats, ajout au Top 5, réorganisation du Top 5, retrait.
4. Section « En cours » transversale, maximum cinq titres, progression saison/épisode lorsque disponible.
5. Section « Déjà vus / terminés » avec ajout et retrait, sans plafond artificiel.
6. Affichage public compact sur le profil : Top 5 par catégorie, titres en cours et historique consultable avec pagination.

## Ordre d'implémentation

1. Vérifier les écrans profil existants, les conventions GetX, les modèles et le schéma Supabase déjà présents afin de réutiliser les composants.
2. Valider par écrit la licence fournisseur films/séries et les droits d'affichage des affiches.
3. Ajouter migration SQL, contraintes, index, RLS et RPC transactionnelles.
4. Développer les Edge Functions et tests de normalisation/cache/limites.
5. Développer l'éditeur culturel et l'écran intermédiaire sans casser l'édition actuelle.
6. Ajouter l'affichage public, pagination et cache local.
7. Tester Web + Android : limites concurrentes, doublons, suppression, changement de catégorie, profil privé/public, erreurs API et absence d'images.

## Critères d'acceptation

- Un utilisateur peut compléter seulement certaines catégories.
- Impossible d'enregistrer un sixième favori dans une catégorie ou un sixième titre en cours, même en appelant directement l'API.
- L'historique terminé n'est pas limité à cinq.
- Les listes restent intactes après déconnexion/reconnexion et sont visibles sur un autre appareil.
- Une panne du fournisseur n'empêche pas l'affichage des titres déjà enregistrés.
- Aucun secret fournisseur n'est embarqué dans le client.
- Les affiches ne sont affichées que si leur usage est autorisé et traçable.

## Prérequis avant activation du catalogue films/séries

Obtenir et archiver :
- accord/licence commerciale couvrant l'usage de Scrole et son modèle économique ;
- barème, quotas, SLA et conditions de cache ;
- droits explicites sur les images/posters ou stratégie sans posters ;
- règles d'attribution à afficher dans « À propos / Crédits ».
