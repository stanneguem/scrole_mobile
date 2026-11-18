import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart';

class StoryMediaPicker {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> pick(BuildContext context) => _picker.pickMedia();
}
