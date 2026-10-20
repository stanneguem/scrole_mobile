import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CommunityPollComposerScreen extends StatelessWidget {
  const CommunityPollComposerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Créer un sondage')),
      body: Center(
        child: ElevatedButton(
          onPressed: () => Get.back(result: {'kind': 'single', 'options': ['Option 1', 'Option 2']}),
          child: const Text('Valider le sondage (Démo)'),
        ),
      ),
    );
  }
}
