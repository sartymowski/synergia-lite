import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/excuses/data/excuse_submitter.dart';
import 'package:synergia_lite/features/excuses/data/excuses_parser.dart';
import 'package:synergia_lite/features/excuses/data/excuses_repository.dart';
import 'package:synergia_lite/features/excuses/domain/excuse.dart';
import 'package:synergia_lite/features/excuses/domain/excuse_submission.dart';
import 'package:synergia_lite/features/excuses/presentation/excuse_form_controller.dart';
import 'package:synergia_lite/features/timetable/data/timetable_parser.dart';

import '../../helpers/fake_http.dart';

/// Fikcyjna strona formularza o strukturze ustalonej 2026-10-19 (token zmyślony).
const formPage = '''
<form id="formUsprawiedliwienie" method="post" action="/eusprawiedliwienia/dodaj" enctype="multipart/form-data">
  <input type="hidden" name="requestkey" value="FIKCYJNY_TOKEN_72">
  <input type="hidden" name="dodajUsprawiedliwienieDo" value="1">
  <input type="radio" name="datyLubLekcje" id="wgDat" value="wgDat">
  <input type="radio" name="datyLubLekcje" id="wgGodzin" value="wgGodzin">
  <input type="text" name="dataOd" id="dataOd"><input type="text" name="dataDo" id="dataDo">
  <textarea name="powodNieobecnosci" id="powodNieobecnosci"></textarea>
  <input type="file" name="attachment">
  <input type="checkbox" name="powiadomInnych" id="powiadomInnych" value="1">
  <input type="button" id="usprawiedliwNieobecnosc" value="Wyślij usprawiedliwienie">
</form>''';

Map<String, Object?> justification(
  int id,
  String from,
  String to, {
  String status = 'send',
}) => {
  'id': id,
  'justificationStatus': status,
  'dateFrom': from,
  'dateTo': to,
  'postDate': '2026-10-19 10:00:00',
  'messageFromParent': 'fikcyjne',
  'lessons': [],
};

/// Symulowana Synergia: historia, strona formularza i (opcjonalnie) przyjęcie zgłoszenia.
class FakeSynergia {
  FakeSynergia({this.page = formPage, this.onPost});

  String page;
  ResponseBody Function(RequestOptions)? onPost;
  final history = <Map<String, Object?>>[
    justification(1, '2026-10-01', '2026-10-02', status: 'accept'),
  ];
  final posts = <RequestOptions>[];

  FutureOr<ResponseBody> handle(RequestOptions o) {
    if (o.path == 'Justifications') {
      return jsonBody({'status': 'OK', 'data': history});
    }
    if (o.path == 'Me') {
      return jsonBody({
        'Me': {'Account': {}},
      });
    }
    if (o.path == 'https://synergia.librus.pl/eusprawiedliwienia/dodaj' &&
        o.method == 'GET') {
      return textBody(page);
    }
    if (o.path == 'https://synergia.librus.pl/eusprawiedliwienia/dodaj' &&
        o.method == 'POST') {
      posts.add(o);
      return onPost?.call(o) ?? textBody('<html>ok</html>');
    }
    return jsonBody({}, status: 404);
  }

  ExcuseSubmitter submitter({DateTime? now}) {
    final api = SynergiaApiClient(
      sessionStore: InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'})),
      dio: fakeDio(FakeAdapter(handle)),
      minInterval: Duration.zero,
    );
    return ExcuseSubmitter(
      api,
      ExcusesRepository(api),
      verifyDelay: Duration.zero,
      clock: () => now ?? DateTime(2026, 10, 19, 9),
    );
  }
}

const days = ExcuseSubmission(mode: ExcuseMode.days, from: null, to: null);

ExcuseSubmission daysFrom(DateTime f, DateTime t, {bool notify = false}) =>
    days.copyWith(
      from: f,
      to: t,
      reason: 'Choroba (fikcyjne)',
      notifyTeachers: notify,
    );

void main() {
  final today = DateTime(2026, 10, 19, 9);

  group('status z API', () {
    test('send = „Wysłane”, accept = „Usprawiedliwione”, inne dosłownie', () {
      expect(ExcuseStatus.fromApi('send'), const ExcuseSent());
      expect(ExcuseStatus.fromApi('send').label, 'Wysłane');
      expect(ExcuseStatus.fromApi('accept').label, 'Usprawiedliwione');
      expect(
        ExcuseStatus.fromApi('reject').label,
        'Status: reject',
        reason: 'nie zgadujemy',
      );
    });

    test('zgłoszenie bez lekcji i z lekcją bez numeru', () {
      final list = ExcusesParser.list({
        'status': 'OK',
        'data': [
          justification(1, '2026-10-01', '2026-10-02'),
          {
            ...justification(2, '2026-10-05', '2026-10-05'),
            'lessons': [
              {'date': '2026-10-05'},
            ],
          },
        ],
      });
      expect(list.firstWhere((e) => e.id == 1).isLessonBased, isFalse);
      expect(list.firstWhere((e) => e.id == 2).lessons.single.number, isNull);
    });
  });

  group('walidacja (reguły strony + uzasadnienie)', () {
    test('pełny dzień, zakres dat i lekcje', () {
      expect(
        validateExcuse(
          daysFrom(DateTime(2026, 10, 12), DateTime(2026, 10, 12)),
          today: today,
        ),
        isEmpty,
      );
      expect(
        validateExcuse(
          daysFrom(DateTime(2026, 10, 12), DateTime(2026, 10, 16)),
          today: today,
        ),
        isEmpty,
      );
      final lessons = ExcuseSubmission(
        mode: ExcuseMode.lessons,
        from: DateTime(2026, 10, 12),
        to: DateTime(2026, 10, 20),
        lessonNumbers: const {3},
        reason: 'x',
      );
      expect(validateExcuse(lessons, today: today), isEmpty);
      expect(
        lessons.effectiveTo,
        DateTime(2026, 10, 12),
        reason: 'dataDo = dataOd',
      );
    });

    test('niepoprawny zakres, brak dat, brak lekcji, brak uzasadnienia', () {
      expect(
        validateExcuse(
          daysFrom(DateTime(2026, 10, 16), DateTime(2026, 10, 12)),
          today: today,
        ),
        [ExcuseProblem.invalidRange],
      );
      expect(validateExcuse(days.copyWith(reason: 'x'), today: today), [
        ExcuseProblem.noDates,
      ]);
      expect(
        validateExcuse(
          ExcuseSubmission(
            mode: ExcuseMode.lessons,
            from: DateTime(2026, 10, 12),
            to: null,
            reason: 'x',
          ),
          today: today,
        ),
        [ExcuseProblem.noLessons],
      );
      expect(
        validateExcuse(
          daysFrom(
            DateTime(2026, 10, 12),
            DateTime(2026, 10, 12),
          ).copyWith(reason: '  '),
          today: today,
        ),
        [ExcuseProblem.noReason],
      );
    });

    test('planowana nieobecność i powiadomienie nauczycieli', () {
      final future = daysFrom(
        DateTime(2026, 10, 22),
        DateTime(2026, 10, 23),
        notify: true,
      );
      expect(future.isPlanned(today), isTrue);
      expect(validateExcuse(future, today: today), isEmpty);
      expect(
        daysFrom(
          DateTime(2026, 10, 19),
          DateTime(2026, 10, 19),
        ).isPlanned(today),
        isTrue,
        reason: 'dziś',
      );
      final past = daysFrom(
        DateTime(2026, 10, 1),
        DateTime(2026, 10, 2),
        notify: true,
      );
      expect(validateExcuse(past, today: today), [
        ExcuseProblem.notifyNotAllowed,
      ]);
    });
  });

  group('kontrakt formularza', () {
    test('zgodna strona → token i stałe ze strony', () {
      final (c, problems) = ExcuseFormContract.parse(formPage);
      expect(problems, isEmpty);
      expect(c!.target, '1');
    });

    test('zmieniona struktura lub brak dostępu → brak kontraktu', () {
      expect(ExcuseFormContract.parse('<p>Brak dostępu</p>').$2, [
        'Brak dostępu do modułu',
      ]);
      expect(
        ExcuseFormContract.parse(formPage.replaceAll('requestkey', 'csrf')).$2,
        contains('brak requestkey'),
      );
      expect(
        ExcuseFormContract.parse(formPage.replaceAll('wgGodzin', 'x')).$2,
        contains('opcje datyLubLekcje'),
      );
      expect(
        ExcuseFormContract.parse(
          formPage.replaceAll(
            'action="/eusprawiedliwienia/dodaj"',
            'action="https://evil.example/x"',
          ),
        ).$2,
        contains('adres formularza'),
      );
    });

    test(
      'pola żądania: lekcje jako usprawiedliwienie[data][], dataDo = dataOd, bez pustych pól',
      () {
        final (c, _) = ExcuseFormContract.parse(formPage);
        final form = c!.toFormData(
          ExcuseSubmission(
            mode: ExcuseMode.lessons,
            from: DateTime(2026, 10, 19),
            to: DateTime(2026, 10, 25),
            lessonNumbers: const {5, 3},
            reason: '  Wizyta  ',
            notifyTeachers: true,
          ),
        );
        expect(
          form.fields.map(
            (e) => '${e.key}=${e.key == 'requestkey' ? '…' : e.value}',
          ),
          [
            'requestkey=…',
            'dodajUsprawiedliwienieDo=1',
            'datyLubLekcje=wgGodzin',
            'dataOd=2026-10-19',
            'dataDo=2026-10-19',
            'usprawiedliwienie[2026-10-19][]=3',
            'usprawiedliwienie[2026-10-19][]=5',
            'powodNieobecnosci=Wizyta',
            'powiadomInnych=1',
          ],
        );
        final daysForm = c.toFormData(
          daysFrom(DateTime(2026, 10, 1), DateTime(2026, 10, 3)),
        );
        expect(
          daysForm.fields.map((e) => e.key),
          isNot(contains('powiadomInnych')),
        );
        expect(
          daysForm.fields.firstWhere((e) => e.key == 'datyLubLekcje').value,
          'wgDat',
        );
      },
    );
  });

  group('wysyłanie (mock, nigdy prawdziwy serwer)', () {
    final sub = daysFrom(DateTime(2026, 10, 12), DateTime(2026, 10, 13));

    test('przyjęcie potwierdzone historią, nie kodem 200', () async {
      final s = FakeSynergia();
      s.onPost = (_) {
        s.history.add(justification(9, '2026-10-12', '2026-10-13'));
        return textBody('<html>dziękujemy</html>');
      };
      final o = await s.submitter().submit(sub);
      expect(o, isA<ExcuseSubmitted>().having((x) => x.created.id, 'id', 9));
      expect(s.posts, hasLength(1));
      expect(s.posts.single.headers['Referer'], ExcuseFormContract.formUrl);
    });

    test('HTTP 200 bez nowego wpisu w historii = nie wiadomo', () async {
      final s = FakeSynergia();
      final o = await s.submitter().submit(sub);
      expect(o, isA<ExcuseUncertain>());
      expect(s.posts, hasLength(1), reason: 'bez ponowienia POST');
    });

    test('nowy wpis o innym zakresie nie jest potwierdzeniem', () async {
      final s = FakeSynergia();
      s.onPost = (_) {
        s.history.add(justification(9, '2026-09-01', '2026-09-01'));
        return textBody('ok');
      };
      expect(await s.submitter().submit(sub), isA<ExcuseUncertain>());
    });

    test('CSRF/kontrakt: zmieniony formularz → brak POST', () async {
      final s = FakeSynergia(page: formPage.replaceAll('requestkey', 'token'));
      expect(await s.submitter().submit(sub), isA<ExcuseNotSent>());
      expect(s.posts, isEmpty);
    });

    test('brak dostępu do modułu → brak POST', () async {
      final s = FakeSynergia(page: '<p>Brak dostępu</p>');
      expect(await s.submitter().submit(sub), isA<ExcuseNotSent>());
      expect(s.posts, isEmpty);
    });

    test(
      'błędy HTTP po wysłaniu: 401/403/przekierowanie na logowanie = nie przyjęto',
      () async {
        for (final r in [
          () => jsonBody({}, status: 401),
          () => jsonBody({}, status: 403),
          () => ResponseBody.fromString(
            '',
            302,
            headers: {
              'location': ['https://synergia.librus.pl/loguj'],
            },
          ),
        ]) {
          final s = FakeSynergia(onPost: (_) => r());
          expect(await s.submitter().submit(sub), isA<ExcuseNotSent>());
          expect(s.posts, hasLength(1));
        }
      },
    );

    test(
      '400, 429, 500 = nie wiadomo (sprawdź historię), bez ponowienia',
      () async {
        for (final status in [400, 429, 500]) {
          final s = FakeSynergia(onPost: (_) => jsonBody({}, status: status));
          expect(
            await s.submitter().submit(sub),
            isA<ExcuseUncertain>(),
            reason: '$status',
          );
          expect(s.posts, hasLength(1));
        }
      },
    );

    test(
      'timeout po wysłaniu = nie wiadomo; brak połączenia przed = nie wysłano',
      () async {
        final late = FakeSynergia(
          onPost: (o) => throw DioException.receiveTimeout(
            timeout: const Duration(seconds: 20),
            requestOptions: o,
          ),
        );
        expect(await late.submitter().submit(sub), isA<ExcuseUncertain>());
        final early = FakeSynergia(
          onPost: (o) => throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 10),
            requestOptions: o,
          ),
        );
        expect(await early.submitter().submit(sub), isA<ExcuseNotSent>());
      },
    );

    test(
      'timeout po wysłaniu, ale wpis pojawił się w historii = przyjęte',
      () async {
        final s = FakeSynergia();
        s.onPost = (o) {
          s.history.add(justification(9, '2026-10-12', '2026-10-13'));
          throw DioException.receiveTimeout(
            timeout: const Duration(seconds: 20),
            requestOptions: o,
          );
        };
        expect(await s.submitter().submit(sub), isA<ExcuseSubmitted>());
      },
    );

    test('błędna sesja przed wysłaniem = brak POST', () async {
      final s = FakeSynergia();
      final api = SynergiaApiClient(
        sessionStore: InMemorySessionStore(),
        dio: fakeDio(FakeAdapter(s.handle)),
        minInterval: Duration.zero,
      );
      final o = await ExcuseSubmitter(
        api,
        ExcusesRepository(api),
        verifyDelay: Duration.zero,
      ).submit(sub);
      expect(o, isA<ExcuseNotSent>());
      expect(s.posts, isEmpty);
    });
  });

  group('kontroler formularza', () {
    test(
      'domyślnie natywne wysyłanie jest wyłączone — nic nie wysyła',
      () async {
        expect(ExcuseSubmitPolicy.nativeSubmitEnabled, isFalse);
        var calls = 0;
        final c = ExcuseFormController(
          submit: (_) async {
            calls++;
            return const ExcuseNotSent('x');
          },
          clock: () => today,
        );
        c
          ..setRange(DateTime(2026, 10, 12), DateTime(2026, 10, 12))
          ..setReason('x');
        expect(await c.send(), isNull);
        expect(calls, 0);
      },
    );

    test(
      'blokada podwójnego wysłania i potwierdzenie po wyniku niejednoznacznym',
      () async {
        final pending = Completer<ExcuseSubmitOutcome>();
        var calls = 0;
        final c = ExcuseFormController(
          submit: (_) {
            calls++;
            return calls == 1
                ? pending.future
                : Future.value(const ExcuseNotSent('x'));
          },
          submitEnabled: true,
          clock: () => today,
        );
        c
          ..setRange(DateTime(2026, 10, 12), DateTime(2026, 10, 12))
          ..setReason('x');
        final first = c.send();
        expect(c.isSending, isTrue);
        expect(await c.send(), isNull);
        pending.complete(const ExcuseUncertain('?'));
        await first;
        expect(c.status, ExcuseFormStatus.uncertain);
        expect(await c.send(), isNull, reason: 'wymaga potwierdzenia');
        expect(calls, 1);
        await c.send(confirmedAfterUncertain: true);
        expect(calls, 2);
      },
    );

    test(
      'zmiana dat na przeszłe wyłącza powiadomienie; tryb lekcji czyści wybór',
      () {
        final c = ExcuseFormController(
          submit: (_) async => const ExcuseNotSent('x'),
          clock: () => today,
        );
        c
          ..setRange(DateTime(2026, 10, 22), DateTime(2026, 10, 22))
          ..setNotifyTeachers(true);
        expect(c.submission.notifyTeachers, isTrue);
        c.setRange(DateTime(2026, 10, 1), DateTime(2026, 10, 1));
        expect(c.submission.notifyTeachers, isFalse);
        c
          ..setMode(ExcuseMode.lessons)
          ..setDay(DateTime(2026, 10, 12))
          ..toggleLesson(3)
          ..toggleLesson(4)
          ..toggleLesson(3);
        expect(c.submission.lessonNumbers, {4});
        c.setDay(DateTime(2026, 10, 13));
        expect(c.submission.lessonNumbers, isEmpty);
      },
    );
  });

  test(
    'lekcje z planu: numer + przedmioty, grupy łączone, odwołane oznaczone',
    () {
      final week = TimetableParser.week({
        'Timetable': {
          '2026-10-19': [
            [],
            [],
            [],
            [
              {
                'LessonNo': '3',
                'Subject': {'Name': 'Matematyka'},
              },
            ],
            [
              {
                'LessonNo': '4',
                'Subject': {'Name': 'Język angielski'},
              },
              {
                'LessonNo': '4',
                'Subject': {'Name': 'Język niemiecki'},
              },
            ],
            [
              {
                'LessonNo': '5',
                'Subject': {'Name': 'Biologia'},
                'IsCanceled': true,
              },
            ],
          ],
        },
      }, DateTime(2026, 10, 19));
      final lessons = lessonsOn(week, DateTime(2026, 10, 19));
      expect(lessons.map((l) => '${l.number}:${l.subjects}:${l.canceled}'), [
        '3:Matematyka:false',
        '4:Język angielski / Język niemiecki:false',
        '5:Biologia:true',
      ]);
      expect(lessonsOn(week, DateTime(2026, 10, 20)), isEmpty);
    },
  );
}
