import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/core/storage/key_value_store.dart';
import 'package:synergia_lite/features/messages/data/messages_api_client.dart';
import 'package:synergia_lite/features/messages/data/messages_repository.dart';
import 'package:synergia_lite/features/messages/domain/message.dart';
import 'package:synergia_lite/features/notifications/data/message_notification_checker.dart';
import 'package:synergia_lite/features/notifications/data/sync_state_repository.dart';
import 'package:synergia_lite/features/notifications/domain/notification_intent.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/messages_fakes.dart';
import '../../helpers/notification_fakes.dart';

/// Fikcyjna skrzynka: wiadomości od najnowszej, strony po 20.
class FakeInbox {
  final items = <Map<String, Object?>>[];
  String owner = 'KONTO-1';
  int pageRequests = 0;
  FutureOr<ResponseBody> Function(RequestOptions)? override;
  Future<void>? gate;

  void add(String id, DateTime sent, {bool read = false}) => items.insert(
    0,
    inboxItem(id, readDate: read ? '2026-10-18 09:00:00' : null)
      ..['sendDate'] = _fmt(sent),
  );

  static String _fmt(DateTime d) =>
      '${d.year}-${_pad(d.month)}-${_pad(d.day)} ${_pad(d.hour)}:${_pad(d.minute)}:${_pad(d.second)}';
  static String _pad(int v) => v.toString().padLeft(2, '0');

  FakeMessagesServer server() => FakeMessagesServer(
    api: {
      'me': (_) => jsonBody({
        'data': {'accountId': owner},
      }),
      'inbox/messages': (o) {
        pageRequests++;
        if (override != null) return override!(o);
        final page = int.parse(o.uri.queryParameters['page'] ?? '1');
        final limit = int.parse(o.uri.queryParameters['limit'] ?? '20');
        final slice = items.skip((page - 1) * limit).take(limit).toList();
        return jsonBody({'data': slice, 'total': items.length});
      },
    },
  );
}

class _Env {
  _Env({DateTime? now}) : now = now ?? DateTime(2026, 10, 18, 10) {
    final f = fakeMessagesClient(inbox.server());
    session = f.store;
    client = f.client;
  }

  final inbox = FakeInbox();
  final kv = InMemoryKeyValueStore();
  final notifier = FakeNotifier();
  late final InMemorySessionStore session;
  late final MessagesApiClient client;
  DateTime now;

  late final settings = NotificationSettingsRepository(kv);
  late final state = MessageSyncStateRepository(kv);

  MessageNotificationChecker checker({
    bool coalesce = false,
    MessagesApiClient? using,
  }) => MessageNotificationChecker(
    messages: MessagesRepository(using ?? client),
    session: session,
    state: state,
    settings: settings,
    notifier: notifier,
    clock: () => now,
    coalesceInIsolate: coalesce,
  );

  Future<SyncOutcome> run({SyncTrigger trigger = SyncTrigger.background}) =>
      checker().run(trigger: trigger);
}

void main() {
  late _Env env;
  final t = DateTime(2026, 10, 18, 9);

  setUp(() async {
    env = _Env();
    await env.settings.setEnabled(true);
    env.inbox
      ..add('100', t.subtract(const Duration(days: 2)))
      ..add('101', t.subtract(const Duration(days: 1)));
  });

  test(
    'pierwsza synchronizacja zapamiętuje skrzynkę bez powiadomień',
    () async {
      expect(
        await env.run(),
        isA<SyncBaseline>().having((o) => o.known, 'known', 2),
      );
      expect(env.notifier.shown, isEmpty);
      expect((await env.state.read('KONTO-1'))!.knownIds, ['101', '100']);
    },
  );

  test(
    'jedna nowa wiadomość → jedno powiadomienie z jej identyfikatorem; potem cisza',
    () async {
      await env.run();
      env.inbox.add('102', t);
      expect(
        await env.run(),
        isA<SyncNotified>().having((o) => o.count, 'count', 1),
      );
      expect(env.notifier.shown.single.ids, ['102']);
      expect(
        env.notifier.shown.single.notificationId,
        NotificationIds.forMessage('KONTO-1', '102'),
      );
      expect(await env.run(), isA<SyncNoNew>());
      expect(
        env.notifier.shown,
        hasLength(1),
        reason: 'bez ponownego powiadomienia o tej samej wiadomości',
      );
    },
  );

  test('kilka nowych → jedno powiadomienie zbiorcze', () async {
    await env.run();
    env.inbox
      ..add('102', t)
      ..add('103', t.add(const Duration(minutes: 1)))
      ..add('104', t.add(const Duration(minutes: 2)));
    expect(
      await env.run(),
      isA<SyncNotified>().having((o) => o.count, 'count', 3),
    );
    expect(env.notifier.shown.single.ids, ['104', '103', '102']);
    expect(env.notifier.shown.single.notificationId, NotificationIds.summary);
  });

  test('zmiana statusu przeczytania nie jest nową wiadomością', () async {
    await env.run();
    env.inbox.items.first['readDate'] = '2026-10-18 09:30:00';
    expect(await env.run(), isA<SyncNoNew>());
  });

  test(
    'pusta skrzynka: stan bazowy, potem pierwsza wiadomość jest nowa',
    () async {
      env.inbox.items.clear();
      expect(
        await env.run(),
        isA<SyncBaseline>().having((o) => o.known, 'known', 0),
      );
      env.inbox.add('200', t);
      expect(await env.run(), isA<SyncNotified>());
    },
  );

  test(
    'więcej nowych niż strona → doczytanie kolejnej strony (bez pomijania)',
    () async {
      await env.run();
      for (var i = 0; i < 25; i++) {
        env.inbox.add('${300 + i}', t.add(Duration(minutes: i)));
      }
      env.inbox.pageRequests = 0;
      expect(
        await env.run(),
        isA<SyncNotified>().having((o) => o.count, 'count', 25),
      );
      expect(env.inbox.pageRequests, 2);
    },
  );

  test(
    'HTTP 401 / sesja Synergii wygasła → wstrzymanie, bez ponownego logowania',
    () async {
      await env.run();
      final expired = _Env();
      await expired.settings.setEnabled(true);
      await expired.state.write((await env.state.read('KONTO-1'))!);
      final server = FakeMessagesServer(
        bootstrap: (_) => redirect('https://portal.librus.pl/rodzina'),
      );
      final client = fakeMessagesClient(server).client;
      final outcome = await expired
          .checker(using: client)
          .run(trigger: SyncTrigger.background);
      expect(
        outcome,
        isA<SyncPaused>().having((o) => o.newlyPaused, 'newly', isTrue),
      );
      expect(outcome.stopsMonitoring, isTrue);
      expect(
        server.calls.where((c) => c.contains('loguj') || c.contains('OAuth')),
        isEmpty,
      );
      expect(
        (await expired.state.readAny())!.pausedReason,
        pausedSessionExpired,
      );
      expect(
        await expired
            .checker(using: client)
            .run(trigger: SyncTrigger.background),
        isA<SyncSkipped>().having((o) => o.reason, 'reason', SkipReason.paused),
      );
    },
  );

  test(
    'HTTP 401 serwisu wiadomości po odnowieniu = błąd przejściowy',
    () async {
      await env.run();
      env.inbox.override = (_) => jsonBody({}, status: 401);
      final o = await env.run();
      expect(
        o,
        isA<SyncFailed>().having((f) => f.transient, 'transient', isTrue),
      );
      expect(
        o.workSucceeded,
        isFalse,
        reason: 'WorkManager ponowi z backoffem',
      );
    },
  );

  test('HTTP 429 z Retry-After → przerwa bez odpytywania', () async {
    await env.run();
    env.inbox.override = (_) => jsonBody(
      {},
      status: 429,
      headers: {
        'retry-after': ['120'],
      },
    );
    final o = await env.run();
    expect(o, isA<SyncFailed>());
    expect(o.workSucceeded, isTrue, reason: 'bez agresywnego ponawiania');
    final s = (await env.state.readAny())!;
    expect(s.retryNotBefore, env.now.add(const Duration(minutes: 2)));

    env.inbox.override = null;
    final callsBefore = env.inbox.pageRequests;
    env.now = env.now.add(const Duration(minutes: 1));
    expect(
      await env.run(),
      isA<SyncSkipped>().having(
        (o) => o.reason,
        'reason',
        SkipReason.rateLimited,
      ),
    );
    expect(env.inbox.pageRequests, callsBefore);
    env.now = env.now.add(const Duration(minutes: 2));
    expect(await env.run(), isA<SyncNoNew>());
  });

  test('429 bez Retry-After i z absurdalnie długim są przycinane', () {
    expect(clampRetryAfter(null), const Duration(minutes: 30));
    expect(clampRetryAfter(const Duration(days: 3)), const Duration(hours: 6));
    expect(clampRetryAfter(Duration.zero), const Duration(minutes: 1));
  });

  test(
    'timeout i brak internetu: stan bez zmian, ograniczona liczba ponowień',
    () async {
      await env.run();
      final known = (await env.state.readAny())!.knownIds;
      final store = env.session;
      final timeoutClient = MessagesApiClient(
        synergiaSession: store,
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
      final offlineClient = MessagesApiClient(
        synergiaSession: store,
        dio: fakeDio(
          FakeAdapter((_) => throw const SocketException('offline')),
        ),
        minInterval: Duration.zero,
      );
      final results = [
        for (final c in [
          timeoutClient,
          offlineClient,
          offlineClient,
          offlineClient,
        ])
          await env.checker(using: c).run(trigger: SyncTrigger.background),
      ];
      expect(results.every((r) => r is SyncFailed && r.transient), isTrue);
      expect(
        results.map((r) => r.workSucceeded),
        [false, false, false, true],
        reason: 'po 3 ponowieniach czekamy na zwykły termin',
      );
      expect((await env.state.readAny())!.knownIds, known);
      expect(env.notifier.shown, isEmpty);
    },
  );

  test('częściowa lub niepoprawna odpowiedź nie jest pustą skrzynką', () async {
    await env.run();
    for (final bad in [
      jsonBody({'wiadomosci': []}),
      jsonBody({
        'data': [
          {'x': 1},
        ],
      }),
      textBody('<html>'),
    ]) {
      env.inbox.override = (_) => bad;
      expect(
        await env.run(),
        isA<SyncFailed>().having((f) => f.transient, 'transient', isFalse),
      );
    }
    env.inbox.override = null;
    expect(
      await env.run(),
      isA<SyncNoNew>(),
      reason: 'znane wiadomości nie zostały „zapomniane”',
    );
    expect(env.notifier.shown, isEmpty);
  });

  test('brak uprawnienia Androida: brak zapytań i powiadomień', () async {
    env.notifier.allowed = false;
    expect(
      await env.run(),
      isA<SyncSkipped>().having(
        (o) => o.reason,
        'reason',
        SkipReason.noPermission,
      ),
    );
    expect(env.inbox.pageRequests, 0);
  });

  test(
    'wyłączone powiadomienia: zadanie w tle nic nie pobiera i kończy monitorowanie',
    () async {
      await env.settings.setEnabled(false);
      final o = await env.run();
      expect(
        o,
        isA<SyncSkipped>().having(
          (o) => o.reason,
          'reason',
          SkipReason.disabled,
        ),
      );
      expect(o.stopsMonitoring, isTrue);
      expect(env.inbox.pageRequests, 0);
    },
  );

  test(
    'wylogowanie w trakcie synchronizacji → bez powiadomienia i bez odtworzenia stanu',
    () async {
      await env.run();
      env.inbox.add('102', t);
      env.inbox.override = (o) {
        // Użytkownik wylogowuje się, gdy zadanie czeka na odpowiedź.
        env.session.session = null;
        env.kv.values.clear();
        env.inbox.override = null;
        return env.inbox.server().handle(o);
      };
      expect(await env.run(), isA<SyncAborted>());
      expect(env.notifier.shown, isEmpty);
      expect(await env.state.readAny(), isNull);
    },
  );

  test(
    'przełączenie konta: stan bazowy dla nowego konta, bez powiadomień',
    () async {
      await env.run();
      env.inbox.owner = 'KONTO-2';
      env.inbox.add('500', t);
      expect(await env.run(), isA<SyncBaseline>());
      expect(env.notifier.shown, isEmpty);
      expect((await env.state.readAny())!.owner, 'KONTO-2');
      expect(await env.state.read('KONTO-1'), isNull);
    },
  );

  test(
    'równoległe uruchomienie (aplikacja + tło): w jednym izolacie wspólny wynik',
    () async {
      await env.run();
      env.inbox.add('102', t);
      final a = env.checker(coalesce: true).run(trigger: SyncTrigger.manual);
      final b = env
          .checker(coalesce: true)
          .run(trigger: SyncTrigger.background);
      expect(identical(await a, await b), isTrue);
      expect(env.notifier.shown, hasLength(1));
    },
  );

  test(
    'równoległe uruchomienie w innym kontekście: blokada (lease) → pominięcie',
    () async {
      await env.run();
      env.inbox.add('102', t);
      final gate = Completer<void>();
      env.inbox.override = (RequestOptions o) async {
        await gate.future;
        env.inbox.override = null;
        return env.inbox.server().handle(o);
      };
      final first = env.run(trigger: SyncTrigger.manual);
      await Future<void>.delayed(Duration.zero);
      final second = await env.run();
      expect(
        second,
        isA<SyncSkipped>().having((o) => o.reason, 'reason', SkipReason.busy),
      );
      gate.complete();
      expect(await first, isA<SyncNotified>());
      expect(env.notifier.shown, hasLength(1));
      env.now = env.now.add(const Duration(minutes: 5));
      expect(await env.run(), isA<SyncNoNew>());
    },
  );

  test('wiadomość obejrzana w aplikacji nie wywołuje powiadomienia', () async {
    await env.run();
    env.inbox.add('102', t);
    final page = await MessagesRepository(
      env.client,
    ).fetchPage(MessageFolder.inbox, 1);
    await env.checker().markSeen('KONTO-1', page.items);
    expect(await env.run(), isA<SyncNoNew>());
  });

  test(
    'ręczne „Sprawdź teraz” działa także przy wyłączonych powiadomieniach w tle',
    () async {
      await env.settings.setEnabled(false);
      expect(await env.run(trigger: SyncTrigger.manual), isA<SyncBaseline>());
    },
  );
}
