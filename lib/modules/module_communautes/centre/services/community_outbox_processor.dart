import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../module_authentification/centre/services/auth_service.dart';
import '../../externe/repositories/community_repository.dart';
import '../../../../app/repository_global/r2_media_repository.dart';
import '../persistence/community_local_dao.dart';

class CommunityOutboxProcessor extends GetxService {
  final CommunityRepository _repository = CommunityRepository();
  final AuthService _authService = Get.find<AuthService>();
  late final CommunityLocalDao _dao = CommunityLocalDao(Get.find<AppDatabase>());

  final RxBool isProcessing = false.obs;
  bool _isProcessingPosts = false;
  static const int _maxPostAttempts = 5;
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

            // Créer d’abord la communauté : l’Edge Function R2 vérifie que
            // l’entité existe et que l’utilisateur en est propriétaire.
            await _repository.createCommunityRpc(
              p_id: communityId,
              p_name: name,
              p_slug: slug,
              p_description: description,
              p_visibility: visibility,
              p_require_manual_approval: requireManualApproval,
            );

            final r2 = R2MediaRepository();
            final avatarLocalPath = payload['avatar_local_path']?.toString() ??
                payload['avatar_url']?.toString() ?? payload['photo_profile']?.toString();
            final bannerLocalPath = payload['banner_local_path']?.toString() ??
                payload['banner_url']?.toString() ?? payload['photo_cover']?.toString();
            String? photoProfile;
            String? photoCover;

            if (avatarLocalPath != null && avatarLocalPath.isNotEmpty) {
              if (avatarLocalPath.startsWith('http://') || avatarLocalPath.startsWith('https://')) {
                photoProfile = avatarLocalPath;
              } else {
                final file = File(avatarLocalPath);
                if (!await file.exists()) {
                  throw FileSystemException('Le fichier de photo de profil de la communauté est introuvable.', avatarLocalPath);
                }
                final uploaded = await r2.uploadFile(
                  file: file,
                  category: 'community_avatar',
                  mediaType: 'image',
                  entityId: communityId,
                );
                photoProfile = uploaded.publicUrl;
                if (photoProfile == null || photoProfile.isEmpty || !uploaded.isPublic) {
                  throw StateError('R2 n’a pas retourné d’URL publique pour la photo de la communauté.');
                }
                debugPrint('[CREATE_COMMUNITY] R2 avatar uploaded key=${uploaded.objectKey}');
              }
            }

            if (bannerLocalPath != null && bannerLocalPath.isNotEmpty) {
              if (bannerLocalPath.startsWith('http://') || bannerLocalPath.startsWith('https://')) {
                photoCover = bannerLocalPath;
              } else {
                final file = File(bannerLocalPath);
                if (!await file.exists()) {
                  throw FileSystemException('Le fichier de couverture de la communauté est introuvable.', bannerLocalPath);
                }
                final uploaded = await r2.uploadFile(
                  file: file,
                  category: 'community_cover',
                  mediaType: 'image',
                  entityId: communityId,
                );
                photoCover = uploaded.publicUrl;
                if (photoCover == null || photoCover.isEmpty || !uploaded.isPublic) {
                  throw StateError('R2 n’a pas retourné d’URL publique pour la couverture de la communauté.');
                }
                debugPrint('[CREATE_COMMUNITY] R2 cover uploaded key=${uploaded.objectKey}');
              }
            }

            if (photoProfile != null || photoCover != null) {
              await _repository.updateCommunityInfo(
                p_id: communityId,
                p_name: name,
                p_description: description,
                p_photo_profile: photoProfile,
                p_photo_cover: photoCover,
              );
            }
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

  Future<void> _persistUploadedMedia(
    dynamic db,
    int rowId,
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> uploadedMedia,
    String operationId,
    String postKind,
  ) async {
    payload['p_uploaded_media'] = List<Map<String, dynamic>>.from(uploadedMedia);
    await db.update(
      'post_outbox',
      {'payload': jsonEncode(payload), 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [rowId],
    );
    debugPrint('[POST_CREATE][$postKind] MEDIA_PROGRESS_SAVED operationId=$operationId uploaded=${uploadedMedia.length}');
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
    debugPrint('[POST_CREATE] PROCESS_START userId=$currentUserId alreadyProcessing=$_isProcessingPosts');
    if (currentUserId == null || _isProcessingPosts) {
      debugPrint('[POST_CREATE] PROCESS_SKIPPED userId=$currentUserId alreadyProcessing=$_isProcessingPosts');
      return;
    }
    _isProcessingPosts = true;

    try {
      final db = await Get.find<AppDatabase>().database;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final pendingList = await db.query(
        'post_outbox',
        where: 'user_id = ? AND status = "pending" AND next_retry_at <= ?',
        whereArgs: [currentUserId, nowMs],
        orderBy: 'created_at ASC',
      );

      debugPrint('[POST_CREATE] OUTBOX_SCAN userId=$currentUserId pendingCount=${pendingList.length} nowMs=$nowMs');
      for (final item in pendingList) {
        final id = (item['id'] as num).toInt();
        final operationId = item['operation_id'].toString();
        final communityId = item['community_id']?.toString();
        final attempts = (item['attempt_count'] as num).toInt();
        final payload = Map<String, dynamic>.from(jsonDecode(item['payload'].toString()));

        final postKind = communityId == null || communityId.isEmpty ? 'feed' : 'community';
        debugPrint('[POST_CREATE][$postKind] OUTBOX_ITEM_START operationId=$operationId communityId=$communityId attempts=$attempts payloadKeys=${payload.keys.toList()}');

        try {
          final rawLocalMedia = List<dynamic>.from(payload['p_local_media'] ?? []);
          final localMediaItems = rawLocalMedia.map((item) => item is Map ? Map<String, dynamic>.from(item) : <String, dynamic>{'path': item.toString(), 'type': 'photo'}).toList();
          List<Map<String, dynamic>> uploadedMedia = [];
          final cachedUploadedMedia = payload['p_uploaded_media'];
          final cachedMediaList = cachedUploadedMedia is List ? cachedUploadedMedia : <dynamic>[];
          final reusableCount = cachedMediaList.length <= localMediaItems.length ? cachedMediaList.length : 0;
          if (reusableCount > 0) {
            uploadedMedia = cachedMediaList.take(reusableCount).where((media) => media is Map && media['url'] != null).map((media) => Map<String, dynamic>.from(media as Map)).toList();
            debugPrint('[POST_CREATE][$postKind] MEDIA_REUSE operationId=$operationId count=${uploadedMedia.length}/${localMediaItems.length} reason=previous_upload_progress');
          }

          final supabaseClient = Supabase.instance.client;
          final r2MediaRepository = R2MediaRepository(client: supabaseClient);
          if (uploadedMedia.length < localMediaItems.length) {
          debugPrint('[POST_CREATE][$postKind] MEDIA_PREPARE_START operationId=$operationId count=${localMediaItems.length} types=${localMediaItems.map((m) => m['type'] ?? 'photo').toList()}');
          for (int i = uploadedMedia.length; i < localMediaItems.length; i++) {
            final mediaStartedAt = DateTime.now();
            final localPath = localMediaItems[i]['path'].toString();
            final mediaType = (localMediaItems[i]['type'] ?? 'photo').toString();
            debugPrint('[POST_CREATE][$postKind] MEDIA_START operationId=$operationId index=${i + 1}/${localMediaItems.length} type=$mediaType remote=${localPath.startsWith('http://') || localPath.startsWith('https://')} exists=${localPath.startsWith('http') ? 'n/a' : File(localPath).existsSync()}');
            if (localPath.startsWith('http://') || localPath.startsWith('https://')) {
              if (mediaType == 'video') {
                throw Exception('Une vidéo locale ne peut pas être une URL distante non vérifiée.');
              }
              uploadedMedia.add({'type': 'photo', 'storage': 'supabase', 'url': localPath}); // legacy queued remote URL; new local uploads always go to R2
              await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);
            } else {
              final file = File(localPath);
              if (file.existsSync()) {
                if (mediaType == 'video') {
                  final uploaded = await r2MediaRepository.uploadFile(
                    file: file, category: 'post_media', mediaType: 'video',
                    communityId: communityId, videoDuration: const Duration(seconds: 30),
                  );
                  uploadedMedia.add({
                    'type': 'video', 'storage': 'r2',
                    'url': uploaded.publicUrl ?? uploaded.objectKey,
                    'object_key': uploaded.objectKey, 'is_public': uploaded.isPublic,
                    'mime_type': uploaded.contentType, 'size_bytes': uploaded.sizeBytes,
                    'duration_seconds': 30,
                  });
                  debugPrint('[POST_CREATE][$postKind] MEDIA_SUCCESS operationId=$operationId index=${i + 1}/${localMediaItems.length} type=video key=${uploaded.objectKey} elapsedMs=${DateTime.now().difference(mediaStartedAt).inMilliseconds}');
                  await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);
                } else {
                  final uploaded = await r2MediaRepository.uploadFile(
                    file: file, category: 'post_media', mediaType: 'photo', communityId: communityId,
                  );
                  uploadedMedia.add({
                    'type': 'photo', 'storage': 'r2',
                    'url': uploaded.publicUrl ?? uploaded.objectKey,
                    'object_key': uploaded.objectKey, 'is_public': uploaded.isPublic,
                    'mime_type': uploaded.contentType, 'size_bytes': uploaded.sizeBytes,
                  });
                  debugPrint('[POST_CREATE][$postKind] MEDIA_SUCCESS operationId=$operationId index=${i + 1}/${localMediaItems.length} type=photo key=${uploaded.objectKey} elapsedMs=${DateTime.now().difference(mediaStartedAt).inMilliseconds}');
                  await _persistUploadedMedia(db, id, payload, uploadedMedia, operationId, postKind);
                }
              } else {
                throw FileSystemException('Le média sélectionné n’existe plus sur le stockage local.', localPath);
              }
            }
          }
          if (uploadedMedia.length != localMediaItems.length) {
            throw StateError('Téléversement incomplet : ${uploadedMedia.length}/${localMediaItems.length} médias ont été préparés.');
          }
          debugPrint('[POST_CREATE][$postKind] MEDIA_CACHE_READY operationId=$operationId count=${uploadedMedia.length}');
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

          debugPrint('[POST_CREATE][$postKind] RPC_START operationId=$operationId postId=$pId communityId=$communityId audience=$audience contentLength=${content.length} mediaCount=${uploadedMedia.length} hashtagCount=${hashtags.length} mentionCount=${mentions.length} pollPresent=${poll != null}');
          final rpcStartedAt = DateTime.now();

          await _repository.createPostRpc(
            p_id: pId,
            p_content: content,
            p_community_id: communityId,
            p_audience: audience,
            p_media: uploadedMedia,
            p_hashtags: hashtags,
            p_mentions: mentions,
            p_comments_enabled: commentsEnabled,
            p_sharing_enabled: sharingEnabled,
            p_reactions_enabled: reactionsEnabled,
            p_poll: poll,
            p_allow_promotion: allowPromotion,
          );

          debugPrint('[POST_CREATE][$postKind] RPC_SUCCESS operationId=$operationId postId=$pId elapsedMs=${DateTime.now().difference(rpcStartedAt).inMilliseconds}');
          debugPrint('[POST_CREATE][$postKind] OUTBOX_COMPLETE operationId=$operationId postId=$pId');
          await db.delete('post_outbox', where: 'id = ?', whereArgs: [id]);
        } catch (e, st) {
          final errStr = e.toString();
          debugPrint('[POST_CREATE][$postKind] FAILED operationId=$operationId communityId=$communityId attempt=${attempts + 1} error=$errStr\n$st');
          final nextAttempt = attempts + 1;
          final permanentError = errStr.contains('community_posts_max_photos') ||
              errStr.contains('violates check constraint') ||
              errStr.contains('code: 23514');
          final terminal = permanentError || nextAttempt >= _maxPostAttempts;
          final retryDelay = _calculateBackoffDelay(nextAttempt);
          final nextRetryAt = terminal ? 0 : DateTime.now().add(retryDelay).millisecondsSinceEpoch;
          debugPrint('[POST_CREATE][$postKind] ${permanentError ? 'PERMANENT_ERROR' : terminal ? 'MAX_ATTEMPTS_REACHED' : 'RETRY_SCHEDULED'} operationId=$operationId attempt=$nextAttempt maxAttempts=$_maxPostAttempts delayMs=${terminal ? 0 : retryDelay.inMilliseconds} nextRetryAt=$nextRetryAt error=$errStr');

          // The installed SQLite post_outbox schema has no last_error column.
          // Keep the error in logs and update only columns known to exist.
          await db.update(
            'post_outbox',
            {
              'status': terminal ? 'failed' : 'pending',
              'attempt_count': nextAttempt,
              'next_retry_at': nextRetryAt,
              'updated_at': DateTime.now().toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      }
    } catch (e, st) {
      debugPrint('[POST_CREATE] PROCESS_FATAL error=$e\n$st');
    } finally {
      _isProcessingPosts = false;
      debugPrint('[POST_CREATE] PROCESS_FINISHED userId=$currentUserId');
    }
  }
}
