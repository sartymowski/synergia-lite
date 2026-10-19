import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/features/messages/data/messages_parser.dart';
import 'package:synergia_lite/features/messages/domain/message.dart';

import '../../helpers/messages_fakes.dart';

void main() {
  group('lista', () {
    test('koperta data + total, nieprzeczytane i załączniki', () {
      final page = MessagesParser.page(
        {
          'data': [
            inboxItem('1', readDate: null, attachment: true),
            inboxItem('2'),
          ],
          'total': 45,
        },
        MessageFolder.inbox,
        page: 1,
        limit: 20,
      );
      expect(page.items.map((m) => m.id), ['1', '2']);
      expect(page.items.first.isUnread, isTrue);
      expect(page.items.first.hasAttachments, isTrue);
      expect(page.items.last.isUnread, isFalse);
      expect(page.items.first.counterpart, 'Ewa Przykładowa');
      expect(page.items.first.preview, 'Podgląd treści');
      expect(page.items.first.sentAt, DateTime(2026, 10, 9, 12, 30));
      expect(page.hasMore, isTrue, reason: '1·20 < 45');
    });

    test('ostatnia strona wg total', () {
      final page = MessagesParser.page(
        {
          'data': [inboxItem('41')],
          'total': 41,
        },
        MessageFolder.inbox,
        page: 3,
        limit: 20,
      );
      expect(page.hasMore, isFalse);
    });

    test(
      'goła lista bez koperty i bez total: pełna strona = może być więcej',
      () {
        final full = MessagesParser.page(
          [for (var i = 0; i < 20; i++) inboxItem('$i')],
          MessageFolder.inbox,
          page: 1,
          limit: 20,
        );
        expect(full.hasMore, isTrue);
        final partial = MessagesParser.page(
          [inboxItem('a')],
          MessageFolder.inbox,
          page: 1,
          limit: 20,
        );
        expect(partial.hasMore, isFalse);
      },
    );

    test('pusta skrzynka', () {
      final page = MessagesParser.page(
        {'data': [], 'total': 0},
        MessageFolder.inbox,
        page: 1,
        limit: 20,
      );
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('Wysłane: odbiorca, a wiadomość nigdy nie jest „nieprzeczytana”', () {
      final page = MessagesParser.page(
        {
          'data': [outboxItem('9')],
        },
        MessageFolder.outbox,
        page: 1,
        limit: 20,
      );
      expect(page.items.single.counterpart, 'Jan Testowy');
      expect(page.items.single.isUnread, isFalse);
    });

    test('nazwa z imienia i nazwiska, gdy brak pełnej', () {
      final item = inboxItem('1')..['senderName'] = '';
      final page = MessagesParser.page(
        {
          'data': [item],
        },
        MessageFolder.inbox,
        page: 1,
        limit: 20,
      );
      expect(page.items.single.counterpart, 'Ewa Przykładowa');
    });

    test('zmieniony format jest zgłaszany', () {
      expect(
        () => MessagesParser.page(
          {'wiadomosci': []},
          MessageFolder.inbox,
          page: 1,
          limit: 20,
        ),
        throwsA(isA<UnexpectedResponseException>()),
      );
      expect(
        () => MessagesParser.page(
          {
            'data': [
              {'x': 1},
            ],
          },
          MessageFolder.inbox,
          page: 1,
          limit: 20,
        ),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('szczegóły', () {
    test('odebrana: treść, nadawca, odpowiedź, załączniki', () {
      final d = MessagesParser.detail(
        {
          'data': {
            'messageId': '77',
            'senderId': '501',
            'senderName': 'Ewa Przykładowa',
            'senderGroup': 'Nauczyciel',
            'topic': 'Zebranie',
            'Message': fullMessage('<p>Zapraszam</p>'),
            'sendDate': '2026-10-09 12:30:00',
            'readDate': null,
            'noReply': 0,
            'attachments': [
              {'id': 'a1', 'filename': 'plan.pdf'},
            ],
          },
        },
        MessageFolder.inbox,
        '77',
      );
      expect(d.senderId, '501');
      expect(d.senderGroup, 'Nauczyciel');
      expect(d.bodyHtml, '<p>Zapraszam</p>');
      expect(d.attachments.single.filename, 'plan.pdf');
      expect(d.canReply, isTrue);
    });

    test('noReply albo brak senderId wyłącza odpowiedź', () {
      Map<String, Object?> data(Map<String, Object?> extra) => {
        'data': {'topic': 't', 'Message': fullMessage('x'), ...extra},
      };
      expect(
        MessagesParser.detail(
          data({'senderId': '1', 'noReply': 1}),
          MessageFolder.inbox,
          '1',
        ).canReply,
        isFalse,
      );
      expect(
        MessagesParser.detail(data({}), MessageFolder.inbox, '1').canReply,
        isFalse,
      );
      expect(
        MessagesParser.detail(
          data({'senderId': '1'}),
          MessageFolder.outbox,
          '1',
        ).canReply,
        isFalse,
      );
    });

    test('wysłana: odbiorcy ze statusem odczytu', () {
      final d = MessagesParser.detail(
        {
          'data': {
            'topic': 't',
            'Message': fullMessage('x'),
            'receiversCount': 2,
            'receivers': [
              {
                'firstName': 'Jan',
                'lastName': 'Testowy',
                'group': 'Nauczyciele',
                'readed': '2026-10-09 13:00:00',
              },
              {'firstName': 'Anna', 'lastName': 'Fikcyjna', 'readed': null},
            ],
          },
        },
        MessageFolder.outbox,
        '5',
      );
      expect(d.receivers.map((r) => r.name), ['Jan Testowy', 'Anna Fikcyjna']);
      expect(d.receivers.first.readAt, DateTime(2026, 10, 9, 13));
      expect(d.receivers.last.readAt, isNull);
      expect(d.receiversCount, 2);
    });

    test('brak obiektu data', () {
      expect(
        () => MessagesParser.detail({'Message': 'x'}, MessageFolder.inbox, '1'),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('odbiorcy', () {
    test(
      'grupy: znani pracownicy najpierw, pominięte grupy spoza pracowników',
      () {
        final groups = MessagesParser.recipientGroups({
          'data': {
            'defaultGroup': 'teachers',
            'list': [
              {'id': 'parentsCouncil', 'name': 'Rada rodziców'},
              {'id': 'speechTherapist', 'name': 'Logopeda'},
              {'id': 'teachers', 'name': 'Nauczyciele'},
              {'id': 'nowaGrupa', 'name': 'Nowa'},
              {'id': 'tutors', 'name': 'Wychowawcy'},
              {'id': 'sadmin', 'name': 'Wsparcie'},
            ],
          },
        });
        expect(groups.map((g) => g.id), [
          'tutors',
          'teachers',
          'speechTherapist',
          'nowaGrupa',
        ]);
      },
    );

    test('osoby w grupie z dostępnością i przedmiotami', () {
      const group = RecipientGroup(id: 'teachers', name: 'Nauczyciele');
      final people = MessagesParser.groupRecipients(
        {
          'receivers': [
            {
              'accountId': '501',
              'label': 'Przykładowa Ewa',
              'userId': '9',
              'availabilityStatus': {'isAvailable': true},
            },
            {
              'accountId': 502,
              'label': 'Testowy Jan',
              'availabilityStatus': {
                'isAvailable': false,
                'returnAt': '2026-11-02',
              },
            },
            {'label': 'bez konta'},
          ],
        },
        group,
        subjectsByTeacher: {
          '501': ['matematyka'],
        },
      );
      expect(people.map((p) => p.accountId), ['501', '502']);
      expect(people.first.subjects, ['matematyka']);
      expect(people.first.groupName, 'Nauczyciele');
      expect(people.last.isAvailable, isFalse);
      expect(people.last.returnAt, DateTime(2026, 11, 2));
      expect(people.first.matches('MATEM'), isTrue);
      expect(people.last.matches('jan'), isTrue);
      expect(people.last.matches('fizyka'), isFalse);
    });

    test('przedmioty nauczycieli i pusta grupa', () {
      expect(
        MessagesParser.teacherSubjects([
          {'teacherIdentifier': '501', 'subject': 'matematyka'},
          {'teacherIdentifier': '501', 'subject': 'fizyka'},
        ]),
        {
          '501': ['matematyka', 'fizyka'],
        },
      );
      expect(
        MessagesParser.groupRecipients({
          'receivers': [],
        }, const RecipientGroup(id: 't', name: 'T')),
        isEmpty,
      );
    });
  });

  test('licznik nieprzeczytanych i identyfikator konta', () {
    expect(
      MessagesParser.unreadInbox({
        'data': {'inbox': 3, 'notes': 0},
      }),
      3,
    );
    expect(
      MessagesParser.accountKey({
        'data': {'accountId': 'K1', 'firstName': 'X'},
      }),
      'K1',
    );
    expect(MessagesParser.accountKey({'accountId': 7}), '7');
    // Kształt potwierdzony na żywo 2026-10-19: pola na poziomie głównym, data = null.
    expect(
      MessagesParser.accountKey({
        'accountId': 'K9',
        'firstName': 'X',
        'data': null,
      }),
      'K9',
    );
    expect(
      () => MessagesParser.accountKey({'data': {}}),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });
}
