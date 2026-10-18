import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/network/web_cookie.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/diagnostics/data/integration_probe.dart';
import 'package:synergia_lite/features/diagnostics/domain/diagnostic_report.dart';

import '../../helpers/fake_http.dart';

/// Wartości, które nie mogą pojawić się w raporcie.
const _secrets = [
  'COOKIE_SECRET_1',
  'TOKEN_SECRET_2',
  'Wiktoria',
  'Sekretna',
  'NauczycielX',
  'zw-SENTINEL',
  'KONTO_LOGIN_X',
  'SALA-SENTINEL',
];

final _webCookies = [
  WebCookie.parse(
    'DZIENNIKSID=COOKIE_SECRET_1; Domain=synergia.librus.pl; Path=/; Secure; HttpOnly',
  )!,
  WebCookie.parse(
    'oauth_token=TOKEN_SECRET_2; Path=/; Secure; HttpOnly; SameSite=Lax',
  )!,
];

ResponseBody _livingAccount(RequestOptions o) {
  final authed = o.headers.containsKey('Cookie');
  if (!authed) {
    return jsonBody({
      'Status': 'Error',
      'Message': 'Request is denied',
    }, status: 401);
  }
  return switch (o.path) {
    'Me' => jsonBody({
      'Me': {
        'Account': {
          'FirstName': 'Wiktoria',
          'LastName': 'Sekretna',
          'Login': 'KONTO_LOGIN_X',
        },
        'User': {'FirstName': 'Wiktoria', 'LastName': 'Sekretna'},
      },
    }),
    'Auth/TokenInfo' => jsonBody({
      'UserIdentifier': 'TOKEN_SECRET_2',
      'UserIdentifiers': [],
    }),
    'Grades' => jsonBody({
      'Grades': [
        {
          'Id': 1,
          'Subject': {'Id': 11},
          'Category': {'Id': 21},
          'Grade': 'zw-SENTINEL',
          'Semester': 1,
        },
        {
          'Id': 2,
          'Subject': {'Id': 11},
          'Category': {'Id': 21},
          'Grade': '5',
          'IsSemester': true,
        },
      ],
    }),
    final p when p.startsWith('Grades/Categories/') => jsonBody({
      'Categories': [
        {
          'Id': 21,
          'Name': 'Sprawdzian',
          'Weight': 3,
          'CountToTheAverage': true,
        },
      ],
    }),
    final p when p.startsWith('Subjects/') => jsonBody({
      'Subjects': [
        {'Id': 11, 'Name': 'Matematyka'},
      ],
    }),
    'Timetables' => jsonBody({
      'Timetable': {
        '2026-10-12': [
          [],
          [
            {
              'LessonNo': '1',
              'Subject': {'Name': 'Matematyka'},
              'Teacher': {'FirstName': 'NauczycielX', 'LastName': 'Y'},
              'Classroom': {'Symbol': 'SALA-SENTINEL'},
              'IsCanceled': true,
            },
          ],
        ],
      },
    }),
    _ => jsonBody({}, status: 404),
  };
}

void main() {
  final now = DateTime(2026, 10, 14, 12);

  Future<(DiagnosticReport, FakeAdapter)> run(
    ResponseBody Function(RequestOptions) handler, {
    List<WebCookie>? cookies,
  }) async {
    final adapter = FakeAdapter(handler);
    final api = SynergiaApiClient(
      sessionStore: InMemorySessionStore(
        SessionCookies.fromWebCookies(cookies ?? _webCookies),
      ),
      dio: fakeDio(adapter),
      minInterval: Duration.zero,
    );
    final report = await IntegrationProbe(api, clock: () => now).run(
      webCookies: cookies ?? _webCookies,
      landingUrl: 'https://synergia.librus.pl/rodzic/index',
    );
    return (report, adapter);
  }

  DiagnosticCheck check(DiagnosticReport r, String prefix) =>
      r.checks.firstWhere((c) => c.title.startsWith(prefix));

  test('uwierzytelniona sesja: Me z kontem + kontrola negatywna 401', () async {
    final (report, adapter) = await run(_livingAccount);
    expect(report.verdict, AuthVerdict.authenticated);
    expect(check(report, 'Oceny').status, CheckStatus.ok);
    expect(
      check(report, 'Oceny').facts,
      contains('rekordów: 2, odczytanych: 2'),
    );
    expect(check(report, 'Plan').facts, contains('odwołane: 1, zastępstwa: 0'));
    expect(check(report, 'Plan').facts, contains('tydzień od 2026-10-12'));
    final negative = adapter.requests.firstWhere(
      (r) => !r.headers.containsKey('Cookie'),
    );
    expect(negative.path, 'Me');
  });

  test(
    'raport nie zawiera wartości ciasteczek, tokenów ani danych ucznia',
    () async {
      final (report, _) = await run(_livingAccount);
      final text = report.toText();
      for (final secret in _secrets) {
        expect(text, isNot(contains(secret)), reason: secret);
      }
      expect(text, contains('oauth_token'));
      expect(text, contains('klucze Me: Account, User'));
    },
  );

  test('Me odpowiada bez sesji → wynik niejednoznaczny', () async {
    final (report, _) = await run(
      (o) => o.path == 'Me'
          ? jsonBody({
              'Me': {'Account': {}},
            })
          : _livingAccount(o),
    );
    expect(report.verdict, AuthVerdict.inconclusive);
    expect(check(report, 'Kontrola').status, CheckStatus.failed);
  });

  test(
    'Me odrzucone → brak uwierzytelnienia i brak dalszych zapytań o dane',
    () async {
      final (report, adapter) = await run(
        (o) => o.path == 'Auth/TokenInfo'
            ? jsonBody({})
            : jsonBody({}, status: 401),
      );
      expect(report.verdict, AuthVerdict.notAuthenticated);
      expect(check(report, 'Uwierzytelnienie').facts.single, contains('401'));
      expect(adapter.requests.map((r) => r.path), isNot(contains('Grades')));
    },
  );

  test('Me 200 bez obiektu konta to nie jest uwierzytelnienie', () async {
    final (report, _) = await run(
      (o) => o.headers.containsKey('Cookie')
          ? jsonBody({'Me': {}})
          : jsonBody({}, status: 401),
    );
    expect(report.verdict, AuthVerdict.notAuthenticated);
  });

  test('zmieniony format ocen jest raportowany jako błąd', () async {
    final (report, _) = await run(
      (o) => o.path == 'Grades' ? jsonBody({'Oceny': []}) : _livingAccount(o),
    );
    expect(report.verdict, AuthVerdict.authenticated);
    final grades = check(report, 'Oceny');
    expect(grades.status, CheckStatus.failed);
    expect(grades.facts.single, contains('nieoczekiwany format'));
    expect(grades.facts.single, contains('Oceny'));
  });

  test('brak ciasteczek i brak oauth_token są widoczne', () async {
    final (empty, _) = await run(_livingAccount, cookies: const []);
    expect(check(empty, 'Ciasteczka').status, CheckStatus.failed);
    final (noMarker, _) = await run(
      _livingAccount,
      cookies: [WebCookie.parse('DZIENNIKSID=x')!],
    );
    expect(check(noMarker, 'Ciasteczka').status, CheckStatus.warning);
  });

  test('limit zapytań jest opisany bez treści odpowiedzi', () async {
    final (report, _) = await run(
      (o) => o.path == 'Grades'
          ? jsonBody(
              {'detail': 'TOKEN_SECRET_2'},
              status: 429,
              headers: {
                'retry-after': ['60'],
              },
            )
          : _livingAccount(o),
    );
    expect(
      check(report, 'Oceny').facts.single,
      'limit zapytań (Retry-After: 60 s)',
    );
    expect(report.toText(), isNot(contains('TOKEN_SECRET_2')));
  });
}
