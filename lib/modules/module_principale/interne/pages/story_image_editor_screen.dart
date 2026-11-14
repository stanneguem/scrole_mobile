import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image_cropper/image_cropper.dart';
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
  File? _croppedImageFile;
  File get _editedImageFile => _croppedImageFile ?? widget.imageFile;
  bool _isCropping = false;
  int? _selectedOverlay;
  bool _isSaving = false;
  bool _imageReady = false;
  bool _imageLoadFailed = false;
  bool _isDraggingOverlay = false;
  String? _activeTextPanel = 'font';
  String _selectedFilter = 'original';
  bool _showFilters = false;
  double _scaleStartFontSize = 27;
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

  Future<void> _addEmoji() async {
    const emojis = [
      '😀','😃','😄','😁','😆','🥹','😂','🤣','😊','😍','🥰','😘','😎','🤩','🥳',
      '😉','😜','🤗','🤔','😴','😭','😡','🤯','🥺','😇','🤭','🫶','❤️','🧡','💛',
      '💚','💙','💜','🖤','🤍','💖','💗','💞','💕','💘','💝','💯','💥','✨','⭐',
      '🌟','🔥','🌈','☀️','🌙','⚡','❄️','🌸','🌺','🌻','🌹','🍀','🌴','🌊','☁️',
      '🎉','🎊','🎈','🎁','🎂','🏆','🥇','🎵','🎶','📸','💎','👑','🦋','🐼','🐱',
      '🐶','🦄','🍓','🍒','🍑','🍉','🍍','🥑','🍕','🍔','☕','🍹','🚀','✈️','🌍',
      '👍','👎','👏','🙌','🙏','💪','🤝','👋','✌️','🤟','👌','💅','🧿','✅','❌',
    ];
    final emoji = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF202020),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(sheetContext).size.height * 0.48,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                child: Row(
                  children: [
                    const Icon(Icons.emoji_emotions_outlined, color: Colors.white70),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'story_editor_emoji'.tr,
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.fromLTRB(14, 4, 14, 16),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 8,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 5,
                  ),
                  itemCount: emojis.length,
                  itemBuilder: (_, index) => InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => Navigator.pop(sheetContext, emojis[index]),
                    child: Center(
                      child: Text(emojis[index], style: const TextStyle(fontSize: 27)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (emoji == null || !mounted) return;
    setState(() {
      _overlays.add(
        _StoryTextOverlay(
          text: emoji,
          fontSize: 48,
          backgroundColor: Colors.transparent,
        ),
      );
      _selectedOverlay = _overlays.length - 1;
      _activeTextPanel = 'font';
      _showFilters = false;
    });
  }

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

  void _transformSelectedText(String mode) {
    final index = _selectedOverlay;
    if (index == null) return;
    final text = _overlays[index].text;
    String transformed;
    switch (mode) {
      case 'upper':
        transformed = text.toUpperCase();
        break;
      case 'lower':
        transformed = text.toLowerCase();
        break;
      default:
        transformed = text.split(RegExp(r'\s+')).map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1).toLowerCase();
        }).join(' ');
    }
    setState(() => _overlays[index].text = transformed);
  }

  void _rotateSelectedText(double degrees) {
    final index = _selectedOverlay;
    if (index == null) return;
    setState(() {
      _overlays[index].rotationDegrees =
          (_overlays[index].rotationDegrees + degrees) % 360;
    });
  }

  Future<void> _cropImage() async {
    if (_isCropping || _isSaving) return;
    final ratios = <String, CropAspectRatio?>{
      'story_editor_crop_free': null,
      'story_editor_crop_square': const CropAspectRatio(ratioX: 1, ratioY: 1),
      'story_editor_crop_portrait': const CropAspectRatio(ratioX: 4, ratioY: 5),
      'story_editor_crop_story': const CropAspectRatio(ratioX: 9, ratioY: 16),
      'story_editor_crop_landscape': const CropAspectRatio(ratioX: 16, ratioY: 9),
    };
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: const Color(0xFF1D1D1D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('story_editor_crop_title'.tr,
                  style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 14),
              Wrap(
                spacing: 9,
                runSpacing: 9,
                children: ratios.keys.map((key) => ActionChip(
                  label: Text(key.tr),
                  onPressed: () => Navigator.pop(context, key),
                  backgroundColor: const Color(0xFF303030),
                  labelStyle: const TextStyle(color: Colors.white),
                )).toList(),
              ),
            ],
          ),
        ),
      ),
    );
    if (selected == null || !mounted) return;
    setState(() => _isCropping = true);
    try {
      final cropped = await ImageCropper().cropImage(
        sourcePath: _editedImageFile.path,
        aspectRatio: ratios[selected],
        compressFormat: ImageCompressFormat.png,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'story_editor_crop_title'.tr,
            toolbarColor: const Color(0xFF151515),
            toolbarWidgetColor: Colors.white,
            backgroundColor: Colors.black,
            activeControlsWidgetColor: const Color(0xFFFFD21F),
            lockAspectRatio: ratios[selected] != null,
          ),
          IOSUiSettings(
            title: 'story_editor_crop_title'.tr,
            aspectRatioLockEnabled: ratios[selected] != null,
          ),
        ],
      );
      if (cropped != null && mounted) {
        setState(() {
          _croppedImageFile = File(cropped.path);
          _imageReady = false;
          _imageLoadFailed = false;
        });
      }
    } catch (error) {
      debugPrint('[STORY_IMAGE_EDITOR] crop failed: $error');
      if (mounted) {
        Get.snackbar('story_error_title'.tr, 'story_editor_crop_error'.tr,
            snackPosition: SnackPosition.BOTTOM,
            backgroundColor: Colors.black87,
            colorText: Colors.white);
      }
    } finally {
      if (mounted) setState(() => _isCropping = false);
    }
  }

  void _changeSelectedFont(String? fontFamily) {
    final index = _selectedOverlay;
    if (index == null) return;
    setState(() => _overlays[index].fontFamily = fontFamily);
  }

  void _changeSelectedColor(Color color) {
    final index = _selectedOverlay;
    if (index == null) return;
    setState(() => _overlays[index].color = color);
  }

  void _changeSelectedBackground(Color? color) {
    final index = _selectedOverlay;
    if (index == null) return;
    setState(() => _overlays[index].backgroundColor = color);
  }

  void _startOverlayGesture(int index) {
    setState(() {
      _selectedOverlay = index;
      _activeTextPanel ??= 'font';
      _isDraggingOverlay = true;
      _scaleStartFontSize = _overlays[index].fontSize;
    });
  }

  void _updateOverlayGesture(int index, ScaleUpdateDetails details) {
    if (_canvasSize.isEmpty) return;
    final overlay = _overlays[index];
    setState(() {
      overlay.x = (overlay.x + details.focalPointDelta.dx / _canvasSize.width)
          .clamp(0.04, 0.96);
      overlay.y = (overlay.y + details.focalPointDelta.dy / _canvasSize.height)
          .clamp(0.04, 0.96);
      overlay.fontSize = (_scaleStartFontSize * details.scale).clamp(12.0, 96.0);
      _selectedOverlay = index;
    });
  }

  void _endOverlayGesture(int index) {
    final shouldDelete = _overlays[index].y > 0.84;
    setState(() {
      _isDraggingOverlay = false;
      if (shouldDelete) {
        _overlays.removeAt(index);
        _selectedOverlay = null;
      }
    });
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
                                ColorFiltered(
                                  colorFilter: ColorFilter.matrix(_storyFilter(_selectedFilter).matrix),
                                  child: Image.file(
                                  _editedImageFile,
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
            if (_selectedOverlay == null && _showFilters)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                child: _buildFilterOptionsPanel(),
              ),
            if (_selectedOverlay != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildTextOptionsPanel(),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          _TextMenuTab(
                            label: 'story_editor_font'.tr,
                            icon: Icons.font_download_rounded,
                            selected: _activeTextPanel == 'font',
                            onTap: () => setState(() => _activeTextPanel = 'font'),
                          ),
                          _TextMenuTab(
                            label: 'story_editor_text_color'.tr,
                            icon: Icons.palette_outlined,
                            selected: _activeTextPanel == 'text_color',
                            onTap: () => setState(() => _activeTextPanel = 'text_color'),
                          ),
                          _TextMenuTab(
                            label: 'story_editor_background'.tr,
                            icon: Icons.format_color_fill_rounded,
                            selected: _activeTextPanel == 'background',
                            onTap: () => setState(() => _activeTextPanel = 'background'),
                          ),
                          _TextMenuTab(
                            label: 'story_editor_format'.tr,
                            icon: Icons.text_format_rounded,
                            selected: _activeTextPanel == 'format',
                            onTap: () => setState(() => _activeTextPanel = 'format'),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )
            else
              const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
              child: SizedBox(
                height: 66,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  physics: const BouncingScrollPhysics(),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (_isDraggingOverlay)
                        const _TrashDropTarget()
                      else if (_selectedOverlay != null) ...[
                        _EditorTool(
                          icon: Icons.text_fields_rounded,
                          label: 'story_editor_add_text'.tr,
                          onTap: _addText,
                        ),
                        const SizedBox(width: 14),
                        _EditorTool(
                          icon: Icons.delete_outline_rounded,
                          label: 'story_editor_delete_text'.tr,
                          onTap: () {
                            setState(() {
                              _overlays.removeAt(_selectedOverlay!);
                              _selectedOverlay = null;
                              _activeTextPanel = 'font';
                            });
                          },
                        ),
                      ]
                      else ...[
                        _EditorTool(
                          icon: Icons.text_fields_rounded,
                          label: 'story_editor_add_text'.tr,
                          onTap: _addText,
                        ),
                        const SizedBox(width: 14),
                        _EditorTool(
                          icon: Icons.emoji_emotions_outlined,
                          label: 'story_editor_emoji'.tr,
                          onTap: _addEmoji,
                        ),
                        const SizedBox(width: 14),
                        _EditorTool(
                          icon: Icons.crop_rounded,
                          label: 'story_editor_crop_tab'.tr,
                          onTap: () {
                            setState(() => _showFilters = false);
                            _cropImage();
                          },
                        ),
                        const SizedBox(width: 14),
                        _EditorTool(
                          icon: Icons.auto_awesome_rounded,
                          label: 'story_editor_filters'.tr,
                          onTap: () => setState(() => _showFilters = !_showFilters),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterOptionsPanel() {
    return Container(
      height: 112,
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D1D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        itemCount: _storyFilters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final filter = _storyFilters[index];
          final selected = _selectedFilter == filter.id;
          return GestureDetector(
            onTap: () => setState(() => _selectedFilter = filter.id),
            child: SizedBox(
              width: 62,
              child: Column(
                children: [
                  Container(
                    width: 58,
                    height: 68,
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected ? const Color(0xFFFFD21F) : Colors.white12,
                        width: selected ? 2 : 1,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(7),
                      child: ColorFiltered(
                        colorFilter: ColorFilter.matrix(filter.matrix),
                        child: Image.file(_editedImageFile, fit: BoxFit.cover),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    filter.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? const Color(0xFFFFD21F) : Colors.white70,
                      fontSize: 10,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTextOptionsPanel() {
    final overlay = _overlays[_selectedOverlay!];
    switch (_activeTextPanel) {
      case 'text_color':
        return _buildOptionSurface(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: _colors.map((color) => _ColorDot(
              color: color,
              selected: overlay.color == color,
              onTap: () => _changeSelectedColor(color),
            )).toList(),
          ),
        );
      case 'background':
        return _buildOptionSurface(
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 10,
            children: [
              _ColorDot(
                color: Colors.transparent,
                selected: overlay.backgroundColor == null,
                transparent: true,
                onTap: () => _changeSelectedBackground(null),
              ),
              ..._colors.map((color) {
                final background = color.withValues(alpha: 0.78);
                return _ColorDot(
                  color: background,
                  selected: overlay.backgroundColor == background,
                  onTap: () => _changeSelectedBackground(background),
                );
              }),
            ],
          ),
        );
      case 'format':
        return _buildOptionSurface(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _MiniTextAction(icon: Icons.keyboard_capslock_rounded, label: 'ABC', onTap: () => _transformSelectedText('upper')),
                _MiniTextAction(icon: Icons.text_fields_rounded, label: 'abc', onTap: () => _transformSelectedText('lower')),
                _MiniTextAction(icon: Icons.title_rounded, label: 'Abc', onTap: () => _transformSelectedText('title')),
                _MiniTextAction(icon: Icons.rotate_left_rounded, label: '−90°', onTap: () => _rotateSelectedText(-90)),
                _MiniTextAction(icon: Icons.rotate_right_rounded, label: '+90°', onTap: () => _rotateSelectedText(90)),
                _MiniTextAction(icon: Icons.rotate_90_degrees_ccw_rounded, label: '−15°', onTap: () => _rotateSelectedText(-15)),
                _MiniTextAction(icon: Icons.rotate_90_degrees_cw_rounded, label: '+15°', onTap: () => _rotateSelectedText(15)),
              ],
            ),
          ),
        );
      case 'font':
      default:
        const fonts = <(String, String)>[
          ('Roboto', 'Roboto'),
          ('serif', 'Serif'),
          ('monospace', 'Mono'),
          ('cursive', 'Cursive'),
        ];
        return _buildOptionSurface(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: fonts.map((font) {
                final selected = overlay.fontFamily == font.$1;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _changeSelectedFont(font.$1),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFFD21F).withValues(alpha: 0.18) : const Color(0xFF303030),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: selected ? const Color(0xFFFFD21F) : Colors.white12),
                      ),
                      child: Text(
                        font.$2,
                        style: TextStyle(
                          color: selected ? const Color(0xFFFFD21F) : Colors.white,
                          fontFamily: font.$1,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        );
    }
  }

  Widget _buildOptionSurface({required Widget child}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 48),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1D1D1D),
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
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
          setState(() {
            _selectedOverlay = index;
            _activeTextPanel = 'font';
          });
          _editText(index);
        },
        onScaleStart: (_) => _startOverlayGesture(index),
        onScaleUpdate: (details) => _updateOverlayGesture(index, details),
        onScaleEnd: (_) => _endOverlayGesture(index),
        child: Transform.rotate(
          angle: overlay.rotationDegrees * 3.141592653589793 / 180,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: overlay.backgroundColor,
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
                fontSize: overlay.fontSize,
                height: 1.15,
                fontWeight: FontWeight.w700,
                fontFamily: overlay.fontFamily,
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
      ),
    );
  }
}

// Lightweight GPU-backed color presets: no extra native dependency is required.
class _StoryImageFilter {
  final String id;
  final String label;
  final List<double> matrix;

  const _StoryImageFilter(this.id, this.label, this.matrix);
}

List<double> _makeStoryFilter({
  double saturation = 1,
  double red = 1,
  double green = 1,
  double blue = 1,
  double brightness = 0,
  double contrast = 1,
}) {
  final sr = 0.213 * (1 - saturation);
  final sg = 0.715 * (1 - saturation);
  final sb = 0.072 * (1 - saturation);
  final offset = (brightness + (1 - contrast) / 2) * 255;
  return <double>[
    (sr + saturation) * red * contrast, sg * red * contrast, sb * red * contrast, 0, offset,
    sr * green * contrast, (sg + saturation) * green * contrast, sb * green * contrast, 0, offset,
    sr * blue * contrast, sg * blue * contrast, (sb + saturation) * blue * contrast, 0, offset,
    0, 0, 0, 1, 0,
  ];
}

final List<_StoryImageFilter> _storyFilters = [
  _StoryImageFilter('original', 'Original', _makeStoryFilter()),
  _StoryImageFilter('soft', 'Soft', _makeStoryFilter(saturation: 0.82, brightness: 0.045, contrast: 0.94, red: 1.03, green: 1.01, blue: 1.02)),
  _StoryImageFilter('beauty', 'Beauty', _makeStoryFilter(saturation: 0.88, brightness: 0.075, contrast: 0.91, red: 1.05, green: 1.01, blue: 1.02)),
  _StoryImageFilter('glow', 'Glow', _makeStoryFilter(saturation: 0.92, brightness: 0.12, contrast: 0.88, red: 1.06, green: 1.03, blue: 1.00)),
  _StoryImageFilter('porcelain', 'Porcelain', _makeStoryFilter(saturation: 0.72, brightness: 0.09, contrast: 0.90, red: 1.04, green: 1.02, blue: 1.04)),
  _StoryImageFilter('peach', 'Peach', _makeStoryFilter(saturation: 1.03, brightness: 0.035, red: 1.08, green: 1.00, blue: 0.94)),
  _StoryImageFilter('rose', 'Rose', _makeStoryFilter(saturation: 0.94, brightness: 0.025, red: 1.07, green: 0.96, blue: 1.02)),
  _StoryImageFilter('warm', 'Warm', _makeStoryFilter(saturation: 1.08, brightness: 0.025, red: 1.09, green: 1.02, blue: 0.91)),
  _StoryImageFilter('golden', 'Golden', _makeStoryFilter(saturation: 1.14, brightness: 0.045, contrast: 1.02, red: 1.12, green: 1.04, blue: 0.86)),
  _StoryImageFilter('fresh', 'Fresh', _makeStoryFilter(saturation: 1.16, brightness: 0.025, red: 0.98, green: 1.06, blue: 1.02)),
  _StoryImageFilter('vivid', 'Vivid', _makeStoryFilter(saturation: 1.42, contrast: 1.08)),
  _StoryImageFilter('pop', 'Pop', _makeStoryFilter(saturation: 1.28, contrast: 1.18, brightness: 0.015)),
  _StoryImageFilter('cool', 'Cool', _makeStoryFilter(saturation: 0.96, red: 0.94, green: 1.00, blue: 1.10, brightness: 0.015)),
  _StoryImageFilter('ocean', 'Ocean', _makeStoryFilter(saturation: 1.12, red: 0.88, green: 1.00, blue: 1.16, contrast: 1.04)),
  _StoryImageFilter('vintage', 'Vintage', _makeStoryFilter(saturation: 0.72, brightness: 0.055, contrast: 0.88, red: 1.08, green: 1.00, blue: 0.86)),
  _StoryImageFilter('fade', 'Fade', _makeStoryFilter(saturation: 0.78, brightness: 0.075, contrast: 0.78)),
  _StoryImageFilter('film', 'Film', _makeStoryFilter(saturation: 0.92, contrast: 1.12, red: 1.05, green: 1.00, blue: 0.94)),
  _StoryImageFilter('cinema', 'Cinema', _makeStoryFilter(saturation: 0.86, contrast: 1.2, red: 1.08, green: 1.00, blue: 0.91)),
  _StoryImageFilter('noir', 'Noir', _makeStoryFilter(saturation: 0, contrast: 1.22, brightness: -0.015)),
  _StoryImageFilter('mono', 'Mono', _makeStoryFilter(saturation: 0, contrast: 1.04)),
  _StoryImageFilter('dream', 'Dream', _makeStoryFilter(saturation: 0.78, brightness: 0.085, contrast: 0.84, red: 1.04, green: 1.02, blue: 1.08)),
];

_StoryImageFilter _storyFilter(String id) =>
    _storyFilters.firstWhere((filter) => filter.id == id, orElse: () => _storyFilters.first);

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
    return Dialog(
      backgroundColor: const Color(0xFF191919),
      insetPadding: const EdgeInsets.symmetric(horizontal: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD21F).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.text_fields_rounded, color: Color(0xFFFFD21F)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'story_editor_add_text'.tr,
                    style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: _close,
                  icon: const Icon(Icons.close_rounded, color: Colors.white60),
                ),
              ],
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _controller,
              focusNode: _focusNode,
              autofocus: true,
              maxLines: 4,
              minLines: 2,
              style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.4),
              decoration: InputDecoration(
                hintText: 'story_editor_text_hint'.tr,
                hintStyle: const TextStyle(color: Colors.white38),
                filled: true,
                fillColor: const Color(0xFF2B2B2B),
                contentPadding: const EdgeInsets.all(16),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: Color(0xFFFFD21F), width: 1.2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _close,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('story_editor_cancel'.tr),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => _close(submit: true),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD21F),
                      foregroundColor: Colors.black,
                      minimumSize: const Size.fromHeight(46),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text('story_editor_done'.tr, style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MiniTextAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _MiniTextAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF303030), borderRadius: BorderRadius.circular(10)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: Colors.white70),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
      ),
    ),
  );
}

class _TextMenuTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TextMenuTab({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFD21F).withValues(alpha: 0.16) : const Color(0xFF292929),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? const Color(0xFFFFD21F) : Colors.white10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: selected ? const Color(0xFFFFD21F) : Colors.white70),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(
                color: selected ? const Color(0xFFFFD21F) : Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  final bool selected;
  final bool transparent;
  final VoidCallback onTap;

  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
    this.transparent = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 27,
        height: 27,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: selected ? const Color(0xFFFFD21F) : Colors.white54, width: selected ? 2.2 : 1),
        ),
        child: transparent
            ? const Icon(Icons.block_rounded, color: Colors.white, size: 17)
            : null,
      ),
    );
  }
}

class _TrashDropTarget extends StatelessWidget {
  const _TrashDropTarget();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFE53935).withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE53935), width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.delete_outline_rounded, color: Colors.white),
          SizedBox(width: 8),
          Text('story_editor_delete_text'.tr, style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _StoryTextOverlay {
  String text;
  double x;
  double y;
  Color color;
  Color? backgroundColor = Colors.black.withValues(alpha: 0.38);
  double fontSize = 27;
  double rotationDegrees = 0;
  String? fontFamily = 'Roboto';

  _StoryTextOverlay({
    required this.text,
    this.x = 0.5,
    this.y = 0.5,
    this.color = Colors.white,
    this.backgroundColor = const Color(0x61000000),
    this.fontSize = 27,
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
