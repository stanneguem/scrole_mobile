import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../theme/app_colors.dart';
import '../theme/text_styles.dart';

class AppError {
  final String title;
  final String message;
  final IconData icon;
  final bool isIdempotentSuccess;

  const AppError({
    required this.title,
    required this.message,
    this.icon = Icons.error_outline_rounded,
    this.isIdempotentSuccess = false,
  });
}

AppError mapSupabaseError(dynamic error) {
  final raw = error.toString().toLowerCase();

  if (raw.contains('rate limit') || raw.contains('5 posts') || raw.contains('10 min')) {
    return AppError(title: 'Erreur', message: 'post_error_rate_limit'.tr, icon: Icons.timer_rounded);
  }
  if (raw.contains('video') || raw.contains('vidéo') || raw.contains('not supported')) {
    return AppError(title: 'Erreur', message: 'post_error_videos_not_supported'.tr, icon: Icons.videocam_off_rounded);
  }
  if (raw.contains('invalid photo') || raw.contains('photo invalide')) {
    return AppError(title: 'Erreur', message: 'post_error_invalid_photo'.tr, icon: Icons.broken_image_rounded);
  }
  if (raw.contains('max 4') || raw.contains('4 photos')) {
    return AppError(title: 'Erreur', message: 'post_error_max_photos'.tr, icon: Icons.photo_library_rounded);
  }
  if (raw.contains('text') || raw.contains('media') || raw.contains('required') || raw.contains('requis')) {
    return AppError(title: 'Erreur', message: 'post_error_text_media_required'.tr, icon: Icons.edit_note_rounded);
  }
  if (raw.contains('5000') || raw.contains('char') || raw.contains('caractère')) {
    return AppError(title: 'Erreur', message: 'post_error_max_chars'.tr, icon: Icons.text_fields_rounded);
  }
  if (raw.contains('audience') || raw.contains('invalid_audience')) {
    return AppError(title: 'Erreur', message: 'post_error_invalid_audience'.tr, icon: Icons.group_rounded);
  }
  if (raw.contains('account') || raw.contains('unavailable') || raw.contains('indisponible')) {
    return AppError(title: 'Erreur', message: 'post_error_account_unavailable'.tr, icon: Icons.person_off_rounded);
  }
  if (raw.contains('member') || raw.contains('membre')) {
    return AppError(title: 'Erreur', message: 'post_error_members_only'.tr, icon: Icons.lock_rounded);
  }
  if (raw.contains('comment') || raw.contains('reaction') || raw.contains('disabled') || raw.contains('désactivé')) {
    return AppError(title: 'Erreur', message: 'post_error_comments_reactions_disabled'.tr, icon: Icons.block_rounded);
  }
  if (raw.contains('poll') || raw.contains('sondage')) {
    return AppError(title: 'Erreur', message: 'post_error_poll'.tr, icon: Icons.poll_rounded);
  }

  if (raw.contains('pas enregistrée') ||
      raw.contains('non enregistré') ||
      raw.contains('pas enregistre') ||
      raw.contains('not_registered') ||
      raw.contains('not registered') ||
      raw.contains('pas inscrit') ||
      raw.contains('non inscrit')) {
    return AppError(
      title: 'checkin_not_registered_title'.tr,
      message: 'checkin_not_registered_msg'.tr,
      icon: Icons.person_off_rounded,
    );
  }

  if (raw.contains('vous ne pouvez pas scanner votre propre qr code')) {
    return const AppError(
      title: 'Ce QR code est le tien',
      message: 'Tu ne peux pas t\'ajouter toi-même. Demande à quelqu\'un d\'autre de scanner ton QR code, ou scanne le sien.',
      icon: Icons.qr_code_2_rounded,
    );
  }

  if (raw.contains('qr code introuvable')) {
    return const AppError(
      title: 'QR code introuvable',
      message: 'Ce code ne correspond à aucun QR Scrole valide. Réessaie en cadrant mieux le code.',
      icon: Icons.qr_code_scanner_rounded,
    );
  }

  if (raw.contains('ce qr code n\'est plus valide') || raw.contains('qr code expiré')) {
    return const AppError(
      title: 'QR code expiré',
      message: 'Ce QR code a déjà été utilisé le nombre de fois maximum. Demande un nouveau code à cette personne.',
      icon: Icons.history_rounded,
    );
  }

  if (raw.contains('déjà ami') || raw.contains('vous êtes déjà ami(e)')) {
    return const AppError(
      title: 'Déjà amis',
      message: 'Vous êtes déjà connectés avec cet utilisateur.',
      icon: Icons.check_circle_rounded,
      isIdempotentSuccess: true,
    );
  }

  if (raw.contains('une demande est déjà en attente')) {
    return const AppError(
      title: 'Demande déjà en attente',
      message: 'Une demande d\'ami a déjà été envoyée à cet utilisateur.',
      icon: Icons.hourglass_top_rounded,
      isIdempotentSuccess: true,
    );
  }

  if (raw.contains('vous devez attendre le')) {
    return const AppError(
      title: 'Délai d\'attente requis',
      message: 'Une demande précédente a été refusée. Veuillez patienter avant d\'envoyer une nouvelle demande.',
      icon: Icons.schedule_rounded,
    );
  }

  if (raw.contains('droit') || raw.contains('réservé') || raw.contains('privilège') || raw.contains('42501')) {
    return const AppError(
      title: 'Action non autorisée',
      message: 'Vous ne disposez pas des permissions requises pour réaliser cette action.',
      icon: Icons.lock_outline_rounded,
    );
  }

  if (raw.contains('en cours de suppression') || raw.contains('pending_deletion')) {
    if (raw.contains('annuler') || raw.contains('cancel')) {
      return const AppError(
        title: 'Activité en cours de suppression',
        message: 'Impossible d\'annuler cette demande de transfert : l\'activité est en cours de suppression. Annulez d\'abord la demande de suppression de l\'activité.',
        icon: Icons.warning_amber_rounded,
      );
    }
    return const AppError(
      title: 'Activité en cours de suppression',
      message: 'Cette activité est en cours de suppression. Contactez son propriétaire actuel afin qu\'il annule la demande de suppression. La suppression dispose de 30 jours avant sa suppression définitive.',
      icon: Icons.warning_amber_rounded,
    );
  }

  if (raw.contains('active') && (raw.contains('transfer') || raw.contains('transfert'))) {
    return const AppError(
      title: 'Transfert impossible',
      message: 'L\'activité doit être au statut "Active" pour pouvoir proposer un transfert de propriété.',
      icon: Icons.info_outline_rounded,
    );
  }

  return AppError(
    title: 'Une erreur est survenue',
    message: error.toString().replaceFirst('Exception: ', '').replaceFirst('PostgrestException: ', ''),
    icon: Icons.error_outline_rounded,
  );
}

void showAppErrorDialog(BuildContext context, dynamic error) {
  final appError = mapSupabaseError(error);

  if (appError.isIdempotentSuccess) {
    Get.snackbar(
      appError.title,
      appError.message,
      backgroundColor: Colors.green,
      colorText: Colors.white,
      snackPosition: SnackPosition.BOTTOM,
      margin: const EdgeInsets.all(16),
      borderRadius: 12,
    );
    return;
  }

  showDialog(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(appError.icon, color: AppColors.error, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              appError.title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              appError.message,
              style: AppTextStyles.bodySmall.copyWith(color: AppColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                minimumSize: const Size(double.infinity, 46),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Compris', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    ),
  );
}
