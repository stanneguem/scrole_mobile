import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'package:image_picker/image_picker.dart';
import 'package:scrole/app/routes/app_pages.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/image_source_sheet.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import 'package:scrole/modules/module_profil/interne/controllers/profile_controller.dart';
import 'package:scrole/modules/module_profil/interne/widgets/circle_button_widget.dart';

class ProfileScreen extends GetView<ProfileController> {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            RefreshIndicator(
              onRefresh: controller.refreshProfile,
              color: colorScheme.primary,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(context, colorScheme),
                    const SizedBox(height: 10),
                    _buildNameAndUsername(colorScheme),
                    const SizedBox(height: 12),
                    _buildFollowStats(colorScheme),
                    const SizedBox(height: 12),
                    _buildBio(colorScheme),
                    const SizedBox(height: 20),
                    _buildTabsAndContent(context, colorScheme),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            
            // Chargement plein écran discret
            Obx(() => controller.isLoading.value
                ? Container(
                    color: Colors.black.withValues(alpha: 0.3),
                    child: Center(
                      child: CircularProgressIndicator(color: colorScheme.primary),
                    ),
                  )
                : const SizedBox.shrink()),
          ],
        ),
      ),
    );
  }

  // ============================================
  // HEADER
  // ============================================
  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return SizedBox(
      height: 185, // 140 (cover) + 45 (avatar overlap)
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: Obx(() {
              final coverUrl = controller.coverImageUrl.value;
              if (coverUrl.isEmpty) {
                return Container(color: AppColors.secondary.withValues(alpha: 0.25));
              }
              return Stack(
                fit: StackFit.expand,
                children: [
                  AppCachedImage(
                    imageUrl: coverUrl,
                    fit: BoxFit.cover,
                    errorWidget: Container(color: AppColors.secondary.withValues(alpha: 0.25)),
                  ),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.35),
                          Colors.black.withValues(alpha: 0.05),
                          colorScheme.surface.withValues(alpha: 0.55),
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ],
              );
            }),
          ),

          Positioned(
            bottom: 8,
            right: 12,
            child: GestureDetector(
              onTap: () => showImageSourceSheet(
                context,
                onCamera: () => controller.pickCoverImage(ImageSource.camera),
                onGallery: () => controller.pickCoverImage(ImageSource.gallery),
              ),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: Obx(
                  () => controller.isUploadingCover.value
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 16),
                ),
              ),
            ),
          ),

          Positioned(
            top: 12,
            left: 16,
            right: 16,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CircleButtonWidget(
                  icon: Icons.arrow_back_ios_rounded,
                  onTap: () => Get.back(),
                ),
                Row(
                  children: [
                    CircleButtonWidget(
                      icon: Icons.people_outline_rounded,
                      onTap: () => Get.toNamed(AppPages.myContacts),
                    ),
                    const SizedBox(width: 8),
                    CircleButtonWidget(
                      icon: Icons.mail_outline_rounded,
                      onTap: () => Get.toNamed(AppPages.eventInvitations),
                    ),
                    const SizedBox(width: 8),
                    CircleButtonWidget(
                      icon: Icons.calendar_today_outlined,
                      onTap: () => Get.toNamed(AppPages.userAgenda),
                    ),
                    const SizedBox(width: 8),
                    CircleButtonWidget(
                      icon: Icons.qr_code_rounded,
                      onTap: () => Get.toNamed(AppPages.userQrCode),
                    ),
                    const SizedBox(width: 8),
                    CircleButtonWidget(
                      icon: Icons.settings_rounded,
                      onTap: () => Get.toNamed(AppPages.setting),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Positioned(
            bottom: 0,
            left: 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Obx(() {
                  final avatarUrl = controller.profileImageUrl.value;
                  return Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: colorScheme.surface, width: 5),
                      color: colorScheme.primary,
                    ),
                    child: avatarUrl.isEmpty
                        ? Center(
                            child: Text(
                              controller.initials,
                              style: AppTextStyles.h3.copyWith(color: Colors.white),
                            ),
                          )
                        : AppCachedImage(
                            imageUrl: avatarUrl,
                            width: 90,
                            height: 90,
                            borderRadius: BorderRadius.circular(45),
                            fit: BoxFit.cover,
                          ),
                  );
                }),
                Positioned(
                  bottom: 2,
                  right: 2,
                  child: GestureDetector(
                    onTap: () => showImageSourceSheet(
                      context,
                      onCamera: () => controller.pickProfileImage(ImageSource.camera),
                      onGallery: () => controller.pickProfileImage(ImageSource.gallery),
                    ),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colorScheme.primary,
                        border: Border.all(color: colorScheme.surface, width: 3),
                      ),
                      child: Obx(
                        () => controller.isUploadingProfileImage.value
                            ? const Padding(
                                padding: EdgeInsets.all(5),
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt_rounded, color: Colors.white, size: 14),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================
  // NAME & USERNAME + bouton d'édition
  // ============================================
  Widget _buildNameAndUsername(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Obx(
                        () => Text(
                          controller.displayName,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.h4.copyWith(color: colorScheme.onSurface),
                        ),
                      ),
                    ),
                    Obx(() {
                      if (!controller.isVerified.value) return const SizedBox.shrink();
                      return const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: UserCertifiedBadge(size: 20),
                      );
                    }),
                  ],
                ),
                const SizedBox(height: 4),
                Obx(
                  () => Text(
                    '@${controller.username.value}',
                    style: AppTextStyles.body.copyWith(color: colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          OutlinedButton.icon(
            onPressed: () => Get.toNamed(AppPages.editmyprofil),
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: Text('profile_edit_button'.tr, style: AppTextStyles.buttonSmall),
            style: OutlinedButton.styleFrom(
              foregroundColor: colorScheme.primary,
              side: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFollowStats(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Obx(() => Row(
        children: [
          Expanded(
            child: _followStat(
              controller.followersCount.value.toString(),
              'follow_tab_followers'.tr,
              colorScheme,
              () => Get.toNamed(AppPages.followLists, arguments: {'userId': controller.userId.value, 'initialTab': 0}),
            ),
          ),
          Expanded(
            child: _followStat(
              controller.followingCount.value.toString(),
              'follow_tab_following'.tr,
              colorScheme,
              () => Get.toNamed(AppPages.followLists, arguments: {'userId': controller.userId.value, 'initialTab': 1}),
            ),
          ),
          Expanded(
            child: _followStat(
              controller.friendsCount.value.toString(),
              'follow_tab_friends'.tr,
              colorScheme,
              () => Get.toNamed(AppPages.followLists, arguments: {'userId': controller.userId.value, 'initialTab': 2}),
            ),
          ),
        ],
      )),
    );
  }

  Widget _followStat(String count, String label, ColorScheme colors, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          children: [
            Text(count, style: AppTextStyles.bodyLarge.copyWith(color: colors.onSurface, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label, style: AppTextStyles.bodySmall.copyWith(color: colors.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  // ============================================
  // BIO
  // ============================================
  Widget _buildBio(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Obx(
        () => Text(
          controller.displayBio,
          style: AppTextStyles.body.copyWith(
            color: controller.bio.value.isEmpty
                ? colorScheme.onSurfaceVariant
                : colorScheme.onSurface.withValues(alpha: 0.85),
            fontStyle: controller.bio.value.isEmpty ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      ),
    );
  }

  // ============================================
  // INSTAGRAM-STYLE TABS & CONTENT
  // ============================================
  Widget _buildTabsAndContent(BuildContext context, ColorScheme colorScheme) {
    return Column(
      children: [
        Obx(() {
          final tab = controller.selectedTab.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildTabButton(0, Icons.grid_on_rounded, 'Publications', tab == 0, colorScheme),
              _buildTabButton(1, Icons.event_rounded, 'Événements', tab == 1, colorScheme),
              _buildTabButton(2, Icons.bookmark_border_rounded, 'Enregistrés', tab == 2, colorScheme),
            ],
          );
        }),
        const SizedBox(height: 4),
        Obx(() {
          switch (controller.selectedTab.value) {
            case 0:
              return _buildUserPostsGrid(colorScheme);
            case 1:
              return _buildUserEventsList(colorScheme);
            case 2:
              return _buildSavedPostsGrid(colorScheme);
            default:
              return const SizedBox.shrink();
          }
        }),
      ],
    );
  }

  Widget _buildTabButton(int index, IconData icon, String label, bool isSelected, ColorScheme colorScheme) {
    return Expanded(
      child: GestureDetector(
        onTap: () => controller.selectedTab.value = index,
        behavior: HitTestBehavior.opaque,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isSelected ? colorScheme.onSurface : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Icon(
            icon,
            size: 24,
            color: isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildUserPostsGrid(ColorScheme colorScheme) {
    final posts = controller.userPosts;
    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text('Aucune publication pour le moment', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        final imageUrl = post.media.isNotEmpty ? post.media.first.url ?? '' : '';
        return Container(
          color: colorScheme.surfaceContainerHighest,
          child: imageUrl.isNotEmpty
              ? AppCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      post.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        );
      },
    );
  }

  Widget _buildUserEventsList(ColorScheme colorScheme) {
    final mockEvents = [
      {
        'title': 'Cameroun Otaku Festival',
        'date': '15 Oct 2026',
        'location': 'Yaoundé, Palais des Congrès',
        'image': 'https://images.unsplash.com/photo-1540575467063-178a50c2df87?w=600&auto=format&fit=crop',
        'role': 'Organisateur',
      },
      {
        'title': 'Yaoundé Tech & Code',
        'date': '22 Oct 2026',
        'location': 'Startup Hub, Yaoundé',
        'image': 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=600&auto=format&fit=crop',
        'role': 'Participant',
      },
      {
        'title': 'Douala Music Fest',
        'date': '05 Nov 2026',
        'location': 'Stade Omnisports, Douala',
        'image': 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&auto=format&fit=crop',
        'role': 'Intervenant',
      },
    ];

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: mockEvents.length,
      itemBuilder: (context, index) {
        final ev = mockEvents[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.25)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  SizedBox(
                    height: 110,
                    width: double.infinity,
                    child: AppCachedImage(
                      imageUrl: ev['image']!,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Container(
                    height: 110,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.black.withValues(alpha: 0.3), Colors.transparent],
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    left: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        ev['role']!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        ev['date']!,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      ev['title']!,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.location_on_rounded, size: 14, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            ev['location']!,
                            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSavedPostsGrid(ColorScheme colorScheme) {
    final posts = controller.savedPosts;
    if (posts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(40),
        child: Center(
          child: Text('Aucun élément enregistré', style: TextStyle(color: colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 2,
        mainAxisSpacing: 2,
      ),
      itemCount: posts.length,
      itemBuilder: (context, index) {
        final post = posts[index];
        final imageUrl = post.media.isNotEmpty ? post.media.first.url ?? '' : '';
        return Container(
          color: colorScheme.surfaceContainerHighest,
          child: imageUrl.isNotEmpty
              ? AppCachedImage(imageUrl: imageUrl, fit: BoxFit.cover)
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.all(4.0),
                    child: Text(
                      post.content,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 10, color: colorScheme.onSurface),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
        );
      },
    );
  }
}
