import '../../../core/errors/synergia_exception.dart';
import '../../../shared/json_read.dart';
import '../domain/message.dart';
import '../domain/message_body.dart';

/// Odwzorowanie odpowiedzi `wiadomosci.librus.pl/api` (stan 2026-10, zob.
/// docs/messages-api.md) na modele domeny. Rekordy bez identyfikatora są
/// pomijane; brak oczekiwanej struktury zgłasza [UnexpectedResponseException].
abstract final class MessagesParser {
  /// Lista: `{"data": [...], "total": N}`; niektóre skrzynki zwracają gołą listę.
  static MessagePage page(
    Object? json,
    MessageFolder folder, {
    required int page,
    required int limit,
  }) {
    final List<Object?> raw;
    int? total;
    if (json is List) {
      raw = json;
    } else if (json is Map && json['data'] is List) {
      raw = json['data'] as List;
      total = readInt(json['total']);
    } else {
      throw UnexpectedResponseException(
        '${folder.name}/messages: brak listy; ${_shape(json)}',
      );
    }
    final items = [
      for (final item in raw.whereType<Map>()) ?_summary(item, folder),
    ];
    if (raw.isNotEmpty && items.isEmpty) {
      throw UnexpectedResponseException(
        '${folder.name}/messages: ${raw.length} rekordów, żadnego nie odczytano',
      );
    }
    return MessagePage(items: items, page: page, limit: limit, total: total);
  }

  static MessageSummary? _summary(Map item, MessageFolder folder) {
    final id = readString(item['messageId']) ?? readString(item['id']);
    if (id == null) return null;
    final counterpart = folder == MessageFolder.outbox
        ? _name(
            item['receiverName'],
            item['receiverFirstName'],
            item['receiverLastName'],
          )
        : _name(
            item['senderName'],
            item['senderFirstName'],
            item['senderLastName'],
          );
    return MessageSummary(
      id: id,
      folder: folder,
      counterpart: counterpart ?? '(nieznany)',
      topic: readString(item['topic']) ?? '(bez tematu)',
      preview: previewText(decodeMessageContent(readString(item['content']))),
      sentAt: readDateTime(item['sendDate']),
      readAt: readDateTime(item['readDate']),
      hasAttachments: readBool(item['isAnyFileAttached']),
    );
  }

  /// Szczegóły: `{"data": {...}}`.
  static MessageDetail detail(Object? json, MessageFolder folder, String id) {
    final data = _data(json);
    if (data == null) {
      throw UnexpectedResponseException(
        '${folder.name}/messages/:id: brak obiektu data; ${_shape(json)}',
      );
    }
    return MessageDetail(
      id: readString(data['messageId']) ?? id,
      folder: folder,
      senderId: readString(data['senderId']),
      senderName:
          _name(
            data['senderName'],
            data['senderFirstName'],
            data['senderLastName'],
          ) ??
          (folder == MessageFolder.outbox ? 'Ty' : '(nieznany)'),
      senderGroup: readString(data['senderGroup']),
      topic: readString(data['topic']) ?? '(bez tematu)',
      bodyHtml: decodeMessageContent(
        readString(data['Message']) ?? readString(data['content']),
      ),
      sentAt: readDateTime(data['sendDate']),
      readAt: readDateTime(data['readDate']),
      attachments: [
        if (data['attachments'] case final List list)
          for (final a in list.whereType<Map>())
            if (readString(a['id']) case final aid?)
              MessageAttachment(
                id: aid,
                filename:
                    readString(a['filename']) ??
                    readString(a['name']) ??
                    'załącznik',
              ),
      ],
      receivers: [
        if (data['receivers'] case final List list)
          for (final r in list.whereType<Map>())
            SentReceiver(
              name:
                  _name(r['name'], r['firstName'], r['lastName']) ??
                  '(nieznany)',
              group: readString(r['group']),
              readAt: readDateTime(r['readed']),
            ),
      ],
      receiversCount: readInt(data['receiversCount']),
      noReply: readBool(data['noReply']),
    );
  }

  /// `inbox/unreadMessagesCount` → liczba nieprzeczytanych w Odebranych.
  static int unreadInbox(Object? json) {
    final data = _data(json);
    final value = readInt(data?['inbox']);
    if (value == null) {
      throw UnexpectedResponseException(
        'unreadMessagesCount: brak pola inbox; ${_shape(json)}',
      );
    }
    return value;
  }

  /// `me` → identyfikator konta (klucz lokalnych wiadomości roboczych).
  static String accountKey(Object? json) {
    final data = _data(json) ?? (json is Map ? json : null);
    final id = readString(data?['accountId']) ?? readString(data?['id']);
    if (id == null) {
      throw UnexpectedResponseException('me: brak accountId; ${_shape(json)}');
    }
    return id;
  }

  /// `receivers/types?includeClass=true` → grupy, do których można pisać.
  /// Najpierw znane grupy pracowników w stałej kolejności, potem pozostałe;
  /// pomijamy grupy spoza pracowników (rady rodziców, własne grupy, wsparcie
  /// Librusa) — wymagają innych endpointów, niezweryfikowanych.
  static List<RecipientGroup> recipientGroups(Object? json) {
    final list = _data(json)?['list'];
    if (list is! List) {
      throw UnexpectedResponseException(
        'receivers/types: brak listy; ${_shape(json)}',
      );
    }
    final offered = [
      for (final g in list.whereType<Map>())
        if ((readString(g['id']), readString(g['name'])) case (
          final id?,
          final name?,
        ))
          if (!skippedGroups.contains(id)) RecipientGroup(id: id, name: name),
    ];
    int rank(RecipientGroup g) {
      final i = staffGroupOrder.indexOf(g.id);
      return i < 0 ? staffGroupOrder.length : i;
    }

    // Stabilnie: przy równej randze zostaje kolejność Librusa.
    final ordered = offered.indexed.toList()
      ..sort((a, b) {
        final byRank = rank(a.$2).compareTo(rank(b.$2));
        return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
      });
    return [for (final (_, group) in ordered) group];
  }

  static const staffGroupOrder = [
    'tutors',
    'teachers',
    'headteachers',
    'secretary',
    'counsellor',
    'specialCounsellor',
    'psychologist',
    'pedagogue',
    'speechTherapist',
    'librarian',
    'otherSpecialist',
    'typhlopedagogue',
    'admin',
  ];
  static const skippedGroups = {
    'parentsCouncil',
    'schoolParentsCouncil',
    'customGroups',
    'sadmin',
  };

  /// `receivers/groups/school-employees?receiverType=<id>` → osoby w grupie.
  static List<MessageRecipient> groupRecipients(
    Object? json,
    RecipientGroup group, {
    Map<String, List<String>> subjectsByTeacher = const {},
  }) {
    final list = json is Map
        ? (json['receivers'] ?? _data(json)?['receivers'])
        : json;
    if (list is! List) {
      throw UnexpectedResponseException(
        'school-employees: brak listy receivers; ${_shape(json)}',
      );
    }
    return [
      for (final r in list.whereType<Map>())
        if ((readString(r['accountId']), readString(r['label'])) case (
          final id?,
          final label?,
        ))
          MessageRecipient(
            accountId: id,
            label: label,
            groupId: group.id,
            groupName: group.name,
            subjects: subjectsByTeacher[id] ?? const [],
            isAvailable: switch (r['availabilityStatus']) {
              final Map s =>
                !s.containsKey('isAvailable') || readBool(s['isAvailable']),
              _ => true,
            },
            returnAt: switch (r['availabilityStatus']) {
              final Map s => readDateTime(s['returnAt']),
              _ => null,
            },
          ),
    ];
  }

  /// `receivers/student-subjects` → przedmioty nauczycieli ucznia.
  static Map<String, List<String>> teacherSubjects(Object? json) {
    final list = json is List
        ? json
        : _data(json) ?? (json is Map ? json['data'] : null);
    final result = <String, List<String>>{};
    if (list is! List) return result;
    for (final e in list.whereType<Map>()) {
      final id = readString(e['teacherIdentifier']);
      final subject = readString(e['subject']);
      if (id != null && subject != null) (result[id] ??= []).add(subject);
    }
    return result;
  }

  static Map<String, dynamic>? _data(Object? json) {
    if (json is! Map) return null;
    final data = json['data'];
    return data is Map<String, dynamic>
        ? data
        : (data is Map ? data.cast<String, dynamic>() : null);
  }

  static String? _name(Object? full, Object? first, Object? last) {
    final f = readString(full);
    if (f != null) return f;
    final parts = [readString(first), readString(last)].nonNulls.join(' ');
    return parts.isEmpty ? null : parts;
  }

  /// Opis struktury bez wartości (do komunikatów błędów).
  static String _shape(Object? json) => switch (json) {
    final Map m =>
      'klucze: ${(m.keys.map((k) => '$k').toList()..sort()).join(', ')}',
    final List l => 'lista (${l.length})',
    null => 'pusta odpowiedź',
    _ => 'typ ${json.runtimeType}',
  };
}
