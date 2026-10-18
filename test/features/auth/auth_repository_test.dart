import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/auth/data/auth_repository.dart';

import '../../helpers/fake_http.dart';

class _RecordingCleaner implements WebSessionCleaner {
  int calls = 0;

  @override
  Future<void> clear() async => calls++;
}

void main() {
  late InMemorySessionStore store;
  late _RecordingCleaner cleaner;

  setUp(() {
    store = InMemorySessionStore();
    cleaner = _RecordingCleaner();
  });

  AuthRepository repo(FakeAdapter adapter) => AuthRepository(
    store: store,
    api: SynergiaApiClient(
      sessionStore: store,
      dio: fakeDio(adapter),
      minInterval: Duration.zero,
    ),
    webCleaner: cleaner,
  );

  final cookies = SessionCookies({'DZIENNIKSID': 'a', 'oauth_token': 'b'});

  test('udane logowanie zapisuje sesję i zwraca minimum danych', () async {
    final adapter = FakeAdapter(
      (_) => jsonBody({
        'Me': {
          'Account': {
            'FirstName': 'Rodzic',
            'LastName': 'Testowy',
            'Login': 'x',
          },
          'User': {'FirstName': 'Uczeń', 'LastName': 'Testowy'},
        },
      }),
    );
    final account = await repo(adapter).completeLogin(cookies);
    expect(account.studentFirstName, 'Uczeń');
    expect(account.accountFirstName, 'Rodzic');
    expect(store.session, isNotNull);
    expect(await repo(adapter).hasSession(), isTrue);
    expect(adapter.requests.single.headers['Cookie'], cookies.toHeader());
  });

  test('odrzucona sesja: błąd z nazwami ciasteczek, nic nie zostaje', () async {
    final adapter = FakeAdapter(
      (_) => jsonBody({
        'Status': 'Error',
        'Message': 'Request is denied',
      }, status: 401),
    );
    await expectLater(
      repo(adapter).completeLogin(cookies),
      throwsA(
        isA<LoginNotCompletedException>().having(
          (e) => e.cookieNames,
          'cookieNames',
          ['DZIENNIKSID', 'oauth_token'],
        ),
      ),
    );
    expect(store.session, isNull);
    // Regresja 2026-10-18: WebView NIE może być czyszczony w trakcie logowania.
    expect(cleaner.calls, 0);
  });

  test('Me 200 bez obiektu konta nie jest uznane za zalogowanie', () async {
    final adapter = FakeAdapter((_) => jsonBody({'Me': {}}));
    await expectLater(
      repo(adapter).completeLogin(cookies),
      throwsA(isA<UnexpectedResponseException>()),
    );
    expect(store.session, isNull);
    expect(cleaner.calls, 0);
  });

  test('limit zapytań przy logowaniu nie zostawia sesji', () async {
    final adapter = FakeAdapter((_) => jsonBody({}, status: 429));
    await expectLater(
      repo(adapter).completeLogin(cookies),
      throwsA(isA<RateLimitedException>()),
    );
    expect(store.session, isNull);
  });

  test('błąd sieci przy logowaniu też nie zostawia sesji', () async {
    final adapter = FakeAdapter((_) => throw const SocketException('offline'));
    await expectLater(
      repo(adapter).completeLogin(cookies),
      throwsA(isA<NetworkException>()),
    );
    expect(store.session, isNull);
  });

  test('wylogowanie: /wyloguj, czyszczenie sesji i WebView', () async {
    store.session = cookies;
    final adapter = FakeAdapter((_) => textBody(''));
    await repo(adapter).logout();
    expect(adapter.requests.single.uri.toString(), SynergiaApiClient.logoutUrl);
    expect(store.session, isNull);
    expect(cleaner.calls, 1);
  });

  test('wylogowanie offline nadal czyści dane lokalne', () async {
    store.session = cookies;
    final adapter = FakeAdapter((_) => throw const SocketException('offline'));
    await repo(adapter).logout();
    expect(store.session, isNull);
    expect(cleaner.calls, 1);
  });

  test('wygaśnięcie sesji czyści dane bez wołania serwera', () async {
    store.session = cookies;
    final adapter = FakeAdapter((_) => jsonBody({}));
    await repo(adapter).onSessionExpired();
    expect(adapter.requests, isEmpty);
    expect(store.session, isNull);
  });
}
