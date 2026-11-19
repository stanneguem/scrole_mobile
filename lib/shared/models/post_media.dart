import 'package:flutter/material.dart';

class PostMedia {
  final String type;
  final String storage;
  final String url;
  final String? thumbnailUrl;
  final Color color;

  const PostMedia({
    this.type = 'photo',
    this.storage = 'supabase',
    required this.url,
    this.thumbnailUrl,
    this.color = Colors.grey,
  });

  bool get isVideo => type.toLowerCase().contains('video');

  /// A video URL must never be handed to Flutter's image decoder as a poster.
  /// Some legacy/API payloads accidentally duplicate the video URL into
  /// thumbnail_url; signed URLs can also differ only by their query string.
  String? get safeThumbnailUrl {
    final candidate = thumbnailUrl?.trim();
    if (candidate == null || candidate.isEmpty) return null;
    if (candidate == url.trim()) return null;

    final candidateUri = Uri.tryParse(candidate);
    final mediaUri = Uri.tryParse(url.trim());
    if (candidateUri != null) {
      if (candidateUri.scheme.toLowerCase() == 'data' &&
          candidateUri.data?.mimeType.toLowerCase().startsWith('video/') == true) {
        return null;
      }
      const videoExtensions = {
        '.mp4', '.m4v', '.mov', '.webm', '.mkv', '.3gp', '.avi', '.m3u8', '.mpd',
      };
      final path = candidateUri.path.toLowerCase();
      if (videoExtensions.any(path.endsWith)) return null;

      // Ignore query parameters (tokens/signatures) when comparing media URLs.
      if (mediaUri != null &&
          candidateUri.host.isNotEmpty &&
          candidateUri.host == mediaUri.host &&
          candidateUri.path == mediaUri.path) {
        return null;
      }
    }
    return candidate;
  }

  factory PostMedia.fromJson(Map<String, dynamic> json) {
    final rawType = (json['type'] ?? json['media_type'] ?? json['mime_type'] ?? 'photo').toString().toLowerCase();
    final type = (rawType.contains('video') || rawType == 'reel')
        ? 'video'
        : (rawType.contains('gif') ? 'gif' : 'photo');
    return PostMedia(
      type: type,
      storage: json['storage']?.toString() ?? 'supabase',
      url: (json['url'] ?? json['media_url'] ?? json['original_url'] ?? json['video_url'] ?? '').toString(),
      thumbnailUrl: (json['thumbnail_url'] ?? json['thumbnail'] ?? json['video_thumbnail_url'])?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'storage': storage,
        'url': url,
        if (thumbnailUrl != null) 'thumbnail_url': thumbnailUrl,
      };
}
