library;

/// Data models for the Prompt History API.
///
/// Mirrors the backend JSON contracts for:
///   GET  /api/v1/prompts          → [HistoryListResponse]
///   GET  /api/v1/prompts/:id      → [HistoryDetailResponse]
///   POST /api/v1/prompts/:id/resubmit (response reuses [PromptSubmitResponse])

// ---------------------------------------------------------------------------
// List endpoint models
// ---------------------------------------------------------------------------

/// A single row from the history list.
///
/// ```json
/// { "id": "<uuid>", "prompt": "...", "created_at": "ISO8601", "rag_doc_id": null }
/// ```
class PromptHistoryItem {
  const PromptHistoryItem({
    required this.id,
    required this.prompt,
    required this.createdAt,
    this.ragDocId,
  });

  final String id;
  final String prompt;
  final DateTime createdAt;
  final String? ragDocId;

  factory PromptHistoryItem.fromJson(Map<String, dynamic> json) {
    return PromptHistoryItem(
      id: json['id'] as String,
      prompt: json['prompt'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      ragDocId: json['rag_doc_id'] as String?,
    );
  }
}

/// Response from `GET /api/v1/prompts?page=X&limit=Y`.
///
/// ```json
/// { "prompts": [...], "total": 42, "page": 1, "limit": 20 }
/// ```
class HistoryListResponse {
  const HistoryListResponse({
    required this.prompts,
    required this.total,
    required this.page,
    required this.limit,
  });

  final List<PromptHistoryItem> prompts;
  final int total;
  final int page;
  final int limit;

  bool get hasMore => (page * limit) < total;

  factory HistoryListResponse.fromJson(Map<String, dynamic> json) {
    final rawPrompts = json['prompts'] as List<dynamic>? ?? [];
    return HistoryListResponse(
      prompts: rawPrompts
          .cast<Map<String, dynamic>>()
          .map(PromptHistoryItem.fromJson)
          .toList(),
      total: json['total'] as int,
      page: json['page'] as int,
      limit: json['limit'] as int,
    );
  }
}

// ---------------------------------------------------------------------------
// Detail endpoint models
// ---------------------------------------------------------------------------

/// Optional rating attached to a stored response.
///
/// ```json
/// { "accuracy": 4, "clarity": 5, "helpfulness": 4 }
/// ```
class RatingData {
  const RatingData({
    required this.accuracy,
    required this.clarity,
    required this.helpfulness,
  });

  final int accuracy;
  final int clarity;
  final int helpfulness;

  factory RatingData.fromJson(Map<String, dynamic> json) {
    return RatingData(
      accuracy: json['accuracy'] as int,
      clarity: json['clarity'] as int,
      helpfulness: json['helpfulness'] as int,
    );
  }
}

/// A single model's response stored under a prompt.
///
/// ```json
/// {
///   "id": "<uuid>",
///   "model_name": "gpt-4o",
///   "response": "...",
///   "latency_ms": 1234,
///   "token_count": 150,
///   "cost": 0.001234,
///   "error": null,
///   "rating": { "accuracy": 4, "clarity": 5, "helpfulness": 4 }
/// }
/// ```
class HistoryResponseItem {
  const HistoryResponseItem({
    required this.id,
    required this.modelName,
    this.response,
    this.latencyMs,
    this.tokenCount,
    this.cost,
    this.error,
    this.rating,
  });

  final String id;
  final String modelName;
  final String? response;
  final int? latencyMs;
  final int? tokenCount;
  final double? cost;
  final String? error;
  final RatingData? rating;

  bool get hasError => error != null && error!.isNotEmpty;

  factory HistoryResponseItem.fromJson(Map<String, dynamic> json) {
    final ratingJson = json['rating'] as Map<String, dynamic>?;
    return HistoryResponseItem(
      id: json['id'] as String,
      modelName: json['model_name'] as String,
      response: json['response'] as String?,
      latencyMs: json['latency_ms'] as int?,
      tokenCount: json['token_count'] as int?,
      cost: (json['cost'] as num?)?.toDouble(),
      error: json['error'] as String?,
      rating: ratingJson != null ? RatingData.fromJson(ratingJson) : null,
    );
  }
}

/// Full response from `GET /api/v1/prompts/:id`.
///
/// ```json
/// {
///   "id": "<uuid>",
///   "prompt": "...",
///   "created_at": "...",
///   "responses": [...]
/// }
/// ```
class HistoryDetailResponse {
  const HistoryDetailResponse({
    required this.id,
    required this.prompt,
    required this.createdAt,
    required this.responses,
  });

  final String id;
  final String prompt;
  final DateTime createdAt;
  final List<HistoryResponseItem> responses;

  factory HistoryDetailResponse.fromJson(Map<String, dynamic> json) {
    final rawResponses = json['responses'] as List<dynamic>? ?? [];
    return HistoryDetailResponse(
      id: json['id'] as String,
      prompt: json['prompt'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      responses: rawResponses
          .cast<Map<String, dynamic>>()
          .map(HistoryResponseItem.fromJson)
          .toList(),
    );
  }
}
