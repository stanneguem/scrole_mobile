import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:scrole/app/repository_global/storage_repository.dart';
import 'package:scrole/app/service_global/media_service.dart';
import 'package:scrole/app/service_global/centre_interrets_service.dart';
import 'package:scrole/shared/models/interest_model.dart';
import 'package:scrole/app_controller.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/modules/module_principale/interne/enums/community_role_enum.dart';
import 'package:scrole/shared/models/post_media.dart';
import '../../../module_discussion_direct/externe/repositories/social_repository.dart';

class ProfileController extends GetxController {
  late final AppController _appController;
  late final MediaService _mediaService;
  late final StorageRepository _storageRepository;
  late final InterestService _interestService;

  // ============================================
  // USER DATA (dérivées du profil d'AppController)
  // ============================================

  final RxString userId = ''.obs;
  final RxString username = ''.obs;
  final RxString nom = ''.obs;
  final RxString prenom = ''.obs;
  final RxString fullName = ''.obs;
  final RxString email = ''.obs;
  final RxString avatarUrl = ''.obs;
  final RxString coverUrl = ''.obs;
  final RxString bio = ''.obs;
  final RxString country = ''.obs;
  final RxString city = ''.obs;
  final RxString gender = ''.obs;
  final RxInt ageValue = 0.obs;
  final Rx<DateTime?> birthDate = Rxn<DateTime>();
  final Rx<DateTime?> usernameUpdatedAt = Rxn<DateTime>();
  final Rx<DateTime?> genderUpdatedAt = Rxn<DateTime>();
  final Rx<DateTime?> locationUpdatedAt = Rxn<DateTime>();
  final Rx<DateTime?> birthDateUpdatedAt = Rxn<DateTime>();
  final RxString accountStatus = ''.obs;
  final RxString createdAt = ''.obs;
  final RxString lastSignInAt = ''.obs;
  final RxBool isVerified = false.obs;
  final RxBool isLoading = false.obs;
  final RxInt followersCount = 0.obs;
  final RxInt followingCount = 0.obs;
  final RxInt friendsCount = 0.obs;

  final RxList<Interest> userInterests = <Interest>[].obs;

  // ============================================
  // TABS & POSTS / EVENTS
  // ============================================

  final RxInt selectedTab = 0.obs;
  final RxList<CommunityPost> userPosts = <CommunityPost>[].obs;
  final RxList<dynamic> userEvents = <dynamic>[].obs;
  final RxList<CommunityPost> savedPosts = <CommunityPost>[].obs;

  // ============================================
  // COVER & PROFILE IMAGE
  // ============================================

  final RxString coverImageUrl = ''.obs;
  final RxString profileImageUrl = ''.obs;
  final RxBool isUploadingCover = false.obs;
  final RxBool isUploadingProfileImage = false.obs;

  Worker? _profileWorker;
  RealtimeChannel? _relationshipChannel;

  @override
  void onInit() {
    super.onInit();
    _appController = Get.find<AppController>();
    _mediaService = Get.find<MediaService>();
    _interestService = Get.find<InterestService>();
    _storageRepository = StorageRepository();
    
    _applyProfileOrDefaults(_appController.profile.value);
    _profileWorker = ever(_appController.profile, (data) {
      _applyProfileOrDefaults(data);
      unawaited(_loadFollowStats());
    });
    unawaited(_loadFollowStats());
    _subscribeToRelationshipChanges();

    // Mock initial user posts & saved items
    userPosts.value = [
      CommunityPost(
        id: 'my_post_1',
        authorName: 'Moi',
        authorId: 'me',
        authorColor: Colors.purple,
        authorRole: CommunityRole.admin,
        timeAgo: '1 j',
        content: 'Superbe journée partagée avec la communauté ! 🚀',
        likeCount: 45,
        commentCount: 4,
        shareCount: 2,
        media: [
          PostMedia(type: 'photo', url: 'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=600&auto=format&fit=crop'),
        ],
      ),
      CommunityPost(
        id: 'my_post_2',
        authorName: 'Moi',
        authorId: 'me',
        authorColor: Colors.purple,
        authorRole: CommunityRole.admin,
        timeAgo: '3 j',
        content: 'Nouveau projet en cours de développement avec Flutter et Supabase. Restez connectés ! 💻',
        likeCount: 92,
        commentCount: 12,
        shareCount: 7,
        media: [
          PostMedia(type: 'photo', url: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&auto=format&fit=crop'),
        ],
      ),
    ];

    savedPosts.value = [
      CommunityPost(
        id: 'saved_1',
        authorName: 'Sarah Koné',
        authorId: 'u_2',
        authorColor: Colors.blue,
        authorRole: CommunityRole.member,
        timeAgo: '5 j',
        content: 'Atelier design system et composants réutilisables.',
        likeCount: 150,
        commentCount: 19,
        media: [
          PostMedia(type: 'photo', url: 'https://images.unsplash.com/photo-1578632767115-351597cf2477?w=600&auto=format&fit=crop'),
        ],
      ),
    ];
  }

  void _subscribeToRelationshipChanges() {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null || uid.isEmpty) return;
    try {
      _relationshipChannel = Supabase.instance.client
          .channel('user:$uid', opts: const RealtimeChannelConfig(private: true))
          .onBroadcast(
            event: 'relationship_changed',
            callback: (payload) {
              debugPrint('[FOLLOW] relationship_changed self stats payload=$payload');
              unawaited(_loadFollowStats());
            },
          )
          ..subscribe();
    } catch (e, stack) {
      debugPrint('[FOLLOW] self relationship_changed subscription exception=$e\\n$stack');
    }
  }

  Future<void> _loadFollowStats() async {
    if (userId.value.isEmpty) return;
    try {
      final stats = await SocialRepository().getFollowStats();
      followersCount.value = (stats['followers_count'] as num?)?.toInt() ?? 0;
      followingCount.value = (stats['following_count'] as num?)?.toInt() ?? 0;
      friendsCount.value = (stats['friends_count'] as num?)?.toInt() ?? 0;
    } catch (e, stack) {
      debugPrint('[FOLLOW] get_follow_stats self exception=$e\\n$stack');
    }
  }

  void _applyProfileOrDefaults(Map<String, dynamic>? data) {
    if (data == null) {
      _setDefaultValues();
      return;
    }
    _updateUserData(data);
  }

  /// Met à jour les données utilisateur.
  /// Gère à la fois un payload plat (ancien format) et le nouveau
  /// payload backend imbriqué `{ privacy: {...}, profile: {...} }`.
  void _updateUserData(Map<String, dynamic> data) {
    try {
      final Map<String, dynamic> profileData =
      (data['profile'] is Map) ? Map<String, dynamic>.from(data['profile'] as Map) : data;

      userId.value = profileData['user_id']?.toString() ?? profileData['id']?.toString() ?? '';
      username.value = profileData['username']?.toString() ?? '';
      nom.value = profileData['last_name']?.toString() ?? profileData['nom']?.toString() ?? '';
      prenom.value = profileData['first_name']?.toString() ?? profileData['prenom']?.toString() ?? '';

      fullName.value = '${prenom.value} ${nom.value}'.trim();

      email.value = profileData['email']?.toString() ?? '';
      avatarUrl.value = profileData['photo_url']?.toString() ?? '';
      coverUrl.value = profileData['cover_url']?.toString() ?? '';
      bio.value = profileData['bio']?.toString() ?? '';

      // Gestion intelligente et stable des noms de pays/villes
      final nextCountry = _extractName(profileData['countries'] ?? profileData['pays']);
      if (nextCountry != null) {
        country.value = nextCountry;
      } else if (profileData['country_id'] != null && 
                 !country.value.contains('-') && 
                 country.value.isNotEmpty) {
        // On a déjà un nom en clair et on reçoit un ID (probablement via Realtime brute)
        // On ne fait rien pour éviter d'écraser le nom par l'ID technique.
      } else {
        country.value = profileData['country_id']?.toString() ?? '';
      }

      final nextCity = _extractName(profileData['cities'] ?? profileData['ville']);
      if (nextCity != null) {
        city.value = nextCity;
      } else if (profileData['city_id'] != null && 
                 !city.value.contains('-') && 
                 city.value.isNotEmpty) {
        // Idem pour la ville
      } else {
        city.value = profileData['city_id']?.toString() ?? '';
      }

      gender.value = profileData['gender']?.toString() ?? profileData['genre']?.toString() ?? '';
      
      accountStatus.value = profileData['account_status']?.toString() ?? 'active';

      // Date de création du compte : priorité absolue au 'created_at' de Supabase Auth (auth.users)
      final authCreatedAt = _appController.authUser.value?.createdAt;
      createdAt.value = authCreatedAt ?? 
          profileData['account_created_at']?.toString() ??
          profileData['created_at']?.toString() ??
          '';

      lastSignInAt.value = profileData['last_sign_in_at']?.toString() ?? '';

      coverImageUrl.value = profileData['cover_url']?.toString() ?? '';
      profileImageUrl.value = profileData['photo_url']?.toString() ?? '';

      if (profileData['age'] != null) {
        ageValue.value = int.tryParse(profileData['age'].toString()) ?? 0;
      }

      if (profileData['birth_date'] != null || profileData['date_de_naissance'] != null) {
        try {
          final birthStr = (profileData['birth_date'] ?? profileData['date_de_naissance']).toString();
          birthDate.value = DateTime.parse(birthStr);
        } catch (e) {
          debugPrint('Erreur parse date naissance: $e');
        }
      }

      // Mappage des dates de verrouillage
      usernameUpdatedAt.value = _parseDate(profileData['username_updated_at']);
      genderUpdatedAt.value = _parseDate(profileData['gender_updated_at']);
      locationUpdatedAt.value = _parseDate(profileData['location_updated_at']);
      birthDateUpdatedAt.value = _parseDate(profileData['birth_date_updated_at']);

      isVerified.value = profileData['account_status'] == 'active' && profileData['is_verified'] == true;
      
      if (userId.value.isNotEmpty) {
        _loadUserInterests();
      }
    } catch (e) {
      debugPrint('Erreur mise à jour données: $e');
    }
  }

  DateTime? _parseDate(dynamic data) {
    if (data == null) return null;
    try {
      return DateTime.parse(data.toString());
    } catch (_) {
      return null;
    }
  }

  String? _extractName(dynamic data) {
    if (data == null) return null;
    if (data is String) return data;
    if (data is Map) return data['nom']?.toString() ?? data['name']?.toString();
    return null;
  }

  void _setDefaultValues() {
    username.value = 'profile_default_username'.tr;
    nom.value = '';
    prenom.value = '';
    fullName.value = '';
    bio.value = '';
    avatarUrl.value = '';
    coverUrl.value = '';
    profileImageUrl.value = '';
    coverImageUrl.value = '';
    country.value = '';
    city.value = '';
    gender.value = '';
    email.value = '';
    createdAt.value = '';
    lastSignInAt.value = '';
    ageValue.value = 0;
    isVerified.value = false;
    accountStatus.value = 'active';
  }

  // ============================================
  // REFRESH
  // ============================================

  Future<void> refreshProfile() async {
    isLoading.value = true;
    await Future.wait([
      _appController.forceRefresh(),
      _loadUserInterests(),
    ]);
    if (Get.isRegistered<ProfileController>()) {
      isLoading.value = false;
    }
  }

  Future<void> _loadUserInterests() async {
    if (userId.value.isEmpty) return;
    try {
      final allInterests = await _interestService.getInterests();
      final userIntIds = await _interestService.getUserInterestIds(userId.value);
      
      userInterests.assignAll(
        allInterests.where((i) => userIntIds.contains(i.id)).toList(),
      );
    } catch (e) {
      debugPrint('Erreur chargement intérêts: $e');
    }
  }

  // ============================================
  // UPDATE PROFILE
  // ============================================

  Future<bool> updateProfile(Map<String, dynamic> data, {bool showLoading = true}) async {
    if (showLoading) isLoading.value = true;
    try {
      final updated = await _appController.updateProfile(data);

      if (updated != null) {
        Get.snackbar(
          'profile_success_title'.tr,
          'profile_success_update'.tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.green,
          colorText: Colors.white,
        );
        return true;
      }

      Get.snackbar(
        'profile_error_title'.tr,
        'profile_error_update'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red,
        colorText: Colors.white,
      );
      return false;
    } finally {
      if (showLoading && Get.isRegistered<ProfileController>()) {
        isLoading.value = false;
      }
    }
  }

  // ============================================
  // COVER IMAGE
  // ============================================

  Future<void> pickCoverImage(ImageSource source) async {
    try {
      final File? picked = await _mediaService.pickCoverImage(source: source);
      if (picked == null) return;

      isUploadingCover.value = true;
      final String uploadedUrl = await _storageRepository.uploadProfileCover(userId.value, picked);

      await updateProfile({'cover_url': uploadedUrl}, showLoading: false);
    } catch (e) {
      Get.snackbar(
        'profile_error_title'.tr,
        'profile_error_cover'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF1E1E22),
        colorText: Colors.white,
      );
    } finally {
      isUploadingCover.value = false;
    }
  }

  // ============================================
  // PROFILE IMAGE
  // ============================================

  Future<void> pickProfileImage(ImageSource source) async {
    try {
      final File? picked = await _mediaService.pickProfileImage(source: source);
      if (picked == null) return;

      isUploadingProfileImage.value = true;
      final String uploadedUrl = await _storageRepository.uploadProfilePicture(userId.value, picked);

      await updateProfile({'photo_url': uploadedUrl}, showLoading: false);
    } catch (e) {
      Get.snackbar(
        'profile_error_title'.tr,
        'profile_error_avatar'.tr,
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: const Color(0xFF1E1E22),
        colorText: Colors.white,
      );
    } finally {
      isUploadingProfileImage.value = false;
    }
  }

  // ============================================
  // GETTERS D'AFFICHAGE
  // ============================================

  String get displayName => fullName.value.isEmpty ? username.value : fullName.value;

  String get initials {
    if (displayName.isEmpty) return '?';
    final parts = displayName.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return displayName.substring(0, 1).toUpperCase();
  }

  /// Âge calculé à partir de la date de naissance (repli si le
  /// backend ne fournit pas directement `age`).
  String get age {
    if (birthDate.value == null) return '';
    final years = DateTime.now().difference(birthDate.value!).inDays ~/ 365;
    return years.toString();
  }

  /// Âge à afficher : priorité au champ `age` du backend.
  String get displayAge {
    if (ageValue.value > 0) return ageValue.value.toString();
    if (birthDate.value != null) return age;
    return '';
  }

  String get displayBio => bio.value.isEmpty ? 'profile_bio_empty'.tr : bio.value;

  String get displayCountry => country.value.isEmpty ? 'profile_not_specified'.tr : country.value;

  String get displayCity => city.value.isEmpty ? 'profile_not_specified'.tr : city.value;

  String get displayEmail => email.value.isEmpty ? 'profile_not_specified'.tr : email.value;

  String get displayGender {
    switch (gender.value.toLowerCase()) {
      case 'male':
      case 'homme':
        return 'profile_gender_male'.tr;
      case 'female':
      case 'femme':
        return 'profile_gender_female'.tr;
      case '':
        return 'profile_not_specified'.tr;
      default:
        return 'profile_gender_other'.tr;
    }
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '';
    try {
      final date = DateTime.parse(raw).toLocal();
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    } catch (_) {
      return '';
    }
  }

  String get formattedMemberSince {
    final formatted = _formatDate(createdAt.value);
    return formatted.isEmpty ? 'profile_not_specified'.tr : formatted;
  }

  String get formattedLastSignIn {
    final formatted = _formatDate(lastSignInAt.value);
    return formatted.isEmpty ? 'profile_not_specified'.tr : formatted;
  }

  @override
  void onClose() {
    _profileWorker?.dispose();
    final channel = _relationshipChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    super.onClose();
  }
}
