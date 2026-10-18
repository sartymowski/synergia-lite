import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../domain/diagnostic_report.dart';

/// Raport diagnostyczny. Zawiera tylko strukturę odpowiedzi, więc można go
/// bezpiecznie skopiować i przekazać dalej.
class DiagnosticsScreen extends StatefulWidget {
  const DiagnosticsScreen({super.key, required this.run});

  final Future<DiagnosticReport> Function() run;

  @override
  State<DiagnosticsScreen> createState() => _DiagnosticsScreenState();
}

class _DiagnosticsScreenState extends State<DiagnosticsScreen> {
  late Future<DiagnosticReport> _report = widget.run();

  static const _icons = {
    CheckStatus.ok: Icons.check_circle_outline,
    CheckStatus.warning: Icons.warning_amber_outlined,
    CheckStatus.failed: Icons.error_outline,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Diagnostyka integracji')),
      body: FutureBuilder(
        future: _report,
        builder: (context, snapshot) {
          final report = snapshot.data;
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Diagnostyka przerwana: ${snapshot.error.runtimeType}',
              ),
            );
          }
          if (report == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final verdictColor = switch (report.verdict) {
            AuthVerdict.authenticated => scheme.primaryContainer,
            AuthVerdict.inconclusive => scheme.tertiaryContainer,
            AuthVerdict.notAuthenticated => scheme.errorContainer,
          };
          return ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Card(
                color: verdictColor,
                margin: const EdgeInsets.all(16),
                child: ListTile(
                  title: Text(DiagnosticReport.verdictLabels[report.verdict]!),
                  subtitle: const Text(
                    'Raport nie zawiera wartości ciasteczek, tokenów ani danych '
                    'ucznia — tylko kody HTTP, liczby i nazwy pól.',
                  ),
                ),
              ),
              for (final c in report.checks)
                ListTile(
                  leading: Icon(_icons[c.status]),
                  title: Text(c.title),
                  subtitle: Text(c.facts.join('\n')),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.copy),
                      label: const Text('Kopiuj raport'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: report.toText()),
                        );
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Skopiowano raport')),
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Uruchom ponownie'),
                      onPressed: () => setState(() => _report = widget.run()),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
