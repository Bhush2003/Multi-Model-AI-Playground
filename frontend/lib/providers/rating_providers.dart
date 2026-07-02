import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/history_models.dart';
import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// RatingArgs — argument bundle for the rating provider
// ---------------------------------------------------------------------------

/// Immutable argument bundle for [submitRatingProvider].
class RatingArgs {
  const RatingArgs({
    required this.responseId,
    required this.accuracy,
    required this.clarity,
    required this.helpfulness,
  });

  final String responseId;

  /// 1–5 inclusive.
  final int accuracy;

  /// 1–5 inclusive.
  final int clarity;

  /// 1–5 inclusive.
  final int helpfulness;

  @override
  bool operator ==(Object other) =>
      other is RatingArgs &&
      other.responseId == responseId &&
      other.accuracy == accuracy &&
      other.clarity == clarity &&
      other.helpfulness == helpfulness;

  @override
  int get hashCode =>
      Object.hash(responseId, accuracy, clarity, helpfulness);
}

// ---------------------------------------------------------------------------
// RatingResult — parsed 200 response from POST /responses/:id/rating
// ---------------------------------------------------------------------------

/// Confirmed rating values returned by the backend after a successful submit.
class RatingResult {
  const RatingResult({
    required this.responseId,
    required this.accuracy,
    required this.clarity,
    required this.helpfulness,
  });

  final String responseId;
  final int accuracy;
  final int clarity;
  final int helpfulness;

  /// Convert to [RatingData] for display purposes.
  RatingData toRatingData() => RatingData(
        accuracy: accuracy,
        clarity: clarity,
        helpfulness: helpfulness,
      );

  factory RatingResult.fromJson(Map<String, dynamic> json) {
    return RatingResult(
      responseId: json['response_id'] as String,
      accuracy: json['accuracy'] as int,
      clarity: json['clarity'] as int,
      helpfulness: json['helpfulness'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// submitRatingProvider — FutureProvider.family
// ---------------------------------------------------------------------------

/// POSTs rating values to `POST /api/v1/responses/:id/rating`.
///
/// Returns the confirmed [RatingResult] from the backend.
///
/// Requirement 9 AC2: submit → POST /api/v1/responses/:id/rating
/// Requirement 9 AC3: re-posting replaces the stored values (upsert)
///
/// Usage:
/// ```dart
/// final args = RatingArgs(
///   responseId: id, accuracy: 4, clarity: 5, helpfulness: 3,
/// );
/// final async = ref.watch(submitRatingProvider(args));
/// ```
final submitRatingProvider =
    FutureProvider.family<RatingResult, RatingArgs>((ref, args) async {
  final dio = createDioClient();
  final response = await dio.post<Map<String, dynamic>>(
    '/responses/${args.responseId}/rating',
    data: {
      'accuracy': args.accuracy,
      'clarity': args.clarity,
      'helpfulness': args.helpfulness,
    },
  );

  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Empty response from server.',
    );
  }

  return RatingResult.fromJson(data);
});
