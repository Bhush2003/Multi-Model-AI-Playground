library;

/// Data models for the prompt submission API response.
///
/// Mirrors the backend JSON contract:
/// ```json
/// {
///   "prompt_id": "<uuid>",
///   "results": [
///     {
///       "model": "gpt-4o",
///       "response": "...",
///       "latency_ms": 1234,
///       "token_count": 150,
///       "cost": 0.001234,
///       "error": null
///     }
///   ]
/// }
/// ```

/// Result for a single model returned by the fan-out API.
class ModelResult {
  const ModelResult({
    required this.model,
    this.response,
    this.latencyMs,
    this.tokenCount,
    this.cost,
    this.error,
  });

  /// API model ID, e.g. `"gpt-4o"`.
  final String model;

  /// Response text from the model. Null if the model returned an error.
  final String? response;

  /// Round-trip latency in milliseconds. Null on error.
  final int? latencyMs;

  /// Total token count consumed. Null on error.
  final int? tokenCount;

  /// Estimated monetary cost in USD. Null on error.
  final double? cost;

  /// Error message if the model failed. Null on success.
  final String? error;

  bool get hasError => error != null && error!.isNotEmpty;

  factory ModelResult.fromJson(Map<String, dynamic> json) {
    return ModelResult(
      model: json['model'] as String,
      response: json['response'] as String?,
      latencyMs: json['latency_ms'] as int?,
      tokenCount: json['token_count'] as int?,
      cost: (json['cost'] as num?)?.toDouble(),
      error: json['error'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'response': response,
        'latency_ms': latencyMs,
        'token_count': tokenCount,
        'cost': cost,
        'error': error,
      };
}

/// Full response from `POST /api/v1/prompts`.
class PromptSubmitResponse {
  const PromptSubmitResponse({
    required this.promptId,
    required this.results,
  });

  final String promptId;
  final List<ModelResult> results;

  factory PromptSubmitResponse.fromJson(Map<String, dynamic> json) {
    final rawResults = json['results'] as List<dynamic>? ?? [];
    return PromptSubmitResponse(
      promptId: json['prompt_id'] as String,
      results: rawResults
          .cast<Map<String, dynamic>>()
          .map(ModelResult.fromJson)
          .toList(),
    );
  }
}
