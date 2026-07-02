/// Centralised HTTP client configuration.
///
/// In production, replace [baseUrl] with the deployed API URL via a build
/// argument or environment variable injected at compile time.
class ApiConfig {
  static const String baseUrl = 'http://localhost:8080/api/v1';

  /// Timeout for initial connection to the server.
  static const Duration connectTimeout = Duration(seconds: 10);

  /// Timeout for receiving a full response — long to accommodate LLM latency.
  static const Duration receiveTimeout = Duration(seconds: 60);
}
