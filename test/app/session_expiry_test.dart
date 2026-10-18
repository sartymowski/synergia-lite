import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/app/providers.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/auth/data/auth_repository.dart';
import 'package:synergia_lite/features/messages/data/drafts_store.dart';
import 'package:synergia_lite/features/messages/domain/message_draft.dart';
import 'package:synergia_lite/features/notifications/data/sync_state_repository.dart';
import 'package:synergia_lite/features/notifications/domain/sync_state.dart';
import 'package:synergia_lite/features/notifications/presentation/notifications_providers.dart';

import '../helpers/fake_http.dart';
import '../helpers/notification_fakes.dart';

class _Cleaner implements WebSessionCleaner {
  int calls = 0;

  @override
  Future<void> clear() async => calls++;
}

void main() {
  late InMemorySessionStore store;
  late _Cleaner cleaner;
  late InMemoryKeyValueStore drafts;
  late InMemoryKeyValueStore notifKv;
  late FakeScheduler scheduler;
  late FakeNotifier notifier;

  ProviderContainer container(FakeAdapter adapter) {
    final c = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sessionStoreProvider.overrideWithValue(store),
        webSessionCleanerProvider.overrideWithValue(cleaner),
        draftsStoreProvider.overrideWithValue(DraftsStore(drafts)),
        notificationsKeyValueStoreProvider.overrideWithValue(notifKv),
        syncSchedulerProvider.overrideWithValue(scheduler),
        messageNotifierProvider.overrideWithValue(notifier),
        apiClientProvider.overrideWith(
          (ref) => SynergiaApiClient(
            sessionStore: store,
            dio: fakeDio(adapter),
            minInterval: Duration.zero,
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    store = InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'}));
    cleaner = _Cleaner();
    drafts = InMemoryKeyValueStore();
    notifKv = InMemoryKeyValueStore();
    scheduler = FakeScheduler();
    notifier = FakeNotifier();
  });

  test('zapisana sesja → SignedIn; brak → SignedOut', () async {
    final c = container(FakeAdapter((_) => jsonBody({})));
    expect(await c.read(authControllerProvider.future), isA<SignedIn>());
    store.session = null;
    c.invalidate(authControllerProvider);
    expect(await c.read(authControllerProvider.future), isA<SignedOut>());
  });

  test(
    '401 podczas pobierania ocen wylogowuje i oznacza wygaśnięcie',
    () async {
      final c = container(FakeAdapter((_) => jsonBody({}, status: 401)));
      await c.read(authControllerProvider.future);
      final sub = c.listen(gradesOverviewProvider, (_, _) {});
      await expectLater(
        c.read(gradesOverviewProvider.future),
        throwsA(isA<SessionExpiredException>()),
      );
      sub.close();
      final state = c.read(authControllerProvider).value;
      expect(
        state,
        isA<SignedOut>().having((s) => s.sessionExpired, 'expired', isTrue),
      );
      expect(store.session, isNull);
      expect(cleaner.calls, 1);
    },
  );

  test('błąd sieci nie wylogowuje', () async {
    final c = container(FakeAdapter((_) => jsonBody({}, status: 500)));
    await c.read(authControllerProvider.future);
    final sub = c.listen(gradesOverviewProvider, (_, _) {});
    await expectLater(
      c.read(gradesOverviewProvider.future),
      throwsA(isA<ServerException>()),
    );
    sub.close();
    expect(c.read(authControllerProvider).value, isA<SignedIn>());
    expect(store.session, isNotNull);
  });

  test('wylogowanie zmienia stan i czyści dane', () async {
    final c = container(FakeAdapter((_) => textBody('')));
    await c.read(authControllerProvider.future);
    await DraftsStore(
      drafts,
    ).save('konto-1', MessageDraft.create().copyWith(topic: 'Szkic'));
    expect(drafts.values, isNotEmpty);
    await c.read(authControllerProvider.notifier).logout();
    expect(drafts.values, isEmpty, reason: 'robocze wiadomości usunięte');
    expect(c.read(authControllerProvider).value, isA<SignedOut>());
    expect(store.session, isNull);
    expect(cleaner.calls, 1);
  });

  test("wylogowanie kończy monitorowanie i usuwa stan powiadomień", () async {
    final c = container(FakeAdapter((_) => textBody("")));
    await c.read(authControllerProvider.future);
    await NotificationSettingsRepository(notifKv).setEnabled(true);
    await MessageSyncStateRepository(notifKv).write(
      MessageSyncState(
        owner: "K",
        knownIds: const ["1"],
        baselineAt: DateTime(2026),
      ),
    );
    await scheduler.schedule();
    await c.read(authControllerProvider.notifier).logout();
    expect(scheduler.active, isFalse);
    expect(
      notifKv.values,
      isEmpty,
      reason: "ustawienia i stan synchronizacji usunięte",
    );
    expect(notifier.cancelled, 1, reason: "pokazane powiadomienia usunięte");
  });
}
