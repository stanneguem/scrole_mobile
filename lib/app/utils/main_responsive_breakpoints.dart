/// Breakpoints communs aux layouts de navigation et du fil Scrole.
abstract final class MainResponsiveBreakpoints {
  static const double mobileMaxWidth = 600;
  static const double tabletMaxWidth = 1024;
  static const double wideSidebarMinWidth = 1280;

  static const double tabletRailWidth = 72;
  static const double desktopSidebarWidth = 320;
  static const double rightSidebarWidth = 320;
  static const double desktopFeedMaxWidth = 680;
  static const double tabletFeedMaxWidth = 640;

  static bool isMobile(double width) => width < mobileMaxWidth;
  static bool isTablet(double width) =>
      width >= mobileMaxWidth && width < tabletMaxWidth;
  static bool isDesktop(double width) => width >= tabletMaxWidth;
  static bool showRightSidebar(double width) =>
      width >= wideSidebarMinWidth;
}
