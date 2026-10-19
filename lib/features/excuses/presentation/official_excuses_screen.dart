import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../../app/build_config.dart';
import '../../auth/domain/login_flow.dart' show isAllowedMainFrame;

/// Rozwiązanie awaryjne: oficjalny moduł e-Usprawiedliwień Librusa w WebView.
///
/// Kontrakt zapisu nie jest znany (moduł działa w Koncie LIBRUS), więc
/// formularz, CSRF, walidację i potwierdzenie obsługuje strona Librusa.
/// Aplikacja nie wstrzykuje skryptów, nie czyta pól formularza i nie
/// przechwytuje nawigacji (zob. docs/decisions.md D11) — strony spoza
/// `https://*.librus.pl` są zamykane po rozpoczęciu ładowania.
class OfficialExcusesScreen extends StatefulWidget {
  const OfficialExcusesScreen({super.key});

  /// Oficjalne wejście do modułu (sesja Synergii z WebView logowania).
  static final startUri = Uri.https(
    'synergia.librus.pl',
    '/eusprawiedliwienia',
  );

  @override
  State<OfficialExcusesScreen> createState() => _OfficialExcusesScreenState();
}

class _OfficialExcusesScreenState extends State<OfficialExcusesScreen> {
  late final WebViewController _controller = _create();
  int _progress = 0;
  bool _blocked = false;

  WebViewController _create() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => _progress = p);
          },
          onPageStarted: (url) {
            final uri = Uri.tryParse(url);
            if (uri != null && !isAllowedMainFrame(uri)) {
              setState(() => _blocked = true);
              _controller.loadRequest(OfficialExcusesScreen.startUri);
            }
          },
        ),
      );
    final platform = controller.platform;
    if (platform is AndroidWebViewController) {
      // chrome://inspect tylko w buildach debug (analiza struktury formularza).
      AndroidWebViewController.enableDebugging(
        BuildConfig.current.webViewDebugging,
      );
      platform
        ..setAllowFileAccess(false)
        ..setAllowContentAccess(false)
        ..setGeolocationEnabled(false);
    }
    controller.loadRequest(OfficialExcusesScreen.startUri);
    return controller;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('e-Usprawiedliwienia (Librus)'),
      actions: [
        IconButton(
          tooltip: 'Wróć i sprawdź historię',
          icon: const Icon(Icons.check),
          onPressed: () => Navigator.of(context).pop(),
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
          dense: true,
          leading: const Icon(Icons.public),
          title: Text(
            _blocked
                ? 'Strona spoza Librusa została zamknięta.'
                : 'Oficjalny moduł Librusa. Usprawiedliwienie wysyłasz na stronie Librusa '
                      '(może być wymagane Konto LIBRUS). Po powrocie aplikacja sprawdzi historię.',
          ),
        ),
        Expanded(child: WebViewWidget(controller: _controller)),
      ],
    ),
  );
}
