/// Modele domenowe modułu Wiadomości. Nie znają nazw pól API — mapowanie
/// z odpowiedzi `wiadomosci.librus.pl/api` żyje w `data/messages_parser.dart`.
library;

enum MessageFolder {
  inbox('Odebrane'),
  outbox('Wysłane'),
  drafts('Robocze');

  const MessageFolder(this.label);

  final String label;

  /// Foldery przechowywane na serwerze (robocze są lokalne).
  bool get isRemote => this != drafts;
}

class MessageAttachment {
  const MessageAttachment({required this.id, required this.filename});

  final String id;
  final String filename;
}

/// Odbiorca, do którego konto może napisać (pracownik szkoły).
class MessageRecipient {
  const MessageRecipient({
    required this.accountId,
    required this.label,
    this.groupId,
    this.groupName,
    this.subjects = const [],
    this.isAvailable = true,
    this.returnAt,
  });

  /// Identyfikator konta, na który wysyła się wiadomość.
  final String accountId;
  final String label;
  final String? groupId;
  final String? groupName;

  /// Przedmioty, których uczy ucznia (jeśli Librus je podał).
  final List<String> subjects;
  final bool isAvailable;
  final DateTime? returnAt;

  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return label.toLowerCase().contains(q) ||
        (groupName?.toLowerCase().contains(q) ?? false) ||
        subjects.any((s) => s.toLowerCase().contains(q));
  }

  Map<String, Object?> toJson() => {'accountId': accountId, 'label': label};

  static MessageRecipient? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['accountId'];
    final label = json['label'];
    if (id is! String || label is! String) return null;
    return MessageRecipient(accountId: id, label: label);
  }
}

class RecipientGroup {
  const RecipientGroup({required this.id, required this.name});

  final String id;
  final String name;

  @override
  bool operator ==(Object other) => other is RecipientGroup && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

class MessageSummary {
  const MessageSummary({
    required this.id,
    required this.folder,
    required this.counterpart,
    required this.topic,
    required this.preview,
    this.sentAt,
    this.readAt,
    this.hasAttachments = false,
  });

  final String id;
  final MessageFolder folder;

  /// Nadawca (Odebrane) albo odbiorca (Wysłane).
  final String counterpart;
  final String topic;

  /// Początek treści jako zwykły tekst (Librus obcina go po bajtach).
  final String preview;
  final DateTime? sentAt;
  final DateTime? readAt;
  final bool hasAttachments;

  bool get isUnread => folder == MessageFolder.inbox && readAt == null;

  MessageSummary markedRead(DateTime at) => MessageSummary(
    id: id,
    folder: folder,
    counterpart: counterpart,
    topic: topic,
    preview: preview,
    sentAt: sentAt,
    readAt: readAt ?? at,
    hasAttachments: hasAttachments,
  );
}

/// Odbiorca wysłanej wiadomości wraz ze statusem odczytu.
class SentReceiver {
  const SentReceiver({required this.name, this.group, this.readAt});

  final String name;
  final String? group;
  final DateTime? readAt;
}

class MessageDetail {
  const MessageDetail({
    required this.id,
    required this.folder,
    required this.senderName,
    required this.topic,
    required this.bodyHtml,
    this.senderId,
    this.senderGroup,
    this.sentAt,
    this.readAt,
    this.attachments = const [],
    this.receivers = const [],
    this.receiversCount,
    this.noReply = false,
  });

  final String id;
  final MessageFolder folder;
  final String? senderId;
  final String senderName;
  final String? senderGroup;
  final String topic;

  /// Treść po zdekodowaniu (HTML Librusa). Wyświetlana wyłącznie przez
  /// bezpieczny konwerter — nigdy w WebView.
  final String bodyHtml;
  final DateTime? sentAt;
  final DateTime? readAt;
  final List<MessageAttachment> attachments;

  /// Tylko dla Wysłanych.
  final List<SentReceiver> receivers;
  final int? receiversCount;

  /// Nadawca wyłączył odpowiedzi.
  final bool noReply;

  /// Odpowiedź w wątku (`messages/reply`) wymaga identyfikatora nadawcy.
  bool get canReply =>
      folder == MessageFolder.inbox && !noReply && senderId != null;
}

class MessagePage {
  const MessagePage({
    required this.items,
    required this.page,
    required this.limit,
    this.total,
  });

  final List<MessageSummary> items;
  final int page;
  final int limit;
  final int? total;

  bool get hasMore =>
      total != null ? page * limit < total! : items.length >= limit;
}
