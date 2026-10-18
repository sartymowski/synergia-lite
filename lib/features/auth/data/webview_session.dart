import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/network/web_cookie.dart';
import 'auth_repository.dart';

/// Wejście do przepływu OAuth portalu Librus Rodzina — ten sam adres, od którego
/// zaczyna przeglądarka. Prowadzi wprost (główna ramka, bez iframe) do formularza
/// `api.librus.pl/OAuth/Authorization`; 2FA i Cloudflare Turnstile obsługuje
/// strona Librusa.
Uri loginStartUri([DateTime? now]) => Uri.https(
  'synergia.librus.pl',
  '/loguj/portalRodzina',
  {'v': '${(now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000}'},
);

bool isLibrusHost(String host) =>
    host == 'librus.pl' || host.endsWith('.librus.pl');

/// Główna ramka może odwiedzać tylko strony Librusa po HTTPS.
/// Ramki podrzędne (np. Cloudflare Turnstile) zostawiamy stronie.
bool isAllowedMainFrame(Uri url) =>
    url.toString() == 'about:blank' ||
    (url.scheme == 'https' && isLibrusHost(url.host));

/// Logowanie uznajemy za zakończone, gdy główna ramka trafi do Synergii
/// poza ścieżkami logowania (np. `/rodzic/index`, `/uczen/index`).
/// To tylko sygnał do sprawdzenia sesji — o sukcesie decyduje `Me`.
bool isPostLoginUrl(Uri? url) =>
    url != null &&
    url.scheme == 'https' &&
    url.host == 'synergia.librus.pl' &&
    !url.path.startsWith('/loguj') &&
    !url.path.startsWith('/wyloguj');

/// Adres bez zapytania i fragmentu — w nich bywają `code` i `state` OAuth.
String redactUrl(Uri url) => '${url.scheme}://${url.host}${url.path}';

const _cookieChannel = MethodChannel('pl.synergialite/cookies');

/// Ciasteczka `https://synergia.librus.pl/` z magazynu WebView (kanał w MainActivity).
Future<List<WebCookie>> readSynergiaCookies() async {
  final raw =
      await _cookieChannel.invokeListMethod<String>('getSynergiaCookies') ??
      const [];
  return raw.map(WebCookie.parse).nonNulls.toList();
}

class WebViewSessionCleaner implements WebSessionCleaner {
  @override
  Future<void> clear() async {
    await WebViewCookieManager().clearCookies();
    await _cookieChannel.invokeMethod<void>('flush');
    final controller = WebViewController();
    await controller.clearCache();
    await controller.clearLocalStorage();
  }
}
