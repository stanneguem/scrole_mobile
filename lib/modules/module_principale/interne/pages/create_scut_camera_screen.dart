import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nosmai_effects_sdk/nosmai_effects_sdk.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:scrole/modules/module_communautes/interne/pages/create_community_post_screen.dart';

class CreateScutCameraScreen extends StatefulWidget {
  const CreateScutCameraScreen({super.key});
  @override
  State<CreateScutCameraScreen> createState() => _CreateScutCameraScreenState();
}

class _CreateScutCameraScreenState extends State<CreateScutCameraScreen>
    with NosmaiCameraLifecycleMixin {
  final _sdk = NosmaiFlutter.instance;
  final _picker = ImagePicker();
  bool _loading = true, _ready = false, _recording = false, _leaving = false, _allowPop = false;
  String? _error;
  Timer? _timer;
  int _seconds = 0, _panel = 0, _preset = 1;
  double _smooth = .32, _whiten = .10, _sharp = .12, _face = 0, _eyes = 0, _nose = 0;
  static const _names = ['Original', 'Naturel', 'Glow', 'Glamour', 'Doux'];
  static const _icons = [Icons.videocam_outlined, Icons.face_retouching_natural, Icons.auto_awesome, Icons.diamond_outlined, Icons.spa_outlined];

  @override
  void initState() { super.initState(); _init(); }
  @override
  void dispose() { _timer?.cancel(); super.dispose(); }

  Future<void> _init() async {
    setState(() { _loading = true; _error = null; _ready = false; });
    try {
      if (!(await Permission.camera.request()).isGranted) {
        throw StateError('Autorise l’accès à la caméra dans les paramètres du téléphone.');
      }
      await Permission.microphone.request();
      final key = Platform.isAndroid
          ? const String.fromEnvironment('NOSMAI_ANDROID_LICENSE_KEY')
          : const String.fromEnvironment('NOSMAI_IOS_LICENSE_KEY');
      if (key.trim().isEmpty) {
        throw StateError('Clé Nosmai manquante. Configure NOSMAI_ANDROID_LICENSE_KEY avec --dart-define.');
      }
      if (!await NosmaiFlutter.initialize(key)) {
        throw StateError('Clé Nosmai invalide ou non associée à com.scrole.app.');
      }
      await _sdk.configureCamera(position: NosmaiCameraPosition.front);
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.toString().replaceFirst('Bad state: ', ''); });
    }
  }

  Future<void> _previewReady() async {
    try {
      final prepared = await _sdk.prepareBeautyFilters();
      if (!prepared) throw StateError('Le moteur beauté n’a pas pu être préparé.');
      if (!mounted) return;
      setState(() { _ready = true; _error = null; });
      await _presetApply(1, toast: false);
    } catch (e) { if (mounted) { setState(() => _ready = true); _showError('Filtres beauté indisponibles', e); } }
  }

  void _previewError(String e) { if (mounted) setState(() { _ready = false; _error = e; }); }

  Future<void> _switchCamera() async {
    if (!_ready || _recording) return;
    try { await _sdk.switchCamera(); } catch (e) { _showError('Changement de caméra impossible', e); }
  }

  Future<void> _recordToggle() async {
    if (!_ready || _leaving) return;
    try {
      if (!_recording) {
        if (await _sdk.startRecording() && mounted) {
          setState(() { _recording = true; _seconds = 0; });
          _timer?.cancel();
          _timer = Timer.periodic(const Duration(seconds: 1), (_) { if (mounted) setState(() => _seconds++); });
        }
      } else {
        _timer?.cancel();
        final result = await _sdk.stopRecording();
        if (!mounted) return;
        setState(() => _recording = false);
        if (result.success && result.videoPath != null) {
          await _openComposer(File(result.videoPath!));
        } else { _showError('Enregistrement impossible', result.error ?? 'La vidéo n’a pas été créée.'); }
      }
    } catch (e) { _timer?.cancel(); if (mounted) setState(() => _recording = false); _showError('Enregistrement impossible', e); }
  }

  Future<void> _gallery() async {
    if (_recording || _leaving) return;
    try {
      final file = await _picker.pickVideo(source: ImageSource.gallery, maxDuration: const Duration(minutes: 10));
      if (file != null && mounted) await _openComposer(File(file.path));
    } catch (e) { _showError('Galerie indisponible', e); }
  }

  Future<void> _openComposer(File file) async {
    if (_leaving || !mounted) return;
    if (!await file.exists() || await file.length() == 0) { _showError('Vidéo indisponible', 'Fichier introuvable.'); return; }
    setState(() => _leaving = true);
    _timer?.cancel();
    await cleanupBeforeNavigation();
    if (!mounted) return;
    _allowPop = true;
    Get.off(() => CreateCommunityPostScreen(
      communityName: 'Fil d’actualité général',
      prefilledMediaUrl: file.path,
      prefilledMediaIsVideo: true,
    ));
  }

  Future<void> _close() async {
    if (_leaving) return;
    _leaving = true;
    _timer?.cancel();
    if (_recording) { try { await _sdk.stopRecording(); } catch (_) {} }
    await cleanupBeforeNavigation();
    if (!mounted) return;
    setState(() => _allowPop = true);
    Get.back();
  }

  Future<void> _presetApply(int i, {bool toast = true}) async {
    if (!_ready || _recording) return;
    try {
      if (i == 0) {
        await _sdk.removeAllBeautyEffects();
        await _sdk.removeAllFilters();
        _smooth = _whiten = _sharp = _face = _eyes = _nose = 0;
      } else {
        final v = switch (i) {
          1 => (.32, .10, .12, 0.0, 0.0, 0.0),
          2 => (.58, .22, .22, 0.0, .05, 0.0),
          3 => (.48, .18, .18, .16, .14, .10),
          _ => (.42, .12, .16, 0.0, 0.0, 0.0),
        };
        _smooth = v.$1; _whiten = v.$2; _sharp = v.$3; _face = v.$4; _eyes = v.$5; _nose = v.$6;
        await _sdk.applySkinSmoothing(_smooth);
        await _sdk.applySkinWhitening(_whiten);
        await _sdk.applySharpening(_sharp);
        await _sdk.setFaceSlimLevel(_face);
        await _sdk.setEyeSizeLevel(_eyes);
        await _sdk.setNoseSlimLevel(_nose);
      }
      if (mounted) setState(() => _preset = i);
      if (toast) Get.snackbar('Filtre appliqué', _names[i], snackPosition: SnackPosition.BOTTOM);
    } catch (e) { _showError('Filtre indisponible', e); }
  }

  Future<void> _change(String id, double v) async {
    setState(() {
      _preset = -1;
      if (id == 'smooth') _smooth = v;
      if (id == 'whiten') _whiten = v;
      if (id == 'sharp') _sharp = v;
      if (id == 'face') _face = v;
      if (id == 'eyes') _eyes = v;
      if (id == 'nose') _nose = v;
    });
    try {
      if (id == 'smooth') await _sdk.applySkinSmoothing(v);
      if (id == 'whiten') await _sdk.applySkinWhitening(v);
      if (id == 'sharp') await _sdk.applySharpening(v);
      if (id == 'face') await _sdk.setFaceSlimLevel(v);
      if (id == 'eyes') await _sdk.setEyeSizeLevel(v);
      if (id == 'nose') await _sdk.setNoseSlimLevel(v);
    } catch (e) { _showError('Réglage impossible', e); }
  }

  Future<void> _makeup(int type, int style) async {
    try {
      if (type == 0) {
        await _sdk.applyLipstick(style: NosmaiLipstickStyle.values[style], intensity: .72);
      } else {
        await _sdk.applyEyeshadow(style: NosmaiEyeshadowStyle.values[style], intensity: .68);
      }
    } catch (e) { _showError('Maquillage indisponible', e); }
  }

  void _filters() {
    if (!_ready || _recording) return;
    showModalBottomSheet<void>(
      context: context, backgroundColor: const Color(0xFF151515), isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, sheetSet) => SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(18, 14, 18, 18 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white30, borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 18),
            Row(children: [
              const Expanded(child: Text('Filtres et beauté', style: TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700))),
              TextButton(onPressed: () async { await _presetApply(0, toast: false); sheetSet(() {}); }, child: const Text('Réinitialiser')),
            ]),
            Row(children: [
              _tab('Beauté', 0, sheetSet), _tab('Visage', 1, sheetSet), _tab('Maquillage', 2, sheetSet),
            ]),
            const SizedBox(height: 18),
            if (_panel == 0) ...[
              const _Section('FILTRES BEAUTÉ'),
              const SizedBox(height: 10),
              SizedBox(height: 96, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: _names.length,
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (_, i) => GestureDetector(onTap: () async { await _presetApply(i, toast: false); sheetSet(() {}); },
                  child: SizedBox(width: 68, child: Column(children: [
                    Container(width: 58, height: 58, decoration: BoxDecoration(shape: BoxShape.circle, color: _preset == i ? Colors.white : Colors.white12, border: Border.all(color: _preset == i ? Colors.white : Colors.white24, width: 2)),
                      child: Icon(_icons[i], color: _preset == i ? Colors.black : Colors.white)),
                    const SizedBox(height: 7), Text(_names[i], style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ])))),
              _slider('Lissage de la peau', _smooth, (v) async { await _change('smooth', v); sheetSet(() {}); }),
              _slider('Éclat du teint', _whiten, (v) async { await _change('whiten', v); sheetSet(() {}); }),
              _slider('Détails et texture', _sharp, (v) async { await _change('sharp', v); sheetSet(() {}); }),
            ] else if (_panel == 1) ...[
              const _Section('RETOUCHE DU VISAGE'),
              _slider('Affiner le visage', _face, (v) async { await _change('face', v); sheetSet(() {}); }),
              _slider('Agrandir les yeux', _eyes, (v) async { await _change('eyes', v); sheetSet(() {}); }),
              _slider('Affiner le nez', _nose, (v) async { await _change('nose', v); sheetSet(() {}); }),
            ] else ...[
              const _Section('MAQUILLAGE VIRTUEL'),
              const SizedBox(height: 12),
              const Text('Rouge à lèvres', style: TextStyle(color: Colors.white)),
              _choices(['Classique', 'Mat', 'Naturel'], (i) => _makeup(0, i)),
              const SizedBox(height: 14),
              const Text('Fard à paupières', style: TextStyle(color: Colors.white)),
              _choices(['Smokey', 'Brillant', 'Naturel'], (i) => _makeup(1, i)),
            ],
            const SizedBox(height: 12),
            const Text('Les effets sont appliqués en direct et intégrés à la vidéo enregistrée.', style: TextStyle(color: Colors.white54, fontSize: 12)),
          ])),
        ),
      )),
    );
  }

  Widget _tab(String label, int index, StateSetter setter) => Expanded(child: Padding(
    padding: const EdgeInsets.only(right: 6),
    child: GestureDetector(onTap: () => setter(() => _panel = index),
      child: Container(padding: const EdgeInsets.symmetric(vertical: 11),
        decoration: BoxDecoration(color: _panel == index ? Colors.white : Colors.white10, borderRadius: BorderRadius.circular(13)),
        child: Text(label, textAlign: TextAlign.center, style: TextStyle(color: _panel == index ? Colors.black : Colors.white70, fontSize: 12, fontWeight: FontWeight.w700))))));

  Widget _slider(String label, double value, ValueChanged<double> change) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [Expanded(child: Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13))),
        Text((value * 100).round().toString() + '%', style: const TextStyle(color: Colors.white54, fontSize: 12))]),
      Slider(value: value.clamp(0.0, 1.0), onChanged: change, activeColor: Colors.white, inactiveColor: Colors.white24),
    ]));

  Widget _choices(List<String> labels, ValueChanged<int> choose) => Wrap(spacing: 8, children: List.generate(labels.length, (i) => ActionChip(
    label: Text(labels[i]), onPressed: () => choose(i), backgroundColor: Colors.white12, side: BorderSide.none, labelStyle: const TextStyle(color: Colors.white))));

  void _showError(String title, Object error) {
    if (!mounted) return;
    Get.snackbar(title, error.toString().replaceFirst('Exception: ', ''), snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.black87, colorText: Colors.white);
  }

  @override
  Widget build(BuildContext context) => PopScope<Object?>(
    canPop: _allowPop, onPopInvokedWithResult: (didPop, result) { if (!didPop) _close(); },
    child: Scaffold(backgroundColor: Colors.black, body: Stack(fit: StackFit.expand, children: [
      if (!_loading && _error == null) RepaintBoundary(child: NosmaiCameraPreview(onInitialized: _previewReady, onError: _previewError)),
      if (_loading) const Center(child: CircularProgressIndicator(color: Colors.white)),
      if (_error != null && !_loading) Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.camera_alt_outlined, color: Colors.white, size: 42), const SizedBox(height: 14),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white70)), const SizedBox(height: 16),
        OutlinedButton(onPressed: _init, child: const Text('Réessayer', style: TextStyle(color: Colors.white))),
      ]))),
      const IgnorePointer(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0x99000000), Colors.transparent, Color(0xB3000000)], stops: [0, .38, 1])))),
      SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 0), child: Row(children: [
          _CameraButton(Icons.close_rounded, _close), const Spacer(),
          Text('creation_menu_create_scut'.tr, style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
          const Spacer(), _CameraButton(Icons.flip_camera_android_rounded, _switchCamera, enabled: _ready && !_recording),
        ])),
        if (_recording) Padding(padding: const EdgeInsets.only(top: 18), child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(20)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 8, height: 8, decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle)),
            const SizedBox(width: 7), Text((_seconds ~/ 60).toString().padLeft(2, '0') + ':' + (_seconds % 60).toString().padLeft(2, '0'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]))),
        const Spacer(),
        Padding(padding: const EdgeInsets.fromLTRB(34, 0, 34, 26),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            _CameraButton(Icons.photo_library_outlined, _gallery, size: 54, enabled: !_recording),
            GestureDetector(onTap: _ready ? _recordToggle : null, child: Opacity(opacity: _ready ? 1 : .35, child: AnimatedContainer(duration: const Duration(milliseconds: 160), width: _recording ? 78 : 72, height: _recording ? 78 : 72,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 5)),
              child: Center(child: AnimatedContainer(duration: const Duration(milliseconds: 160), width: _recording ? 30 : 56, height: _recording ? 30 : 56,
                decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(_recording ? 8 : 40)))))),
            _CameraButton(Icons.face_retouching_natural, _filters, size: 54, enabled: _ready && !_recording),
          ])),
      ])),
    ])),
  );
}

class _Section extends StatelessWidget {
  const _Section(this.label); final String label;
  @override Widget build(BuildContext context) => Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.1));
}

class _CameraButton extends StatelessWidget {
  const _CameraButton(this.icon, this.onTap, {this.size = 42, this.enabled = true});
  final IconData icon; final VoidCallback onTap; final double size; final bool enabled;
  @override Widget build(BuildContext context) => Material(color: Colors.black.withValues(alpha: .42), shape: const CircleBorder(),
    child: InkWell(customBorder: const CircleBorder(), onTap: enabled ? onTap : null,
      child: SizedBox(width: size, height: size, child: Icon(icon, color: enabled ? Colors.white : Colors.white38, size: 23))));
}
