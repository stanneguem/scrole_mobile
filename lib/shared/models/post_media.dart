import 'package:flutter/material.dart';

class PostMedia {
  final String type; // 'photo'
  final String storage; // 'supabase'
  final String url;
  final Color color;

  const PostMedia({
    this.type = 'photo',
    this.storage = 'supabase',
    required this.url,
    this.color = Colors.grey,
  });

  factory PostMedia.fromJson(Map<String, dynamic> json) {
    return PostMedia(
      type: 'photo',
      storage: json['storage']?.toString() ?? 'supabase',
      url: (json['url'] ?? json['media_url'] ?? '').toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'storage': storage,
        'url': url,
      };
}
