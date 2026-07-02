import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/dio_client.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

/// Immutable state held by [AuthNotifier].
class AuthState {
  const AuthState({
    this.token,
    this.isLoading = false,
    this.error,
  });

  final String? token;
  final bool isLoading;
  final String? error;

  bool get isAuthenticated => token != null && token!.isNotEmpty;

  AuthState copyWith({
    String? token,
    bool? isLoading,
    String? error,
    bool clearToken = false,
    bool clearError = false,
  }) {
    return AuthState(
      token: clearToken ? null : (token ?? this.token),
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier (Riverpod 3 — replaces StateNotifier)
// ---------------------------------------------------------------------------

/// Manages authentication state: JWT token, loading indicator, and error.
///
/// Exposes [login], [register], and [logout] methods that call the backend
/// `/api/v1/auth/*` endpoints via Dio.
class AuthNotifier extends Notifier<AuthState> {
  late final Dio _dio;

  @override
  AuthState build() {
    _dio = createDioClient();
    return const AuthState();
  }

  // -------------------------------------------------------------------------
  // Public API
  // -------------------------------------------------------------------------

  /// Authenticate an existing user. Stores the returned JWT on success.
  Future<void> login(String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {'email': email, 'password': password},
      );
      final token = response.data?['token'] as String?;
      if (token == null || token.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Unexpected response from server.',
        );
        return;
      }
      state = AuthState(token: token);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e, fallback: 'Login failed. Please try again.'),
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred.',
      );
    }
  }

  /// Register a new user. Stores the returned JWT on success.
  Future<void> register(String name, String email, String password) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/register',
        data: {'name': name, 'email': email, 'password': password},
      );
      final token = response.data?['token'] as String?;
      if (token == null || token.isEmpty) {
        state = state.copyWith(
          isLoading: false,
          error: 'Unexpected response from server.',
        );
        return;
      }
      state = AuthState(token: token);
    } on DioException catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: _extractError(e, fallback: 'Registration failed. Please try again.'),
      );
    } catch (_) {
      state = state.copyWith(
        isLoading: false,
        error: 'An unexpected error occurred.',
      );
    }
  }

  /// Clear the stored token and error, effectively logging the user out.
  void logout() {
    state = const AuthState();
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

  String _extractError(DioException e, {required String fallback}) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final msg = data['error'] ?? data['message'];
      if (msg is String && msg.isNotEmpty) return msg;
    }
    if (e.response?.statusCode == 401) {
      return 'Invalid email or password.';
    }
    return fallback;
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

/// Global auth provider. Read this to get the current [AuthState].
///
/// Example:
/// ```dart
/// final isAuth = ref.watch(authProvider).isAuthenticated;
/// ref.read(authProvider.notifier).login(email, password);
/// ```
final authProvider = NotifierProvider<AuthNotifier, AuthState>(
  AuthNotifier.new,
);
