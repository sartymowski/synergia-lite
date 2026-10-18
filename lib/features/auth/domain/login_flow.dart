/// Logika nawigacji ekranu logowania, niezależna od WebView (testowalna).
///
/// Oficjalny przepływ (stan 2026-10-18, zob. docs/integration-status.md):
/// 1. `portal.librus.pl/rodzina` → użytkownik wybiera „Zaloguj” → LIBRUS Synergia;
/// 2. `portal.librus.pl/rodzina/synergia/loguj` — serwer wymaga przejścia
///    z portalu (Referer), inaczej odsyła na `/rodzina`;
/// 3. strona osadza iframe `synergia.librus.pl/loguj/portalRodzina` →
///    formularz `api.librus.pl/OAuth/Authorization?client_id=46`;
/// 4. formularz poza ramką portalu sam przekierowuje na `/rodzina`.
///
/// Dlatego WebView NIE przechwytuje nawigacji (webview_flutter anulowałby ją
/// i ponawiał przez `loadUrl`, gubiąc Referer) — ograniczenie domen jest
/// egzekwowane po rozpoczęciu ładowania strony.
library;

bool isLibrusHost(String host) =>
    host == 'librus.pl' || host.endsWith('.librus.pl');

/// Główna ramka może odwiedzać tylko strony Librusa po HTTPS.
/// Ramki podrzędne (iframe logowania, Cloudflare Turnstile) zostawiamy stronie.
bool isAllowedMainFrame(Uri url) =>
    url.toString() == 'about:blank' ||
    (url.scheme == 'https' && isLibrusHost(url.host));

/// Synergia poza ścieżkami logowania (np. `/rodzic/index`). To tylko sygnał
/// do sprawdzenia sesji — o sukcesie decyduje odpowiedź `Me`.
bool isPostLoginUrl(Uri? url) =>
    url != null &&
    url.scheme == 'https' &&
    url.host == 'synergia.librus.pl' &&
    !url.path.startsWith('/loguj') &&
    !url.path.startsWith('/wyloguj') &&
    !url.path.startsWith('/gateway');

/// Formularz OAuth wczytany jako strona główna — skrypt Librusa zaraz
/// przekieruje na portal (`redirectToPortalIfNotInIframe`).
bool isOAuthFormOutsideFrame(Uri url) =>
    url.host == 'api.librus.pl' && url.path.startsWith('/OAuth/Authorization');

/// Adres bez zapytania i fragmentu — w nich bywają `code` i `state` OAuth.
String redactUrl(Uri url) => '${url.scheme}://${url.host}${url.path}';

/// Host + ścieżka bez zapytania, z zamaskowanymi identyfikatorami i długimi
/// segmentami. Bezpieczne do logów diagnostycznych.
String safeLocation(Uri? url) {
  if (url == null) return '(brak adresu)';
  if (url.scheme != 'https' && url.scheme != 'http') return '${url.scheme}:…';
  final segments = [
    for (final s in url.pathSegments)
      if (s.isNotEmpty)
        RegExp(r'\d{3,}').hasMatch(s) || s.length > 32 ? ':id' : s,
  ];
  return '${url.host}/${segments.join('/')}';
}

/// Co ekran ma zrobić po zdarzeniu nawigacji głównej ramki.
enum PageAction {
  none,

  /// Strona spoza Librusa — wróć na start i poinformuj użytkownika.
  leaveForbidden,

  /// Wykryto pętlę przekierowań — przestań reagować i pokaż komunikat.
  stopLoop,

  /// Możliwe zakończenie logowania — sprawdź sesję zapytaniem `Me`.
  verifySession,
}

class LoginFlow {
  LoginFlow({
    DateTime Function()? clock,
    this.loopWindow = const Duration(seconds: 30),
    this.loopThreshold = 4,
  }) : _clock = clock ?? DateTime.now;

  static final startUri = Uri.https('portal.librus.pl', '/rodzina');

  final DateTime Function() _clock;
  final Duration loopWindow;
  final int loopThreshold;

  final _recentLoads = <(DateTime, String)>[];
  bool _loopDetected = false;
  String? _lastTrigger;

  bool get loopDetected => _loopDetected;

  /// Nowa próba (przycisk „Zacznij od nowa”).
  void reset() {
    _recentLoads.clear();
    _loopDetected = false;
    _lastTrigger = null;
  }

  PageAction onMainFrameStarted(Uri? url) {
    if (url == null) return PageAction.none;
    if (!isAllowedMainFrame(url)) return PageAction.leaveForbidden;
    return PageAction.none;
  }

  PageAction onMainFrameFinished(Uri? url) {
    if (url == null || _loopDetected) return PageAction.none;
    if (!isAllowedMainFrame(url)) return PageAction.leaveForbidden;
    final now = _clock();
    final location = safeLocation(url);
    _recentLoads
      ..removeWhere((e) => now.difference(e.$1) > loopWindow)
      ..add((now, location));
    if (_recentLoads.where((e) => e.$2 == location).length >= loopThreshold) {
      _loopDetected = true;
      return PageAction.stopLoop;
    }
    return isPostLoginUrl(url) && _markTrigger('page:$location')
        ? PageAction.verifySession
        : PageAction.none;
  }

  /// Zmiana adresu bez przeładowania (history API).
  PageAction onUrlChange(Uri? url) {
    if (url == null || _loopDetected) return PageAction.none;
    if (!isAllowedMainFrame(url)) return PageAction.leaveForbidden;
    return isPostLoginUrl(url) && _markTrigger('page:${safeLocation(url)}')
        ? PageAction.verifySession
        : PageAction.none;
  }

  /// Logowanie w iframe portalu nie zawsze zmienia stronę główną. Sygnałem jest
  /// pojawienie się lub zmiana ciasteczka sesji Synergii — [fingerprint] to
  /// skrót wartości liczony lokalnie (nigdy logowany), `null` gdy go brak.
  bool shouldVerifyForCookie(String? fingerprint) =>
      !_loopDetected &&
      fingerprint != null &&
      _markTrigger('cookie:$fingerprint');

  /// Ręczne sprawdzenie (przycisk) zawsze dozwolone.
  void allowVerifyAgain() => _lastTrigger = null;

  bool _markTrigger(String trigger) {
    if (_lastTrigger == trigger) return false;
    _lastTrigger = trigger;
    return true;
  }
}
