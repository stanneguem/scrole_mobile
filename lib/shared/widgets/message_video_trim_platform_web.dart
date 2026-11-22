import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

import 'video_trim_platform_web.dart';

Future<XFile?> trimMessageVideo(
  BuildContext context,
  XFile file, {
  required Duration maxDuration,
}) => trimVideoForWeb(context, file, maxDuration: maxDuration);
