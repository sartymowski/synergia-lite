import '../../../core/errors/synergia_exception.dart';
import '../../../core/network/session_cookies.dart';
import '../../../core/network/synergia_api_client.dart';
import '../../../core/security/session_store.dart';
import '../domain/account_info.dart';

/// Czyści stan przeglądarki użytej do logowania (ciasteczka, cache).
/// Osobny interfejs, bo implementacja zależy od wtyczki WebView.
abstract interface class WebSessionCleaner {
  Future<void> clear();
}

class AuthRepository {
  AuthRepository({
    required this._store,
    required this._api,
    required this._webCleaner,
  });

  final SessionStore _store;
  final SynergiaApiClient _api;
  final WebSessionCleaner _webCleaner;

  Future<bool> hasSession() async {
    final s = await _store.read();
    return s != null && !s.isEmpty;
  }

  /// Zapisuje ciasteczka z WebView i od razu sprawdza je na `Me`.
  /// Nieudana weryfikacja nie zostawia po sobie zapisanej sesji, ale NIE
  /// czyści WebView — logowanie może być wciąż w toku (np. `oauth_state`).
  Future<AccountInfo> completeLogin(SessionCookies cookies) async {
    await _store.write(cookies);
    _api.resetSession();
    try {
      final me = await _api.get('Me');
      return AccountInfo.tryParse(me) ??
          (throw const UnexpectedResponseException('Me: brak obiektu konta'));
    } on SessionExpiredException {
      await _discardStoredSession();
      throw LoginNotCompletedException(cookies.names.toList()..sort());
    } on SynergiaException {
      await _discardStoredSession();
      rethrow;
    }
  }

  Future<void> logout() async {
    await _api.endRemoteSession();
    await _discardLocal();
  }

  /// Sesja odrzucona przez serwer — usuwamy ją, ale nie wołamy `wyloguj`.
  Future<void> onSessionExpired() => _discardLocal();

  Future<void> _discardStoredSession() async {
    _api.resetSession();
    await _store.clear();
  }

  Future<void> _discardLocal() async {
    try {
      await _discardStoredSession();
    } finally {
      // Ciasteczka WebView czyścimy także wtedy, gdy zawiódł magazyn sesji.
      await _webCleaner.clear();
    }
  }
}
