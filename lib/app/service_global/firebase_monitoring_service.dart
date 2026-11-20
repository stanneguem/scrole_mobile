import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../firebase_options.dart';

/// Centralise les diagnostics Firebase de Scrole.
/// Ne jamais ajouter le contenu des messages, publications, e-mails ou jetons.
class FirebaseMonitoringService {
  FirebaseMonitoringService._();

  static bool _initialized = false;
  static bool get isInitialized => _initialized;

  static bool get _collectionEnabled =>
      kReleaseMode || const bool.fromEnvironment('ENABLE_FIREBASE_DIAGNOSTICS');

  static FirebaseAnalytics get analytics => FirebaseAnalytics.instance;

  static Future<void> initialize() async {
    if (kIsWeb || _initialized) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      await Future.wait([
        FirebaseCrashlytics.instance
            .setCrashlyticsCollectionEnabled(_collectionEnabled),
        FirebaseAnalytics.instance
            .setAnalyticsCollectionEnabled(_collectionEnabled),
      ]);

      final packageInfo = await PackageInfo.fromPlatform();
      await Future.wait([
        FirebaseCrashlytics.instance.setCustomKey('app_version', packageInfo.version),
        FirebaseCrashlytics.instance.setCustomKey('build_number', packageInfo.buildNumber),
        FirebaseCrashlytics.instance.setCustomKey('platform', defaultTargetPlatform.name),
        FirebaseCrashlytics.instance.setCustomKey(
          'build_mode',
          kReleaseMode ? 'release' : kProfileMode ? 'profile' : 'debug',
        ),
      ]);
      _initialized = true;
      debugPrint('[FirebaseMonitoring] Analytics et Crashlytics initialisés.');
    } catch (error, stackTrace) {
      // Les diagnostics ne doivent jamais empêcher le démarrage de Scrole.
      debugPrint('[FirebaseMonitoring] Initialisation impossible: $error');
      debugPrint('$stackTrace');
    }
  }

  static Future<void> recordFlutterError(FlutterErrorDetails details) async {
    if (!_initialized) return;
    try {
      await FirebaseCrashlytics.instance.recordFlutterFatalError(details);
    } catch (error) {
      debugPrint('[FirebaseMonitoring] Échec envoi erreur Flutter: $error');
    }
  }

  static Future<void> recordError(
    Object error,
    StackTrace stackTrace, {
    required bool fatal,
    String? reason,
  }) async {
    if (!_initialized) return;
    try {
      await FirebaseCrashlytics.instance.recordError(
        error,
        stackTrace,
        fatal: fatal,
        reason: reason,
      );
    } catch (reportError) {
      debugPrint('[FirebaseMonitoring] Échec envoi exception: $reportError');
    }
  }

  static Future<void> setUserIdentifier(String? identifier) async {
    if (!_initialized) return;
    try {
      await Future.wait([
        FirebaseCrashlytics.instance.setUserIdentifier(identifier ?? ''),
        FirebaseAnalytics.instance.setUserId(id: identifier),
      ]);
    } catch (error) {
      debugPrint('[FirebaseMonitoring] Échec mise à jour utilisateur: $error');
    }
  }

  static Future<void> logLogin() async {
    if (!_initialized) return;
    try {
      await analytics.logLogin(loginMethod: 'supabase');
    } catch (error) {
      debugPrint('[FirebaseMonitoring] Échec événement login: $error');
    }
  }

  static Future<void> logLogout() async {
    if (!_initialized) return;
    try {
      await analytics.logEvent(name: 'scrole_logout');
    } catch (error) {
      debugPrint('[FirebaseMonitoring] Échec événement logout: $error');
    }
  }
}
