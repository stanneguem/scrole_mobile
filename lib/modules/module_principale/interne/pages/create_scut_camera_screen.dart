import 'dart:async';
import 'dart:io';
import 'dart:ui' show FontFeature;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'package:scrole/modules/module_communautes/interne/pages/create_community_post_screen.dart';
import 'package:scrole/modules/module_principale/centre/services/scut_video_filter_service.dart';

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
  bool _isProcessingFilter = false;
  String? _cameraError;
  File? _videoCapturedBeforePause;
  int _selectedFilterIndex = 0;

  static const List<_ScutBeautyFilter> _beautyFilters = [
    _ScutBeautyFilter('Original', Icons.videocam_outlined, null),
    _ScutBeautyFilter('Naturel', Icons.face_retouching_natural, <double>[
      1.04, 0, 0, 0, 3, 0, 1.04, 0, 0, 3, 0, 0, 1.04, 0, 3, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Doux', Icons.auto_awesome, <double>[
      1.08, 0, 0, 0, 8, 0, 1.08, 0, 0, 8, 0, 0, 1.08, 0, 8, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Éclat', Icons.wb_sunny_outlined, <double>[
      1.12, 0, 0, 0, 10, 0, 1.12, 0, 0, 10, 0, 0, 1.12, 0, 10, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Chaud', Icons.wb_twilight, <double>[
      1.08, 0, 0, 0, 7, 0, 1.02, 0, 0, 2, 0, 0, 0.94, 0, -3, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Golden Hour', Icons.wb_sunny_rounded, <double>[
      1.16, 0, 0, 0, 13, 0, 1.06, 0, 0, 5, 0, 0, 0.84, 0, -5, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Cinéma froid', Icons.ac_unit_rounded, <double>[
      0.92, 0, 0, 0, -2, 0, 1.02, 0, 0, 1, 0, 0, 1.16, 0, 8, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Vintage', Icons.photo_camera_back_outlined, <double>[
      0.90, 0.08, 0.02, 0, 12, 0.04, 0.88, 0.04, 0, 8, 0.02, 0.06, 0.78, 0, 2, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('N&B', Icons.monochrome_photos, <double>[
      0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0.2126, 0.7152, 0.0722, 0, 0, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Pastel', Icons.palette_outlined, <double>[
      0.92, 0.04, 0.02, 0, 18, 0.03, 0.94, 0.03, 0, 17, 0.02, 0.04, 0.96, 0, 20, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Moody', Icons.nights_stay_outlined, <double>[
      0.88, 0, 0.04, 0, -5, 0, 0.91, 0.02, 0, -4, 0.02, 0.04, 1.02, 0, 2, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Rétro 90s', Icons.grain, <double>[
      1.08, 0.02, 0, 0, 7, 0.02, 0.98, 0.02, 0, 3, 0, 0.03, 0.88, 0, -2, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Dreamy', Icons.blur_on_rounded, <double>[
      1.04, 0.02, 0.02, 0, 15, 0.02, 1.03, 0.02, 0, 15, 0.02, 0.02, 1.04, 0, 16, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Matte', Icons.filter_vintage_outlined, <double>[
      0.92, 0, 0, 0, 14, 0, 0.92, 0, 0, 14, 0, 0, 0.92, 0, 14, 0, 0, 0, 1, 0,
    ]),
    _ScutBeautyFilter('Teal & Orange', Icons.theater_comedy_outlined, <double>[
      1.12, 0.02, -0.04, 0, 4, -0.02, 1.02, 0.04, 0, 2, 0.02, 0.08, 0.94, 0, 3, 0, 0, 0, 1, 0,
    ]),
  ];

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
        _openCapturedVideoWithFilter(file);
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

  Future<void> _showBeautyFilters() async {
    if (_isRecording || _isInitializing || _isOpeningNextScreen || _isProcessingFilter) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      isScrollControlled: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white30,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Filtres beauté',
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 18),
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _beautyFilters.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, index) {
                    final filter = _beautyFilters[index];
                    final selected = _selectedFilterIndex == index;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedFilterIndex = index);
                        Navigator.of(sheetContext).pop();
                      },
                      child: SizedBox(
                        width: 68,
                        child: Column(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 58,
                              height: 58,
                              decoration: BoxDecoration(
                                color: selected ? Colors.white : Colors.white12,
                                shape: BoxShape.circle,
                                border: Border.all(color: selected ? Colors.white : Colors.white24, width: 2),
                              ),
                              child: Icon(filter.icon, color: selected ? Colors.black : Colors.white, size: 25),
                            ),
                            const SizedBox(height: 7),
                            Text(filter.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: selected ? Colors.white : Colors.white70, fontSize: 11, fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Choisis un rendu avant de commencer ta vidéo.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _switchCamera() async {
    if (_isRecording || _isInitializing || _isProcessingFilter || _cameras.length < 2) return;
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
        _isInitializing || _isOpeningNextScreen || _isProcessingFilter) {
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
        await _openCapturedVideoWithFilter(File(captured.path));
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
    if (_isRecording || _isOpeningNextScreen || _isProcessingFilter) return;
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

  Future<void> _openCapturedVideoWithFilter(File originalVideo) async {
    if (!mounted || _isOpeningNextScreen || _isProcessingFilter) return;
    final filterName = _beautyFilters[_selectedFilterIndex].name;
    if (filterName == 'Original') {
      await _openComposer(originalVideo);
      return;
    }

    setState(() => _isProcessingFilter = true);
    try {
      final filteredVideo = await ScutVideoFilterService.applyFilter(
        input: originalVideo,
        filterName: filterName,
      );
      if (mounted) await _openComposer(filteredVideo);
    } catch (error) {
      debugPrint('[SCUT_CAMERA] Video filter rendering failed: $error');
      if (!mounted) return;
      Get.snackbar(
        'Filtre non appliqué',
        'La vidéo originale a été conservée. Réessaie ou publie-la sans filtre.',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
      await _openComposer(originalVideo);
    } finally {
      if (mounted) setState(() => _isProcessingFilter = false);
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
                  child: ColorFiltered(
                    colorFilter: _beautyFilters[_selectedFilterIndex].matrix == null
                        ? const ColorFilter.mode(Colors.transparent, BlendMode.dst)
                        : ColorFilter.matrix(_beautyFilters[_selectedFilterIndex].matrix!),
                    child: CameraPreview(controller),
                  ),
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
                if (_isProcessingFilter)
                  const Padding(
                    padding: EdgeInsets.only(top: 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(height: 10),
                        Text(
                          'Application du filtre à la vidéo…',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
                          enabled: !_isProcessingFilter,
                        ),
                        GestureDetector(
                          onTap: _isProcessingFilter ? null : _toggleRecording,
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
                        _RoundCameraButton(
                          icon: Icons.face_retouching_natural,
                          onTap: _showBeautyFilters,
                          size: 54,
                          enabled: !_isRecording && !_isProcessingFilter,
                        ),
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

class _ScutBeautyFilter {
  const _ScutBeautyFilter(this.name, this.icon, this.matrix);

  final String name;
  final IconData icon;
  final List<double>? matrix;
}
