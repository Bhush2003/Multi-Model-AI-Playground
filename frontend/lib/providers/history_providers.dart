import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_models.dart';
import '../models/prompt_result.dart';
import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// Page tracking
// ---------------------------------------------------------------------------

/// Notifier holding the currently displayed page number (1-based).
class HistoryPageNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void setPage(int page) => state = page;
  void nextPage() => state = state + 1;
  void prevPage() {
    if (state > 1) state = state - 1;
  }

  void reset() => state = 1;
}

final historyPageProvider = NotifierProvider<HistoryPageNotifier, int>(
  HistoryPageNotifier.new,
);

// ---------------------------------------------------------------------------
// History list — FutureProvider.family (keyed by page number)
// ---------------------------------------------------------------------------

/// Fetches one page of prompt history from `GET /api/v1/prompts?page=X&limit=20`.
///
/// Usage:
/// ```dart
/// final page = ref.watch(historyPageProvider);
/// final asyncValue = ref.watch(historyProvider(page));
/// ```
final historyProvider =
    FutureProvider.family<HistoryListResponse, int>((ref, page) async {
  final dio = createDioClient();
  final response = await dio.get<Map<String, dynamic>>(
    '/prompts',
    queryParameters: {'page': page, 'limit': 20},
  );

  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Empty response from server.',
    );
  }

  return HistoryListResponse.fromJson(data);
});

// ---------------------------------------------------------------------------
// History detail — FutureProvider.family (keyed by prompt ID)
// ---------------------------------------------------------------------------

/// Fetches the full detail for a single prompt from `GET /api/v1/prompts/:id`.
///
/// Usage:
/// ```dart
/// final asyncValue = ref.watch(historyDetailProvider(promptId));
/// ```
final historyDetailProvider =
    FutureProvider.family<HistoryDetailResponse, String>((ref, promptId) async {
  final dio = createDioClient();
  final response = await dio.get<Map<String, dynamic>>('/prompts/$promptId');

  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Empty response from server.',
    );
  }

  return HistoryDetailResponse.fromJson(data);
});

// ---------------------------------------------------------------------------
// Resubmit — argument bundle
// ---------------------------------------------------------------------------

/// Argument bundle for [resubmitProvider].
class ResubmitArgs {
  const ResubmitArgs({required this.promptId, required this.models});

  final String promptId;
  final List<String> models;

  @override
  bool operator ==(Object other) =>
      other is ResubmitArgs &&
      other.promptId == promptId &&
      _listEquals(other.models, models);

  @override
  int get hashCode => Object.hash(promptId, Object.hashAll(models));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

// ---------------------------------------------------------------------------
// Resubmit — FutureProvider.family
// ---------------------------------------------------------------------------

/// POSTs to `/api/v1/prompts/:id/resubmit` with the given model list.
///
/// Usage:
/// ```dart
/// final args = ResubmitArgs(promptId: id, models: selectedModels.toList());
/// final asyncValue = ref.watch(resubmitProvider(args));
/// ```
final resubmitProvider =
    FutureProvider.family<PromptSubmitResponse, ResubmitArgs>(
        (ref, args) async {
  final dio = createDioClient();
  final response = await dio.post<Map<String, dynamic>>(
    '/prompts/${args.promptId}/resubmit',
    data: {'models': args.models},
  );

  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Empty response from server.',
    );
  }

  return PromptSubmitResponse.fromJson(data);
});
