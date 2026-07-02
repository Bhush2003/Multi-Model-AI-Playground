library;

/// Data models for the AI Judge evaluation API.
///
/// API contract (POST/GET /api/v1/prompts/:id/judge):
/// ```json
/// {
///   "prompt_id": "<uuid>",
///   "winner": "gpt-4o",
///   "ranked_models": [
///     { "model": "gpt-4o", "score": 87, "reasoning": "..." },
///     { "model": "gemini-1.5-pro", "score": 73, "reasoning": "..." }
///   ]
/// }
/// ```

/// Score and reasoning for a single model returned by the AI Judge.
class JudgeModelScore {
  const JudgeModelScore({
    required this.model,
    required this.score,
    required this.reasoning,
  });

  /// API model ID, e.g. `"gpt-4o"`.
  final String model;

  /// Integer score in range 1–100.
  final int score;

  /// Text explanation of the score from the AI Judge.
  final String reasoning;

  factory JudgeModelScore.fromJson(Map<String, dynamic> json) {
    return JudgeModelScore(
      model: json['model'] as String,
      score: json['score'] as int,
      reasoning: json['reasoning'] as String,
    );
  }

  Map<String, dynamic> toJson() => {
        'model': model,
        'score': score,
        'reasoning': reasoning,
      };
}

/// Full evaluation result returned by the AI Judge.
class JudgeResult {
  const JudgeResult({
    required this.promptId,
    required this.winner,
    required this.rankedModels,
  });

  final String promptId;

  /// The model ID of the top-ranked model.
  final String winner;

  /// Models ordered by rank (highest score first).
  final List<JudgeModelScore> rankedModels;

  factory JudgeResult.fromJson(Map<String, dynamic> json) {
    final raw = json['ranked_models'] as List<dynamic>? ?? [];
    return JudgeResult(
      promptId: json['prompt_id'] as String,
      winner: json['winner'] as String,
      rankedModels: raw
          .cast<Map<String, dynamic>>()
          .map(JudgeModelScore.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {
        'prompt_id': promptId,
        'winner': winner,
        'ranked_models': rankedModels.map((m) => m.toJson()).toList(),
      };
}
