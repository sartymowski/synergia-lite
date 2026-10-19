import 'excuse.dart';

/// Natywne wysyłanie e-Usprawiedliwienia.
///
/// Kontrakt ŻĄDANIA ustalony 2026-10-19 z oficjalnej strony
/// `synergia.librus.pl/eusprawiedliwienia/dodaj` (struktura DOM i skrypt
/// `eusprawiedliwienia_rodzic.js`); ODPOWIEDŹ serwera nie została zaobserwowana
/// (wymagałaby prawdziwego wysłania). Dlatego przycisk jest domyślnie
/// nieaktywny: `--dart-define=SYNERGIA_NATIVE_EXCUSE_SUBMIT=true` włącza go
/// dopiero po świadomej decyzji (pierwszy test przez użytkownika).
abstract final class ExcuseSubmitPolicy {
  static const nativeSubmitEnabled = bool.fromEnvironment(
    'SYNERGIA_NATIVE_EXCUSE_SUBMIT',
  );

  /// Limit aplikacji (Librus go nie podaje; pole na stronie nie ma maxlength).
  static const maxReasonLength = 2000;
}

enum ExcuseMode {
  /// „Wybrane dni” — `datyLubLekcje=wgDat`, zakres `dataOd`–`dataDo`.
  days,

  /// „Kilka godzin w wybranym dniu” — `datyLubLekcje=wgGodzin`, jeden dzień,
  /// numery lekcji w `usprawiedliwienie[RRRR-MM-DD][]`.
  lessons,
}

class ExcuseSubmission {
  const ExcuseSubmission({
    required this.mode,
    required this.from,
    required this.to,
    this.lessonNumbers = const {},
    this.reason = '',
    this.notifyTeachers = false,
  });

  final ExcuseMode mode;
  final DateTime? from;

  /// W trybie lekcji ignorowane — wysyłane jest `dataDo = dataOd` (jak na stronie).
  final DateTime? to;
  final Set<int> lessonNumbers;
  final String reason;

  /// `powiadomInnych=1` — dostępne tylko dla nieobecności dziś lub w przyszłości.
  final bool notifyTeachers;

  DateTime? get effectiveTo => mode == ExcuseMode.lessons ? from : to;

  /// Planowana nieobecność: koniec zakresu nie wcześniej niż dziś
  /// (ta sama reguła, którą strona włącza opcję powiadomienia nauczycieli).
  bool isPlanned(DateTime today) {
    final end = effectiveTo;
    if (end == null) return false;
    return !_day(end).isBefore(_day(today));
  }

  ExcuseSubmission copyWith({
    ExcuseMode? mode,
    DateTime? from,
    DateTime? to,
    Set<int>? lessonNumbers,
    String? reason,
    bool? notifyTeachers,
  }) => ExcuseSubmission(
    mode: mode ?? this.mode,
    from: from ?? this.from,
    to: to ?? this.to,
    lessonNumbers: lessonNumbers ?? this.lessonNumbers,
    reason: reason ?? this.reason,
    notifyTeachers: notifyTeachers ?? this.notifyTeachers,
  );
}

enum ExcuseProblem {
  noDates,
  invalidRange,
  noLessons,
  noReason,
  reasonTooLong,
  notifyNotAllowed,
}

/// Walidacja: reguły ze skryptu strony (`wyslijUsprawiedliwienie`) + wymóg
/// uzasadnienia (reguła aplikacji — strona go nie wymusza).
List<ExcuseProblem> validateExcuse(
  ExcuseSubmission s, {
  required DateTime today,
}) {
  final from = s.from;
  final to = s.effectiveTo;
  return [
    if (from == null || to == null) ExcuseProblem.noDates,
    if (from != null && to != null && _day(from).isAfter(_day(to)))
      ExcuseProblem.invalidRange,
    if (s.mode == ExcuseMode.lessons && s.lessonNumbers.isEmpty)
      ExcuseProblem.noLessons,
    if (s.reason.trim().isEmpty) ExcuseProblem.noReason,
    if (s.reason.trim().length > ExcuseSubmitPolicy.maxReasonLength)
      ExcuseProblem.reasonTooLong,
    if (s.notifyTeachers && !s.isPlanned(today)) ExcuseProblem.notifyNotAllowed,
  ];
}

const excuseProblemMessages = {
  ExcuseProblem.noDates: 'Nie ustawiono zakresu dat.',
  ExcuseProblem.invalidRange: 'Niepoprawny zakres dat (początek po końcu).',
  ExcuseProblem.noLessons: 'Nie zaznaczono żadnej lekcji.',
  ExcuseProblem.noReason: 'Wpisz uzasadnienie.',
  ExcuseProblem.reasonTooLong: 'Uzasadnienie jest za długie.',
  ExcuseProblem.notifyNotAllowed:
      'Powiadomienie nauczycieli dotyczy tylko planowanych nieobecności.',
};

/// Wynik jednej (nigdy nie ponawianej) próby wysłania.
sealed class ExcuseSubmitOutcome {
  const ExcuseSubmitOutcome();
}

/// Przyjęcie potwierdzone odczytem historii (nowe zgłoszenie o tym zakresie).
final class ExcuseSubmitted extends ExcuseSubmitOutcome {
  const ExcuseSubmitted(this.created);

  final ExcuseRequest created;
}

/// Na pewno nie wysłano (np. zmieniony formularz, brak dostępu, odrzucona sesja).
final class ExcuseNotSent extends ExcuseSubmitOutcome {
  const ExcuseNotSent(this.reason);

  final String reason;
}

/// Nie wiadomo, czy zgłoszenie dotarło — sprawdź historię przed ponowieniem.
final class ExcuseUncertain extends ExcuseSubmitOutcome {
  const ExcuseUncertain(this.reason);

  final String reason;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

/// `RRRR-MM-DD` — format pól `dataOd`/`dataDo` i klucza lekcji.
String isoDay(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
