import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_trimmer/video_trimmer.dart';
import '../../app/theme/app_colors.dart';

enum _DragMode { start, end, move }

/// Clippe horizontalement la timeline mais laisse dépasser le playhead
/// de quelques pixels en haut et en bas.
class _HClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) => Rect.fromLTRB(0, -6, size.width, size.height + 6);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

class VideoTrimScreen extends StatefulWidget {
  final File videoFile;
  final Duration maxDuration;

  const VideoTrimScreen({
    super.key,
    required this.videoFile,
    this.maxDuration = const Duration(seconds: 29),
  });

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  static const _accent = Color(0xFFFFD21F);
  static const _handleW = 18.0;
  static const _timelineH = 52.0;

  /// Durée visible en même temps sur la timeline (le reste se fait au scroll).
  static const _viewSpanMs = 60000.0;

  Trimmer _trimmer = Trimmer();
  File? _workingVideoFile;
  StreamSubscription<double>? _conversionSubscription;
  double _conversionProgress = 0;
  bool _isConverting = false;
  final ValueNotifier<double> _playhead = ValueNotifier<double>(0);
  final ScrollController _scroll = ScrollController();
  Timer? _ticker;

  bool _isPlaying = false;
  bool _isSaving = false;
  bool _isLoadingVideo = true;
  bool _loadFailed = false;
  bool _muted = false;
  Duration _videoDuration = Duration.zero;

  // Sélection en millisecondes (video_trimmer v5 travaille en ms).
  double _selectedStartMs = 0;
  double _selectedEndMs = 0;

  // Miniatures chargées à la demande (seulement celles visibles).
  final Map<int, File> _thumbs = {};
  final Set<int> _wanted = {};
  final Set<int> _failed = {};
  bool _thumbLoop = false;
  int _thumbSlots = 0;

  // Géométrie de la timeline, recalculée à chaque build.
  double _viewportW = 0;
  double _slotW = 40;
  double _pxPerMs = 1;

  _DragMode? _drag;
  bool _wasAtLimit = false;
  DateTime _lastSeek = DateTime.fromMillisecondsSinceEpoch(0);

  double get _totalMs => _videoDuration.inMilliseconds.toDouble();
  /// Marge de sécurité : on reste 100 ms sous la limite (29 s -> 28,9 s)
  /// pour ne jamais atteindre la durée maximale autorisée.
  static const _safetyMarginMs = 100.0;
  double get _maxMs => math.max(
    1000.0,
    widget.maxDuration.inMilliseconds.toDouble() - _safetyMarginMs,
  );
  double get _minMs => math.min(1000.0, _totalMs);

  @override
  void initState() {
    super.initState();
    _workingVideoFile = widget.videoFile;
    _loadVideo();
  }

  Future<void> _loadVideo() async {
    try {
      await _trimmer.loadVideo(videoFile: widget.videoFile);
      await _finishVideoLoading();
      return;
    } catch (error, stack) {
      debugPrint('[VideoTrimScreen] native load failed; trying H.264 normalization: $error\n$stack');
    }

    // Fallback codec/container: re-encode only when the native trimmer cannot
    // open the original. Media3 (Android) / AVFoundation (iOS) decode the source
    // and write a broadly compatible MP4 (H.264 + AAC) using hardware encoders.
    try {
      _trimmer.dispose();
      if (!mounted) return;
      setState(() {
        _isConverting = true;
        _conversionProgress = 0;
      });

      final subscription = VideoCompress.compressProgress$.listen((progress) {
        if (mounted) setState(() => _conversionProgress = (progress / 100).clamp(0, 1));
      });
      _conversionSubscription = subscription;
      final converted = await VideoCompress.compressVideo(
        (_workingVideoFile ?? widget.videoFile).path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
        includeAudio: true,
      );
      await subscription.cancel();
      _conversionSubscription = null;

      final normalizedFile = converted?.file;
      if (normalizedFile == null) {
        throw StateError('La conversion vidéo n’a retourné aucun fichier.');
      }
      if (!await normalizedFile.exists() || await normalizedFile.length() == 0) {
        throw StateError('Le fichier MP4 normalisé est introuvable ou vide.');
      }

      _workingVideoFile = normalizedFile;
      _trimmer = Trimmer();
      await _trimmer.loadVideo(videoFile: normalizedFile);
      if (mounted) setState(() => _isConverting = false);
      await _finishVideoLoading();
    } catch (error, stack) {
      debugPrint('[VideoTrimScreen] codec normalization failed: $error\n$stack');
      await _conversionSubscription?.cancel();
      _conversionSubscription = null;
      if (mounted) {
        setState(() {
          _isConverting = false;
          _isLoadingVideo = false;
          _loadFailed = true;
        });
      }
    }
  }

  Future<void> _finishVideoLoading() async {
    final duration =
        _trimmer.videoPlayerController?.value.duration ?? Duration.zero;
    final durationMs = duration.inMilliseconds.toDouble();
    if (durationMs <= 0) throw Exception('durée invalide');

    if (!mounted) return;
    setState(() {
      _videoDuration = duration;
      _selectedStartMs = 0;
      _selectedEndMs = math.min(durationMs, _maxMs);
      _isLoadingVideo = false;
      _isConverting = false;
    });
    _ticker ??= Timer.periodic(const Duration(milliseconds: 40), (_) => _tick());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _conversionSubscription?.cancel();
    _playhead.dispose();
    _scroll.dispose();
    // Libère le décodeur natif à la fermeture de l'écran.
    _trimmer.dispose();
    super.dispose();
  }

  // ───────────────────────── Lecture / playhead ─────────────────────────

  void _tick() {
    final c = _trimmer.videoPlayerController;
    if (c == null || !mounted || !c.value.isInitialized) return;
    final v = c.value;
    final pos = v.position.inMilliseconds.toDouble();

    // Lecture en boucle à l'intérieur de la sélection.
    if (v.isPlaying && _drag == null && pos >= _selectedEndMs - 30) {
      c.seekTo(Duration(milliseconds: _selectedStartMs.round()));
    }

    if (_drag == null) _playhead.value = pos;
    if (v.isPlaying != _isPlaying) setState(() => _isPlaying = v.isPlaying);
  }

  void _seekTo(double ms, {bool force = false}) {
    final now = DateTime.now();
    if (!force && now.difference(_lastSeek).inMilliseconds < 70) return;
    _lastSeek = now;
    _playhead.value = ms;
    _trimmer.videoPlayerController?.seekTo(Duration(milliseconds: ms.round()));
  }

  Future<void> _togglePlayback() async {
    if (_isLoadingVideo || _loadFailed || _isSaving) return;
    final c = _trimmer.videoPlayerController;
    if (c == null) return;
    try {
      if (c.value.isPlaying) {
        await c.pause();
      } else {
        final pos = c.value.position.inMilliseconds.toDouble();
        if (pos < _selectedStartMs || pos >= _selectedEndMs - 50) {
          await c.seekTo(Duration(milliseconds: _selectedStartMs.round()));
        }
        await c.play();
      }
      if (mounted) setState(() => _isPlaying = c.value.isPlaying);
    } catch (e) {
      debugPrint('[VideoTrimScreen] playback error: $e');
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    _trimmer.videoPlayerController?.setVolume(_muted ? 0 : 1);
  }

  // ───────────────────────── Miniatures (lazy) ─────────────────────────

  void _requestThumb(int i) {
    if (_thumbs.containsKey(i) || _failed.contains(i)) return;
    if (_wanted.add(i)) scheduleMicrotask(_pumpThumbs);
  }

  /// Charge les miniatures une par une, en commençant par celles
  /// les plus proches du centre de la zone visible.
  Future<void> _pumpThumbs() async {
    if (_thumbLoop) return;
    _thumbLoop = true;
    try {
      while (mounted && _wanted.isNotEmpty) {
        final off = _scroll.hasClients ? _scroll.offset : 0.0;
        final centerSlot = ((off + _viewportW / 2) / _slotW).floor();
        final reach = (_viewportW / _slotW).ceil() + 4;

        _wanted.removeWhere(
              (i) => _thumbs.containsKey(i) || (i - centerSlot).abs() > reach,
        );
        if (_wanted.isEmpty) break;

        final next = _wanted.reduce(
              (a, b) => (a - centerSlot).abs() <= (b - centerSlot).abs() ? a : b,
        );
        _wanted.remove(next);

        final slots = _thumbSlots;
        try {
          final frame = await _grabKeyFrame(next, slots);
          if (!mounted) return;
          if (slots == _thumbSlots && frame != null) {
            setState(() => _thumbs[next] = frame);
          }
        } catch (e) {
          _failed.add(next);
          debugPrint('[VideoTrimScreen] thumbnail $next failed: $e');
        }
      }
    } finally {
      _thumbLoop = false;
    }
  }

  /// Frames plats / noirs (fondus, transitions) : on cherche une image plus
  /// parlante dans la même tranche de temps. Un JPEG très léger = peu de détails.
  static const _flatFrameBytes = 12 * 1024;

  /// Retourne l'image la plus représentative de la tranche [slot].
  /// On prend d'abord le milieu ; si l'image est quasi vide, on essaie
  /// à 25 % et 75 % de la tranche et on garde la plus détaillée.
  Future<File?> _grabKeyFrame(int slot, int slots) async {
    final maxPos = math.max(0, _totalMs.toInt() - 1);
    final slotMs = _totalMs / slots;

    Future<File?> grab(double fraction) async {
      final pos = ((slot + fraction) * slotMs).round().clamp(0, maxPos).toInt();
      final f = await VideoCompress.getFileThumbnail(
        widget.videoFile.path,
        quality: 50,
        position: pos,
      ).timeout(const Duration(seconds: 8));
      return await f.exists() ? f : null;
    }

    var best = await grab(.5);
    if (best != null && await best.length() >= _flatFrameBytes) return best;

    for (final fraction in const [.25, .75]) {
      try {
        final alt = await grab(fraction);
        if (alt == null) continue;
        if (best == null || await alt.length() > await best.length()) best = alt;
      } catch (_) {}
    }
    return best;
  }

  // ───────────────────────── Sauvegarde ─────────────────────────

  Future<void> _saveVideo() async {
    await _trimmer.videoPlayerController?.pause();
    setState(() => _isSaving = true);

    try {
      await _trimmer.saveTrimmedVideo(
        startValue: _selectedStartMs,
        endValue: _selectedEndMs,
        onSave: (outputPath) {
          if (mounted) setState(() => _isSaving = false);
          if (outputPath != null &&
              outputPath.trim().isNotEmpty &&
              File(outputPath).existsSync()) {
            debugPrint('[VideoTrimScreen] TRIM_SUCCESS outputPath=$outputPath');
            Get.back(result: File(outputPath));
          } else {
            debugPrint('[VideoTrimScreen] TRIM_FAILED reason=empty_output_path');
            Get.back<File?>(result: null);
          }
        },
      );
    } catch (e) {
      debugPrint('[VideoTrimScreen] save error: $e');
      if (mounted) setState(() => _isSaving = false);
      // Ne jamais renvoyer la vidéo originale quand le découpage a échoué :
      // elle pourrait dépasser la limite et faire annuler la publication.
      Get.back<File?>(result: null);
    }
  }

  // ───────────────────────── Gestes timeline ─────────────────────────

  /// Fait défiler la timeline pour garder la plage [startPx, endPx]
  /// (en pixels de contenu) visible pendant un glissement.
  void _reveal(double startPx, double endPx) {
    if (!_scroll.hasClients) return;
    final off = _scroll.offset;
    final vw = _scroll.position.viewportDimension;
    var target = off;
    if (startPx < off) {
      target = startPx;
    } else if (endPx > off + vw) {
      target = endPx - vw;
    }
    target = target.clamp(0.0, _scroll.position.maxScrollExtent).toDouble();
    if (target != off) _scroll.jumpTo(target);
  }

  void _beginDrag(_DragMode mode) {
    _trimmer.videoPlayerController?.pause();
    HapticFeedback.selectionClick();
    setState(() {
      _drag = mode;
      _isPlaying = false;
    });
  }

  void _dragBy(_DragMode mode, double dx) {
    if (_drag == null) return;
    final deltaMs = dx / _pxPerMs;

    double start = _selectedStartMs;
    double end = _selectedEndMs;
    final limit = math.min(_maxMs, _totalMs);

    switch (mode) {
      case _DragMode.start:
        start = (start + deltaMs).clamp(0.0, end - _minMs).toDouble();
        if (end - start > limit) start = end - limit;
        break;
      case _DragMode.end:
        end = (end + deltaMs).clamp(start + _minMs, _totalMs).toDouble();
        if (end - start > limit) end = start + limit;
        break;
      case _DragMode.move:
        final len = end - start;
        start = (start + deltaMs).clamp(0.0, _totalMs - len).toDouble();
        end = start + len;
        break;
    }

    final atLimit = (end - start) >= limit - 1 && _totalMs > _maxMs;
    if (atLimit && !_wasAtLimit && mode != _DragMode.move) {
      HapticFeedback.mediumImpact();
    }
    _wasAtLimit = atLimit;

    setState(() {
      _selectedStartMs = start;
      _selectedEndMs = end;
    });

    final sPx = start * _pxPerMs;
    final ePx = end * _pxPerMs;
    switch (mode) {
      case _DragMode.start:
        _reveal(sPx, sPx + _handleW);
        break;
      case _DragMode.end:
        _reveal(ePx - _handleW, ePx);
        break;
      case _DragMode.move:
        _reveal(sPx, ePx);
        break;
    }

    // Aperçu en direct du frame sous la poignée.
    _seekTo(mode == _DragMode.end ? math.max(start, end - 40) : start);
  }

  void _endDrag() {
    if (_drag == null) return;
    _seekTo(_selectedStartMs, force: true);
    setState(() => _drag = null);
  }

  /// Tap sur la timeline : dans la sélection → lecture à cet endroit,
  /// en dehors → la sélection vient se placer autour du point touché.
  void _onTimelineTap(double contentX) {
    final ms = (contentX / _pxPerMs).clamp(0.0, _totalMs).toDouble();
    if (ms >= _selectedStartMs && ms <= _selectedEndMs) {
      _seekTo(math.min(ms, _selectedEndMs - 50), force: true);
      return;
    }
    final len = _selectedEndMs - _selectedStartMs;
    final start = (ms - len / 2).clamp(0.0, _totalMs - len).toDouble();
    HapticFeedback.selectionClick();
    _trimmer.videoPlayerController?.pause();
    setState(() {
      _selectedStartMs = start;
      _selectedEndMs = start + len;
      _isPlaying = false;
    });
    _reveal(start * _pxPerMs, (start + len) * _pxPerMs);
    _seekTo(start, force: true);
  }

  // ───────────────────────── UI ─────────────────────────

  @override
  Widget build(BuildContext context) {
    final ready = !_isLoadingVideo && !_loadFailed;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                _buildTopBar(ready && !_isSaving),
                Expanded(child: _buildPreview()),
                if (ready) _buildBottomBar(),
              ],
            ),
            if (_isSaving || _isConverting)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: .72),
                  alignment: Alignment.center,
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: 16),
                      Text(
                        'Découpage en cours…',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar(bool canSave) {
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white, size: 24),
            onPressed: _isSaving ? null : () => Get.back<File?>(result: null),
          ),
          IconButton(
            icon: Icon(
              _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: _accent,
              size: 22,
            ),
            onPressed: (!_isLoadingVideo && !_loadFailed) ? _toggleMute : null,
          ),
          const Spacer(),
          TextButton(
            onPressed: canSave ? _saveVideo : null,
            child: const Text(
              'Terminer',
              style: TextStyle(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (_isLoadingVideo) {
      return const Center(child: CircularProgressIndicator(color: Colors.white));
    }
    if (_loadFailed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Impossible de lire cette vidéo sur cet appareil.',
            style: TextStyle(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _togglePlayback,
      child: VideoViewer(trimmer: _trimmer),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      color: Colors.black,
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
      child: Row(
        children: [
          // Bouton lecture / pause à gauche de la timeline
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 44,
              height: _timelineH,
              decoration: BoxDecoration(
                color: const Color(0xFF2C2C2E),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: _timelineH,
              child: LayoutBuilder(
                builder: (context, c) => _buildTimeline(c.maxWidth),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeline(double vw) {
    final total = _totalMs;
    // La zone visible couvre au maximum 1 minute ; au-delà, on scrolle.
    final visibleSpan = math.min(total, _viewSpanMs);
    final contentW = vw * total / visibleSpan;

    _viewportW = vw;
    _pxPerMs = contentW / total;

    final slots = math.max(1, (contentW / (vw / 8)).ceil());
    _slotW = contentW / slots;
    if (slots != _thumbSlots) {
      _thumbSlots = slots;
      _thumbs.clear();
      _wanted.clear();
      _failed.clear();
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Bande de miniatures scrollable (tap = lecture / déplacement)
        Positioned.fill(
          child: GestureDetector(
            onTapUp: (d) {
              final off = _scroll.hasClients ? _scroll.offset : 0.0;
              _onTimelineTap(off + d.localPosition.dx);
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ListView.builder(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                itemExtent: _slotW,
                itemCount: slots,
                itemBuilder: (_, i) {
                  final f = _thumbs[i];
                  if (f == null) {
                    _requestThumb(i);
                    return Container(
                      color: i.isEven
                          ? const Color(0xFF2A2A2A)
                          : const Color(0xFF222222),
                    );
                  }
                  return Image.file(
                    f,
                    fit: BoxFit.cover,
                    height: double.infinity,
                    gaplessPlayback: true,
                    frameBuilder: (_, child, frame, sync) => AnimatedOpacity(
                      opacity: (frame == null && !sync) ? 0 : 1,
                      duration: const Duration(milliseconds: 250),
                      child: child,
                    ),
                  );
                },
              ),
            ),
          ),
        ),

        // Sélection, poignées et playhead, positionnés selon le scroll
        Positioned.fill(
          child: AnimatedBuilder(
            animation: Listenable.merge([_scroll, _playhead]),
            builder: (_, __) => _buildOverlay(vw),
          ),
        ),
      ],
    );
  }

  Widget _buildOverlay(double vw) {
    final off = _scroll.hasClients ? _scroll.offset : 0.0;
    final sx = _selectedStartMs * _pxPerMs - off;
    final ex = _selectedEndMs * _pxPerMs - off;
    final selW = math.max(ex - sx, _handleW * 2);
    final endHandleLeft = math.max(sx + _handleW, ex - _handleW);

    final leftDimW = sx.clamp(0.0, vw).toDouble();
    final rightDimLeft = ex.clamp(0.0, vw).toDouble();

    final minX = sx + _handleW;
    final maxX = math.max(minX, ex - _handleW);
    final phX =
    (_playhead.value * _pxPerMs - off).clamp(minX, maxX).toDouble();

    return ClipRect(
      clipper: _HClipper(),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Zones hors sélection assombries
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: leftDimW,
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: .62)),
            ),
          ),
          Positioned(
            left: rightDimLeft,
            top: 0,
            bottom: 0,
            width: math.max(0.0, vw - rightDimLeft),
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: .62)),
            ),
          ),

          // Cadre jaune (bords haut / bas)
          Positioned(
            left: sx,
            top: 0,
            bottom: 0,
            width: selW,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.symmetric(
                    horizontal: BorderSide(color: _accent, width: 3),
                  ),
                ),
              ),
            ),
          ),

          // Poignées avec chevrons
          Positioned(
            left: sx,
            top: 0,
            bottom: 0,
            width: _handleW,
            child: IgnorePointer(child: _handle(left: true)),
          ),
          Positioned(
            left: endHandleLeft,
            top: 0,
            bottom: 0,
            width: _handleW,
            child: IgnorePointer(child: _handle(left: false)),
          ),

          // Playhead blanc
          Positioned(
            left: phX - 1.5,
            top: -3,
            bottom: -3,
            width: 3,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: const [
                    BoxShadow(color: Colors.black45, blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),

          // Zones tactiles : milieu = déplacer la sélection
          Positioned(
            left: sx + _handleW,
            top: 0,
            bottom: 0,
            width: math.max(0.0, ex - sx - _handleW * 2),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapUp: (d) => _onTimelineTap(off + sx + _handleW + d.localPosition.dx),
              onHorizontalDragStart: (_) => _beginDrag(_DragMode.move),
              onHorizontalDragUpdate: (d) => _dragBy(_DragMode.move, d.delta.dx),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: _endDrag,
            ),
          ),
          // Poignée gauche : zone élargie
          Positioned(
            left: sx - 14,
            top: 0,
            bottom: 0,
            width: _handleW + 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _beginDrag(_DragMode.start),
              onHorizontalDragUpdate: (d) => _dragBy(_DragMode.start, d.delta.dx),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: _endDrag,
            ),
          ),
          // Poignée droite : zone élargie
          Positioned(
            left: endHandleLeft - 6,
            top: 0,
            bottom: 0,
            width: _handleW + 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (_) => _beginDrag(_DragMode.end),
              onHorizontalDragUpdate: (d) => _dragBy(_DragMode.end, d.delta.dx),
              onHorizontalDragEnd: (_) => _endDrag(),
              onHorizontalDragCancel: _endDrag,
            ),
          ),
        ],
      ),
    );
  }

  Widget _handle({required bool left}) {
    const r = Radius.circular(8);
    return Container(
      decoration: BoxDecoration(
        color: _accent,
        borderRadius: BorderRadius.horizontal(
          left: left ? r : Radius.zero,
          right: left ? Radius.zero : r,
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        left ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
        color: Colors.black,
        size: 22,
      ),
    );
  }
}