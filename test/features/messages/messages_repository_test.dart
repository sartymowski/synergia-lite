import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/features/messages/data/messages_api_client.dart';
import 'package:synergia_lite/features/messages/data/messages_repository.dart';
import 'package:synergia_lite/features/messages/domain/message.dart';
import 'package:synergia_lite/features/messages/domain/message_draft.dart';
import 'package:synergia_lite/features/messages/domain/send_outcome.dart';

import '../../helpers/fake_http.dart';
import '../../helpers/messages_fakes.dart';

const _teacher = MessageRecipient(accountId: '501', label: 'Przykładowa Ewa');

MessageDraft _draft({ReplyContext? reply}) =>
    MessageDraft.create(replyTo: reply, to: _teacher).copyWith(
      topic: reply == null ? 'Pytanie <o> zebranie' : null,
      body: 'Dzień dobry,\r\nczy 2 < 3 & 4 > 1?',
    );

({MessagesRepository repo, FakeMessagesServer server}) _repo(
  ResponseBody Function(RequestOptions) onSend, {
  ResponseBody Function(RequestOptions)? me,
}) {
  final server = FakeMessagesServer(
    api: {
      'me':
          me ??
          (_) => jsonBody({
            'data': {'accountId': 'K'},
          }),
      'messages': onSend,
      'messages/reply': onSend,
    },
  );
  return (
    repo: MessagesRepository(fakeMessagesClient(server).client),
    server: server,
  );
}

int _posts(FakeMessagesServer s) =>
    s.calls.where((c) => c.startsWith('POST')).length;

void main() {
  group('odczyt', () {
    test('strony skrzynki z parametrami page/limit', () async {
      final server = FakeMessagesServer(
        api: {
          'inbox/messages': (o) {
            final page = int.parse(o.uri.queryParameters['page']!);
            expect(
              o.uri.queryParameters['limit'],
              '${MessagesRepository.pageSize}',
            );
            return jsonBody({
              'data': [
                for (var i = 0; i < (page == 1 ? 20 : 5); i++)
                  inboxItem('$page-$i'),
              ],
              'total': 25,
            });
          },
        },
      );
      final repo = MessagesRepository(fakeMessagesClient(server).client);
      final first = await repo.fetchPage(MessageFolder.inbox, 1);
      expect(first.items, hasLength(20));
      expect(first.hasMore, isTrue);
      final second = await repo.fetchPage(MessageFolder.inbox, 2);
      expect(second.items, hasLength(5));
      expect(second.hasMore, isFalse);
    });

    test(
      'szczegóły i odbiorcy z przedmiotami (403 na przedmiotach nie przeszkadza)',
      () async {
        final server = FakeMessagesServer(
          api: {
            'outbox/messages/9': (_) => jsonBody({
              'data': {'topic': 'T', 'Message': fullMessage('<p>x</p>')},
            }),
            'receivers/groups/school-employees': (o) {
              expect(o.uri.queryParameters['receiverType'], 'teachers');
              return jsonBody({
                'receivers': [
                  {'accountId': '501', 'label': 'Przykładowa Ewa'},
                ],
              });
            },
            'receivers/student-subjects': (_) => jsonBody({}, status: 403),
          },
        );
        final repo = MessagesRepository(fakeMessagesClient(server).client);
        final d = await repo.fetchDetail(MessageFolder.outbox, '9');
        expect(d.bodyHtml, '<p>x</p>');
        final people = await repo.recipientsIn(
          const RecipientGroup(id: 'teachers', name: 'Nauczyciele'),
        );
        expect(people.single.subjects, isEmpty);
      },
    );
  });

  group('wysyłanie — kształt żądania', () {
    test(
      'nowa wiadomość: POST messages, base64, ucieczka HTML, bez originalMessageId',
      () async {
        late Map<String, dynamic> sent;
        final r = _repo((o) {
          sent = jsonDecode(o.data as String) as Map<String, dynamic>;
          expect(o.headers['Content-Type'], 'application/json');
          return jsonBody({
            'data': {'messageId': 123, 'status': 'sent'},
          }, status: 201);
        });
        final outcome = await r.repo.send(_draft());
        expect(
          outcome,
          isA<SendSucceeded>().having((s) => s.messageId, 'id', '123'),
        );
        expect(
          r.server.calls,
          contains('POST wiadomosci.librus.pl/api/messages'),
        );
        expect(sent['receivers'], {
          'schoolReceivers': [
            {'accountId': '501'},
          ],
        });
        expect(
          utf8.decode(base64.decode(sent['topic'] as String)),
          'Pytanie <o> zebranie',
        );
        expect(
          utf8.decode(base64.decode(sent['content'] as String)),
          'Dzień dobry,\nczy 2 &lt; 3 &amp; 4 &gt; 1?',
        );
        expect(sent['category'], 'normal');
        expect(sent.containsKey('storageId'), isTrue);
        expect(sent['storageId'], isNull);
        expect(sent.containsKey('originalMessageId'), isFalse);
      },
    );

    test(
      'odpowiedź w wątku: POST messages/reply z originalMessageId (liczba) i Re:',
      () async {
        late Map<String, dynamic> sent;
        final r = _repo((o) {
          sent = jsonDecode(o.data as String) as Map<String, dynamic>;
          return jsonBody({'data': {}});
        });
        final draft = _draft(
          reply: const ReplyContext(
            originalMessageId: '77',
            originalTopic: 'Zebranie',
          ),
        );
        expect(draft.topic, 'Re: Zebranie');
        final outcome = await r.repo.send(draft);
        expect(
          outcome,
          isA<SendSucceeded>().having((s) => s.messageId, 'id', isNull),
        );
        expect(
          r.server.calls,
          contains('POST wiadomosci.librus.pl/api/messages/reply'),
        );
        expect(sent['originalMessageId'], 77);
      },
    );

    test('sesja sprawdzana odczytem przed jedynym POST', () async {
      final r = _repo((_) => jsonBody({}));
      await r.repo.send(_draft());
      final calls = r.server.calls.where((c) => c.contains('/api/')).toList();
      expect(calls, [
        'GET wiadomosci.librus.pl/api/me',
        'POST wiadomosci.librus.pl/api/messages',
      ]);
    });
  });

  group('wysyłanie — wyniki', () {
    Future<(SendOutcome, int)> outcomeFor(
      ResponseBody Function(RequestOptions) onSend,
    ) async {
      final r = _repo(onSend);
      final o = await r.repo.send(_draft());
      return (o, _posts(r.server));
    }

    test('200 z błędem w treści to NIE sukces', () async {
      for (final body in [
        {
          'errors': ['Coś poszło nie tak'],
        },
        {
          'data': {'status': 'failed'},
        },
        {'status': 'error'},
      ]) {
        final (o, posts) = await outcomeFor((_) => jsonBody(body));
        expect(o, isA<SendUnknown>(), reason: '$body');
        expect(posts, 1);
      }
    });

    test('200 z HTML (np. strona logowania) = nie wiadomo', () async {
      final (o, _) = await outcomeFor((_) => textBody('<html>Zaloguj</html>'));
      expect(o, isA<SendUnknown>());
    });

    test('4xx = nie wysłano, z komunikatami serwera', () async {
      final (o, posts) = await outcomeFor(
        (_) => jsonBody({
          'errors': [
            {'message': 'Temat jest za długi'},
          ],
        }, status: 422),
      );
      expect(
        o,
        isA<SendRejected>().having((r) => r.serverMessages, 'msgs', [
          'Temat jest za długi',
        ]),
      );
      expect(posts, 1);
    });

    test('401, 403, 3xx, 429 = nie wysłano', () async {
      for (final status in [401, 403, 302, 429]) {
        final (o, posts) = await outcomeFor(
          (_) => jsonBody({}, status: status),
        );
        expect(o, isA<SendRejected>(), reason: '$status');
        expect(posts, 1, reason: 'bez ponowienia przy $status');
      }
    });

    test('5xx = nie wiadomo, bez ponowienia', () async {
      for (final status in [500, 502, 504]) {
        final (o, posts) = await outcomeFor(
          (_) => jsonBody({}, status: status),
        );
        expect(o, isA<SendUnknown>(), reason: '$status');
        expect(posts, 1);
      }
    });

    test(
      'timeout po wysłaniu = nie wiadomo; brak połączenia przed = nie wysłano',
      () async {
        final (late, _) = await outcomeFor(
          (o) => throw DioException.receiveTimeout(
            timeout: const Duration(seconds: 20),
            requestOptions: o,
          ),
        );
        expect(late, isA<SendUnknown>());
        final (early, _) = await outcomeFor(
          (o) => throw DioException.connectionTimeout(
            timeout: const Duration(seconds: 10),
            requestOptions: o,
          ),
        );
        expect(early, isA<SendRejected>());
      },
    );

    test('nieudany odczyt kontrolny: brak POST', () async {
      final r = _repo(
        (_) => jsonBody({}),
        me: (_) => jsonBody({}, status: 401),
      );
      expect(await r.repo.send(_draft()), isA<SendRejected>());
      expect(_posts(r.server), 0);
    });

    test('niepoprawny szkic: brak jakiegokolwiek żądania', () async {
      final r = _repo((_) => jsonBody({}));
      final empty = MessageDraft.create();
      expect(await r.repo.send(empty), isA<SendRejected>());
      expect(r.server.calls, isEmpty);
    });

    test(
      'odpowiedź z nienumerycznym identyfikatorem oryginału jest odrzucana',
      () async {
        final r = _repo((_) => jsonBody({}));
        final d = _draft(
          reply: const ReplyContext(
            originalMessageId: 'abc',
            originalTopic: 'T',
          ),
        );
        expect(await r.repo.send(d), isA<SendRejected>());
        expect(_posts(r.server), 0);
      },
    );
  });

  test('klasyfikacja nie zależy wyłącznie od kodu 200', () {
    expect(
      MessagesRepository.classifySendResponse(const RawResponse(200, '')),
      isA<SendSucceeded>(),
    );
    expect(
      MessagesRepository.classifySendResponse(
        const RawResponse(200, '{"errors":[]}'),
      ),
      isA<SendSucceeded>(),
      reason: 'pusta lista błędów',
    );
    expect(
      MessagesRepository.classifySendResponse(
        const RawResponse(200, '{"errors":{"topic":"za długi"}}'),
      ),
      isA<SendUnknown>(),
    );
  });
}
