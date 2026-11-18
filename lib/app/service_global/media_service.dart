import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:get/get.dart';

import '../../shared/widgets/media_gallery_sheet.dart';

/// Sélection et préparation de médias sans exposer dart:io aux contrôleurs.
/// Sur le Web, l'image originale est conservée lorsque les traitements natifs
/// (cropper/compression fichier) ne sont pas disponibles.
class MediaService extends GetxService {
  final ImagePicker _picker = ImagePicker();

  Future<XFile?> _pickGalleryImage() async {
    final context = Get.context;
    if (context == null) return _picker.pickImage(source: ImageSource.gallery);
    return ScroleBottomSheetGallery.pick(context);
  }

  Future<XFile?> pickImage({ImageSource source = ImageSource.gallery}) async {
    return source == ImageSource.gallery
        ? _pickGalleryImage()
        : _picker.pickImage(source: source);
  }

  Future<XFile?> cropImage(XFile imageFile, {bool circle = false}) async {
    // Le plugin cropper Web nécessite une UI dédiée. On préserve le média
    // plutôt que de convertir une URL Blob en chemin de fichier local.
    if (kIsWeb) return imageFile;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: imageFile.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Redimensionner',
          toolbarColor: const Color(0xFFEB5E28),
          statusBarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          activeControlsWidgetColor: const Color(0xFFEB5E28),
          initAspectRatio: circle ? CropAspectRatioPreset.square : CropAspectRatioPreset.original,
          lockAspectRatio: circle,
        ),
        IOSUiSettings(
          title: 'Redimensionner',
          doneButtonTitle: 'Terminer',
          cancelButtonTitle: 'Annuler',
        ),
      ],
    );
    return croppedFile == null ? null : XFile(croppedFile.path);
  }

  Future<XFile?> compressImage(XFile file, {int quality = 80}) async {
    if (kIsWeb) return file;
    final tempDir = await getTemporaryDirectory();
    final targetPath = p.join(
      tempDir.path,
      "${DateTime.now().millisecondsSinceEpoch}.jpg",
    );
    final result = await FlutterImageCompress.compressAndGetFile(
      file.path,
      targetPath,
      quality: quality,
    );
    return result == null ? null : XFile(result.path);
  }

  Future<XFile?> pickProfileImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await pickImage(source: source);
    if (picked == null) return null;
    final cropped = await cropImage(picked, circle: true);
    if (cropped == null) return null;
    return compressImage(cropped);
  }

  Future<XFile?> pickCoverImage({ImageSource source = ImageSource.gallery}) async {
    final picked = await pickImage(source: source);
    if (picked == null) return null;
    if (kIsWeb) return picked;

    final cropped = await ImageCropper().cropImage(
      sourcePath: picked.path,
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Recadrer la couverture',
          toolbarColor: const Color(0xFFEB5E28),
          statusBarColor: Colors.black,
          toolbarWidgetColor: Colors.white,
          initAspectRatio: CropAspectRatioPreset.ratio16x9,
          lockAspectRatio: true,
        ),
        IOSUiSettings(title: 'Recadrer', aspectRatioLockEnabled: true),
      ],
    );
    if (cropped == null) return null;
    return compressImage(XFile(cropped.path));
  }
}

/// Adaptateur de la galerie interne.
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
