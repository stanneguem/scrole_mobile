import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../../../shared/widgets/web_video_trim_screen.dart';

VideoPlayerController createStoryVideoController(XFile file) =>
    VideoPlayerController.networkUrl(Uri.parse(file.path));

Future<XFile?> editStoryImage(BuildContext context, XFile file) async => file;

Future<XFile?> trimStoryVideo(
  BuildContext context,
  XFile file, {
  required Duration maxDuration,
}) {
  return Get.to<XFile>(() => WebVideoTrimScreen(
        videoFile: file,
        maxDuration: maxDuration,
      ));
}

Future<XFile?> createStoryVideoThumbnail(XFile file) async => null;
