import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:video_frames/video_frames.dart';

/// Sticker placé sur la vidéo. x/y sont normalisés entre 0 et 1.
@immutable
class ScutSticker {
  const ScutSticker({
    required this.emoji,
    this.x = .5,
    this.y = .5,
    this.size = .18,
    this.rotation = 0,
    this.startMs = 0,
  });

  final String emoji;
  final double x;
  final double y;
  final double size;
  final double rotation;
  final int startMs;

  ScutSticker copyWith({
    String? emoji,
    double? x,
    double? y,
    double? size,
    double? rotation,
    int? startMs,
  }) {
    return ScutSticker(
      emoji: emoji ?? this.emoji,
      x: x ?? this.x,
      y: y ?? this.y,
      size: size ?? this.size,
      rotation: rotation ?? this.rotation,
      startMs: startMs ?? this.startMs,
    );
  }
}

class _RasterSticker {
  const _RasterSticker(this.sticker, this.image);

  final ScutSticker sticker;
  final ui.Image image;

  void dispose() => image.dispose();
}

/// Incruste les stickers sur chaque frame et conserve la piste audio compatible.
class ScutStickerRenderer {
  static Future<File> render(
    File source,
    List<ScutSticker> stickers, {
    Duration? duration,
    void Function(double progress)? onProgress,
  }) async {
    if (!await source.exists() || await source.length() == 0) {
      throw const FormatException('Le fichier vidéo source est introuvable ou vide.');
    }
    if (stickers.isEmpty) return source;

    final reader = await VideoReader.open(source.path, maxDimension: 1920);
    VideoWriter? writer;
    var writerFinished = false;
    final rasterStickers = <_RasterSticker>[];
    try {
      final info = reader.info;
      final maxDuration = duration == null || duration > info.duration
          ? info.duration
          : duration;

      // Les textes, ombres et glyphes sont dessinés une seule fois, pas 28 à 30
      // fois par seconde. La boucle vidéo ne fait ensuite que composer des images.
      for (final sticker in stickers) {
        rasterStickers.add(
          await _rasterizeSticker(sticker, info.width),
        );
      }

      final temp = await getTemporaryDirectory();
      final outputPath = p.join(
        temp.path,
        'scut_stickers_${DateTime.now().microsecondsSinceEpoch}.mp4',
      );

      writer = await VideoWriter.create(
        outputPath,
        width: info.width,
        height: info.height,
        frameRate: info.frameRate > 0 ? info.frameRate : 30,
        audioSourcePath: info.hasAudio && info.audioCompatible ? source.path : null,
      );

      final totalFrames = info.estimatedFrameCount;
      var writtenFrames = 0;
      while (true) {
        final frame = await reader.nextFrame();
        if (frame == null || frame.pts > maxDuration) break;

        final renderedRgba = await _drawStickers(frame, rasterStickers);
        await writer.addFrame(renderedRgba, frame.pts);
        writtenFrames++;
        if (totalFrames > 0) {
          onProgress?.call((writtenFrames / totalFrames).clamp(0.0, 1.0));
        }
      }

      if (writtenFrames == 0) {
        throw const FormatException('Aucune image vidéo n’a pu être lue.');
      }

      await writer.finish();
      writerFinished = true;
      onProgress?.call(1);
      final output = File(outputPath);
      if (!await output.exists() || await output.length() == 0) {
        throw const FormatException('Le fichier vidéo exporté est vide.');
      }
      return output;
    } catch (_) {
      if (writer != null && !writerFinished) {
        try {
          await writer.cancel();
        } catch (_) {}
      }
      rethrow;
    } finally {
      for (final sticker in rasterStickers) {
        sticker.dispose();
      }
      await reader.close();
    }
  }

  static Future<_RasterSticker> _rasterizeSticker(
    ScutSticker sticker,
    int videoWidth,
  ) async {
    final fontSize = videoWidth * sticker.size *
        (sticker.emoji.length > 3 ? .22 : 1);
    final painter = TextPainter(
      text: TextSpan(
        text: sticker.emoji,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          height: 1,
          shadows: const [
            Shadow(color: Colors.black87, blurRadius: 7, offset: Offset(0, 2)),
            Shadow(color: Colors.black54, blurRadius: 2),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: videoWidth.toDouble());

    final width = painter.width.ceil().clamp(1, videoWidth).toInt();
    final height = painter.height.ceil().clamp(1, videoWidth).toInt();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, Offset.zero);
    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(width, height);
      return _RasterSticker(sticker, image);
    } finally {
      painter.dispose();
      picture.dispose();
    }
  }

  static Future<Uint8List> _drawStickers(
    VideoFrame frame,
    List<_RasterSticker> stickers,
  ) async {
    final sourceImage = await _imageFromRgba(
      frame.rgba,
      frame.width,
      frame.height,
    );
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawImage(sourceImage, Offset.zero, Paint());

    for (final raster in stickers) {
      final sticker = raster.sticker;
      if (frame.pts.inMilliseconds < sticker.startMs) continue;

      final center = Offset(
        sticker.x.clamp(0.0, 1.0).toDouble() * frame.width,
        sticker.y.clamp(0.0, 1.0).toDouble() * frame.height,
      );
      final image = raster.image;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(sticker.rotation);
      canvas.drawImage(
        image,
        Offset(-image.width / 2, -image.height / 2),
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
    }

    final picture = recorder.endRecording();
    try {
      final outputImage = await picture.toImage(frame.width, frame.height);
      try {
        final data = await outputImage.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (data == null) {
          throw const FormatException(
            'Impossible de convertir une image avec ses stickers.',
          );
        }
        return data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      } finally {
        outputImage.dispose();
      }
    } finally {
      sourceImage.dispose();
      picture.dispose();
    }
  }

  static Future<ui.Image> _imageFromRgba(
    Uint8List rgba,
    int width,
    int height,
  ) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      rgba,
      width,
      height,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}
