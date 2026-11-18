import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<VideoPlayerController> createStoryPlaybackController({
  required String objectKey,
  required String storyId,
  required DateTime expiresAt,
}) async {
  if (!expiresAt.isAfter(DateTime.now())) {
    throw StateError('Cette story a expiré.');
  }
  var url = objectKey;
  if (!url.startsWith('http://') && !url.startsWith('https://')) {
    final response = await Supabase.instance.client.functions.invoke(
      'r2-media-upload',
      body: {'action': 'create-download-url', 'object_key': objectKey},
    );
    if (response.status < 200 || response.status >= 300 || response.data is! Map) {
      throw StateError('Impossible de résoudre la vidéo privée de la story.');
    }
    url = (response.data as Map)['url']?.toString() ?? '';
    if (url.isEmpty) throw StateError('URL de lecture de la vidéo absente.');
  }
  return VideoPlayerController.networkUrl(Uri.parse(url));
}

Future<void> deleteCachedStoryVideo({
  required String storyId,
  required String objectKey,
}) async {}
