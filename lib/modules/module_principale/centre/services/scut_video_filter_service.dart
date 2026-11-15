import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_full/return_code.dart';
import 'package:path_provider/path_provider.dart';

/// Bake Scut's live-preview color presets into the exported video pixels.
///
/// Processing is local on the device. The original recording is never
/// overwritten, and the audio stream is copied without re-encoding.
class ScutVideoFilterService {
  ScutVideoFilterService._();

  static const Map<String, String> _videoFilters = {
    'Naturel': 'eq=contrast=1.04:saturation=1.04:brightness=0.008',
    'Doux': 'eq=contrast=1.02:saturation=0.92:brightness=0.025',
    'Éclat': 'eq=contrast=1.08:saturation=1.15:brightness=0.025',
    'Chaud': 'colorbalance=rs=0.08:gs=0.02:bs=-0.06,eq=saturation=1.06:brightness=0.012',
    'Golden Hour': 'colorbalance=rs=0.12:gs=0.04:bs=-0.12,eq=contrast=1.06:saturation=1.18:brightness=0.035',
    'Cinéma froid': 'colorbalance=rs=-0.06:gs=0.01:bs=0.12,eq=contrast=1.08:saturation=0.92',
    'Vintage': 'colorbalance=rs=0.06:gs=0.015:bs=-0.04,eq=contrast=0.90:saturation=0.78:brightness=0.025',
    'N&B': 'hue=s=0,eq=contrast=1.12:brightness=0.005',
    'Pastel': 'eq=contrast=0.92:saturation=0.78:brightness=0.055',
    'Moody': 'eq=contrast=1.16:saturation=0.82:brightness=-0.025',
    'Rétro 90s': 'colorbalance=rs=0.05:gs=0.015:bs=-0.06,eq=contrast=0.92:saturation=0.88:brightness=0.025',
    'Dreamy': 'eq=contrast=0.92:saturation=0.92:brightness=0.05',
    'Matte': 'eq=contrast=0.84:saturation=0.94:brightness=0.055',
    'Teal & Orange': 'colorbalance=rs=0.10:gs=-0.015:bs=0.08:rh=0.12:gh=0.025:bh=-0.10,eq=contrast=1.08:saturation=1.08',
  };

  static Future<File> applyFilter({
    required File input,
    required String filterName,
  }) async {
    if (!input.existsSync() || input.lengthSync() == 0) {
      throw const FileSystemException('La vidéo source est introuvable.');
    }

    final filter = _videoFilters[filterName];
    if (filter == null) {
      if (filterName == 'Original') return input;
      throw ArgumentError.value(filterName, 'filterName', 'Filtre Scut inconnu');
    }

    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError('Le traitement vidéo Scut est disponible sur Android et iOS.');
    }

    final tempDirectory = await getTemporaryDirectory();
    final output = File(
      '${tempDirectory.path}/scut_${DateTime.now().microsecondsSinceEpoch}.mp4',
    );
    final inputPath = _quote(input.absolute.path);
    final outputPath = _quote(output.absolute.path);
    final encoder = Platform.isAndroid ? 'h264_mediacodec' : 'h264_videotoolbox';

    final command = [
      '-y',
      '-i $inputPath',
      '-map 0:v:0',
      '-map 0:a?',
      '-vf "$filter"',
      '-c:v $encoder',
      '-b:v 6M',
      '-pix_fmt yuv420p',
      '-c:a copy',
      '-movflags +faststart',
      outputPath,
    ].join(' ');

    try {
      final session = await FFmpegKit.execute(command);
      final returnCode = await session.getReturnCode();
      if (ReturnCode.isSuccess(returnCode) &&
          output.existsSync() &&
          output.lengthSync() > 0) {
        return output;
      }

      final logs = await session.getLogs();
      final diagnostic = logs
          .map((log) => log.getMessage())
          .where((line) => line.trim().isNotEmpty)
          .toList()
          .reversed
          .take(8)
          .toList()
          .reversed
          .join('\n');
      throw FileSystemException(
        'Impossible d’appliquer le filtre à la vidéo.'
        '${diagnostic.isEmpty ? '' : '\n$diagnostic'}',
      );
    } catch (_) {
      if (output.existsSync()) {
        try {
          await output.delete();
        } catch (_) {}
      }
      rethrow;
    }
  }

  static String _quote(String value) =>
      '"${value.replaceAll(r'\\', r'\\\\').replaceAll('"', r'\\"')}"';
}
