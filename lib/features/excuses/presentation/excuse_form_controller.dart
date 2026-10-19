import 'package:flutter/foundation.dart';

import '../../timetable/domain/lesson.dart';
import '../domain/excuse.dart';
import '../domain/excuse_submission.dart';

enum ExcuseFormStatus { editing, sending, submitted, notSent, uncertain }

/// Lekcja do wyboru: numer (wartość pola formularza Librusa) + przedmiot z planu.
typedef LessonChoice = ({int number, String subjects, bool canceled});

/// Lekcje z planu danego dnia, po jednej pozycji na numer (grupy łączone).
List<LessonChoice> lessonsOn(TimetableWeek week, DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  final byNumber = <int, List<Lesson>>{};
  for (final l in week.days[d] ?? const <Lesson>[]) {
    (byNumber[l.lessonNo] ??= []).add(l);
  }
  return [
    for (final n in byNumber.keys.toList()..sort())
      (
        number: n,
        subjects: byNumber[n]!.map((l) => l.subjectName).toSet().join(' / '),
        canceled: byNumber[n]!.every((l) => l.isCanceled),
      ),
  ];
}

/// Stan formularza nowego e-Usprawiedliwienia.
/// Wysyłka: tylko z [send], jedna naraz, bez ponowień; po wyniku niejednoznacznym
/// kolejna próba wymaga potwierdzenia. Przy wyłączonej polityce nic nie wysyła.
class ExcuseFormController extends ChangeNotifier {
  ExcuseFormController({
    required this._submit,
    this.submitEnabled = ExcuseSubmitPolicy.nativeSubmitEnabled,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<ExcuseSubmitOutcome> Function(ExcuseSubmission) _submit;
  final DateTime Function() _clock;
  final bool submitEnabled;

  ExcuseSubmission _s = const ExcuseSubmission(
    mode: ExcuseMode.days,
    from: null,
    to: null,
  );
  ExcuseFormStatus _status = ExcuseFormStatus.editing;
  String? _message;
  ExcuseRequest? _created;
  bool _showProblems = false;
  bool _hadUncertain = false;
  bool _disposed = false;

  ExcuseSubmission get submission => _s;
  ExcuseFormStatus get status => _status;
  String? get message => _message;
  ExcuseRequest? get created => _created;
  bool get isSending => _status == ExcuseFormStatus.sending;
  bool get canEdit =>
      _status != ExcuseFormStatus.sending &&
      _status != ExcuseFormStatus.submitted;
  bool get needsConfirmationAfterUncertain => _hadUncertain;

  /// Opcja „powiadom nauczycieli” — tylko dla planowanej nieobecności.
  bool get canNotifyTeachers => _s.isPlanned(_clock());

  List<ExcuseProblem> get problems =>
      _showProblems ? validateExcuse(_s, today: _clock()) : const [];

  void setMode(ExcuseMode mode) =>
      _update(_s.copyWith(mode: mode, lessonNumbers: {}));

  void setRange(DateTime from, DateTime to) =>
      _update(_s.copyWith(from: from, to: to, lessonNumbers: {}));

  void setDay(DateTime day) =>
      _update(_s.copyWith(from: day, to: day, lessonNumbers: {}));

  void toggleLesson(int number) {
    final next = {..._s.lessonNumbers};
    if (!next.remove(number)) next.add(number);
    _update(_s.copyWith(lessonNumbers: next));
  }

  void setReason(String reason) => _update(_s.copyWith(reason: reason));

  void setNotifyTeachers(bool value) =>
      _update(_s.copyWith(notifyTeachers: value && canNotifyTeachers));

  void _update(ExcuseSubmission next) {
    if (!canEdit) return;
    // Zmiana dat może wyłączyć możliwość powiadomienia nauczycieli.
    _s = next.notifyTeachers && !next.isPlanned(_clock())
        ? next.copyWith(notifyTeachers: false)
        : next;
    if (_status == ExcuseFormStatus.notSent) {
      _status = ExcuseFormStatus.editing;
      _message = null;
    }
    _notify();
  }

  /// Sprawdza formularz (np. przed podsumowaniem). Zwraca, czy jest poprawny.
  bool validate() {
    _showProblems = true;
    _notify();
    return validateExcuse(_s, today: _clock()).isEmpty;
  }

  /// `null` = nic nie wysłano (wyłączone, trwa wysyłka, błędy, brak potwierdzenia).
  Future<ExcuseSubmitOutcome?> send({
    bool confirmedAfterUncertain = false,
  }) async {
    if (!submitEnabled) return null;
    if (_status == ExcuseFormStatus.sending ||
        _status == ExcuseFormStatus.submitted) {
      return null;
    }
    if (!validate()) return null;
    if (_hadUncertain && !confirmedAfterUncertain) return null;

    _status = ExcuseFormStatus.sending;
    _message = null;
    _notify();
    ExcuseSubmitOutcome outcome;
    try {
      outcome = await _submit(_s);
    } catch (_) {
      outcome = const ExcuseUncertain(
        'Nieoczekiwany błąd aplikacji. Sprawdź historię przed ponowną próbą.',
      );
    }
    switch (outcome) {
      case ExcuseSubmitted(:final created):
        _status = ExcuseFormStatus.submitted;
        _created = created;
        _message =
            'Zgłoszenie przyjęte — widoczne w historii ze statusem „${created.status.label}”.';
      case ExcuseNotSent(:final reason):
        _status = ExcuseFormStatus.notSent;
        _message = reason;
      case ExcuseUncertain(:final reason):
        _status = ExcuseFormStatus.uncertain;
        _hadUncertain = true;
        _message = reason;
    }
    _notify();
    return outcome;
  }

  /// Użytkownik sprawdził historię i chce poprawić/ponowić.
  void acknowledgeUncertain() {
    if (_status == ExcuseFormStatus.uncertain) {
      _status = ExcuseFormStatus.editing;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
