import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'video_trim_screen.dart';

Future<XFile?> trimMessageVideo(
  BuildContext context,
  XFile file, {
  required Duration maxDuration,
}) async {
  final trimmed = await Get.to<File>(() => VideoTrimScreen(
        videoFile: File(file.path),
        maxDuration: maxDuration,
      ));
  if (trimmed == null || !await trimmed.exists()) return null;
  return XFile(trimmed.path, mimeType: file.mimeType);
}
