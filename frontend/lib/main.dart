import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/auth_provider.dart';
import 'screens/auth_screen.dart';
import 'screens/home_screen.dart';
import 'services/dio_client.dart';

/// Global [ScaffoldMessengerState] key used to show snackbars from outside the
/// widget tree (e.g., from Dio error interceptors).
///
/// Must be assigned to [MaterialApp.scaffoldMessengerKey].
final GlobalKey<ScaffoldMessengerState> scaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

void main() {
  // Create the ProviderContainer before runApp so we can wire up the Dio
  // callback hooks that break the circular dependency.
  final container = ProviderContainer();

  // Wire the token getter: Dio interceptor calls this to attach Bearer header.
  getToken = () => container.read(authProvider).token;

  // Wire the 401 handler: on unauthorised response, logout and navigate.
  onUnauthorized = () {
    container.read(authProvider.notifier).logout();
    navigatorKey.currentState?.pushNamedAndRemoveUntil('/auth', (_) => false);
  };

  // Wire the network-error handler: show a floating snackbar for connection
  // errors and 5xx responses so the user always gets feedback.
  onNetworkError = (String message) {
    scaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
  };

  // Forward unhandled Flutter framework errors to the standard error handler.
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
  };

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const AiPlaygroundApp(),
    ),
  );
}

class AiPlaygroundApp extends ConsumerWidget {
  const AiPlaygroundApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(authProvider).isAuthenticated;

    return MaterialApp(
      title: 'Multi-Model AI Playground',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      // Named routes used by the 401 interceptor's pushNamedAndRemoveUntil.
      routes: {
        '/auth': (_) => const AuthScreen(),
        '/home': (_) => const HomeScreen(),
      },
      // Determine the initial screen based on whether a token is present.
      home: isAuthenticated ? const HomeScreen() : const AuthScreen(),
    );
  }
}
