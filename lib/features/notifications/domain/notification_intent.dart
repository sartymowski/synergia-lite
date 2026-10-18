import 'dart:convert';

/// Dokąd prowadzi kliknięte powiadomienie. Payload zawiera wyłącznie rodzaj,
/// identyfikator wiadomości i skrót identyfikatora konta — żadnych ciasteczek,
/// tokenów ani danych logowania.
sealed class NotificationIntent {
  const NotificationIntent();

  String encode();

  static NotificationIntent? decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final json = jsonDecode(payload);
      if (json is! Map || json['v'] != 1) return null;
      final owner = json['o'];
      switch (json['k']) {
        case 'm':
          final id = json['id'];
          if (owner is String && id is String && _validId.hasMatch(id)) {
            return OpenMessage(ownerTag: owner, messageId: id);
          }
        case 'i':
          if (owner is String) return OpenInbox(ownerTag: owner);
        case 's':
          return const OpenApp();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  static final _validId = RegExp(r'^\d{1,20}$');
}

final class OpenMessage extends NotificationIntent {
  const OpenMessage({required this.ownerTag, required this.messageId});

  final String ownerTag;
  final String messageId;

  @override
  String encode() =>
      jsonEncode({'v': 1, 'k': 'm', 'o': ownerTag, 'id': messageId});

  @override
  bool operator ==(Object other) =>
      other is OpenMessage &&
      other.ownerTag == ownerTag &&
      other.messageId == messageId;

  @override
  int get hashCode => Object.hash(ownerTag, messageId);
}

final class OpenInbox extends NotificationIntent {
  const OpenInbox({required this.ownerTag});

  final String ownerTag;

  @override
  String encode() => jsonEncode({'v': 1, 'k': 'i', 'o': ownerTag});

  @override
  bool operator ==(Object other) =>
      other is OpenInbox && other.ownerTag == ownerTag;

  @override
  int get hashCode => ownerTag.hashCode;
}

/// Powiadomienie o stanie (np. wymagane ponowne logowanie) — tylko otwiera aplikację.
final class OpenApp extends NotificationIntent {
  const OpenApp();

  @override
  String encode() => jsonEncode({'v': 1, 'k': 's'});

  @override
  bool operator ==(Object other) => other is OpenApp;

  @override
  int get hashCode => 0;
}

/// FNV-1a (32 bity). Deterministyczny — ta sama wiadomość ma zawsze ten sam
/// identyfikator powiadomienia, także w różnych kontekstach wykonania.
int fnv1a32(String s) {
  var hash = 0x811c9dc5;
  for (final unit in utf8.encode(s)) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xffffffff;
  }
  return hash;
}

/// Skrót identyfikatora konta do payloadu (nie ujawnia samego identyfikatora).
String ownerTag(String owner) =>
    fnv1a32('owner:$owner').toRadixString(16).padLeft(8, '0');

abstract final class NotificationIds {
  static const summary = 1;
  static const status = 2;

  /// Stały identyfikator dla wiadomości: ponowne pokazanie zastępuje
  /// istniejące powiadomienie zamiast dodawać duplikat.
  static int forMessage(String owner, String messageId) {
    final h = fnv1a32('msg:$owner:$messageId') & 0x7fffffff;
    return h < 100 ? h + 100 : h;
  }
}
