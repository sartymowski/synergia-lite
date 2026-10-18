import '../../../core/errors/synergia_exception.dart';
import '../../../shared/json_read.dart';
import '../domain/grade.dart';

/// Odwzorowanie odpowiedzi `gateway/api/2.0` na modele domeny.
/// Rekordy bez wymaganych pól są pomijane, a nie zgadywane.
abstract final class GradesParser {
  static List<Grade> grades(Map<String, dynamic> json) => [
    for (final g in readList(json, 'Grades')) ?_grade(g),
  ];

  static Grade? _grade(Map<String, dynamic> g) {
    final id = readInt(g['Id']);
    final subjectId = readRefId(g['Subject']);
    final value = readString(g['Grade']);
    if (id == null || subjectId == null || value == null) return null;
    return Grade(
      id: id,
      subjectId: subjectId,
      value: value,
      semester: readInt(g['Semester']) ?? 1,
      kind: _kind(g),
      date: readDateTime(g['Date']),
      addedAt: readDateTime(g['AddDate']),
      categoryId: readRefId(g['Category']),
      teacherId: readRefId(g['AddedBy']),
      isConstituent: g.containsKey('IsConstituent')
          ? readBool(g['IsConstituent'])
          : true,
      improvementId: readRefId(g['Improvement']),
    );
  }

  static GradeKind _kind(Map<String, dynamic> g) {
    if (readBool(g['IsFinal'])) return GradeKind.finalGrade;
    if (readBool(g['IsFinalProposition'])) return GradeKind.finalProposal;
    if (readBool(g['IsSemester'])) return GradeKind.semester;
    if (readBool(g['IsSemesterProposition'])) return GradeKind.semesterProposal;
    return GradeKind.regular;
  }

  static Map<int, GradeCategory> categories(Map<String, dynamic> json) => {
    for (final c in readList(json, 'Categories').map(_category).nonNulls)
      c.id: c,
  };

  static GradeCategory? _category(Map<String, dynamic> c) {
    final id = readInt(c['Id']);
    if (id == null) return null;
    final weight = readInt(c['Weight']);
    return GradeCategory(
      id: id,
      name: readString(c['Name']) ?? 'Bez kategorii',
      weight: weight,
      countsToAverage: c.containsKey('CountToTheAverage')
          ? readBool(c['CountToTheAverage'])
          : weight != null,
    );
  }

  static Map<int, Subject> subjects(Map<String, dynamic> json) => {
    for (final s in readList(json, 'Subjects').map(_subject).nonNulls) s.id: s,
  };

  static Subject? _subject(Map<String, dynamic> s) {
    final id = readInt(s['Id']);
    final name = readString(s['Name']);
    if (id == null || name == null) return null;
    return Subject(id: id, name: name, short: readString(s['Short']));
  }

  static Map<int, Teacher> teachers(Map<String, dynamic> json) => {
    for (final t in readList(json, 'Users').map(_teacher).nonNulls) t.id: t,
  };

  static Teacher? _teacher(Map<String, dynamic> u) {
    final id = readInt(u['Id']);
    if (id == null) return null;
    return Teacher(
      id: id,
      firstName: readString(u['FirstName']) ?? '',
      lastName: readString(u['LastName']) ?? '',
    );
  }

  /// Kontrola spójności — wykrywa zmianę formatu zamiast cicho pokazywać pustkę.
  static void ensureAllParsed(Map<String, dynamic> json, List<Grade> parsed) {
    final raw = readList(json, 'Grades').length;
    if (raw > 0 && parsed.isEmpty) {
      throw UnexpectedResponseException(
        'Grades: $raw rekordów, żadnego nie udało się odczytać',
      );
    }
  }
}
