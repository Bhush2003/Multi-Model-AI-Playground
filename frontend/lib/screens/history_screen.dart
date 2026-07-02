import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_models.dart';
import '../providers/history_providers.dart';
import 'history_detail_screen.dart';

// ---------------------------------------------------------------------------
// Timestamp formatting helper (no external package needed)
// ---------------------------------------------------------------------------

String _formatTimestamp(DateTime dt) {
  // Convert to local time for display
  final local = dt.toLocal();

  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  final month = months[local.month - 1];
  final day = local.day;
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour < 12 ? 'AM' : 'PM';

  return '$month $day, $hour:$minute $period';
}

// ---------------------------------------------------------------------------
// HistoryScreen
// ---------------------------------------------------------------------------

/// Paginated list of the user's past prompts.
///
/// Each row shows the truncated prompt (≤ 120 chars) and a human-readable
/// timestamp. Tapping navigates to [HistoryDetailScreen].
///
/// Requirement 6 AC1, AC4, AC5.
class HistoryScreen extends ConsumerWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(historyPageProvider);
    final asyncHistory = ref.watch(historyProvider(page));

    return asyncHistory.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => _ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(historyProvider(page)),
      ),
      data: (historyData) => _HistoryListView(
        data: historyData,
        currentPage: page,
        onPageChanged: (newPage) =>
            ref.read(historyPageProvider.notifier).setPage(newPage),
        onRetry: () => ref.invalidate(historyProvider(page)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HistoryListView
// ---------------------------------------------------------------------------

class _HistoryListView extends StatelessWidget {
  const _HistoryListView({
    required this.data,
    required this.currentPage,
    required this.onPageChanged,
    required this.onRetry,
  });

  final HistoryListResponse data;
  final int currentPage;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (data.prompts.isEmpty && currentPage == 1) {
      return const _EmptyState();
    }

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => onRetry(),
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: data.prompts.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final item = data.prompts[index];
                return _HistoryListTile(item: item);
              },
            ),
          ),
        ),
        _PaginationBar(
          currentPage: currentPage,
          hasMore: data.hasMore,
          onPrev: currentPage > 1
              ? () => onPageChanged(currentPage - 1)
              : null,
          onNext: data.hasMore
              ? () => onPageChanged(currentPage + 1)
              : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _HistoryListTile
// ---------------------------------------------------------------------------

class _HistoryListTile extends StatelessWidget {
  const _HistoryListTile({required this.item});

  final PromptHistoryItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Truncate to 120 characters (Req 6 AC4)
    final truncated = item.prompt.length > 120
        ? '${item.prompt.substring(0, 120)}…'
        : item.prompt;

    return InkWell(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => HistoryDetailScreen(promptId: item.id),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              truncated,
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              _formatTimestamp(item.createdAt),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _PaginationBar
// ---------------------------------------------------------------------------

class _PaginationBar extends StatelessWidget {
  const _PaginationBar({
    required this.currentPage,
    required this.hasMore,
    this.onPrev,
    this.onNext,
  });

  final int currentPage;
  final bool hasMore;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton.icon(
            onPressed: onPrev,
            icon: const Icon(Icons.chevron_left),
            label: const Text('Previous'),
          ),
          Text(
            'Page $currentPage',
            style: theme.textTheme.bodySmall,
          ),
          TextButton.icon(
            onPressed: onNext,
            icon: const Icon(Icons.chevron_right),
            label: const Text('Next'),
            iconAlignment: IconAlignment.end,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _EmptyState
// ---------------------------------------------------------------------------

/// Shown when the user has no prior prompts (Req 6 AC5).
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.history_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No prompts yet',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your submitted prompts will appear here.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ErrorView
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(
              'Failed to load history',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
