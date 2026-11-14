import 'dart:async';
import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:get/get.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../module_creation_de_compte/centre/services/user_service.dart';
import '../../../module_notification/externe/repositories/fcm_token_repository.dart';
import '../../../../app/service_global/notification_service.dart';
import '../../externe/repositories/auth_repository.dart';

class AuthService extends GetxService {
  final AuthRepository _authRepository = AuthRepository();
  final FcmTokenRepository _fcmTokenRepository = FcmTokenRepository(Supabase.instance.client);

  final RxBool isLoading = false.obs;
  final Rxn<User> currentUser = Rxn<User>();
  final RxBool isAuthenticated = false.obs;
  StreamSubscription? _authSubscription;
  String? _lastUserId;

  @override
  void onInit() {
    super.onInit();
    _initializeAuthState();
    _listenAuthChanges();
  }

  void _initializeAuthState() {
    final user = _authRepository.currentUser;
    _lastUserId = user?.id;
    currentUser.value = user;
    isAuthenticated.value = user != null;
  }

  void _listenAuthChanges() {
    _authSubscription = _authRepository.onAuthStateChange().listen(
      (authState) {
        final event = authState.event;
        final user = authState.session?.user;
        if (event == AuthChangeEvent.tokenRefreshed) return;

        if (event == AuthChangeEvent.signedOut) {
          _lastUserId = null;
          currentUser.value = null;
          isAuthenticated.value = false;
        } else if (user != null) {
          final userChanged = _lastUserId != user.id;
          _lastUserId = user.id;
          isAuthenticated.value = true;
          if (userChanged || currentUser.value == null) currentUser.value = user;
        } else {
          isAuthenticated.value = false;
          currentUser.value = null;
          _lastUserId = null;
        }

        if (kDebugMode) print('Auth state changed [$event]: ${user?.email ?? 'No user'}');
      },
      onError: (error, stackTrace) {
        if (kDebugMode) {
          print('[Auth] Exception interceptée sur le flux auth (PKCE/deeplink) : $error');
        }
      },
    );
  }

  Future<bool> signInWithGoogle() async {
    try {
      isLoading.value = true;
      await Get.find<UserService>().clearCache();
      return await _authRepository.signInWithGoogle();
    } catch (e) {
      if (kDebugMode) print('Erreur de connexion: $e');
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> signOut() async {
    try {
      isLoading.value = true;
      final token = await NotificationService.instance.getDeviceToken();
      if (token != null) {
        try {
          // Désactiver le token sur le serveur avant de se déconnecter
          await _fcmTokenRepository.unregisterToken(token);
        } catch (e) {
          if (kDebugMode) print('Erreur désactivation device push: $e');
        }
      }

      await _authRepository.signOut();
      await _clearScutOfflineCache();
      currentUser.value = null;
      isAuthenticated.value = false;
      _lastUserId = null;

      // Optionnel : Supprimer le token FCM localement pour forcer une rotation
      // au prochain login sur cet appareil.
      if (!kIsWeb) {
        await FirebaseMessaging.instance.deleteToken();
      }

      if (kDebugMode) print('Déconnexion réussie');
    } catch (e) {
      if (kDebugMode) print('Erreur de déconnexion: $e');
      rethrow;
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> _clearScutOfflineCache() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final videoCache = Directory('${directory.path}/scut_video_cache');
      if (await videoCache.exists()) {
        await videoCache.delete(recursive: true);
      }
      final manifest = File('${directory.path}/scut_feed_cache.json');
      if (await manifest.exists()) await manifest.delete();
    } catch (error) {
      if (kDebugMode) print('[Auth] Unable to clear Scut offline cache: $error');
    }
  }

  bool get isLoggedIn => isAuthenticated.value;
  String? get userId => currentUser.value?.id;
  String? get userEmail => currentUser.value?.email;

  @override
  void onClose() {
    _authSubscription?.cancel();
    super.onClose();
  }
}
