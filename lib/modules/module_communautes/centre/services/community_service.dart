import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:sqflite/sqflite.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../../app/repository_global/storage_repository.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../models/community_model.dart';
import '../persistence/community_local_dao.dart';
import '../../externe/repositories/community_repository.dart';
import 'community_outbox_processor.dart';
import '../models/news/community_hashtag.dart';
import '../../interne/controllers/community/community_feed_controller.dart';
import '../../interne/controllers/community/community_controller.dart';

class CommunityService extends GetxService with WidgetsBindingObserver {
  final CommunityRepository _repo;
  final StorageRepository? _storageRepo;
  late final CommunityLocalDao _dao = CommunityLocalDao(Get.find<AppDatabase>());
  final AuthService _authService = Get.find<AuthService>();

  RealtimeChannel? _userChannel;

  CommunityService([CommunityRepository? repo, this._storageRepo])
      : _repo = repo ?? CommunityRepository();

  Future<CommunityService> init() async {
    WidgetsBinding.instance.addObserver(this);
    if (!Get.isRegistered<CommunityOutboxProcessor>()) {
      Get.put(CommunityOutboxProcessor());
    }
    final userId = _authService.userId;
    if (userId != null) {
      listenRealtime(userId);
      await reconcileMyCommunities();
    }
    return this;
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    _userChannel?.unsubscribe();
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(reconcileMyCommunities());
    }
  }

  void listenRealtime(String userId) {
    if (_userChannel != null) return;
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null || session.isExpired) return;

    _userChannel = Supabase.instance.client
        .channel('user:$userId', opts: const RealtimeChannelConfig(private: true))
        .onBroadcast(
          event: 'community_membership_removed',
          callback: (payload) async {
            final communityId = payload['community_id']?.toString();
            if (communityId != null && communityId.isNotEmpty) {
              await handleCommunityMembershipRemoved(communityId);
            }
          },
        )
        .subscribe((status, [error]) {
          if (status == RealtimeSubscribeStatus.subscribed) {
            unawaited(reconcileMyCommunities());
          }
        });
  }

  Future<void> handleCommunityMembershipRemoved(String communityId) async {
    await _dao.deleteCommunity(communityId);
    try {
      if (Get.isRegistered<CommunityFeedController>()) {
        final feedCtrl = Get.find<CommunityFeedController>();
        if (feedCtrl.communityId == communityId) {
          Get.back();
        }
      } else if (Get.currentRoute.contains(communityId) || Get.currentRoute.contains('community_feed')) {
        Get.back();
      }
    } catch (_) {}

    Get.snackbar(
      'community_membership_removed_title'.tr,
      'community_membership_removed_msg'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );

    await reconcileMyCommunities();
  }

  bool _isReconciling = false;

  Future<void> reconcileMyCommunities() async {
    if (_isReconciling) return;
    _isReconciling = true;

    try {
      List<Map<String, dynamic>> remoteList = [];
      try {
        remoteList = await _repo.getMyCommunities();
      } catch (e) {
        return;
      }

      final remoteIds = remoteList.map((m) => m['id']?.toString()).where((id) => id != null && id.isNotEmpty).toSet();
      final now = DateTime.now().millisecondsSinceEpoch;
      final userId = _authService.userId ?? 'local_user';

      for (final map in remoteList) {
        final id = map['id']?.toString();
        if (id == null || id.isEmpty) continue;
        try {
          final existing = await _dao.getCommunity(id);
          final createdAt = existing?.createdAt ?? now;
          final rawSlug = map['slug']?.toString();
          final slug = (rawSlug != null && rawSlug.trim().isNotEmpty) ? rawSlug.trim() : id;

          final community = CommunityModel(
            id: id,
            name: map['name']?.toString() ?? '',
            slug: slug,
            description: map['description']?.toString(),
            avatarUrl: map['avatar_url']?.toString() ?? map['photo_profile']?.toString() ?? map['imageUrl']?.toString(),
            bannerUrl: map['banner_url']?.toString() ?? map['photo_cover']?.toString(),
            visibility: map['visibility']?.toString() ?? 'public',
            status: 'confirmed',
            memberCount: (map['member_count'] as num?)?.toInt() ?? 1,
            cachedAt: now,
            createdAt: createdAt,
          );
          await _dao.saveCommunity(community);
          await _dao.ensureCommunityMember(userId, id);
        } catch (_) {}
      }

      final localCommunities = await _dao.getAllCommunities();
      for (final local in localCommunities) {
        if (local.status != 'pending' && !remoteIds.contains(local.id)) {
          await _dao.deleteCommunity(local.id);
        }
      }
    } catch (e) {
      debugPrint('[COMMUNITY_SYNC] Reconciliation error: $e');
    } finally {
      _isReconciling = false;
    }
  }

  Future<CommunityModel?> getCommunityById(String id) async {
    return await _dao.getCommunity(id);
  }

  Future<List<CommunityModel>> getJoinedCommunities() async {
    final userId = _authService.userId ?? 'local_user';
    return await _dao.getCommunities(userId);
  }

  Future<Map<String, dynamic>> getCommunityMembersRpc({
    required String communityId,
    int limit = 50,
    String? cursor,
    String? query,
  }) async {
    return await _repo.getCommunityMembersRpc(
      communityId: communityId,
      limit: limit,
      cursor: cursor,
      query: query,
    );
  }

  Future<bool> isCommunityStaffRpc(String communityId) async {
    return await _repo.isCommunityStaffRpc(communityId);
  }

  Future<List<Map<String, dynamic>>> getCommunityMembers(String communityId) async {
    return await _repo.getCommunityMembers(communityId);
  }

  Future<void> updateMemberRole(String communityId, String userId, String newRole) async {
    await _repo.updateCommunityMemberRoleRpc(
      communityId: communityId,
      userId: userId,
      newRole: newRole,
    );
  }

  /// Returns a non-privileged role unless the backend confirms staff access.
  ///
  /// This value is used to decide which management controls to show in the UI;
  /// sensitive operations must still be authorized by their Supabase RPC/RLS.
  Future<String> getCurrentUserRole(String communityId) async {
    try {
      final userId = _authService.userId;
      if (userId == null) return 'member';

      try {
        final myCommunities = await _repo.getMyCommunities();
        for (final comm in myCommunities) {
          final id = comm['id']?.toString();
          if (id == communityId) {
            final rawRole = comm['role']?.toString() ??
                comm['user_role']?.toString() ??
                comm['member_role']?.toString() ??
                comm['role_id']?.toString() ??
                '';
            final role = rawRole.toLowerCase();
            if (role.contains('admin') ||
                role.contains('owner') ||
                role.contains('fondateur') ||
                role.contains('administrateur') ||
                role.contains('créateur')) {
              return 'admin';
            }
            if (role.contains('moderator') ||
                role.contains('modérateur') ||
                role.contains('moderateur')) {
              return 'moderator';
            }
            if (role.isNotEmpty) return 'member';
          }
        }
      } catch (e) {
        debugPrint('[CommunityService] Could not read community membership role: $e');
      }

      try {
        final isStaff = await _repo.isCommunityStaffRpc(communityId);
        if (isStaff) {
          // The current RPC only reports whether the user is staff, not the
          // precise role. Keep existing UI compatibility while avoiding
          // privilege escalation when the check fails.
          return 'admin';
        }
      } catch (e) {
        debugPrint('[CommunityService] Could not verify community staff role: $e');
      }

      return 'member';
    } catch (e) {
      debugPrint('[CommunityService] getCurrentUserRole error: $e');
      return 'member';
    }
  }

  Future<void> excludeCommunityMember(String communityId, String userId, {String? reason, bool deleteContent = false}) async {
    await _repo.excludeCommunityMember(communityId, userId, reason: reason, deleteContent: deleteContent);
  }

  Future<void> unexcludeCommunityMember(String communityId, String userId) async {
    await _repo.unexcludeCommunityMember(communityId, userId);
  }

  Future<Map<String, dynamic>> getCommunityExclusions(String communityId, {int limit = 30, int offset = 0}) async {
    return await _repo.getCommunityExclusions(communityId, limit: limit, offset: offset);
  }

  Future<List<Map<String, dynamic>>> getSignalementRaisons() async {
    return await _repo.getSignalementRaisons();
  }

  Future<void> reportCommunity({
    required String communityId,
    required String reasonId,
    String? description,
  }) async {
    try {
      final trimmedDesc = (description != null && description.trim().isNotEmpty) ? description.trim() : null;
      await _repo.reportContent(
        targetType: 'community',
        targetId: communityId,
        reasonId: reasonId,
        description: trimmedDesc,
      );
    } catch (e) {
      debugPrint('[CommunityService] reportCommunity error: $e');
      rethrow;
    }
  }

  Future<CommunityOpenResult> openCommunity(String communityId) async {
    final resMap = await _repo.openCommunityRpc(communityId);
    return CommunityOpenResult.fromJson(resMap);
  }

  Future<Map<String, dynamic>> joinCommunity(String communityId) async {
    final userId = _authService.userId ?? 'local_user';
    final res = await _repo.joinCommunityRpc(communityId);
    final status = (res['status'] ?? res['membership_status'] ?? res['request_status'] ?? '').toString().toLowerCase();

    if (status == 'active' || status == 'approved' || status == 'joined' || status == 'confirmed') {
      await _dao.ensureCommunityMember(userId, communityId);
    }

    await reconcileMyCommunities();
    return res;
  }

  Future<void> leaveCommunity(String communityId) async {
    await _repo.leaveCommunityRpc(communityId);
    await _dao.deleteCommunity(communityId);
    await reconcileMyCommunities();
  }

  Future<CommunityModel> createCommunity({
    required String name,
    required String slug,
    required String description,
    required String visibility,
    File? avatarFile,
    File? bannerFile,
  }) async {
    final userId = _authService.userId ?? 'local_user';
    final communityId = _generateUuidV4();
    final operationId = _generateUuidV4();
    final nowMs = DateTime.now().millisecondsSinceEpoch;

    String? avatarLocalPath;
    String? bannerLocalPath;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (avatarFile != null && avatarFile.existsSync()) {
        final targetPath = p.join(appDir.path, 'communities', communityId, 'profile.jpg');
        await Directory(p.dirname(targetPath)).create(recursive: true);
        final compressed = await FlutterImageCompress.compressAndGetFile(
          avatarFile.absolute.path,
          targetPath,
          minWidth: 1280,
          minHeight: 1280,
          quality: 80,
        );
        avatarLocalPath = compressed?.path ?? avatarFile.path;
      }

      if (bannerFile != null && bannerFile.existsSync()) {
        final targetPath = p.join(appDir.path, 'communities', communityId, 'cover.jpg');
        await Directory(p.dirname(targetPath)).create(recursive: true);
        final compressed = await FlutterImageCompress.compressAndGetFile(
          bannerFile.absolute.path,
          targetPath,
          minWidth: 1280,
          minHeight: 1280,
          quality: 80,
        );
        bannerLocalPath = compressed?.path ?? bannerFile.path;
      }
    } catch (_) {}

    final community = CommunityModel(
      id: communityId,
      name: name,
      slug: slug,
      description: description,
      avatarUrl: avatarLocalPath,
      bannerUrl: bannerLocalPath,
      visibility: visibility,
      status: 'pending',
      memberCount: 1,
      cachedAt: nowMs,
      createdAt: nowMs,
    );

    await _dao.saveCommunity(community);

    final payload = {
      'name': name,
      'slug': slug,
      'description': description,
      'visibility': visibility,
      'avatar_local_path': avatarLocalPath,
      'banner_local_path': bannerLocalPath,
      'require_manual_approval': visibility == 'prive',
    };

    await _dao.insertCommunityOutbox(
      operationId: operationId,
      userId: userId,
      communityId: communityId,
      operationType: 'create_community',
      payload: jsonEncode(payload),
    );

    try {
      if (!Get.isRegistered<CommunityOutboxProcessor>()) {
        Get.put(CommunityOutboxProcessor());
      }
      await Get.find<CommunityOutboxProcessor>().processPendingOperations();
    } catch (_) {}

    return community;
  }

  Future<void> updateCommunityInfo({
    required String id,
    required String name,
    String? slogan,
    required String description,
    String? photoProfile,
    String? photoCover,
  }) async {
    await _repo.updateCommunityInfo(
      p_id: id,
      p_name: name,
      p_slogan: slogan,
      p_description: description,
      p_photo_profile: photoProfile,
      p_photo_cover: photoCover,
    );
  }

  Future<Map<String, dynamic>> getCommunityModerationCounts(String communityId) async {
    return await _repo.getCommunityModerationCounts(communityId);
  }

  Future<Map<String, dynamic>> getCommunityReports(String communityId, {String status = 'open', int limit = 20, int offset = 0}) async {
    return await _repo.getCommunityReports(communityId, status: status, limit: limit, offset: offset);
  }

  Future<Map<String, dynamic>> resolveCommunityReport(String reportId, String action, {String? note}) async {
    return await _repo.resolveCommunityReport(reportId, action, note: note);
  }

  Future<Map<String, dynamic>> getCommunityPendingPosts(String communityId, {int limit = 20, int offset = 0}) async {
    return await _repo.getCommunityPendingPosts(communityId, limit: limit, offset: offset);
  }

  Future<void> moderateCommunityPost(String postId, String action, {String? reason}) async {
    await _repo.moderateCommunityPost(postId, action, reason: reason);
  }

  Future<Map<String, dynamic>> getCommunityJoinRequests(String communityId, {int limit = 20, String? cursor}) async {
    return await _repo.getCommunityJoinRequests(communityId, limit: limit, cursor: cursor);
  }

  Future<void> respondCommunityJoinRequest(String requestId, bool accepted) async {
    await _repo.respondCommunityJoinRequest(requestId, accepted);
  }

  Future<Map<String, dynamic>> getCommunityAccessRules(String communityId) async {
    return await _repo.getCommunityAccessRules(communityId);
  }

  Future<void> updateCommunityAccessRules({
    required String communityId,
    required bool countriesEnabled,
    required List<String> allowedCountries,
    required bool citiesEnabled,
    required List<String> allowedCities,
    required bool certificationRequired,
    String? genderRestriction,
    int? ageMin,
    int? ageMax,
  }) async {
    await _repo.updateCommunityAccessRules(
      p_id: communityId,
      p_countries_enabled: countriesEnabled,
      p_allowed_countries: allowedCountries,
      p_cities_enabled: citiesEnabled,
      p_allowed_cities: allowedCities,
      p_certification_required: certificationRequired,
      p_gender_restriction: genderRestriction,
      p_age_min: ageMin,
      p_age_max: ageMax,
    );
  }

  Future<void> updateCommunitySettings({
    required String communityId,
    required String visibility,
    required bool requireManualApproval,
  }) async {
    await _repo.updateCommunitySettings(
      p_id: communityId,
      p_visibility: visibility,
      p_require_manual_approval: requireManualApproval,
    );
  }

  Future<void> updateCommunityPostSettings({
    required String communityId,
    required String postPermission,
    required bool postsRequireApproval,
  }) async {
    await _repo.updateCommunityPostSettings(
      communityId: communityId,
      postPermission: postPermission,
      postsRequireApproval: postsRequireApproval,
    );
  }

  Future<void> updateCommunityFeatures(
    String communityId, {
    bool? membersListVisible,
    bool? allowReports,
    bool? allowComments,
    bool? allowReactions,
  }) async {
    await _repo.updateCommunityFeatures(
      communityId: communityId,
      membersListVisible: membersListVisible ?? true,
      allowReports: allowReports ?? true,
      allowComments: allowComments ?? true,
      allowReactions: allowReactions ?? true,
    );
  }

  Future<List<Map<String, dynamic>>> getCommunityRules(String communityId) async {
    return await _repo.getCommunityRules(communityId);
  }

  Future<void> setCommunityRule({
    required String p_id,
    required String p_community_id,
    required String p_text,
    required int p_order_index,
  }) async {
    await _repo.setCommunityRule(
      p_id: p_id,
      p_community_id: p_community_id,
      p_text: p_text,
      p_order_index: p_order_index,
    );
  }

  Future<void> deleteCommunityRule(String p_id) async {
    await _repo.deleteCommunityRule(p_id);
  }

  Future<void> transferCommunityOwnership({
    required String communityId,
    required String toUserId,
  }) async {
    await _repo.transferCommunityOwnership(
      communityId: communityId,
      toUserId: toUserId,
    );
  }

  Future<void> deleteCommunity(String communityId) async {
    await _dao.deleteCommunity(communityId);
    await _repo.deleteCommunity(communityId);
  }

  Future<void> leaveCommunityAndReport({
    required String communityId,
    required String reasonId,
    required String description,
  }) async {
    await _repo.leaveCommunityAndReport(
      communityId: communityId,
      reasonId: reasonId,
      description: description,
    );
    await _dao.deleteCommunity(communityId);
    await reconcileMyCommunities();
  }

  Future<void> updateCommunityMemberVisibility(String communityId, bool membersListVisible) async {
    await _repo.updateCommunityMemberVisibility(communityId, membersListVisible);
  }

  Future<Map<String, dynamic>> getCommunityUserReports(String communityId, {String status = 'open', int limit = 20, int offset = 0}) async {
    return await _repo.getCommunityUserReports(communityId, status: status, limit: limit, offset: offset);
  }

  Future<Map<String, dynamic>> resolveCommunityUserReport(String reportId, String action, {String? note, bool deleteContent = false}) async {
    return await _repo.resolveCommunityUserReport(reportId, action, note: note, deleteContent: deleteContent);
  }

  Future<List<Map<String, dynamic>>> getAvailableInterests() async {
    return await _repo.getAvailableInterests();
  }

  Future<List<Map<String, dynamic>>> getCommunityInterests(String communityId) async {
    return await _repo.getCommunityInterests(communityId);
  }

  Future<void> updateCommunityInterests(String communityId, List<String> interestIds) async {
    await _repo.updateCommunityInterests(communityId, interestIds);
  }

  Future<void> checkPendingExpirations() async {
    try {
      final localCommunities = await _dao.getAllCommunities();
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final twoMinutesMs = 2 * 60 * 1000;

      final pendingCommunities = localCommunities.where((c) => c.status == 'pending').toList();
      if (pendingCommunities.isEmpty) return;

      List<Map<String, dynamic>> remoteList = [];
      try {
        remoteList = await _repo.getMyCommunities();
      } catch (e) {
        debugPrint('[COMMUNITY_SYNC] Failed to fetch remote communities during expiration check: $e');
      }
      final remoteIds = remoteList.map((m) => m['id']?.toString()).where((id) => id != null && id.isNotEmpty).toSet();

      for (final community in pendingCommunities) {
        final age = nowMs - community.createdAt;
        final expired = age > twoMinutesMs;
        if (expired) {
          if (remoteIds.contains(community.id)) {
            await _dao.updateCommunityStatus(community.id, 'confirmed');
          } else {
            await _dao.deleteCommunity(community.id);
          }
        }
      }
    } catch (e) {
      debugPrint('[COMMUNITY_SYNC] checkPendingExpirations error: $e');
    }
  }

  Future<void> createCommunityPost({
    required String communityId,
    String? postId,
    String? content,
    List<File>? imageFiles,
    String? audience,
    bool commentsEnabled = true,
    bool sharingEnabled = true,
    bool reactionsEnabled = true,
    List<String>? hashtags,
    List<String>? mentions,
    Map<String, dynamic>? poll,
    bool allowPromotion = true,
  }) async {
    final userId = _authService.userId ?? 'local_user';
    final postId = postId ?? _generateUuidV4();
    final operationId = postId;

    List<String> localMediaPaths = [];
    try {
      final appDir = await getApplicationDocumentsDirectory();
      if (imageFiles != null && imageFiles.isNotEmpty) {
        final filesToProcess = imageFiles.take(4).toList();
        for (int i = 0; i < filesToProcess.length; i++) {
          final file = filesToProcess[i];
          if (file.existsSync()) {
            final targetPath = p.join(appDir.path, 'posts', postId, 'photo_$i.jpg');
            await Directory(p.dirname(targetPath)).create(recursive: true);
            final compressed = await FlutterImageCompress.compressAndGetFile(
              file.absolute.path,
              targetPath,
              minWidth: 1280,
              minHeight: 1280,
              quality: 80,
            );
            localMediaPaths.add(compressed?.path ?? file.path);
          }
        }
      }
    } catch (_) {}

    final payload = {
      'p_id': postId,
      'p_content': content ?? '',
      'p_community_id': communityId.isEmpty ? null : communityId,
      'p_audience': audience ?? 'public',
      'p_local_media': localMediaPaths,
      'p_hashtags': hashtags ?? [],
      'p_mentions': mentions ?? [],
      'p_comments_enabled': commentsEnabled,
      'p_sharing_enabled': sharingEnabled,
      'p_reactions_enabled': reactionsEnabled,
      'p_poll': poll,
      'p_allow_promotion': allowPromotion,
    };

    final db = await Get.find<AppDatabase>().database;
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'post_outbox',
      {
        'operation_id': operationId,
        'user_id': userId,
        'community_id': communityId.isEmpty ? null : communityId,
        'payload': jsonEncode(payload),
        'status': 'pending',
        'attempt_count': 0,
        'next_retry_at': 0,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );

    try {
      if (!Get.isRegistered<CommunityOutboxProcessor>()) {
        Get.put(CommunityOutboxProcessor());
      }
      await Get.find<CommunityOutboxProcessor>().processPendingPosts();
    } catch (_) {}
  }

  String _generateUuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final chars = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
  }
}
