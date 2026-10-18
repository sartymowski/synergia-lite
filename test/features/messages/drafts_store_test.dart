import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/features/messages/data/drafts_store.dart';
import 'package:synergia_lite/features/messages/domain/message.dart';
import 'package:synergia_lite/features/messages/domain/message_draft.dart';

MessageDraft draft(String id, DateTime at, {String topic = 'Temat'}) =>
    MessageDraft(
      id: id,
      updatedAt: at,
      topic: topic,
      body: 'Treść',
      recipients: const [
        MessageRecipient(accountId: '501', label: 'Przykładowa Ewa'),
      ],
    );

void main() {
  late InMemoryKeyValueStore kv;
  late DraftsStore store;

  setUp(() {
    kv = InMemoryKeyValueStore();
    store = DraftsStore(kv);
  });

  test('zapis, odczyt (od najnowszej), aktualizacja i usuwanie', () async {
    await store.save('K', draft('a', DateTime(2026, 10, 1)));
    await store.save('K', draft('b', DateTime(2026, 10, 2)));
    expect((await store.list('K')).map((d) => d.id), ['b', 'a']);

    await store.save('K', draft('a', DateTime(2026, 10, 3), topic: 'Nowy'));
    final list = await store.list('K');
    expect(list.map((d) => d.id), ['a', 'b']);
    expect(list.first.topic, 'Nowy');

    await store.remove('K', 'a');
    expect((await store.list('K')).map((d) => d.id), ['b']);
  });

  test(
    'pusty szkic nie jest zapisywany (i usuwa wcześniejszą wersję)',
    () async {
      await store.save('K', draft('a', DateTime(2026)));
      await store.save('K', MessageDraft(id: 'a', updatedAt: DateTime(2026)));
      expect(await store.list('K'), isEmpty);
      expect(kv.values, isEmpty);
    },
  );

  test('robocze innego konta nie są widoczne i zostają usunięte', () async {
    await store.save('KONTO-1', draft('a', DateTime(2026)));
    expect(await store.list('KONTO-2'), isEmpty);
    expect(kv.values, isEmpty);
    expect(await store.list('KONTO-1'), isEmpty);
  });

  test('uszkodzony zapis jest bezpiecznie czyszczony', () async {
    kv.values['message_drafts_v1'] = '{nie json';
    expect(await store.list('K'), isEmpty);
    expect(kv.values, isEmpty);
  });

  test('clearAll (wylogowanie) usuwa wszystko', () async {
    await store.save('K', draft('a', DateTime(2026)));
    await store.clearAll();
    expect(kv.values, isEmpty);
  });

  test('pełny zapis: odpowiedź w wątku i niejednoznaczna wysyłka', () async {
    final d = MessageDraft.create(
      replyTo: const ReplyContext(
        originalMessageId: '77',
        originalTopic: 'Zebranie',
      ),
      to: const MessageRecipient(accountId: '501', label: 'Przykładowa Ewa'),
      now: DateTime(2026, 10, 1),
    ).copyWith(body: 'Odpowiedź', unknownSendAt: DateTime(2026, 10, 1, 12));
    await store.save('K', d);
    final r = (await store.list('K')).single;
    expect(r.replyTo!.originalMessageId, '77');
    expect(r.topic, 'Re: Zebranie');
    expect(r.recipients.single.accountId, '501');
    expect(r.unknownSendAt, DateTime(2026, 10, 1, 12));
  });

  group('walidacja', () {
    test('wymagane pola i limity', () {
      final empty = MessageDraft.create();
      expect(
        validateDraft(empty),
        containsAll([
          DraftProblem.noRecipients,
          DraftProblem.noTopic,
          DraftProblem.noBody,
        ]),
      );

      final ok = draft('a', DateTime(2026));
      expect(validateDraft(ok), isEmpty);

      expect(validateDraft(ok.copyWith(topic: '   ')), [DraftProblem.noTopic]);
      expect(validateDraft(ok.copyWith(topic: 'x' * 201)), [
        DraftProblem.topicTooLong,
      ]);
      expect(validateDraft(ok.copyWith(body: 'x' * 10001)), [
        DraftProblem.bodyTooLong,
      ]);
      expect(
        validateDraft(
          ok.copyWith(recipients: [ok.recipients.first, ok.recipients.first]),
        ),
        [DraftProblem.duplicateRecipient],
      );
      expect(
        validateDraft(
          ok.copyWith(
            recipients: [
              for (var i = 0; i < 51; i++)
                MessageRecipient(accountId: '$i', label: 'x'),
            ],
          ),
        ),
        [DraftProblem.tooManyRecipients],
      );
    });

    test('temat odpowiedzi bez podwójnego Re:', () {
      expect(replyTopic('Zebranie'), 'Re: Zebranie');
      expect(replyTopic('RE: Zebranie'), 'RE: Zebranie');
      expect(replyTopic('x' * 250).length, 200);
    });
  });
}
