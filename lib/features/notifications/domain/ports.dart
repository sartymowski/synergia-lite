import '../../messages/domain/message.dart';

/// Wyświetlanie powiadomień (Android: flutter_local_notifications; w testach atrapa).
abstract interface class MessageNotifier {
  /// Czy system pozwala aplikacji pokazywać powiadomienia (uprawnienie
  /// POST_NOTIFICATIONS na Androidzie 13+ i niewyłączone w ustawieniach).
  Future<bool> canNotify();

  /// Treść jest ogólna — bez nadawcy, tematu i fragmentu wiadomości.
  Future<void> showNewMessages(String owner, List<MessageSummary> messages);

  /// Jednorazowa informacja, że monitorowanie wstrzymano (np. wygasła sesja).
  Future<void> showMonitoringPaused(String reason);

  Future<void> cancelAll();
}

/// Rejestracja okresowego zadania (Android: WorkManager; w testach atrapa).
abstract interface class SyncScheduler {
  Future<void> schedule();
  Future<void> cancel();
}
