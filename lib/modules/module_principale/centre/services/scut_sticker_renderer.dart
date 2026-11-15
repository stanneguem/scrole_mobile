import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_frames/video_frames.dart';

/// Position and appearance are normalized to the video frame (0..1).
class ScutSticker {
  const ScutSticker({
    required this.emoji,
    required this.x,
    required this.y,
    this.size = 0.18,
    this.rotation = 0,
  });

  final String emoji;
  final double x;
  final double y;
  final double size;
  final double rotation;

  ScutSticker copyWith({double? x, double? y, double? size, double? rotation}) =>
      ScutSticker(
        emoji: emoji,
        x: x ?? this.x,
        y: y ?? this.y,
        size: size ?? this.size,
        rotation: rotation ?? this.rotation,
      );
}

/// Bakes stickers into every frame using the device codecs (no FFmpeg).
class ScutStickerRenderer {
  static Future<File> render(File source, List<ScutSticker> stickers,
      {ValueChanged<double>? onProgress}) async {
    if (stickers.isEmpty) return source;
    final reader = await VideoReader.open(source.path, maxDimension: 1920);
    final directory = await getTemporaryDirectory();
    final output = File(
      '${directory.path}/scut_stickers_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    VideoWriter? writer;
    try {
      writer = await VideoWriter.create(
        output.path,
        width: reader.info.width,
        height: reader.info.height,
        frameRate: reader.info.frameRate,
        audioSourcePath: reader.info.hasAudio && reader.info.audioCompatible
            ? source.path
            : null,
      );
      var processed = 0;
      final total = reader.info.duration.inMilliseconds > 0
          ? reader.info.duration.inMilliseconds
          : 1;
      VideoFrame? frame;
      while ((frame = await reader.nextFrame()) != null) {
        final current = frame!;
        final image = await ui.decodeImageFromPixels(
          current.rgba,
          reader.info.width,
          reader.info.height,
          ui.PixelFormat.rgba8888,
        );
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawImage(image, Offset.zero, Paint());
        for (final sticker in stickers) {
          final fontSize = reader.info.width * sticker.size;
          final painter = TextPainter(
            text: TextSpan(
              text: sticker.emoji,
              style: TextStyle(
                fontSize: fontSize,
                height: 1,
                shadows: const [
                  Shadow(color: Colors.black54, blurRadius: 8, offset: Offset(0, 2)),
                ],
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          canvas.save();
          canvas.translate(
            reader.info.width * sticker.x,
            reader.info.height * sticker.y,
          );
          canvas.rotate(sticker.rotation);
          painter.paint(
            canvas,
            Offset(-painter.width / 2, -painter.height / 2),
          );
          canvas.restore();
        }
        final picture = recorder.endRecording();
        final composited = await picture.toImage(
          reader.info.width,
          reader.info.height,
        );
        final bytes = await composited.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (bytes == null) {
          throw StateError('Impossible de composer une image vidéo.');
        }
        await writer.addFrame(
          bytes.buffer.asUint8List(),
          current.pts,
        );
        image.dispose();
        composited.dispose();
        picture.dispose();
        processed = current.pts.inMilliseconds;
        onProgress?.call((processed / total).clamp(0.0, 1.0));
      }
      await writer.finish();
      onProgress?.call(1);
      return output;
    } catch (_) {
      if (writer != null) {
        await writer.cancel();
      }
      if (await output.exists()) await output.delete();
      rethrow;
    } finally {
      await reader.close();
    }
  }
}
