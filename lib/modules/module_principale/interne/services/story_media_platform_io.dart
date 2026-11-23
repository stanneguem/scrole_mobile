import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';

import '../pages/story_image_editor_screen.dart';
import '../../../../shared/widgets/video_trim_screen.dart';

VideoPlayerController createStoryVideoController(XFile file) =>
    VideoPlayerController.file(File(file.path));

Future<XFile?> editStoryImage(BuildContext context, XFile file) async {
  final edited = await Get.to<File>(
    () => StoryImageEditorScreen(imageFile: File(file.path)),
    fullscreenDialog: true,
  );
  return edited == null ? null : XFile(edited.path);
}

Future<XFile?> trimStoryVideo(
  BuildContext context,
  XFile file, {
  required Duration maxDuration,
}) async {
  final trimmed = await Get.to<File>(
    () => VideoTrimScreen(
      videoFile: File(file.path),
      maxDuration: maxDuration,
    ),
  );
  return trimmed == null ? null : XFile(trimmed.path);
}

Future<XFile?> createStoryVideoThumbnail(XFile file) async {
  final thumbnail = await VideoCompress.getFileThumbnail(
    file.path,
    quality: 82,
    position: 1000,
  );
  return await thumbnail.exists() ? XFile(thumbnail.path) : null;
}

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
