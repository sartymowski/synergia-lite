import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/synergia_exception.dart';
import '../core/network/session_cookies.dart';
import '../core/network/synergia_api_client.dart';
import '../core/security/session_store.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/webview_session.dart';
import '../features/auth/domain/account_info.dart';
import '../features/grades/data/grades_repository.dart';
import '../features/grades/domain/grades_overview.dart';
import '../features/timetable/data/timetable_repository.dart';
import '../features/timetable/domain/lesson.dart';

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

final webSessionCleanerProvider = Provider<WebSessionCleaner>(
  (ref) => WebViewSessionCleaner(),
);

final apiClientProvider = Provider<SynergiaApiClient>(
  (ref) => SynergiaApiClient(sessionStore: ref.watch(sessionStoreProvider)),
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    store: ref.watch(sessionStoreProvider),
    api: ref.watch(apiClientProvider),
    webCleaner: ref.watch(webSessionCleanerProvider),
  ),
);

sealed class AuthState {
  const AuthState();
}

final class SignedOut extends AuthState {
  const SignedOut({this.sessionExpired = false});

  final bool sessionExpired;
}

final class SignedIn extends AuthState {
  const SignedIn();
}

class AuthController extends AsyncNotifier<AuthState> {
  AuthRepository get _repo => ref.read(authRepositoryProvider);

  @override
  Future<AuthState> build() async =>
      await _repo.hasSession() ? const SignedIn() : const SignedOut();

  /// Błędy (np. [LoginNotCompletedException]) trafiają do wywołującego ekranu.
  Future<AccountInfo> completeLogin(SessionCookies cookies) async {
    final account = await _repo.completeLogin(cookies);
    state = const AsyncData(SignedIn());
    return account;
  }

  Future<void> logout() async {
    await _repo.logout();
    state = const AsyncData(SignedOut());
  }

  Future<void> sessionExpired() async {
    await _repo.onSessionExpired();
    state = const AsyncData(SignedOut(sessionExpired: true));
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Wylogowuje lokalnie, gdy serwer odrzuci sesję, i przekazuje błąd dalej.
Future<T> _guardSession<T>(Ref ref, Future<T> Function() load) async {
  try {
    return await load();
  } on SessionExpiredException {
    await ref.read(authControllerProvider.notifier).sessionExpired();
    rethrow;
  }
}

final accountProvider = FutureProvider.autoDispose<AccountInfo?>(
  (ref) => _guardSession(
    ref,
    () async =>
        AccountInfo.tryParse(await ref.read(apiClientProvider).get('Me')),
  ),
);

final gradesOverviewProvider = FutureProvider.autoDispose<GradesOverview>(
  (ref) => _guardSession(
    ref,
    () => GradesRepository(ref.read(apiClientProvider)).fetchOverview(),
  ),
);

final timetableWeekProvider = FutureProvider.autoDispose
    .family<TimetableWeek, DateTime>(
      (ref, monday) => _guardSession(
        ref,
        () =>
            TimetableRepository(ref.read(apiClientProvider)).fetchWeek(monday),
      ),
    );
