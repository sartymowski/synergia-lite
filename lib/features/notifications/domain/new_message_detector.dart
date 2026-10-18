import '../../messages/domain/message.dart';
import 'sync_state.dart';

/// Wynik porównania pobranej listy Odebranych ze stanem zapisanym lokalnie.
class Detection {
  const Detection({
    required this.newMessages,
    required this.knownIds,
    required this.watermark,
  });

  /// Wiadomości nowe względem poprzedniej udanej synchronizacji (od najnowszej).
  final List<MessageSummary> newMessages;

  /// Zaktualizowana lista znanych identyfikatorów (do zapisania w stanie).
  final List<String> knownIds;
  final DateTime? watermark;
}

/// Tolerancja dla dat wysłania nieco starszych od znaku wodnego (np. kilka
/// wiadomości wysłanych w tej samej minucie albo różnice zegarów).
const watermarkTolerance = Duration(hours: 24);

/// Czysta logika wykrywania:
/// - nowa = identyfikator nieznany i data wysłania nie starsza niż znak wodny
///   minus tolerancja (stara wiadomość przywrócona z kosza nie budzi alarmu);
/// - zmiana statusu przeczytania nie ma znaczenia (porównujemy tylko id);
/// - znane identyfikatory tylko przybywają (pusta lub częściowa odpowiedź nie
///   „zapomina” wiadomości, więc nie wywoła ponownych powiadomień);
/// - kolejność listy z API nie jest zakładana.
Detection detectNewMessages(
  MessageSyncState state,
  Iterable<MessageSummary> fetched,
) {
  final known = state.knownIds.toSet();
  final items = fetched.where((m) => m.folder == MessageFolder.inbox).toList();
  final cutoff = state.watermark?.subtract(watermarkTolerance);
  final fresh = <MessageSummary>[];
  final seenNow = <String>{};
  for (final m in items) {
    if (!seenNow.add(m.id) || known.contains(m.id)) continue;
    final sent = m.sentAt;
    if (cutoff != null && sent != null && sent.isBefore(cutoff)) continue;
    fresh.add(m);
  }
  fresh.sort((a, b) {
    final da = a.sentAt, db = b.sentAt;
    if (da == null || db == null) return 0;
    return db.compareTo(da);
  });

  final sortedFetched = [...items]
    ..sort((a, b) {
      final da = a.sentAt, db = b.sentAt;
      if (da == null || db == null) return 0;
      return db.compareTo(da);
    });
  DateTime? watermark = state.watermark;
  for (final m in items) {
    final s = m.sentAt;
    if (s != null && (watermark == null || s.isAfter(watermark))) watermark = s;
  }
  return Detection(
    newMessages: fresh,
    knownIds: [for (final m in sortedFetched) m.id, ...state.knownIds],
    watermark: watermark,
  );
}

/// Najnowsza data wysłania w pobranej liście (znak wodny dla stanu bazowego).
DateTime? newestSentAt(Iterable<MessageSummary> items) {
  DateTime? newest;
  for (final m in items) {
    final s = m.sentAt;
    if (s != null && (newest == null || s.isAfter(newest))) newest = s;
  }
  return newest;
}

/// Polska odmiana: 1 wiadomość, 2–4 wiadomości, 5+ wiadomości (12–14 → wiadomości).
String newMessagesPhrase(int n) {
  final lastTwo = n % 100;
  final last = n % 10;
  final noun = n == 1
      ? 'nową wiadomość'
      : (last >= 2 && last <= 4 && (lastTwo < 12 || lastTwo > 14))
      ? 'nowe wiadomości'
      : 'nowych wiadomości';
  return n == 1 ? 'Masz $noun.' : 'Masz $n $noun w Synergii.';
}
