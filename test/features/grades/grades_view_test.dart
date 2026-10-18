import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/app/providers.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/features/grades/domain/grade.dart';
import 'package:synergia_lite/features/grades/domain/grades_overview.dart';
import 'package:synergia_lite/features/grades/presentation/grades_view.dart';

Widget _app(Future<GradesOverview> Function() load) => ProviderScope(
  retry: (_, _) => null,
  overrides: [gradesOverviewProvider.overrideWith((ref) => load())],
  child: const MaterialApp(home: Scaffold(body: GradesView())),
);

void main() {
  testWidgets('pokazuje przedmiot, średnią i datę pobrania', (tester) async {
    final overview = GradesOverview.build(
      grades: const [
        Grade(
          id: 1,
          subjectId: 1,
          value: '5',
          semester: 1,
          kind: GradeKind.regular,
          categoryId: 1,
        ),
        Grade(
          id: 2,
          subjectId: 1,
          value: '4',
          semester: 1,
          kind: GradeKind.regular,
          categoryId: 1,
        ),
      ],
      categories: const {
        1: GradeCategory(
          id: 1,
          name: 'Sprawdzian',
          weight: 1,
          countsToAverage: true,
        ),
      },
      subjects: const {1: Subject(id: 1, name: 'Matematyka')},
      teachers: const {},
      fetchedAt: DateTime(2026, 10, 18, 9, 5),
    );
    await tester.pumpWidget(_app(() async => overview));
    await tester.pumpAndSettle();

    expect(find.text('Pobrano: 18.10.2026, 09:05'), findsOneWidget);
    expect(find.text('Matematyka'), findsOneWidget);
    expect(find.text('Śr. orientacyjna sem. 1: 4,50'), findsOneWidget);
  });

  testWidgets('pusta odpowiedź nie udaje sukcesu', (tester) async {
    await tester.pumpWidget(
      _app(
        () async =>
            GradesOverview(subjects: const [], fetchedAt: DateTime(2026)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('nie zwróciła żadnych ocen'), findsOneWidget);
  });

  testWidgets('błąd pokazuje komunikat i przycisk ponowienia', (tester) async {
    await tester.pumpWidget(_app(() async => throw const NetworkException()));
    await tester.pumpAndSettle();
    expect(find.text(const NetworkException().message), findsOneWidget);
    expect(find.text('Spróbuj ponownie'), findsOneWidget);
  });
}
