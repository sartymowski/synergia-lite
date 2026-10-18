import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/app/home_screen.dart';
import 'package:synergia_lite/app/providers.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/core/storage/key_value_store.dart';
import 'package:synergia_lite/features/messages/data/messages_repository.dart';
import 'package:synergia_lite/features/messages/presentation/messages_providers.dart';
import 'package:synergia_lite/features/notifications/data/sync_state_repository.dart';
import 'package:synergia_lite/features/notifications/domain/notification_intent.dart';
import 'package:synergia_lite/features/notifications/presentation/notifications_providers.dart';
import 'package:synergia_lite/features/notifications/presentation/settings_screen.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/messages_fakes.dart';
import '../../helpers/notification_fakes.dart';

class _Harness {
  _Harness({bool policy = false, NotificationIntent? launch}) {
    final messages = FakeMessagesServer(
      api: {
        'me': (_) => jsonBody({
          'data': {'accountId': 'KONTO'},
        }),
        'inbox/messages': (_) => jsonBody({
          'data': [inboxItem('77', topic: 'Zebranie')],
          'total': 1,
        }),
        'inbox/unreadMessagesCount': (_) => jsonBody({
          'data': {'inbox': 0},
        }),
        'inbox/messages/77': (_) => jsonBody({
          'data': {
            'messageId': '77',
            'senderId': '501',
            'senderName': 'Ewa Przykładowa',
            'topic': 'Zebranie',
            'Message': fullMessage('<p>Zapraszam</p>'),
          },
        }),
      },
    );
    messagesServer = messages;
    final f = fakeMessagesClient(messages);
    final synergia = FakeAdapter(
      (o) => switch (o.path) {
        'Me' => jsonBody({
          'Me': {
            'Account': {'FirstName': 'Rodzic'},
            'User': {'FirstName': 'Uczeń'},
          },
        }),
        'Grades' => jsonBody({'Grades': []}),
        'Timetables' => jsonBody({'Timetable': {}}),
        _ => jsonBody({}, status: 404),
      },
    );
    container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        sessionStoreProvider.overrideWithValue(session),
        apiClientProvider.overrideWithValue(
          SynergiaApiClient(
            sessionStore: session,
            dio: fakeDio(synergia),
            minInterval: Duration.zero,
          ),
        ),
        messagesRepositoryProvider.overrideWithValue(
          MessagesRepository(f.client),
        ),
        messagesAccountKeyProvider.overrideWith((ref) async => 'KONTO'),
        notificationsKeyValueStoreProvider.overrideWithValue(kv),
        notificationPermissionProvider.overrideWithValue(notifier),
        messageNotifierProvider.overrideWithValue(notifier),
        syncSchedulerProvider.overrideWithValue(scheduler),
        backgroundSyncAllowedProvider.overrideWithValue(policy),
        initialNotificationIntentProvider.overrideWithValue(launch),
      ],
    );
  }

  final session = InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'}));
  final kv = InMemoryKeyValueStore();
  final notifier = FakeNotifier();
  final scheduler = FakeScheduler();
  late final FakeMessagesServer messagesServer;
  late final ProviderContainer container;

  Future<void> pump(WidgetTester tester, Widget home) async {
    await container.read(authControllerProvider.future);
    container.read(backgroundSyncReconcilerProvider);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }
}

void main() {
  group('Ustawienia → Powiadomienia', () {
    testWidgets(
      'bez potwierdzonej dopuszczalności przełącznik jest nieaktywny i objaśniony',
      (tester) async {
        final h = _Harness();
        await h.pump(tester, const SettingsScreen());
        expect(
          find.text('Sprawdzanie w tle jest wyłączone w tej wersji'),
          findsOneWidget,
        );
        final toggle = tester.widget<SwitchListTile>(
          find.byType(SwitchListTile),
        );
        expect(toggle.onChanged, isNull);
        expect(toggle.value, isFalse);
        await tester.scrollUntilVisible(
          find.text('Sprawdź teraz (debug)'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text('Sprawdź teraz (debug)'), findsOneWidget);
        expect(
          find.textContaining('mogą przychodzić z opóźnieniem'),
          findsOneWidget,
        );
        h.container.dispose();
      },
    );

    testWidgets(
      'włączenie: uprawnienie → stan bazowy → rejestracja; wyłączenie anuluje',
      (tester) async {
        final h = _Harness(policy: true)..notifier.allowed = false;
        await h.pump(tester, const SettingsScreen());
        expect(
          find.text('Nieprzyznane — powiadomienia nie będą wyświetlane.'),
          findsOneWidget,
        );

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(
          h.notifier.permissionRequests,
          1,
          reason: 'prośba o uprawnienie przy włączaniu',
        );
        expect(
          (await NotificationSettingsRepository(h.kv).read()).enabled,
          isTrue,
        );
        expect(
          await MessageSyncStateRepository(h.kv).read('KONTO'),
          isNotNull,
          reason: 'stan bazowy',
        );
        expect(
          h.notifier.shown,
          isEmpty,
          reason: 'bez powiadomień historycznych',
        );
        expect(h.scheduler.active, isTrue);
        expect(find.text('Przyznane'), findsOneWidget);

        await tester.tap(find.byType(SwitchListTile));
        await tester.pumpAndSettle();
        expect(h.scheduler.active, isFalse);
        expect(
          (await NotificationSettingsRepository(h.kv).read()).enabled,
          isFalse,
        );
        h.container.dispose();
      },
    );

    testWidgets('odmowa uprawnienia: nic nie jest włączane', (tester) async {
      final h = _Harness(policy: true)
        ..notifier.allowed = false
        ..notifier.grantOnRequest = false;
      await h.pump(tester, const SettingsScreen());
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      expect(
        (await NotificationSettingsRepository(h.kv).read()).enabled,
        isFalse,
      );
      expect(h.scheduler.scheduled, 0);
      expect(h.messagesServer.calls, isEmpty);
      h.container.dispose();
    });
  });

  group('kliknięcie powiadomienia', () {
    testWidgets('zimny start: otwiera właściwą wiadomość tego samego konta', (
      tester,
    ) async {
      final h = _Harness(
        launch: OpenMessage(ownerTag: ownerTag('KONTO'), messageId: '77'),
      );
      await h.pump(tester, const HomeScreen());
      expect(
        find.text('Wiadomość'),
        findsOneWidget,
        reason: 'ekran szczegółów',
      );
      expect(find.textContaining('Zapraszam'), findsOneWidget);
      expect(
        h.container.read(notificationIntentProvider),
        isNull,
        reason: 'obsłużone raz',
      );
      h.container.dispose();
    });

    testWidgets(
      'powiadomienie innego konta: tylko Odebrane, bez otwierania wiadomości',
      (tester) async {
        final h = _Harness(
          launch: OpenMessage(ownerTag: ownerTag('INNE'), messageId: '77'),
        );
        await h.pump(tester, const HomeScreen());
        expect(find.textContaining('innego konta'), findsOneWidget);
        expect(
          h.messagesServer.calls.where((c) => c.endsWith('/messages/77')),
          isEmpty,
        );
        h.container.dispose();
      },
    );

    testWidgets(
      'kliknięcie przy działającej aplikacji (ciepły start): zbiorcze → Odebrane',
      (tester) async {
        final h = _Harness();
        await h.pump(tester, const HomeScreen());
        NotificationTapBus.instance.add(OpenInbox(ownerTag: ownerTag('KONTO')));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('Zebranie'),
          findsOneWidget,
          reason: 'lista Odebranych',
        );
        h.container.dispose();
      },
    );
  });

  test('cel powiadomienia dla bieżącego konta', () {
    final tag = ownerTag('K');
    expect(
      resolveNotificationTarget(
        OpenMessage(ownerTag: tag, messageId: '1'),
        'K',
      ),
      isA<TargetMessage>(),
    );
    expect(
      resolveNotificationTarget(
        OpenMessage(ownerTag: tag, messageId: '1'),
        'L',
      ),
      isA<TargetInbox>().having((t) => t.otherAccount, 'other', isTrue),
    );
    expect(
      resolveNotificationTarget(
        OpenMessage(ownerTag: tag, messageId: '1'),
        null,
      ),
      isA<TargetInbox>(),
    );
    expect(resolveNotificationTarget(const OpenApp(), 'K'), isA<TargetHome>());
  });
}
