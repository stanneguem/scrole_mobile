import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../externe/repositories/community_repository.dart';
import '../persistence/community_local_dao.dart';

class CommunityOutboxProcessor extends GetxService {
  final CommunityRepository _repository = CommunityRepository();
  final AuthService _authService = Get.find<AuthService>();
  late final CommunityLocalDao _dao = CommunityLocalDao(Get.find<AppDatabase>());

  final RxBool isProcessing = false.obs;
  Timer? _pollingTimer;

  @override
  void onInit() {
    super.onInit();
    debugPrint('[CREATE_COMMUNITY] [Outbox] CommunityOutboxProcessor onInit triggered');
    _pollingTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      debugPrint('[CREATE_COMMUNITY] [Outbox] Timer tick triggered processPendingOperations & processPendingPosts');
      processPendingOperations();
      processPendingPosts();
    });
    unawaited(processPendingOperations());
    unawaited(processPendingPosts());
  }

  @override
  void onClose() {
    _pollingTimer?.cancel();
    super.onClose();
  }

  Future<void> processPendingOperations() async {
    final currentUserId = _authService.userId;
    debugPrint('[CREATE_COMMUNITY] [Outbox] processPendingOperations started. currentUserId=$currentUserId, isProcessing=${isProcessing.value}');
    if (currentUserId == null || isProcessing.value) {
      debugPrint('[CREATE_COMMUNITY] [Outbox] Skipped processing: userId=$currentUserId, isProcessing=${isProcessing.value}');
      return;
    }

    isProcessing.value = true;
    try {
      final pendingList = await _dao.getPendingOutboxOperations(currentUserId);
      debugPrint('[CREATE_COMMUNITY] [Outbox] Found ${pendingList.length} pending operations for userId=$currentUserId');
      for (final item in pendingList) {
        final id = (item['id'] as num).toInt();
        final operationId = item['operation_id'].toString();
        final userId = item['user_id'].toString();
        final communityId = item['community_id']?.toString() ?? '';
        final operationType = item['operation_type'].toString();
        final attempts = (item['attempt_count'] as num).toInt();
        final payload = Map<String, dynamic>.from(jsonDecode(item['payload'].toString()));
        final createdAtStr = item['created_at']?.toString();

        debugPrint('[CREATE_COMMUNITY] [Outbox] Inspecting item id=$id, operationId=$operationId, type=$operationType, communityId=$communityId, attempts=$attempts');

        if (userId != currentUserId) {
          debugPrint('[CREATE_COMMUNITY] [Outbox] Skipping item: userId $userId != currentUserId $currentUserId');
          continue;
        }

        // 2-Minute Pending Creation Expiration check in Outbox handler
        if (operationType == 'create_community' && createdAtStr != null) {
          final createdAtTime = DateTime.tryParse(createdAtStr) ?? DateTime.fromMillisecondsSinceEpoch(0);
          final age = DateTime.now().difference(createdAtTime);
          debugPrint('[CREATE_COMMUNITY] [Outbox] Item $operationId age: ${age.inSeconds}s');
          if (age.inMinutes >= 2) {
            debugPrint('[CREATE_COMMUNITY] [Outbox] Outbox operation $operationId refused: pending creation expired (>2m)');
            await _dao.markOutboxOperationFailed(id: id, lastError: 'Pending creation expired (>2m)');
            if (communityId.isNotEmpty) {
              await _dao.deleteCommunity(communityId);
            }
            Get.snackbar(
              'error'.tr,
              'community_creation_expired_msg'.tr,
              snackPosition: SnackPosition.BOTTOM,
            );
            continue;
          }
        }

        try {
          debugPrint('[CREATE_COMMUNITY] [Outbox] Executing operationId=$operationId type=$operationType communityId=$communityId');

          if (operationType == 'create_community') {
            final name = payload['name']?.toString() ?? '';
            final slug = payload['slug']?.toString() ?? '';
            final description = payload['description']?.toString() ?? '';
            final visibility = payload['visibility']?.toString() ?? 'public';
            final requireManualApproval = payload['require_manual_approval'] == true || visibility == 'prive';

            final supabaseClient = Supabase.instance.client;
            String? photoProfile;
            String? photoCover;

            final avatarLocalPath = payload['avatar_local_path']?.toString() ?? payload['avatar_url']?.toString() ?? payload['photo_profile']?.toString();
            if (avatarLocalPath != null && avatarLocalPath.isNotEmpty) {
              if (avatarLocalPath.startsWith('http://') || avatarLocalPath.startsWith('https://')) {
                photoProfile = avatarLocalPath;
              } else {
                final file = File(avatarLocalPath);
                if (file.existsSync()) {
                  final storagePath = 'communities/$communityId/profile.jpg';
                  debugPrint('[CREATE_COMMUNITY] [Outbox] Uploading avatar to community-media at $storagePath');
                  try {
                    await supabaseClient.storage.from('community-media').upload(
                      storagePath,
                      file,
                      fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
                    );
                    photoProfile = supabaseClient.storage.from('community-media').getPublicUrl(storagePath);
                    debugPrint('[CREATE_COMMUNITY] [Outbox] Avatar uploaded successfully. Public URL: $photoProfile');
                  } catch (e) {
                    debugPrint('[CREATE_COMMUNITY] [Outbox] Avatar upload error: $e');
                    if (_isDefinitiveUploadError(e)) {
                      rethrow;
                    }
                    rethrow;
                  }
                }
              }
            }

            final bannerLocalPath = payload['banner_local_path']?.toString() ?? payload['banner_url']?.toString() ?? payload['photo_cover']?.toString();
            if (bannerLocalPath != null && bannerLocalPath.isNotEmpty) {
              if (bannerLocalPath.startsWith('http://') || bannerLocalPath.startsWith('https://')) {
                photoCover = bannerLocalPath;
              } else {
                final file = File(bannerLocalPath);
                if (file.existsSync()) {
                  final storagePath = 'communities/$communityId/cover.jpg';
                  debugPrint('[CREATE_COMMUNITY] [Outbox] Uploading banner to community-media at $storagePath');
                  try {
                    await supabaseClient.storage.from('community-media').upload(
                      storagePath,
                      file,
                      fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
                    );
                    photoCover = supabaseClient.storage.from('community-media').getPublicUrl(storagePath);
                    debugPrint('[CREATE_COMMUNITY] [Outbox] Banner uploaded successfully. Public URL: $photoCover');
                  } catch (e) {
                    debugPrint('[CREATE_COMMUNITY] [Outbox] Banner upload error: $e');
                    if (_isDefinitiveUploadError(e)) {
                      rethrow;
                    }
                    rethrow;
                  }
                }
              }
            }

            debugPrint('[CREATE_COMMUNITY] [Outbox] Calling createCommunityRpc with exact parameters: p_id=$communityId, p_name=$name, p_slug=$slug, p_description=$description, p_photo_profile=$photoProfile, p_photo_cover=$photoCover, p_visibility=$visibility, p_require_manual_approval=$requireManualApproval');

            await _repository.createCommunityRpc(
              p_id: communityId,
              p_name: name,
              p_slug: slug,
              p_description: description,
              p_visibility: visibility,
              p_photo_profile: photoProfile,
              p_photo_cover: photoCover,
              p_require_manual_approval: requireManualApproval,
            );
          }

          debugPrint('[CREATE_COMMUNITY] [Outbox] Operation $operationId completed successfully. Marking confirmed.');
          await _dao.updateCommunityStatus(communityId, 'confirmed');
          await _dao.markOutboxOperationCompleted(id);
        } catch (e, stackTrace) {
          final errStr = e.toString();
          debugPrint('[CREATE_COMMUNITY] [Outbox] Operation $operationId failed with error: $errStr');
          debugPrint('[CREATE_COMMUNITY] [Outbox] StackTrace: $stackTrace');

          if (_isTerminalError(e)) {
            debugPrint('[CREATE_COMMUNITY] [Outbox] Terminal error detected for operation $operationId. Marking failed.');
            await _dao.markOutboxOperationFailed(id: id, lastError: errStr);
            await _dao.updateCommunityStatus(communityId, 'error');
          } else {
            final nextAttempt = attempts + 1;
            final retryDelay = _calculateBackoffDelay(nextAttempt);
            final nextRetryAt = DateTime.now().add(retryDelay).millisecondsSinceEpoch;
            debugPrint('[CREATE_COMMUNITY] [Outbox] Transient error for operation $operationId. Scheduling retry attempt $nextAttempt at $nextRetryAt');

            await _dao.markOutboxOperationRetry(
              id: id,
              attemptCount: nextAttempt,
              nextRetryAt: nextRetryAt,
              lastError: errStr,
            );
          }
        }
      }
    } catch (e, st) {
      debugPrint('[CREATE_COMMUNITY] [Outbox] Unexpected error in processPendingOperations: $e\n$st');
    } finally {
      isProcessing.value = false;
      debugPrint('[CREATE_COMMUNITY] [Outbox] processPendingOperations finished.');
    }
  }

  bool _isDefinitiveUploadError(dynamic error) {
    final str = error.toString().toLowerCase();
    return str.contains('413') ||
        str.contains('payload too large') ||
        str.contains('invalid') ||
        str.contains('unsupported') ||
        str.contains('bad request') ||
        str.contains('400');
  }

  bool _isTerminalError(dynamic error) {
    final str = error.toString().toLowerCase();
    return _isDefinitiveUploadError(error) ||
        str.contains('permission denied') ||
        str.contains('not found') ||
        str.contains('already used') ||
        str.contains('exists') ||
        str.contains('23505') ||
        str.contains('409') ||
        str.contains('422');
  }

  Duration _calculateBackoffDelay(int attempt) {
    switch (attempt) {
      case 1:
        return const Duration(seconds: 5);
      case 2:
        return const Duration(seconds: 15);
      case 3:
        return const Duration(seconds: 30);
      default:
        return const Duration(minutes: 1);
    }
  }

  Future<void> processPendingPosts() async {
    final currentUserId = _authService.userId;
    debugPrint('[POST] [Outbox] processPendingPosts started. currentUserId=$currentUserId');
    if (currentUserId == null) return;

    try {
      final db = await Get.find<AppDatabase>().database;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pendingList = await db.query(
        'post_outbox',
        where: 'user_id = ? AND status = "pending" AND next_retry_at <= ?',
        whereArgs: [currentUserId, nowMs],
        orderBy: 'created_at ASC',
      );

      debugPrint('[POST] [Outbox] Found ${pendingList.length} pending posts');
      for (final item in pendingList) {
        final id = (item['id'] as num).toInt();
        final operationId = item['operation_id'].toString();
        final communityId = item['community_id']?.toString();
        final attempts = (item['attempt_count'] as num).toInt();
        final payload = Map<String, dynamic>.from(jsonDecode(item['payload'].toString()));

        debugPrint('[POST] [Outbox] Processing post operationId=$operationId, communityId=$communityId, attempts=$attempts');

        try {
          final localMediaPaths = List<String>.from(payload['p_local_media'] ?? []);
          List<Map<String, dynamic>> supabaseMedia = [];

          final supabaseClient = Supabase.instance.client;
          for (int i = 0; i < localMediaPaths.length; i++) {
            final localPath = localMediaPaths[i];
            if (localPath.startsWith('http://') || localPath.startsWith('https://')) {
              supabaseMedia.add({'type': 'photo', 'storage': 'supabase', 'url': localPath});
            } else {
              final file = File(localPath);
              if (file.existsSync()) {
                final timestamp = DateTime.now().millisecondsSinceEpoch;
                final fileName = 'post_${timestamp}_$i.jpg';
                final storagePath = (communityId != null && communityId.isNotEmpty)
                    ? 'communities/$communityId/posts/$fileName'
                    : 'users/$currentUserId/posts/$fileName';

                debugPrint('[POST] [Outbox] Uploading photo $i to bucket community-media at path $storagePath');
                await supabaseClient.storage.from('community-media').upload(
                  storagePath,
                  file,
                  fileOptions: const FileOptions(upsert: true, contentType: 'image/jpeg'),
                );
                final publicUrl = supabaseClient.storage.from('community-media').getPublicUrl(storagePath);
                debugPrint('[POST] [Outbox] Photo uploaded successfully. Public URL: $publicUrl');
                supabaseMedia.add({'type': 'photo', 'storage': 'supabase', 'url': publicUrl});
              }
            }
          }

          final pId = payload['p_id']?.toString() ?? operationId;
          final content = payload['p_content']?.toString() ?? '';
          final audience = payload['p_audience']?.toString() ?? 'public';
          final hashtags = List<String>.from(payload['p_hashtags'] ?? []);
          final mentions = List<String>.from(payload['p_mentions'] ?? []);
          final commentsEnabled = payload['p_comments_enabled'] == true;
          final sharingEnabled = payload['p_sharing_enabled'] == true;
          final reactionsEnabled = payload['p_reactions_enabled'] == true;
          final poll = payload['p_poll'] is Map ? Map<String, dynamic>.from(payload['p_poll']) : null;
          final allowPromotion = payload['p_allow_promotion'] ?? true;

          debugPrint('[POST] [Outbox] Calling repository createPostRpc with p_id=$pId, communityId=$communityId, audience=$audience, mediaCount=${supabaseMedia.length}');

          await _repository.createPostRpc(
            p_id: pId,
            p_content: content,
            p_community_id: communityId,
            p_audience: audience,
            p_media: supabaseMedia,
            p_hashtags: hashtags,
            p_mentions: mentions,
            p_comments_enabled: commentsEnabled,
            p_sharing_enabled: sharingEnabled,
            p_reactions_enabled: reactionsEnabled,
            p_poll: poll,
            p_allow_promotion: allowPromotion,
          );

          debugPrint('[POST] [Outbox] Post operation $operationId completed successfully.');
          await db.delete('post_outbox', where: 'id = ?', whereArgs: [id]);
        } catch (e, st) {
          final errStr = e.toString();
          debugPrint('[POST] [Outbox] Post operation $operationId failed with error: $errStr\n$st');
          final nextAttempt = attempts + 1;
          final retryDelay = _calculateBackoffDelay(nextAttempt);
          final nextRetryAt = DateTime.now().add(retryDelay).millisecondsSinceEpoch;

          await db.update(
            'post_outbox',
            {
              'attempt_count': nextAttempt,
              'next_retry_at': nextRetryAt,
              'last_error': errStr,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (e, st) {
      debugPrint('[POST] [Outbox] Unexpected error in processPendingPosts: $e\n$st');
    }
  }
}
