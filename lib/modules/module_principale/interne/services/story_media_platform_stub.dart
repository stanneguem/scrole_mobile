import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import '../../../../app/media/media_asset.dart';

VideoPlayerController createStoryVideoController(XFile file) =>
    VideoPlayerController.networkUrl(Uri.parse(file.path));

Future<XFile?> editStoryImage(BuildContext context, XFile file) async => file;

Future<XFile?> trimStoryVideo(
  BuildContext context,
  XFile file, {
  required Duration maxDuration,
}) async {
  final controller = createStoryVideoController(file);
  try {
    await controller.initialize().timeout(const Duration(seconds: 30));
    final duration = controller.value.duration;
    final extension = MediaAsset.fromXFile(file).extension;
    if (duration <= Duration.zero || duration > maxDuration ||
        !const {'mp4', 'mov', 'webm'}.contains(extension)) return null;
    return file;
  } finally {
    await controller.dispose();
  }
}

Future<XFile?> createStoryVideoThumbnail(XFile file) async => null;

Future<String> resolveStoryVideoPlaybackUrl(XFile file) async => file.path;

void releaseStoryVideoPlaybackUrl(String url) {}

Future<Duration> getStoryVideoDuration(XFile file) async {
  final controller = createStoryVideoController(file);
  try {
    await controller.initialize().timeout(const Duration(seconds: 30));
    final duration = controller.value.duration;
    if (duration <= Duration.zero) throw StateError('Durée vidéo introuvable.');
    return duration;
  } finally {
    await controller.dispose();
  }
}
