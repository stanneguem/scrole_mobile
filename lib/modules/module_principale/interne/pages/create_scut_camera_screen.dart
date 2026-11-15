import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:camera/camera.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:scrole/modules/module_communautes/interne/pages/create_community_post_screen.dart';
import 'package:scrole/modules/module_principale/centre/services/scut_sticker_renderer.dart';
import 'package:scrole/modules/module_principale/interne/pages/scut_sticker_editor_screen.dart';
import 'package:scrole/shared/widgets/media_gallery_sheet.dart';

class CreateScutCameraScreen extends StatefulWidget {
  const CreateScutCameraScreen({super.key});

  @override
  State<CreateScutCameraScreen> createState() => _CreateScutCameraScreenState();
}

class _CreateScutCameraScreenState extends State<CreateScutCameraScreen>
    with WidgetsBindingObserver {
  List<CameraDescription> _cameras = [];
  CameraController? _cameraController;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;
  bool _isInitializing = true;
  bool _isRecording = false;
  bool _isOpeningNextScreen = false;
  String? _cameraError;
  File? _videoCapturedBeforePause;
  bool _isFlashOn = false;
  final List<ScutSticker> _stickers = [];

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
        _openComposer(file, isVideo: true);
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
    _isFlashOn = false;
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
    _isFlashOn = false;
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
        await _openComposer(File(captured.path), isVideo: true);
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

  Future<void> _addSticker() async {
    if (_isRecording || _isOpeningNextScreen) return;
    const choices = ['😂','❤️','🔥','😍','🥰','😎','😭','✨','⭐','💯','🎉','👏','🤣','🤩','🥳','💖','💕','🌸','🦋','🌈','👑','💫','🤍','🙌'];
    final sticker = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Ajouter un sticker', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 16),
              GridView.count(
                crossAxisCount: 6,
                shrinkWrap: true,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                children: choices.map((item) => InkWell(
                  onTap: () => Navigator.pop(context, item),
                  child: Center(child: Text(item, style: const TextStyle(fontSize: 30))),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (sticker == null || !mounted) return;
    setState(() => _stickers.add(ScutSticker(emoji: sticker, x: .5, y: .48)));
  }

  Future<void> _openGallery() async {
    if (_isRecording || _isOpeningNextScreen) return;
    try {
      final selected = await showModalBottomSheet<List<XFile>>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => MediaGallerySheet(
          maxSelection: 1,
          allowMixedMedia: true,
          onSelected: (_) async {},
        ),
      );
      if (!mounted || selected == null || selected.isEmpty) return;

      final media = selected.first;
      final file = File(media.path);
      final isVideo = media.mimeType?.startsWith('video/') ??
          _isVideoFile(media.path);
      if (!isVideo) {
        Get.snackbar(
          'Format non pris en charge',
          'Pour créer un Scut, sélectionne une vidéo dans l’onglet Vidéos.',
          snackPosition: SnackPosition.BOTTOM,
        );
        return;
      }
      await _openComposer(file, isVideo: true);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar(
        'Galerie indisponible',
        error.toString().replaceFirst('Exception: ', ''),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  bool _isVideoFile(String path) {
    final extension = path.split('.').last.toLowerCase();
    return const {'mp4', 'mov', 'm4v', 'webm', 'mkv', '3gp', 'avi', 'ts'}
        .contains(extension);
  }

  Future<void> _openComposer(File mediaFile, {required bool isVideo}) async {
    if (_isOpeningNextScreen || !mounted) return;
    if (!await mediaFile.exists() || await mediaFile.length() <= 0) {
      Get.snackbar('Média indisponible', 'Le fichier sélectionné est introuvable.');
      return;
    }
    setState(() => _isOpeningNextScreen = true);
    File finalMedia = mediaFile;
    if (isVideo) {
      final edited = await Get.to<File>(
        () => ScutStickerEditorScreen(
          videoFile: mediaFile,
          initialStickers: List<ScutSticker>.from(_stickers),
        ),
      );
      if (!mounted) return;
      if (edited == null) {
        setState(() => _isOpeningNextScreen = false);
        return;
      }
      finalMedia = edited;
    }
    Get.off(
      () => CreateCommunityPostScreen(
        communityName: 'Fil d’actualité général',
        prefilledMediaUrl: finalMedia.path,
        prefilledMediaIsVideo: isVideo,
      ),
    );
  }

  bool get controllerCanUseFlash =>
      _cameraController?.description.lensDirection == CameraLensDirection.back;

  Future<void> _toggleFlash() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized ||
        _isRecording || !controllerCanUseFlash) return;
    final next = !_isFlashOn;
    try {
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (mounted) setState(() => _isFlashOn = next);
    } catch (error) {
      if (!mounted) return;
      Get.snackbar(
        'Flash indisponible',
        error.toString().replaceFirst('Exception: ', ''),
        snackPosition: SnackPosition.BOTTOM,
      );
    }
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
          if (_stickers.isNotEmpty)
            ..._stickers.asMap().entries.map((entry) {
              final sticker = entry.value;
              return Positioned(
                left: sticker.x * size.width - 28,
                top: sticker.y * size.height - 28,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    if (_isRecording) return;
                    setState(() {
                      _stickers[entry.key] = sticker.copyWith(
                        x: (sticker.x + details.delta.dx / size.width).clamp(.02, .98),
                        y: (sticker.y + details.delta.dy / size.height).clamp(.02, .98),
                      );
                    });
                  },
                  child: Transform.rotate(
                    angle: sticker.rotation,
                    child: Text(sticker.emoji, style: TextStyle(fontSize: size.width * sticker.size)),
                  ),
                ),
              );
            }),
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
                        icon: _isFlashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
                        onTap: _toggleFlash,
                        enabled: !_isRecording && controllerCanUseFlash,
                      ),
                      const SizedBox(width: 8),
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
                    child: SizedBox(
                      width: double.infinity,
                      height: 78,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            right: 0,
                            child: _RoundCameraButton(
                              icon: Icons.emoji_emotions_outlined,
                              onTap: _addSticker,
                              size: 54,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            child: _RoundCameraButton(
                              icon: Icons.photo_library_outlined,
                              onTap: _openGallery,
                              size: 54,
                            ),
                          ),
                          GestureDetector(
                            onTap: _toggleRecording,
                            child: Container(
                              width: 72,
                              height: 72,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: 5,
                                ),
                              ),
                              child: Center(
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 160),
                                  width: _isRecording ? 28 : 56,
                                  height: _isRecording ? 28 : 56,
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(
                                      _isRecording ? 7 : 40,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
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


