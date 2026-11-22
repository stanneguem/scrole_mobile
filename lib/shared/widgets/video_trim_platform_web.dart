import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'web_video_trim_screen.dart';

Future<XFile?> trimVideoForWeb(
  BuildContext context,
  XFile file, {
  required Duration maxDuration,
}) async {
  return await Get.to<XFile>(() => WebVideoTrimScreen(
        videoFile: file,
        maxDuration: maxDuration,
      ));
}
