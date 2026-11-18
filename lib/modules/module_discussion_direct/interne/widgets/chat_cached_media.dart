import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../centre/repositories/messaging_repository.dart';
import '../../centre/persistence/pending_chat_media_store.dart';
import '../../centre/services/chat_media_cache.dart';
import 'chat_cached_media_image_stub.dart'
    if (dart.library.io) 'chat_cached_media_image_io.dart' as media_image;

class ChatCachedMedia extends StatefulWidget {
  const ChatCachedMedia({
    super.key,
    required this.remoteUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });

  final String remoteUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  State<ChatCachedMedia> createState() => _ChatCachedMediaState();
}

class _ResolvedChatImage {
  const _ResolvedChatImage({this.path, this.bytes});
  final String? path;
  final Uint8List? bytes;
}

class _ChatCachedMediaState extends State<ChatCachedMedia> {
  Future<_ResolvedChatImage>? _future;

  @override
  void initState() {
    super.initState();
    _future = _resolve(widget.remoteUrl);
  }

  @override
  void didUpdateWidget(ChatCachedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteUrl != widget.remoteUrl) {
      _future = _resolve(widget.remoteUrl);
    }
  }

  Future<_ResolvedChatImage> _resolve(String value) async {
    if (PendingChatMediaStore.isReference(value)) {
      if (!Get.isRegistered<MessagingRepository>()) {
        return const _ResolvedChatImage();
      }
      final asset = await Get.find<MessagingRepository>()
          .resolvePendingMediaAsset(value);
      if (asset == null) return const _ResolvedChatImage();
      // Read the binary image directly. Avoid the Base64/Data-URI expansion.
      return _ResolvedChatImage(bytes: await asset.readAsBytes());
    }
    if (value.startsWith('data:')) {
      return _ResolvedChatImage(path: value);
    }
    return _ResolvedChatImage(
      path: await ChatMediaCache.instance.resolveLocalPath(value),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_ResolvedChatImage>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _frame(const CircularProgressIndicator(strokeWidth: 2));
        }
        final resolved = snapshot.data;
        if (resolved == null ||
            (resolved.bytes == null &&
                (resolved.path == null || resolved.path!.isEmpty))) {
          return _unavailable();
        }
        return media_image.buildChatCachedMediaImage(
          path: resolved.path ?? '',
          bytes: resolved.bytes,
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          borderRadius: widget.borderRadius,
          unavailable: _unavailable,
        );
      },
    );
  }

  Widget _unavailable() {
    return _frame(
      const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.image_not_supported_outlined, size: 30),
          SizedBox(height: 6),
          Text(
            'Cette image n’est plus disponible',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _frame(Widget child) {
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.04),
        borderRadius: widget.borderRadius,
      ),
      child: child,
    );
  }
}
