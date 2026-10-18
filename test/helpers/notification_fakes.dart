import 'package:synergia_lite/features/messages/domain/message.dart';
import 'package:synergia_lite/features/notifications/domain/notification_intent.dart';
import 'package:synergia_lite/features/notifications/domain/ports.dart';
import 'package:synergia_lite/features/notifications/presentation/notifications_providers.dart';

/// Atrapa powiadomień: zapisuje, co i pod jakim identyfikatorem by pokazano.
class FakeNotifier implements MessageNotifier, NotificationPermission {
  bool allowed = true;
  bool grantOnRequest = true;
  int permissionRequests = 0;
  final shown = <({String owner, List<String> ids, int notificationId})>[];
  final paused = <String>[];
  int cancelled = 0;

  @override
  Future<bool> canNotify() async => allowed;

  @override
  Future<bool> granted() async => allowed;

  @override
  Future<bool> request() async {
    permissionRequests++;
    allowed = grantOnRequest;
    return allowed;
  }

  @override
  Future<void> showNewMessages(
    String owner,
    List<MessageSummary> messages,
  ) async {
    shown.add((
      owner: owner,
      ids: [for (final m in messages) m.id],
      notificationId: messages.length == 1
          ? NotificationIds.forMessage(owner, messages.single.id)
          : NotificationIds.summary,
    ));
  }

  @override
  Future<void> showMonitoringPaused(String reason) async => paused.add(reason);

  @override
  Future<void> cancelAll() async => cancelled++;
}

class FakeScheduler implements SyncScheduler {
  int scheduled = 0;
  int cancelled = 0;
  bool get active => _active;
  bool _active = false;

  @override
  Future<void> schedule() async {
    scheduled++;
    _active = true;
  }

  @override
  Future<void> cancel() async {
    cancelled++;
    _active = false;
  }
}
