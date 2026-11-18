import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

Future<XFile> compressSelectedImage(XFile file, {int quality = 80}) async {
  final tempDir = await getTemporaryDirectory();
  final targetPath = p.join(tempDir.path, "${DateTime.now().millisecondsSinceEpoch}.jpg");
  final result = await FlutterImageCompress.compressAndGetFile(
    file.path,
    targetPath,
    quality: quality,
  );
  return result == null ? file : XFile(result.path);
}
