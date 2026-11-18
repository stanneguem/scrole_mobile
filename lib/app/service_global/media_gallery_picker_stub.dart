import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

class ScroleBottomSheetGallery {
  static final ImagePicker _picker = ImagePicker();

  static Future<XFile?> pick(BuildContext context) =>
      _picker.pickImage(source: ImageSource.gallery);
}
