import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/features/grades/data/grades_parser.dart';
import 'package:synergia_lite/features/grades/domain/grade.dart';

import '../../helpers/fake_http.dart';

void main() {
  group('GradesParser.grades', () {
    final grades = GradesParser.grades(fixture('grades.json'));

    test('pomija rekord bez przedmiotu zamiast zgadywać', () {
      expect(grades.map((g) => g.id), [1001, 1002, 1003, 1004, 1005]);
    });

    test('czyta identyfikatory podane jako tekst', () {
      final g = grades.firstWhere((g) => g.id == 1002);
      expect(g.subjectId, 11);
      expect(g.categoryId, 22);
      expect(g.teacherId, 31);
      expect(g.semester, 1);
      expect(g.isConstituent, isTrue);
      expect(g.value, '3-');
    });

    test('czyta daty i rodzaj oceny', () {
      final first = grades.first;
      expect(first.date, DateTime(2026, 9, 15));
      expect(first.addedAt, DateTime(2026, 9, 15, 10, 12));
      expect(first.kind, GradeKind.regular);
      final proposal = grades.firstWhere((g) => g.id == 1005);
      expect(proposal.kind, GradeKind.semesterProposal);
      expect(proposal.isConstituent, isFalse);
    });

    test('pusta lista ocen jest poprawną odpowiedzią', () {
      expect(GradesParser.grades({'Grades': []}), isEmpty);
    });

    test('brak klucza Grades to zmiana formatu', () {
      expect(
        () => GradesParser.grades({'Url': 'x', 'Other': []}),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });

    test('ensureAllParsed wykrywa rekordy w nieznanym formacie', () {
      final json = {
        'Grades': [
          {'Id': 1, 'Ocena': '5'},
        ],
      };
      expect(
        () => GradesParser.ensureAllParsed(json, GradesParser.grades(json)),
        throwsA(isA<UnexpectedResponseException>()),
      );
    });
  });

  group('słowniki', () {
    test('kategorie: waga jako tekst i brak wagi', () {
      final c = GradesParser.categories(fixture('grade_categories.json'));
      expect(c[21]!.weight, 3);
      expect(c[22]!.weight, 2);
      expect(c[23]!.weight, isNull);
      expect(c[23]!.countsToAverage, isFalse);
      expect(c[24]!.countsToAverage, isFalse);
    });

    test('pojedynczy obiekt zamiast listy (jeden selektor)', () {
      final c = GradesParser.categories({
        'Category': {
          'Id': 5,
          'Name': 'Test',
          'Weight': 1,
          'CountToTheAverage': true,
        },
        'Url': 'x',
      });
      expect(c.keys, [5]);
    });

    test('przedmioty i nauczyciele', () {
      final s = GradesParser.subjects({
        'Subjects': [
          {'Id': 11, 'Name': 'Matematyka', 'Short': 'mat'},
          {'Id': 12},
        ],
      });
      expect(s.keys, [11]);
      final t = GradesParser.teachers({
        'Users': [
          {'Id': '31', 'FirstName': 'Ewa', 'LastName': 'Przykładowa'},
        ],
      });
      expect(t[31]!.displayName, 'Ewa Przykładowa');
    });
  });

  group('numericGradeValue', () {
    final cases = {
      '1': 1.0,
      '5': 5.0,
      '6': 6.0,
      '4+': 4.5,
      '3-': 2.75,
      ' 2+ ': 2.5,
      'np': null,
      'bz': null,
      '+': null,
      '-': null,
      '0': null,
      '7': null,
      '5/4': null,
      '': null,
    };
    cases.forEach((input, expected) {
      test(
        '"$input" → $expected',
        () => expect(numericGradeValue(input), expected),
      );
    });
  });

  group('weightedAverage', () {
    const categories = {
      1: GradeCategory(
        id: 1,
        name: 'Sprawdzian',
        weight: 3,
        countsToAverage: true,
      ),
      2: GradeCategory(
        id: 2,
        name: 'Kartkówka',
        weight: 1,
        countsToAverage: true,
      ),
      3: GradeCategory(
        id: 3,
        name: 'Aktywność',
        weight: 2,
        countsToAverage: false,
      ),
      4: GradeCategory(
        id: 4,
        name: 'Bez wagi',
        weight: null,
        countsToAverage: true,
      ),
    };
    Grade g(
      String v,
      int cat, {
      GradeKind kind = GradeKind.regular,
      bool constituent = true,
    }) => Grade(
      id: 0,
      subjectId: 1,
      value: v,
      semester: 1,
      kind: kind,
      categoryId: cat,
      isConstituent: constituent,
    );

    test('liczy średnią ważoną', () {
      final r = weightedAverage([g('5', 1), g('2', 2)], categories);
      expect(r.value, closeTo((5 * 3 + 2) / 4, 1e-9));
      expect(r.counted, 2);
      expect(r.skipped, 0);
    });

    test('pomija oceny nieliczbowe, nieliczone, bez wagi i nie-cząstkowe', () {
      final r = weightedAverage([
        g('4', 2),
        g('np', 1),
        g('6', 3),
        g('6', 4),
        g('6', 99),
        g('1', 2, constituent: false),
      ], categories);
      expect(r.value, 4);
      expect(r.counted, 1);
      expect(r.skipped, 5);
    });

    test('ignoruje oceny śródroczne i roczne', () {
      final r = weightedAverage([
        g('3', 1),
        g('6', 1, kind: GradeKind.semester),
        g('6', 1, kind: GradeKind.finalProposal),
      ], categories);
      expect(r.value, 3);
      expect(r.skipped, 0);
    });

    test('brak ocen do średniej daje null', () {
      expect(weightedAverage([], categories).value, isNull);
      expect(weightedAverage([g('np', 1)], categories).value, isNull);
    });
  });
}
