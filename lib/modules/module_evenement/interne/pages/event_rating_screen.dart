import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/utils/number_formatter.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import '../../centre/models/event_model.dart';
import '../../centre/repositories/event_repository.dart';

/// Écran complet dédié à la notation d'un événement (Échelle de 1 à 10).
class EventRatingScreen extends StatefulWidget {
  final EventModel event;

  const EventRatingScreen({
    super.key,
    required this.event,
  });

  @override
  State<EventRatingScreen> createState() => _EventRatingScreenState();
}

class _EventRatingScreenState extends State<EventRatingScreen> {
  final EventRepository _repository = Get.find<EventRepository>();

  int? _selectedScore;
  double _ratingAverage = 0.0;
  int _ratingsCount = 0;
  int? _myExistingRating;

  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadRatingStats();
  }

  Future<void> _loadRatingStats() async {
    setState(() => _isLoading = true);

    try {
      final stats = await _repository.getEventInteractionStats(widget.event.id);
      if (stats != null && mounted) {
        final avg = (stats['rating_average'] as num?)?.toDouble() ?? 0.0;
        final count = (stats['ratings_count'] as num?)?.toInt() ?? 0;
        final myScore = (stats['my_rating'] as num?)?.toInt();

        setState(() {
          _ratingAverage = avg;
          _ratingsCount = count;
          _myExistingRating = myScore;
          if (myScore != null && myScore >= 1 && myScore <= 10) {
            _selectedScore = myScore;
          } else {
            _selectedScore = null;
          }
          _isLoading = false;
        });
      } else if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('[EventRatingScreen] _loadRatingStats error: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _submitRating() async {
    if (_selectedScore == null || _isSaving) return;

    setState(() => _isSaving = true);

    try {
      await _repository.rateEvent(
        eventId: widget.event.id,
        rating: _selectedScore!,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Votre note de $_selectedScore/10 a été enregistrée avec succès !',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.primary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Get.back(result: true);
      }
    } catch (e) {
      debugPrint('[EventRatingScreen] _submitRating error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Impossible d\'enregistrer votre note. Veuillez réessayer.',
              style: AppTextStyles.bodySmall.copyWith(color: Colors.white),
            ),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Map<String, String> _getSatisfactionInfo(int? score) {
    if (score == null) {
      return {
        'title': 'Choisissez une note',
        'desc': 'Appuyez sur un chiffre de 1 à 10 pour évaluer l\'événement.',
        'color': '0xFF9CA3AF',
      };
    }
    if (score <= 3) {
      return {
        'title': 'Très insatisfait',
        'desc': 'L\'expérience était largement en dessous de vos attentes.',
        'color': '0xFFEF4444',
      };
    } else if (score <= 5) {
      return {
        'title': 'Insatisfait',
        'desc': 'Certains aspects n\'étaient pas à la hauteur.',
        'color': '0xFFF97316',
      };
    } else if (score <= 7) {
      return {
        'title': 'Satisfait',
        'desc': 'Une expérience globale positive.',
        'color': '0xFFEAB308',
      };
    } else if (score <= 9) {
      return {
        'title': 'Très satisfait',
        'desc': 'Une excellente expérience, très bien organisée !',
        'color': '0xFF10B981',
      };
    } else {
      return {
        'title': 'Exceptionnel',
        'desc': 'Absolument parfait, un moment inoubliable !',
        'color': '0xFF3B82F6',
      };
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final info = _getSatisfactionInfo(_selectedScore);
    final themeColor = Color(int.parse(info['color']!));

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'Noter cet événement',
          style: GoogleFonts.spaceGrotesk(
            color: colorScheme.onSurface,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // En-tête visuel de l'événement
                  ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: SizedBox(
                      width: double.infinity,
                      height: 140,
                      child: widget.event.coverImageUrl != null && widget.event.coverImageUrl!.isNotEmpty
                          ? AppCachedImage(imageUrl: widget.event.coverImageUrl!, fit: BoxFit.cover)
                          : Container(
                              color: colorScheme.surfaceContainerHighest,
                              child: const Icon(Icons.event_rounded, size: 48, color: AppColors.textSecondary),
                            ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    widget.event.name,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),

                  // Statistiques actuelles de notation de l'événement
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star_rounded, size: 18, color: Color(0xFFEAB308)),
                      const SizedBox(width: 4),
                      Text(
                        _ratingsCount > 0
                            ? '${_ratingAverage.toStringAsFixed(1)} / 10'
                            : 'Aucune note pour le moment',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      if (_ratingsCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          '(${NumberFormatter.formatCount(_ratingsCount)} note${_ratingsCount > 1 ? 's' : ''})',
                          style: AppTextStyles.caption.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ],
                  ),
                  if (_myExistingRating != null) ...[
                    const SizedBox(height: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Votre note actuelle : $_myExistingRating/10',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 28),

                  // Affichage de la note sélectionnée
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      color: themeColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: themeColor.withValues(alpha: 0.4), width: 1.5),
                    ),
                    child: Column(
                      children: [
                        Text(
                          _selectedScore != null ? '$_selectedScore / 10' : '- / 10',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                            color: themeColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info['title']!,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          info['desc']!,
                          style: AppTextStyles.bodySmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 28),

                  Text(
                    'Sélectionnez votre note',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Grille de sélection de 1 à 10
                  Wrap(
                    spacing: 10,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: List.generate(10, (index) {
                      final score = index + 1;
                      final isSelected = score == _selectedScore;

                      return InkWell(
                        onTap: () => setState(() => _selectedScore = score),
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: isSelected ? themeColor : colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: isSelected ? themeColor : colorScheme.outlineVariant.withValues(alpha: 0.4),
                              width: isSelected ? 2 : 1,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: themeColor.withValues(alpha: 0.3),
                                      blurRadius: 8,
                                      offset: const Offset(0, 3),
                                    )
                                  ]
                                : [],
                          ),
                          child: Center(
                            child: Text(
                              '$score',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected ? Colors.white : colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),

                  const SizedBox(height: 36),

                  // Bouton de validation
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: (_selectedScore == null || _isSaving) ? null : _submitRating,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
                        disabledForegroundColor: Colors.white70,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                            )
                          : Text(
                              _myExistingRating != null ? 'Modifier ma note' : 'Valider ma note',
                              style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
