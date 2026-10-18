import 'dart:ui';

import 'package:workmanager/workmanager.dart';

import '../../../core/security/session_store.dart';
import '../../../core/storage/key_value_store.dart';
import '../../messages/data/messages_api_client.dart';
import '../../messages/data/messages_repository.dart';
import '../domain/background_policy.dart';
import '../domain/ports.dart';
import 'local_notification_service.dart';
import 'message_notification_checker.dart';
import 'sync_state_repository.dart';

/// Rejestracja okresowego sprawdzania w Android WorkManager.
class WorkmanagerSyncScheduler implements SyncScheduler {
  WorkmanagerSyncScheduler([Workmanager? workmanager])
    : _wm = workmanager ?? Workmanager();

  static const uniqueName = 'synergia-messages-check';
  static const taskName = 'synergiaMessagesCheck';

  final Workmanager _wm;

  /// Idempotentne (`keep`): ponowne wywołanie nie przesuwa harmonogramu.
  @override
  Future<void> schedule() => _wm.registerPeriodicTask(
    uniqueName,
    taskName,
    frequency: BackgroundSyncPolicy.interval,
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
    backoffPolicy: BackoffPolicy.exponential,
    backoffPolicyDelay: BackgroundSyncPolicy.backoffDelay,
  );

  @override
  Future<void> cancel() => _wm.cancelByUniqueName(uniqueName);
}

/// Punkt wejścia WorkManagera — osobny kontekst wykonania: brak WebView,
/// widżetów i providerów; wszystko jest odtwarzane z magazynu sesji.
@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    if (task != WorkmanagerSyncScheduler.taskName) return true;
    DartPluginRegistrant.ensureInitialized();
    return runBackgroundSync();
  });
}

/// Jedno uruchomienie w tle. Zwraca wynik dla WorkManagera (`false` = ponów).
Future<bool> runBackgroundSync({
  SessionStore? session,
  KeyValueStore? kv,
  MessagesApiClient? client,
  MessageNotifier? notifier,
  SyncScheduler? scheduler,
  bool policyAllowed = BackgroundSyncPolicy.allowed,
}) async {
  if (!policyAllowed) {
    // Zadanie z buildu, w którym synchronizacja w tle była dozwolona.
    await (scheduler ?? WorkmanagerSyncScheduler()).cancel();
    return true;
  }
  final store = session ?? SecureSessionStore();
  final storage = kv ?? SecureKeyValueStore();
  final notify = notifier ?? LocalNotificationService();
  final settings = NotificationSettingsRepository(storage);
  final checker = MessageNotificationChecker(
    messages: MessagesRepository(
      client ?? MessagesApiClient(synergiaSession: store),
    ),
    session: store,
    state: MessageSyncStateRepository(storage),
    settings: settings,
    notifier: notify,
  );
  final outcome = await checker.run(trigger: SyncTrigger.background);
  if (outcome.stopsMonitoring) {
    // Bez sesji lub z wyłączonymi powiadomieniami nie odpytujemy dalej.
    await (scheduler ?? WorkmanagerSyncScheduler()).cancel();
    if (outcome is SyncPaused &&
        outcome.newlyPaused &&
        (await settings.read()).enabled) {
      await notify.showMonitoringPaused(outcome.reason);
    }
  }
  return outcome.workSucceeded;
}
