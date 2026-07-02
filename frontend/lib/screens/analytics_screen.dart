import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics_models.dart';
import '../providers/analytics_providers.dart';
import '../providers/playground_providers.dart';

// ---------------------------------------------------------------------------
// Date helpers
// ---------------------------------------------------------------------------

/// Month abbreviations for display formatting.
const _kMonthAbbr = [
  '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// Formats a [DateTime] as `"Jan 5, 2024"` for display in the UI.
String _formatDateDisplay(DateTime date) {
  return '${_kMonthAbbr[date.month]} ${date.day}, ${date.year}';
}

/// Formats an integer with comma separators, e.g. `25000` → `"25,000"`.
String _formatTokens(int tokens) {
  final s = tokens.toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return buf.toString();
}

/// Formats a cost as `"$0.1234"` (4 decimal places).
String _formatCost(double cost) {
  return '\$${cost.toStringAsFixed(4)}';
}

// ---------------------------------------------------------------------------
// AnalyticsScreen
// ---------------------------------------------------------------------------

/// Displays aggregated cost and token analytics for the authenticated user.
///
/// Requirements covered:
///   - Req 7 AC1: total request count across all models
///   - Req 7 AC2: total token count per model
///   - Req 7 AC3: total estimated cost per model
///   - Req 7 AC5: date range filter (start + end date)
///   - Req 7 AC6: zero-state when no data exists
class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateRange = ref.watch(analyticsDateRangeProvider);
    final args = AnalyticsArgs(
      startDate: dateRange.startDate,
      endDate: dateRange.endDate,
    );
    final asyncAnalytics = ref.watch(analyticsProvider(args));

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Date range picker row
          _DateRangeRow(dateRange: dateRange),
          const Divider(height: 1),

          // Analytics content
          Expanded(
            child: asyncAnalytics.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _ErrorState(
                error: error.toString(),
                onRetry: () =>
                    ref.invalidate(analyticsProvider(args)),
              ),
              data: (analytics) => analytics.totalRequests == 0
                  ? const _ZeroState()
                  : _AnalyticsContent(analytics: analytics),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Date range picker row
// ---------------------------------------------------------------------------

class _DateRangeRow extends ConsumerWidget {
  const _DateRangeRow({required this.dateRange});

  final AnalyticsDateRange dateRange;

  Future<void> _pickStart(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateRange.startDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: dateRange.endDate ?? DateTime.now(),
      helpText: 'Select start date',
    );
    if (picked != null) {
      ref.read(analyticsDateRangeProvider.notifier).setStartDate(picked);
    }
  }

  Future<void> _pickEnd(BuildContext context, WidgetRef ref) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateRange.endDate ?? DateTime.now(),
      firstDate: dateRange.startDate ?? DateTime(2020),
      lastDate: DateTime.now(),
      helpText: 'Select end date',
    );
    if (picked != null) {
      ref.read(analyticsDateRangeProvider.notifier).setEndDate(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final hasRange =
        dateRange.startDate != null || dateRange.endDate != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(Icons.date_range_outlined, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                // Start date chip
                ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 14),
                  label: Text(
                    dateRange.startDate != null
                        ? _formatDateDisplay(dateRange.startDate!)
                        : 'Start date',
                    style: theme.textTheme.bodySmall,
                  ),
                  onPressed: () => _pickStart(context, ref),
                ),
                // End date chip
                ActionChip(
                  avatar: const Icon(Icons.calendar_today, size: 14),
                  label: Text(
                    dateRange.endDate != null
                        ? _formatDateDisplay(dateRange.endDate!)
                        : 'End date',
                    style: theme.textTheme.bodySmall,
                  ),
                  onPressed: () => _pickEnd(context, ref),
                ),
              ],
            ),
          ),
          // Clear button — shown only when a range is set
          if (hasRange)
            TextButton.icon(
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('All time'),
              onPressed: () =>
                  ref.read(analyticsDateRangeProvider.notifier).clearRange(),
            )
          else
            Text(
              'All time',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics content
// ---------------------------------------------------------------------------

class _AnalyticsContent extends StatelessWidget {
  const _AnalyticsContent({required this.analytics});

  final AnalyticsResponse analytics;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary card — total requests
        _SummaryCard(totalRequests: analytics.totalRequests),
        const SizedBox(height: 16),

        // Per-model section header
        Text(
          'Per-model breakdown',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),

        // Per-model cards
        ...analytics.perModel.map(
          (stats) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ModelStatsCard(stats: stats),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Summary card
// ---------------------------------------------------------------------------

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.totalRequests});

  final int totalRequests;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              Icons.query_stats,
              size: 36,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Requests',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  '$totalRequests',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Per-model stats card
// ---------------------------------------------------------------------------

class _ModelStatsCard extends StatelessWidget {
  const _ModelStatsCard({required this.stats});

  final PerModelStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Resolve display name from the playground catalogue; fall back to raw ID.
    final displayName =
        kModelDisplayNames[stats.model] ?? stats.model;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Model name header
            Row(
              children: [
                const Icon(Icons.smart_toy_outlined, size: 20),
                const SizedBox(width: 8),
                Text(
                  displayName,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),

            // Stats rows
            _StatRow(
              icon: Icons.send_outlined,
              label: 'Requests',
              value: '${stats.requestCount}',
            ),
            const SizedBox(height: 8),
            _StatRow(
              icon: Icons.token_outlined,
              label: 'Total tokens',
              value: _formatTokens(stats.totalTokens),
            ),
            const SizedBox(height: 8),
            _StatRow(
              icon: Icons.attach_money,
              label: 'Estimated cost',
              value: _formatCost(stats.totalCost),
              valueStyle: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Stat row widget
// ---------------------------------------------------------------------------

class _StatRow extends StatelessWidget {
  const _StatRow({
    required this.icon,
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final IconData icon;
  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: valueStyle ?? theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Zero-state
// ---------------------------------------------------------------------------

class _ZeroState extends StatelessWidget {
  const _ZeroState();

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
              Icons.bar_chart_outlined,
              size: 64,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              'No activity for this period',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Try selecting a different date range or submit some prompts to get started.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
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
// Error state
// ---------------------------------------------------------------------------

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.error, required this.onRetry});

  final String error;
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
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load analytics',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              onPressed: onRetry,
            ),
          ],
        ),
      ),
    );
  }
}
