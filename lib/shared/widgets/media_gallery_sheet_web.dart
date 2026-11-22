import 'dart:async';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// Browser-native media selection for Flutter Web. The photo_manager gallery
/// is only available on Android/iOS, so Web delegates selection to the browser.
class MediaGallerySheet extends StatefulWidget {
  const MediaGallerySheet({
    super.key,
    required this.onSelected,
    this.maxSelection = 4,
    this.allowMixedMedia = true,
  });

  final FutureOr<void> Function(List<XFile>) onSelected;
  final int maxSelection;
  final bool allowMixedMedia;

  @override
  State<MediaGallerySheet> createState() => _MediaGallerySheetState();
}

class _MediaGallerySheetState extends State<MediaGallerySheet> {
  bool _picking = false;

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final picker = ImagePicker();
      final files = widget.allowMixedMedia
          ? await picker.pickMultipleMedia(limit: widget.maxSelection)
          : await picker.pickMultiImage(limit: widget.maxSelection);
      if (files.isNotEmpty) {
        await widget.onSelected(files);
        // Fermer uniquement la feuille de galerie après que le callback a
        // lancé l'envoi, sans dépiler la page de conversation.
        if (mounted) Navigator.of(context).pop(files);
      }
    } catch (error, stackTrace) {
      debugPrint('[MEDIA_GALLERY_WEB] Browser file selection failed: $error\n$stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Impossible de sélectionner ces médias. Réessaie.')),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Container(
        height: MediaQuery.sizeOf(context).height * .45,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Ajouter des médias', style: Theme.of(context).textTheme.titleLarge),
                ),
                IconButton(
                  onPressed: _picking ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text('Choisis des photos ou vidéos depuis ton appareil.'),
            const Spacer(),
            FilledButton.icon(
              onPressed: _picking ? null : _pick,
              icon: _picking
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.folder_open_rounded),
              label: Text(_picking ? 'Ouverture…' : 'Parcourir les fichiers'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
