/// Błędy warstwy integracji z Synergią.
///
/// [message] jest przeznaczone do pokazania użytkownikowi (po polsku)
/// i nigdy nie zawiera ciasteczek, tokenów ani danych osobowych.
sealed class SynergiaException implements Exception {
  const SynergiaException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Brak sesji albo serwer odrzucił sesję (HTTP 401 / 403).
final class SessionExpiredException extends SynergiaException {
  const SessionExpiredException()
    : super('Sesja wygasła. Zaloguj się ponownie.');
}

/// Brak połączenia lub błąd na poziomie gniazda / TLS.
final class NetworkException extends SynergiaException {
  const NetworkException()
    : super('Brak połączenia z Synergią. Sprawdź internet.');
}

final class RequestTimeoutException extends SynergiaException {
  const RequestTimeoutException()
    : super('Synergia nie odpowiada. Spróbuj ponownie za chwilę.');
}

/// HTTP 429 albo 503 z nagłówkiem Retry-After.
final class RateLimitedException extends SynergiaException {
  const RateLimitedException({this.retryAfter})
    : super('Zbyt wiele zapytań. Odczekaj chwilę przed odświeżeniem.');

  final Duration? retryAfter;
}

final class ServerException extends SynergiaException {
  const ServerException(this.statusCode)
    : super('Synergia zwróciła błąd ($statusCode).');

  final int statusCode;
}

/// Odpowiedź ma inny kształt niż oczekiwany — najczęściej oznacza zmianę
/// po stronie Librusa. [detail] opisuje strukturę, nie zawartość.
final class UnexpectedResponseException extends SynergiaException {
  const UnexpectedResponseException(this.detail)
    : super(
        'Nieoczekiwana odpowiedź Synergii. Możliwa zmiana po stronie Librusa.',
      );

  final String detail;

  @override
  String toString() => 'UnexpectedResponseException: $detail';
}

/// Logowanie zakończyło się w WebView, ale Synergia nie przyjmuje sesji.
/// [cookieNames] (bez wartości) pomaga zdiagnozować zmianę przepływu.
final class LoginNotCompletedException extends SynergiaException {
  LoginNotCompletedException(this.cookieNames)
    : super('Logowanie nie zostało dokończone — Synergia nie przyjęła sesji.');

  final List<String> cookieNames;
}

/// Szkoła nie udostępnia modułu Wiadomości temu kontu (strona „Brak dostępu”).
final class MessagesUnavailableException extends SynergiaException {
  const MessagesUnavailableException()
    : super('Moduł Wiadomości nie jest dostępny dla tego konta.');
}

/// Sesja serwisu wiadomości wygasła i nie udało się jej odnowić
/// (sesja Synergii może nadal działać).
final class MessagesSessionExpiredException extends SynergiaException {
  const MessagesSessionExpiredException()
    : super(
        'Nie udało się odnowić sesji wiadomości. Spróbuj ponownie później '
        'albo zaloguj się ponownie.',
      );
}

/// Serwer odmówił dostępu do zasobu lub operacji (HTTP 403).
final class PermissionDeniedException extends SynergiaException {
  const PermissionDeniedException()
    : super('Brak uprawnień do tej operacji na tym koncie.');
}
