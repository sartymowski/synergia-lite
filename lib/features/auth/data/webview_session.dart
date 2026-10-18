import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../core/network/web_cookie.dart';
import '../domain/login_flow.dart';
import 'auth_repository.dart';

export '../domain/login_flow.dart'
    show isAllowedMainFrame, isLibrusHost, isPostLoginUrl, redactUrl;

/// Strona główna portalu Librus Rodzina. Formularz Synergii działa tylko
/// w iframe strony `/rodzina/synergia/loguj`, na którą portal wpuszcza po
/// przejściu z portalu — zob. [LoginFlow].
Uri loginStartUri() => LoginFlow.startUri;

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
