import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/local_storage/structured/app_cache_database.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../../centre/persistence/social_local_dao.dart';

class SocialRepository {
  final SupabaseClient _client;
  final SocialLocalDao _dao;

  SocialRepository({
    SupabaseClient? client,
    SocialLocalDao? dao,
  })  : _client = client ?? Get.find<SupabaseService>().client,
        _dao = dao ?? SocialLocalDao(Get.find<AppDatabase>());

  SocialLocalDao get dao => _dao;

  String? get currentUserId => _client.auth.currentUser?.id;

  /// Calcul de l'état de relation (§1) strictement depuis le cache local SQLite.
  Future<RelationState> getRelationState(String targetUserId) async {
    final userId = currentUserId;
    if (userId == null) return RelationState.none;
    return await _dao.getRelationState(userId, targetUserId);
  }

  /// Récupère la liste des amis confirmés.
  Future<List<Map<String, dynamic>>> getAcceptedConnections() async {
    final userId = currentUserId;
    if (userId == null) return [];

    // 1. Essai de rechargement distant
    try {
      final rows = await _client.from('friendships').select();
      final List<Map<String, dynamic>> friendships = List<Map<String, dynamic>>.from(rows);

      await _dao.saveFriendships(friendships, replaceAll: true);

      final blockedIds = await _dao.getBlockedUserIds();

      final otherUserIds = friendships.map((f) {
        final a = f['user_a_id'] as String;
        final b = f['user_b_id'] as String;
        return a == userId ? b : a;
      }).where((id) => !blockedIds.contains(id)).toSet().toList();

      if (otherUserIds.isEmpty) return [];

      // Batch profiles (colonnes restreintes de sécurité, JAMAIS select *)
      final profiles = await _client
          .from('user_profiles')
          .select('user_id, username, first_name, last_name, photo_url, is_verified, account_status, deleted_at')
          .inFilter('user_id', otherUserIds);

      final List<Map<String, dynamic>> safeProfiles = List<Map<String, dynamic>>.from(profiles);
      await _dao.savePeople(safeProfiles);

      return safeProfiles.where((p) => p['deleted_at'] == null && !blockedIds.contains(p['user_id'])).toList();
    } catch (e) {
      debugPrint('[SocialRepository] Error loading remote friends: $e. Falling back to local cache...');
      final blockedIds = await _dao.getBlockedUserIds();
      final localFriendships = await _dao.getFriendships(userId);
      final otherIds = localFriendships.map((f) {
        final a = f['user_a_id'] as String;
        final b = f['user_b_id'] as String;
        return a == userId ? b : a;
      }).where((id) => !blockedIds.contains(id)).toList();

      return await _dao.getPeople(otherIds);
    }
  }

  /// Envoyer une demande d'ami.
  Future<void> sendFriendRequest(String receiverId) async {
    final userId = currentUserId;
    if (userId == null) throw 'Utilisateur non connecté';

    final localReq = {
      'id': 'local:$receiverId',
      'sender_id': userId,
      'receiver_id': receiverId,
      'status': 'pending',
      'attempt_count': 1,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_push',
    };

    // Local DB first
    await _dao.saveFriendRequests([localReq]);

    // Outbox
    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'send_friend_request',
      payload: {'receiver_id': receiverId},
    );

    // Immediate RPC if online
    try {
      final res = await _client.rpc('send_friend_request', params: {'p_receiver_id': receiverId});
      if (res is Map) {
        await _dao.saveFriendRequests([Map<String, dynamic>.from(res)]);
      }
    } catch (e) {
      debugPrint('[SocialRepository] sendFriendRequest offline/error: $e. Outbox will replay.');
    }
  }

  /// Répondre à une demande d'ami (Accepter / Refuser).
  Future<void> respondFriendRequest(String requestId, bool accept, {String? senderId}) async {
    final userId = currentUserId;
    if (userId == null) throw 'Utilisateur non connecté';

    if (accept && senderId != null) {
      await _dao.saveFriendships([{
        'user_a_id': userId,
        'user_b_id': senderId,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'sync_status': 'pending_push',
      }]);
    }

    await _dao.saveFriendRequests([{
      'id': requestId,
      'sender_id': senderId ?? '',
      'receiver_id': userId,
      'status': accept ? 'accepted' : 'rejected',
      'responded_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_push',
    }]);

    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'respond_friend_request',
      payload: {'request_id': requestId, 'accepted': accept},
    );

    try {
      await _client.rpc('respond_friend_request', params: {
        'p_request_id': requestId,
        'p_accepted': accept,
      });
    } catch (e) {
      debugPrint('[SocialRepository] respondFriendRequest offline/error: $e. Outbox will replay.');
    }
  }

  /// Annuler une demande envoyée encore pending.
  Future<void> cancelFriendRequest(String requestId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _dao.removeFriendRequest(requestId);

    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'cancel_friend_request',
      payload: {'request_id': requestId},
    );

    try {
      await _client.rpc('cancel_friend_request', params: {'p_request_id': requestId});
    } catch (e) {
      debugPrint('[SocialRepository] cancelFriendRequest offline/error: $e.');
    }
  }

  /// Retirer un ami.
  Future<void> removeFriendship(String otherUserId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _dao.removeFriendship(userId, otherUserId);

    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'remove_friendship',
      payload: {'other_user_id': otherUserId},
    );

    try {
      await _client.rpc('remove_friendship', params: {'p_other_user_id': otherUserId});
    } catch (e) {
      debugPrint('[SocialRepository] removeFriendship offline/error: $e.');
    }
  }

  /// Bloquer un utilisateur.
  Future<void> blockUser(String targetUserId, {String? reason, DateTime? until}) async {
    final userId = currentUserId;
    if (userId == null) return;

    // 1. Remove friendship locally first (§7)
    await _dao.removeFriendship(userId, targetUserId);

    // 2. Add to local blocked_users
    await _dao.saveBlockedUsers([{
      'id': 'local:$targetUserId',
      'bloque_id': targetUserId,
      'raison': reason,
      'bloque_jusquau': until?.toUtc().toIso8601String(),
      'statut': 1,
      'bloque_le': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_push',
    }]);

    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'block_user',
      payload: {
        'bloque_id': targetUserId,
        if (reason != null) 'raison': reason,
        if (until != null) 'bloque_jusquau': until.toUtc().toIso8601String(),
      },
    );
  }

  /// Débloquer un utilisateur.
  Future<void> unblockUser(String targetUserId) async {
    final userId = currentUserId;
    if (userId == null) return;

    await _dao.removeBlockedUser(targetUserId);

    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'unblock_user',
      payload: {'bloque_id': targetUserId},
    );
  }

  /// Récupère ou génère un QR code d'ajout d'ami (§5.1).
  Future<Map<String, dynamic>?> getOrGenerateUserQrCode() async {
    final userId = currentUserId;
    if (userId == null) return null;

    final active = await _dao.getActiveUserQrCode(userId);
    if (active != null) return active;

    // Generate new client UUID
    final clientUuid = generateLocalUuid();
    final localQr = {
      'id': clientUuid,
      'user_id': userId,
      'uses_remaining': 3,
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'sync_status': 'pending_push',
    };

    await _dao.saveUserQrCodes([localQr]);

    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'generate_user_qr_code',
      payload: {'id': clientUuid},
    );

    try {
      final res = await _client.rpc('generate_user_qr_code', params: {'p_id': clientUuid});
      if (res is Map) {
        final synced = Map<String, dynamic>.from(res);
        await _dao.saveUserQrCodes([synced]);
        return synced;
      }
    } catch (e) {
      debugPrint('[SocialRepository] generateUserQrCode offline/error: $e');
    }
    return localQr;
  }

  /// Scanner le QR code d'un autre utilisateur (§5.2).
  Future<Map<String, dynamic>?> scanQrCode(String qrId, String mode) async {
    final userId = currentUserId;
    if (userId == null) throw 'Utilisateur non connecté';

    await _dao.enqueueOutbox(
      userId: userId,
      operation: 'scan_qr_code',
      payload: {'qr_id': qrId, 'mode': mode},
    );

    final res = await _client.rpc('scan_qr_code', params: {
      'p_qr_id': qrId,
      'p_mode': mode,
    });

    if (res is Map) {
      return Map<String, dynamic>.from(res);
    }
    return null;
  }

  String generateLocalUuid() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final chars = bytes.map(hex).join();
    return '${chars.substring(0, 8)}-${chars.substring(8, 12)}-${chars.substring(12, 16)}-${chars.substring(16, 20)}-${chars.substring(20, 32)}';
  }

  /// Récupère la liste de mes demandes d'amis.
  Future<List<Map<String, dynamic>>> getMyFriendRequests() async {
    final userId = currentUserId;
    if (userId == null) return [];

    try {
      final response = await _client.rpc('get_my_friend_requests');
      if (response is! List) return [];

      final requests = List<Map<String, dynamic>>.from(response);
      await _dao.saveFriendRequests(requests, replaceAll: true);

      final otherUserIds = requests.map((r) {
        final sender = r['sender_id'] as String;
        final receiver = r['receiver_id'] as String;
        return sender == userId ? receiver : sender;
      }).toSet().toList();

      if (otherUserIds.isNotEmpty) {
        final profiles = await _client
            .from('user_profiles')
            .select('user_id, username, first_name, last_name, photo_url, is_verified, account_status, deleted_at')
            .inFilter('user_id', otherUserIds);
        await _dao.savePeople(List<Map<String, dynamic>>.from(profiles));
      }

      final blockedIds = await _dao.getBlockedUserIds();
      final filteredRequests = requests.where((r) {
        final sender = r['sender_id'] as String;
        final receiver = r['receiver_id'] as String;
        final other = sender == userId ? receiver : sender;
        return !blockedIds.contains(other);
      }).toList();

      return filteredRequests;
    } catch (e) {
      debugPrint('[SocialRepository] Error getMyFriendRequests: $e. Returning local...');
      final blockedIds = await _dao.getBlockedUserIds();
      final local = await _dao.getFriendRequests(userId);
      return local.where((r) {
        final sender = r['sender_id'] as String;
        final receiver = r['receiver_id'] as String;
        final other = sender == userId ? receiver : sender;
        return !blockedIds.contains(other);
      }).toList();
    }
  }
}
