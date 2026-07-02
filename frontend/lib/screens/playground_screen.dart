import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/prompt_result.dart';
import '../models/rag_models.dart';
import '../providers/judge_providers.dart';
import '../providers/playground_providers.dart';
import '../providers/rag_providers.dart';
import '../widgets/judge_panel.dart';
import '../widgets/model_selector_widget.dart';
import '../widgets/prompt_input_widget.dart';
import '../widgets/response_panel_list.dart';

// ---------------------------------------------------------------------------
// PlaygroundScreen
// ---------------------------------------------------------------------------

/// The main Playground screen.
///
/// Layout (top to bottom):
///   1. [ModelSelectorWidget]     — checkbox row for model selection
///   2. RAG Mode toggle row       — shows document selector when enabled
///   3. Context banner            — visible when RAG document is selected
///   4. [PromptInputWidget]       — text area + submit button
///   5. Response panels           — side-by-side / paged response cards
///   6. No-context notice         — shown when RAG returns no_context_found
///
/// The normal (non-RAG) submit path is unchanged.
class PlaygroundScreen extends ConsumerWidget {
  const PlaygroundScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ragMode = ref.watch(ragModeProvider);
    final activeArgs = ref.watch(activeSubmitArgsProvider);

    // Watch the normal submit future only when args are set.
    final normalAsync = activeArgs != null
        ? ref.watch(promptSubmitProvider(activeArgs))
        : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Model selector
          const ModelSelectorWidget(),
          const SizedBox(height: 12),

          // RAG mode toggle
          const _RagToggleRow(),
          const SizedBox(height: 8),

          // Document selector + context banner (visible when RAG is on)
          if (ragMode) ...[
            const _DocumentSelector(),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 8),

          // Prompt input — drives submission
          _PlaygroundPromptInput(ragMode: ragMode),
          const SizedBox(height: 24),

          // Response section
          _ResponseSectionRouter(
            activeNormalArgs: activeArgs,
            normalAsync: normalAsync,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// RAG toggle row
// ---------------------------------------------------------------------------

class _RagToggleRow extends ConsumerWidget {
  const _RagToggleRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ragMode = ref.watch(ragModeProvider);
    return Row(
      children: [
        const Icon(Icons.auto_stories_outlined),
        const SizedBox(width: 8),
        const Expanded(child: Text('RAG Mode')),
        Switch(
          value: ragMode,
          onChanged: (_) {
            final notifier = ref.read(ragModeProvider.notifier);
            notifier.toggle();
            // Clear selected document when turning off
            if (ragMode) {
              ref.read(ragDocumentProvider.notifier).clear();
              ref.read(activeRagSubmitArgsProvider.notifier).clear();
            } else {
              ref.read(activeSubmitArgsProvider.notifier).clear();
            }
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Document selector (shown when RAG mode is on)
// ---------------------------------------------------------------------------

class _DocumentSelector extends ConsumerWidget {
  const _DocumentSelector();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final docsAsync = ref.watch(documentsProvider);
    final selectedDoc = ref.watch(ragDocumentProvider);

    return docsAsync.when(
      loading: () =>
          const LinearProgressIndicator(),
      error: (e, _) => Text(
        'Could not load documents: $e',
        style:
            TextStyle(color: Theme.of(context).colorScheme.error),
      ),
      data: (data) {
        final readyDocs =
            data.documents.where((d) => d.isReady).toList();

        if (readyDocs.isEmpty) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 4),
            child: Text(
              'No ready documents. Upload one from the Documents tab.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<DocumentItem>(
              decoration: const InputDecoration(
                labelText: 'Select document',
                prefixIcon: Icon(Icons.insert_drive_file_outlined),
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              initialValue: selectedDoc,
              items: readyDocs
                  .map(
                    (doc) => DropdownMenuItem(
                      value: doc,
                      child: Text(
                        doc.filename,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (doc) {
                if (doc != null) {
                  ref.read(ragDocumentProvider.notifier).select(doc);
                }
              },
            ),
            // Context banner when a document is chosen
            if (selectedDoc != null) ...[
              const SizedBox(height: 8),
              _ContextBanner(filename: selectedDoc.filename),
            ],
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Context banner — Req 11 AC1, AC4
// ---------------------------------------------------------------------------

class _ContextBanner extends StatelessWidget {
  const _ContextBanner({required this.filename});

  final String filename;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.secondary),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_stories, color: colorScheme.secondary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  const TextSpan(text: 'Context: '),
                  TextSpan(
                    text: filename,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              style: TextStyle(color: colorScheme.onSecondaryContainer),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Playground prompt input — wires submit to correct provider
// ---------------------------------------------------------------------------

class _PlaygroundPromptInput extends ConsumerWidget {
  const _PlaygroundPromptInput({required this.ragMode});

  final bool ragMode;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PromptInputWidget(
      onSubmit: (prompt, models) {
        // Clear any previous judge result when a new prompt is submitted.
        ref.read(activeJudgeArgsProvider.notifier).clear();

        if (ragMode) {
          final doc = ref.read(ragDocumentProvider);
          if (doc == null) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Please select a document for RAG mode.'),
              ),
            );
            return;
          }
          // Clear normal args, set RAG args
          ref.read(activeSubmitArgsProvider.notifier).clear();
          ref.read(activeRagSubmitArgsProvider.notifier).submit(
                RagSubmitArgs(
                  prompt: prompt,
                  documentId: doc.id,
                  models: models,
                ),
              );
        } else {
          // Normal path — unchanged
          ref.read(activeRagSubmitArgsProvider.notifier).clear();
          ref.read(activeSubmitArgsProvider.notifier).submit(
                PromptSubmitArgs(prompt: prompt, models: models),
              );
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Response section router — picks normal or RAG response path
// ---------------------------------------------------------------------------

class _ResponseSectionRouter extends ConsumerWidget {
  const _ResponseSectionRouter({
    required this.activeNormalArgs,
    required this.normalAsync,
  });

  final PromptSubmitArgs? activeNormalArgs;
  final AsyncValue<PromptSubmitResponse>? normalAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeRagArgs = ref.watch(activeRagSubmitArgsProvider);

    // RAG path
    if (activeRagArgs != null) {
      final ragAsync = ref.watch(ragSubmitProvider(activeRagArgs));
      return _RagResponseSection(
        activeArgs: activeRagArgs,
        submitAsync: ragAsync,
      );
    }

    // Normal path
    if (activeNormalArgs == null || normalAsync == null) {
      return const SizedBox.shrink();
    }

    return _NormalResponseSection(
      activeArgs: activeNormalArgs!,
      submitAsync: normalAsync!,
    );
  }
}

// ---------------------------------------------------------------------------
// Normal response section (unchanged from original)
// ---------------------------------------------------------------------------

class _NormalResponseSection extends ConsumerWidget {
  const _NormalResponseSection({
    required this.activeArgs,
    required this.submitAsync,
  });

  final PromptSubmitArgs activeArgs;
  final AsyncValue<PromptSubmitResponse> submitAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return submitAsync.when(
      loading: () => ResponsePanelList(
        results: const [],
        isLoading: true,
        loadingModelIds: activeArgs.models,
      ),
      error: (err, _) => _GlobalErrorBanner(message: err.toString()),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ResponsePanelList(
            results: data.results,
            isLoading: false,
            loadingModelIds: activeArgs.models,
          ),
          const SizedBox(height: 16),
          _JudgeSection(promptId: data.promptId),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// RAG response section
// ---------------------------------------------------------------------------

class _RagResponseSection extends ConsumerWidget {
  const _RagResponseSection({
    required this.activeArgs,
    required this.submitAsync,
  });

  final RagSubmitArgs activeArgs;
  final AsyncValue<RagSubmitResponse> submitAsync;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return submitAsync.when(
      loading: () => ResponsePanelList(
        results: const [],
        isLoading: true,
        loadingModelIds: activeArgs.models,
      ),
      error: (err, _) => _GlobalErrorBanner(message: err.toString()),
      data: (data) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // No-context notice — Req 11 AC5
          if (data.noContextFound) const _NoContextNotice(),
          ResponsePanelList(
            results: data.results,
            isLoading: false,
            loadingModelIds: activeArgs.models,
          ),
          const SizedBox(height: 16),
          _JudgeSection(promptId: data.promptId),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// No-context notice — Req 11 AC5
// ---------------------------------------------------------------------------

class _NoContextNotice extends StatelessWidget {
  const _NoContextNotice();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.tertiary),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: colorScheme.onTertiaryContainer,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'No relevant context found; responding without document',
              style:
                  TextStyle(color: colorScheme.onTertiaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Judge section — Req 12 AC1, AC3, AC4
// ---------------------------------------------------------------------------

/// Shows the "Evaluate with AI Judge" button after responses are loaded.
/// When tapped, triggers [judgeProvider] and displays [JudgePanel] with
/// the evaluation result.
class _JudgeSection extends ConsumerWidget {
  const _JudgeSection({required this.promptId});

  final String promptId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeArgs = ref.watch(activeJudgeArgsProvider);
    final theme = Theme.of(context);

    // Only watch judgeProvider when we have active args for this prompt
    final isActive =
        activeArgs != null && activeArgs.promptId == promptId;

    if (!isActive) {
      // Show the trigger button — Req 12 AC1
      return FilledButton.tonal(
        onPressed: () {
          ref
              .read(activeJudgeArgsProvider.notifier)
              .submit(JudgeArgs(promptId: promptId));
        },
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.gavel_rounded, size: 18),
            SizedBox(width: 8),
            Text('Evaluate with AI Judge'),
          ],
        ),
      );
    }

    // Watch the judge future
    final judgeAsync = ref.watch(judgeProvider(activeArgs));

    return judgeAsync.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (err, _) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: theme.colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Evaluation failed: $err',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            TextButton(
              onPressed: () =>
                  ref.read(activeJudgeArgsProvider.notifier).clear(),
              child: const Text('Dismiss'),
            ),
          ],
        ),
      ),
      data: (result) => JudgePanel(result: result),
    );
  }
}

// ---------------------------------------------------------------------------
// Global error banner
// ---------------------------------------------------------------------------

class _GlobalErrorBanner extends StatelessWidget {
  const _GlobalErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: colorScheme.onErrorContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
    );
  }
}
