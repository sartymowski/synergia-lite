import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/presentation/login_screen.dart';
import 'home_screen.dart';
import 'providers.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authChanges = ValueNotifier<Object?>(null);
  ref.listen(authControllerProvider, (_, next) => authChanges.value = next);
  ref.onDispose(authChanges.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: authChanges,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      final at = state.matchedLocation;
      if (auth.isLoading && !auth.hasValue) {
        return at == '/splash' ? null : '/splash';
      }
      final signedIn = auth.value is SignedIn;
      if (!signedIn) return at == '/login' ? null : '/login';
      if (at == '/login' || at == '/splash') return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
    ],
  );
});
