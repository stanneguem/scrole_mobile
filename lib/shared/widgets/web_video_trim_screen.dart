import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;
import 'dart:math' as math;
import 'dart:js_util' as js_util;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

/// Browser-native trim: records only the selected playback interval.
/// Chromium generally exports WebM; Safari may export MP4 when supported.
class WebVideoTrimScreen extends StatefulWidget {
  final XFile videoFile;
  final Duration maxDuration;

  const WebVideoTrimScreen({
    super.key,
    required this.videoFile,
    this.maxDuration = const Duration(seconds: 60),
  });

  @override
  State<WebVideoTrimScreen> createState() => _WebVideoTrimScreenState();
}

class _WebVideoTrimScreenState extends State<WebVideoTrimScreen> {
  VideoPlayerController? _preview;
  bool _loading = true;
  bool _exporting = false;
  String? _error;
  Duration _duration = Duration.zero;
  RangeValues _range = const RangeValues(0, 60);
  int? _dragHandle;
  double _timelineWidth = 1;
  static const double _handleWidth = 18;
  final List<String?> _thumbnailData = List<String?>.filled(12, null);

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      final controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoFile.path));
      _preview = controller;
      await controller.initialize().timeout(const Duration(seconds: 30));
      final duration = controller.value.duration;
      if (duration <= Duration.zero) throw StateError('Durée vidéo introuvable.');
      if (!mounted) return;
      setState(() {
        _duration = duration;
        final max = widget.maxDuration.inMilliseconds / 1000;
        _range = RangeValues(0, duration.inMilliseconds / 1000 < max
            ? duration.inMilliseconds / 1000 : max);
        _loading = false;
      });
      unawaited(_loadTimelineThumbnails());
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<XFile> _exportSelection() async {
    final source = html.VideoElement()
      ..preload = 'auto'
      ..muted = false;
    final metadataLoaded = source.onLoadedMetadata.first;
    source.src = widget.videoFile.path;
    await metadataLoaded.timeout(const Duration(seconds: 30));
    final start = _range.start;
    final end = _range.end;
    if (end <= start || end - start > widget.maxDuration.inMilliseconds / 1000) {
      throw StateError('Sélection vidéo invalide.');
    }
    final stream = source.captureStream();
    final mediaRecorderConstructor = js_util.getProperty(html.window, 'MediaRecorder');
    final supportsMp4 = js_util.callMethod<bool>(
      mediaRecorderConstructor,
      'isTypeSupported',
      <Object?>['video/mp4'],
    );
    final mime = supportsMp4 ? 'video/mp4' : 'video/webm';
    final recorder = js_util.callConstructor(
      mediaRecorderConstructor,
      <Object?>[stream, js_util.jsify(<String, Object?>{'mimeType': mime})],
    );
    final chunks = <html.Blob>[];
    final stopped = Completer<void>();
    final onData = js_util.allowInterop((dynamic event) {
      final data = js_util.getProperty(event, 'data');
      if (data != null && (data as html.Blob).size > 0) {
        chunks.add(data);
      }
    });
    final onStop = js_util.allowInterop((dynamic _) {
      if (!stopped.isCompleted) stopped.complete();
    });
    js_util.callMethod<void>(recorder, 'addEventListener', <Object?>['dataavailable', onData]);
    js_util.callMethod<void>(recorder, 'addEventListener', <Object?>['stop', onStop]);
    try {
      final seekCompleted = source.onSeeked.first;
      source.currentTime = start;
      await seekCompleted.timeout(const Duration(seconds: 15));
      js_util.callMethod<void>(recorder, 'start', <Object?>[250]);
      await source.play();
      while (source.currentTime < end && !source.ended) {
        await source.onTimeUpdate.first.timeout(const Duration(seconds: 2));
      }
      source.pause();
      js_util.callMethod<void>(recorder, 'stop', <Object?>[]);
      await stopped.future.timeout(const Duration(minutes: 2));
      if (chunks.isEmpty) throw StateError('Le navigateur n’a produit aucun segment vidéo.');
      final blob = html.Blob(chunks, mime);
      final reader = html.FileReader();
      reader.readAsArrayBuffer(blob);
      await reader.onLoad.first.timeout(const Duration(minutes: 2));
      final result = reader.result;
      if (result is! ByteBuffer) throw StateError('Export vidéo illisible.');
      final bytes = Uint8List.view(result);
      if (bytes.isEmpty) throw StateError('Le segment vidéo est vide.');
      final extension = mime == 'video/mp4' ? 'mp4' : 'webm';
      return XFile.fromData(
        bytes,
        name: 'scrole-trimmed-${DateTime.now().millisecondsSinceEpoch}.$extension',
        mimeType: mime,
        length: bytes.length,
      );
    } finally {
      try { source.pause(); } catch (_) {}
      try { js_util.callMethod<void>(recorder, 'stop', <Object?>[]); } catch (_) {}
      for (final track in stream.getTracks()) {
        track.stop();
      }
      source.removeAttribute('src');
      source.load();
    }
  }

  Future<void> _confirm() async {
    if (_exporting || _loading || _error != null) return;
    setState(() => _exporting = true);
    try {
      final result = await _exportSelection();
      if (mounted) Get.back(result: result);
    } catch (e) {
      if (mounted) {
        setState(() => _exporting = false);
        Get.snackbar('Découpage impossible', e.toString(),
            snackPosition: SnackPosition.BOTTOM);
      }
    }
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  Future<void> _loadTimelineThumbnails() async {
    final video = html.VideoElement()
      ..preload = 'auto'
      ..muted = true
      ..src = widget.videoFile.path;
    try {
      await video.onLoadedMetadata.first.timeout(const Duration(seconds: 20));
      final canvas = html.CanvasElement(width: 120, height: 72);
      final context = canvas.context2D;
      for (var i = 0; i < _thumbnailData.length; i++) {
        if (!mounted) return;
        final target = (video.duration * (i + 0.5) / _thumbnailData.length)
            .clamp(0.0, math.max(0.0, video.duration - 0.05)).toDouble();
        final seeked = video.onSeeked.first;
        video.currentTime = target;
        await seeked.timeout(const Duration(seconds: 8));
        context.drawImageScaled(video, 0, 0, canvas.width!, canvas.height!);
        final data = canvas.toDataUrl('image/jpeg', 0.55);
        if (mounted) setState(() => _thumbnailData[i] = data);
      }
    } catch (e) {
      debugPrint('[WebVideoTrim] timeline thumbnails unavailable: $e');
    } finally {
      video.pause();
      video.removeAttribute('src');
      video.load();
    }
  }

  void _updateTrimFromDrag(double dx) {
    final total = _duration.inMilliseconds / 1000;
    if (total <= 0) return;
    final delta = dx / _timelineWidth * total;
    final max = widget.maxDuration.inMilliseconds / 1000;
    var start = _range.start;
    var end = _range.end;
    if (_dragHandle == 0) {
      start = (start + delta).clamp(0.0, end - 0.1).toDouble();
      if (end - start > max) start = end - max;
    } else if (_dragHandle == 1) {
      end = (end + delta).clamp(start + 0.1, total).toDouble();
      if (end - start > max) end = start + max;
    } else if (_dragHandle == 2) {
      final length = end - start;
      start = (start + delta).clamp(0.0, total - length).toDouble();
      end = start + length;
    }
    setState(() => _range = RangeValues(start, end));
    _preview?.seekTo(Duration(milliseconds: (start * 1000).round()));
  }

  Widget _buildTimeline() {
    final total = math.max(0.1, _duration.inMilliseconds / 1000);
    final start = _range.start / total;
    final end = _range.end / total;
    return LayoutBuilder(builder: (context, constraints) {
      _timelineWidth = constraints.maxWidth;
      final left = start * constraints.maxWidth;
      final right = end * constraints.maxWidth;
      final selectedWidth = math.max(36.0, right - left);
      return SizedBox(
        height: 58,
        child: Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  children: List.generate(12, (i) => Expanded(
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: .5),
                      color: i.isEven ? const Color(0xFF383838) : const Color(0xFF292929),
                      child: _thumbnailData[i] == null
                          ? null
                          : Image.network(_thumbnailData[i]!, fit: BoxFit.cover, gaplessPlayback: true),
                    ),
                  )),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Row(children: [
                  Container(width: left.clamp(0.0, constraints.maxWidth), color: Colors.black.withValues(alpha: .62)),
                  Expanded(child: Container(width: math.max(0, constraints.maxWidth-right), color: Colors.black.withValues(alpha: .62))),
                ]),
              ),
            ),
            Positioned(left: left, width: selectedWidth, top: 0, bottom: 0,
              child: IgnorePointer(child: Container(
                decoration: const BoxDecoration(
                  border: Border.symmetric(horizontal: BorderSide(color: Color(0xFFFFD21F), width: 3)),
                ),
              )),
            ),
            Positioned(left: left.clamp(0.0, constraints.maxWidth-18), top: 0, bottom: 0, width: 18,
              child: GestureDetector(
                onHorizontalDragStart: (_) => _dragHandle = 0,
                onHorizontalDragUpdate: (d) => _updateTrimFromDrag(d.delta.dx),
                onHorizontalDragEnd: (_) => _dragHandle = null,
                child: Container(
                  decoration: const BoxDecoration(color: Color(0xFFFFD21F), borderRadius: BorderRadius.horizontal(left: Radius.circular(8))),
                  alignment: Alignment.center,
                  child: const Icon(Icons.chevron_left_rounded, color: Colors.black, size: 22),
                ),
              ),
            ),
            Positioned(left: (right-18).clamp(0.0, constraints.maxWidth-18), top: 0, bottom: 0, width: 18,
              child: GestureDetector(
                onHorizontalDragStart: (_) => _dragHandle = 1,
                onHorizontalDragUpdate: (d) => _updateTrimFromDrag(d.delta.dx),
                onHorizontalDragEnd: (_) => _dragHandle = null,
                child: Container(
                  decoration: const BoxDecoration(color: Color(0xFFFFD21F), borderRadius: BorderRadius.horizontal(right: Radius.circular(8))),
                  alignment: Alignment.center,
                  child: const Icon(Icons.chevron_right_rounded, color: Colors.black, size: 22),
                ),
              ),
            ),
            Positioned(left: (left+18).clamp(0.0, constraints.maxWidth), width: math.max(0.0, selectedWidth-36), top: 0, bottom: 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragStart: (_) => _dragHandle = 2,
                onHorizontalDragUpdate: (d) => _updateTrimFromDrag(d.delta.dx),
                onHorizontalDragEnd: (_) => _dragHandle = null,
              ),
            ),
          ],
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final ready = !_loading && _error == null;
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
            SizedBox(
              height: 48,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
                    onPressed: _exporting ? null : () => Get.back<XFile?>(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded, color: Color(0xFFFFD21F), size: 22),
                    onPressed: _loading || _error != null ? null : () {
                      final controller = _preview;
                      if (controller != null) {
                        controller.setVolume(controller.value.volume > 0 ? 0 : 1);
                      }
                    },
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: ready && !_exporting ? _confirm : null,
                    child: const Text('Terminer', style: TextStyle(
                      color: Color(0xFFFFD21F), fontWeight: FontWeight.w800, fontSize: 16,
                    )),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
            Expanded(
              child: _loading
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : _error != null
                  ? Center(child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('Impossible de lire cette vidéo sur cet appareil. $_error',
                        style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                    ))
                  : GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        final controller = _preview;
                        if (controller == null) return;
                        controller.value.isPlaying ? controller.pause() : controller.play();
                      },
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: (_preview?.value.aspectRatio ?? 16 / 9).clamp(0.5, 2.4).toDouble(),
                          child: VideoPlayer(_preview!),
                        ),
                      ),
                    ),
            ),
            if (ready)
              Container(
                color: Colors.black,
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () {
                        final controller = _preview;
                        if (controller == null) return;
                        controller.value.isPlaying ? controller.pause() : controller.play();
                      },
                      child: Container(
                        width: 44, height: 52,
                        decoration: BoxDecoration(color: const Color(0xFF2C2C2E), borderRadius: BorderRadius.circular(10)),
                        child: Icon(_preview?.value.isPlaying == true ? Icons.pause_rounded : Icons.play_arrow_rounded,
                          color: Colors.white, size: 28),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _buildTimeline()),
                  ],
                ),
              ),
              ],
            ),
            if (_exporting)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: .72),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFFFD21F)),
                      SizedBox(height: 16),
                      Text('Découpage en cours…', style: TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
