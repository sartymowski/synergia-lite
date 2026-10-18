import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/notifications/presentation/notifications_providers.dart';
import 'router.dart';
import 'theme.dart';

class SynergiaLiteApp extends ConsumerWidget {
  const SynergiaLiteApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Uzgadnia harmonogram sprawdzania w tle przy zmianach stanu logowania.
    ref.watch(backgroundSyncReconcilerProvider);
    return MaterialApp.router(
      title: 'Synergia Lite',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      routerConfig: ref.watch(routerProvider),
      debugShowCheckedModeBanner: false,
    );
  }
}
