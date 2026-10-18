class Lesson {
  const Lesson({
    required this.date,
    required this.lessonNo,
    required this.subjectName,
    this.startTime,
    this.endTime,
    this.teacherName,
    this.classroom,
    this.isCanceled = false,
    this.isSubstitution = false,
    this.substitutionNote,
    this.originalSubjectName,
    this.originalTeacherName,
  });

  final DateTime date;
  final int lessonNo;
  final String subjectName;

  /// `HH:mm`, tak jak w Synergii.
  final String? startTime;
  final String? endTime;
  final String? teacherName;
  final String? classroom;
  final bool isCanceled;
  final bool isSubstitution;
  final String? substitutionNote;
  final String? originalSubjectName;
  final String? originalTeacherName;
}

class TimetableWeek {
  const TimetableWeek({required this.weekStart, required this.days});

  final DateTime weekStart;

  /// Klucz: dzień (północ, czas lokalny). Lekcje posortowane po numerze.
  final Map<DateTime, List<Lesson>> days;

  bool get isEmpty => days.values.every((l) => l.isEmpty);
}

/// Poniedziałek tygodnia zawierającego [day] — tego wymaga `weekStart`.
DateTime mondayOf(DateTime day) {
  final d = DateTime(day.year, day.month, day.day);
  return d.subtract(Duration(days: d.weekday - DateTime.monday));
}
