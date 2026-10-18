import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';

import '../helpers/fake_http.dart';

void main() {
  late InMemorySessionStore store;

  setUp(
    () => store = InMemorySessionStore(SessionCookies({'DZIENNIKSID': 's1'})),
  );

  SynergiaApiClient client(FakeAdapter adapter, {Duration? minInterval}) =>
      SynergiaApiClient(
        sessionStore: store,
        dio: fakeDio(adapter),
        minInterval: minInterval ?? Duration.zero,
      );

  test('bez sesji nie wysyła żądania i zgłasza wygaśnięcie', () async {
    store.session = null;
    final adapter = FakeAdapter((_) => jsonBody({}));
    await expectLater(
      client(adapter).get('Me'),
      throwsA(isA<SessionExpiredException>()),
    );
    expect(adapter.requests, isEmpty);
  });

  test('wysyła ciasteczka, nagłówki i selektor identyfikatorów', () async {
    final adapter = FakeAdapter((_) => jsonBody({'Users': []}));
    final json = await client(
      adapter,
    ).get('Users', ids: [3, 1, 3], query: {'a': 'b'});
    expect(json, {'Users': []});
    final r = adapter.requests.single;
    expect(r.uri.toString(), '${SynergiaApiClient.baseUrl}Users/3,1?a=b');
    expect(r.headers['Cookie'], 'DZIENNIKSID=s1');
    expect(r.headers['Accept'], 'application/json');
    expect(r.followRedirects, isFalse);
  });

  for (final status in [401, 403, 302]) {
    test('HTTP $status oznacza utratę sesji', () async {
      final adapter = FakeAdapter(
        (_) => jsonBody({
          'Status': 'Error',
          'Message': 'Request is denied',
        }, status: status),
      );
      await expectLater(
        client(adapter).get('Me'),
        throwsA(isA<SessionExpiredException>()),
      );
    });
  }

  test('HTTP 429 przekazuje Retry-After i nie ponawia', () async {
    final adapter = FakeAdapter(
      (_) => jsonBody(
        {},
        status: 429,
        headers: {
          'retry-after': ['30'],
        },
      ),
    );
    await expectLater(
      client(adapter).get('Grades'),
      throwsA(
        isA<RateLimitedException>().having(
          (e) => e.retryAfter,
          'retryAfter',
          const Duration(seconds: 30),
        ),
      ),
    );
    expect(adapter.requests, hasLength(1));
  });

  test('HTTP 500 to błąd serwera', () async {
    final adapter = FakeAdapter((_) => jsonBody({}, status: 500));
    await expectLater(
      client(adapter).get('Grades'),
      throwsA(
        isA<ServerException>().having((e) => e.statusCode, 'status', 500),
      ),
    );
  });

  test('HTML zamiast JSON to nieoczekiwana odpowiedź', () async {
    final adapter = FakeAdapter((_) => textBody('<html>logowanie</html>'));
    await expectLater(
      client(adapter).get('Grades'),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });

  test('Status=Error w treści 200 to nieoczekiwana odpowiedź', () async {
    final adapter = FakeAdapter(
      (_) => jsonBody({'Status': 'Error', 'Code': 'X'}),
    );
    await expectLater(
      client(adapter).get('Grades'),
      throwsA(
        isA<UnexpectedResponseException>().having(
          (e) => e.detail,
          'detail',
          contains('Code=X'),
        ),
      ),
    );
  });

  test('timeout jest rozpoznawany', () async {
    final adapter = FakeAdapter(
      (o) => throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 10),
        requestOptions: o,
      ),
    );
    await expectLater(
      client(adapter).get('Me'),
      throwsA(isA<RequestTimeoutException>()),
    );
  });

  test('błąd gniazda to brak połączenia', () async {
    final adapter = FakeAdapter((_) => throw const SocketException('offline'));
    await expectLater(
      client(adapter).get('Me'),
      throwsA(isA<NetworkException>()),
    );
  });

  test('rotacja ciasteczek jest zapisywana i używana dalej', () async {
    var call = 0;
    final adapter = FakeAdapter((_) {
      call++;
      return jsonBody(
        {'Me': {}},
        headers: call == 1
            ? {
                'set-cookie': ['DZIENNIKSID=s2; path=/; HttpOnly'],
              }
            : {},
      );
    });
    final api = client(adapter);
    await api.get('Me');
    await api.get('Me');
    expect(store.session!.toHeader(), 'DZIENNIKSID=s2');
    expect(adapter.requests.last.headers['Cookie'], 'DZIENNIKSID=s2');
  });

  test('żądania idą po kolei z minimalnym odstępem', () async {
    final starts = <DateTime>[];
    final adapter = FakeAdapter((_) {
      starts.add(DateTime.now());
      return jsonBody({});
    });
    final api = client(adapter, minInterval: const Duration(milliseconds: 60));
    await Future.wait([api.get('A'), api.get('B'), api.get('C')]);
    expect(adapter.requests.map((r) => r.path), ['A', 'B', 'C']);
    for (var i = 1; i < starts.length; i++) {
      expect(
        starts[i].difference(starts[i - 1]),
        greaterThanOrEqualTo(const Duration(milliseconds: 50)),
      );
    }
  });

  test('błąd jednego żądania nie blokuje kolejki', () async {
    var call = 0;
    final adapter = FakeAdapter(
      (_) => ++call == 1 ? jsonBody({}, status: 500) : jsonBody({'ok': 1}),
    );
    final api = client(adapter);
    await expectLater(api.get('A'), throwsA(isA<ServerException>()));
    expect(await api.get('B'), {'ok': 1});
  });

  test('wylogowanie zdalne woła /wyloguj i ignoruje błędy', () async {
    final adapter = FakeAdapter((o) => throw const SocketException('offline'));
    await client(adapter).endRemoteSession();
    expect(adapter.requests.single.uri.toString(), SynergiaApiClient.logoutUrl);
  });

  group('ochrona ciasteczek', () {
    for (final path in [
      'https://example.com/Me',
      '//example.com/Me',
      '/Me',
      '../Me',
    ]) {
      test('odrzuca ścieżkę "$path" bez wysyłania żądania', () async {
        final adapter = FakeAdapter((_) => jsonBody({}));
        expect(() => client(adapter).get(path), throwsArgumentError);
        expect(
          () => client(adapter).statusWithoutSession(path),
          throwsArgumentError,
        );
        expect(adapter.requests, isEmpty);
      });
    }

    test('kontrola negatywna nie wysyła ciasteczek', () async {
      final adapter = FakeAdapter((_) => jsonBody({}, status: 401));
      expect(await client(adapter).statusWithoutSession('Me'), 401);
      expect(adapter.requests.single.headers.containsKey('Cookie'), isFalse);
    });

    test('kontrola negatywna: brak sieci daje null', () async {
      final adapter = FakeAdapter((_) => throw const SocketException('x'));
      expect(await client(adapter).statusWithoutSession('Me'), isNull);
    });
  });

  group('kody HTTP', () {
    test(
      '404 (moduł wyłączony przez szkołę) to błąd serwera, nie wylogowanie',
      () async {
        final adapter = FakeAdapter((_) => jsonBody({}, status: 404));
        await expectLater(
          client(adapter).get('LuckyNumbers'),
          throwsA(
            isA<ServerException>().having((e) => e.statusCode, 'status', 404),
          ),
        );
        expect(store.session, isNotNull);
      },
    );

    test('503 bez Retry-After to limit bez czasu', () async {
      final adapter = FakeAdapter((_) => jsonBody({}, status: 503));
      await expectLater(
        client(adapter).get('Grades'),
        throwsA(
          isA<RateLimitedException>().having(
            (e) => e.retryAfter,
            'retryAfter',
            isNull,
          ),
        ),
      );
    });

    test('przekierowanie na stronę logowania to utrata sesji', () async {
      final adapter = FakeAdapter(
        (_) => ResponseBody.fromString(
          '',
          302,
          headers: {
            'location': ['https://synergia.librus.pl/loguj'],
          },
        ),
      );
      await expectLater(
        client(adapter).get('Me'),
        throwsA(isA<SessionExpiredException>()),
      );
    });

    test('pusta treść 200 to nieoczekiwana odpowiedź', () async {
      final adapter = FakeAdapter((_) => textBody(''));
      await expectLater(
        client(adapter).get('Me'),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });

    test('lista JSON zamiast obiektu to nieoczekiwana odpowiedź', () async {
      final adapter = FakeAdapter((_) => jsonBody([1, 2]));
      await expectLater(
        client(adapter).get('Me'),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });

    test('receive timeout jest rozpoznawany', () async {
      final adapter = FakeAdapter(
        (o) => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 20),
          requestOptions: o,
        ),
      );
      await expectLater(
        client(adapter).get('Me'),
        throwsA(isA<RequestTimeoutException>()),
      );
    });

    test('sesja z magazynu jest czytana raz i buforowana', () async {
      final adapter = FakeAdapter((_) => jsonBody({}));
      final api = client(adapter);
      await api.get('A');
      store.session = SessionCookies({'DZIENNIKSID': 'inna'});
      await api.get('B');
      expect(adapter.requests.last.headers['Cookie'], 'DZIENNIKSID=s1');
      api.resetSession();
      await api.get('C');
      expect(adapter.requests.last.headers['Cookie'], 'DZIENNIKSID=inna');
    });
  });
}
