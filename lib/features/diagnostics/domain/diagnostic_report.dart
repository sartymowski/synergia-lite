enum CheckStatus { ok, warning, failed }

enum AuthVerdict {
  /// `Me` z sesją zwraca konto, a bez sesji — 401/403.
  authenticated,

  /// `Me` z sesją działa, ale kontrola negatywna nie wypadła zgodnie z oczekiwaniem.
  inconclusive,
  notAuthenticated,
}

/// Wynik jednego kroku. [facts] zawierają wyłącznie dane strukturalne:
/// kody HTTP, liczby, nazwy kluczy JSON i nazwy/atrybuty ciasteczek.
class DiagnosticCheck {
  const DiagnosticCheck(this.title, this.status, this.facts);

  final String title;
  final CheckStatus status;
  final List<String> facts;
}

class DiagnosticReport {
  const DiagnosticReport({
    required this.createdAt,
    required this.verdict,
    required this.checks,
  });

  final DateTime createdAt;
  final AuthVerdict verdict;
  final List<DiagnosticCheck> checks;

  static const verdictLabels = {
    AuthVerdict.authenticated: 'Sesja uwierzytelniona (potwierdzone)',
    AuthVerdict.inconclusive: 'Wynik niejednoznaczny',
    AuthVerdict.notAuthenticated: 'Sesja NIE jest uwierzytelniona',
  };

  static const _statusMarks = {
    CheckStatus.ok: '[OK]',
    CheckStatus.warning: '[UWAGA]',
    CheckStatus.failed: '[BŁĄD]',
  };

  /// Tekst do skopiowania i wklejenia do zgłoszenia.
  String toText() => [
    'Synergia Lite — diagnostyka integracji',
    'Czas: ${createdAt.toUtc().toIso8601String()}',
    'Werdykt: ${verdictLabels[verdict]}',
    for (final c in checks) ...[
      '',
      '${_statusMarks[c.status]} ${c.title}',
      for (final f in c.facts) '  - $f',
    ],
  ].join('\n');
}
