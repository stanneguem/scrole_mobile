import 'package:flutter/material.dart';

/// Non-web fallback. Mobile platforms keep using webview_flutter.
class WebViewIframe extends StatelessWidget {
  final String url;

  const WebViewIframe({super.key, required this.url});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Text('Le navigateur intégré Web est disponible sur le Web.'),
    );
  }
}
