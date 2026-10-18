import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../messages/domain/message.dart';
import '../domain/new_message_detector.dart';
import '../domain/notification_intent.dart';
import '../domain/ports.dart';
import 'message_notification_checker.dart' show pausedSessionExpired;

/// Powiadomienia Androida. Treść jest zawsze ogólna (bez nadawcy, tematu,
/// fragmentu treści), a payload zawiera tylko [NotificationIntent].
class LocalNotificationService implements MessageNotifier {
  LocalNotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const messagesChannel = AndroidNotificationChannel(
    'synergia_messages',
    'Nowe wiadomości',
    description: 'Nowe wiadomości przychodzące w Synergii.',
  );

  static const statusChannel = AndroidNotificationChannel(
    'synergia_sync_status',
    'Stan powiadomień',
    description: 'Informacja, że sprawdzanie wiadomości zostało wstrzymane.',
    importance: Importance.low,
  );

  /// Drawable `android/app/src/main/res/drawable/ic_stat_synergia.xml`.
  static const _icon = 'ic_stat_synergia';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// [onTap] — kliknięcie, gdy aplikacja działa (ciepły start / wznowienie).
  Future<void> initialize({
    void Function(NotificationIntent? intent)? onTap,
  }) async {
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings(_icon),
      ),
      onDidReceiveNotificationResponse: onTap == null
          ? null
          : (response) => onTap(NotificationIntent.decode(response.payload)),
    );
    await _android?.createNotificationChannel(messagesChannel);
    await _android?.createNotificationChannel(statusChannel);
    _initialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) await initialize();
  }

  /// Zimny start: czy aplikację uruchomiło kliknięcie powiadomienia.
  Future<NotificationIntent?> launchIntent() async {
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return NotificationIntent.decode(details.notificationResponse?.payload);
  }

  @override
  Future<bool> canNotify() async {
    await _ensureInitialized();
    return await _android?.areNotificationsEnabled() ?? false;
  }

  /// Android 13+: systemowe okno zgody na POST_NOTIFICATIONS.
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    return await _android?.requestNotificationsPermission() ?? false;
  }

  static AndroidNotificationDetails _details(
    AndroidNotificationChannel channel,
  ) => AndroidNotificationDetails(
    channel.id,
    channel.name,
    channelDescription: channel.description,
    importance: channel.importance,
    icon: _icon,
    category: AndroidNotificationCategory.message,
    // Na ekranie blokady bez szczegółów.
    visibility: NotificationVisibility.private,
    onlyAlertOnce: true,
    autoCancel: true,
  );

  @override
  Future<void> showNewMessages(
    String owner,
    List<MessageSummary> messages,
  ) async {
    if (messages.isEmpty) return;
    await _ensureInitialized();
    final tag = ownerTag(owner);
    if (messages.length == 1) {
      final m = messages.single;
      await _plugin.show(
        id: NotificationIds.forMessage(owner, m.id),
        title: 'Nowa wiadomość w Synergii',
        body: newMessagesPhrase(1),
        notificationDetails: NotificationDetails(
          android: _details(messagesChannel),
        ),
        payload: OpenMessage(ownerTag: tag, messageId: m.id).encode(),
      );
      return;
    }
    await _plugin.show(
      id: NotificationIds.summary,
      title: 'Nowe wiadomości w Synergii',
      body: newMessagesPhrase(messages.length),
      notificationDetails: NotificationDetails(
        android: _details(messagesChannel),
      ),
      payload: OpenInbox(ownerTag: tag).encode(),
    );
  }

  @override
  Future<void> showMonitoringPaused(String reason) async {
    await _ensureInitialized();
    await _plugin.show(
      id: NotificationIds.status,
      title: 'Powiadomienia o wiadomościach wstrzymane',
      body: reason == pausedSessionExpired
          ? 'Sesja wygasła. Otwórz Synergia Lite i zaloguj się, aby je wznowić.'
          : 'Moduł Wiadomości jest niedostępny dla tego konta.',
      notificationDetails: NotificationDetails(
        android: _details(statusChannel),
      ),
      payload: const OpenApp().encode(),
    );
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _plugin.cancelAll();
  }
}
