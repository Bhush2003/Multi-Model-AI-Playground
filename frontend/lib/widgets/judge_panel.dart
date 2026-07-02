import 'package:flutter/material.dart';

import '../models/judge_models.dart';
import '../providers/playground_providers.dart';

// ---------------------------------------------------------------------------
// JudgePanel — Req 12 AC3 / AC4
// ---------------------------------------------------------------------------

/// Displays an AI Judge evaluation result, including:
/// - A winner header with a trophy icon.
/// - A ranked list of models with score bars and reasoning text.
///
/// Requirement 12 AC3, AC4.
class JudgePanel extends StatelessWidget {
  const JudgePanel({super.key, required this.result});

  final JudgeResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final winnerDisplay =
        kModelDisplayNames[result.winner] ?? result.winner;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Header -------------------------------------------------------
            Row(
              children: [
                const Icon(
                  Icons.psychology_alt_rounded,
                  size: 18,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 6),
                Text(
                  'AI Judge Evaluation',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ---- Winner row ---------------------------------------------------
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade300),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.amber.shade700,
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Winner',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.amber.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          winnerDisplay,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---- Ranked model list -------------------------------------------
            ...result.rankedModels.asMap().entries.map((entry) {
              final rank = entry.key + 1;
              final item = entry.value;
              return _ModelScoreRow(rank: rank, item: item);
            }),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _ModelScoreRow
// ---------------------------------------------------------------------------

class _ModelScoreRow extends StatelessWidget {
  const _ModelScoreRow({required this.rank, required this.item});

  final int rank;
  final JudgeModelScore item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final displayName = kModelDisplayNames[item.model] ?? item.model;
    final scoreValue = item.score.clamp(0, 100);
    final isWinner = rank == 1;

    // Choose progress bar color based on score
    final barColor = scoreValue >= 80
        ? Colors.green.shade500
        : scoreValue >= 60
            ? Colors.blue.shade400
            : Colors.orange.shade400;

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Model name + rank badge + score
          Row(
            children: [
              // Rank badge
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isWinner
                      ? Colors.amber.shade600
                      : colorScheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$rank',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isWinner ? Colors.white : colorScheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // Score chip
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$scoreValue/100',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: scoreValue / 100,
              minHeight: 6,
              backgroundColor: colorScheme.surfaceContainerHigh,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 6),

          // Reasoning text
          Text(
            item.reasoning,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),

          // Divider between models (except last)
          const SizedBox(height: 4),
          Divider(height: 1, color: colorScheme.outlineVariant),
        ],
      ),
    );
  }
}
