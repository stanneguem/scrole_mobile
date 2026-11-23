import 'dart:async';
import 'dart:convert';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../modules/module_authentification/centre/services/auth_service.dart';
import '../../modules/module_notification/externe/repositories/fcm_token_repository.dart';
import '../../modules/module_notification/centre/services/notification_db_service.dart';
import '../../modules/module_notification/centre/services/notification_deep_link_router.dart';

/// FCM Web registration. Browser permission is requested only from the
/// explicit enablePushNotifications() action (never during app startup).
class WebPushNotificationService extends GetxService {
  static const String vapidPublicKey =
      'BK6hsP4yA-GRk52zVSSNs-3-4XUljrOA6sAOtyZnAx2tVcf22TbAeWfvaEXhhDua0GH5eAwobFX0GuMv3ev6zL8';

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  late final FcmTokenRepository _tokens =
      FcmTokenRepository(Supabase.instance.client);
  StreamSubscription<String>? _tokenRefresh;
  StreamSubscription<RemoteMessage>? _foreground;
  StreamSubscription<RemoteMessage>? _opened;
  Worker? _authWorker;
  bool _initialized = false;

  Future<WebPushNotificationService> init() async {
    if (!kIsWeb) return this;
    _foreground = FirebaseMessaging.onMessage.listen((message) {
      // Foreground notifications are already synchronized by Supabase Realtime.
      debugPrint('[WebPush] Foreground push received: ${message.data['type']}');
    });
    _opened = FirebaseMessaging.onMessageOpenedApp.listen((message) {
      unawaited(NotificationDeepLinkRouter.open(message.data));
    });
    _tokenRefresh = _messaging.onTokenRefresh.listen((token) {
      unawaited(_register(token));
    });
    try {
      final auth = Get.find<AuthService>();
      _authWorker = ever(auth.currentUser, (_) {
        unawaited(_registerExistingPermission());
      });
    } catch (error) {
      debugPrint('[WebPush] Auth listener unavailable: $error');
    }
    _initialized = true;
    await _registerExistingPermission();
    unawaited(_handleBrowserLaunchPayload());
    return this;
  }

  Future<bool> get isPermissionGranted async {
    if (!kIsWeb) return false;
    final settings = await _messaging.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<bool> enablePushNotifications() async {
    if (!kIsWeb) return false;
    try {
      final settings = await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return false;
      }
      final token = await _messaging.getToken(vapidKey: vapidPublicKey);
      if (token == null || token.isEmpty) return false;
      await _register(token);
      return true;
    } catch (error, stack) {
      debugPrint('[WebPush] Activation failed: $error');
      debugPrint('$stack');
      return false;
    }
  }

  Future<void> _registerExistingPermission() async {
    if (!_initialized || Supabase.instance.client.auth.currentUser == null) return;
    try {
      final permission = await _messaging.getNotificationSettings();
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }
      final token = await _messaging.getToken(vapidKey: vapidPublicKey);
      if (token != null && token.isNotEmpty) await _register(token);
    } catch (error) {
      debugPrint('[WebPush] Existing permission registration failed: $error');
    }
  }

  Future<void> _register(String token) async {
    if (Supabase.instance.client.auth.currentUser == null) return;
    try {
      final missed = await _tokens.registerToken(
        token: token,
        platform: 'web',
        deviceBrand: 'Browser',
        deviceModel: defaultTargetPlatform.name,
      );
      if (Get.isRegistered<NotificationDbService>()) {
        final db = Get.find<NotificationDbService>();
        final userId = Supabase.instance.client.auth.currentUser?.id;
        if (userId != null) {
          for (final row in missed) {
            final rawData = row['data'];
            final data = rawData is Map
                ? Map<String, dynamic>.from(rawData)
                : <String, dynamic>{};
            final id = row['id']?.toString();
            if (id == null || id.isEmpty) continue;
            await db.saveNotification(
              id: id,
              userId: userId,
              title: row['title']?.toString() ?? 'Scrole',
              message: row['body']?.toString() ?? '',
              type: row['type']?.toString() ?? 'info',
              payload: jsonEncode({
                ...data,
                'type': row['type'] ?? 'info',
                'notification_id': id,
                if (row['actor_id'] != null) 'actor_id': row['actor_id'],
              }),
              createdAt: DateTime.tryParse(row['created_at']?.toString() ?? ''),
              isRead: row['read_at'] != null,
            );
          }
        }
      }
      debugPrint('[WebPush] Browser token registered.');
    } catch (error) {
      debugPrint('[WebPush] Token registration failed: $error');
    }
  }

  Future<void> _handleBrowserLaunchPayload() async {
    if (!kIsWeb) return;
    final encoded = Uri.base.queryParameters['push_data'];
    if (encoded == null || encoded.isEmpty) return;
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        await NotificationDeepLinkRouter.open(Map<String, dynamic>.from(decoded));
      }
    } catch (error) {
      debugPrint('[WebPush] Invalid launch payload: $error');
    }
  }

  Future<void> disablePushNotifications() async {
    if (!kIsWeb) return;
    try {
      final token = await _messaging.getToken(vapidKey: vapidPublicKey);
      if (token != null && token.isNotEmpty) {
        await _tokens.unregisterToken(token);
        await _messaging.deleteToken();
      }
    } catch (error) {
      debugPrint('[WebPush] Token removal failed: $error');
    }
  }

  @override
  void onClose() {
    _authWorker?.dispose();
    unawaited(_tokenRefresh?.cancel());
    unawaited(_foreground?.cancel());
    unawaited(_opened?.cancel());
    super.onClose();
  }
}
