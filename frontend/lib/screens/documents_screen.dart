import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/rag_models.dart';
import '../providers/rag_providers.dart';
import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// DocumentsScreen
// ---------------------------------------------------------------------------

/// Displays the list of uploaded documents and provides a file-upload flow.
///
/// - Status badges: Processing (orange), Ready (green), Error (red)
/// - FAB / button opens the OS file picker (PDF and DOCX only)
/// - Upload progress indicator while multipart POST is in flight
/// - Automatically refreshes the list after a successful upload
/// - Pull-to-refresh support
/// - Empty state when no documents are present
class DocumentsScreen extends ConsumerStatefulWidget {
  const DocumentsScreen({super.key});

  @override
  ConsumerState<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends ConsumerState<DocumentsScreen> {
  bool _uploading = false;
  String? _uploadError;

  // -------------------------------------------------------------------------
  // Upload flow
  // -------------------------------------------------------------------------

  Future<void> _pickAndUpload() async {
    // 1. Open file picker — PDF and DOCX only
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx'],
      withData: false, // stream from path, not memory
      withReadStream: false,
    );

    if (result == null || result.files.isEmpty) return; // user cancelled

    final file = result.files.single;
    final filePath = file.path;

    if (filePath == null) {
      setState(() => _uploadError = 'Could not access the selected file.');
      return;
    }

    setState(() {
      _uploading = true;
      _uploadError = null;
    });

    try {
      final dio = createDioClient();
      final formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          filePath,
          filename: file.name,
        ),
      });

      await dio.post<Map<String, dynamic>>(
        '/documents',
        data: formData,
        options: Options(
          // Let Dio set the Content-Type to multipart/form-data automatically
          contentType: 'multipart/form-data',
        ),
      );

      // Refresh the documents list
      ref.invalidate(documentsProvider);
    } on DioException catch (e) {
      final errMsg = _extractError(e);
      setState(() => _uploadError = errMsg);
    } catch (e) {
      setState(() => _uploadError = 'Upload failed: $e');
    } finally {
      setState(() => _uploading = false);
    }
  }

  String _extractError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['error'] ?? data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    if (e.response?.statusCode == 422) {
      return 'File rejected: unsupported format or exceeds size limit.';
    }
    return 'Upload failed. Please try again.';
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final docsAsync = ref.watch(documentsProvider);

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(documentsProvider),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Upload progress / error banner
            if (_uploading || _uploadError != null)
              SliverToBoxAdapter(
                child: _UploadStatusBanner(
                  uploading: _uploading,
                  error: _uploadError,
                  onDismissError: () =>
                      setState(() => _uploadError = null),
                ),
              ),

            // Documents list
            docsAsync.when(
              loading: () => const SliverFillRemaining(
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => SliverFillRemaining(
                child: Center(
                  child: Text(
                    'Failed to load documents.\n$err',
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              data: (data) {
                if (data.documents.isEmpty) {
                  return const SliverFillRemaining(
                    child: _EmptyState(),
                  );
                }
                return SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) =>
                        _DocumentTile(doc: data.documents[index]),
                    childCount: data.documents.length,
                  ),
                );
              },
            ),
          ],
        ),
      ),
      floatingActionButton: _uploading
          ? null
          : FloatingActionButton.extended(
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: const Text('Upload Document'),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Upload status banner
// ---------------------------------------------------------------------------

class _UploadStatusBanner extends StatelessWidget {
  const _UploadStatusBanner({
    required this.uploading,
    required this.error,
    required this.onDismissError,
  });

  final bool uploading;
  final String? error;
  final VoidCallback onDismissError;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (uploading) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: colorScheme.primaryContainer,
        child: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(
              'Uploading document…',
              style: TextStyle(color: colorScheme.onPrimaryContainer),
            ),
          ],
        ),
      );
    }

    if (error != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: colorScheme.errorContainer,
        child: Row(
          children: [
            Icon(Icons.error_outline, color: colorScheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                error!,
                style: TextStyle(color: colorScheme.onErrorContainer),
              ),
            ),
            IconButton(
              icon: Icon(Icons.close, color: colorScheme.onErrorContainer),
              onPressed: onDismissError,
              tooltip: 'Dismiss',
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

// ---------------------------------------------------------------------------
// Document list tile
// ---------------------------------------------------------------------------

class _DocumentTile extends StatelessWidget {
  const _DocumentTile({required this.doc});

  final DocumentItem doc;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.insert_drive_file_outlined),
      title: Text(
        doc.filename,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(_formatDate(doc.createdAt)),
      trailing: _StatusBadge(status: doc.status),
    );
  }

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.year}-${_two(local.month)}-${_two(local.day)}  '
        '${_two(local.hour)}:${_two(local.minute)}';
  }

  String _two(int n) => n.toString().padLeft(2, '0');
}

// ---------------------------------------------------------------------------
// Status badge chip
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'ready' => ('Ready', Colors.green),
      'processing' => ('Processing', Colors.orange),
      _ => ('Error', Colors.red),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        border: Border.all(color: color, width: 1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.folder_open_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No documents yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Upload a PDF or DOCX file to use in RAG mode.',
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
