/// Wynik jednej (nigdy nie ponawianej) próby wysłania.
sealed class SendOutcome {
  const SendOutcome();
}

/// Librus potwierdził przyjęcie. Odpowiedź w wątku nie zwraca identyfikatora.
final class SendSucceeded extends SendOutcome {
  const SendSucceeded({this.messageId});

  final String? messageId;
}

/// Na pewno nie wysłano (np. odrzucona sesja, błąd walidacji 4xx,
/// brak połączenia przed wysłaniem żądania).
final class SendRejected extends SendOutcome {
  const SendRejected(this.reason, {this.serverMessages = const []});

  final String reason;

  /// Komunikaty błędów zwrócone przez Librusa (do pokazania, nie do logów).
  final List<String> serverMessages;
}

/// Nie wiadomo, czy wiadomość wyszła (timeout po wysłaniu, 5xx, odpowiedź
/// sukcesu z informacją o błędzie). Przed ponowną próbą sprawdź Wysłane.
final class SendUnknown extends SendOutcome {
  const SendUnknown(this.reason);

  final String reason;
}
