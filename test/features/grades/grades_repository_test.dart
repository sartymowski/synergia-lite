import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/grades/data/grades_repository.dart';

import '../../helpers/fake_http.dart';

void main() {
  SynergiaApiClient api(FakeAdapter adapter) => SynergiaApiClient(
    sessionStore: InMemorySessionStore(SessionCookies({'DZIENNIKSID': 'x'})),
    dio: fakeDio(adapter),
    minInterval: Duration.zero,
  );

  test('łączy oceny ze słownikami pobranymi selektorami', () async {
    final adapter = FakeAdapter((o) {
      final path = o.path;
      if (path == 'Grades') return jsonBody(fixture('grades.json'));
      if (path.startsWith('Grades/Categories/')) {
        return jsonBody(fixture('grade_categories.json'));
      }
      if (path.startsWith('Subjects/')) {
        return jsonBody({
          'Subjects': [
            {'Id': 11, 'Name': 'Matematyka'},
            {'Id': 12, 'Name': 'Biologia'},
          ],
        });
      }
      if (path.startsWith('Users/')) {
        return jsonBody({
          'Users': [
            {'Id': 31, 'FirstName': 'Ewa', 'LastName': 'Przykładowa'},
          ],
        });
      }
      return jsonBody({}, status: 404);
    });

    final overview = await GradesRepository(api(adapter)).fetchOverview();

    expect(adapter.requests.map((r) => r.path), [
      'Grades',
      'Grades/Categories/21,22,23,24',
      'Subjects/11,12',
      'Users/31,32',
    ]);
    expect(overview.subjects.map((s) => s.subject.name), [
      'Biologia',
      'Matematyka',
    ]);
    expect(overview.gradeCount, 5);

    final math = overview.subjects.last;
    // Najnowsza pierwsza: np (2.10), 3- (1.10), 5 (15.09).
    expect(math.entries.map((e) => e.grade.value), ['np', '3-', '5']);
    expect(math.entries.last.teacher?.displayName, 'Ewa Przykładowa');
    // (5·3 + 2,75·2) / 5; „np” pominięte.
    expect(math.averageBySemester[1]!.value, closeTo(4.1, 1e-9));
    expect(math.averageBySemester[1]!.skipped, 1);

    final bio = overview.subjects.first;
    expect(bio.entries.first.teacher, isNull, reason: 'brak w słowniku Users');
    expect(bio.averageBySemester[1]!.value, 4.5);

    expect(overview.recent(2).map((r) => r.$2.grade.id), [1005, 1004]);
  });

  test('dzieli długie listy identyfikatorów na porcje', () async {
    final grades = [
      for (var i = 1; i <= 60; i++)
        {
          'Id': i,
          'Subject': {'Id': 1},
          'Category': {'Id': 1},
          'AddedBy': {'Id': i},
          'Grade': '5',
        },
    ];
    final adapter = FakeAdapter((o) {
      if (o.path == 'Grades') return jsonBody({'Grades': grades});
      if (o.path.startsWith('Users/')) return jsonBody({'Users': []});
      if (o.path.startsWith('Subjects/')) return jsonBody({'Subjects': []});
      return jsonBody({'Categories': []});
    });
    await GradesRepository(api(adapter)).fetchOverview();
    final users = adapter.requests
        .where((r) => r.path.startsWith('Users/'))
        .toList();
    expect(users, hasLength(2));
    expect(users.first.path.split('/').last.split(','), hasLength(50));
  });

  test('brak ocen nie wysyła zapytań o słowniki', () async {
    final adapter = FakeAdapter((_) => jsonBody({'Grades': []}));
    final overview = await GradesRepository(api(adapter)).fetchOverview();
    expect(overview.subjects, isEmpty);
    expect(adapter.requests, hasLength(1));
  });

  test('wygaśnięcie sesji w trakcie przerywa pobieranie', () async {
    final adapter = FakeAdapter(
      (o) => o.path == 'Grades'
          ? jsonBody(fixture('grades.json'))
          : jsonBody({}, status: 401),
    );
    await expectLater(
      GradesRepository(api(adapter)).fetchOverview(),
      throwsA(isA<SessionExpiredException>()),
    );
  });
}
