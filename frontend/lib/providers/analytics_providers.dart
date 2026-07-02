import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/analytics_models.dart';
import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// Date range state
// ---------------------------------------------------------------------------

/// Holds the currently selected analytics date range.
/// Both fields are null when "All time" is selected.
class AnalyticsDateRange {
  const AnalyticsDateRange({this.startDate, this.endDate});

  final DateTime? startDate;
  final DateTime? endDate;

  AnalyticsDateRange copyWith({DateTime? startDate, DateTime? endDate}) {
    return AnalyticsDateRange(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }

  AnalyticsDateRange clearStart() =>
      AnalyticsDateRange(startDate: null, endDate: endDate);

  AnalyticsDateRange clearEnd() =>
      AnalyticsDateRange(startDate: startDate, endDate: null);
}

/// Notifier that holds the analytics date range filter.
class AnalyticsDateRangeNotifier extends Notifier<AnalyticsDateRange> {
  @override
  AnalyticsDateRange build() => const AnalyticsDateRange();

  void setStartDate(DateTime? date) {
    state = AnalyticsDateRange(startDate: date, endDate: state.endDate);
  }

  void setEndDate(DateTime? date) {
    state = AnalyticsDateRange(startDate: state.startDate, endDate: date);
  }

  void clearRange() {
    state = const AnalyticsDateRange();
  }
}

/// Provides the current [AnalyticsDateRange] selection.
final analyticsDateRangeProvider =
    NotifierProvider<AnalyticsDateRangeNotifier, AnalyticsDateRange>(
  AnalyticsDateRangeNotifier.new,
);

// ---------------------------------------------------------------------------
// Analytics data — FutureProvider.family
// ---------------------------------------------------------------------------

/// Formats a [DateTime] as a `"YYYY-MM-DD"` string for API query parameters.
String _formatDateForApi(DateTime date) {
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// FutureProvider.family that GETs aggregated analytics from `/analytics`.
///
/// Pass an [AnalyticsArgs] with optional start/end dates. When both dates are
/// null the backend returns all-time aggregates.
///
/// Usage:
/// ```dart
/// final args = AnalyticsArgs(startDate: start, endDate: end);
/// final asyncValue = ref.watch(analyticsProvider(args));
/// ```
final analyticsProvider =
    FutureProvider.family<AnalyticsResponse, AnalyticsArgs>(
  (ref, args) async {
    final dio = createDioClient();

    final Map<String, dynamic> queryParams = {};
    if (args.startDate != null) {
      queryParams['start_date'] = _formatDateForApi(args.startDate!);
    }
    if (args.endDate != null) {
      queryParams['end_date'] = _formatDateForApi(args.endDate!);
    }

    final response = await dio.get<Map<String, dynamic>>(
      '/analytics',
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    final data = response.data;
    if (data == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        message: 'Empty response from server.',
      );
    }

    return AnalyticsResponse.fromJson(data);
  },
);
