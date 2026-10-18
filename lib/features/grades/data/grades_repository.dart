import '../../../core/network/synergia_api_client.dart';
import '../domain/grades_overview.dart';
import 'grades_parser.dart';

class GradesRepository {
  GradesRepository(this._api);

  final SynergiaApiClient _api;

  static const _chunk = 50;

  /// Pobiera oceny i tylko te słowniki, które są potrzebne do ich opisania.
  Future<GradesOverview> fetchOverview() async {
    final gradesJson = await _api.get('Grades');
    final grades = GradesParser.grades(gradesJson);
    GradesParser.ensureAllParsed(gradesJson, grades);

    final categories = await _byIds(
      'Grades/Categories',
      grades.map((g) => g.categoryId),
      GradesParser.categories,
    );
    final subjects = await _byIds(
      'Subjects',
      grades.map((g) => g.subjectId),
      GradesParser.subjects,
    );
    final teachers = await _byIds(
      'Users',
      grades.map((g) => g.teacherId),
      GradesParser.teachers,
    );

    return GradesOverview.build(
      grades: grades,
      categories: categories,
      subjects: subjects,
      teachers: teachers,
      fetchedAt: DateTime.now(),
    );
  }

  Future<Map<int, T>> _byIds<T>(
    String path,
    Iterable<int?> ids,
    Map<int, T> Function(Map<String, dynamic>) parse,
  ) async {
    final unique = ids.whereType<int>().toSet().toList()..sort();
    final result = <int, T>{};
    for (var i = 0; i < unique.length; i += _chunk) {
      final part = unique.sublist(i, (i + _chunk).clamp(0, unique.length));
      result.addAll(parse(await _api.get(path, ids: part)));
    }
    return result;
  }
}
