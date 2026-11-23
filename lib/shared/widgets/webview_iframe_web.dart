import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

/// Browser-native iframe used only by Flutter Web.
///
/// External sites may opt out of iframe embedding through their own
/// X-Frame-Options or Content-Security-Policy headers; those restrictions
/// are intentionally respected.
class WebViewIframe extends StatefulWidget {
  final String url;

  const WebViewIframe({super.key, required this.url});

  @override
  State<WebViewIframe> createState() => _WebViewIframeState();
}

class _WebViewIframeState extends State<WebViewIframe> {
  static const String _viewType = 'scrole-external-webview';
  static bool _registered = false;

  @override
  void initState() {
    super.initState();
    _registerFactory();
  }

  void _registerFactory() {
    if (_registered) return;
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      final frame = html.IFrameElement()
        ..src = widget.url
        ..title = 'Page web externe'
        ..allow = 'clipboard-read; clipboard-write; fullscreen'
        ..allowFullscreen = true
        ..setAttribute('loading', 'eager')
        ..setAttribute('referrerpolicy', 'strict-origin-when-cross-origin');

      frame.style
        ..border = '0'
        ..width = '100%'
        ..height = '100%'
        ..display = 'block'
        ..backgroundColor = 'transparent';

      return frame;
    });
    _registered = true;
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand(
      child: HtmlElementView(viewType: _viewType),
    );
  }
}
