import 'dart:convert';

import '../../../core/errors/synergia_exception.dart';
import '../domain/message.dart';
import '../domain/message_draft.dart';
import '../domain/send_outcome.dart';
import 'messages_api_client.dart';
import 'messages_parser.dart';

class MessagesRepository {
  MessagesRepository(this._api);

  static const pageSize = 20;

  final MessagesApiClient _api;
  Map<String, List<String>>? _subjects;

  Future<MessagePage> fetchPage(MessageFolder folder, int page) async {
    assert(folder.isRemote);
    final json = await _api.get(
      '${folder.name}/messages',
      query: {'page': '$page', 'limit': '$pageSize'},
    );
    return MessagesParser.page(json, folder, page: page, limit: pageSize);
  }

  /// Uwaga: otwarcie wiadomości z Odebranych oznacza ją jako przeczytaną —
  /// tak samo jak w aplikacji internetowej Librusa.
  Future<MessageDetail> fetchDetail(MessageFolder folder, String id) async {
    final json = await _api.get(
      '${folder.name}/messages/${Uri.encodeComponent(id)}',
    );
    return MessagesParser.detail(json, folder, id);
  }

  Future<int> unreadInboxCount() async =>
      MessagesParser.unreadInbox(await _api.get('inbox/unreadMessagesCount'));

  Future<String> accountKey() async =>
      MessagesParser.accountKey(await _api.get('me'));

  Future<List<RecipientGroup>> recipientGroups() async =>
      MessagesParser.recipientGroups(
        await _api.get('receivers/types', query: {'includeClass': 'true'}),
      );

  Future<List<MessageRecipient>> recipientsIn(RecipientGroup group) async {
    final json = await _api.get(
      'receivers/groups/school-employees',
      query: {'receiverType': group.id},
    );
    return MessagesParser.groupRecipients(
      json,
      group,
      subjectsByTeacher: await _teacherSubjects(),
    );
  }

  /// Przedmioty są dodatkiem — np. konto przedszkolne dostaje tu 403.
  Future<Map<String, List<String>>> _teacherSubjects() async {
    if (_subjects case final cached?) return cached;
    try {
      return _subjects = MessagesParser.teacherSubjects(
        await _api.get('receivers/student-subjects'),
      );
    } on PermissionDeniedException {
      return _subjects = const {};
    } on ServerException {
      return _subjects = const {};
    }
  }

  /// Jedna próba wysłania — nigdy nie ponawiana. Nowa wiadomość: `POST messages`;
  /// odpowiedź w wątku: `POST messages/reply` z `originalMessageId`.
  Future<SendOutcome> send(MessageDraft draft) async {
    if (validateDraft(draft).isNotEmpty) {
      return const SendRejected(
        'Formularz zawiera błędy — wiadomość nie została wysłana.',
      );
    }
    final reply = draft.replyTo;
    final originalId = reply == null
        ? null
        : int.tryParse(reply.originalMessageId);
    if (reply != null && originalId == null) {
      return const SendRejected(
        'Nieprawidłowy identyfikator wiadomości, na którą odpowiadasz.',
      );
    }

    // Sesję sprawdzamy odczytem (z ewentualnym odnowieniem), nie wysyłką.
    try {
      await _api.get('me');
    } on SynergiaException catch (e) {
      return SendRejected('${e.message} Wiadomość nie została wysłana.');
    }

    final body = <String, Object?>{
      'receivers': {
        'schoolReceivers': [
          for (final r in draft.recipients) {'accountId': r.accountId},
        ],
      },
      'topic': encodeTopic(draft.topic),
      'content': encodeBody(draft.body),
      'storageId': null,
      'category': 'normal',
      'originalMessageId': ?originalId,
    };

    final RawResponse response;
    try {
      response = await _api.postOnce(
        reply == null ? 'messages' : 'messages/reply',
        body,
      );
    } on SendTransportException catch (e) {
      return e.requestMayHaveReachedServer
          ? const SendUnknown(
              'Połączenie zostało przerwane lub upłynął limit czasu. Nie wiadomo, '
              'czy wiadomość została wysłana.',
            )
          : const SendRejected(
              'Brak połączenia z serwerem — wiadomość nie została wysłana.',
            );
    }
    return classifySendResponse(response);
  }

  /// Temat: UTF-8 w base64 (jak aplikacja internetowa Librusa).
  static String encodeTopic(String topic) =>
      base64.encode(utf8.encode(topic.trim()));

  /// Treść jako zwykły tekst: ucieczka znaków HTML (czytnik pokazuje HTML),
  /// nowe linie zostają; UTF-8 w base64.
  static String encodeBody(String text) {
    final escaped = const HtmlEscape(
      HtmlEscapeMode.element,
    ).convert(text.trim().replaceAll('\r\n', '\n'));
    return base64.encode(utf8.encode(escaped));
  }

  static SendOutcome classifySendResponse(RawResponse r) {
    final status = r.statusCode;
    if (status >= 200 && status < 300) {
      final json = r.tryJson();
      if (r.body.trim().isNotEmpty && json == null) {
        return const SendUnknown(
          'Serwer odpowiedział w nieoczekiwany sposób. Nie wiadomo, czy wiadomość została wysłana.',
        );
      }
      if (json is Map) {
        final data = json['data'] is Map ? json['data'] as Map : const {};
        final state = '${data['status'] ?? json['status'] ?? ''}'.toLowerCase();
        if (_hasErrors(json['errors']) ||
            const {'error', 'failed', 'rejected'}.contains(state)) {
          return const SendUnknown(
            'Serwer zgłosił błąd mimo kodu sukcesu. Nie wiadomo, czy wiadomość została wysłana.',
          );
        }
        final id = data['messageId'] ?? data['id'] ?? json['messageId'];
        return SendSucceeded(messageId: id == null ? null : '$id');
      }
      return const SendSucceeded();
    }
    if (status >= 300 && status < 400 || status == 401) {
      return const SendRejected(
        'Sesja wiadomości została odrzucona — wiadomość nie została wysłana.',
      );
    }
    if (status == 403) {
      return const SendRejected(
        'Brak uprawnień do wysłania tej wiadomości — nie została wysłana.',
      );
    }
    if (status == 429) {
      return const SendRejected(
        'Zbyt wiele zapytań — wiadomość nie została wysłana. Spróbuj za chwilę.',
      );
    }
    if (status >= 400 && status < 500) {
      return SendRejected(
        'Librus odrzucił wiadomość (HTTP $status) — nie została wysłana.',
        serverMessages: _messages(r.tryJson()),
      );
    }
    return SendUnknown(
      'Błąd serwera (HTTP $status). Nie wiadomo, czy wiadomość została wysłana.',
    );
  }

  static bool _hasErrors(Object? errors) => switch (errors) {
    null || false => false,
    final List l => l.isNotEmpty,
    final Map m => m.isNotEmpty,
    final String s => s.trim().isNotEmpty,
    _ => true,
  };

  /// Komunikaty z treści błędu (do pokazania użytkownikowi, nie do logów).
  static List<String> _messages(Object? json) {
    final found = <String>[];
    void visit(Object? v) {
      if (found.length >= 5) return;
      switch (v) {
        case final String s when s.trim().isNotEmpty:
          found.add(
            s.trim().length > 200 ? '${s.trim().substring(0, 200)}…' : s.trim(),
          );
        case final List l:
          l.forEach(visit);
        case final Map m:
          visit(m['message'] ?? m['errors'] ?? m.values.toList());
      }
    }

    if (json is Map) visit(json['errors'] ?? json['message']);
    return found;
  }
}
