import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../network/session_cookies.dart';

/// Trwałe przechowywanie sesji. Hasło nigdy tu nie trafia — aplikacja
/// go nie zna, bo logowanie odbywa się na stronie Librusa w WebView.
abstract interface class SessionStore {
  Future<SessionCookies?> read();
  Future<void> write(SessionCookies session);
  Future<void> clear();
}

/// Android: klucz w Android Keystore, dane zaszyfrowane (flutter_secure_storage).
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'synergia_session_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<SessionCookies?> read() async =>
      SessionCookies.tryFromJson(await _storage.read(key: _key));

  @override
  Future<void> write(SessionCookies session) =>
      _storage.write(key: _key, value: session.toJson());

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

class InMemorySessionStore implements SessionStore {
  InMemorySessionStore([this.session]);

  SessionCookies? session;

  @override
  Future<SessionCookies?> read() async => session;

  @override
  Future<void> write(SessionCookies session) async => this.session = session;

  @override
  Future<void> clear() async => session = null;
}
