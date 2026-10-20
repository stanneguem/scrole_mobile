import 'package:flutter/material.dart';
import 'package:get/get.dart';

class CommunityPollComposerScreen extends StatefulWidget {
  const CommunityPollComposerScreen({super.key});

  @override
  State<CommunityPollComposerScreen> createState() => _CommunityPollComposerScreenState();
}

class _CommunityPollComposerScreenState extends State<CommunityPollComposerScreen> {
  final _optionControllers = <TextEditingController>[
    TextEditingController(),
    TextEditingController(),
  ];
  final _explanationController = TextEditingController();
  String _kind = 'single';
  int _durationHours = 24;
  int? _correctIndex;
  bool _saving = false;

  bool get _isQuiz => _kind == 'quiz';
  bool get _isThisOrThat => _kind == 'this_or_that';

  @override
  void dispose() {
    for (final controller in _optionControllers) {
      controller.dispose();
    }
    _explanationController.dispose();
    super.dispose();
  }

  void _addOption() {
    if (_optionControllers.length >= 6) return;
    setState(() => _optionControllers.add(TextEditingController()));
  }

  void _removeOption(int index) {
    if (_optionControllers.length <= 2) return;
    final controller = _optionControllers.removeAt(index);
    controller.dispose();
    if (_correctIndex == index) {
      _correctIndex = null;
    } else if (_correctIndex != null && _correctIndex! > index) {
      _correctIndex = _correctIndex! - 1;
    }
    setState(() {});
  }

  void _submit() {
    if (_saving) return;
    final labels = _optionControllers.map((c) => c.text.trim()).toList();
    if (labels.any((label) => label.isEmpty)) {
      Get.snackbar('Options incomplètes', 'Renseigne chaque option ou supprime les champs inutilisés.');
      return;
    }
    if (labels.toSet().length != labels.length) {
      Get.snackbar('Options en double', 'Chaque option doit être différente.');
      return;
    }
    if (_isQuiz && _correctIndex == null) {
      Get.snackbar('Bonne réponse requise', 'Choisis la bonne réponse du quiz.');
      return;
    }

    setState(() => _saving = true);
    final poll = <String, dynamic>{
      'kind': _kind,
      'options': [
        for (var i = 0; i < labels.length; i++)
          {'label': labels[i], 'is_correct': _isQuiz && i == _correctIndex},
      ],
      if (!_isQuiz) 'duration_hours': _durationHours,
      if (_isQuiz && _explanationController.text.trim().isNotEmpty)
        'explanation': _explanationController.text.trim(),
    };
    Get.back<Map<String, dynamic>>(result: poll);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Créer une interaction'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _submit,
            child: const Text('Ajouter'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [colors.primary.withValues(alpha: .13), colors.tertiary.withValues(alpha: .08)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: colors.outlineVariant.withValues(alpha: .45)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(color: colors.primary.withValues(alpha: .14), borderRadius: BorderRadius.circular(16)),
                    child: Icon(_isQuiz ? Icons.lightbulb_rounded : Icons.poll_rounded, color: colors.primary, size: 27),
                  ),
                  const SizedBox(height: 14),
                  Text(_isQuiz ? 'Lance un quiz' : 'Fais participer ta communauté',
                    style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                  const SizedBox(height: 5),
                  Text('Ajoute des options claires pour donner envie de répondre.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: colors.onSurfaceVariant)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text('Format', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            _KindTile(
              selected: _kind == 'single',
              icon: Icons.radio_button_checked_rounded,
              title: 'Sondage classique',
              subtitle: 'Une seule réponse par personne',
              onTap: () => setState(() => _kind = 'single'),
            ),
            const SizedBox(height: 8),
            _KindTile(
              selected: _kind == 'multiple',
              icon: Icons.checklist_rounded,
              title: 'Choix multiples',
              subtitle: 'Les participants peuvent choisir plusieurs options',
              onTap: () => setState(() => _kind = 'multiple'),
            ),
            const SizedBox(height: 8),
            _KindTile(
              selected: _kind == 'quiz',
              icon: Icons.quiz_rounded,
              title: 'Quiz',
              subtitle: 'Définis une bonne réponse et une explication facultative',
              onTap: () => setState(() => _kind = 'quiz'),
            ),
            const SizedBox(height: 8),
            _KindTile(
              selected: _isThisOrThat,
              icon: Icons.compare_arrows_rounded,
              title: 'Tu préfères…',
              subtitle: 'Un choix rapide entre deux possibilités',
              onTap: () {
                setState(() {
                  _kind = 'this_or_that';
                  while (_optionControllers.length > 2) {
                    _optionControllers.removeLast().dispose();
                  }
                });
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(child: Text('Options', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                Text('${_optionControllers.length}/${_isThisOrThat ? 2 : 6}',
                  style: theme.textTheme.labelLarge?.copyWith(color: colors.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 10),
            ..._optionControllers.asMap().entries.map((entry) {
              final index = entry.key;
              final controller = entry.value;
              final correct = _isQuiz && _correctIndex == index;
              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    if (_isQuiz)
                      IconButton(
                        tooltip: 'Définir comme bonne réponse',
                        onPressed: () => setState(() => _correctIndex = index),
                        icon: Icon(correct ? Icons.check_circle_rounded : Icons.circle_outlined,
                          color: correct ? Colors.green : colors.outline, size: 23),
                      )
                    else
                      Container(
                        width: 38,
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(color: colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(13)),
                        child: Text('${index + 1}', style: TextStyle(color: colors.onSurfaceVariant, fontWeight: FontWeight.bold)),
                      ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: controller,
                        textCapitalization: TextCapitalization.sentences,
                        maxLength: 120,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: 'Option ${index + 1}',
                          filled: true,
                          fillColor: colors.surfaceContainerLow,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.outlineVariant)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: colors.outlineVariant)),
                        ),
                      ),
                    ),
                    if (_optionControllers.length > 2)
                      IconButton(onPressed: () => _removeOption(index), icon: const Icon(Icons.close_rounded), tooltip: 'Supprimer'),
                  ],
                ),
              );
            }),
            if (!_isThisOrThat && _optionControllers.length < 6)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Ajouter une option'),
                  style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                ),
              ),
            if (_isQuiz) ...[
              const SizedBox(height: 18),
              Text('Explication (facultatif)', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              TextField(
                controller: _explanationController,
                maxLines: 3,
                maxLength: 500,
                decoration: InputDecoration(
                  hintText: 'Explique pourquoi cette réponse est correcte…',
                  filled: true,
                  fillColor: colors.surfaceContainerLow,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
            ] else ...[
              const SizedBox(height: 20),
              Text('Durée', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final hours in [1, 6, 12, 24, 48, 72, 168])
                    ChoiceChip(
                      label: Text(hours == 168 ? '7 jours' : hours < 24 ? '${hours} h' : '${hours ~/ 24} j'),
                      selected: _durationHours == hours,
                      onSelected: (_) => setState(() => _durationHours = hours),
                    ),
                ],
              ),
            ],
            if (_isQuiz) ...[
              const SizedBox(height: 10),
              Text('Un quiz reste disponible sans date d’expiration.', style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            ],
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Ajouter à la publication'),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
            ),
          ],
        ),
      ),
    );
  }
}

class _KindTile extends StatelessWidget {
  const _KindTile({required this.selected, required this.icon, required this.title, required this.subtitle, required this.onTap});

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: selected ? colors.primary.withValues(alpha: .09) : colors.surface,
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: selected ? colors.primary : colors.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: selected ? colors.primary.withValues(alpha: .15) : colors.surfaceContainerHighest, borderRadius: BorderRadius.circular(13)),
                child: Icon(icon, color: selected ? colors.primary : colors.onSurfaceVariant),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 12, color: colors.onSurfaceVariant)),
              ])),
              if (selected) Icon(Icons.check_circle_rounded, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
