import 'dart:io' show HttpDate, HttpException;

/// Ciasteczko odczytane z magazynu WebView wraz z atrybutami.
/// Na starszych WebView (bez GET_COOKIE_INFO) atrybuty są nieznane (`null`).
class WebCookie {
  const WebCookie({
    required this.name,
    required this.value,
    this.domain,
    this.path,
    this.secure,
    this.httpOnly,
    this.sameSite,
    this.expires,
    this.attributesKnown = false,
  });

  final String name;
  final String value;
  final String? domain;
  final String? path;
  final bool? secure;
  final bool? httpOnly;
  final String? sameSite;
  final DateTime? expires;
  final bool attributesKnown;

  /// Ciasteczko sesyjne (bez Expires/Max-Age) — znika po zamknięciu przeglądarki
  /// po stronie WebView, a o jego ważności decyduje serwer.
  bool? get isSession => attributesKnown ? expires == null : null;

  static WebCookie? parse(String raw) {
    final parts = raw.split(';');
    final eq = parts.first.indexOf('=');
    if (eq <= 0) return null;
    String? domain, path, sameSite;
    DateTime? expires;
    var secure = false, httpOnly = false;
    for (final attr in parts.skip(1)) {
      final i = attr.indexOf('=');
      final key = (i < 0 ? attr : attr.substring(0, i)).trim().toLowerCase();
      final value = i < 0 ? '' : attr.substring(i + 1).trim();
      switch (key) {
        case 'domain':
          domain = value;
        case 'path':
          path = value;
        case 'samesite':
          sameSite = value;
        case 'secure':
          secure = true;
        case 'httponly':
          httpOnly = true;
        case 'expires':
          expires ??= _tryHttpDate(value);
        case 'max-age':
          final seconds = int.tryParse(value);
          if (seconds != null) {
            expires = DateTime.now().add(Duration(seconds: seconds));
          }
      }
    }
    final known = parts.length > 1;
    return WebCookie(
      name: parts.first.substring(0, eq).trim(),
      value: parts.first.substring(eq + 1).trim(),
      domain: domain,
      path: path,
      secure: known ? secure : null,
      httpOnly: known ? httpOnly : null,
      sameSite: sameSite,
      expires: expires,
      attributesKnown: known,
    );
  }

  /// Opis do diagnostyki — nigdy nie zawiera wartości.
  String describe() {
    if (!attributesKnown) return '$name (atrybuty niedostępne w tym WebView)';
    final flags = [
      'domena ${domain ?? 'host'}',
      'ścieżka ${path ?? '/'}',
      if (secure == true) 'Secure',
      if (httpOnly == true) 'HttpOnly',
      if (sameSite != null) 'SameSite=$sameSite',
      expires == null
          ? 'sesyjne'
          : 'wygasa ${expires!.toUtc().toIso8601String()}',
    ];
    return '$name: ${flags.join(', ')}';
  }

  @override
  String toString() => 'WebCookie($name)';
}

DateTime? _tryHttpDate(String value) {
  try {
    return HttpDate.parse(value);
  } on HttpException {
    return null;
  } on FormatException {
    return null;
  }
}
