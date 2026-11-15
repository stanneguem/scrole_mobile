import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:scrole/modules/module_communautes/interne/pages/create_community_post_screen.dart';

class CreateScutCameraScreen extends StatefulWidget {
  const CreateScutCameraScreen({super.key});

  @override
  State<CreateScutCameraScreen> createState() => _CreateScutCameraScreenState();
}

class _CreateScutCameraScreenState extends State<CreateScutCameraScreen>
    with WidgetsBindingObserver {
  final ImagePicker _galleryPicker = ImagePicker();
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isOpeningNextScreen = false;
  String? _cameraError;
  File? _videoCapturedBeforePause;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _recordingTimer?.cancel();
    final controller = _cameraController;
    _cameraController = null;
    if (controller != null) {
      unawaited(controller.dispose());
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(_releaseCameraForLifecycle());
    } else if (state == AppLifecycleState.resumed) {
      if (_videoCapturedBeforePause != null) {
        final file = _videoCapturedBeforePause!;
        _videoCapturedBeforePause = null;
        _openComposer(file);
      } else {
        _initializeCamera();
      }
    }
  }

  Future<void> _releaseCameraForLifecycle() async {
    _recordingTimer?.cancel();
    final controller = _cameraController;
    if (controller == null) return;
    try {
      if (controller.value.isRecordingVideo) {
        final captured = await controller.stopVideoRecording();
        _videoCapturedBeforePause = File(captured.path);
      }
    } catch (error) {
      debugPrint('[SCUT_CAMERA] Could not finalize recording on lifecycle change: $error');
    }
    _isRecording = false;
    _cameraController = null;
    await controller.dispose();
  }

  Future<void> _initializeCamera({CameraDescription? preferredCamera}) async {
    if (!mounted) return;
    setState(() {
      _isInitializing = true;
      _cameraError = null;
    });

    CameraController? nextController;
    try {
      if (_cameras.isEmpty) {
        _cameras = await availableCameras();
      }
      if (_cameras.isEmpty) {
        throw CameraException('NoCamera', 'Aucune caméra disponible sur cet appareil.');
      }

      final camera = preferredCamera ??
          _cameras.firstWhere(
            (item) => item.lensDirection == CameraLensDirection.front,
            orElse: () => _cameras.first,
          );
      nextController = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: true,
      );
      await nextController.initialize();
      if (!mounted) {
        await nextController.dispose();
        return;
      }
      final previous = _cameraController;
      _cameraController = nextController;
      nextController = null;
      if (previous != null) await previous.dispose();
      setState(() => _isInitializing = false);
    } catch (error) {
      if (nextController != null) await nextController.dispose();
      if (!mounted) return;
      setState(() {
        _isInitializing = false;
        _cameraError = error is CameraException &&
                (error.code == 'CameraAccessDenied' ||
                    error.code == 'CameraAccessDeniedWithoutPrompt')
            ? 'Autorise l’accès à la caméra dans les paramètres du téléphone.'
            : error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_isRecording || _isInitializing || _cameras.length < 2) return;
    final current = _cameraController?.description;
    if (current == null) return;
    final next = _cameras.firstWhere(
      (camera) => camera.lensDirection != current.lensDirection,
      orElse: () => _cameras.first,
    );
    final old = _cameraController;
    _cameraController = null;
    if (old != null) await old.dispose();
    await _initializeCamera(preferredCamera: next);
  }

  Future<void> _toggleRecording() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized ||
        _isInitializing || _isOpeningNextScreen) {
      return;
    }

    try {
      if (!_isRecording) {
        await controller.prepareForVideoRecording();
        await controller.startVideoRecording();
        if (!mounted) return;
        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });
        _recordingTimer?.cancel();
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() => _recordingSeconds++);
        });
      } else {
        _recordingTimer?.cancel();
        final captured = await controller.stopVideoRecording();
        if (!mounted) return;
        setState(() => _isRecording = false);
        await _openComposer(File(captured.path));
      }
    } catch (error) {
      _recordingTimer?.cancel();
      if (mounted) {
        setState(() => _isRecording = false);
        Get.snackbar(
          'Enregistrement impossible',
          error.toString().replaceFirst('Exception: ', ''),
          snackPosition: SnackPosition.BOTTOM,
        );
      }
    }
  }

  Future<void> _openGallery() async {
    if (_isRecording || _isOpeningNextScreen) return;
    try {
      final selected = await _galleryPicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10),
      );
      if (selected == null || !mounted) return;
      await _openComposer(File(selected.path));
    } catch (error) {
      if (!mounted) return;
      Get.snackbar(
        'Galerie indisponible',
        error.toString().replaceFirst('Exception: ', ''),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  Future<void> _openComposer(File videoFile) async {
    if (_isOpeningNextScreen || !mounted) return;
    if (!await videoFile.exists() || await videoFile.length() <= 0) {
      Get.snackbar('Vidéo indisponible', 'Le fichier vidéo sélectionné est introuvable.');
      return;
    }
    setState(() => _isOpeningNextScreen = true);
    Get.off(
      () => CreateCommunityPostScreen(
        communityName: 'Fil d’actualité général',
        prefilledMediaUrl: videoFile.path,
        prefilledMediaIsVideo: true,
      ),
    );
  }

  String get _formattedDuration {
    final minutes = (_recordingSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_recordingSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _cameraController;
    final size = MediaQuery.sizeOf(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (controller != null && controller.value.isInitialized)
            ClipRect(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width: controller.value.previewSize?.height ?? size.width,
                  height: controller.value.previewSize?.width ?? size.height,
                  child: CameraPreview(controller),
                ),
              ),
            )
          else
            const ColoredBox(color: Colors.black),
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x99000000), Colors.transparent, Color(0xAA000000)],
                stops: [0, 0.38, 1],
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
                  child: Row(
                    children: [
                      _RoundCameraButton(
                        icon: Icons.close_rounded,
                        onTap: () => Get.back(),
                      ),
                      const Spacer(),
                      Text(
                        'creation_menu_create_scut'.tr,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      _RoundCameraButton(
                        icon: Icons.flip_camera_android_rounded,
                        onTap: _switchCamera,
                        enabled: !_isRecording && _cameras.length > 1,
                      ),
                    ],
                  ),
                ),
                if (_isRecording)
                  Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Text(
                            _formattedDuration,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                if (_isInitializing)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 28),
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else if (_cameraError != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                    child: Column(
                      children: [
                        const Icon(Icons.no_photography_outlined,
                            color: Colors.white, size: 42),
                        const SizedBox(height: 12),
                        Text(
                          _cameraError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white),
                        ),
                        const SizedBox(height: 14),
                        OutlinedButton(
                          onPressed: _initializeCamera,
                          child: const Text('Réessayer'),
                        ),
                      ],
                    ),
                  )
                else
                  Padding(
                    padding: const EdgeInsets.fromLTRB(34, 0, 34, 26),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _RoundCameraButton(
                          icon: Icons.photo_library_outlined,
                          onTap: _openGallery,
                          size: 54,
                        ),
                        GestureDetector(
                          onTap: _toggleRecording,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            width: _isRecording ? 78 : 72,
                            height: _isRecording ? 78 : 72,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 5),
                            ),
                            child: Center(
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                width: _isRecording ? 30 : 56,
                                height: _isRecording ? 30 : 56,
                                decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(
                                    _isRecording ? 8 : 40,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 54, height: 54),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RoundCameraButton extends StatelessWidget {
  const _RoundCameraButton({
    required this.icon,
    required this.onTap,
    this.size = 42,
    this.enabled = true,
  });

  final IconData icon;
  final VoidCallback onTap;
  final double size;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.42),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: enabled ? onTap : null,
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            icon,
            color: enabled ? Colors.white : Colors.white38,
            size: 23,
          ),
        ),
      ),
    );
  }
}
