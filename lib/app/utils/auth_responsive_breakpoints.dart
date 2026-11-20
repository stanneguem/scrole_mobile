import 'package:flutter/widgets.dart';

/// Breakpoints dédiés à l'écran d'authentification Scrole.
/// Les seuils sont centralisés ici pour éviter les largeurs dispersées dans l'UI.
abstract final class AuthResponsiveBreakpoints {
  static const double mobileMaxWidth = 600;
  static const double tabletLandscapeMinWidth = 900;
  static const double desktopMinWidth = 1024;
  static const double contentMaxWidth = 1180;
  static const double authCardMaxWidth = 480;
  static const double loginPanelMaxWidth = 400;

  static bool isMobile(double width) => width < mobileMaxWidth;

  static bool isTabletLandscape(double width, Orientation orientation) =>
      width >= tabletLandscapeMinWidth &&
      width < desktopMinWidth &&
      orientation == Orientation.landscape;

  static bool isTwoColumn(double width, Orientation orientation) =>
      width >= desktopMinWidth || isTabletLandscape(width, orientation);
}
