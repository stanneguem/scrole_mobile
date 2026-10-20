import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../app/service_global/connectivity_service.dart';
import '../../../../app/service_global/supabse_service.dart';
import '../persistence/social_local_dao.dart';

class SocialOutboxProcessor extends GetxService {
  final SocialLocalDao _dao;
  final ConnectivityService _connectivity;
  final SupabaseClient _client = Get.find<SupabaseService>().client;

  StreamSubscription<InternetStatus>? _connectivitySub;
  bool _isProcessing = false;

  SocialOutboxProcessor(this._dao, this._connectivity);

  @override
  void onInit() {
    super.onInit();
    _listenConnectivity();
  }

  void _listenConnectivity() {
    _connectivitySub = _connectivity.onStatusChange.listen((status) {
      if (status == InternetStatus.connected) {
        final userId = _client.auth.currentUser?.id;
        if (userId != null) {
          processPendingOutbox(userId);
        }
      }
    });
  }

  Future<void> processPendingOutbox(String userId) async {
    if (_isProcessing) return;
    if (!_connectivity.isConnected.value) return;

    _isProcessing = true;
    try {
      final pendingItems = await _dao.getPendingOutbox(userId);
      if (pendingItems.isEmpty) return;

      debugPrint('[SocialOutbox] Processing ${pendingItems.length} pending items for $userId...');

      for (final item in pendingItems) {
        final id = item['id'] as int;
        final operation = item['operation'] as String;
        final payloadRaw = item['payload'] as String;
        final attempts = (item['attempts'] as int? ?? 0) + 1;

        Map<String, dynamic> payload = {};
        try {
          payload = jsonDecode(payloadRaw) as Map<String, dynamic>;
        } catch (_) {}

        try {
          await _executeOperation(operation: operation, payload: payload);
          await _dao.removeFromOutbox(id);
          debugPrint('[SocialOutbox] Item $id ($operation) processed successfully.');
        } on PostgrestException catch (pe) {
          final msg = pe.message;
          final code = pe.code;
          debugPrint('[SocialOutbox Error] PostgrestException on item $id ($operation): $msg (code: $code)');

          if (_isIdempotentSuccess(operation, msg, code)) {
            debugPrint('[SocialOutbox] Treating idempotent error as SUCCESS for item $id ($operation)');
            await _dao.removeFromOutbox(id);
          } else {
            await _dao.updateOutboxAttempts(id, attempts, msg);
            if (attempts >= 3) {
              await _dao.removeFromOutbox(id);
            }
          }
        } catch (e) {
          final errorMsg = e.toString();
          debugPrint('[SocialOutbox Error] Generic error on item $id ($operation): $errorMsg');
          await _dao.updateOutboxAttempts(id, attempts, errorMsg);
          if (attempts >= 3) {
            await _dao.removeFromOutbox(id);
          }
        }
      }
    } finally {
      _isProcessing = false;
    }
  }

  bool _isIdempotentSuccess(String operation, String message, String? code) {
    if (code == '23505') return true; // Unique constraint violation

    final msgLower = message.toLowerCase();
    if (msgLower.contains('une demande est déjà en attente') ||
        msgLower.contains('déjà ami') ||
        msgLower.contains('déjà été traitée') ||
        msgLower.contains('demande introuvable ou déjà traitée') ||
        msgLower.contains('pas ami')) {
      return true;
    }
    return false;
  }

  Future<void> _executeOperation({
    required String operation,
    required Map<String, dynamic> payload,
  }) async {
    switch (operation) {
      case 'send_friend_request':
        final receiverId = payload['receiver_id'] as String;
        await _client.rpc('send_friend_request', params: {'p_receiver_id': receiverId});
        break;

      case 'respond_friend_request':
        final requestId = payload['request_id'] as String;
        final accepted = payload['accepted'] as bool;
        await _client.rpc('respond_friend_request', params: {
          'p_request_id': requestId,
          'p_accepted': accepted,
        });
        break;

      case 'cancel_friend_request':
        final requestId = payload['request_id'] as String;
        await _client.rpc('cancel_friend_request', params: {'p_request_id': requestId});
        break;

      case 'remove_friendship':
        final otherUserId = payload['other_user_id'] as String;
        await _client.rpc('remove_friendship', params: {'p_other_user_id': otherUserId});
        break;

      case 'generate_user_qr_code':
        final qrId = payload['id'] as String;
        await _client.rpc('generate_user_qr_code', params: {'p_id': qrId});
        break;

      case 'scan_qr_code':
        final qrId = payload['qr_id'] as String;
        final mode = payload['mode'] as String;
        await _client.rpc('scan_qr_code', params: {'p_qr_id': qrId, 'p_mode': mode});
        break;

      case 'block_user':
        final targetId = payload['bloque_id'] as String;
        final reason = payload['raison'] as String?;
        final until = payload['bloque_jusquau'] as String?;

        // 1. Remove friendship first (§7)
        try {
          await _client.rpc('remove_friendship', params: {'p_other_user_id': targetId});
        } catch (_) {}

        // 2. Insert into blocage_utilisateur
        await _client.from('blocage_utilisateur').insert({
          'bloqueur_id': _client.auth.currentUser?.id,
          'bloque_id': targetId,
          if (reason != null && reason.isNotEmpty) 'raison': reason,
          if (until != null && until.isNotEmpty) 'bloque_jusquau': until,
        });
        break;

      case 'unblock_user':
        final targetId = payload['bloque_id'] as String;
        await _client
            .from('blocage_utilisateur')
            .delete()
            .eq('bloqueur_id', _client.auth.currentUser?.id ?? '')
            .eq('bloque_id', targetId);
        break;

      default:
        debugPrint('[SocialOutbox Warning] Unknown operation: $operation');
        break;
    }
  }

  @override
  void onClose() {
    _connectivitySub?.cancel();
    super.onClose();
  }
}
