import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../app/build_config.dart';
import '../../../app/providers.dart';
import '../../../core/errors/synergia_exception.dart';
import '../../../core/network/session_cookies.dart';
import '../../../core/network/synergia_api_client.dart';
import '../../../core/network/web_cookie.dart';
import '../../../core/security/session_store.dart';
import '../../diagnostics/data/integration_probe.dart';
import '../../diagnostics/presentation/diagnostics_screen.dart';
import '../data/webview_session.dart';
import '../domain/login_flow.dart';
import '../domain/nav_log.dart';

/// EKSPERYMENTALNE: logowanie na stronie Librusa w osadzonym WebView
/// (docs/decisions.md D1). Aplikacja nie wstrzykuje JavaScriptu i nie czyta
/// pól formularza. Nie przechwytuje też nawigacji (zob. [LoginFlow]) —
/// strony spoza Librusa są zamykane po rozpoczęciu ładowania.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _cookiePollInterval = Duration(seconds: 2);

  final _flow = LoginFlow();
  final _log = NavLog();
  late final WebViewController _controller = _createController();
  Timer? _cookiePoll;
  int _progress = 0;
  bool _verifying = false;
  String? _message;
  bool _messageIsError = false;

  /// Kandydat na sesję z nieudanej próby — tylko w pamięci, do diagnostyki.
  ({List<WebCookie> cookies, String? landing})? _failedAttempt;

  @override
  void initState() {
    super.initState();
    _cookiePoll = Timer.periodic(_cookiePollInterval, (_) => _pollCookies());
  }

  @override
  void dispose() {
    _cookiePoll?.cancel();
    super.dispose();
  }

  WebViewController _createController() {
    final controller = WebViewController()
      // Wymagane przez portal, formularz Librusa i Cloudflare Turnstile.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      // Bez onNavigationRequest: webview_flutter anulowałby każdą nawigację
      // głównej ramki i ponawiał ją przez loadUrl bez Referer — portal
      // odsyła wtedy na /rodzina (pętla).
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (url) {
            final uri = Uri.tryParse(url);
            final action = _flow.onMainFrameStarted(uri);
            _log.add(
              NavEvent(
                'onPageStarted',
                uri,
                mainFrame: true,
                decision: action == PageAction.leaveForbidden
                    ? 'CANCEL'
                    : 'ALLOW',
                detail: uri != null && isOAuthFormOutsideFrame(uri)
                    ? 'formularz OAuth poza ramką portalu'
                    : null,
              ),
            );
            _handle(action, uri);
          },
          onPageFinished: (url) {
            final uri = Uri.tryParse(url);
            final action = _flow.onMainFrameFinished(uri);
            _log.add(
              NavEvent(
                'onPageFinished',
                uri,
                mainFrame: true,
                detail: action.name,
              ),
            );
            _handle(action, uri);
          },
          onUrlChange: (change) {
            final uri = Uri.tryParse(change.url ?? '');
            final action = _flow.onUrlChange(uri);
            _log.add(
              NavEvent(
                'onUrlChange',
                uri,
                mainFrame: true,
                detail: action.name,
              ),
            );
            _handle(action, uri);
          },
          onHttpError: (error) {
            _log.add(
              NavEvent(
                'onHttpError',
                error.request?.uri,
                status: error.response?.statusCode,
              ),
            );
          },
          onWebResourceError: (error) {
            final uri = Uri.tryParse(error.url ?? '');
            _log.add(
              NavEvent(
                'onWebResourceError',
                uri,
                mainFrame: error.isForMainFrame,
                detail: error.errorType?.name ?? 'kod ${error.errorCode}',
              ),
            );
            if (error.isForMainFrame ?? false) {
              _show(
                'Nie udało się wczytać strony (${error.errorType?.name ?? error.errorCode}). '
                'Sprawdź internet i spróbuj od nowa.',
                error: true,
              );
            }
          },
        ),
      );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // chrome://inspect tylko w buildach debug.
      AndroidWebViewController.enableDebugging(
        BuildConfig.current.webViewDebugging,
      );
      platform
        ..setAllowFileAccess(false)
        ..setAllowContentAccess(false)
        ..setGeolocationEnabled(false)
        ..setMediaPlaybackRequiresUserGesture(true);
      // Formularz działa w iframe na subdomenach librus.pl (ten sam „site”
      // co portal); ciasteczka obcych witryn nie są potrzebne.
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, false);
    }
    _log.add(NavEvent('loadRequest', loginStartUri(), mainFrame: true));
    controller.loadRequest(loginStartUri());
    return controller;
  }

  void _handle(PageAction action, Uri? uri) {
    switch (action) {
      case PageAction.none:
        break;
      case PageAction.leaveForbidden:
        _show('Strona spoza Librusa została zamknięta.', error: true);
        _loadStart();
      case PageAction.stopLoop:
        _show(
          'Wykryto pętlę przekierowań (ta sama strona ładuje się wielokrotnie). '
          'Zatrzymano automatyczne działania. Spróbuj „Zacznij od nowa”'
          '${BuildConfig.current.developerTools ? ' lub sprawdź log nawigacji' : ''}.',
          error: true,
        );
      case PageAction.verifySession:
        unawaited(_verify(landing: uri == null ? null : redactUrl(uri)));
    }
  }

  Future<void> _pollCookies() async {
    if (_verifying || !mounted) return;
    final List<WebCookie> cookies;
    try {
      cookies = await readSynergiaCookies();
    } on PlatformException {
      return;
    }
    final token = cookies
        .where((c) => c.name == SessionCookies.authMarker)
        .firstOrNull;
    // Skrót liczony lokalnie; nie trafia do logów.
    final fingerprint = token?.value.hashCode.toRadixString(16);
    if (_flow.shouldVerifyForCookie(fingerprint)) {
      _log.add(
        NavEvent(
          'cookiePoll',
          Uri.https('synergia.librus.pl', '/'),
          detail: '${SessionCookies.authMarker} pojawiło się/zmieniło',
        ),
      );
      await _verify(landing: null, cookies: cookies);
    }
  }

  /// Zapisuje sesję wyłącznie po potwierdzeniu przez `Me`. Nieudana próba
  /// nie przeładowuje strony i nie czyści WebView — logowanie trwa dalej.
  Future<void> _verify({String? landing, List<WebCookie>? cookies}) async {
    if (_verifying) return;
    setState(() => _verifying = true);
    try {
      final webCookies = cookies ?? await readSynergiaCookies();
      _log.add(
        NavEvent(
          'verifySession',
          Uri.https('synergia.librus.pl', '/gateway/api/2.0/Me'),
          detail: 'ciasteczek: ${webCookies.length}',
        ),
      );
      try {
        await ref
            .read(authControllerProvider.notifier)
            .completeLogin(SessionCookies.fromWebCookies(webCookies));
        _log.add(NavEvent('verifySession', null, detail: 'OK'));
        // Router przejdzie do ocen po zmianie stanu.
      } on SynergiaException catch (e) {
        _log.add(
          NavEvent('verifySession', null, detail: e.runtimeType.toString()),
        );
        _failedAttempt = (cookies: webCookies, landing: landing);
        _show(
          e is LoginNotCompletedException
              ? 'Synergia nie potwierdziła jeszcze sesji. Dokończ logowanie na '
                    'stronie albo użyj „Sprawdź logowanie”.'
              : BuildConfig.current.diagnostics
              ? '${e.message} Możesz uruchomić diagnostykę.'
              : '${e.message} Spróbuj „Zacznij od nowa”.',
          error: e is! LoginNotCompletedException,
        );
      }
    } on PlatformException {
      _show('Nie udało się odczytać ciasteczek WebView.', error: true);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  void _show(String message, {required bool error}) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = error;
    });
  }

  void _loadStart() {
    _log.add(NavEvent('loadRequest', loginStartUri(), mainFrame: true));
    _controller.loadRequest(loginStartUri());
  }

  void _restart() {
    _flow.reset();
    setState(() {
      _message = null;
      _failedAttempt = null;
    });
    _loadStart();
  }

  void _manualVerify() {
    _flow.allowVerifyAgain();
    unawaited(_verify());
  }

  void _openDiagnostics() {
    final attempt = _failedAttempt;
    if (attempt == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiagnosticsScreen(
          run: () => IntegrationProbe(
            SynergiaApiClient(
              sessionStore: InMemorySessionStore(
                SessionCookies.fromWebCookies(attempt.cookies),
              ),
            ),
          ).run(webCookies: attempt.cookies, landingUrl: attempt.landing),
        ),
      ),
    );
  }

  void _showNavLog() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        builder: (context, scroll) => Column(
          children: [
            ListTile(
              title: const Text('Log nawigacji (debug)'),
              subtitle: const Text(
                'Tylko host i ścieżka — bez zapytań, ciasteczek i treści.',
              ),
              trailing: IconButton(
                tooltip: 'Kopiuj log',
                icon: const Icon(Icons.copy),
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: _log.toText())),
              ),
            ),
            Expanded(
              child: ListView(
                controller: scroll,
                children: [
                  for (final e in _log.events.reversed)
                    ListTile(dense: true, title: Text(e.toString())),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final expired = switch (ref.watch(authControllerProvider).value) {
      SignedOut(:final sessionExpired) => sessionExpired,
      _ => false,
    };
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logowanie do Synergii'),
        actions: [
          IconButton(
            tooltip: 'Sprawdź logowanie',
            icon: const Icon(Icons.verified_user_outlined),
            onPressed: _verifying ? null : _manualVerify,
          ),
          IconButton(
            tooltip: 'Zacznij od nowa',
            icon: const Icon(Icons.refresh),
            onPressed: _verifying ? null : _restart,
          ),
          if (BuildConfig.current.developerTools)
            IconButton(
              tooltip: 'Log nawigacji',
              icon: const Icon(Icons.bug_report_outlined),
              onPressed: _showNavLog,
            ),
        ],
        bottom: _progress < 100
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(value: _progress / 100),
              )
            : null,
      ),
      body: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.lock_outline),
            dense: true,
            title: Text(
              expired
                  ? 'Sesja wygasła. Zaloguj się ponownie.'
                  : 'Na stronie portalu wybierz „Zaloguj” → LIBRUS Synergia. '
                        'Logujesz się na stronie Librusa; aplikacja nie odczytuje '
                        'ani nie zapisuje hasła. Tryb eksperymentalny.',
            ),
          ),
          if (_message != null)
            MaterialBanner(
              backgroundColor: _messageIsError
                  ? scheme.errorContainer
                  : scheme.secondaryContainer,
              content: Text(_message!),
              actions: [
                if (_failedAttempt != null && BuildConfig.current.diagnostics)
                  TextButton(
                    onPressed: _openDiagnostics,
                    child: const Text('Diagnostyka'),
                  ),
                TextButton(
                  onPressed: () => setState(() => _message = null),
                  child: const Text('Ukryj'),
                ),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_verifying)
                  const ColoredBox(
                    color: Colors.black26,
                    child: Center(child: CircularProgressIndicator()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
