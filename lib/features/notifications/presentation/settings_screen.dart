import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/build_config.dart';
import '../../../shared/format.dart';
import '../data/message_notification_checker.dart';
import '../domain/background_policy.dart';
import 'notifications_providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _busy = false;
  String? _lastCheck;

  Future<void> _guarded(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      ref.invalidate(notificationStatusProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  /// Włączenie: uprawnienie Androida w tym momencie, zapis decyzji, pierwsza
  /// synchronizacja (stan bazowy bez powiadomień) i rejestracja zadania.
  Future<void> _enable() => _guarded(() async {
    final permission = ref.read(notificationPermissionProvider);
    if (!await permission.granted() && !await permission.request()) {
      _toast(
        'Bez uprawnienia Android nie pokaże powiadomień. Możesz je nadać w ustawieniach systemu.',
      );
      return;
    }
    await ref.read(notificationSettingsRepositoryProvider).setEnabled(true);
    final outcome = await ref
        .read(messageNotificationCheckerProvider)
        .run(trigger: SyncTrigger.manual);
    setState(() => _lastCheck = outcome.label);
    await ref.read(backgroundSyncReconcilerProvider)();
    _toast('Powiadomienia włączone.');
  });

  Future<void> _disable() => _guarded(() async {
    await ref.read(notificationSettingsRepositoryProvider).setEnabled(false);
    await ref.read(syncSchedulerProvider).cancel();
    _toast('Powiadomienia wyłączone — sprawdzanie w tle zatrzymane.');
  });

  Future<void> _requestPermission() => _guarded(() async {
    final granted = await ref.read(notificationPermissionProvider).request();
    if (!granted) _toast('Uprawnienie nie zostało przyznane.');
    await ref.read(backgroundSyncReconcilerProvider)();
  });

  Future<void> _checkNow() => _guarded(() async {
    final outcome = await ref
        .read(messageNotificationCheckerProvider)
        .run(trigger: SyncTrigger.manual);
    setState(() => _lastCheck = outcome.label);
  });

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(notificationStatusProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Ustawienia')),
      body: status.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Text('Nie udało się odczytać ustawień (${e.runtimeType}).'),
        ),
        data: (s) {
          final state = s.state;
          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Powiadomienia', style: theme.textTheme.titleSmall),
              ),
              if (!s.policyAllowed)
                Card(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: theme.colorScheme.tertiaryContainer,
                  child: const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text(
                      'Sprawdzanie w tle jest wyłączone w tej wersji',
                    ),
                    subtitle: Text(
                      'Regulamin Synergii nie określa wprost, czy aplikacja może automatycznie '
                      'sprawdzać skrzynkę co kilkadziesiąt minut. Do czasu potwierdzenia '
                      'dopuszczalności okresowe sprawdzanie pozostaje nieaktywne. Wiadomości '
                      'możesz zawsze sprawdzić w zakładce „Wiadomości”.',
                    ),
                  ),
                ),
              SwitchListTile(
                title: const Text('Powiadomienia o nowych wiadomościach'),
                subtitle: Text(
                  'Sprawdzanie ok. co ${BackgroundSyncPolicy.interval.inMinutes} min, gdy telefon ma '
                  'internet. Treść powiadomienia nie zawiera nadawcy ani tematu.',
                ),
                value: s.policyAllowed && s.enabled,
                onChanged: !s.policyAllowed || _busy
                    ? null
                    : (v) => v ? _enable() : _disable(),
              ),
              ListTile(
                leading: Icon(
                  s.permissionGranted
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                ),
                title: const Text('Uprawnienie Androida'),
                subtitle: Text(
                  s.permissionGranted
                      ? 'Przyznane'
                      : 'Nieprzyznane — powiadomienia nie będą wyświetlane.',
                ),
                trailing: s.permissionGranted
                    ? null
                    : TextButton(
                        onPressed: _busy ? null : _requestPermission,
                        child: const Text('Nadaj'),
                      ),
              ),
              ListTile(
                leading: const Icon(Icons.sync),
                title: const Text('Ostatnia udana synchronizacja'),
                subtitle: Text(
                  [
                    state?.lastSuccessAt == null
                        ? 'Jeszcze nie było'
                        : formatDateTime(state!.lastSuccessAt!),
                    if (state?.pausedReason == pausedSessionExpired)
                      'Wstrzymano: sesja wygasła — zaloguj się ponownie.',
                    if (state?.pausedReason == pausedModuleUnavailable)
                      'Wstrzymano: moduł Wiadomości niedostępny.',
                    if (state?.lastError != null && state?.pausedReason == null)
                      'Ostatni błąd: ${state!.lastError}',
                    if (state?.retryNotBefore != null &&
                        state!.retryNotBefore!.isAfter(DateTime.now()))
                      'Przerwa po HTTP 429 do ${formatDateTime(state.retryNotBefore!)}',
                  ].join('\n'),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Powiadomienia mogą przychodzić z opóźnieniem: Android decyduje o terminie '
                  'sprawdzania (oszczędzanie baterii, tryb Doze). Wymuszone zatrzymanie aplikacji '
                  'w ustawieniach systemu wstrzymuje sprawdzanie do ponownego uruchomienia aplikacji.',
                ),
              ),
              if (BuildConfig.current.developerTools) ...[
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.bug_report_outlined),
                  title: const Text('Sprawdź teraz (debug)'),
                  subtitle: Text(
                    _lastCheck ??
                        'Ten sam mechanizm co zadanie w tle; jedno sprawdzenie skrzynki.',
                  ),
                  trailing: _busy
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _busy ? null : _checkNow,
                ),
              ],
              const Divider(),
              const AboutSection(config: BuildConfig.current),
            ],
          );
        },
      ),
    );
  }
}

/// Wersja, charakter aplikacji i aktywne funkcje eksperymentalne — testerzy
/// podają te dane w zgłoszeniach (docs/beta/feedback-template.md).
class AboutSection extends StatelessWidget {
  const AboutSection({super.key, required this.config});

  final BuildConfig config;

  @override
  Widget build(BuildContext context) {
    final experimental = config.experimentalFeatures;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(
            'O aplikacji',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text('Synergia Lite ${config.versionLabel}'),
          subtitle: const Text(
            'Nieoficjalna aplikacja, niezwiązana z firmą Librus. Logowanie odbywa się '
            'na stronie Librusa; aplikacja nie zna hasła i nie wysyła danych nigdzie '
            'poza serwery Librusa. Wylogowanie usuwa z telefonu sesję, wiadomości '
            'robocze i stan powiadomień.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.science_outlined),
          title: const Text('Funkcje eksperymentalne'),
          subtitle: Text(
            experimental.isEmpty
                ? 'Wyłączone (logowanie przez stronę Librusa nadal jest '
                      'mechanizmem testowym).'
                : 'Włączone: ${experimental.join(', ')}.',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.description_outlined),
          title: const Text('Licencje bibliotek'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Synergia Lite',
            applicationVersion: config.versionLabel,
          ),
        ),
      ],
    );
  }
}
