library;

import 'prompt_result.dart';

/// Represents a single document returned by GET /api/v1/documents.
class DocumentItem {
  const DocumentItem({
    required this.id,
    required this.filename,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String filename;

  /// One of: `"processing"`, `"ready"`, `"error"`.
  final String status;

  final DateTime createdAt;

  bool get isReady => status == 'ready';
  bool get isProcessing => status == 'processing';
  bool get isError => status == 'error';

  factory DocumentItem.fromJson(Map<String, dynamic> json) {
    return DocumentItem(
      id: json['id'] as String,
      filename: json['filename'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'filename': filename,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };
}

/// Response from GET /api/v1/documents.
class DocumentsListResponse {
  const DocumentsListResponse({required this.documents});

  final List<DocumentItem> documents;

  factory DocumentsListResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['documents'] as List<dynamic>? ?? [];
    return DocumentsListResponse(
      documents: raw
          .cast<Map<String, dynamic>>()
          .map(DocumentItem.fromJson)
          .toList(),
    );
  }
}

/// Argument bundle used as the family key for [ragSubmitProvider].
///
/// POST /api/v1/prompts/rag body:
/// ```json
/// { "prompt": "...", "document_id": "<uuid>", "models": [...] }
/// ```
class RagSubmitArgs {
  const RagSubmitArgs({
    required this.prompt,
    required this.documentId,
    required this.models,
  });

  final String prompt;
  final String documentId;
  final List<String> models;

  @override
  bool operator ==(Object other) =>
      other is RagSubmitArgs &&
      other.prompt == prompt &&
      other.documentId == documentId &&
      _listEquals(other.models, models);

  @override
  int get hashCode =>
      Object.hash(prompt, documentId, Object.hashAll(models));

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Full response from POST /api/v1/prompts/rag.
///
/// ```json
/// {
///   "prompt_id": "<uuid>",
///   "no_context_found": false,
///   "results": [...]
/// }
/// ```
class RagSubmitResponse {
  const RagSubmitResponse({
    required this.promptId,
    required this.noContextFound,
    required this.results,
  });

  final String promptId;

  /// `true` when the backend found no chunks with cosine similarity > 0.5
  /// and proceeded without injected context.
  final bool noContextFound;

  final List<ModelResult> results;

  factory RagSubmitResponse.fromJson(Map<String, dynamic> json) {
    final raw = json['results'] as List<dynamic>? ?? [];
    return RagSubmitResponse(
      promptId: json['prompt_id'] as String,
      noContextFound: (json['no_context_found'] as bool?) ?? false,
      results: raw
          .cast<Map<String, dynamic>>()
          .map(ModelResult.fromJson)
          .toList(),
    );
  }
}
