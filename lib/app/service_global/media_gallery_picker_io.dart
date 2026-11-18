import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../shared/widgets/media_gallery_sheet.dart';

class ScroleBottomSheetGallery {
  static Future<XFile?> pick(BuildContext context) async {
    final result = await showModalBottomSheet<List<XFile>>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MediaGallerySheet(
        maxSelection: 1,
        onSelected: (_) {},
      ),
    );
    return result != null && result.isNotEmpty ? result.first : null;
  }
}
