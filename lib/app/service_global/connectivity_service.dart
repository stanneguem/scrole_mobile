import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:internet_connection_checker_plus/internet_connection_checker_plus.dart';

import '../../shared/etats/connectivity_states.dart';

class ConnectivityService extends GetxService with WidgetsBindingObserver {
  final Connectivity _connectivity = Connectivity();
  final InternetConnection _internetChecker = InternetConnection();

  final RxBool isConnected = true.obs;
  final Rx<ConnectionBannerState> bannerState =
      ConnectionBannerState.hidden.obs;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<InternetStatus>? _internetSub;
  Timer? _bannerTimer;

  bool _isDisposed = false;
  bool _isForeground = true;
  bool _isListening = false;

  bool get _canPublish => !_isDisposed && _isForeground;

  Future<ConnectivityService> init() async {
    if (_isDisposed || _isListening) return this;

    _isListening = true;
    WidgetsBinding.instance.addObserver(this);
    _isForeground =
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.detached &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.hidden &&
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.paused;

    // Les vérifications réseau ne doivent jamais bloquer le premier rendu.
    unawaited(_checkInitialConnection());
    _listenConnectivity();
    return this;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isForeground = state == AppLifecycleState.resumed;

    // Sur le Web, le navigateur peut envoyer des événements réseau pendant
    // que la vue Flutter est masquée ou en cours de démontage. On ignore ces
    // événements jusqu'au retour effectif de l'application au premier plan.
    if (_isForeground && !_isDisposed) {
      unawaited(_checkInitialConnection());
    }
  }

  Future<void> _checkInitialConnection() async {
    try {
      final status = await _internetChecker.hasInternetAccess.timeout(
        const Duration(seconds: 2),
      );
      if (!_canPublish) return;
      _setConnected(status);
    } catch (_) {
      if (!_canPublish) return;
      // Conserver l'état courant en cas de timeout/erreur transitoire :
      // une vérification échouée ne prouve pas que l'appareil est hors ligne.
    }
  }

  void _listenConnectivity() {
    _connectivitySub = _connectivity.onConnectivityChanged.listen((results) {
      if (!_canPublish) return;

      final hasInterface =
          results.isNotEmpty && !results.contains(ConnectivityResult.none);
      if (!hasInterface) _setConnected(false);
    });

    _internetSub = _internetChecker.onStatusChange.listen((status) {
      if (!_canPublish) return;

      _setConnected(status == InternetStatus.connected);
    });
  }

  void _setConnected(bool connected) {
    if (!_canPublish || isConnected.value == connected) return;

    final wasOffline = !isConnected.value;
    isConnected.value = connected;

    _bannerTimer?.cancel();
    if (wasOffline && connected) {
      bannerState.value = ConnectionBannerState.backOnline;
      _bannerTimer = Timer(const Duration(seconds: 2), () {
        if (!_canPublish) return;
        if (bannerState.value == ConnectionBannerState.backOnline) {
          bannerState.value = ConnectionBannerState.hidden;
        }
      });
    } else if (!connected) {
      bannerState.value = ConnectionBannerState.offline;
    } else {
      bannerState.value = ConnectionBannerState.hidden;
    }
  }

  Future<bool> checkConnection() async {
    final result = await _internetChecker.hasInternetAccess;
    if (_canPublish) _setConnected(result);
    return result;
  }

  Stream<InternetStatus> get onStatusChange =>
      _internetChecker.onStatusChange;

  @override
  void onClose() {
    _isDisposed = true;
    _isForeground = false;
    _bannerTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySub?.cancel();
    _internetSub?.cancel();
    super.onClose();
  }
}
