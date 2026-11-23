import 'dart:async';
import 'dart:html' as html;
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:scrole/app/media/media_asset.dart';

import '../../../../shared/widgets/web_video_trim_screen.dart';

VideoPlayerController createStoryVideoController(XFile file) =>
    VideoPlayerController.networkUrl(Uri.parse(file.path));

/// XFile.fromData (résultat du trim Web) n'a pas nécessairement de chemin
/// blob exploitable. Créer une URL objet à partir des octets pour le lecteur.
Future<String> resolveStoryVideoPlaybackUrl(XFile file) async {
  final path = file.path.trim();
  if (path.startsWith('blob:') || path.startsWith('http://') || path.startsWith('https://')) {
    return path;
  }
  final bytes = await file.readAsBytes();
  if (bytes.isEmpty) throw StateError('Le segment vidéo Web est vide.');
  final extension = MediaAsset.fromXFile(file).extension;
  final mime = file.mimeType ??
      (extension == 'mp4' ? 'video/mp4' : extension == 'mov' ? 'video/quicktime' : 'video/webm');
  final blob = html.Blob(<Object>[bytes], mime);
  return html.Url.createObjectUrlFromBlob(blob);
}

void releaseStoryVideoPlaybackUrl(String url) {
  if (url.startsWith('blob:')) html.Url.revokeObjectUrl(url);
}

/// Lit les métadonnées depuis une vraie URL Blob, pas depuis XFile.path.
Future<Duration> getStoryVideoDuration(XFile file) async {
  final sourceUrl = await resolveStoryVideoPlaybackUrl(file);
  final ownsUrl = sourceUrl.startsWith('blob:') &&
      sourceUrl != file.path.trim();
  final video = html.VideoElement()
    ..preload = 'metadata'
    ..src = sourceUrl;
  try {
    final metadata = Completer<void>();
    final loaded = video.onLoadedMetadata.first.then((_) {
      if (!metadata.isCompleted) metadata.complete();
    });
    final failed = video.onError.first.then((_) {
      if (!metadata.isCompleted) {
        metadata.completeError(StateError('Impossible de lire les métadonnées de la vidéo Web.'));
      }
    });
    video.load();
    await metadata.future.timeout(const Duration(seconds: 30));
    await Future.wait<void>([loaded, failed].where((_) => false));
    final seconds = video.duration;
    if (!seconds.isFinite || seconds <= 0) {
      throw StateError('Durée vidéo Web introuvable.');
    }
    return Duration(milliseconds: (seconds * 1000).round());
  } finally {
    video.pause();
    video.removeAttribute('src');
    video.load();
    if (ownsUrl) releaseStoryVideoPlaybackUrl(sourceUrl);
  }
}

Future<XFile?> editStoryImage(BuildContext context, XFile file) async => file;

Future<XFile?> trimStoryVideo(
  BuildContext context,
  XFile file, {
  required Duration maxDuration,
}) async {
  return await Get.to<XFile>(() => WebVideoTrimScreen(
        videoFile: file,
        maxDuration: maxDuration,
      ));
}

Future<XFile?> createStoryVideoThumbnail(XFile file) async => null;
