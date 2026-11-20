import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../../../app/theme/text_styles.dart';
import '../../../../app/utils/auth_responsive_breakpoints.dart';
import '../../../../shared/constantes/image_path.dart';
import '../../../../shared/widgets/auth_button.dart';
import '../../../../shared/widgets/external_web_view_screen.dart';
import '../../interne/controllers/auth_controller.dart';

class AuthScreen extends GetView<AuthController> {
  const AuthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final orientation = MediaQuery.orientationOf(context);

          // Le rendu mobile existant est conservé tel quel.
          if (AuthResponsiveBreakpoints.isMobile(width)) {
            return _buildMobile(context, colorScheme);
          }

          if (AuthResponsiveBreakpoints.isTwoColumn(width, orientation)) {
            return _buildWideLayout(context, colorScheme, width);
          }

          return _buildTabletLayout(context, colorScheme);
        },
      ),
    );
  }

  Widget _buildMobile(BuildContext context, ColorScheme colorScheme) {
    return Stack(
      children: [
        Positioned(
          top: -80,
          left: -60,
          child: _AmbientBlob(color: colorScheme.primary, size: 260),
        ),
        Positioned(
          bottom: -100,
          right: -80,
          child: _AmbientBlob(color: colorScheme.secondary, size: 300),
        ),
        SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    Container(
                      width: 156,
                      height: 156,
                      alignment: Alignment.center,
                      child: Image.asset(ImagePath.logoApp),
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'welcome_back'.tr,
                      style: AppTextStyles.appName.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'description'.tr,
                      textAlign: TextAlign.center,
                      style: AppTextStyles.bodyLarge.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                    const Spacer(flex: 4),
                    Obx(
                      () => AppAuthButton(
                        onPressed: controller.authentification,
                        isLoading: controller.isLoading.value,
                        icon: SvgPicture.asset(
                          ImagePath.googleImage,
                          width: 20,
                          height: 20,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.g_mobiledata_rounded,
                            color: colorScheme.onSurface,
                            size: 24,
                          ),
                        ),
                        text: 'continue_with_google'.tr,
                      ),
                    ),
                    const SizedBox(height: 20),
                    _LegalLinks(colorScheme: colorScheme),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletLayout(BuildContext context, ColorScheme colorScheme) {
    return Stack(
      children: [
        Positioned(
          top: -90,
          left: -80,
          child: _AmbientBlob(color: colorScheme.primary, size: 300),
        ),
        Positioned(
          bottom: -110,
          right: -100,
          child: _AmbientBlob(color: colorScheme.secondary, size: 340),
        ),
        SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - 64,
                ),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: AuthResponsiveBreakpoints.authCardMaxWidth,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 36,
                        vertical: 40,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF232529),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.white.withValues(alpha: .07)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: .22),
                            blurRadius: 36,
                            offset: const Offset(0, 16),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(ImagePath.logoApp, width: 112, height: 112),
                          const SizedBox(height: 24),
                          Text(
                            'welcome_back'.tr,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.h1.copyWith(color: Colors.white),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'description'.tr,
                            textAlign: TextAlign.center,
                            style: AppTextStyles.bodyLarge.copyWith(
                              color: Colors.white.withValues(alpha: .68),
                            ),
                          ),
                          const SizedBox(height: 32),
                          _ResponsiveGoogleButton(
                            controller: controller,
                            colorScheme: colorScheme,
                          ),
                          const SizedBox(height: 20),
                          _LegalLinks(colorScheme: colorScheme, compact: true),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideLayout(
    BuildContext context,
    ColorScheme colorScheme,
    double screenWidth,
  ) {
    final isTabletLandscape =
        screenWidth < AuthResponsiveBreakpoints.desktopMinWidth;
    final leftFlex = isTabletLandscape ? 48 : 55;
    final rightFlex = 100 - leftFlex;

    return Stack(
      children: [
        Row(
          children: [
            Expanded(
              flex: leftFlex,
              child: Container(
                color: const Color(0xFF1B1D21),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: EdgeInsets.symmetric(
                        horizontal: isTabletLandscape ? 28 : 40,
                        vertical: 28,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 56,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 650),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Image.asset(
                                      ImagePath.logoApp,
                                      width: isTabletLandscape ? 42 : 50,
                                      height: isTabletLandscape ? 42 : 50,
                                    ),
                                    const SizedBox(width: 12),
                                    Text(
                                      'Scrole',
                                      style: AppTextStyles.h2.copyWith(
                                        color: Colors.white,
                                        letterSpacing: -1,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(height: isTabletLandscape ? 34 : 58),
                                _HeroMessage(compact: isTabletLandscape),
                                const SizedBox(height: 28),
                                _VisualComposition(compact: isTabletLandscape),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: rightFlex,
              child: Container(
                color: const Color(0xFF232529),
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 28,
                        vertical: 28,
                      ),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight - 56,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(
                              maxWidth: AuthResponsiveBreakpoints.loginPanelMaxWidth,
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'welcome_back'.tr,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.h1.copyWith(
                                    color: Colors.white,
                                    fontSize: 32,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  'description'.tr,
                                  textAlign: TextAlign.center,
                                  style: AppTextStyles.bodyLarge.copyWith(
                                    color: Colors.white.withValues(alpha: .68),
                                  ),
                                ),
                                const SizedBox(height: 36),
                                _ResponsiveGoogleButton(
                                  controller: controller,
                                  colorScheme: colorScheme,
                                ),
                                const SizedBox(height: 20),
                                _LegalLinks(
                                  colorScheme: colorScheme,
                                  compact: true,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        Positioned(
          left: 24,
          right: 24,
          bottom: 10,
          child: IgnorePointer(
            child: Text(
              'À propos   ·   Aide   ·   Confidentialité   ·   Conditions'
              '                                      © 2026 Scrole',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withValues(alpha: .38),
                fontSize: 10,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _HeroMessage extends StatelessWidget {
  const _HeroMessage({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final size = compact ? 34.0 : 46.0;
    final style = AppTextStyles.displayMedium.copyWith(
      fontSize: size,
      height: 1.12,
      letterSpacing: -1.4,
      color: Colors.white,
    );

    return RichText(
      text: TextSpan(
        style: style,
        children: [
          const TextSpan(text: 'Découvrez les '),
          TextSpan(
            text: 'événements',
            style: style.copyWith(color: const Color(0xFFFF8A3D)),
          ),
          const TextSpan(text: ' et les communautés qui vous '),
          TextSpan(
            text: 'ressemblent.',
            style: style.copyWith(color: const Color(0xFFFF8A3D)),
          ),
        ],
      ),
    );
  }
}

class _VisualComposition extends StatelessWidget {
  const _VisualComposition({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scale = compact ? .78 : 1.0;
    return SizedBox(
      height: 260 * scale,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned(
            left: 18 * scale,
            top: 24 * scale,
            child: Transform.rotate(
              angle: -.075,
              child: _PreviewCard(
                width: 205 * scale,
                height: 178 * scale,
                icon: Icons.people_alt_rounded,
                title: 'Communautés',
                subtitle: 'Rencontrez ceux qui partagent vos passions',
                accent: const Color(0xFFFF8A3D),
              ),
            ),
          ),
          Positioned(
            right: 8 * scale,
            top: 0,
            child: Transform.rotate(
              angle: .065,
              child: _PreviewCard(
                width: 205 * scale,
                height: 190 * scale,
                icon: Icons.event_rounded,
                title: 'Événements',
                subtitle: 'Les expériences à vivre près de vous',
                accent: const Color(0xFF9B8CFF),
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            left: 105 * scale,
            child: Transform.rotate(
              angle: .025,
              child: _PreviewCard(
                width: 220 * scale,
                height: 105 * scale,
                icon: Icons.auto_awesome_rounded,
                title: 'Découvrez Scrole',
                subtitle: 'Tout ce qui vous rassemble, au même endroit.',
                accent: const Color(0xFF54C7A5),
                horizontal: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.width,
    required this.height,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    this.horizontal = false,
  });

  final double width;
  final double height;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF292C32),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .35),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: accent, size: 21),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.h6.copyWith(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  subtitle,
                  maxLines: horizontal ? 2 : 3,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.white.withValues(alpha: .62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveGoogleButton extends StatefulWidget {
  const _ResponsiveGoogleButton({
    required this.controller,
    required this.colorScheme,
  });

  final AuthController controller;
  final ColorScheme colorScheme;

  @override
  State<_ResponsiveGoogleButton> createState() =>
      _ResponsiveGoogleButtonState();
}

class _ResponsiveGoogleButtonState extends State<_ResponsiveGoogleButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final fg = Colors.white;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 52,
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF343840) : const Color(0xFF292C32),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Colors.white.withValues(alpha: _hovered ? .38 : .2),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.controller.isLoading.value
                ? null
                : widget.controller.authentification,
            borderRadius: BorderRadius.circular(12),
            child: Obx(
              () => widget.controller.isLoading.value
                  ? const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SvgPicture.asset(
                          ImagePath.googleImage,
                          width: 20,
                          height: 20,
                          errorBuilder: (_, __, ___) => const Icon(
                            Icons.g_mobiledata_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'continue_with_google'.tr,
                          style: AppTextStyles.button.copyWith(color: fg),
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

class _LegalLinks extends StatelessWidget {
  const _LegalLinks({
    required this.colorScheme,
    this.compact = false,
  });

  final ColorScheme colorScheme;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final baseStyle = AppTextStyles.link.copyWith(
      fontSize: compact ? 12 : 14,
      color: Colors.white.withValues(alpha: .58),
    );
    return Text.rich(
      TextSpan(
        style: baseStyle,
        children: [
          TextSpan(text: '\u0024{'agree_continue'.tr} '),
          TextSpan(
            text: 'terms'.tr,
            style: baseStyle.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openLegalUrl(
                    'https://legal.scrole.fun',
                    'terms'.tr,
                  ),
          ),
          TextSpan(text: ' \u0024{'and'.tr} '),
          TextSpan(
            text: 'privacy_policy'.tr,
            style: baseStyle.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.underline,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () => _openLegalUrl(
                    'https://police.scrole.fun',
                    'privacy_policy'.tr,
                  ),
          ),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}

Future<void> _openLegalUrl(String url, String title) async {
  await Get.to(() => ExternalWebViewScreen(url: url, title: title));
}

class _AmbientBlob extends StatelessWidget {
  const _AmbientBlob({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            color.withValues(alpha: .12),
            color.withValues(alpha: 0),
          ],
        ),
      ),
    );
  }
}
