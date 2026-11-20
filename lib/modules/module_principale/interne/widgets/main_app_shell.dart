import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../../app/utils/main_responsive_breakpoints.dart';
import '../controllers/main_layout_controller.dart';
import 'main_app_bar.dart';

/// Coquille persistante de navigation des pages principales Scrole.
///
/// Le shell ne connaît ni les données du fil ni la logique métier des pages.
/// Le contenu central est fourni par [child].
class MainAppShell extends StatefulWidget {
  const MainAppShell({
    super.key,
    required this.child,
    required this.controller,
    required this.onDestinationSelected,
    required this.mobileDrawer,
    required this.mobileBottomNavigation,
    required this.tabletRail,
    required this.desktopSidebar,
    this.rightSidebar,
    this.onScrollNotification,
    this.bottomNavigationVisible = true,
  });

  final Widget child;
  final MainLayoutController controller;
  final ValueChanged<int> onDestinationSelected;
  final Widget mobileDrawer;
  final Widget mobileBottomNavigation;
  final Widget tabletRail;
  final Widget desktopSidebar;
  final Widget? rightSidebar;
  final bool Function(ScrollNotification)? onScrollNotification;
  final bool bottomNavigationVisible;

  @override
  State<MainAppShell> createState() => _MainAppShellState();
}

class _MainAppShellState extends State<MainAppShell> {
  bool _tabletMenuExpanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final mobile = MainResponsiveBreakpoints.isMobile(width);
        final tablet = MainResponsiveBreakpoints.isTablet(width);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: PreferredSize(
            preferredSize: Size.fromHeight(mobile ? 72 : 56),
            child: CustomAppBar(
              controller: widget.controller,
              onDestinationSelected: widget.onDestinationSelected,
              onLogoTap: tablet
                  ? () => setState(() => _tabletMenuExpanded = !_tabletMenuExpanded)
                  : null,
            ),
          ),
          drawer: mobile ? widget.mobileDrawer : null,
          body: mobile
              ? _buildMobileBody()
              : tablet
                  ? _buildTabletBody()
                  : _buildDesktopBody(width),
        );
      },
    );
  }

  Widget _buildMobileBody() {
    return Stack(
      children: [
        Positioned.fill(
          child: _listenToChild(widget.child),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 250),
            offset: widget.bottomNavigationVisible
                ? Offset.zero
                : const Offset(0, 1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 250),
              opacity: widget.bottomNavigationVisible ? 1 : 0,
              child: widget.mobileBottomNavigation,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTabletBody() {
    return Stack(
      children: [
        Row(
          children: [
            SizedBox(
              width: MainResponsiveBreakpoints.tabletRailWidth,
              child: widget.tabletRail,
            ),
            Expanded(child: _listenToChild(widget.child)),
          ],
        ),
        if (_tabletMenuExpanded) ...[
          Positioned.fill(
            child: GestureDetector(
              onTap: () => setState(() => _tabletMenuExpanded = false),
              child: ColoredBox(color: Colors.black.withValues(alpha: .48)),
            ),
          ),
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            child: SizedBox(
              width: MainResponsiveBreakpoints.desktopSidebarWidth,
              child: Material(
                elevation: 18,
                child: widget.desktopSidebar,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildDesktopBody(double width) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: MainResponsiveBreakpoints.desktopSidebarWidth,
          child: widget.desktopSidebar,
        ),
        Expanded(child: _listenToChild(widget.child)),
        if (MainResponsiveBreakpoints.showRightSidebar(width) &&
            widget.rightSidebar != null)
          SizedBox(
            width: MainResponsiveBreakpoints.rightSidebarWidth,
            child: widget.rightSidebar,
          ),
      ],
    );
  }

  Widget _listenToChild(Widget child) {
    final listener = widget.onScrollNotification;
    if (listener == null) return child;
    return NotificationListener<ScrollNotification>(
      onNotification: listener,
      child: child,
    );
  }
}
