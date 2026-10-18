import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'app/app.dart';
import 'features/notifications/data/background_sync.dart';
import 'features/notifications/data/local_notification_service.dart';
import 'features/notifications/domain/notification_intent.dart';
import 'features/notifications/presentation/notifications_providers.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final notifications = LocalNotificationService();
  NotificationIntent? launchIntent;
  try {
    await notifications.initialize(onTap: NotificationTapBus.instance.add);
    // Zimny start z powiadomienia.
    launchIntent = await notifications.launchIntent();
  } catch (_) {
    // Bez powiadomień aplikacja nadal działa.
  }
  try {
    await Workmanager().initialize(callbackDispatcher);
  } catch (_) {
    // Brak WorkManagera = brak synchronizacji w tle; reszta działa.
  }

  runApp(
    // Bez automatycznych ponowień: odświeżanie tylko na żądanie użytkownika,
    // żeby nie generować zbędnego ruchu do Synergii.
    ProviderScope(
      retry: (_, _) => null,
      overrides: [
        localNotificationServiceProvider.overrideWithValue(notifications),
        initialNotificationIntentProvider.overrideWithValue(launchIntent),
      ],
      child: const SynergiaLiteApp(),
    ),
  );
}
