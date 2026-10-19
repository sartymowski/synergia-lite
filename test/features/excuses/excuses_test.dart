import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/app/providers.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/auth/data/auth_repository.dart';
import 'package:synergia_lite/features/excuses/data/excuses_parser.dart';
import 'package:synergia_lite/features/excuses/data/excuses_repository.dart';
import 'package:synergia_lite/features/excuses/domain/excuse.dart';
import 'package:synergia_lite/features/excuses/presentation/excuse_detail_screen.dart';
import 'package:synergia_lite/features/excuses/presentation/excuses_providers.dart';
import 'package:synergia_lite/features/excuses/presentation/excuses_view.dart';

import '../../helpers/fake_http.dart';

/// Fikcyjne zgłoszenia (kształt jak `Justifications`, librus-synergia 10.2026).
Map<String, Object?> item(
  int id, {
  String? status = 'accept',
  String from = '2026-10-06',
  String? to = '2026-10-07',
  String posted = '2026-10-08 07:30:00',
  List<Map<String, Object?>> lessons = const [],
  String reason = 'Wizyta u lekarza (fikcyjne)',
}) => {
  'id': id,
  'messageFromParent': reason,
  'postDate': posted,
  'justificationStatus': status,
  'dateFrom': from,
  'dateTo': to,
  'lessons': lessons,
  'justifiedAbsences': lessons.length,
  'attachment': false,
  'notifiedTeachers': [
    {'name': 'Ewa Przykładowa'},
  ],
};

Map<String, Object?> envelope(List<Map<String, Object?>> data) => {
  'status': 'OK',
  'message': '',
  'data': data,
};

class _NoopCleaner implements WebSessionCleaner {
  @override
  Future<void> clear() async {}
}

void main() {
  group('parser', () {
    test('pusta historia', () {
      expect(ExcusesParser.list(envelope([])), isEmpty);
    });

    test(
      'wiele statusów: potwierdzony, nieznany zachowany dosłownie, brak',
      () {
        final list = ExcusesParser.list(
          envelope([
            item(1),
            item(2, status: 'pending', posted: '2026-10-09 08:00:00'),
            item(3, status: null, posted: '2026-10-01 08:00:00'),
          ]),
        );
        expect(list.map((e) => e.id), [2, 1, 3], reason: 'od najnowszego');
        expect(list[1].status, const ExcuseAccepted());
        expect(list[0].status, const ExcuseStatusOther('pending'));
        expect(
          list[0].status.label,
          'Status: pending',
          reason: 'bez zgadywania znaczenia',
        );
        expect(list[2].status, const ExcuseStatusMissing());
      },
    );

    test('okres całych dni, pojedynczy dzień, lekcje', () {
      final list = ExcusesParser.list(
        envelope([
          item(1),
          item(2, from: '2026-10-10', to: null),
          item(
            3,
            from: '2026-10-12',
            to: '2026-10-12',
            lessons: [
              {'number': 1, 'date': '2026-10-12'},
              {'number': '3', 'date': '2026-10-12'},
            ],
          ),
        ]),
      );
      final byId = {for (final e in list) e.id: e};
      expect(byId[1]!.period!.from, DateTime(2026, 10, 6));
      expect(byId[1]!.period!.to, DateTime(2026, 10, 7));
      expect(byId[1]!.isLessonBased, isFalse);
      expect(byId[2]!.period!.isSingleDay, isTrue);
      expect(byId[3]!.isLessonBased, isTrue);
      expect(byId[3]!.lessons.map((l) => l.number), [1, 3]);
      expect(byId[1]!.notifiedTeachers, ['Ewa Przykładowa']);
      expect(byId[1]!.postedAt, DateTime(2026, 10, 8, 7, 30));
    });

    test('niepoprawny zakres (koniec przed początkiem) jest normalizowany', () {
      final e = ExcusesParser.list(
        envelope([item(1, from: '2026-10-10', to: '2026-10-01')]),
      ).single;
      expect(e.period!.to, e.period!.from);
    });

    test('zmieniony format lub błąd w kopercie jest zgłaszany', () {
      expect(
        () => ExcusesParser.list({'status': 'ERROR', 'data': []}),
        throwsA(isA<UnexpectedResponseException>()),
      );
      expect(
        () => ExcusesParser.list({'Justifications': []}),
        throwsA(isA<UnexpectedResponseException>()),
      );
      expect(
        () => ExcusesParser.list(
          envelope([
            {'bez': 'id'},
          ]),
        ),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('filtry', () {
    final list = ExcusesParser.list(
      envelope([
        item(1, from: '2026-09-01', to: '2026-09-03'),
        item(2, status: 'other', from: '2026-10-06', to: '2026-10-06'),
        item(3, from: '2026-10-20', to: '2026-10-22'),
      ]),
    );

    test('po statusie', () {
      expect(
        const ExcuseFilter(statusKey: 'accept').apply(list).map((e) => e.id),
        unorderedEquals([1, 3]),
      );
      expect(
        const ExcuseFilter(statusKey: 'raw:other').apply(list).map((e) => e.id),
        [2],
      );
    });

    test('po dacie: zakres nachodzący na okres zgłoszenia', () {
      final f = ExcuseFilter(
        from: DateTime(2026, 9, 3),
        to: DateTime(2026, 10, 6),
      );
      expect(f.apply(list).map((e) => e.id), unorderedEquals([1, 2]));
      expect(
        ExcuseFilter(
          from: DateTime(2026, 11, 1),
          to: DateTime(2026, 11, 30),
        ).apply(list),
        isEmpty,
      );
    });

    test('status i data razem; brak filtra', () {
      expect(
        ExcuseFilter(
          statusKey: 'accept',
          from: DateTime(2026, 10, 1),
          to: DateTime(2026, 10, 31),
        ).apply(list).single.id,
        3,
      );
      expect(const ExcuseFilter().isActive, isFalse);
      expect(const ExcuseFilter().apply(list), hasLength(3));
    });
  });

  test(
    'weryfikacja po oficjalnym module: nowe zgłoszenie po identyfikatorze',
    () {
      final before = ExcusesParser.list(envelope([item(1)]));
      final after = ExcusesParser.list(envelope([item(1), item(2)]));
      expect(
        compareHistory(before, after),
        isA<NewExcusesFound>().having((c) => c.newOnes.single.id, 'id', 2),
      );
      expect(compareHistory(after, after), isA<NoNewExcuses>());
    },
  );

  group('repozytorium (sesja Synergii)', () {
    late InMemorySessionStore store;
    setUp(
      () => store = InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'})),
    );

    (ExcusesRepository, FakeAdapter) repo(
      ResponseBody Function(RequestOptions) handler,
    ) {
      final adapter = FakeAdapter(handler);
      return (
        ExcusesRepository(
          SynergiaApiClient(
            sessionStore: store,
            dio: fakeDio(adapter),
            minInterval: Duration.zero,
          ),
        ),
        adapter,
      );
    }

    test('odczyt listy wyłącznie metodą GET', () async {
      final (r, adapter) = repo((_) => jsonBody(envelope([item(1)])));
      expect(await r.fetchAll(), hasLength(1));
      expect(adapter.requests.map((o) => '${o.method} ${o.path}'), [
        'GET Justifications',
      ]);
    });

    test(
      '401/403 przy działającej sesji = moduł niedostępny (bez wylogowania)',
      () async {
        for (final status in [401, 403]) {
          final (r, adapter) = repo(
            (o) => o.path == 'Me'
                ? jsonBody({
                    'Me': {'Account': {}},
                  })
                : jsonBody({}, status: status),
          );
          await expectLater(
            r.fetchAll(),
            throwsA(isA<PermissionDeniedException>()),
            reason: '$status',
          );
          expect(adapter.requests.last.path, 'Me');
        }
      },
    );

    test('błędna sesja (Me też odrzucone) = wygasła sesja', () async {
      final (r, _) = repo((_) => jsonBody({}, status: 401));
      await expectLater(r.fetchAll(), throwsA(isA<SessionExpiredException>()));
    });

    test('400, 429, 500, timeout, brak sieci', () async {
      final (r400, _) = repo((_) => jsonBody({}, status: 400));
      await expectLater(r400.fetchAll(), throwsA(isA<ServerException>()));
      final (r429, _) = repo(
        (_) => jsonBody(
          {},
          status: 429,
          headers: {
            'retry-after': ['30'],
          },
        ),
      );
      await expectLater(r429.fetchAll(), throwsA(isA<RateLimitedException>()));
      final (r500, _) = repo((_) => jsonBody({}, status: 500));
      await expectLater(r500.fetchAll(), throwsA(isA<ServerException>()));
      final (rTimeout, _) = repo(
        (o) => throw DioException.receiveTimeout(
          timeout: const Duration(seconds: 20),
          requestOptions: o,
        ),
      );
      await expectLater(
        rTimeout.fetchAll(),
        throwsA(isA<RequestTimeoutException>()),
      );
      final (rOffline, _) = repo((_) => throw const SocketException('offline'));
      await expectLater(rOffline.fetchAll(), throwsA(isA<NetworkException>()));
    });
  });

  group('widżety', () {
    Widget app(ResponseBody Function(RequestOptions) handler, Widget home) {
      final store = InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'}));
      return ProviderScope(
        retry: (_, _) => null,
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(
            SynergiaApiClient(
              sessionStore: store,
              dio: fakeDio(FakeAdapter(handler)),
              minInterval: Duration.zero,
            ),
          ),
        ],
        child: MaterialApp(home: home),
      );
    }

    testWidgets('pusta historia', (tester) async {
      await tester.pumpWidget(
        app((_) => jsonBody(envelope([])), const ExcusesView()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brak wysłanych e-Usprawiedliwień.'), findsOneWidget);
      expect(find.text('Nowe (Librus)'), findsOneWidget);
    });

    testWidgets('lista, nieznany status i filtr statusu', (tester) async {
      await tester.pumpWidget(
        app(
          (_) => jsonBody(
            envelope([
              item(1),
              item(2, status: 'pending', from: '2026-10-10', to: '2026-10-10'),
            ]),
          ),
          const ExcusesView(),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('06.10.2026 – 07.10.2026'), findsOneWidget);
      expect(find.text('10.10.2026'), findsOneWidget);
      expect(
        find.text('Status: pending'),
        findsNWidgets(2),
        reason: 'chip filtra + status na liście',
      );
      await tester.tap(find.widgetWithText(ChoiceChip, 'Usprawiedliwione'));
      await tester.pumpAndSettle();
      expect(find.text('10.10.2026'), findsNothing);
      expect(find.text('06.10.2026 – 07.10.2026'), findsOneWidget);
    });

    testWidgets('błąd 500 z ponowieniem; moduł niedostępny', (tester) async {
      var fail = true;
      await tester.pumpWidget(
        app(
          (_) =>
              fail ? jsonBody({}, status: 500) : jsonBody(envelope([item(1)])),
          const ExcusesView(),
        ),
      );
      await tester.pumpAndSettle();
      fail = false;
      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();
      expect(find.text('06.10.2026 – 07.10.2026'), findsOneWidget);

      await tester.pumpWidget(
        app(
          (o) => o.path == 'Me'
              ? jsonBody({
                  'Me': {'Account': {}},
                })
              : jsonBody({}, status: 403),
          const ExcusesView(key: ValueKey('b')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('niedostępne dla tego konta'), findsOneWidget);
    });

    testWidgets('szczegóły: lekcje według dni, uzasadnienie, status', (
      tester,
    ) async {
      final e = ExcusesParser.list(
        envelope([
          item(
            5,
            from: '2026-10-12',
            to: '2026-10-12',
            lessons: [
              {'number': 3, 'date': '2026-10-12'},
              {'number': 1, 'date': '2026-10-12'},
            ],
          ),
        ]),
      ).single;
      // Plan lekcji: 1 = Matematyka; lekcji 3 brak w planie → sam numer.
      await tester.pumpWidget(
        app(
          (o) => o.path == 'Timetables'
              ? jsonBody({
                  'Timetable': {
                    '2026-10-12': [
                      [],
                      [
                        {
                          'LessonNo': '1',
                          'Subject': {'Name': 'Matematyka'},
                        },
                      ],
                    ],
                  },
                })
              : jsonBody({}, status: 404),
          ExcuseDetailScreen(excuse: e),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Poniedziałek, 12.10.2026'), findsOneWidget);
      expect(find.text('1. Matematyka\nlekcja 3'), findsOneWidget);
      expect(find.text('Wizyta u lekarza (fikcyjne)'), findsOneWidget);
      expect(
        find.textContaining('Zakres: wybrane lekcje', findRichText: true),
        findsOneWidget,
      );
    });
  });

  test(
    'wylogowanie: brak lokalnych danych, ponowny odczyt bez sesji jest odrzucany',
    () async {
      final store = InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'}));
      final adapter = FakeAdapter((_) => jsonBody(envelope([item(1)])));
      final c = ProviderContainer(
        retry: (_, _) => null,
        overrides: [
          sessionStoreProvider.overrideWithValue(store),
          webSessionCleanerProvider.overrideWithValue(_NoopCleaner()),
          apiClientProvider.overrideWithValue(
            SynergiaApiClient(
              sessionStore: store,
              dio: fakeDio(adapter),
              minInterval: Duration.zero,
            ),
          ),
        ],
      );
      addTearDown(c.dispose);
      final sub = c.listen(excusesProvider, (_, _) {});
      expect(await c.read(excusesProvider.future), hasLength(1));
      sub.close();
      store.session = null;
      c.read(apiClientProvider).resetSession();
      c.invalidate(excusesProvider);
      await expectLater(
        c.read(excusesProvider.future),
        throwsA(isA<SessionExpiredException>()),
      );
      expect(adapter.requests, hasLength(1), reason: 'bez sesji brak zapytań');
    },
  );
}
