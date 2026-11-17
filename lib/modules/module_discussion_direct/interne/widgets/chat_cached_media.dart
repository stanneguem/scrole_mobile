import 'package:flutter/material.dart';
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

class _ChatCachedMediaState extends State<ChatCachedMedia> {
  Future<String?>? _future;

  @override
  void initState() {
    super.initState();
    _future = ChatMediaCache.instance.resolveLocalPath(widget.remoteUrl);
  }

  @override
  void didUpdateWidget(ChatCachedMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.remoteUrl != widget.remoteUrl) {
      _future = ChatMediaCache.instance.resolveLocalPath(widget.remoteUrl);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _frame(const CircularProgressIndicator(strokeWidth: 2));
        }
        final path = snapshot.data;
        if (path == null || path.isEmpty) return _unavailable();

        return media_image.buildChatCachedMediaImage(
          path: path,
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
