import 'package:flutter/material.dart';

import '../models/prompt_result.dart';
import '../providers/playground_providers.dart';
import 'response_card.dart';

/// Displays one [ResponseCard] per selected model in a layout that adapts to
/// the available width:
///
/// - **Mobile** (width < 600): horizontally swipeable [PageView]
/// - **Tablet / Web** (width ≥ 600): side-by-side [Row]
///
/// While [isLoading] is true a shimmer card is shown for every model in
/// [models] (or for each ID in [loadingModelIds] when no results are available
/// yet).
class ResponsePanelList extends StatelessWidget {
  const ResponsePanelList({
    super.key,
    required this.results,
    required this.isLoading,
    this.loadingModelIds = const [],
  });

  /// Results returned by the API. May be empty while loading.
  final List<ModelResult> results;

  /// True while the API call is in-flight.
  final bool isLoading;

  /// Model IDs to render shimmer cards for when [results] is still empty.
  final List<String> loadingModelIds;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// The model ID with the lowest latency among successful results.
  String? _fastestModelId() {
    final successful = results
        .where((r) => !r.hasError && r.latencyMs != null)
        .toList();
    if (successful.isEmpty) return null;
    successful.sort((a, b) => a.latencyMs!.compareTo(b.latencyMs!));
    return successful.first.model;
  }

  List<Widget> _buildCards(BuildContext context) {
    final fastestId = _fastestModelId();

    if (isLoading && results.isEmpty) {
      // Show shimmer cards for the selected (pending) models.
      return loadingModelIds.map((modelId) {
        final displayName = kModelDisplayNames[modelId] ?? modelId;
        return _PanelWrapper(
          child: ResponseCard(
            key: ValueKey('loading-$modelId'),
            modelId: modelId,
            displayName: displayName,
            isLoading: true,
          ),
        );
      }).toList();
    }

    return results.map((result) {
      final displayName =
          kModelDisplayNames[result.model] ?? result.model;
      return _PanelWrapper(
        child: ResponseCard(
          key: ValueKey(result.model),
          modelId: result.model,
          displayName: displayName,
          response: result.response,
          latencyMs: result.latencyMs,
          error: result.error,
          isLoading: false,
          isFastest: result.model == fastestId,
        ),
      );
    }).toList();
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final cards = _buildCards(context);

    if (cards.isEmpty) return const SizedBox.shrink();

    final screenWidth = MediaQuery.of(context).size.width;
    final isMobile = screenWidth < 600;

    if (isMobile) {
      return _MobilePageView(cards: cards);
    } else {
      return _TabletRow(cards: cards);
    }
  }
}

// ---------------------------------------------------------------------------
// Layout variants
// ---------------------------------------------------------------------------

class _MobilePageView extends StatefulWidget {
  const _MobilePageView({required this.cards});
  final List<Widget> cards;

  @override
  State<_MobilePageView> createState() => _MobilePageViewState();
}

class _MobilePageViewState extends State<_MobilePageView> {
  final PageController _controller = PageController(viewportFraction: 0.92);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 420,
      child: PageView(
        controller: _controller,
        clipBehavior: Clip.none,
        children: widget.cards,
      ),
    );
  }
}

class _TabletRow extends StatelessWidget {
  const _TabletRow({required this.cards});
  final List<Widget> cards;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cards,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Wrapper that adds consistent padding between cards
// ---------------------------------------------------------------------------

class _PanelWrapper extends StatelessWidget {
  const _PanelWrapper({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: child,
      ),
    );
  }
}
