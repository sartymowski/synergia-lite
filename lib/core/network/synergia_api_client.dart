import 'dart:async';

import 'package:dio/dio.dart';

import '../errors/synergia_exception.dart';
import '../security/session_store.dart';
import 'session_cookies.dart';

/// Klient JSON-owego API, z którego korzysta frontend Synergii
/// (`synergia.librus.pl/gateway/api/2.0`). Autoryzacja wyłącznie
/// ciasteczkami sesji zdobytymi w WebView.
///
/// Zasady: brak automatycznych ponowień, przekierowania nie są śledzone
/// (przekierowanie = utrata sesji), żądania są wykonywane po kolei
/// z minimalnym odstępem, żeby nie obciążać serwera.
class SynergiaApiClient {
  SynergiaApiClient({
    required SessionStore sessionStore,
    Dio? dio,
    this.minInterval = const Duration(milliseconds: 300),
  }) : _store = sessionStore,
       _dio = dio ?? Dio() {
    _dio.options
      ..baseUrl = baseUrl
      ..connectTimeout = const Duration(seconds: 10)
      ..receiveTimeout = const Duration(seconds: 20)
      ..followRedirects = false
      ..validateStatus = ((_) => true)
      ..responseType = ResponseType.json
      ..headers.addAll({'Accept': 'application/json', 'User-Agent': userAgent});
  }

  static const baseUrl = 'https://synergia.librus.pl/gateway/api/2.0/';
  static const logoutUrl = 'https://synergia.librus.pl/wyloguj';
  static const userAgent = 'SynergiaLite/0.1 (Android; nieoficjalny klient)';

  final SessionStore _store;
  final Dio _dio;
  final Duration minInterval;

  SessionCookies? _session;
  Future<void> _queue = Future.value();
  DateTime? _lastRequestAt;

  /// GET [path], opcjonalnie z selektorem identyfikatorów (`Users/1,2,3`).
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? query,
    Iterable<Object>? ids,
  }) {
    _checkRelative(path);
    final idList = ids?.map((e) => '$e').toSet().toList();
    final fullPath = (idList == null || idList.isEmpty)
        ? path
        : '$path/${idList.join(',')}';
    return _serialized(() => _send(fullPath, query));
  }

  /// Kontrola negatywna dla diagnostyki: to samo żądanie bez ciasteczek.
  /// Zwraca kod HTTP albo `null`, gdy nie udało się połączyć.
  Future<int?> statusWithoutSession(String path) {
    _checkRelative(path);
    return _serialized(() async {
      try {
        final r = await _dio.get<dynamic>(path);
        return r.statusCode;
      } on DioException {
        return null;
      }
    });
  }

  /// Ciasteczka sesji mogą trafić wyłącznie do gateway Synergii.
  static void _checkRelative(String path) {
    if (path.contains('://') || path.startsWith('/') || path.contains('..')) {
      throw ArgumentError.value(path, 'path', 'oczekiwano ścieżki względnej');
    }
  }

  /// Zapomina sesję zbuforowaną w pamięci (np. po wylogowaniu).
  void resetSession() => _session = null;

  /// Najlepsza próba zakończenia sesji po stronie Synergii. Błędy są
  /// pomijane — dane lokalne i tak zostaną usunięte.
  Future<void> endRemoteSession() async {
    final session = _session ?? await _store.read();
    if (session == null || session.isEmpty) return;
    try {
      await _dio.get<void>(
        logoutUrl,
        options: Options(
          headers: {'Cookie': session.toHeader()},
          responseType: ResponseType.plain,
        ),
      );
    } on DioException {
      // celowo ignorowane
    }
  }

  Future<T> _serialized<T>(Future<T> Function() task) {
    final result = _queue.then((_) async {
      final last = _lastRequestAt;
      if (last != null) {
        final wait = minInterval - DateTime.now().difference(last);
        if (wait > Duration.zero) await Future<void>.delayed(wait);
      }
      try {
        return await task();
      } finally {
        _lastRequestAt = DateTime.now();
      }
    });
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  Future<Map<String, dynamic>> _send(
    String path,
    Map<String, String>? query,
  ) async {
    final session = _session ??= await _store.read();
    if (session == null || session.isEmpty) {
      throw const SessionExpiredException();
    }

    final Response<dynamic> response;
    try {
      response = await _dio.get<dynamic>(
        path,
        queryParameters: query,
        options: Options(headers: {'Cookie': session.toHeader()}),
      );
    } on DioException catch (e) {
      throw _mapDioException(e);
    }

    final setCookies = response.headers['set-cookie'];
    if (setCookies != null && setCookies.isNotEmpty) {
      final updated = session.merge(setCookies);
      if (!identical(updated, session)) {
        _session = updated;
        await _store.write(updated);
      }
    }

    return _decode(response, path);
  }

  Map<String, dynamic> _decode(Response<dynamic> response, String path) {
    final status = response.statusCode ?? 0;
    final endpoint = path.split('/').first;
    if (status == 401 || status == 403 || (status >= 300 && status < 400)) {
      throw const SessionExpiredException();
    }
    if (status == 429 || status == 503) {
      throw RateLimitedException(retryAfter: _retryAfter(response));
    }
    if (status != 200) throw ServerException(status);

    final data = response.data;
    if (data is! Map<String, dynamic>) {
      throw UnexpectedResponseException(
        '$endpoint: oczekiwano obiektu JSON, otrzymano ${data.runtimeType}',
      );
    }
    if (data['Status'] == 'Error') {
      throw UnexpectedResponseException(
        '$endpoint: Status=Error, Code=${data['Code'] ?? '-'}',
      );
    }
    return data;
  }

  static Duration? _retryAfter(Response<dynamic> response) {
    final seconds = int.tryParse(response.headers.value('retry-after') ?? '');
    return seconds == null ? null : Duration(seconds: seconds);
  }

  static SynergiaException _mapDioException(DioException e) => switch (e.type) {
    DioExceptionType.connectionTimeout ||
    DioExceptionType.sendTimeout ||
    DioExceptionType.receiveTimeout => const RequestTimeoutException(),
    DioExceptionType.badResponse => ServerException(
      e.response?.statusCode ?? 0,
    ),
    _ => const NetworkException(),
  };
}
