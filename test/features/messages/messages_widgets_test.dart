import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/app/providers.dart';
import 'package:synergia_lite/features/messages/data/drafts_store.dart';
import 'package:synergia_lite/features/messages/data/messages_repository.dart';
import 'package:synergia_lite/features/messages/domain/message.dart';
import 'package:synergia_lite/features/messages/domain/message_draft.dart';
import 'package:synergia_lite/features/messages/presentation/compose_screen.dart';
import 'package:synergia_lite/features/messages/presentation/message_detail_screen.dart';
import 'package:synergia_lite/features/messages/presentation/message_list_view.dart';
import 'package:synergia_lite/features/messages/presentation/messages_providers.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/messages_fakes.dart';

Widget _app(
  FakeMessagesServer server,
  Widget child, {
  InMemoryKeyValueStore? kv,
}) => ProviderScope(
  retry: (_, _) => null,
  overrides: [
    messagesRepositoryProvider.overrideWithValue(
      MessagesRepository(fakeMessagesClient(server).client),
    ),
    messagesAccountKeyProvider.overrideWith((ref) async => 'KONTO'),
    draftsStoreProvider.overrideWithValue(
      DraftsStore(kv ?? InMemoryKeyValueStore()),
    ),
  ],
  child: MaterialApp(home: Scaffold(body: child)),
);

void main() {
  group('lista Odebranych', () {
    testWidgets('pusta skrzynka', (tester) async {
      final server = FakeMessagesServer(
        api: {
          'inbox/messages': (_) => jsonBody({'data': [], 'total': 0}),
        },
      );
      await tester.pumpWidget(
        _app(server, const MessageListView(folder: MessageFolder.inbox)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Brak odebranych wiadomości.'), findsOneWidget);
    });

    testWidgets('nieprzeczytane wyróżnione, kolejne strony na żądanie', (
      tester,
    ) async {
      final server = FakeMessagesServer(
        api: {
          'inbox/messages': (o) => o.uri.queryParameters['page'] == '1'
              ? jsonBody({
                  'data': [
                    inboxItem('1', topic: 'Nowa sprawa', readDate: null),
                    for (var i = 2; i <= 20; i++)
                      inboxItem('$i', topic: 'Temat $i'),
                  ],
                  'total': 21,
                })
              : jsonBody({
                  'data': [inboxItem('21', topic: 'Najstarsza')],
                  'total': 21,
                }),
        },
      );
      await tester.pumpWidget(
        _app(server, const MessageListView(folder: MessageFolder.inbox)),
      );
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.mark_email_unread), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('Nieprzeczytana wiadomość')),
        findsOneWidget,
      );

      await tester.scrollUntilVisible(find.text('Wczytaj starsze'), 300);
      await tester.tap(find.text('Wczytaj starsze'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('To wszystkie wiadomości.'),
        300,
      );
      expect(find.textContaining('Najstarsza'), findsOneWidget);
    });

    testWidgets('błąd pobierania z możliwością ponowienia', (tester) async {
      var fail = true;
      final server = FakeMessagesServer(
        api: {
          'inbox/messages': (_) => fail
              ? jsonBody({}, status: 500)
              : jsonBody({
                  'data': [inboxItem('1')],
                }),
        },
      );
      await tester.pumpWidget(
        _app(server, const MessageListView(folder: MessageFolder.inbox)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Spróbuj ponownie'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Spróbuj ponownie'));
      await tester.pumpAndSettle();
      expect(find.text('Ewa Przykładowa'), findsOneWidget);
    });

    testWidgets('szkoła bez modułu Wiadomości', (tester) async {
      final server = FakeMessagesServer(
        bootstrap: (_) => textBody('Brak dostępu'),
      );
      await tester.pumpWidget(
        _app(server, const MessageListView(folder: MessageFolder.inbox)),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('nie jest dostępny'), findsOneWidget);
    });
  });

  group('szczegóły', () {
    Map<String, Object?> detail({int noReply = 0}) => {
      'data': {
        'messageId': '77',
        'senderId': '501',
        'senderName': 'Ewa Przykładowa',
        'topic': 'Zebranie',
        'Message': fullMessage(
          '<p>Zapraszam <b>wszystkich</b></p><script>alert(1)</script>',
        ),
        'sendDate': '2026-10-09 12:30:00',
        'noReply': noReply,
        'attachments': [
          {'id': 'a', 'filename': 'plan.pdf'},
        ],
      },
    };

    testWidgets('treść bez skryptów, załącznik i przycisk Odpowiedz', (
      tester,
    ) async {
      final server = FakeMessagesServer(
        api: {'inbox/messages/77': (_) => jsonBody(detail())},
      );
      await tester.pumpWidget(
        _app(
          server,
          const MessageDetailScreen(folder: MessageFolder.inbox, id: '77'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('Zapraszam'), findsOneWidget);
      expect(find.textContaining('alert'), findsNothing);
      expect(find.text('plan.pdf'), findsOneWidget);
      expect(find.text('Odpowiedz'), findsOneWidget);
      expect(
        find.text('Odpowiedz wszystkim'),
        findsNothing,
        reason: 'API nie podaje adresatów do odpowiedzi wszystkim',
      );
    });

    testWidgets('noReply ukrywa odpowiedź', (tester) async {
      final server = FakeMessagesServer(
        api: {'inbox/messages/77': (_) => jsonBody(detail(noReply: 1))},
      );
      await tester.pumpWidget(
        _app(
          server,
          const MessageDetailScreen(folder: MessageFolder.inbox, id: '77'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Odpowiedz'), findsNothing);
      expect(
        find.textContaining('wyłączył możliwość odpowiedzi'),
        findsOneWidget,
      );
    });
  });

  group('formularz', () {
    testWidgets('walidacja po próbie wysłania, bez żądań', (tester) async {
      final server = FakeMessagesServer();
      await tester.pumpWidget(
        _app(server, ComposeScreen(initial: MessageDraft.create())),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wyślij'));
      await tester.pumpAndSettle();
      // Najpierw walidacja — bez dialogu potwierdzenia i bez żądań.
      expect(find.text('Wysłać wiadomość?'), findsNothing);
      expect(
        find.text('Wybierz co najmniej jednego odbiorcę.'),
        findsOneWidget,
      );
      expect(find.text('Wpisz temat.'), findsOneWidget);
      expect(find.text('Wpisz treść wiadomości.'), findsOneWidget);
      expect(server.calls, isEmpty);
    });

    testWidgets('potwierdzenie → jedno wysłanie → wyraźny wynik', (
      tester,
    ) async {
      final server = FakeMessagesServer(
        api: {
          'me': (_) => jsonBody({
            'data': {'accountId': 'KONTO'},
          }),
          'messages': (_) => jsonBody({
            'data': {'messageId': 9, 'status': 'sent'},
          }, status: 201),
        },
      );
      final kv = InMemoryKeyValueStore();
      final initial = MessageDraft.create(
        to: const MessageRecipient(accountId: '501', label: 'Przykładowa Ewa'),
      );
      await tester.pumpWidget(
        _app(server, ComposeScreen(initial: initial), kv: kv),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Temat'),
        'Pytanie',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Treść'),
        'Dzień dobry',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(kv.values, isNotEmpty, reason: 'autozapis kopii roboczej');

      await tester.tap(find.text('Wyślij'));
      await tester.pumpAndSettle();
      expect(find.text('Wysłać wiadomość?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Wyślij').last);
      await tester.pumpAndSettle();

      expect(find.text('Wiadomość została wysłana.'), findsOneWidget);
      expect(server.calls.where((c) => c.startsWith('POST')), hasLength(1));
      expect(
        kv.values,
        isEmpty,
        reason: 'szkic usunięty po potwierdzonym sukcesie',
      );
      expect(find.widgetWithText(FilledButton, 'Wyślij'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'Wyślij'))
            .onPressed,
        isNull,
      );
    });

    testWidgets('anulowanie potwierdzenia nic nie wysyła', (tester) async {
      final server = FakeMessagesServer(api: {'me': (_) => jsonBody({})});
      final initial = MessageDraft.create(
        to: const MessageRecipient(accountId: '501', label: 'Przykładowa Ewa'),
      ).copyWith(topic: 'T', body: 'B');
      await tester.pumpWidget(_app(server, ComposeScreen(initial: initial)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Wyślij'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Anuluj'));
      await tester.pumpAndSettle();
      expect(server.calls, isEmpty);
    });

    testWidgets(
      'timeout → „Nie wiadomo, czy wiadomość została wysłana” + Sprawdź Wysłane',
      (tester) async {
        final server = FakeMessagesServer(
          api: {
            'me': (_) => jsonBody({}),
            'messages': (_) => jsonBody({}, status: 504),
          },
        );
        final initial = MessageDraft.create(
          to: const MessageRecipient(
            accountId: '501',
            label: 'Przykładowa Ewa',
          ),
        ).copyWith(topic: 'T', body: 'B');
        await tester.pumpWidget(_app(server, ComposeScreen(initial: initial)));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wyślij'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Wyślij').last);
        await tester.pumpAndSettle();
        expect(
          find.text('Nie wiadomo, czy wiadomość została wysłana'),
          findsOneWidget,
        );
        expect(find.text('Sprawdź Wysłane'), findsOneWidget);

        // Ponowna próba wymaga dodatkowego potwierdzenia.
        await tester.scrollUntilVisible(
          find.text('Wyślij'),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.tap(find.text('Wyślij'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Wyślij').last);
        await tester.pumpAndSettle();
        expect(find.text('Poprzednia próba mogła się udać'), findsOneWidget);
        await tester.tap(find.text('Anuluj'));
        await tester.pumpAndSettle();
        expect(server.calls.where((c) => c.startsWith('POST')), hasLength(1));
      },
    );
  });
}
