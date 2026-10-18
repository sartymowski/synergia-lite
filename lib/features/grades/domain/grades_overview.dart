import 'grade.dart';

class GradeEntry {
  const GradeEntry({required this.grade, this.category, this.teacher});

  final Grade grade;
  final GradeCategory? category;
  final Teacher? teacher;
}

class SubjectGrades {
  const SubjectGrades({
    required this.subject,
    required this.entries,
    required this.averageBySemester,
  });

  final Subject subject;

  /// Od najnowszej.
  final List<GradeEntry> entries;
  final Map<int, AverageResult> averageBySemester;

  Iterable<GradeEntry> forSemester(int semester) =>
      entries.where((e) => e.grade.semester == semester);
}

class GradesOverview {
  const GradesOverview({required this.subjects, required this.fetchedAt});

  factory GradesOverview.build({
    required List<Grade> grades,
    required Map<int, GradeCategory> categories,
    required Map<int, Subject> subjects,
    required Map<int, Teacher> teachers,
    required DateTime fetchedAt,
  }) {
    final bySubject = <int, List<Grade>>{};
    for (final g in grades) {
      (bySubject[g.subjectId] ??= []).add(g);
    }
    final result = [
      for (final MapEntry(key: subjectId, value: list) in bySubject.entries)
        SubjectGrades(
          subject:
              subjects[subjectId] ??
              Subject(id: subjectId, name: 'Przedmiot #$subjectId'),
          entries: [
            for (final g in list..sort(_newestFirst))
              GradeEntry(
                grade: g,
                category: categories[g.categoryId],
                teacher: teachers[g.teacherId],
              ),
          ],
          averageBySemester: {
            for (final semester in list.map((g) => g.semester).toSet())
              semester: weightedAverage(
                list.where((g) => g.semester == semester),
                categories,
              ),
          },
        ),
    ]..sort((a, b) => a.subject.name.compareTo(b.subject.name));
    return GradesOverview(subjects: result, fetchedAt: fetchedAt);
  }

  final List<SubjectGrades> subjects;
  final DateTime fetchedAt;

  int get gradeCount => subjects.fold(0, (n, s) => n + s.entries.length);

  /// Najnowsze oceny cząstkowe ze wszystkich przedmiotów (dla dashboardu).
  List<(Subject, GradeEntry)> recent(int count) {
    final all = [
      for (final s in subjects)
        for (final e in s.entries) (s.subject, e),
    ]..sort((a, b) => _newestFirst(a.$2.grade, b.$2.grade));
    return all.take(count).toList();
  }
}

int _newestFirst(Grade a, Grade b) {
  final da = a.addedAt ?? a.date;
  final db = b.addedAt ?? b.date;
  if (da == null || db == null) return b.id.compareTo(a.id);
  return db.compareTo(da);
}
