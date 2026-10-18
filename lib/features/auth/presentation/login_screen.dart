import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../app/providers.dart';
import '../../../core/errors/synergia_exception.dart';
import '../../../core/network/session_cookies.dart';
import '../../../core/network/synergia_api_client.dart';
import '../../../core/network/web_cookie.dart';
import '../../../core/security/session_store.dart';
import '../../diagnostics/data/integration_probe.dart';
import '../../diagnostics/presentation/diagnostics_screen.dart';
import '../data/webview_session.dart';

/// EKSPERYMENTALNE: logowanie na stronie Librusa w osadzonym WebView
/// (zob. docs/decisions.md D1). Aplikacja nie wstrzykuje JavaScriptu,
/// nie dodaje kanałów JS i nie czyta pól formularza — po zakończeniu
/// przepływu odczytuje tylko ciasteczka Synergii.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  late final WebViewController _controller = _createController();
  int _progress = 0;
  bool _completing = false;
  String? _error;

  /// Kandydat na sesję z nieudanej próby — tylko w pamięci, do diagnostyki.
  ({List<WebCookie> cookies, String landing})? _failedAttempt;

  WebViewController _createController() {
    final controller = WebViewController()
      // Wymagane przez formularz Librusa i Cloudflare Turnstile.
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) => setState(() => _progress = p),
          onNavigationRequest: (request) {
            final uri = Uri.tryParse(request.url);
            if (!request.isMainFrame) return NavigationDecision.navigate;
            return uri != null && isAllowedMainFrame(uri)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
          onPageFinished: (url) => _onPageLoaded(Uri.tryParse(url)),
          onWebResourceError: (error) {
            if (error.isForMainFrame ?? false) {
              _fail(
                'Nie udało się wczytać strony logowania (${error.errorType?.name ?? error.errorCode}).',
              );
            }
          },
        ),
      );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      platform
        ..setAllowFileAccess(false)
        ..setAllowContentAccess(false)
        ..setGeolocationEnabled(false)
        ..setMediaPlaybackRequiresUserGesture(true);
      // Cały przepływ odbywa się w głównej ramce na domenach librus.pl.
      AndroidWebViewCookieManager(
        const PlatformWebViewCookieManagerCreationParams(),
      ).setAcceptThirdPartyCookies(platform, false);
    }
    controller.loadRequest(loginStartUri());
    return controller;
  }

  Future<void> _onPageLoaded(Uri? url) async {
    if (_completing || !isPostLoginUrl(url)) return;
    setState(() {
      _completing = true;
      _error = null;
      _failedAttempt = null;
    });
    final List<WebCookie> webCookies;
    try {
      webCookies = await readSynergiaCookies();
    } on PlatformException {
      _fail('Nie udało się odczytać ciasteczek WebView.');
      return;
    }
    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeLogin(SessionCookies.fromWebCookies(webCookies));
      // Router przekieruje dalej po zmianie stanu.
    } on SynergiaException catch (e) {
      _failedAttempt = (cookies: webCookies, landing: redactUrl(url!));
      _fail(
        e is LoginNotCompletedException
            ? '${e.message} Uruchom diagnostykę, aby sprawdzić przyczynę.'
            : e.message,
      );
    }
  }

  void _fail(String message) {
    if (!mounted) return;
    setState(() {
      _completing = false;
      _error = message;
    });
  }

  void _restart() {
    setState(() {
      _error = null;
      _failedAttempt = null;
    });
    _controller.loadRequest(loginStartUri());
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

  @override
  Widget build(BuildContext context) {
    final expired = switch (ref.watch(authControllerProvider).value) {
      SignedOut(:final sessionExpired) => sessionExpired,
      _ => false,
    };
    return Scaffold(
      appBar: AppBar(
        title: const Text('Logowanie do Synergii'),
        actions: [
          IconButton(
            tooltip: 'Zacznij od nowa',
            icon: const Icon(Icons.refresh),
            onPressed: _completing ? null : _restart,
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
                  ? 'Sesja wygasła. Zaloguj się ponownie na stronie Librusa.'
                  : 'Logujesz się na stronie Librusa. Synergia Lite nie '
                        'odczytuje ani nie zapisuje hasła. Tryb eksperymentalny.',
            ),
          ),
          if (_error != null)
            MaterialBanner(
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              content: Text(_error!),
              actions: [
                if (_failedAttempt != null)
                  TextButton(
                    onPressed: _openDiagnostics,
                    child: const Text('Diagnostyka'),
                  ),
                TextButton(onPressed: _restart, child: const Text('Ponów')),
              ],
            ),
          Expanded(
            child: Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_completing)
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
