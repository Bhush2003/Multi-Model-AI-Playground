import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../config/api_config.dart';

/// Global navigator key used by the 401 interceptor to redirect to
/// `AuthScreen` without requiring a [BuildContext].
///
/// Must be assigned to [MaterialApp.navigatorKey] in `main.dart`.
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// ---------------------------------------------------------------------------
// Callback hooks — wired up in main.dart after ProviderScope is mounted.
// Using callbacks breaks the circular dependency between dio_client and
// auth_provider: auth_provider imports dio_client (to call createDioClient),
// but dio_client never imports auth_provider.
// ---------------------------------------------------------------------------

/// Called by the JWT interceptor to retrieve the current token.
/// Set this in main.dart: `getToken = () => container.read(authProvider).token;`
String? Function() getToken = () => null;

/// Called by the 401 interceptor to clear the stored token.
/// Set this in main.dart: `onUnauthorized = () { container.read(authProvider.notifier).logout(); ... };`
void Function() onUnauthorized = () {};

/// Called when a non-401 network/server error occurs (connection error or 5xx).
/// Wired in main.dart to display a global snackbar via [scaffoldMessengerKey].
void Function(String message) onNetworkError = (_) {};

/// Creates and configures a shared [Dio] instance with:
/// - Base URL, timeouts, and JSON content-type header.
/// - A JWT interceptor that reads the token via [getToken] and attaches an
///   `Authorization: Bearer <token>` header to every outgoing request.
/// - A 401 error interceptor that calls [onUnauthorized] so the app can
///   clear state and redirect to `AuthScreen`.
Dio createDioClient() {
  final dio = Dio(
    BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: ApiConfig.connectTimeout,
      receiveTimeout: ApiConfig.receiveTimeout,
      headers: const {'Content-Type': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (RequestOptions options, RequestInterceptorHandler handler) {
        final token = getToken();
        if (token != null && token.isNotEmpty) {
          options.headers['Authorization'] = 'Bearer $token';
        }
        handler.next(options);
      },
      onError: (DioException e, ErrorInterceptorHandler handler) {
        if (e.response?.statusCode == 401) {
          onUnauthorized();
        } else if (e.type == DioExceptionType.connectionError ||
            e.type == DioExceptionType.connectionTimeout ||
            (e.response?.statusCode != null &&
                e.response!.statusCode! >= 500)) {
          final msg = _extractErrorMessage(e);
          onNetworkError(msg);
        }
        handler.next(e);
      },
    ),
  );

  return dio;
}

/// Extracts a human-readable error message from a [DioException].
///
/// Returns a connection-failure message for network-level errors, extracts
/// the `error` or `message` field from a JSON response body if available,
/// and falls back to a generic server-error string.
String _extractErrorMessage(DioException e) {
  if (e.type == DioExceptionType.connectionError ||
      e.type == DioExceptionType.connectionTimeout) {
    return 'Connection failed. Check your internet connection.';
  }
  final data = e.response?.data;
  if (data is Map<String, dynamic>) {
    final msg = data['error'] ?? data['message'];
    if (msg is String && msg.isNotEmpty) return msg;
  }
  return 'An unexpected server error occurred.';
}
