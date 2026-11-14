import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:get/get.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

/// Full-screen story image editor. The exported file contains the image and
/// all text overlays, so the existing story upload pipeline can stay unchanged.
class StoryImageEditorScreen extends StatefulWidget {
  final File imageFile;

  const StoryImageEditorScreen({super.key, required this.imageFile});

  @override
  State<StoryImageEditorScreen> createState() => _StoryImageEditorScreenState();
}

class _StoryImageEditorScreenState extends State<StoryImageEditorScreen> {
  final GlobalKey _canvasKey = GlobalKey();
  final List<_StoryTextOverlay> _overlays = [];
  int? _selectedOverlay;
  bool _isSaving = false;
  bool _imageReady = false;
  bool _imageLoadFailed = false;
  Size _canvasSize = Size.zero;

  static const List<Color> _colors = [
    Colors.white,
    Color(0xFFFFD54F),
    Color(0xFFFF6B81),
    Color(0xFF64D8CB),
    Color(0xFF8AB4FF),
    Color(0xFFCE93D8),
  ];

  Future<void> _addText() => _editText(null);

  Future<void> _editText(int? overlayIndex) async {
    // The dialog owns its controller and focus node. They are disposed only
    // when the dialog subtree itself is removed, not when its pop animation
    // merely starts.
    final result = await Get.dialog<String>(
      _StoryTextDialog(
        initialText: overlayIndex == null ? '' : _overlays[overlayIndex].text,
      ),
      barrierDismissible: false,
    );

    if (result == null || result.isEmpty || !mounted) return;
    setState(() {
      if (overlayIndex != null && overlayIndex < _overlays.length) {
        _overlays[overlayIndex].text = result;
        _selectedOverlay = overlayIndex;
      } else if (overlayIndex == null) {
        _overlays.add(_StoryTextOverlay(text: result));
        _selectedOverlay = _overlays.length - 1;
      }
    });
  }

  void _moveOverlay(int index, DragUpdateDetails details) {
    if (_canvasSize.isEmpty) return;
    final overlay = _overlays[index];
    setState(() {
      overlay.x = (overlay.x + details.delta.dx / _canvasSize.width)
          .clamp(0.08, 0.92);
      overlay.y = (overlay.y + details.delta.dy / _canvasSize.height)
          .clamp(0.08, 0.92);
      _selectedOverlay = index;
    });
  }

  void _changeSelectedColor(Color color) {
    final index = _selectedOverlay;
    if (index == null) return;
    setState(() => _overlays[index].color = color);
  }

  Future<void> _save() async {
    if (_isSaving || !_imageReady || _imageLoadFailed) return;
    setState(() {
      _isSaving = true;
      // Selection handles are editor-only and must not be baked into the image.
      _selectedOverlay = null;
    });
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundary = _canvasKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Story canvas is unavailable');

      final image = await boundary.toImage(pixelRatio: 3);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (byteData == null) throw StateError('Unable to encode story image');

      final directory = await getTemporaryDirectory();
      final output = File(
        '${directory.path}/story_edit_${const Uuid().v4()}.png',
      );
      await output.writeAsBytes(
        byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        ),
        flush: true,
      );
      if (!await output.exists() || await output.length() == 0) {
        throw StateError('Edited story image is empty');
      }
      if (mounted) Get.back<File>(result: output);
    } catch (error, stack) {
      debugPrint('[STORY_IMAGE_EDITOR] export failed: $error\n$stack');
      if (mounted) {
        Get.snackbar(
          'story_error_title'.tr,
          'story_editor_export_error'.tr,
          snackPosition: SnackPosition.BOTTOM,
          backgroundColor: Colors.black87,
          colorText: Colors.white,
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 56,
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isSaving ? null : () => Get.back<File?>(),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                  Expanded(
                    child: Text(
                      'story_editor_title'.tr,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: (_isSaving || !_imageReady || _imageLoadFailed) ? null : _save,
                    child: _isSaving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            'story_editor_done'.tr,
                            style: const TextStyle(
                              color: Color(0xFFFFD21F),
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AspectRatio(
                    aspectRatio: 9 / 16,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _canvasSize = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
                        return RepaintBoundary(
                          key: _canvasKey,
                          child: ClipRect(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Image.file(
                                  widget.imageFile,
                                  fit: BoxFit.cover,
                                  frameBuilder: (context, child, frame, synchronous) {
                                    if ((frame != null || synchronous) && !_imageReady) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted) setState(() => _imageReady = true);
                                      });
                                    }
                                    if (frame == null && !synchronous) {
                                      return const Center(
                                        child: CircularProgressIndicator(color: Colors.white),
                                      );
                                    }
                                    return child;
                                  },
                                  errorBuilder: (_, __, ___) {
                                    if (!_imageLoadFailed) {
                                      WidgetsBinding.instance.addPostFrameCallback((_) {
                                        if (mounted) setState(() => _imageLoadFailed = true);
                                      });
                                    }
                                    return const ColoredBox(
                                      color: Color(0xFF202020),
                                      child: Center(
                                        child: Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.white54,
                                          size: 42,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                for (var i = 0; i < _overlays.length; i++)
                                  _buildOverlay(i),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (_selectedOverlay != null)
              SizedBox(
                height: 58,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final color in _colors)
                      GestureDetector(
                        onTap: () => _changeSelectedColor(color),
                        child: Container(
                          width: 29,
                          height: 29,
                          margin: const EdgeInsets.symmetric(horizontal: 7),
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white70,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            else
              const SizedBox(height: 58),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
              child: Row(
                children: [
                  _EditorTool(
                    icon: Icons.text_fields_rounded,
                    label: 'story_editor_add_text'.tr,
                    onTap: _addText,
                  ),
                  const SizedBox(width: 22),
                  if (_selectedOverlay != null)
                    _EditorTool(
                      icon: Icons.delete_outline_rounded,
                      label: 'story_editor_delete_text'.tr,
                      onTap: () {
                        setState(() {
                          _overlays.removeAt(_selectedOverlay!);
                          _selectedOverlay = null;
                        });
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(int index) {
    final overlay = _overlays[index];
    final selected = _selectedOverlay == index;
    return Align(
      alignment: Alignment(
        (overlay.x * 2) - 1,
        (overlay.y * 2) - 1,
      ),
      child: GestureDetector(
        onTap: () {
          setState(() => _selectedOverlay = index);
          _editText(index);
        },
        onPanStart: (_) => setState(() => _selectedOverlay = index),
        onPanUpdate: (details) => _moveOverlay(index, details),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.38),
            borderRadius: BorderRadius.circular(8),
            border: selected
                ? Border.all(color: Colors.white70, width: 1)
                : null,
          ),
          child: Text(
            overlay.text,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: overlay.color,
              fontSize: 27,
              height: 1.15,
              fontWeight: FontWeight.w700,
              shadows: const [
                Shadow(
                  color: Colors.black54,
                  blurRadius: 5,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StoryTextDialog extends StatefulWidget {
  final String initialText;

  const _StoryTextDialog({required this.initialText});

  @override
  State<_StoryTextDialog> createState() => _StoryTextDialogState();
}

class _StoryTextDialogState extends State<_StoryTextDialog> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
    _focusNode = FocusNode();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _close({bool submit = false}) {
    final result = submit ? _controller.text.trim() : null;
    _focusNode.unfocus();
    Navigator.of(context).pop<String>(result);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF242424),
      title: Text(
        'story_editor_add_text'.tr,
        style: const TextStyle(color: Colors.white),
      ),
      content: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: true,
        maxLines: 4,
        minLines: 1,
        style: const TextStyle(color: Colors.white, fontSize: 18),
        decoration: InputDecoration(
          hintText: 'story_editor_text_hint'.tr,
          hintStyle: const TextStyle(color: Colors.white54),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white38),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _close,
          child: Text('story_editor_cancel'.tr),
        ),
        TextButton(
          onPressed: () => _close(submit: true),
          child: Text('story_editor_done'.tr),
        ),
      ],
    );
  }
}

class _StoryTextOverlay {
  String text;
  double x;
  double y;
  Color color;

  _StoryTextOverlay({
    required this.text,
    this.x = 0.5,
    this.y = 0.5,
    this.color = Colors.white,
  });
}

class _EditorTool extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _EditorTool({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
