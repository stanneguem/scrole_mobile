import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';
import 'package:scrole/modules/module_principale/centre/models/community_post.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';

class ProfilePostDetailScreen extends StatefulWidget {
  const ProfilePostDetailScreen({super.key, required this.post});
  final CommunityPost post;

  @override
  State<ProfilePostDetailScreen> createState() => _ProfilePostDetailScreenState();
}

class _ProfilePostDetailScreenState extends State<ProfilePostDetailScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final post = widget.post;
    final colors = Theme.of(context).colorScheme;
    final media = post.media;
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const Text('Publication'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Get.back()),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          if (media.isNotEmpty)
            AspectRatio(
              aspectRatio: 1,
              child: Stack(fit: StackFit.expand, children: [
                PageView.builder(
                  controller: _pageController,
                  itemCount: media.length,
                  onPageChanged: (index) => setState(() => _currentPage = index),
                  itemBuilder: (context, index) => _PostMediaPage(key: ValueKey('${post.id}:$index'), media: media[index]),
                ),
                if (media.length > 1)
                  Positioned(top: 12, right: 12, child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
                    child: Text('${_currentPage + 1}/${media.length}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                  )),
                if (media.length > 1) ...[
                  Positioned(left: 4, top: 0, bottom: 0, child: IconButton(
                    onPressed: _currentPage > 0 ? () => _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut) : null,
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 34))),
                  Positioned(right: 4, top: 0, bottom: 0, child: IconButton(
                    onPressed: _currentPage < media.length - 1 ? () => _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut) : null,
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 34))),
                ],
              ]),
            ),
          if (post.content.trim().isNotEmpty)
            Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 8), child: Text(post.content, style: Theme.of(context).textTheme.bodyLarge)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Wrap(spacing: 22, runSpacing: 12, children: [
              _Metric(icon: Icons.favorite_border_rounded, label: 'J’aime', value: post.likeCount),
              _Metric(icon: Icons.chat_bubble_outline_rounded, label: 'Commentaires', value: post.commentCount),
              _Metric(icon: Icons.visibility_outlined, label: 'Vues', value: post.viewCount),
              _Metric(icon: Icons.repeat_rounded, label: 'Partages', value: post.shareCount),
            ]),
          ),
          if (post.timeAgo.isNotEmpty)
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(post.timeAgo, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant))),
        ],
      ),
    );
  }
}

class _PostMediaPage extends StatefulWidget {
  const _PostMediaPage({super.key, required this.media});
  final dynamic media;

  @override
  State<_PostMediaPage> createState() => _PostMediaPageState();
}

class _PostMediaPageState extends State<_PostMediaPage> {
  VideoPlayerController? _videoController;
  bool _videoFailed = false;

  @override
  void initState() {
    super.initState();
    _initializeVideo();
  }

  @override
  void didUpdateWidget(covariant _PostMediaPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.media.url != widget.media.url || oldWidget.media.type != widget.media.type) {
      _disposeVideo();
      _initializeVideo();
    }
  }

  void _initializeVideo() {
    if (!widget.media.isVideo || widget.media.url.toString().trim().isEmpty) return;
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.media.url));
    _videoController = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
    }).catchError((_) {
      if (mounted) setState(() => _videoFailed = true);
    });
  }

  void _disposeVideo() {
    final controller = _videoController;
    _videoController = null;
    if (controller != null) controller.dispose();
  }

  @override
  void dispose() {
    _disposeVideo();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final url = widget.media.url.toString().trim();
    if (widget.media.isVideo) {
      final controller = _videoController;
      if (_videoFailed) {
        return Center(child: Icon(Icons.videocam_off_outlined, size: 48, color: colors.onSurfaceVariant));
      }
      if (controller == null || !controller.value.isInitialized) {
        return const Center(child: CircularProgressIndicator());
      }
      return GestureDetector(
        onTap: () {
          if (controller.value.isPlaying) {
            controller.pause();
          } else {
            controller.play();
          }
          setState(() {});
        },
        child: Stack(alignment: Alignment.center, children: [
          Center(child: AspectRatio(aspectRatio: controller.value.aspectRatio, child: VideoPlayer(controller))),
          if (!controller.value.isPlaying)
            const CircleAvatar(backgroundColor: Colors.black54, radius: 28, child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 36)),
        ]),
      );
    }
    if (url.isEmpty) return Center(child: Icon(Icons.image_not_supported_outlined, size: 48, color: colors.onSurfaceVariant));
    return InteractiveViewer(minScale: 1, maxScale: 4, child: AppCachedImage(imageUrl: url, fit: BoxFit.contain));
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 18, color: colors.primary),
      const SizedBox(width: 6),
      Text('$value $label', style: Theme.of(context).textTheme.bodyMedium),
    ]);
  }
}
