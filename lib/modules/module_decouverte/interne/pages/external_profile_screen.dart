import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';
import 'package:scrole/app/theme/app_colors.dart';
import 'package:scrole/app/theme/text_styles.dart';
import 'package:scrole/shared/models/interest_model.dart';
import 'package:scrole/shared/utils/number_formatter.dart';
import 'package:scrole/shared/widgets/app_cached_image.dart';
import 'package:scrole/shared/widgets/user_certified_badge.dart';
import '../controllers/external_profile_controller.dart';

class ExternalProfileScreen extends GetView<ExternalProfileController> {
  const ExternalProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Obx(() {
          if (controller.isLoading.value) {
            return Center(
              child: CircularProgressIndicator(color: colors.primary),
            );
          }

          final state = controller.profileState.value;

          if (state == ProfileScreenState.deleted) {
            return const _ProfileDeletedView();
          }

          if (state == ProfileScreenState.notFound) {
            return const _ProfileNotFoundView();
          }

          if (state == ProfileScreenState.error) {
            return _ProfileErrorView(
              message: controller.error.value,
              onRetry: controller.loadProfile,
            );
          }

          final isSuspended = state == ProfileScreenState.suspended;
          final isBanned = state == ProfileScreenState.banned;
          final profile = controller.profile.value;

          Widget backgroundProfileView;
          if (profile != null) {
            backgroundProfileView = ListView(
              padding: EdgeInsets.zero,
              children: [
                const _ReactiveHeader(),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _ReactiveIdentity(),
                      const SizedBox(height: 16),
                      const _ReactiveProfileBody(),
                      const SizedBox(height: 30),
                    ],
                  ),
                ),
              ],
            );
          } else {
            backgroundProfileView = Container(color: colors.surface);
          }

          if (isSuspended || isBanned) {
            return Stack(
              fit: StackFit.expand,
              children: [
                AbsorbPointer(
                  absorbing: true,
                  child: backgroundProfileView,
                ),
                if (isSuspended)
                  const _BlockingProfileOverlay(
                    title: 'Profil temporairement indisponible',
                    message: 'Ce compte est actuellement suspendu. Son profil et ses fonctionnalités ne sont pas accessibles pour le moment.',
                    icon: Icons.pause_circle_outline_rounded,
                    iconColor: Colors.orange,
                  )
                else if (isBanned)
                  const _BlockingProfileOverlay(
                    title: 'Profil indisponible',
                    message: 'Ce compte a été banni de Scrole. Son profil et ses fonctionnalités ne sont plus accessibles.',
                    icon: Icons.block_rounded,
                    iconColor: Colors.red,
                  ),
              ],
            );
          }

          if (profile == null) return const SizedBox.shrink();
          if (profile.isBlocked) {
            return _PrivateProfile(
              message: 'profile_blocked_msg'.tr,
            );
          }

          return RefreshIndicator(
            onRefresh: controller.loadProfile,
            color: colors.primary,
            child: backgroundProfileView,
          );
        }),
      ),
    );
  }
}

class _ReactiveHeader extends GetView<ExternalProfileController> {
  const _ReactiveHeader();
  @override
  Widget build(BuildContext context) =>
      Obx(() => _Header(profile: controller.profile.value!));
}

class _Header extends StatelessWidget {
  const _Header({required this.profile});
  final dynamic profile;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SizedBox(
      height: 185,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            height: 140,
            width: double.infinity,
            child: profile.coverUrl == null || profile.coverUrl!.isEmpty
                ? Container(color: AppColors.secondary.withValues(alpha: .25))
                : Stack(
                    fit: StackFit.expand,
                    children: [
                      AppCachedImage(
                        imageUrl: profile.coverUrl!,
                        fit: BoxFit.cover,
                      ),
                      Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: .30),
                              Colors.transparent,
                              colors.surface.withValues(alpha: .35),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
          Positioned(
            top: 12,
            left: 16,
            child: _HeaderButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: Get.back,
            ),
          ),
          Positioned(
            top: 12,
            right: 16,
            child: _HeaderButton(
              icon: Icons.more_horiz_rounded,
              onTap: () => _showProfileMenu(context),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 20,
            child: Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: colors.surface, width: 5),
                color: colors.primary,
              ),
              child: ClipOval(
                child: profile.photoUrl == null || profile.photoUrl!.isEmpty
                    ? const Icon(
                        Icons.person_rounded,
                        size: 48,
                        color: Colors.white,
                      )
                    : AppCachedImage(
                        imageUrl: profile.photoUrl!,
                        fit: BoxFit.cover,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .35),
      builder: (_) => const _ProfileMenuSheet(),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.black.withValues(alpha: .42),
    shape: const CircleBorder(),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    ),
  );
}

class _ReactiveIdentity extends GetView<ExternalProfileController> {
  const _ReactiveIdentity();
  @override
  Widget build(BuildContext context) => Obx(() {
    final p = controller.profile.value!;
    final name = p.displayName.trim();
    final displayName = name.isEmpty
        ? name
        : '${name[0].toUpperCase()}${name.substring(1)}';
    return _Identity(
      profile: p,
      displayName: displayName,
      controller: controller,
    );
  });
}

class _Identity extends StatelessWidget {
  const _Identity({
    required this.profile,
    required this.displayName,
    required this.controller,
  });
  final dynamic profile;
  final String displayName;
  final ExternalProfileController controller;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.h4.copyWith(
                        color: colors.onSurface,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (profile.isCertified) ...[
                    const SizedBox(width: 6),
                    const UserCertifiedBadge(size: 20),
                  ],
                ],
              ),
              if ((profile.username ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  '@${profile.username}',
                  style: TextStyle(
                    color: colors.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              if (profile.age != null || (profile.gender ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    if (profile.age != null) ...[
                      Text(
                        '${profile.age} ans',
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    if (profile.age != null && (profile.gender ?? '').trim().isNotEmpty)
                      Text(' • ', style: TextStyle(color: colors.onSurfaceVariant, fontSize: 12)),
                    if ((profile.gender ?? '').trim().isNotEmpty) ...[
                      Text(
                        profile.gender!,
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
              if ((profile.city ?? '').toString().trim().isNotEmpty ||
                  (profile.country ?? '').toString().trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(
                      Icons.location_on_outlined,
                      size: 14,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        [profile.city, profile.country]
                            .where((s) => s != null && s.toString().trim().isNotEmpty)
                            .join(', '),
                        style: TextStyle(
                          color: colors.onSurfaceVariant,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 10),
        _HeaderStats(profile: profile),
      ],
    );
  }
}

class _ProfileActions extends GetView<ExternalProfileController> {
  const _ProfileActions({required this.controller});
  final ExternalProfileController controller;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Obx(() {
      final p = controller.profile.value!;
      final relationState = p.relationshipState;
      final pending = relationState == 'requested';
      final connected = relationState == 'friends';
      final busy = controller.isSendingRequest.value;
      return Row(
        children: [
          Expanded(
            child: _ConnectionButton(
              state: relationState,
              connected: connected,
              pending: pending,
              busy: busy,
              colors: colors,
              onTap: busy || (p.retryAt != null && p.retryAt!.isAfter(DateTime.now())) ? null : controller.handleConnectionTap,
            ),
          ),
          if (p.canMessage) ...[
            const SizedBox(width: 10),
            Expanded(
              child: _CompactActionButton(
                iconWidget: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SvgPicture.asset(
                      'assets/svg_icons/chat-round-svgrepo-com.svg',
                      width: 18,
                      height: 18,
                      colorFilter: ColorFilter.mode(colors.onSurface, BlendMode.srcIn),
                    ),
                    const SizedBox(width: 6),
                    Text('Message', style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.w600, fontSize: 13.5)),
                  ],
                ),
                foreground: colors.onSurface,
                background: colors.surfaceContainerHigh,
                onTap: controller.openConversation,
              ),
            ),
          ],
        ],
      );
    });
  }
}

class _ConnectionButton extends StatelessWidget {
  const _ConnectionButton({
    required this.state,
    required this.connected,
    required this.pending,
    required this.busy,
    required this.colors,
    required this.onTap,
  });
  final String state;
  final bool connected, pending, busy;
  final ColorScheme colors;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) {
    final isFollowed = state == 'following';
    final isFollowBack = state == 'follow_back';
    final isIncoming = state == 'request_received';
    final isBlocked = state == 'blocked';
    final labeled = pending || connected || isFollowed || isFollowBack || isIncoming || isBlocked;
    final label = switch (state) {
      'friends' => 'follow_state_friends'.tr,
      'following' => 'follow_state_following'.tr,
      'follow_back' => 'follow_state_follow_back'.tr,
      'requested' => 'follow_state_requested'.tr,
      'request_received' => 'follow_state_request_received'.tr,
      'blocked' => 'follow_state_blocked'.tr,
      'self' => 'follow_state_self'.tr,
      _ => 'follow_state_follow'.tr,
    };
    final icon = busy
        ? Icons.hourglass_top_rounded
        : (connected || isFollowed)
            ? Icons.check_rounded
            : (pending || isIncoming)
                ? Icons.hourglass_top_rounded
                : isBlocked
                    ? Icons.block_rounded
                    : Icons.person_add_alt_1_rounded;
    return Material(
      color: (connected || isFollowed)
          ? colors.primary.withValues(alpha: .15)
          : (pending || isIncoming || isBlocked)
              ? colors.surfaceContainerHigh
              : colors.primary,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 38,
          constraints: BoxConstraints(minWidth: labeled ? 110 : 38),
          padding: EdgeInsets.symmetric(horizontal: labeled ? 14 : 0),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: (connected || isFollowed)
                    ? colors.primary
                    : (pending || isIncoming || isBlocked)
                        ? colors.onSurfaceVariant
                        : colors.onPrimary,
                size: 16,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    color: (connected || isFollowed) ? colors.primary : ((pending || isIncoming || isBlocked) ? colors.onSurfaceVariant : colors.onPrimary),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompactActionButton extends StatelessWidget {
  const _CompactActionButton({
    this.icon,
    this.iconWidget,
    required this.foreground,
    required this.background,
    required this.onTap,
  });
  final IconData? icon;
  final Widget? iconWidget;
  final Color foreground;
  final Color background;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(10),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: iconWidget ?? Icon(icon, color: foreground, size: 18),
        ),
      ),
    ),
  );
}

class _ReactiveProfileBody extends GetView<ExternalProfileController> {
  const _ReactiveProfileBody();
  @override
  Widget build(BuildContext context) => Obx(() {
    final p = controller.profile.value!;
    if (p.isPrivate)
      return _PrivateProfile(
        message: 'profile_private_msg'.tr,
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((p.bio ?? '').isNotEmpty) ...[
          _ExpandableBio(bio: p.bio!),
          const SizedBox(height: 14),
        ],
        if (!p.isPrivate) ...[
          _ProfileActions(controller: controller),
          const SizedBox(height: 16),
        ],
        if (p.activities.isNotEmpty) ...[
          const SizedBox(height: 16),
          _ProfileActivitiesSection(activities: p.activities),
        ],
        if ((p.slogan ?? '').isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(p.slogan!, style: const TextStyle(fontStyle: FontStyle.italic)),
        ],
        const SizedBox(height: 20),
        _buildTabsAndContent(context),
      ],
    );
  });

  Widget _buildTabsAndContent(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
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
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Text('Aucune publication de cet utilisateur', style: TextStyle(color: colorScheme.onSurfaceVariant)),
      ),
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
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Center(
        child: Text('Aucun média associé', style: TextStyle(color: colorScheme.onSurfaceVariant)),
      ),
    );
  }
}

class _ExpandableBio extends StatefulWidget {
  final String bio;
  const _ExpandableBio({required this.bio});

  @override
  State<_ExpandableBio> createState() => _ExpandableBioState();
}

class _ExpandableBioState extends State<_ExpandableBio> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(
          text: widget.bio,
          style: TextStyle(color: colors.onSurface, fontSize: 14),
        );
        final tp = TextPainter(
          text: span,
          maxLines: 2,
          textDirection: TextDirection.ltr,
        );
        tp.layout(maxWidth: constraints.maxWidth);
        final exceeds = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.bio,
              style: TextStyle(color: colors.onSurface, fontSize: 14, height: 1.4),
              maxLines: _expanded ? null : 2,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (exceeds) ...[
              const SizedBox(height: 4),
              GestureDetector(
                onTap: () => setState(() => _expanded = !_expanded),
                child: Text(
                  _expanded ? 'profile_see_less'.tr : 'profile_see_more'.tr,
                  style: TextStyle(
                    color: colors.primary,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ProfileInterests extends StatelessWidget {
  const _ProfileInterests({required this.interests});
  final List<Interest> interests;
  @override
  Widget build(BuildContext context) {
    if (interests.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    final visibleInterests = interests.take(3).toList();
    final additionalCount = interests.length - 3;

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        ...visibleInterests.map(
          (i) => Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerLow,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .45),
              ),
            ),
            child: Text(
              '#${i.name}',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        if (additionalCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colors.outlineVariant.withValues(alpha: .6),
              ),
            ),
            child: Text(
              '+$additionalCount',
              style: TextStyle(
                color: colors.onSurfaceVariant,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }
}

class _ProfileStats extends StatelessWidget {
  const _ProfileStats({required this.profile});
  final dynamic profile;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _StatItem(
            value: NumberFormatter.formatCount(profile.friendCount),
            label: 'profile_action_friends'.tr,
          ),
          _StatItem(
            value: NumberFormatter.formatCount(profile.eventsParticipatedCount),
            label: 'profile_stat_participated'.tr,
          ),
          _StatItem(
            value: NumberFormatter.formatCount(profile.eventsInAgendaCount),
            label: 'profile_stat_agenda'.tr,
          ),
          _StatItem(
            value: NumberFormatter.formatCount(profile.followersCount),
            label: 'profile_stat_followers'.tr,
          ),
          _StatItem(
            value: profile.rating > 0 ? profile.rating.toStringAsFixed(1) : '0.0',
            label: 'profile_stat_rating'.tr,
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  const _StatItem({
    required this.value,
    required this.label,
  });
  final String value, label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfileActivitiesSection extends StatelessWidget {
  const _ProfileActivitiesSection({required this.activities});
  final List<Map<String, dynamic>> activities;
  @override
  Widget build(BuildContext context) {
    if (activities.isEmpty) return const SizedBox.shrink();
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Activités',
          style: AppTextStyles.h6.copyWith(color: colors.onSurface, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 120,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: activities.length,
            itemBuilder: (context, index) {
              final act = activities[index];
              return Container(
                width: 140,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.3)),
                ),
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      act['name']?.toString() ?? '',
                      style: TextStyle(color: colors.onSurface, fontWeight: FontWeight.bold),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PrivateProfile extends StatelessWidget {
  const _PrivateProfile({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Icon(Icons.lock_outline_rounded, size: 34),
          const SizedBox(height: 10),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _ProfileMenuSheet extends StatelessWidget {
  const _ProfileMenuSheet();
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.share_rounded),
            title: const Text('Partager le profil'),
            onTap: () {
              Navigator.pop(context);
              // TODO: share profile
            },
          ),
          ListTile(
            leading: const Icon(Icons.flag_rounded, color: Colors.red),
            title: const Text('Signaler le profil', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              // TODO: report profile
            },
          ),
        ],
      ),
    ),
  );
}

class _HeaderStats extends StatelessWidget {
  const _HeaderStats({required this.profile});
  final dynamic profile;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Get.toNamed(AppPages.followLists, arguments: {'userId': profile.userId, 'initialTab': 0}),
          child: _buildStatCol(NumberFormatter.formatCount(profile.followersCount), 'follow_tab_followers'.tr, colors),
        ),
        const SizedBox(width: 10),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Get.toNamed(AppPages.followLists, arguments: {'userId': profile.userId, 'initialTab': 1}),
          child: _buildStatCol(NumberFormatter.formatCount(profile.followingCount), 'follow_tab_following'.tr, colors),
        ),
        const SizedBox(width: 10),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => Get.toNamed(AppPages.followLists, arguments: {'userId': profile.userId, 'initialTab': 2}),
          child: _buildStatCol(NumberFormatter.formatCount(profile.friendsCount), 'follow_tab_friends'.tr, colors),
        ),
      ],
    );
  }

  Widget _buildStatCol(String value, String label, ColorScheme colors) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: colors.onSurface,
          ),
        ),
        const SizedBox(height: 1),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: colors.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ProfileDeletedView extends StatelessWidget {
  const _ProfileDeletedView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_off_rounded, size: 40, color: colors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Profil supprimé',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Ce compte a été supprimé et son profil n’est plus disponible sur Scrole.',
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Retour', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileNotFoundView extends StatelessWidget {
  const _ProfileNotFoundView();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 40, color: colors.primary),
            ),
            const SizedBox(height: 20),
            Text(
              'Profil introuvable',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              'Ce profil n’existe pas ou n’est plus disponible sur Scrole.',
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: const Text('Retour', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: colors.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ProfileErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, size: 40, color: colors.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Erreur de chargement',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: colors.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message.isNotEmpty ? message : 'Impossible de charger ce profil. Vérifiez votre connexion Internet.',
              style: TextStyle(
                fontSize: 14,
                color: colors.onSurfaceVariant,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Retour'),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Réessayer', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
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

class _BlockingProfileOverlay extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color iconColor;

  const _BlockingProfileOverlay({
    required this.title,
    required this.message,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          Navigator.of(context).pop();
        }
      },
      child: Container(
        color: Colors.black.withValues(alpha: 0.65),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: Colors.black26, blurRadius: 16, offset: Offset(0, 8)),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, size: 34, color: iconColor),
                ),
                const SizedBox(height: 18),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: colors.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 10),
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Retour', style: TextStyle(fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: colors.primary,
                    foregroundColor: colors.onPrimary,
                    minimumSize: const Size(double.infinity, 46),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
