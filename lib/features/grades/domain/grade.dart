class Subject {
  const Subject({required this.id, required this.name, this.short});

  final int id;
  final String name;
  final String? short;
}

class Teacher {
  const Teacher({
    required this.id,
    required this.firstName,
    required this.lastName,
  });

  final int id;
  final String firstName;
  final String lastName;

  String get displayName => '$firstName $lastName'.trim();
}

class GradeCategory {
  const GradeCategory({
    required this.id,
    required this.name,
    required this.weight,
    required this.countsToAverage,
  });

  final int id;
  final String name;

  /// Brak wagi zdarza się w kategoriach nieliczonych do średniej.
  final int? weight;
  final bool countsToAverage;
}

enum GradeKind {
  regular,
  semesterProposal,
  semester,
  finalProposal,
  finalGrade;

  bool get isSummary => this != regular;
}

class Grade {
  const Grade({
    required this.id,
    required this.subjectId,
    required this.value,
    required this.semester,
    required this.kind,
    this.date,
    this.addedAt,
    this.categoryId,
    this.teacherId,
    this.isConstituent = true,
    this.improvementId,
  });

  final int id;
  final int subjectId;

  /// Ocena dokładnie tak, jak pokazuje ją Synergia: `5`, `4+`, `3-`, `np`, `+`.
  final String value;
  final int semester;
  final GradeKind kind;
  final DateTime? date;
  final DateTime? addedAt;
  final int? categoryId;
  final int? teacherId;
  final bool isConstituent;

  /// Referencja `Improvement` z API. Znaczenie (która ocena poprawia którą)
  /// nie zostało jeszcze potwierdzone na żywym koncie.
  final int? improvementId;
}

/// Wartość liczbowa w skali 1–6. Domyślnie `+` = +0,5, `-` = −0,25
/// (domyślne ustawienie Synergii; szkoła może je zmienić).
double? numericGradeValue(
  String value, {
  double plus = 0.5,
  double minus = 0.25,
}) {
  final match = RegExp(r'^([1-6])\s*([+-]?)$').firstMatch(value.trim());
  if (match == null) return null;
  final base = double.parse(match.group(1)!);
  return switch (match.group(2)) {
    '+' => base + plus,
    '-' => base - minus,
    _ => base,
  };
}

class AverageResult {
  const AverageResult({
    required this.value,
    required this.counted,
    required this.skipped,
  });

  /// `null`, gdy żadna ocena nie liczy się do średniej.
  final double? value;
  final int counted;

  /// Oceny pominięte: nieliczbowe, bez wagi, z kategorii nieliczonej itd.
  final int skipped;
}

/// Średnia ważona ocen cząstkowych. Liczona lokalnie i orientacyjnie —
/// może różnić się od średniej w Synergii, jeśli szkoła ma inne ustawienia.
AverageResult weightedAverage(
  Iterable<Grade> grades,
  Map<int, GradeCategory> categories,
) {
  var sum = 0.0;
  var weights = 0;
  var counted = 0;
  var skipped = 0;
  for (final grade in grades) {
    if (grade.kind.isSummary) continue;
    final numeric = numericGradeValue(grade.value);
    final category = categories[grade.categoryId];
    final weight = category?.weight;
    if (numeric == null ||
        !grade.isConstituent ||
        category == null ||
        !category.countsToAverage ||
        weight == null ||
        weight <= 0) {
      skipped++;
      continue;
    }
    sum += numeric * weight;
    weights += weight;
    counted++;
  }
  return AverageResult(
    value: weights == 0 ? null : sum / weights,
    counted: counted,
    skipped: skipped,
  );
}
