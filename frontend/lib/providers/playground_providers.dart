import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/prompt_result.dart';
import '../models/rag_models.dart';
import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// Model catalogue
// ---------------------------------------------------------------------------

/// All supported model IDs and their human-readable display names.
const Map<String, String> kModelDisplayNames = {
  'gpt-4o': 'GPT-4o',
  'gemini-1.5-pro': 'Gemini 1.5 Pro',
  'claude-3-5-sonnet': 'Claude 3.5 Sonnet',
};

/// Ordered list of model IDs shown in the selector.
const List<String> kAvailableModels = [
  'gpt-4o',
  'gemini-1.5-pro',
  'claude-3-5-sonnet',
];

// ---------------------------------------------------------------------------
// Selected models — Riverpod 3: Notifier<Set<String>>
// ---------------------------------------------------------------------------

/// Notifier that holds the set of model IDs currently selected by the user.
/// Default: all three models selected.
class SelectedModelsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => Set<String>.from(kAvailableModels);

  void toggle(String modelId) {
    final next = Set<String>.from(state);
    if (next.contains(modelId)) {
      next.remove(modelId);
    } else {
      next.add(modelId);
    }
    state = next;
  }

  void setModels(Set<String> models) {
    state = Set<String>.from(models);
  }
}

final selectedModelsProvider =
    NotifierProvider<SelectedModelsNotifier, Set<String>>(
  SelectedModelsNotifier.new,
);

// ---------------------------------------------------------------------------
// Prompt text — Riverpod 3: Notifier<String>
// ---------------------------------------------------------------------------

/// Holds the current text in the prompt input field.
class PromptTextNotifier extends Notifier<String> {
  @override
  String build() => '';

  void setText(String text) => state = text;
}

final promptTextProvider =
    NotifierProvider<PromptTextNotifier, String>(PromptTextNotifier.new);

// ---------------------------------------------------------------------------
// Active submission args — drives promptSubmitProvider
// ---------------------------------------------------------------------------

/// Argument bundle for [promptSubmitProvider].
class PromptSubmitArgs {
  const PromptSubmitArgs({required this.prompt, required this.models});

  final String prompt;
  final List<String> models;

  @override
  bool operator ==(Object other) =>
      other is PromptSubmitArgs &&
      other.prompt == prompt &&
      _listEquals(other.models, models);

  @override
  int get hashCode => Object.hash(prompt, Object.hashAll(models));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Holds the [PromptSubmitArgs] for the most recent submission, or null when
/// no submission has been made yet.
class ActiveSubmitArgsNotifier extends Notifier<PromptSubmitArgs?> {
  @override
  PromptSubmitArgs? build() => null;

  void submit(PromptSubmitArgs args) => state = args;
  void clear() => state = null;
}

final activeSubmitArgsProvider =
    NotifierProvider<ActiveSubmitArgsNotifier, PromptSubmitArgs?>(
  ActiveSubmitArgsNotifier.new,
);

// ---------------------------------------------------------------------------
// Prompt submit — FutureProvider.family
// ---------------------------------------------------------------------------

/// FutureProvider.family that POSTs to `/prompts` and returns the parsed
/// [PromptSubmitResponse].
///
/// Usage:
/// ```dart
/// final args = PromptSubmitArgs(prompt: text, models: selected.toList());
/// final result = ref.watch(promptSubmitProvider(args));
/// ```
final promptSubmitProvider =
    FutureProvider.family<PromptSubmitResponse, PromptSubmitArgs>(
  (ref, args) async {
    final dio = createDioClient();
    final response = await dio.post<Map<String, dynamic>>(
      '/prompts',
      data: {
        'prompt': args.prompt,
        'models': args.models,
      },
    );

    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Empty response from server.',
      );
    }

    return PromptSubmitResponse.fromJson(data);
  },
);

// ---------------------------------------------------------------------------
// Active RAG submission args — drives ragSubmitProvider
// ---------------------------------------------------------------------------

/// Holds the [RagSubmitArgs] for the most recent RAG submission, or null when
/// no RAG submission has been made yet.
class ActiveRagSubmitArgsNotifier extends Notifier<RagSubmitArgs?> {
  @override
  RagSubmitArgs? build() => null;

  void submit(RagSubmitArgs args) => state = args;
  void clear() => state = null;
}

final activeRagSubmitArgsProvider =
    NotifierProvider<ActiveRagSubmitArgsNotifier, RagSubmitArgs?>(
  ActiveRagSubmitArgsNotifier.new,
);
