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

/// Lit la durée d'un média Web, y compris les WebM MediaRecorder dont
/// les métadonnées indiquent parfois Infinity tant que la lecture n'est pas
/// arrivée à sa fin. L'URL Blob reste indépendante de XFile.path.
Future<Duration> getStoryVideoDuration(XFile file) async {
  final sourceUrl = await resolveStoryVideoPlaybackUrl(file);
  final ownsUrl = sourceUrl.startsWith('blob:') &&
      sourceUrl != file.path.trim();
  final video = html.VideoElement()
    ..preload = 'metadata'
    ..muted = true
    ..setAttribute('playsinline', 'true');
  try {
    // Installer les écouteurs avant src/load : certains navigateurs émettent
    // loadedmetadata immédiatement pour les petits Blob.
    final metadata = video.onLoadedMetadata.first;
    final mediaError = video.onError.first.then<void>(
      (_) => throw StateError('Le navigateur ne peut pas décoder cette vidéo.'),
    );
    video.src = sourceUrl;
    video.load();
    await Future.any<void>([metadata, mediaError])
        .timeout(const Duration(seconds: 30));

    var seconds = video.duration;
    if (!seconds.isFinite || seconds <= 0) {
      // Les WebM produits par MediaRecorder peuvent avoir une durée Infinity.
      // Une lecture muette jusqu'à ended permet de récupérer la vraie durée
      // sans bloquer la publication sur une métadonnée absente.
      final ended = video.onEnded.first;
      final playbackError = video.onError.first.then<void>(
        (_) => throw StateError('La lecture de la vidéo a échoué.'),
      );
      await video.play();
      await Future.any<void>([ended, playbackError])
          .timeout(const Duration(seconds: 75));
      seconds = video.currentTime;
      if ((!seconds.isFinite || seconds <= 0) && video.duration.isFinite) {
        seconds = video.duration;
      }
    }

    if (!seconds.isFinite || seconds <= 0) {
      debugPrint('[STORY][WEB_DURATION] unavailable name=${file.name} '
          'mime=${file.mimeType} readyState=${video.readyState} '
          'currentTime=${video.currentTime} duration=${video.duration}');
      throw StateError('Impossible de déterminer la durée de cette vidéo. '
          'Réessaie de la découper avant de publier.');
    }
    final duration = Duration(milliseconds: (seconds * 1000).round());
    debugPrint('[STORY][WEB_DURATION] resolved name=${file.name} '
        'durationMs=${duration.inMilliseconds} '
        'reportedDuration=${video.duration}');
    return duration;
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
