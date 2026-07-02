library;

/// Data models for the Cost Analytics API.
///
/// Mirrors the backend JSON contract:
/// ```
/// GET /api/v1/analytics?start_date=2024-01-01&end_date=2024-12-31
/// Response 200:
/// {
///   "total_requests": 42,
///   "per_model": [
///     { "model": "gpt-4o", "request_count": 18, "total_tokens": 25000, "total_cost": 0.3456 }
///   ]
/// }
/// ```

// ---------------------------------------------------------------------------
// Per-model stats
// ---------------------------------------------------------------------------

/// Aggregated usage stats for a single model.
class PerModelStats {
  const PerModelStats({
    required this.model,
    required this.requestCount,
    required this.totalTokens,
    required this.totalCost,
  });

  /// API model ID, e.g. `"gpt-4o"`.
  final String model;

  /// Number of requests made to this model.
  final int requestCount;

  /// Total tokens consumed by this model.
  final int totalTokens;

  /// Total estimated cost in USD for this model.
  final double totalCost;

  factory PerModelStats.fromJson(Map<String, dynamic> json) {
    return PerModelStats(
      model: json['model'] as String,
      requestCount: json['request_count'] as int,
      totalTokens: json['total_tokens'] as int,
      totalCost: (json['total_cost'] as num).toDouble(),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics response
// ---------------------------------------------------------------------------

/// Full response from `GET /api/v1/analytics`.
class AnalyticsResponse {
  const AnalyticsResponse({
    required this.totalRequests,
    required this.perModel,
  });

  /// Total request count across all models.
  final int totalRequests;

  /// Per-model breakdown of requests, tokens, and cost.
  final List<PerModelStats> perModel;

  factory AnalyticsResponse.fromJson(Map<String, dynamic> json) {
    final rawPerModel = json['per_model'] as List<dynamic>? ?? [];
    return AnalyticsResponse(
      totalRequests: json['total_requests'] as int,
      perModel: rawPerModel
          .cast<Map<String, dynamic>>()
          .map(PerModelStats.fromJson)
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics args — argument bundle for the FutureProvider.family
// ---------------------------------------------------------------------------

/// Argument bundle for [analyticsProvider]. Both dates are optional; when
/// null, the backend returns all-time aggregates.
class AnalyticsArgs {
  const AnalyticsArgs({this.startDate, this.endDate});

  /// Inclusive start of the date range filter, or null for all time.
  final DateTime? startDate;

  /// Inclusive end of the date range filter, or null for all time.
  final DateTime? endDate;

  @override
  bool operator ==(Object other) =>
      other is AnalyticsArgs &&
      other.startDate == startDate &&
      other.endDate == endDate;

  @override
  int get hashCode => Object.hash(startDate, endDate);
}
