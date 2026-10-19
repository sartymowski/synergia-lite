import 'dart:convert';

import 'package:dio/dio.dart';

import '../../../core/errors/synergia_exception.dart';
import '../../../core/network/request_queue.dart';
import '../../../core/network/session_cookies.dart';
import '../../../core/network/web_cookie.dart';
import '../../../core/security/session_store.dart';
import '../../auth/domain/login_flow.dart' show isLibrusHost;

/// Odpowiedź na POST — klasyfikacja wyniku wysyłki należy do repozytorium.
class RawResponse {
  const RawResponse(this.statusCode, this.body);

  final int statusCode;
  final String body;

  Object? tryJson() {
    if (body.trim().isEmpty) return null;
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}

/// Błąd transportu przy wysyłaniu. [requestMayHaveReachedServer] = false tylko
/// wtedy, gdy połączenia na pewno nie nawiązano.
final class SendTransportException implements Exception {
  const SendTransportException({
    required this.requestMayHaveReachedServer,
    required this.kind,
  });

  final bool requestMayHaveReachedServer;
  final String kind;

  @override
  String toString() => 'SendTransportException($kind)';
}

/// Klient `https://wiadomosci.librus.pl/api/` — osobnego serwisu z własną sesją.
///
/// Inicjalizacja jak w aplikacji internetowej: `GET synergia.librus.pl/wiadomosci3`
/// z ciasteczkami Synergii; Synergia przekierowaniami (MultiDomainLogon)
/// ustawia ciasteczka domeny wiadomości. Ciasteczka wiadomości są trzymane
/// wyłącznie w pamięci. Sesja wiadomości wygasa niezależnie i często —
/// GET po 401/403 odnawia ją raz; POST nigdy nie jest ponawiany.
class MessagesApiClient {
  MessagesApiClient({
    required SessionStore synergiaSession,
    Dio? dio,
    Duration minInterval = const Duration(milliseconds: 300),
    this._onSynergiaCookiesChanged,
  }) : _store = synergiaSession,
       _dio = dio ?? Dio(),
       _queue = RequestQueue(minInterval: minInterval) {
    _dio.options
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      ..sendTimeout = const Duration(seconds: 20)
      ..followRedirects = false
      ..validateStatus = ((_) => true)
      ..responseType = ResponseType.plain
      // Bez słowa „Android”: serwis wiadomości odsyła przeglądarki mobilne
      // na stronę `/blad-urzadzenie-mobilne`.
      ..headers['User-Agent'] = userAgent;
  }

  static const apiBase = 'https://wiadomosci.librus.pl/api/';
  static const host = 'wiadomosci.librus.pl';
  static final bootstrapUri = Uri.https(SessionCookies.host, '/wiadomosci3');
  static const userAgent = 'SynergiaLite/0.1 (nieoficjalny klient)';
  static const accessDeniedMarker = 'Brak dostępu';
  static const _maxHops = 10;

  final SessionStore _store;
  final Dio _dio;
  final RequestQueue _queue;
  final void Function()? _onSynergiaCookiesChanged;
  final _cookies = <String, String>{};
  Future<void>? _bootstrapping;

  bool get hasSession => _cookies.isNotEmpty;

  /// Nazwy ciasteczek serwisu wiadomości (do diagnostyki; bez wartości).
  List<String> get cookieNames => _cookies.keys.toList()..sort();

  /// Zapomina sesję wiadomości (np. przy wylogowaniu).
  void reset() => _cookies.clear();

  Future<void> ensureSession() async {
    if (_cookies.isEmpty) await bootstrap();
  }

  /// Współbieżne wywołania dzielą jedną inicjalizację.
  Future<void> bootstrap() =>
      _bootstrapping ??= _bootstrap().whenComplete(() => _bootstrapping = null);

  Future<void> _bootstrap() async {
    _cookies.clear();
    var url = bootstrapUri;
    for (var hop = 0; hop < _maxHops; hop++) {
      final response = await _send('GET', url);
      final status = response.statusCode ?? 0;
      if (status >= 300 && status < 400) {
        final location = response.headers.value('location');
        if (location == null) {
          throw const UnexpectedResponseException(
            'wiadomosci3: przekierowanie bez adresu',
          );
        }
        var next = url.resolve(location);
        // Librus w kroku MultiDomainLogon potrafi wskazać `http://` (zgłoszone
        // 2026-10-19 przy ponownej inicjalizacji). Dla własnych hostów Librusa
        // podnosimy do HTTPS (jak przeglądarka z HSTS) — nic nie idzie jawnym
        // tekstem; inne schematy i obce domeny są nadal odrzucane.
        if (next.scheme == 'http' &&
            isLibrusHost(next.host) &&
            (!next.hasPort || next.port == 80)) {
          next = next.replace(scheme: 'https', port: 443);
        }
        if (next.scheme != 'https' || !isLibrusHost(next.host)) {
          // Tylko schemat i host celu — bez ścieżki i parametrów (tokeny).
          throw UnexpectedResponseException(
            'wiadomosci3: odrzucone przekierowanie (krok ${hop + 1}) na '
            '${next.scheme.isEmpty ? "(brak schematu)" : next.scheme}://'
            '${next.host.isEmpty ? "(brak hosta)" : next.host}'
            '${next.scheme != "https" ? " — nie HTTPS" : " — host spoza librus.pl"}',
          );
        }
        if (_isLoginPage(next)) throw const SessionExpiredException();
        url = next;
        continue;
      }
      if (status == 401 || status == 403) throw const SessionExpiredException();
      if (status == 429 || status == 503) {
        throw RateLimitedException(retryAfter: _retryAfter(response));
      }
      if (status != 200) throw ServerException(status);
      final body = '${response.data ?? ''}';
      if (body.contains(accessDeniedMarker)) {
        throw const MessagesUnavailableException();
      }
      if (_cookies.isEmpty) {
        throw const UnexpectedResponseException(
          'wiadomosci3: serwis nie ustawił ciasteczek sesji wiadomości',
        );
      }
      return;
    }
    throw const UnexpectedResponseException(
      'wiadomosci3: zbyt wiele przekierowań',
    );
  }

  /// GET z jednorazowym odnowieniem sesji po 401/403/3xx.
  /// Zwraca zdekodowany JSON (obiekt albo lista — oba warianty występują).
  Future<Object?> get(String path, {Map<String, String>? query}) async {
    _checkRelative(path);
    await ensureSession();
    final url = Uri.parse('$apiBase$path').replace(queryParameters: query);
    var response = await _send('GET', url);
    if (_sessionRejected(response.statusCode)) {
      await bootstrap();
      response = await _send('GET', url);
      final status = response.statusCode ?? 0;
      if (status == 403) throw const PermissionDeniedException();
      if (_sessionRejected(status)) {
        throw const MessagesSessionExpiredException();
      }
    }
    return _decodeGet(response, path);
  }

  /// Jedno żądanie POST, bez ponowień i bez odnawiania sesji (wywołujący
  /// sprawdza sesję wcześniej odczytem).
  Future<RawResponse> postOnce(String path, Map<String, Object?> body) async {
    _checkRelative(path);
    final url = Uri.parse('$apiBase$path');
    final Response<dynamic> response;
    try {
      response = await _queue.run(
        () => _dio.postUri<dynamic>(
          url,
          data: jsonEncode(body),
          options: Options(
            headers: {
              'Cookie': _cookieHeader(),
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
          ),
        ),
      );
    } on DioException catch (e) {
      throw SendTransportException(
        // Tylko nieudane nawiązanie połączenia gwarantuje, że nic nie wyszło.
        requestMayHaveReachedServer:
            e.type != DioExceptionType.connectionTimeout,
        kind: e.type.name,
      );
    }
    _absorbCookies(url, response.headers['set-cookie']);
    return RawResponse(response.statusCode ?? 0, '${response.data ?? ''}');
  }

  Future<Response<dynamic>> _send(String method, Uri url) async {
    final cookie = await _cookieHeaderFor(url);
    final Response<dynamic> response;
    try {
      response = await _queue.run(
        () => _dio.requestUri<dynamic>(
          url,
          options: Options(
            method: method,
            headers: {
              if (cookie.isNotEmpty) 'Cookie': cookie,
              'Accept': url.host == host ? 'application/json' : '*/*',
            },
          ),
        ),
      );
    } on DioException catch (e) {
      throw switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.sendTimeout ||
        DioExceptionType.receiveTimeout => const RequestTimeoutException(),
        _ => const NetworkException(),
      };
    }
    await _absorbCookiesAsync(url, response.headers['set-cookie']);
    return response;
  }

  Object? _decodeGet(Response<dynamic> response, String path) {
    final status = response.statusCode ?? 0;
    final endpoint = path.split('?').first;
    if (status == 429 || status == 503) {
      throw RateLimitedException(retryAfter: _retryAfter(response));
    }
    if (status < 200 || status >= 300) throw ServerException(status);
    final raw = '${response.data ?? ''}';
    try {
      return jsonDecode(raw);
    } on FormatException {
      throw UnexpectedResponseException(
        'wiadomości $endpoint: odpowiedź nie jest JSON',
      );
    }
  }

  static Duration? _retryAfter(Response<dynamic> response) {
    final seconds = int.tryParse(response.headers.value('retry-after') ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static bool _sessionRejected(int? status) =>
      status == 401 ||
      status == 403 ||
      (status != null && status >= 300 && status < 400);

  static bool _isLoginPage(Uri url) =>
      url.host == 'portal.librus.pl' ||
      url.host == 'api.librus.pl' ||
      (url.host == SessionCookies.host && url.path.startsWith('/loguj'));

  Future<String> _cookieHeaderFor(Uri url) async {
    if (url.host == SessionCookies.host) {
      final session = await _store.read();
      if (session == null || session.isEmpty) {
        throw const SessionExpiredException();
      }
      return session.toHeader();
    }
    return url.host == host ? _cookieHeader() : '';
  }

  String _cookieHeader() =>
      _cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');

  Future<void> _absorbCookiesAsync(Uri url, List<String>? headers) async {
    if (headers == null || headers.isEmpty) return;
    if (url.host == SessionCookies.host) {
      // Rotacja ciasteczek Synergii podczas inicjalizacji — zapisz i daj znać
      // głównemu klientowi, żeby nie używał nieaktualnych wartości.
      final session = await _store.read();
      if (session != null) {
        final updated = session.merge(headers);
        if (!identical(updated, session)) {
          await _store.write(updated);
          _onSynergiaCookiesChanged?.call();
        }
      }
    }
    _absorbCookies(url, headers);
  }

  /// Ciasteczka dla domeny wiadomości: ustawione przez nią samą albo przez
  /// inny host librus.pl z atrybutem `Domain` obejmującym wiadomości.
  void _absorbCookies(Uri url, List<String>? headers) {
    if (headers == null) return;
    for (final header in headers) {
      final c = WebCookie.parse(header);
      if (c == null) continue;
      final domain = c.domain?.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
      final applies = domain == null || domain.isEmpty
          ? url.host == host
          : (host == domain || host.endsWith('.$domain')) &&
                isLibrusHost(url.host);
      if (!applies) continue;
      final expired = c.expires != null && !c.expires!.isAfter(DateTime.now());
      if (c.value.isEmpty || c.value == 'deleted' || expired) {
        _cookies.remove(c.name);
      } else {
        _cookies[c.name] = c.value;
      }
    }
  }

  static void _checkRelative(String path) {
    if (path.contains('://') || path.startsWith('/') || path.contains('..')) {
      throw ArgumentError.value(path, 'path', 'oczekiwano ścieżki względnej');
    }
  }
}
