import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/core/storage/key_value_store.dart';
import 'package:synergia_lite/features/notifications/data/background_sync.dart';
import 'package:synergia_lite/features/notifications/data/message_notification_checker.dart';
import 'package:synergia_lite/features/notifications/data/sync_state_repository.dart';
import 'package:synergia_lite/features/notifications/domain/background_policy.dart';
import 'package:synergia_lite/features/notifications/domain/sync_state.dart';
import 'package:synergia_lite/features/notifications/presentation/notifications_providers.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/messages_fakes.dart';
import '../../helpers/notification_fakes.dart';

void main() {
  group('zadanie w tle (runBackgroundSync)', () {
    late InMemoryKeyValueStore kv;
    late FakeNotifier notifier;
    late FakeScheduler scheduler;

    setUp(() async {
      kv = InMemoryKeyValueStore();
      notifier = FakeNotifier();
      scheduler = FakeScheduler();
      await NotificationSettingsRepository(kv).setEnabled(true);
    });

    Future<bool> run(
      FakeMessagesServer server, {
      bool policy = true,
      InMemorySessionStore? session,
    }) {
      final f = fakeMessagesClient(server);
      return runBackgroundSync(
        session: session ?? f.store,
        kv: kv,
        client: f.client,
        notifier: notifier,
        scheduler: scheduler,
        policyAllowed: policy,
      );
    }

    FakeMessagesServer ok() => FakeMessagesServer(
      api: {
        'me': (_) => jsonBody({
          'data': {'accountId': 'K'},
        }),
        'inbox/messages': (_) => jsonBody({
          'data': [inboxItem('1')],
          'total': 1,
        }),
      },
    );

    test(
      'domyślnie (brak potwierdzenia dopuszczalności) zadanie się wyrejestrowuje bez zapytań',
      () async {
        expect(BackgroundSyncPolicy.allowed, isFalse, reason: 'domyślny build');
        final server = ok();
        expect(await run(server, policy: false), isTrue);
        expect(scheduler.cancelled, 1);
        expect(server.calls, isEmpty);
      },
    );

    test(
      'udane sprawdzenie zwraca sukces i nie anuluje harmonogramu',
      () async {
        expect(await run(ok()), isTrue);
        expect(scheduler.cancelled, 0);
        expect(await MessageSyncStateRepository(kv).read('K'), isNotNull);
      },
    );

    test('wylogowany użytkownik: anulowanie bez zapytań', () async {
      final server = ok();
      expect(await run(server, session: InMemorySessionStore()), isTrue);
      expect(scheduler.cancelled, 1);
      expect(server.calls, isEmpty);
    });

    test('wyłączone powiadomienia: anulowanie', () async {
      await NotificationSettingsRepository(kv).setEnabled(false);
      expect(await run(ok()), isTrue);
      expect(scheduler.cancelled, 1);
    });

    test('wygasła sesja: anulowanie i jednorazowa informacja', () async {
      await run(ok()); // stan bazowy
      final expired = FakeMessagesServer(
        bootstrap: (_) => redirect('https://portal.librus.pl/rodzina'),
      );
      expect(await run(expired), isTrue);
      expect(scheduler.cancelled, 1);
      expect(notifier.paused, [pausedSessionExpired]);
      await run(expired);
      expect(
        notifier.paused,
        hasLength(1),
        reason: 'bez powtarzania informacji',
      );
    });

    test('błąd przejściowy → WorkManager ponawia (false)', () async {
      await run(ok());
      final failing = FakeMessagesServer(
        api: {
          'me': (_) => jsonBody({
            'data': {'accountId': 'K'},
          }),
          'inbox/messages': (_) => jsonBody({}, status: 503),
        },
      );
      // 503 jest traktowane jak 429 (przerwa) → bez ponawiania.
      expect(await run(failing), isTrue);
      final s500 = FakeMessagesServer(
        api: {
          'me': (_) => jsonBody({
            'data': {'accountId': 'K'},
          }),
          'inbox/messages': (_) => jsonBody({}, status: 500),
        },
      );
      final state = MessageSyncStateRepository(kv);
      await state.write((await state.readAny())!.copyWith(clearRetry: true));
      expect(await run(s500), isFalse);
    });
  });

  group('uzgadnianie harmonogramu', () {
    late InMemoryKeyValueStore kv;
    late FakeNotifier permission;
    late FakeScheduler scheduler;
    late NotificationSettingsRepository settings;
    late MessageSyncStateRepository state;

    setUp(() {
      kv = InMemoryKeyValueStore();
      permission = FakeNotifier();
      scheduler = FakeScheduler();
      settings = NotificationSettingsRepository(kv);
      state = MessageSyncStateRepository(kv);
    });

    Future<bool> reconcile({bool policy = true, bool signedIn = true}) =>
        reconcileBackgroundSync(
          policyAllowed: policy,
          signedIn: signedIn,
          settings: settings,
          permission: permission,
          scheduler: scheduler,
          state: state,
        );

    test(
      'domyślnie wyłączone — bez decyzji użytkownika nic nie jest rejestrowane',
      () async {
        expect(await reconcile(), isFalse);
        expect(scheduler.scheduled, 0);
      },
    );

    test('rejestracja tylko przy spełnieniu wszystkich warunków', () async {
      await settings.setEnabled(true);
      expect(await reconcile(), isTrue);
      expect(scheduler.active, isTrue);
      expect(await reconcile(policy: false), isFalse);
      expect(scheduler.active, isFalse);
      expect(await reconcile(signedIn: false), isFalse);
      permission.allowed = false;
      expect(await reconcile(), isFalse);
      expect(scheduler.active, isFalse);
    });

    test('anulowanie i ponowna rejestracja', () async {
      await settings.setEnabled(true);
      await reconcile();
      await settings.setEnabled(false);
      await reconcile();
      expect(scheduler.active, isFalse);
      await settings.setEnabled(true);
      await reconcile();
      expect(scheduler.active, isTrue);
      expect(scheduler.scheduled, 2);
      expect(scheduler.cancelled, 1);
    });

    test('ponowne zalogowanie wznawia wstrzymane monitorowanie', () async {
      await settings.setEnabled(true);
      await state.write(
        MessageSyncState(
          owner: 'K',
          knownIds: const ['1'],
          baselineAt: DateTime(2026),
          pausedReason: pausedSessionExpired,
        ),
      );
      await reconcile();
      expect((await state.readAny())!.pausedReason, isNull);
    });
  });

  test('sesja Synergii jest dostępna bez WebView (tylko magazyn)', () async {
    final store = InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'}));
    expect((await store.read())!.toHeader(), 'DZIENNIKSID=x');
  });
}
