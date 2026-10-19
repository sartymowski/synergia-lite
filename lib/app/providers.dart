import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/errors/synergia_exception.dart';
import '../core/network/session_cookies.dart';
import '../core/network/synergia_api_client.dart';
import '../core/security/session_store.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/webview_session.dart';
import '../features/auth/domain/account_info.dart';
import '../features/grades/data/grades_repository.dart';
import '../features/messages/data/drafts_store.dart';
import '../features/messages/data/messages_api_client.dart';
import '../features/messages/data/messages_repository.dart';
import '../features/notifications/presentation/notifications_providers.dart';
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

  /// Świadome wylogowanie usuwa także lokalne wiadomości robocze. Klient
  /// wiadomości (ciasteczka w pamięci) jest odtwarzany przy zmianie stanu.
  ///
  /// Kroki są niezależne: błąd jednego (np. wtyczki) nie zostawia na telefonie
  /// danych z pozostałych, a aplikacja i tak przechodzi do ekranu logowania.
  /// Pierwszy błąd jest zgłaszany dalej po wykonaniu wszystkich kroków.
  Future<void> logout() async {
    Object? firstError;
    StackTrace? firstStack;
    // Najpierw koniec monitorowania (trwające zadanie w tle sprawdza sesję
    // i ustawienia przed pokazaniem powiadomienia).
    for (final step in <Future<void> Function()>[
      () => ref.read(notificationsCleanupProvider)(),
      () => _repo.logout(),
      () => ref.read(draftsStoreProvider).clearAll(),
    ]) {
      try {
        await step();
      } catch (e, st) {
        firstError ??= e;
        firstStack ??= st;
      }
    }
    state = const AsyncData(SignedOut());
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }

  Future<void> sessionExpired() async {
    await _repo.onSessionExpired();
    state = const AsyncData(SignedOut(sessionExpired: true));
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// Wylogowuje lokalnie, gdy serwer odrzuci sesję Synergii, i przekazuje błąd dalej.
/// Robocze wiadomości zostają (to może być chwilowe wygaśnięcie tego samego konta).
Future<T> guardSession<T>(Ref ref, Future<T> Function() load) async {
  try {
    return await load();
  } on SessionExpiredException {
    await ref.read(authControllerProvider.notifier).sessionExpired();
    rethrow;
  }
}

final accountProvider = FutureProvider.autoDispose<AccountInfo?>(
  (ref) => guardSession(
    ref,
    () async =>
        AccountInfo.tryParse(await ref.read(apiClientProvider).get('Me')),
  ),
);

final gradesOverviewProvider = FutureProvider.autoDispose<GradesOverview>(
  (ref) => guardSession(
    ref,
    () => GradesRepository(ref.read(apiClientProvider)).fetchOverview(),
  ),
);

final timetableWeekProvider = FutureProvider.autoDispose
    .family<TimetableWeek, DateTime>(
      (ref, monday) => guardSession(
        ref,
        () =>
            TimetableRepository(ref.read(apiClientProvider)).fetchWeek(monday),
      ),
    );

final draftsStoreProvider = Provider<DraftsStore>(
  (ref) => DraftsStore(SecureKeyValueStore()),
);

/// Odtwarzany przy każdej zmianie stanu logowania — ciasteczka serwisu
/// wiadomości (tylko w pamięci) nie przechodzą między sesjami.
final messagesApiClientProvider = Provider<MessagesApiClient>((ref) {
  ref.watch(authControllerProvider.select((s) => s.value is SignedIn));
  return MessagesApiClient(
    synergiaSession: ref.watch(sessionStoreProvider),
    onSynergiaCookiesChanged: () => ref.read(apiClientProvider).resetSession(),
  );
});

final messagesRepositoryProvider = Provider<MessagesRepository>(
  (ref) => MessagesRepository(ref.watch(messagesApiClientProvider)),
);
