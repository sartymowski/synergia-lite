import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/features/messages/domain/message.dart';
import 'package:synergia_lite/features/notifications/domain/new_message_detector.dart';
import 'package:synergia_lite/features/notifications/domain/notification_intent.dart';
import 'package:synergia_lite/features/notifications/domain/sync_state.dart';

MessageSummary msg(String id, DateTime sent, {DateTime? read}) =>
    MessageSummary(
      id: id,
      folder: MessageFolder.inbox,
      counterpart: 'Nadawca Fikcyjny',
      topic: 'Temat',
      preview: '',
      sentAt: sent,
      readAt: read,
    );

void main() {
  final t0 = DateTime(2026, 10, 18, 8);
  MessageSyncState state(List<String> ids, {DateTime? watermark}) =>
      MessageSyncState(
        owner: 'K',
        knownIds: ids,
        baselineAt: t0,
        watermark: watermark ?? t0,
      );

  test('jedna nowa wiadomość', () {
    final d = detectNewMessages(state(['1', '2']), [
      msg('3', t0.add(const Duration(minutes: 5))),
      msg('2', t0),
      msg('1', t0.subtract(const Duration(hours: 1))),
    ]);
    expect(d.newMessages.map((m) => m.id), ['3']);
    expect(d.knownIds.take(3), ['3', '2', '1']);
    expect(d.watermark, t0.add(const Duration(minutes: 5)));
  });

  test('kilka nowych — od najnowszej, bez względu na kolejność z API', () {
    final d = detectNewMessages(state(['1']), [
      msg('2', t0.add(const Duration(minutes: 1))),
      msg('1', t0),
      msg('4', t0.add(const Duration(minutes: 9))),
      msg('3', t0.add(const Duration(minutes: 3))),
    ]);
    expect(d.newMessages.map((m) => m.id), ['4', '3', '2']);
  });

  test('brak nowych i zmiana statusu przeczytania nie są nowością', () {
    final s = state(['1', '2']);
    expect(
      detectNewMessages(s, [msg('2', t0), msg('1', t0)]).newMessages,
      isEmpty,
    );
    expect(
      detectNewMessages(s, [
        msg('2', t0, read: t0.add(const Duration(hours: 1))),
        msg('1', t0),
      ]).newMessages,
      isEmpty,
    );
  });

  test('pusta lub częściowa odpowiedź nie usuwa znanych identyfikatorów', () {
    final s = state(['1', '2', '3']);
    final empty = detectNewMessages(s, []);
    expect(empty.newMessages, isEmpty);
    expect(empty.knownIds, ['1', '2', '3']);
    final again = detectNewMessages(
      MessageSyncState(
        owner: 'K',
        knownIds: empty.knownIds,
        baselineAt: t0,
        watermark: t0,
      ),
      [msg('3', t0)],
    );
    expect(
      again.newMessages,
      isEmpty,
      reason: 'po pustej odpowiedzi nie ma ponownych powiadomień',
    );
  });

  test('stara wiadomość przywrócona z kosza nie budzi alarmu (znak wodny)', () {
    final d = detectNewMessages(state(['5']), [
      msg('9', t0.subtract(const Duration(days: 30))),
    ]);
    expect(d.newMessages, isEmpty);
    expect(d.knownIds, contains('9'));
  });

  test(
    'wiadomość tuż sprzed znaku wodnego (ta sama minuta, zegary) jest nowa',
    () {
      final d = detectNewMessages(state(['5']), [
        msg('6', t0.subtract(const Duration(minutes: 2))),
      ]);
      expect(d.newMessages.map((m) => m.id), ['6']);
    },
  );

  test('duplikaty w odpowiedzi i limit zapamiętanych identyfikatorów', () {
    final d = detectNewMessages(state([]), [msg('7', t0), msg('7', t0)]);
    expect(d.newMessages, hasLength(1));
    final many = [for (var i = 0; i < 400; i++) "$i"];
    // Ścieżki zapisu (copyWith, stan bazowy) i odczyt z dysku przycinają listę.
    expect(
      state([]).copyWith(knownIds: many).knownIds,
      hasLength(MessageSyncState.maxKnown),
    );
    expect(
      MessageSyncState.baseline("K", many, t0, t0).knownIds,
      hasLength(MessageSyncState.maxKnown),
    );
    final raw = state([]).toJson()..["knownIds"] = many;
    expect(
      MessageSyncState.fromJson(raw)!.knownIds,
      hasLength(MessageSyncState.maxKnown),
    );
    expect(
      state([]).copyWith(knownIds: many).knownIds.first,
      "0",
      reason: "zostają najnowsze",
    );
  });

  test('stan: zapis i odczyt bez treści wiadomości', () {
    final s = state([
      '1',
      '2',
    ]).copyWith(lastError: 'HTTP 500', consecutiveFailures: 2);
    final restored = MessageSyncState.fromJson(s.toJson())!;
    expect(restored.knownIds, ['1', '2']);
    expect(restored.consecutiveFailures, 2);
    expect(s.toJson().keys, isNot(contains('topic')));
    expect(MessageSyncState.fromJson({'v': 2}), isNull);
  });

  test('polskie formy liczebników', () {
    expect(newMessagesPhrase(1), 'Masz nową wiadomość.');
    expect(newMessagesPhrase(3), 'Masz 3 nowe wiadomości w Synergii.');
    expect(newMessagesPhrase(5), 'Masz 5 nowych wiadomości w Synergii.');
    expect(newMessagesPhrase(12), 'Masz 12 nowych wiadomości w Synergii.');
    expect(newMessagesPhrase(22), 'Masz 22 nowe wiadomości w Synergii.');
  });

  group('payload powiadomienia', () {
    test('kodowanie i dekodowanie bez sekretów', () {
      final intent = OpenMessage(
        ownerTag: ownerTag('KONTO-1'),
        messageId: '7705268',
      );
      final payload = intent.encode();
      expect(NotificationIntent.decode(payload), intent);
      expect(payload, isNot(contains('KONTO-1')), reason: 'tylko skrót konta');
      expect(payload.length, lessThan(80));
      expect(
        NotificationIntent.decode(OpenInbox(ownerTag: 'ab').encode()),
        const OpenInbox(ownerTag: 'ab'),
      );
      expect(
        NotificationIntent.decode(const OpenApp().encode()),
        const OpenApp(),
      );
    });

    test('niepoprawne payloady są ignorowane', () {
      for (final p in [
        null,
        '',
        'xyz',
        '{"v":2,"k":"m"}',
        '{"v":1,"k":"m","o":"a","id":"../x"}',
        '{"v":1,"k":"?"}',
      ]) {
        expect(NotificationIntent.decode(p), isNull, reason: '$p');
      }
    });

    test(
      'identyfikatory powiadomień są deterministyczne i rozdzielone między kontami',
      () {
        expect(
          NotificationIds.forMessage('K', '1'),
          NotificationIds.forMessage('K', '1'),
        );
        expect(
          NotificationIds.forMessage('K', '1'),
          isNot(NotificationIds.forMessage('L', '1')),
        );
        expect(NotificationIds.forMessage('K', '1'), greaterThanOrEqualTo(100));
      },
    );
  });
}
