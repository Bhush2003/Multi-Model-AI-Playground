import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rag_models.dart';
import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// ragModeProvider — whether RAG mode is currently active
// ---------------------------------------------------------------------------

/// `true` when the user has toggled RAG mode on.
class RagModeNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void enable() => state = true;
  void disable() => state = false;
  void toggle() => state = !state;
}

final ragModeProvider = NotifierProvider<RagModeNotifier, bool>(
  RagModeNotifier.new,
);

// ---------------------------------------------------------------------------
// ragDocumentProvider — the currently selected RAG document (null = none)
// ---------------------------------------------------------------------------

/// Holds the [DocumentItem] the user has chosen for RAG mode.
/// `null` means no document is selected (RAG mode is effectively off).
class RagDocumentNotifier extends Notifier<DocumentItem?> {
  @override
  DocumentItem? build() => null;

  void select(DocumentItem doc) => state = doc;
  void clear() => state = null;
}

final ragDocumentProvider =
    NotifierProvider<RagDocumentNotifier, DocumentItem?>(
  RagDocumentNotifier.new,
);

// ---------------------------------------------------------------------------
// documentsProvider — fetches the list of uploaded documents
// ---------------------------------------------------------------------------

/// FutureProvider that loads documents from GET /api/v1/documents.
/// Invalidate this provider to trigger a refresh.
final documentsProvider =
    FutureProvider<DocumentsListResponse>((ref) async {
  final dio = createDioClient();
  final response =
      await dio.get<Map<String, dynamic>>('/documents');

  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Empty response from server.',
    );
  }

  return DocumentsListResponse.fromJson(data);
});

// ---------------------------------------------------------------------------
// ragSubmitProvider — POSTs to /prompts/rag
// ---------------------------------------------------------------------------

/// FutureProvider.family that POSTs to `/prompts/rag` and returns a
/// [RagSubmitResponse].
///
/// Usage:
/// ```dart
/// final args = RagSubmitArgs(
///   prompt: text,
///   documentId: doc.id,
///   models: selected.toList(),
/// );
/// final result = ref.watch(ragSubmitProvider(args));
/// ```
final ragSubmitProvider =
    FutureProvider.family<RagSubmitResponse, RagSubmitArgs>(
  (ref, args) async {
    final dio = createDioClient();
    final response = await dio.post<Map<String, dynamic>>(
      '/prompts/rag',
      data: {
        'prompt': args.prompt,
        'document_id': args.documentId,
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

    return RagSubmitResponse.fromJson(data);
  },
);
