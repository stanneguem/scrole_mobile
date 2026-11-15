import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_full/ffmpeg_kit.dart';
import 'package:path_provider/path_provider.dart';

/// Applies the exact same 4x5 color matrix used by Flutter's camera preview
/// to every decoded video frame. The original recording is never overwritten.
class ScutVideoFilterService {
  ScutVideoFilterService._();

  static Future<File> applyFilter({
    required File input,
    required List<double> matrix,
  }) async {
    if (!input.existsSync() || input.lengthSync() == 0) {
      throw const FileSystemException('La vidéo source est introuvable.');
    }
    if (matrix.length != 20) {
      throw ArgumentError.value(matrix.length, 'matrix', 'Une matrice 4x5 est requise.');
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
    final videoFilter = _toFfmpegColorMatrix(matrix);

    final command = [
      '-y',
      '-i $inputPath',
      '-map 0:v:0',
      '-map 0:a?',
      '-vf "$videoFilter"',
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

  /// Flutter matrices use 0..255 channel values and offsets. FFmpeg's
  /// colorchannelmixer works with normalized 0..1 values, so offsets are
  /// normalized by 255 while the 16 channel coefficients stay unchanged.
  static String _toFfmpegColorMatrix(List<double> matrix) {
    const channelNames = [
      'rr', 'rg', 'rb', 'ra', 'ro',
      'gr', 'gg', 'gb', 'ga', 'go',
      'br', 'bg', 'bb', 'ba', 'bo',
      'ar', 'ag', 'ab', 'aa', 'ao',
    ];
    final values = <String>[];
    for (var index = 0; index < matrix.length; index++) {
      final value = index % 5 == 4 ? matrix[index] / 255 : matrix[index];
      values.add('${channelNames[index]}=${value.toStringAsFixed(6)}');
    }
    return 'colorchannelmixer=${values.join(':')}';
  }

  static String _quote(String value) =>
      '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';
}
