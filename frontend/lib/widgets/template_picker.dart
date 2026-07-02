import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/template_providers.dart';

/// A bottom sheet that displays prompt templates grouped by category.
///
/// Shows an [ExpansionTile] per category, each containing [ListTile]s for
/// every template in that category. Tapping a template pops the sheet and
/// returns the template body to the caller via [Navigator.pop].
///
/// Usage:
/// ```dart
/// final body = await showModalBottomSheet<String>(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => const TemplatePicker(),
/// );
/// if (body != null) { /* populate prompt field */ }
/// ```
class TemplatePicker extends ConsumerWidget {
  const TemplatePicker({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(templatesProvider);
    final theme = Theme.of(context);

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag handle + header
            _BottomSheetHeader(theme: theme),
            // Body
            Expanded(
              child: async.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (err, _) => _ErrorState(message: err.toString()),
                data: (response) {
                  if (response.categories.isEmpty) {
                    return const _EmptyState();
                  }
                  return ListView.builder(
                    controller: scrollController,
                    itemCount: response.categories.length,
                    itemBuilder: (context, index) {
                      final category = response.categories[index];
                      return ExpansionTile(
                        title: Text(
                          category.category,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        // Expand the first category by default for quick access
                        initiallyExpanded: index == 0,
                        children: category.templates.map((template) {
                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 2,
                            ),
                            leading: const Icon(
                              Icons.article_outlined,
                              size: 20,
                            ),
                            title: Text(template.title),
                            onTap: () => Navigator.of(context).pop(template.body),
                          );
                        }).toList(),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

class _BottomSheetHeader extends StatelessWidget {
  const _BottomSheetHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drag handle
        Center(
          child: Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 8),
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withAlpha(80),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded),
              const SizedBox(width: 8),
              Text(
                'Prompt Templates',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
                tooltip: 'Close',
              ),
            ],
          ),
        ),
        Divider(
          height: 1,
          color: theme.colorScheme.outlineVariant,
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Failed to load templates',
              style: TextStyle(color: colorScheme.error),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 48),
          SizedBox(height: 12),
          Text('No templates available'),
        ],
      ),
    );
  }
}
