import 'package:image_picker/image_picker.dart';

class StoryMediaPicker {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> pick() => _picker.pickMedia();
}
