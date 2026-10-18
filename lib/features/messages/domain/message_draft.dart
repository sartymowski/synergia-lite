import 'message.dart';

/// Powiązanie odpowiedzi z oryginalną wiadomością (wątek po stronie Librusa).
class ReplyContext {
  const ReplyContext({
    required this.originalMessageId,
    required this.originalTopic,
  });

  final String originalMessageId;
  final String originalTopic;

  Map<String, Object?> toJson() => {
    'originalMessageId': originalMessageId,
    'originalTopic': originalTopic,
  };

  static ReplyContext? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['originalMessageId'];
    final topic = json['originalTopic'];
    if (id is! String || topic is! String) return null;
    return ReplyContext(originalMessageId: id, originalTopic: topic);
  }
}

/// Wiadomość w przygotowaniu. Przechowywana lokalnie (zaszyfrowana) do czasu
/// potwierdzonego wysłania albo świadomego usunięcia.
class MessageDraft {
  const MessageDraft({
    required this.id,
    required this.updatedAt,
    this.recipients = const [],
    this.topic = '',
    this.body = '',
    this.replyTo,
    this.unknownSendAt,
  });

  factory MessageDraft.create({
    ReplyContext? replyTo,
    MessageRecipient? to,
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    return MessageDraft(
      id: 'd${at.microsecondsSinceEpoch}',
      updatedAt: at,
      recipients: to == null ? const [] : [to],
      topic: replyTo == null ? '' : replyTopic(replyTo.originalTopic),
      replyTo: replyTo,
    );
  }

  final String id;
  final DateTime updatedAt;
  final List<MessageRecipient> recipients;
  final String topic;
  final String body;
  final ReplyContext? replyTo;

  /// Ostatnia próba wysłania zakończyła się niejednoznacznie — przed kolejną
  /// trzeba sprawdzić folder Wysłane.
  final DateTime? unknownSendAt;

  bool get isReply => replyTo != null;

  bool get isEmpty =>
      recipients.isEmpty && topic.trim().isEmpty && body.trim().isEmpty;

  MessageDraft copyWith({
    List<MessageRecipient>? recipients,
    String? topic,
    String? body,
    DateTime? updatedAt,
    DateTime? unknownSendAt,
    bool clearUnknownSend = false,
  }) => MessageDraft(
    id: id,
    updatedAt: updatedAt ?? DateTime.now(),
    recipients: recipients ?? this.recipients,
    topic: topic ?? this.topic,
    body: body ?? this.body,
    replyTo: replyTo,
    unknownSendAt: clearUnknownSend
        ? null
        : (unknownSendAt ?? this.unknownSendAt),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'recipients': [for (final r in recipients) r.toJson()],
    'topic': topic,
    'body': body,
    'replyTo': replyTo?.toJson(),
    'unknownSendAt': unknownSendAt?.toUtc().toIso8601String(),
  };

  static MessageDraft? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final updated = DateTime.tryParse('${json['updatedAt']}');
    if (id is! String || updated == null) return null;
    final unknown = json['unknownSendAt'];
    return MessageDraft(
      id: id,
      updatedAt: updated.toLocal(),
      recipients: [
        if (json['recipients'] case final List list)
          for (final r in list) ?MessageRecipient.fromJson(r),
      ],
      topic: json['topic'] is String ? json['topic'] as String : '',
      body: json['body'] is String ? json['body'] as String : '',
      replyTo: ReplyContext.fromJson(json['replyTo']),
      unknownSendAt: unknown is String
          ? DateTime.tryParse(unknown)?.toLocal()
          : null,
    );
  }
}

/// Limity po stronie aplikacji (zachowawcze; Librus ich nie dokumentuje).
abstract final class MessageLimits {
  static const maxRecipients = 50;
  static const maxTopicLength = 200;
  static const maxBodyLength = 10000;
}

/// „Re: temat” bez podwajania przedrostka, w limicie długości tematu.
String replyTopic(String topic) {
  final t = topic.trim();
  final reply = t.toLowerCase().startsWith('re:') ? t : 'Re: $t';
  return reply.length > MessageLimits.maxTopicLength
      ? reply.substring(0, MessageLimits.maxTopicLength)
      : reply;
}

enum DraftProblem {
  noRecipients,
  tooManyRecipients,
  duplicateRecipient,
  noTopic,
  topicTooLong,
  noBody,
  bodyTooLong,
}

/// Walidacja przed wysłaniem. Pusta lista = gotowe do wysłania.
List<DraftProblem> validateDraft(MessageDraft d) {
  final ids = d.recipients.map((r) => r.accountId).toList();
  return [
    if (ids.isEmpty) DraftProblem.noRecipients,
    if (ids.length > MessageLimits.maxRecipients)
      DraftProblem.tooManyRecipients,
    if (ids.toSet().length != ids.length) DraftProblem.duplicateRecipient,
    if (d.topic.trim().isEmpty) DraftProblem.noTopic,
    if (d.topic.trim().length > MessageLimits.maxTopicLength)
      DraftProblem.topicTooLong,
    if (d.body.trim().isEmpty) DraftProblem.noBody,
    if (d.body.trim().length > MessageLimits.maxBodyLength)
      DraftProblem.bodyTooLong,
  ];
}

const draftProblemMessages = {
  DraftProblem.noRecipients: 'Wybierz co najmniej jednego odbiorcę.',
  DraftProblem.tooManyRecipients:
      'Maksymalnie ${MessageLimits.maxRecipients} odbiorców.',
  DraftProblem.duplicateRecipient: 'Odbiorca jest wybrany więcej niż raz.',
  DraftProblem.noTopic: 'Wpisz temat.',
  DraftProblem.topicTooLong:
      'Temat może mieć najwyżej ${MessageLimits.maxTopicLength} znaków.',
  DraftProblem.noBody: 'Wpisz treść wiadomości.',
  DraftProblem.bodyTooLong:
      'Treść może mieć najwyżej ${MessageLimits.maxBodyLength} znaków.',
};
