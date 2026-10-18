import 'dart:convert';

import 'web_cookie.dart';

/// Ciasteczka sesji dla `synergia.librus.pl`, przejęte z WebView po
/// zalogowaniu się użytkownika na oficjalnej stronie Librusa.
///
/// Wartości są wrażliwe: [toString] celowo pokazuje tylko nazwy.
class SessionCookies {
  SessionCookies(Map<String, String> cookies, {DateTime? obtainedAt})
    : _cookies = Map.unmodifiable(cookies),
      obtainedAt = obtainedAt ?? DateTime.now();

  factory SessionCookies.fromWebCookies(Iterable<WebCookie> cookies) =>
      SessionCookies({for (final c in cookies) c.name: c.value});

  final Map<String, String> _cookies;
  final DateTime obtainedAt;

  /// Cookie ustawiane dopiero po zakończeniu przepływu OAuth
  /// (por. librus-api #88). `DZIENNIKSID` pojawia się nawet bez logowania,
  /// więc nie świadczy o aktywnej sesji.
  static const authMarker = 'oauth_token';

  static const host = 'synergia.librus.pl';

  bool get isEmpty => _cookies.isEmpty;
  Iterable<String> get names => _cookies.keys;
  bool get hasAuthMarker => _cookies.containsKey(authMarker);

  String toHeader() =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  /// Uwzględnia nagłówki `Set-Cookie` z odpowiedzi (np. rotację DZIENNIKSID).
  SessionCookies merge(Iterable<String> setCookieHeaders) {
    final next = Map.of(_cookies);
    var changed = false;
    for (final header in setCookieHeaders) {
      final parsed = _parseSetCookie(header);
      if (parsed == null) continue;
      if (parsed.deleted) {
        changed |= next.remove(parsed.name) != null;
      } else if (next[parsed.name] != parsed.value) {
        next[parsed.name] = parsed.value;
        changed = true;
      }
    }
    return changed ? SessionCookies(next, obtainedAt: obtainedAt) : this;
  }

  String toJson() => jsonEncode({
    'cookies': _cookies,
    'obtainedAt': obtainedAt.toUtc().toIso8601String(),
  });

  static SessionCookies? tryFromJson(String? raw) {
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final cookies = (map['cookies'] as Map).map(
        (k, v) => MapEntry(k as String, v as String),
      );
      return SessionCookies(
        cookies,
        obtainedAt: DateTime.parse(map['obtainedAt'] as String).toLocal(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'SessionCookies(${_cookies.keys.join(', ')})';
}

({String name, String value, bool deleted})? _parseSetCookie(String header) {
  final cookie = WebCookie.parse(header);
  if (cookie == null) return null;
  final domain = cookie.domain?.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
  if (domain != null &&
      domain.isNotEmpty &&
      !SessionCookies.host.endsWith(domain)) {
    return null;
  }
  final expires = cookie.expires;
  final deleted =
      cookie.value.isEmpty ||
      cookie.value == 'deleted' ||
      (expires != null && !expires.isAfter(DateTime.now()));
  return (name: cookie.name, value: cookie.value, deleted: deleted);
}
