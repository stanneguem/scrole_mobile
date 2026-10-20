import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/scrole_bottom_sheet.dart';

/// BottomSheet de consultation et rédaction de commentaires événementiels.
class EventCommentsSheet extends StatefulWidget {
  final String eventId;
  final String eventName;

  const EventCommentsSheet({
    super.key,
    required this.eventId,
    required this.eventName,
  });

  @override
  State<EventCommentsSheet> createState() => _EventCommentsSheetState();
}

class _EventCommentsSheetState extends State<EventCommentsSheet> {
  final TextEditingController _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ScroleBottomSheet(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Commentaires',
                style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
              ),
              IconButton(
                onPressed: () => Get.back(),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            widget.eventName,
            style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // Zone d'état vide
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: Column(
              children: [
                Icon(Icons.chat_bubble_outline_rounded, size: 40, color: colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                Text(
                  'Aucun commentaire pour le moment',
                  style: AppTextStyles.labelLarge.copyWith(color: colorScheme.onSurface),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  'Soyez le premier à commenter cet événement !',
                  style: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Zone de saisie
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentController,
                  decoration: InputDecoration(
                    hintText: 'Écrire un commentaire...',
                    hintStyle: AppTextStyles.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
                    filled: true,
                    fillColor: colorScheme.surfaceContainerLow,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () {
                  final text = _commentController.text.trim();
                  if (text.isEmpty) return;
                  _commentController.clear();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Envoi de commentaire en attente de l\'API backend.',
                        style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
                      ),
                      backgroundColor: AppColors.primary,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                },
                icon: const Icon(Icons.send_rounded, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
