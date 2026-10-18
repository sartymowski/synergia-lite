import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/core/errors/synergia_exception.dart';
import 'package:synergia_lite/core/network/session_cookies.dart';
import 'package:synergia_lite/core/network/synergia_api_client.dart';
import 'package:synergia_lite/core/security/session_store.dart';
import 'package:synergia_lite/features/timetable/data/timetable_parser.dart';
import 'package:synergia_lite/features/timetable/data/timetable_repository.dart';
import 'package:synergia_lite/features/timetable/domain/lesson.dart';

import '../../helpers/fake_http.dart';

void main() {
  final monday = DateTime(2026, 10, 12);
  final week = TimetableParser.week(fixture('timetable_week.json'), monday);

  test('czyta zwykłą lekcję', () {
    final l = week.days[DateTime(2026, 10, 12)]!.first;
    expect(l.lessonNo, 1);
    expect(l.subjectName, 'Matematyka');
    expect(l.teacherName, 'Ewa Przykładowa');
    expect(l.classroom, '12');
    expect((l.startTime, l.endTime), ('08:00', '08:45'));
    expect(l.isCanceled || l.isSubstitution, isFalse);
  });

  test('kilka grup w jednym slocie to osobne lekcje', () {
    final monday = week.days[DateTime(2026, 10, 12)]!;
    expect(monday.where((l) => l.lessonNo == 2).map((l) => l.subjectName), [
      'Język angielski',
      'Język niemiecki',
    ]);
  });

  test('odwołana lekcja', () {
    final l = week.days[DateTime(2026, 10, 13)]!.firstWhere(
      (l) => l.lessonNo == 1,
    );
    expect(l.isCanceled, isTrue);
    expect(l.isSubstitution, isFalse);
  });

  test('zastępstwo z oryginalnym przedmiotem i nauczycielem', () {
    final l = week.days[DateTime(2026, 10, 13)]!.firstWhere(
      (l) => l.lessonNo == 2,
    );
    expect(l.isSubstitution, isTrue);
    expect(l.subjectName, 'Chemia');
    expect(l.originalSubjectName, 'Fizyka');
    expect(l.originalTeacherName, 'Adam Wzorcowy');
    expect(l.substitutionNote, 'Zmiana sali');
  });

  test('wpis bez przedmiotu jest pomijany', () {
    expect(week.days[DateTime(2026, 10, 13)]!.map((l) => l.lessonNo), [1, 2]);
  });

  test('puste dni', () {
    expect(week.days[DateTime(2026, 10, 14)], isEmpty);
    expect(week.days[DateTime(2026, 10, 18)], isEmpty);
    expect(week.isEmpty, isFalse);
    expect(TimetableParser.week({'Timetable': {}}, monday).isEmpty, isTrue);
  });

  test('pusty tydzień zakodowany przez PHP jako []', () {
    expect(TimetableParser.week({'Timetable': []}, monday).isEmpty, isTrue);
  });

  test('brak obiektu Timetable to zmiana formatu', () {
    expect(
      () => TimetableParser.week({'Timetable': 'x'}, monday),
      throwsA(isA<UnexpectedResponseException>()),
    );
    expect(
      () => TimetableParser.week({'Other': {}}, monday),
      throwsA(isA<UnexpectedResponseException>()),
    );
  });

  test('mondayOf', () {
    expect(mondayOf(DateTime(2026, 10, 18, 15)), DateTime(2026, 10, 12));
    expect(mondayOf(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
    expect(mondayOf(DateTime(2026, 11, 1)), DateTime(2026, 10, 26));
  });

  test('repozytorium wysyła weekStart jako poniedziałek', () async {
    final adapter = FakeAdapter((_) => jsonBody({'Timetable': {}}));
    final api = SynergiaApiClient(
      sessionStore: InMemorySessionStore(SessionCookies({'a': 'b'})),
      dio: fakeDio(adapter),
      minInterval: Duration.zero,
    );
    final w = await TimetableRepository(api).fetchWeek(DateTime(2026, 3, 5));
    expect(adapter.requests.single.queryParameters, {
      'weekStart': '2026-03-02',
    });
    expect(w.weekStart, DateTime(2026, 3, 2));
  });
}
