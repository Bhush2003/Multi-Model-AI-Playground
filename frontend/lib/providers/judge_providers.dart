import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/judge_models.dart';
import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// JudgeArgs — argument bundle for judgeProvider
// ---------------------------------------------------------------------------

/// Argument bundle used as the family key for [judgeProvider].
class JudgeArgs {
  const JudgeArgs({required this.promptId});

  final String promptId;

  @override
  bool operator ==(Object other) =>
      other is JudgeArgs && other.promptId == promptId;

  @override
  int get hashCode => promptId.hashCode;
}

// ---------------------------------------------------------------------------
// judgeProvider — POST /prompts/:id/judge
// ---------------------------------------------------------------------------

/// FutureProvider.family that POSTs to `/prompts/:id/judge` and returns the
/// [JudgeResult]. Triggers the AI Judge evaluation for the given prompt.
///
/// Usage:
/// ```dart
/// final args = JudgeArgs(promptId: id);
/// final asyncValue = ref.watch(judgeProvider(args));
/// ```
final judgeProvider =
    FutureProvider.family<JudgeResult, JudgeArgs>((ref, args) async {
  final dio = createDioClient();
  final response = await dio.post<Map<String, dynamic>>(
    '/prompts/${args.promptId}/judge',
  );

  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Empty response from server.',
    );
  }

  return JudgeResult.fromJson(data);
});

// ---------------------------------------------------------------------------
// judgeHistoryProvider — GET /prompts/:id/judge (returns null on 404)
// ---------------------------------------------------------------------------

/// FutureProvider.family that GETs `/prompts/:id/judge`. Returns `null` if
/// the evaluation has not been performed yet (404 response). Returns a
/// [JudgeResult] when a saved evaluation exists.
///
/// Usage:
/// ```dart
/// final asyncValue = ref.watch(judgeHistoryProvider(promptId));
/// ```
final judgeHistoryProvider =
    FutureProvider.family<JudgeResult?, String>((ref, promptId) async {
  final dio = createDioClient();
  try {
    final response = await dio.get<Map<String, dynamic>>(
      '/prompts/$promptId/judge',
    );

    final data = response.data;
    if (data == null) return null;

    return JudgeResult.fromJson(data);
  } on DioException catch (e) {
    if (e.response?.statusCode == 404) {
      // No evaluation exists for this prompt yet — not an error.
      return null;
    }
    rethrow;
  }
});

// ---------------------------------------------------------------------------
// ActiveJudgeArgsNotifier — tracks which prompt is being judged
// ---------------------------------------------------------------------------

/// Notifier that holds the [JudgeArgs] for the currently active evaluation
/// request, or `null` when no evaluation has been requested.
class ActiveJudgeArgsNotifier extends Notifier<JudgeArgs?> {
  @override
  JudgeArgs? build() => null;

  void submit(JudgeArgs args) => state = args;
  void clear() => state = null;
}

/// Provider that tracks the active [JudgeArgs] on the PlaygroundScreen.
/// When non-null, [judgeProvider] is watched with this value.
final activeJudgeArgsProvider =
    NotifierProvider<ActiveJudgeArgsNotifier, JudgeArgs?>(
  ActiveJudgeArgsNotifier.new,
);
