import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shimmer/shimmer.dart';

import '../models/history_models.dart';
import '../providers/rating_providers.dart';

/// A card displaying a single model's response.
///
/// States:
///   - **Loading** (`isLoading: true`): shimmer skeleton fill
///   - **Error** (`result.hasError`): red border + error text
///   - **Success**: model label, markdown response, latency badge,
///     optional green "Fastest" badge when [isFastest] is true
///
/// Rating section (Requirement 9):
///   - When [responseId] is non-null AND `!isLoading` AND `error == null`,
///     an expandable "Rate this response" section is shown below the content.
///   - Star controls for Accuracy, Clarity, Helpfulness (1–5 each).
///   - Pre-populated from [initialRating] if provided.
///   - On submit, POSTs via [submitRatingProvider]; shows "Rating saved ✓".
class ResponseCard extends ConsumerStatefulWidget {
  const ResponseCard({
    super.key,
    required this.modelId,
    required this.displayName,
    this.response,
    this.latencyMs,
    this.error,
    this.isLoading = false,
    this.isFastest = false,
    // Rating params (optional — null = no rating UI shown)
    this.responseId,
    this.initialRating,
  });

  /// API model ID (used as key / semantic label).
  final String modelId;

  /// Human-readable name shown in the card header.
  final String displayName;

  /// Response text (markdown). Null when loading or error.
  final String? response;

  /// Latency in milliseconds. Null when loading or error.
  final int? latencyMs;

  /// Error message. Null when loading or success.
  final String? error;

  /// When true the card shows a shimmer loading skeleton.
  final bool isLoading;

  /// When true the card shows a green "Fastest" badge.
  final bool isFastest;

  /// Backend response UUID. When non-null and no error, shows rating controls.
  final String? responseId;

  /// Pre-populates star controls when an existing rating is available.
  final RatingData? initialRating;

  @override
  ConsumerState<ResponseCard> createState() => _ResponseCardState();
}

class _ResponseCardState extends ConsumerState<ResponseCard> {
  // Local rating state — initialised from initialRating or defaults to 0
  // (0 = no selection yet, valid selections are 1–5)
  late int _accuracy;
  late int _clarity;
  late int _helpfulness;

  // The args of the last submitted rating (drives the FutureProvider watch)
  RatingArgs? _submittedArgs;

  // Whether a successful submit message should be shown
  bool _showSavedMessage = false;

  @override
  void initState() {
    super.initState();
    _initFromRating(widget.initialRating);
  }

  @override
  void didUpdateWidget(ResponseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If the parent passes in a new initialRating (e.g., after reload),
    // and we haven't submitted anything locally yet, adopt the new values.
    if (oldWidget.initialRating != widget.initialRating &&
        _submittedArgs == null) {
      _initFromRating(widget.initialRating);
    }
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
      responseId: widget.responseId!,
      accuracy: _accuracy,
      clarity: _clarity,
      helpfulness: _helpfulness,
    );
    setState(() {
      _submittedArgs = args;
      _showSavedMessage = false;
    });
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  String _formatLatency(int ms) {
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(2)} s';
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final bool hasError = widget.error != null && widget.error!.isNotEmpty;
    final bool showRating =
        widget.responseId != null && !widget.isLoading && !hasError;

    final borderColor =
        hasError ? colorScheme.error : colorScheme.outlineVariant;
    final borderWidth = hasError ? 2.0 : 1.0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: borderWidth),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.isLoading
          ? _buildShimmer(context)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                const Divider(height: 16, indent: 16, endIndent: 16),
                Expanded(
                  child: hasError
                      ? _buildError(context)
                      : _buildResponse(context),
                ),
                if (showRating) _buildRatingSection(context),
              ],
            ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              widget.displayName,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (widget.isFastest && !widget.isLoading && widget.error == null) ...[
            const SizedBox(width: 8),
            _FastestBadge(),
          ],
          if (widget.latencyMs != null && widget.error == null) ...[
            const SizedBox(width: 8),
            _LatencyBadge(latency: _formatLatency(widget.latencyMs!)),
          ],
        ],
      ),
    );
  }

  Widget _buildResponse(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: widget.response != null && widget.response!.isNotEmpty
          ? Markdown(
              data: widget.response!,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              styleSheet: MarkdownStyleSheet.fromTheme(theme),
            )
          : Text(
              'No response received.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
    );
  }

  Widget _buildError(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded,
              color: theme.colorScheme.error, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.error ?? 'An unknown error occurred.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Rating section
  // ---------------------------------------------------------------------------

  Widget _buildRatingSection(BuildContext context) {
    // If a submission is in-flight or complete, watch the provider
    final asyncRating = _submittedArgs != null
        ? ref.watch(submitRatingProvider(_submittedArgs!))
        : null;

    // When provider completes successfully, show saved message
    if (asyncRating is AsyncData<RatingResult> && !_showSavedMessage) {
      // Schedule the state update after build
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _showSavedMessage = true);
        }
      });
    }

    return _RatingSection(
      accuracy: _accuracy,
      clarity: _clarity,
      helpfulness: _helpfulness,
      onAccuracyChanged: (v) => setState(() => _accuracy = v),
      onClarityChanged: (v) => setState(() => _clarity = v),
      onHelpfulnessChanged: (v) => setState(() => _helpfulness = v),
      onSubmit: _canSubmit ? _onSubmit : null,
      isSubmitting: asyncRating is AsyncLoading,
      showSavedMessage: _showSavedMessage,
      submitError: asyncRating is AsyncError
          ? (asyncRating as AsyncError).error.toString()
          : null,
    );
  }

  Widget _buildShimmer(BuildContext context) {
    final theme = Theme.of(context);
    final base = theme.colorScheme.surfaceContainerHighest;
    final highlight = theme.colorScheme.surface;

    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Fake header row
            Row(
              children: [
                Container(
                  width: 120,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 50,
                  height: 14,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 12),
            // Fake text lines
            for (final width in [0.9, 0.75, 0.85, 0.6])
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: FractionallySizedBox(
                  widthFactor: width,
                  child: Container(
                    height: 12,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RatingSection — collapsible rating UI
// ---------------------------------------------------------------------------

/// Collapsible section housing three 1–5 star rows and a submit button.
///
/// Shown only when [ResponseCard.responseId] is non-null and there is no error.
class _RatingSection extends StatelessWidget {
  const _RatingSection({
    required this.accuracy,
    required this.clarity,
    required this.helpfulness,
    required this.onAccuracyChanged,
    required this.onClarityChanged,
    required this.onHelpfulnessChanged,
    required this.onSubmit,
    required this.isSubmitting,
    required this.showSavedMessage,
    this.submitError,
  });

  final int accuracy;
  final int clarity;
  final int helpfulness;
  final ValueChanged<int> onAccuracyChanged;
  final ValueChanged<int> onClarityChanged;
  final ValueChanged<int> onHelpfulnessChanged;
  final VoidCallback? onSubmit;
  final bool isSubmitting;
  final bool showSavedMessage;
  final String? submitError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(
          height: 1,
          color: colorScheme.outlineVariant,
        ),
        Theme(
          // Remove the default ExpansionTile dividers
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
            childrenPadding:
                const EdgeInsets.fromLTRB(16, 0, 16, 12),
            title: Row(
              children: [
                Icon(
                  Icons.star_half_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  showSavedMessage ? 'Rating saved ✓' : 'Rate this response',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: showSavedMessage
                        ? Colors.green.shade700
                        : colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            children: [
              _StarRow(
                label: 'Accuracy',
                value: accuracy,
                onChanged: onAccuracyChanged,
              ),
              const SizedBox(height: 6),
              _StarRow(
                label: 'Clarity',
                value: clarity,
                onChanged: onClarityChanged,
              ),
              const SizedBox(height: 6),
              _StarRow(
                label: 'Helpfulness',
                value: helpfulness,
                onChanged: onHelpfulnessChanged,
              ),
              const SizedBox(height: 10),
              // Submit button row
              Row(
                children: [
                  const Spacer(),
                  if (submitError != null)
                    Expanded(
                      child: Text(
                        submitError!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.error,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  FilledButton.tonal(
                    onPressed: isSubmitting ? null : onSubmit,
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
                              color: colorScheme.onSecondaryContainer,
                            ),
                          )
                        : const Text('Submit Rating'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// _StarRow — a single dimension's 5-star row
// ---------------------------------------------------------------------------

/// One row: a label and five tappable star icons for values 1–5.
class _StarRow extends StatelessWidget {
  const _StarRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;

  /// 0 = unset, 1–5 = selected value.
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
// Badge widgets
// ---------------------------------------------------------------------------

class _FastestBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.flash_on_rounded, color: Colors.white, size: 12),
          SizedBox(width: 3),
          Text(
            'Fastest',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({required this.latency});

  final String latency;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        latency,
        style: TextStyle(
          color: colorScheme.onSecondaryContainer,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
