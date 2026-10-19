import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/features/messages/data/messages_api_client.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/messages_fakes.dart';

void main() {
  group('inicjalizacja (wiadomosci3 → MultiDomainLogon)', () {
    test(
      'ciasteczka Synergii idą tylko do Synergii, wiadomości tylko do wiadomości',
      () async {
        final server = FakeMessagesServer(
          api: {
            'me': (_) => jsonBody({
              'data': {'accountId': 'K'},
            }),
          },
        );
        final f = fakeMessagesClient(server);
        await f.client.get('me');

        final req = f.adapter.requests;
        expect(req.map((r) => '${r.uri.host}${r.uri.path}'), [
          'synergia.librus.pl/wiadomosci3',
          'wiadomosci.librus.pl/MultiDomainLogon',
          'wiadomosci.librus.pl/module/inbox',
          'wiadomosci.librus.pl/api/me',
        ]);
        expect(req[0].headers['Cookie'], 'DZIENNIKSID=syn1; oauth_token=tok');
        expect(
          req[1].headers.containsKey('Cookie'),
          isFalse,
          reason: 'brak ciasteczek wiadomości przed MultiDomainLogon',
        );
        expect(req[3].headers['Cookie'], 'WIADSID=w1');
        expect(req[3].headers['Cookie'], isNot(contains('DZIENNIKSID')));
        expect(f.client.cookieNames, ['WIADSID']);
        expect(
          req.every((r) => !'${r.headers['User-Agent']}'.contains('Android')),
          isTrue,
        );
      },
    );

    test('kolejne odczyty nie inicjalizują ponownie', () async {
      final server = FakeMessagesServer(api: {'me': (_) => jsonBody({})});
      final f = fakeMessagesClient(server);
      await f.client.get('me');
      await f.client.get('me');
      expect(server.bootstraps, 1);
    });

    test('„Brak dostępu” = szkoła bez modułu Wiadomości', () async {
      final server = FakeMessagesServer(
        bootstrap: (_) => textBody('<h1>Brak dostępu</h1>'),
      );
      final f = fakeMessagesClient(server);
      await expectLater(
        f.client.get('me'),
        throwsA(isA<MessagesUnavailableException>()),
      );
    });

    test(
      'przekierowanie na logowanie = brak aktywnej sesji Synergii',
      () async {
        for (final target in [
          'https://portal.librus.pl/rodzina',
          'https://synergia.librus.pl/loguj/portalRodzina',
          'https://api.librus.pl/OAuth/Authorization?client_id=46',
        ]) {
          final server = FakeMessagesServer(bootstrap: (_) => redirect(target));
          final f = fakeMessagesClient(server);
          await expectLater(
            f.client.get('me'),
            throwsA(isA<SessionExpiredException>()),
            reason: target,
          );
        }
      },
    );

    test('przekierowanie poza librus.pl jest odrzucane', () async {
      final server = FakeMessagesServer(
        bootstrap: (_) => redirect('https://evil.example/steal'),
      );
      final f = fakeMessagesClient(server);
      await expectLater(
        f.client.get('me'),
        throwsA(isA<UnexpectedResponseException>()),
      );
      expect(
        f.adapter.requests.map((r) => r.uri.host),
        isNot(contains('evil.example')),
      );
    });

    test(
      "przekierowanie http na host Librusa jest podnoszone do https (regresja 2026-10-19)",
      () async {
        final server = FakeMessagesServer(
          bootstrap: (_) =>
              redirect("http://wiadomosci.librus.pl/MultiDomainLogon?token=X"),
          api: {"me": (_) => jsonBody({})},
        );
        final f = fakeMessagesClient(server);
        await f.client.get("me");
        expect(
          f.adapter.requests.every((r) => r.uri.scheme == "https"),
          isTrue,
          reason: "nic jawnym tekstem",
        );
        expect(
          f.adapter.requests[1].uri.toString(),
          startsWith("https://wiadomosci.librus.pl/MultiDomainLogon"),
        );
      },
    );

    test("http na obcy host i inny port nadal są odrzucane", () async {
      for (final target in [
        "http://evil.example/x",
        "http://wiadomosci.librus.pl:8080/x",
        "ftp://wiadomosci.librus.pl/x",
      ]) {
        final f = fakeMessagesClient(
          FakeMessagesServer(bootstrap: (_) => redirect(target)),
        );
        await expectLater(
          f.client.get("me"),
          throwsA(isA<UnexpectedResponseException>()),
          reason: target,
        );
        expect(
          f.adapter.requests,
          hasLength(1),
          reason: "bez żądania pod odrzucony adres",
        );
      }
    });

    test('brak ciasteczek wiadomości po inicjalizacji', () async {
      final server = FakeMessagesServer(
        bootstrap: (_) => textBody('<html>ok</html>'),
      );
      final f = fakeMessagesClient(server);
      await expectLater(
        f.client.get('me'),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });

    test('brak sesji Synergii w magazynie', () async {
      final f = fakeMessagesClient(FakeMessagesServer());
      f.store.session = null;
      await expectLater(
        f.client.get('me'),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test('rotacja ciasteczek Synergii jest zapisywana i zgłaszana', () async {
      var changed = 0;
      final server = FakeMessagesServer(
        bootstrap: (_) => redirect(
          'https://wiadomosci.librus.pl/MultiDomainLogon?token=X',
          setCookie: ['DZIENNIKSID=syn2; path=/'],
        ),
        api: {'me': (_) => jsonBody({})},
      );
      final f = fakeMessagesClient(
        server,
        onSynergiaCookiesChanged: () => changed++,
      );
      await f.client.get('me');
      expect(f.store.session!.toHeader(), contains('DZIENNIKSID=syn2'));
      expect(changed, 1);
    });

    test('współbieżne zapytania dzielą jedną inicjalizację', () async {
      final server = FakeMessagesServer(
        api: {'me': (_) => jsonBody({}), 'tags': (_) => jsonBody({})},
      );
      final f = fakeMessagesClient(server);
      await Future.wait([f.client.get('me'), f.client.get('tags')]);
      expect(server.bootstraps, 1);
    });
  });

  group('wygaśnięcie sesji wiadomości', () {
    test('401 → jedna ponowna inicjalizacja i powtórzony odczyt', () async {
      var calls = 0;
      final server = FakeMessagesServer(
        api: {
          'inbox/messages': (_) =>
              ++calls == 1 ? jsonBody({}, status: 401) : jsonBody({'data': []}),
        },
      );
      final f = fakeMessagesClient(server);
      expect(await f.client.get('inbox/messages'), {'data': []});
      expect(server.bootstraps, 2);
      expect(f.adapter.requests.last.headers['Cookie'], 'WIADSID=w2');
    });

    test(
      '401 również po odnowieniu → MessagesSessionExpired (bez wylogowania z Synergii)',
      () async {
        final server = FakeMessagesServer(
          api: {'me': (_) => jsonBody({}, status: 401)},
        );
        final f = fakeMessagesClient(server);
        await expectLater(
          f.client.get('me'),
          throwsA(isA<MessagesSessionExpiredException>()),
        );
        expect(server.bootstraps, 2);
      },
    );

    test('403 po odnowieniu = brak uprawnień', () async {
      final server = FakeMessagesServer(
        api: {'receivers/student-subjects': (_) => jsonBody({}, status: 403)},
      );
      final f = fakeMessagesClient(server);
      await expectLater(
        f.client.get('receivers/student-subjects'),
        throwsA(isA<PermissionDeniedException>()),
      );
    });

    test('błędy HTTP i sieci', () async {
      final f404 = fakeMessagesClient(FakeMessagesServer());
      await expectLater(
        f404.client.get('alerts/messages'),
        throwsA(isA<ServerException>()),
      );

      final f429 = fakeMessagesClient(
        FakeMessagesServer(api: {'me': (_) => jsonBody({}, status: 429)}),
      );
      await expectLater(
        f429.client.get('me'),
        throwsA(isA<RateLimitedException>()),
      );

      final fHtml = fakeMessagesClient(
        FakeMessagesServer(api: {'me': (_) => textBody('<html>')}),
      );
      await expectLater(
        fHtml.client.get('me'),
        throwsA(isA<UnexpectedResponseException>()),
      );

      final offline = MessagesApiClient(
        synergiaSession: fakeMessagesClient(FakeMessagesServer()).store,
        dio: fakeDio(
          FakeAdapter((_) => throw const SocketException('offline')),
        ),
        minInterval: Duration.zero,
      );
      await expectLater(offline.get('me'), throwsA(isA<NetworkException>()));

      final slow = MessagesApiClient(
        synergiaSession: fakeMessagesClient(FakeMessagesServer()).store,
        dio: fakeDio(
          FakeAdapter(
            (o) => throw DioException.receiveTimeout(
              timeout: const Duration(seconds: 20),
              requestOptions: o,
            ),
          ),
        ),
        minInterval: Duration.zero,
      );
      await expectLater(
        slow.get('me'),
        throwsA(isA<RequestTimeoutException>()),
      );
    });

    test('reset() zapomina sesję wiadomości', () async {
      final server = FakeMessagesServer(api: {'me': (_) => jsonBody({})});
      final f = fakeMessagesClient(server);
      await f.client.get('me');
      f.client.reset();
      expect(f.client.hasSession, isFalse);
      await f.client.get('me');
      expect(server.bootstraps, 2);
    });
  });

  test("HTTP 429 przekazuje Retry-After (regresja)", () async {
    final f = fakeMessagesClient(
      FakeMessagesServer(
        api: {
          "me": (_) => jsonBody(
            {},
            status: 429,
            headers: {
              "retry-after": ["90"],
            },
          ),
        },
      ),
    );
    await expectLater(
      f.client.get("me"),
      throwsA(
        isA<RateLimitedException>().having(
          (e) => e.retryAfter,
          "retryAfter",
          const Duration(seconds: 90),
        ),
      ),
    );
  });

  group('POST', () {
    test(
      'jedno żądanie, bez ponowienia przy 500 i bez odnawiania przy 401',
      () async {
        for (final status in [500, 401]) {
          final server = FakeMessagesServer(
            api: {
              'me': (_) => jsonBody({}),
              'messages': (_) => jsonBody({}, status: status),
            },
          );
          final f = fakeMessagesClient(server);
          await f.client.ensureSession();
          final r = await f.client.postOnce('messages', {'a': 1});
          expect(r.statusCode, status);
          expect(
            server.calls.where(
              (c) => c == 'POST wiadomosci.librus.pl/api/messages',
            ),
            hasLength(1),
          );
          expect(server.bootstraps, 1);
        }
      },
    );

    test(
      'przekroczenie czasu połączenia = na pewno nie wysłano; po wysłaniu = nie wiadomo',
      () async {
        Future<SendTransportException> failWith(DioExceptionType type) async {
          final store = fakeMessagesClient(FakeMessagesServer()).store;
          final client = MessagesApiClient(
            synergiaSession: store,
            dio: fakeDio(
              FakeAdapter(
                (o) => throw DioException(requestOptions: o, type: type),
              ),
            ),
            minInterval: Duration.zero,
          );
          try {
            await client.postOnce('messages', {});
          } on SendTransportException catch (e) {
            return e;
          }
          fail('oczekiwano SendTransportException');
        }

        expect(
          (await failWith(
            DioExceptionType.connectionTimeout,
          )).requestMayHaveReachedServer,
          isFalse,
        );
        for (final t in [
          DioExceptionType.sendTimeout,
          DioExceptionType.receiveTimeout,
          DioExceptionType.connectionError,
          DioExceptionType.unknown,
        ]) {
          expect(
            (await failWith(t)).requestMayHaveReachedServer,
            isTrue,
            reason: t.name,
          );
        }
      },
    );

    test('ścieżki absolutne są odrzucane bez żądania', () async {
      final f = fakeMessagesClient(FakeMessagesServer());
      expect(() => f.client.get('https://evil.example/x'), throwsArgumentError);
      expect(() => f.client.postOnce('/messages', {}), throwsArgumentError);
      expect(f.adapter.requests, isEmpty);
    });
  });
}
