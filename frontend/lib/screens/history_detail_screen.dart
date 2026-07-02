import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_models.dart';
import '../models/prompt_result.dart';
import '../providers/history_providers.dart';
import '../providers/judge_providers.dart';
import '../providers/playground_providers.dart';
import '../providers/rating_providers.dart';
import '../widgets/judge_panel.dart';

// ---------------------------------------------------------------------------
// Timestamp formatter (shared logic, duplicated here to avoid coupling)
// ---------------------------------------------------------------------------

String _formatTimestamp(DateTime dt) {
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

String _formatLatency(int ms) {
  if (ms < 1000) return '$ms ms';
  return '${(ms / 1000).toStringAsFixed(2)} s';
}

// ---------------------------------------------------------------------------
// HistoryDetailScreen
// ---------------------------------------------------------------------------

/// Displays the full prompt text and all stored model responses for a
/// historical prompt. Provides a "Resubmit" button that posts to
/// POST /api/v1/prompts/:id/resubmit using the currently selected models.
///
/// Requirement 6 AC2, AC3.
class HistoryDetailScreen extends ConsumerStatefulWidget {
  const HistoryDetailScreen({super.key, required this.promptId});

  final String promptId;

  @override
  ConsumerState<HistoryDetailScreen> createState() =>
      _HistoryDetailScreenState();
}

class _HistoryDetailScreenState extends ConsumerState<HistoryDetailScreen> {
  ResubmitArgs? _activeResubmitArgs;

  void _onResubmit(HistoryDetailResponse detail) {
    final selectedModels =
        ref.read(selectedModelsProvider).toList();
    if (selectedModels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select at least one model on the Playground tab.'),
        ),
      );
      return;
    }
    setState(() {
      _activeResubmitArgs = ResubmitArgs(
        promptId: widget.promptId,
        models: selectedModels,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final asyncDetail = ref.watch(historyDetailProvider(widget.promptId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Prompt Detail'),
      ),
      body: asyncDetail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorBody(
          message: err.toString(),
          onRetry: () =>
              ref.invalidate(historyDetailProvider(widget.promptId)),
        ),
        data: (detail) => _DetailBody(
          detail: detail,
          promptId: widget.promptId,
          activeResubmitArgs: _activeResubmitArgs,
          onResubmit: () => _onResubmit(detail),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DetailBody
// ---------------------------------------------------------------------------

class _DetailBody extends ConsumerWidget {
  const _DetailBody({
    required this.detail,
    required this.promptId,
    required this.activeResubmitArgs,
    required this.onResubmit,
  });

  final HistoryDetailResponse detail;
  final String promptId;
  final ResubmitArgs? activeResubmitArgs;
  final VoidCallback onResubmit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    // Watch the resubmit async state when a request is in flight
    final asyncResubmit = activeResubmitArgs != null
        ? ref.watch(resubmitProvider(activeResubmitArgs!))
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ---- Prompt section -----------------------------------------------
        _SectionHeader(label: 'Prompt'),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  detail.prompt,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  _formatTimestamp(detail.createdAt),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),

        // ---- Resubmit button & results ------------------------------------
        _ResubmitSection(
          asyncResubmit: asyncResubmit,
          onResubmit: onResubmit,
        ),
        const SizedBox(height: 20),

        // ---- Stored responses ---------------------------------------------
        _SectionHeader(label: 'Stored Responses (${detail.responses.length})'),
        const SizedBox(height: 8),
        if (detail.responses.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                'No responses stored for this prompt.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          )
        else
          ...detail.responses.map(
            (r) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _HistoryResponseCard(item: r),
            ),
          ),

        const SizedBox(height: 20),

        // ---- AI Judge evaluation (Req 12 AC6) --------------------------------
        _HistoryJudgeSection(promptId: promptId),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _HistoryJudgeSection — Req 12 AC6
// ---------------------------------------------------------------------------

/// Watches [judgeHistoryProvider] for a saved AI evaluation and renders
/// [JudgePanel] if one exists, or a subtle "no evaluation" message.
class _HistoryJudgeSection extends ConsumerWidget {
  const _HistoryJudgeSection({required this.promptId});

  final String promptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final judgeAsync = ref.watch(judgeHistoryProvider(promptId));

    return judgeAsync.when(
      loading: () => const LinearProgressIndicator(),
      error: (_, err) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          'No AI evaluation for this prompt.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontStyle: FontStyle.italic,
          ),
        ),
      ),
      data: (result) {
        if (result == null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'No AI evaluation for this prompt.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontStyle: FontStyle.italic,
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(label: 'AI Judge Evaluation'),
            const SizedBox(height: 8),
            JudgePanel(result: result),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// _ResubmitSection
// ---------------------------------------------------------------------------

class _ResubmitSection extends StatelessWidget {
  const _ResubmitSection({
    required this.asyncResubmit,
    required this.onResubmit,
  });

  final AsyncValue<PromptSubmitResponse>? asyncResubmit;
  final VoidCallback onResubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final isLoading = asyncResubmit is AsyncLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Resubmit button
        FilledButton.icon(
          onPressed: isLoading ? null : onResubmit,
          icon: isLoading
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.onPrimary,
                  ),
                )
              : const Icon(Icons.replay_rounded),
          label: Text(isLoading ? 'Resubmitting…' : 'Resubmit'),
        ),

        // Resubmit results
        if (asyncResubmit != null) ...[
          const SizedBox(height: 16),
          asyncResubmit!.when(
            loading: () => const SizedBox.shrink(),
            error: (err, _) => _InlineError(message: err.toString()),
            data: (result) => _ResubmitResults(response: result),
          ),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ResubmitResults
// ---------------------------------------------------------------------------

class _ResubmitResults extends StatelessWidget {
  const _ResubmitResults({required this.response});

  final PromptSubmitResponse response;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'Resubmit Results'),
        const SizedBox(height: 8),
        ...response.results.map((r) {
          final displayName =
              kModelDisplayNames[r.model] ?? r.model;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Card(
              elevation: 1,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: r.hasError
                      ? theme.colorScheme.error
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (r.latencyMs != null && !r.hasError)
                          _Badge(
                            label: _formatLatencyFromMs(r.latencyMs!),
                            color: theme.colorScheme.secondaryContainer,
                            textColor: theme.colorScheme.onSecondaryContainer,
                          ),
                      ],
                    ),
                    const Divider(height: 16),
                    if (r.hasError)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline_rounded,
                              color: theme.colorScheme.error, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              r.error ?? 'Unknown error',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      MarkdownBody(
                        data: r.response ?? 'No response.',
                        styleSheet:
                            MarkdownStyleSheet.fromTheme(Theme.of(context)),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  String _formatLatencyFromMs(int ms) {
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(2)} s';
  }
}

// ---------------------------------------------------------------------------
// _HistoryResponseCard
// ---------------------------------------------------------------------------

/// A compact card displaying a stored [HistoryResponseItem] with active
/// rating controls (Requirement 9 AC1, AC3, AC4).
class _HistoryResponseCard extends ConsumerStatefulWidget {
  const _HistoryResponseCard({required this.item});

  final HistoryResponseItem item;

  @override
  ConsumerState<_HistoryResponseCard> createState() =>
      _HistoryResponseCardState();
}

class _HistoryResponseCardState extends ConsumerState<_HistoryResponseCard> {
  late int _accuracy;
  late int _clarity;
  late int _helpfulness;

  RatingArgs? _submittedArgs;
  bool _showSavedMessage = false;

  @override
  void initState() {
    super.initState();
    _initFromRating(widget.item.rating);
  }

  void _initFromRating(RatingData? rating) {
    _accuracy = rating?.accuracy ?? 0;
    _clarity = rating?.clarity ?? 0;
    _helpfulness = rating?.helpfulness ?? 0;
  }

  bool get _canSubmit =>
      _accuracy >= 1 &&
      _accuracy <= 5 &&
      _clarity >= 1 &&
      _clarity <= 5 &&
      _helpfulness >= 1 &&
      _helpfulness <= 5;

  void _onSubmit() {
    if (!_canSubmit) return;
    final args = RatingArgs(
      responseId: widget.item.id,
      accuracy: _accuracy,
      clarity: _clarity,
      helpfulness: _helpfulness,
    );
    setState(() {
      _submittedArgs = args;
      _showSavedMessage = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayName = kModelDisplayNames[widget.item.modelName] ?? widget.item.modelName;

    // Watch the rating submit state when in-flight
    final asyncRating = _submittedArgs != null
        ? ref.watch(submitRatingProvider(_submittedArgs!))
        : null;

    if (asyncRating is AsyncData<RatingResult> && !_showSavedMessage) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _showSavedMessage = true);
      });
    }

    final isSubmitting = asyncRating is AsyncLoading;
    final submitError = asyncRating is AsyncError
        ? (asyncRating as AsyncError).error.toString()
        : null;

    return Card(
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.item.hasError
              ? theme.colorScheme.error
              : theme.colorScheme.outlineVariant,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    displayName,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (widget.item.latencyMs != null && !widget.item.hasError)
                  _Badge(
                    label: _formatLatency(widget.item.latencyMs!),
                    color: theme.colorScheme.secondaryContainer,
                    textColor: theme.colorScheme.onSecondaryContainer,
                  ),
                if (widget.item.tokenCount != null && !widget.item.hasError) ...[
                  const SizedBox(width: 6),
                  _Badge(
                    label: '${widget.item.tokenCount} tok',
                    color: theme.colorScheme.tertiaryContainer,
                    textColor: theme.colorScheme.onTertiaryContainer,
                  ),
                ],
              ],
            ),
            const Divider(height: 16),

            // Body
            if (widget.item.hasError)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      color: theme.colorScheme.error, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.item.error ?? 'Unknown error',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              )
            else
              MarkdownBody(
                data: widget.item.response ?? 'No response.',
                styleSheet: MarkdownStyleSheet.fromTheme(theme),
              ),

            // Rating controls (Req 9 AC1, AC3, AC4)
            if (!widget.item.hasError) ...[
              const SizedBox(height: 12),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 10),
              // Section label
              Row(
                children: [
                  Icon(
                    Icons.star_half_rounded,
                    size: 15,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _showSavedMessage ? 'Rating saved ✓' : 'Rate this response',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: _showSavedMessage
                          ? Colors.green.shade700
                          : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _HistoryStarRow(
                label: 'Accuracy',
                value: _accuracy,
                onChanged: (v) => setState(() => _accuracy = v),
              ),
              const SizedBox(height: 5),
              _HistoryStarRow(
                label: 'Clarity',
                value: _clarity,
                onChanged: (v) => setState(() => _clarity = v),
              ),
              const SizedBox(height: 5),
              _HistoryStarRow(
                label: 'Helpfulness',
                value: _helpfulness,
                onChanged: (v) => setState(() => _helpfulness = v),
              ),
              const SizedBox(height: 10),
              // Submit button + optional error
              Row(
                children: [
                  if (submitError != null)
                    Expanded(
                      child: Text(
                        submitError,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  else
                    const Spacer(),
                  FilledButton.tonal(
                    onPressed: (isSubmitting || !_canSubmit) ? null : _onSubmit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(80, 32),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 6),
                      textStyle: theme.textTheme.labelSmall,
                    ),
                    child: isSubmitting
                        ? SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: theme.colorScheme.onSecondaryContainer,
                            ),
                          )
                        : const Text('Submit Rating'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HistoryStarRow — star row for the history detail card
// ---------------------------------------------------------------------------

class _HistoryStarRow extends StatelessWidget {
  const _HistoryStarRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// 0 = unset, 1–5 = selected.
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Row(
      children: [
        SizedBox(
          width: 88,
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (int i = 1; i <= 5; i++)
          GestureDetector(
            onTap: () => onChanged(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                i <= value ? Icons.star_rounded : Icons.star_border_rounded,
                size: 22,
                color: i <= value
                    ? Colors.amber.shade600
                    : colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable badge widget
// ---------------------------------------------------------------------------

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
    required this.textColor,
  });

  final String label;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _SectionHeader
// ---------------------------------------------------------------------------

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
    );
  }
}

// ---------------------------------------------------------------------------
// _InlineError
// ---------------------------------------------------------------------------

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(Icons.error_outline_rounded, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'Resubmit failed: $message',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.error),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _ErrorBody
// ---------------------------------------------------------------------------

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onRetry});

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
            Text('Failed to load prompt', style: theme.textTheme.titleMedium),
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
