import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/features/messages/domain/message.dart';
import 'package:synergia_lite/features/messages/domain/message_draft.dart';
import 'package:synergia_lite/features/messages/domain/send_outcome.dart';
import 'package:synergia_lite/features/messages/presentation/compose_controller.dart';

const _teacher = MessageRecipient(accountId: '501', label: 'Przykładowa Ewa');

class _Harness {
  _Harness({
    MessageDraft? draft,
    this.outcome = const SendSucceeded(messageId: '1'),
  }) {
    controller = ComposeController(
      draft:
          draft ??
          MessageDraft.create(
            to: _teacher,
          ).copyWith(topic: 'Temat', body: 'Treść'),
      send: (d) {
        sendCalls.add(d);
        return pending?.future ?? Future.value(outcome);
      },
      saveDraft: (d) async {
        if (failSave) throw StateError('brak miejsca');
        saved.add(d);
      },
      deleteDraft: (id) async => deleted.add(id),
      autosaveDelay: const Duration(milliseconds: 500),
    );
  }

  late final ComposeController controller;
  SendOutcome outcome;
  Completer<SendOutcome>? pending;
  bool failSave = false;
  final sendCalls = <MessageDraft>[];
  final saved = <MessageDraft>[];
  final deleted = <String>[];
}

void main() {
  test('błędy formularza blokują wysyłkę i są pokazywane', () async {
    final h = _Harness(draft: MessageDraft.create());
    expect(h.controller.problems, isEmpty, reason: 'przed pierwszą próbą');
    expect(await h.controller.send(), isNull);
    expect(h.sendCalls, isEmpty);
    expect(h.controller.problems, contains(DraftProblem.noRecipients));
    h.controller.addRecipients([_teacher]);
    expect(h.controller.problems, isNot(contains(DraftProblem.noRecipients)));
  });

  test(
    'poprawne wysłanie: szkic zapisany przed, usunięty po sukcesie, dalej zablokowane',
    () async {
      final h = _Harness();
      final outcome = await h.controller.send();
      expect(outcome, isA<SendSucceeded>());
      expect(h.saved, isNotEmpty, reason: 'zapis przed wysłaniem');
      expect(h.deleted, [h.controller.draft.id]);
      expect(h.controller.status, ComposeStatus.sent);
      expect(h.controller.sentMessageId, '1');
      expect(await h.controller.send(), isNull);
      expect(h.sendCalls, hasLength(1));
      h.controller.update(topic: 'zmiana po wysłaniu');
      expect(h.controller.draft.topic, 'Temat');
    },
  );

  test('blokada podwójnego wysłania podczas trwającego żądania', () async {
    final h = _Harness()..pending = Completer();
    final first = h.controller.send();
    expect(h.controller.isSending, isTrue);
    expect(await h.controller.send(), isNull);
    expect(await h.controller.send(confirmedDespiteUnknown: true), isNull);
    h.controller.update(body: 'edycja w trakcie');
    expect(
      h.controller.draft.body,
      'Treść',
      reason: 'treść zablokowana podczas wysyłki',
    );
    h.pending!.complete(const SendSucceeded());
    await first;
    expect(h.sendCalls, hasLength(1));
  });

  test(
    'odrzucenie: treść i szkic zostają, można poprawić i wysłać ponownie',
    () async {
      final h = _Harness(
        outcome: const SendRejected(
          'Nie wysłano',
          serverMessages: ['Temat za długi'],
        ),
      );
      await h.controller.send();
      expect(h.controller.status, ComposeStatus.rejected);
      expect(h.controller.serverMessages, ['Temat za długi']);
      expect(h.deleted, isEmpty);
      expect(h.controller.canEdit, isTrue);
      h.controller.update(topic: 'Krótszy');
      expect(h.controller.status, ComposeStatus.editing);
      h.outcome = const SendSucceeded();
      await h.controller.send();
      expect(h.sendCalls, hasLength(2));
      expect(h.controller.status, ComposeStatus.sent);
    },
  );

  test(
    'timeout / wynik niejednoznaczny: oznaczenie szkicu i wymagane potwierdzenie',
    () async {
      final h = _Harness(outcome: const SendUnknown('Upłynął limit czasu'));
      await h.controller.send();
      expect(h.controller.status, ComposeStatus.unknown);
      expect(h.controller.draft.unknownSendAt, isNotNull);
      expect(
        h.saved.last.unknownSendAt,
        isNotNull,
        reason: 'stan przetrwa restart',
      );
      expect(h.deleted, isEmpty);

      expect(
        await h.controller.send(),
        isNull,
        reason: 'bez potwierdzenia nic nie wychodzi',
      );
      expect(h.sendCalls, hasLength(1));

      h.outcome = const SendSucceeded();
      await h.controller.send(confirmedDespiteUnknown: true);
      expect(h.sendCalls, hasLength(2));
      expect(h.controller.status, ComposeStatus.sent);
    },
  );

  test(
    'szkic z niejednoznaczną wysyłką po restarcie też wymaga potwierdzenia',
    () async {
      final h = _Harness(
        draft: MessageDraft.create(
          to: _teacher,
        ).copyWith(topic: 'T', body: 'B', unknownSendAt: DateTime(2026)),
      );
      expect(h.controller.needsResendConfirmation, isTrue);
      expect(await h.controller.send(), isNull);
      expect(h.sendCalls, isEmpty, reason: 'brak automatycznej wysyłki');
    },
  );

  test('wyjątek w trakcie wysyłki = nie wiadomo (nie „wysłano”)', () async {
    final h = _Harness();
    final c = ComposeController(
      draft: h.controller.draft,
      send: (_) async => throw StateError('błąd aplikacji'),
      saveDraft: (_) async {},
      deleteDraft: (_) async {},
    );
    expect(await c.send(), isA<SendUnknown>());
    expect(c.status, ComposeStatus.unknown);
  });

  test('błąd zapisu szkicu nie blokuje wysyłki i jest sygnalizowany', () async {
    final h = _Harness(outcome: const SendRejected('x'))..failSave = true;
    await h.controller.send();
    expect(h.sendCalls, hasLength(1));
    expect(h.controller.draftSaveFailed, isTrue);
  });

  test('odpowiedź w wątku: adresat stały, powiązanie z oryginałem', () async {
    final h = _Harness(
      draft: MessageDraft.create(
        replyTo: const ReplyContext(
          originalMessageId: '77',
          originalTopic: 'Zebranie',
        ),
        to: _teacher,
      ).copyWith(body: 'Dziękuję'),
    );
    h.controller.addRecipients([
      const MessageRecipient(accountId: '999', label: 'Inny'),
    ]);
    h.controller.removeRecipient('501');
    expect(h.controller.draft.recipients.map((r) => r.accountId), ['501']);
    await h.controller.send();
    expect(h.sendCalls.single.replyTo!.originalMessageId, '77');
    expect(h.controller.statusMessage, contains('w wątku'));
  });

  test('autozapis po przerwie w pisaniu i zapis przy wyjściu', () {
    fakeAsync((async) {
      final h = _Harness();
      h.controller.update(body: 'a');
      h.controller.update(body: 'ab');
      async.elapse(const Duration(milliseconds: 300));
      expect(h.saved, isEmpty);
      async.elapse(const Duration(milliseconds: 300));
      expect(h.saved.single.body, 'ab');
      h.controller.update(body: 'abc');
      h.controller.flush();
      async.flushMicrotasks();
      expect(h.saved.last.body, 'abc');
      h.controller.dispose();
    });
  });

  test('dodawanie odbiorców bez duplikatów', () {
    final h = _Harness(draft: MessageDraft.create());
    h.controller.addRecipients([
      _teacher,
      _teacher,
      const MessageRecipient(accountId: '502', label: 'B'),
    ]);
    expect(h.controller.draft.recipients.map((r) => r.accountId), [
      '501',
      '502',
    ]);
  });
}
