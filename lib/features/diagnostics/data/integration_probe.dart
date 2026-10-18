import '../../../core/errors/synergia_exception.dart';
import '../../../core/network/synergia_api_client.dart';
import '../../../core/network/web_cookie.dart';
import '../../../shared/json_read.dart';
import '../../auth/domain/account_info.dart';
import '../../grades/data/grades_parser.dart';
import '../../timetable/data/timetable_parser.dart';
import '../../timetable/domain/lesson.dart';
import '../domain/diagnostic_report.dart';

/// Sprawdza sesję i odczyt danych, raportując wyłącznie strukturę odpowiedzi.
/// Nigdy nie umieszcza w raporcie wartości ciasteczek ani treści danych.
class IntegrationProbe {
  IntegrationProbe(this._api, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final SynergiaApiClient _api;
  final DateTime Function() _clock;

  Future<DiagnosticReport> run({
    required List<WebCookie> webCookies,
    String? landingUrl,
  }) async {
    final checks = <DiagnosticCheck>[_cookies(webCookies, landingUrl)];

    final negative = await _negativeControl();
    checks.add(negative);
    final me = await _me();
    checks.add(me);
    checks.add(await _tokenInfo());

    final verdict = switch ((me.status, negative.status)) {
      (CheckStatus.ok, CheckStatus.ok) => AuthVerdict.authenticated,
      (CheckStatus.ok, _) => AuthVerdict.inconclusive,
      _ => AuthVerdict.notAuthenticated,
    };
    if (verdict != AuthVerdict.notAuthenticated) {
      checks.add(await _grades());
      checks.add(await _timetable());
    }
    return DiagnosticReport(
      createdAt: _clock(),
      verdict: verdict,
      checks: checks,
    );
  }

  DiagnosticCheck _cookies(List<WebCookie> cookies, String? landingUrl) {
    final hasMarker = cookies.any((c) => c.name == 'oauth_token');
    return DiagnosticCheck(
      'Ciasteczka WebView dla synergia.librus.pl',
      cookies.isEmpty
          ? CheckStatus.failed
          : (hasMarker ? CheckStatus.ok : CheckStatus.warning),
      [
        if (landingUrl != null) 'strona po zalogowaniu: $landingUrl',
        'liczba: ${cookies.length}',
        'oauth_token obecne: ${hasMarker ? 'tak' : 'nie'} '
            '(sama obecność nie dowodzi uwierzytelnienia)',
        for (final c in cookies) c.describe(),
      ],
    );
  }

  Future<DiagnosticCheck> _negativeControl() async {
    final status = await _api.statusWithoutSession('Me');
    return DiagnosticCheck(
      'Kontrola negatywna: Me bez ciasteczek',
      switch (status) {
        401 || 403 => CheckStatus.ok,
        200 => CheckStatus.failed,
        _ => CheckStatus.warning,
      },
      [
        'HTTP ${status ?? 'brak połączenia'} (oczekiwane 401)',
        if (status == 200)
          'endpoint odpowiada bez sesji — nie da się nim potwierdzić logowania',
      ],
    );
  }

  Future<DiagnosticCheck> _me() =>
      _guard('Uwierzytelnienie: Me z sesją', () async {
        final json = await _api.get('Me');
        final me = json['Me'];
        final account = AccountInfo.tryParse(json);
        return DiagnosticCheck(
          'Uwierzytelnienie: Me z sesją',
          account == null ? CheckStatus.failed : CheckStatus.ok,
          [
            'HTTP 200',
            'klucze odpowiedzi: ${_keys(json)}',
            if (me is Map<String, dynamic>) 'klucze Me: ${_keys(me)}',
            'obiekt konta: ${account == null ? 'BRAK' : 'obecny'}',
          ],
        );
      });

  Future<DiagnosticCheck> _tokenInfo() =>
      _guard('Auth/TokenInfo (informacyjnie)', () async {
        final json = await _api.get('Auth/TokenInfo');
        return DiagnosticCheck(
          'Auth/TokenInfo (informacyjnie)',
          CheckStatus.ok,
          ['HTTP 200', 'klucze: ${_keys(json)}'],
        );
      }, failure: CheckStatus.warning);

  Future<DiagnosticCheck> _grades() => _guard('Oceny: Grades', () async {
    final json = await _api.get('Grades');
    final raw = readList(json, 'Grades');
    final grades = GradesParser.grades(json);
    final categoryIds = grades.map((g) => g.categoryId).nonNulls.toSet();
    final subjectIds = grades.map((g) => g.subjectId).toSet();
    final categories = categoryIds.isEmpty
        ? const {}
        : GradesParser.categories(
            await _api.get('Grades/Categories', ids: categoryIds.take(50)),
          );
    final subjects = subjectIds.isEmpty
        ? const {}
        : GradesParser.subjects(
            await _api.get('Subjects', ids: subjectIds.take(50)),
          );
    final allParsed = grades.length == raw.length;
    return DiagnosticCheck(
      'Oceny: Grades',
      raw.isEmpty
          ? CheckStatus.warning
          : (allParsed ? CheckStatus.ok : CheckStatus.warning),
      [
        'rekordów: ${raw.length}, odczytanych: ${grades.length}',
        if (raw.isEmpty) '0 ocen — porównaj z widokiem Synergii',
        if (raw.isNotEmpty) 'pola pierwszego rekordu: ${_keys(raw.first)}',
        'rodzaje: ${_kindCounts(grades.map((g) => g.kind.name))}',
        'kategorie rozpoznane: ${categories.length}/${categoryIds.take(50).length}',
        'przedmioty rozpoznane: ${subjects.length}/${subjectIds.take(50).length}',
      ],
    );
  });

  Future<DiagnosticCheck> _timetable() => _guard(
    'Plan lekcji: Timetables',
    () async {
      final monday = mondayOf(_clock());
      final weekStart =
          '${monday.year}-${_two(monday.month)}-${_two(monday.day)}';
      final json = await _api.get(
        'Timetables',
        query: {'weekStart': weekStart},
      );
      final week = TimetableParser.week(json, monday);
      final lessons = week.days.values.expand((l) => l).toList();
      final firstEntry = _firstTimetableEntry(json);
      return DiagnosticCheck(
        'Plan lekcji: Timetables',
        lessons.isEmpty ? CheckStatus.warning : CheckStatus.ok,
        [
          'tydzień od $weekStart',
          'dni: ${week.days.length}, lekcji: ${lessons.length}',
          'odwołane: ${lessons.where((l) => l.isCanceled).length}, '
              'zastępstwa: ${lessons.where((l) => l.isSubstitution).length}',
          if (lessons.isEmpty) '0 lekcji — porównaj z widokiem Synergii',
          if (firstEntry != null) 'pola pierwszego wpisu: ${_keys(firstEntry)}',
        ],
      );
    },
  );

  Future<DiagnosticCheck> _guard(
    String title,
    Future<DiagnosticCheck> Function() body, {
    CheckStatus failure = CheckStatus.failed,
  }) async {
    try {
      return await body();
    } on SynergiaException catch (e) {
      return DiagnosticCheck(title, failure, [describeError(e)]);
    }
  }

  static String describeError(SynergiaException e) => switch (e) {
    SessionExpiredException() => 'odrzucone: HTTP 401/403 lub przekierowanie',
    ServerException(:final statusCode) => 'HTTP $statusCode',
    RateLimitedException(:final retryAfter) =>
      'limit zapytań (Retry-After: ${retryAfter?.inSeconds ?? '-'} s)',
    RequestTimeoutException() => 'przekroczony czas odpowiedzi',
    NetworkException() => 'brak połączenia',
    UnexpectedResponseException(:final detail) =>
      'nieoczekiwany format: $detail',
    LoginNotCompletedException() => 'logowanie niedokończone',
  };

  static String _keys(Map<String, dynamic> map) =>
      (map.keys.toList()..sort()).join(', ');

  static String _kindCounts(Iterable<String> kinds) {
    final counts = <String, int>{};
    for (final k in kinds) {
      counts[k] = (counts[k] ?? 0) + 1;
    }
    return counts.isEmpty
        ? '-'
        : counts.entries.map((e) => '${e.key}=${e.value}').join(', ');
  }

  static Map<String, dynamic>? _firstTimetableEntry(Map<String, dynamic> json) {
    final t = json['Timetable'];
    if (t is! Map) return null;
    for (final day in t.values) {
      if (day is! List) continue;
      for (final slot in day) {
        if (slot is List &&
            slot.isNotEmpty &&
            slot.first is Map<String, dynamic>) {
          return slot.first as Map<String, dynamic>;
        }
      }
    }
    return null;
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
