import 'package:flutter/material.dart';

/// Définition unique des destinations de navigation principales.
class MainNavigationItem {
  const MainNavigationItem({
    required this.index,
    required this.label,
    this.svgAsset,
    this.icon,
  });

  final int index;
  final String label;
  final String? svgAsset;
  final IconData? icon;
}

abstract final class MainNavigationItems {
  static const List<MainNavigationItem> all = [
    MainNavigationItem(index: 0, label: 'nav_home', svgAsset: 'assets/svg_icons/japan-svgrepo-com.svg'),
    MainNavigationItem(index: 1, label: 'Communautés', svgAsset: 'assets/svg_icons/discussion.svg'),
    MainNavigationItem(index: 2, label: 'Réels', icon: Icons.video_library_outlined),
    MainNavigationItem(index: 3, label: 'nav_events', svgAsset: 'assets/svg_icons/event-promotion-sale-svgrepo-com.svg'),
    MainNavigationItem(index: 4, label: 'Notifications', svgAsset: 'assets/svg_icons/notification-svgrepo-com.svg'),
    MainNavigationItem(index: 5, label: 'nav_profile', icon: Icons.person_outline_rounded),
  ];

  static List<MainNavigationItem> get topBar =>
      all.where((item) => item.index < 5).toList(growable: false);
}
