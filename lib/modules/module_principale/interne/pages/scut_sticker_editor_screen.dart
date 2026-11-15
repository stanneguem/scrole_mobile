import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:video_player/video_player.dart';

import '../centre/services/scut_sticker_renderer.dart';

class ScutStickerEditorScreen extends StatefulWidget {
  const ScutStickerEditorScreen({
    super.key,
    required this.videoFile,
    this.initialStickers = const [],
  });

  final File videoFile;
  final List<ScutSticker> initialStickers;

  @override
  State<ScutStickerEditorScreen> createState() => _ScutStickerEditorScreenState();
}

class _ScutStickerEditorScreenState extends State<ScutStickerEditorScreen> {
  static const _stickers = [
    '😂','❤️','🔥','😍','🥰','😎','😭','✨','⭐','💯','🎉','👏',
    '🤣','🤩','🥳','💖','💕','🌸','🦋','🌈','☀️','👑','💫','🤍',
    '😜','😱','🥹','🙌','💥','🍀','🎵','🚀','💎','🌍','🐼','🐱',
  ];

  late final VideoPlayerController _player;
  late List<ScutSticker> _items;
  bool _ready = false;
  bool _exporting = false;
  double _progress = 0;
  int _activeIndex = -1;
  double _gestureStartSize = .18;
  double _gestureStartRotation = 0;

  @override
  void initState() {
    super.initState();
    _items = List<ScutSticker>.from(widget.initialStickers);
    _player = VideoPlayerController.file(widget.videoFile)
      ..initialize().then((_) {
        if (!mounted) return;
        _player.setLooping(true);
        _player.play();
        setState(() => _ready = true);
      });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _chooseSticker() async {
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 38, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4))),
              const SizedBox(height: 18),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text('Stickers et emojis',
                  style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 16),
              GridView.builder(
                shrinkWrap: true,
                itemCount: _stickers.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6, mainAxisSpacing: 8, crossAxisSpacing: 8,
                ),
                itemBuilder: (_, index) => InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () => Navigator.pop(context, _stickers[index]),
                  child: Center(child: Text(_stickers[index], style: const TextStyle(fontSize: 30))),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _items.add(ScutSticker(emoji: selected, x: .5, y: .5));
      _activeIndex = _items.length - 1;
    });
  }

  void _updateSticker(int index, Offset delta, Size area, double scale, double rotation) {
    if (area.isEmpty || index < 0 || index >= _items.length) return;
    final old = _items[index];
    setState(() {
      _items[index] = old.copyWith(
        x: (old.x + delta.dx / area.width).clamp(0.02, 0.98),
        y: (old.y + delta.dy / area.height).clamp(0.02, 0.98),
        size: (_gestureStartSize * scale).clamp(.06, .65),
        rotation: _gestureStartRotation + rotation,
      );
      _activeIndex = index;
    });
  }

  Future<void> _finish() async {
    if (_exporting) return;
    if (_items.isEmpty) {
      Get.back<File>(result: widget.videoFile);
      return;
    }
    setState(() {
      _exporting = true;
      _progress = 0;
    });
    try {
      final rendered = await ScutStickerRenderer.render(
        widget.videoFile,
        _items,
        duration: _player.value.duration,
        onProgress: (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (mounted) Get.back<File>(result: rendered);
    } catch (error) {
      if (!mounted) return;
      setState(() => _exporting = false);
      Get.snackbar(
        'Export des stickers impossible',
        'La vidéo originale est conservée. Réessaie ou retire les stickers. $error',
        snackPosition: SnackPosition.BOTTOM,
        duration: const Duration(seconds: 5),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _exporting ? null : () => Get.back<File>(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  const Spacer(),
                  const Text('Modifier ton Scut',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton(
                    onPressed: _exporting ? null : _finish,
                    child: const Text('Terminer',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: _ready
                    ? AspectRatio(
                        aspectRatio: _player.value.aspectRatio,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final area = Size(constraints.maxWidth, constraints.maxHeight);
                            return Stack(
                              fit: StackFit.expand,
                              children: [
                                VideoPlayer(_player),
                                for (var i = 0; i < _items.length; i++)
                                  Positioned(
                                    left: _items[i].x * area.width - 34,
                                    top: _items[i].y * area.height - 34,
                                    child: GestureDetector(
                                      onTap: () => setState(() => _activeIndex = i),
                                      onScaleStart: (_) {
                                        _gestureStartSize = _items[i].size;
                                        _gestureStartRotation = _items[i].rotation;
                                      },
                                      onScaleUpdate: (details) => _updateSticker(
                                        i,
                                        details.focalPointDelta,
                                        area,
                                        details.scale,
                                        details.rotation,
                                      ),
                                      child: Container(
                                        padding: const EdgeInsets.all(4),
                                        decoration: BoxDecoration(
                                          border: _activeIndex == i
                                              ? Border.all(color: Colors.white70, width: 1, strokeAlign: BorderSide.strokeAlignOutside)
                                              : null,
                                        ),
                                        child: Transform.rotate(
                                          angle: _items[i].rotation,
                                          child: Text(
                                            _items[i].emoji,
                                            style: TextStyle(fontSize: area.width * _items[i].size),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),
                      )
                    : const CircularProgressIndicator(color: Colors.white),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
              child: Column(
                children: [
                  if (_exporting) ...[
                    LinearProgressIndicator(value: _progress, color: Colors.white),
                    const SizedBox(height: 8),
                    Text('Incrustation des stickers… ${(_progress * 100).round()}%',
                      style: const TextStyle(color: Colors.white70, fontSize: 12)),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _chooseSticker,
                            icon: const Icon(Icons.emoji_emotions_outlined),
                            label: const Text('Ajouter un sticker'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.white,
                              side: const BorderSide(color: Colors.white38),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        if (_activeIndex >= 0 && _activeIndex < _items.length) ...[
                          const SizedBox(width: 10),
                          IconButton(
                            tooltip: 'Supprimer le sticker',
                            onPressed: () => setState(() {
                              _items.removeAt(_activeIndex);
                              _activeIndex = -1;
                            }),
                            icon: const Icon(Icons.delete_outline, color: Colors.white),
                          ),
                        ],
                      ],
                    ),
                  const SizedBox(height: 4),
                  const Text('Déplace, agrandis ou fais pivoter tes stickers avec les doigts.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white60, fontSize: 11)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
