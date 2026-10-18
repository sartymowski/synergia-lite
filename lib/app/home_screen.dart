import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/data/webview_session.dart';
import '../features/diagnostics/data/integration_probe.dart';
import '../features/diagnostics/presentation/diagnostics_screen.dart';
import '../features/grades/presentation/grades_view.dart';
import '../features/timetable/presentation/timetable_view.dart';
import 'providers.dart';

/// Etap A: tymczasowa powłoka do weryfikacji integracji (oceny + plan).
/// Dashboard i pełna nawigacja przyjdą w etapach B/D.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _tab = 0;

  void _openDiagnostics() {
    final api = ref.read(apiClientProvider);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DiagnosticsScreen(
          run: () async => IntegrationProbe(
            api,
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
        children: const [GradesView(), TimetableView()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.grade_outlined),
            label: 'Oceny',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_view_week),
            label: 'Plan lekcji',
          ),
        ],
      ),
    );
  }
}
