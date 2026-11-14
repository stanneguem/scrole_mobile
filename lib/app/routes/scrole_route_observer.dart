import 'package:flutter/widgets.dart';

/// Shared route observer used by media previews that must stop when covered
/// by another page, even while their widget remains mounted in the navigator.
final RouteObserver<PageRoute<dynamic>> scroleRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
