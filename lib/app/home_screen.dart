import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/webview_session.dart';
import '../features/diagnostics/data/integration_probe.dart';
import '../features/diagnostics/presentation/diagnostics_screen.dart';
import '../features/grades/presentation/grades_view.dart';
import '../features/messages/domain/message.dart';
import '../features/messages/presentation/message_detail_screen.dart';
import '../features/messages/presentation/messages_providers.dart';
import '../features/messages/presentation/messages_tab.dart';
import '../features/notifications/presentation/notifications_providers.dart';
import '../features/notifications/presentation/settings_screen.dart';
import '../features/timetable/presentation/timetable_view.dart';
import 'providers.dart';

/// Powłoka aplikacji: Oceny, Plan lekcji, Wiadomości; obsługa kliknięć powiadomień.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;
  final _visited = <int>{0};
  int _messagesKey = 0;

  @override
  void initState() {
    super.initState();
    // Zimny start / powrót po zalogowaniu: cel z powiadomienia czeka w providerze.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _consumeNotificationIntent(),
    );
  }

  /// Kliknięte powiadomienie: Odebrane, a dla tego samego konta — wiadomość.
  Future<void> _consumeNotificationIntent() async {
    final intent = ref.read(notificationIntentProvider.notifier).take();
    if (intent == null || !mounted) return;
    String? owner;
    try {
      owner = await ref.read(messagesAccountKeyProvider.future);
    } catch (_) {
      owner = null; // bez konta wiadomości otwieramy tylko Odebrane
    }
    if (!mounted) return;
    final target = resolveNotificationTarget(intent, owner);
    if (target is TargetHome) return;
    ref.invalidate(messageListProvider(MessageFolder.inbox));
    setState(() {
      _tab = 2;
      _visited.add(2);
      _messagesKey++;
    });
    switch (target) {
      case TargetMessage(:final messageId):
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                MessageDetailScreen(folder: MessageFolder.inbox, id: messageId),
          ),
        );
      case TargetInbox(otherAccount: true):
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Powiadomienie dotyczyło innego konta — otwarto Odebrane.',
            ),
          ),
        );
      case TargetInbox() || TargetHome():
        break;
    }
  }

  void _openSettings() => Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  void _openDiagnostics() {
    final api = ref.read(apiClientProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiagnosticsScreen(
          run: () async => IntegrationProbe(
            api,
            messages: ref.read(messagesApiClientProvider),
          ).run(webCookies: await readSynergiaCookies()),
        ),
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Wylogować?'),
        content: const Text(
          'Sesja i dane logowania przeglądarki zostaną usunięte z telefonu.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Anuluj'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Wyloguj'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context) {
    final student = ref.watch(accountProvider).value?.studentFirstName;
    final unread = ref.watch(unreadCountProvider).value ?? 0;
    ref.listen(notificationIntentProvider, (_, next) {
      if (next != null) _consumeNotificationIntent();
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text('Synergia Lite'),
        bottom: student == null
            ? null
            : PreferredSize(
                preferredSize: const Size.fromHeight(20),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('Uczeń: $student'),
                ),
              ),
        actions: [
          IconButton(
            tooltip: 'Ustawienia',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          IconButton(
            tooltip: 'Diagnostyka integracji',
            icon: const Icon(Icons.health_and_safety_outlined),
            onPressed: _openDiagnostics,
          ),
          IconButton(
            tooltip: 'Wyloguj',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [
          const GradesView(),
          const TimetableView(),
          // Budowana dopiero po pierwszym otwarciu (bez zbędnych zapytań).
          if (_visited.contains(2))
            MessagesTab(key: ValueKey(_messagesKey))
          else
            const SizedBox(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() {
          _tab = i;
          _visited.add(i);
        }),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.grade_outlined),
            label: 'Oceny',
          ),
          const NavigationDestination(
            icon: Icon(Icons.calendar_view_week),
            label: 'Plan lekcji',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: unread > 0,
              label: Text('$unread'),
              child: const Icon(Icons.mail_outline),
            ),
            label: 'Wiadomości',
          ),
        ],
      ),
    );
  }
}
