import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/playground_providers.dart';

/// A row of checkboxes — one per supported AI model.
///
/// Reads and updates [selectedModelsProvider].  Checking/unchecking a box
/// adds or removes the corresponding model ID from the set.
class ModelSelectorWidget extends ConsumerWidget {
  const ModelSelectorWidget({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selected = ref.watch(selectedModelsProvider);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Models',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 8,
          runSpacing: 0,
          children: kAvailableModels.map((modelId) {
            final isSelected = selected.contains(modelId);
            final displayName = kModelDisplayNames[modelId] ?? modelId;

            return FilterChip(
              label: Text(displayName),
              selected: isSelected,
              onSelected: (_) {
                ref.read(selectedModelsProvider.notifier).toggle(modelId);
              },
              selectedColor:
                  theme.colorScheme.primaryContainer,
              checkmarkColor: theme.colorScheme.onPrimaryContainer,
            );
          }).toList(),
        ),
      ],
    );
  }
}
