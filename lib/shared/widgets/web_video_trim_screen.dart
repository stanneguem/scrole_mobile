import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;
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
      <Object?>[stream, <String, Object?>{'mimeType': mime}],
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

  @override
  Widget build(BuildContext context) {
    final maxSeconds = _duration.inMilliseconds / 1000;
    return Scaffold(
      appBar: AppBar(title: const Text('Découper la vidéo')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text('Cette vidéo ne peut pas être lue dans le navigateur. $_error'),
                ))
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: AspectRatio(
                          aspectRatio: (_preview?.value.aspectRatio ?? 16 / 9).clamp(0.5, 2.4).toDouble(),
                          child: VideoPlayer(_preview!),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      child: Column(
                        children: [
                          Text('Sélection : ${_range.start.toStringAsFixed(1)} s – ${_range.end.toStringAsFixed(1)} s'),
                          RangeSlider(
                            min: 0,
                            max: maxSeconds,
                            divisions: (maxSeconds * 10).round().clamp(1, 10000).toInt(),
                            values: _range,
                            onChanged: _exporting ? null : (value) {
                              final limit = widget.maxDuration.inMilliseconds / 1000;
                              var next = value;
                              if (next.end - next.start > limit) {
                                next = RangeValues(next.start, next.start + limit);
                              }
                              setState(() => _range = next);
                              _preview?.seekTo(Duration(milliseconds: (next.start * 1000).round()));
                            },
                          ),
                          Text('Maximum autorisé : ${widget.maxDuration.inSeconds} secondes'),
                        ],
                      ),
                    ),
                    SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _exporting ? null : _confirm,
                            child: _exporting
                                ? const CircularProgressIndicator()
                                : const Text('Utiliser cette vidéo'),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }
}
