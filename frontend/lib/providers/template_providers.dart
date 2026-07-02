import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/template_models.dart';
import '../services/dio_client.dart';

/// FutureProvider that fetches all prompt template categories from
/// `GET /api/v1/templates`.
///
/// Usage:
/// ```dart
/// final async = ref.watch(templatesProvider);
/// async.when(
///   data: (response) => ...,
///   loading: () => ...,
///   error: (e, _) => ...,
/// );
/// ```
final templatesProvider = FutureProvider<TemplatesResponse>((ref) async {
  final dio = createDioClient();
  final response = await dio.get<Map<String, dynamic>>('/templates');

  final data = response.data;
  if (data == null) {
    throw DioException(
      requestOptions: response.requestOptions,
      message: 'Empty response from server.',
    );
  }

  return TemplatesResponse.fromJson(data);
});
