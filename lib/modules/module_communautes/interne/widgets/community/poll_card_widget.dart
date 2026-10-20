import 'package:flutter/material.dart';
import 'package:scrole/app/theme/app_colors.dart';

class PollCardWidget extends StatefulWidget {
  final dynamic poll;
  final String postId;
  final dynamic controller;

  const PollCardWidget({
    super.key,
    required this.poll,
    required this.postId,
    required this.controller,
  });

  @override
  State<PollCardWidget> createState() => _PollCardWidgetState();
}

class _PollCardWidgetState extends State<PollCardWidget> {
  List<String> _selectedOptionIds = [];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final pollMap = widget.poll is Map ? Map<String, dynamic>.from(widget.poll) : {};
    final options = pollMap['options'] is List ? (pollMap['options'] as List) : [];
    final kind = pollMap['kind']?.toString() ?? 'single';
    final isMultiple = kind == 'multiple';

    if (options.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.poll_rounded, size: 18, color: AppColors.primary),
              const SizedBox(width: 8),
              Text(
                'Sondage (${isMultiple ? "Choix multiples" : "Choix unique"})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.primary),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...options.asMap().entries.map((entry) {
            final idx = entry.key;
            final opt = entry.value.toString();
            final isSelected = _selectedOptionIds.contains(idx.toString()) || _selectedOptionIds.contains(opt);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: InkWell(
                onTap: () {
                  setState(() {
                    final key = idx.toString();
                    if (isMultiple) {
                      if (_selectedOptionIds.contains(key)) {
                        _selectedOptionIds.remove(key);
                      } else {
                        _selectedOptionIds.add(key);
                      }
                    } else {
                      _selectedOptionIds = [key];
                    }
                  });
                },
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.primary.withValues(alpha: 0.15) : colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected ? AppColors.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        isSelected
                            ? (isMultiple ? Icons.check_box_rounded : Icons.radio_button_checked_rounded)
                            : (isMultiple ? Icons.check_box_outline_blank_rounded : Icons.radio_button_off_rounded),
                        size: 18,
                        color: isSelected ? AppColors.primary : colorScheme.outline,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          opt,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}
