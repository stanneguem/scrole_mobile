import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scrole/app/routes/app_pages.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../app/theme/text_styles.dart';
import '../../../../shared/widgets/app_cached_image.dart';
import '../controllers/user_agenda_controller.dart';
import '../../centre/models/event_model.dart';
import 'user_pass_screen.dart';

class UserAgendaScreen extends GetView<UserAgendaController> {
  const UserAgendaScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'my_agenda_title'.tr,
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.bold),
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }

        if (controller.myAgenda.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.calendar_today_outlined, size: 64, color: colors.outline),
                const SizedBox(height: 16),
                Text('my_agenda_empty'.tr, style: AppTextStyles.body),
              ],
            ),
          );
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (controller.activeEvent != null) ...[
              _buildActiveEventCard(context, controller.activeEvent!),
              const SizedBox(height: 24),
              Text('agenda_upcoming'.tr, style: AppTextStyles.labelSmall.copyWith(color: colors.outline)),
              const SizedBox(height: 12),
            ],
            ...controller.myAgenda.map((event) => _AgendaItem(
                  event: event,
                  onTap: () async {
                    await Get.toNamed(
                      AppPages.eventPreview.replaceFirst(':id', event.id),
                      arguments: event,
                    );
                    controller.loadMyAgenda();
                  },
                  onPassTap: () => Get.to(() => UserPassScreen(event: event)),
                  onRemoveTap: () => _confirmRemoveEvent(context, event),
                )),
          ],
        );
      }),
    );
  }

  void _confirmRemoveEvent(BuildContext context, EventModel event) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Retirer de l\'agenda ?'),
        content: Text('Voulez-vous vraiment retirer "${event.name}" de votre agenda ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('cancel'.tr),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              controller.removeFromAgenda(event.id);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Retirer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Widget _buildActiveEventCard(BuildContext context, EventModel event) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'agenda_live_now'.tr,
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
              const Spacer(),
              const Icon(Icons.flash_on, color: Colors.white, size: 18),
            ],
          ),
          const SizedBox(height: 12),
          InkWell(
            onTap: () async {
              await Get.toNamed(
                AppPages.eventPreview.replaceFirst(':id', event.id),
                arguments: event,
              );
              controller.loadMyAgenda();
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.name, style: AppTextStyles.h3.copyWith(color: Colors.white)),
                const SizedBox(height: 4),
                Text(event.address ?? '', style: AppTextStyles.bodySmall.copyWith(color: Colors.white.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => Get.to(() => UserPassScreen(event: event)),
            icon: const Icon(Icons.qr_code_scanner, color: AppColors.primary),
            label: Text(
              'agenda_open_pass'.tr,
              style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 50),
            ),
          ),
        ],
      ),
    );
  }
}

class _AgendaItem extends StatelessWidget {
  final EventModel event;
  final VoidCallback onTap;
  final VoidCallback onPassTap;
  final VoidCallback onRemoveTap;

  const _AgendaItem({
    required this.event,
    required this.onTap,
    required this.onPassTap,
    required this.onRemoveTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Text(event.startsAt.day.toString(), style: AppTextStyles.h3),
              Text(
                event.startsAt.month.toString(),
                style: AppTextStyles.bodySmall.copyWith(color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Material(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                onTap: onTap,
                onLongPress: onRemoveTap,
                borderRadius: BorderRadius.circular(14),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AppCachedImage(imageUrl: event.coverImageUrl ?? '', fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(event.name, style: AppTextStyles.h4, overflow: TextOverflow.ellipsis),
                            Text(
                              '${event.startsAt.hour.toString().padLeft(2, '0')}:${event.startsAt.minute.toString().padLeft(2, '0')}',
                              style: AppTextStyles.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_rounded, size: 22, color: AppColors.textSecondary),
                        tooltip: 'user_pass_title'.tr,
                        onPressed: onPassTap,
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, size: 18, color: AppColors.textSecondary),
                        tooltip: 'Retirer de l\'agenda',
                        onPressed: onRemoveTap,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
