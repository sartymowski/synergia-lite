import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/storage/key_value_store.dart';
import '../../messages/domain/message.dart';
import '../../messages/presentation/messages_providers.dart';
import '../data/background_sync.dart';
import '../data/local_notification_service.dart';
import '../data/message_notification_checker.dart';
import '../data/sync_state_repository.dart';
import '../domain/background_policy.dart';
import '../domain/notification_intent.dart';
import '../domain/ports.dart';
import '../domain/sync_state.dart';

final notificationsKeyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => SecureKeyValueStore(),
);

final syncStateRepositoryProvider = Provider<MessageSyncStateRepository>(
  (ref) =>
      MessageSyncStateRepository(ref.watch(notificationsKeyValueStoreProvider)),
);

final notificationSettingsRepositoryProvider =
    Provider<NotificationSettingsRepository>(
      (ref) => NotificationSettingsRepository(
        ref.watch(notificationsKeyValueStoreProvider),
      ),
    );

/// Nadpisywany w `main()` instancją zainicjalizowaną z obsługą kliknięć.
final localNotificationServiceProvider = Provider<LocalNotificationService>(
  (ref) => LocalNotificationService(),
);

final messageNotifierProvider = Provider<MessageNotifier>(
  (ref) => ref.watch(localNotificationServiceProvider),
);

/// Uprawnienie POST_NOTIFICATIONS (osobno, żeby testy mogły je podmienić).
abstract interface class NotificationPermission {
  Future<bool> granted();
  Future<bool> request();
}

class _PluginPermission implements NotificationPermission {
  _PluginPermission(this._service);

  final LocalNotificationService _service;

  @override
  Future<bool> granted() => _service.canNotify();

  @override
  Future<bool> request() => _service.requestPermission();
}

final notificationPermissionProvider = Provider<NotificationPermission>(
  (ref) => _PluginPermission(ref.watch(localNotificationServiceProvider)),
);

final syncSchedulerProvider = Provider<SyncScheduler>(
  (ref) => WorkmanagerSyncScheduler(),
);

final backgroundSyncAllowedProvider = Provider<bool>(
  (ref) => BackgroundSyncPolicy.allowed,
);

/// Ten sam mechanizm co w zadaniu WorkManagera, na klientach aplikacji.
final messageNotificationCheckerProvider = Provider<MessageNotificationChecker>(
  (ref) => MessageNotificationChecker(
    messages: ref.watch(messagesRepositoryProvider),
    session: ref.watch(sessionStoreProvider),
    state: ref.watch(syncStateRepositoryProvider),
    settings: ref.watch(notificationSettingsRepositoryProvider),
    notifier: ref.watch(messageNotifierProvider),
  ),
);

/// Rejestruje albo anuluje zadanie zależnie od: dopuszczalności, sesji,
/// decyzji użytkownika i uprawnienia Androida. Zwraca, czy zadanie jest aktywne.
Future<bool> reconcileBackgroundSync({
  required bool policyAllowed,
  required bool signedIn,
  required NotificationSettingsRepository settings,
  required NotificationPermission permission,
  required SyncScheduler scheduler,
  required MessageSyncStateRepository state,
}) async {
  final enabled = (await settings.read()).enabled;
  if (policyAllowed && signedIn && enabled && await permission.granted()) {
    await state.clearPause();
    await scheduler.schedule();
    return true;
  }
  await scheduler.cancel();
  return false;
}

/// Uzgadnia harmonogram przy każdej zmianie stanu logowania.
final backgroundSyncReconcilerProvider = Provider<Future<bool> Function()>((
  ref,
) {
  Future<bool> reconcile() => reconcileBackgroundSync(
    policyAllowed: ref.read(backgroundSyncAllowedProvider),
    signedIn: ref.read(authControllerProvider).value is SignedIn,
    settings: ref.read(notificationSettingsRepositoryProvider),
    permission: ref.read(notificationPermissionProvider),
    scheduler: ref.read(syncSchedulerProvider),
    state: ref.read(syncStateRepositoryProvider),
  );

  ref.listen(authControllerProvider, (previous, next) {
    if (next.hasValue &&
        previous?.value.runtimeType != next.value.runtimeType) {
      unawaited(reconcile().catchError((_) => false));
    }
  });
  return reconcile;
});

/// Wylogowanie: koniec monitorowania i usunięcie lokalnego stanu powiadomień.
/// Kolejne kroki są niezależne — błąd jednego nie blokuje pozostałych.
final notificationsCleanupProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    for (final step in <Future<void> Function()>[
      () => ref.read(syncSchedulerProvider).cancel(),
      () => ref.read(notificationSettingsRepositoryProvider).clear(),
      () => ref.read(syncStateRepositoryProvider).clear(),
      () => ref.read(messageNotifierProvider).cancelAll(),
    ]) {
      try {
        await step();
      } catch (_) {
        // Brak wtyczki (np. testy) lub błąd systemu — kontynuujemy czyszczenie.
      }
    }
  };
});

class NotificationStatus {
  const NotificationStatus({
    required this.policyAllowed,
    required this.enabled,
    required this.permissionGranted,
    this.state,
  });

  final bool policyAllowed;
  final bool enabled;
  final bool permissionGranted;
  final MessageSyncState? state;
}

final notificationStatusProvider =
    FutureProvider.autoDispose<NotificationStatus>((ref) async {
      bool granted;
      try {
        granted = await ref.watch(notificationPermissionProvider).granted();
      } catch (_) {
        granted = false;
      }
      return NotificationStatus(
        policyAllowed: ref.watch(backgroundSyncAllowedProvider),
        enabled:
            (await ref.watch(notificationSettingsRepositoryProvider).read())
                .enabled,
        permissionGranted: granted,
        state: await ref.watch(syncStateRepositoryProvider).readAny(),
      );
    });

/// Kliknięcia powiadomień, gdy aplikacja działa (z `onDidReceiveNotificationResponse`).
class NotificationTapBus {
  NotificationTapBus._();

  static final instance = NotificationTapBus._();
  final _controller = StreamController<NotificationIntent>.broadcast();

  Stream<NotificationIntent> get stream => _controller.stream;

  void add(NotificationIntent? intent) {
    if (intent != null) _controller.add(intent);
  }
}

/// Zimny start z powiadomienia — nadpisywany w `main()`.
final initialNotificationIntentProvider = Provider<NotificationIntent?>(
  (ref) => null,
);

/// Oczekująca nawigacja z powiadomienia. Zostaje do czasu, aż ekran główny
/// (dostępny dopiero po zalogowaniu) ją przejmie.
class NotificationIntentController extends Notifier<NotificationIntent?> {
  @override
  NotificationIntent? build() {
    final sub = NotificationTapBus.instance.stream.listen((i) => state = i);
    ref.onDispose(sub.cancel);
    return ref.read(initialNotificationIntentProvider);
  }

  void push(NotificationIntent intent) => state = intent;

  /// Zwraca i usuwa oczekujący cel (obsługa tylko raz).
  NotificationIntent? take() {
    final current = state;
    state = null;
    return current;
  }
}

final notificationIntentProvider =
    NotifierProvider<NotificationIntentController, NotificationIntent?>(
      NotificationIntentController.new,
    );

/// Gdzie prowadzi powiadomienie dla aktualnie zalogowanego konta.
sealed class NotificationTarget {
  const NotificationTarget();
}

final class TargetMessage extends NotificationTarget {
  const TargetMessage(this.messageId);

  final String messageId;
}

final class TargetInbox extends NotificationTarget {
  const TargetInbox({this.otherAccount = false});

  /// Powiadomienie dotyczyło innego konta niż obecnie zalogowane.
  final bool otherAccount;
}

final class TargetHome extends NotificationTarget {
  const TargetHome();
}

/// Rozstrzyga cel; wiadomość otwieramy tylko dla tego samego konta.
NotificationTarget resolveNotificationTarget(
  NotificationIntent intent,
  String? currentOwner,
) {
  final tag = currentOwner == null ? null : ownerTag(currentOwner);
  return switch (intent) {
    OpenMessage(:final ownerTag, :final messageId) =>
      ownerTag == tag
          ? TargetMessage(messageId)
          : TargetInbox(otherAccount: tag != null),
    OpenInbox(:final ownerTag) => TargetInbox(
      otherAccount: tag != null && ownerTag != tag,
    ),
    OpenApp() => const TargetHome(),
  };
}

/// Oznacza wiadomości widoczne w aplikacji jako znane (bez powiadomień o nich).
Future<void> markInboxSeen(Ref ref, List<MessageSummary> items) async {
  try {
    final owner = await ref.read(messagesAccountKeyProvider.future);
    await ref.read(messageNotificationCheckerProvider).markSeen(owner, items);
  } catch (_) {
    // Najlepsza próba — brak wpływu na wyświetlanie listy.
  }
}
