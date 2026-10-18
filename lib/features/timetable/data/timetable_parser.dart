import '../../../core/errors/synergia_exception.dart';
import '../../../shared/json_read.dart';
import '../domain/lesson.dart';

/// `Timetables?weekStart=YYYY-MM-DD` zwraca
/// `{"Timetable": {"2025-10-06": [[lekcja, …], [], …], …}}` — każdy dzień
/// to lista slotów, a slot to lista wpisów (np. kilka grup naraz).
abstract final class TimetableParser {
  static TimetableWeek week(Map<String, dynamic> json, DateTime weekStart) {
    final raw = json['Timetable'];
    // PHP koduje pustą tablicę asocjacyjną jako `[]`.
    final timetable = (raw is List && raw.isEmpty) ? <String, dynamic>{} : raw;
    if (timetable is! Map) {
      throw UnexpectedResponseException(
        'Timetables: brak obiektu "Timetable"; klucze: ${json.keys.join(', ')}',
      );
    }
    final days = <DateTime, List<Lesson>>{};
    for (final MapEntry(key: dayKey, value: slots) in timetable.entries) {
      final date = readDateTime(dayKey);
      if (date == null || slots is! List) continue;
      final lessons = <Lesson>[];
      for (final (index, slot) in slots.indexed) {
        if (slot is! List) continue;
        for (final entry in slot.whereType<Map<String, dynamic>>()) {
          final lesson = _lesson(entry, date, index);
          if (lesson != null) lessons.add(lesson);
        }
      }
      lessons.sort((a, b) => a.lessonNo.compareTo(b.lessonNo));
      days[date] = lessons;
    }
    return TimetableWeek(weekStart: weekStart, days: days);
  }

  static Lesson? _lesson(Map<String, dynamic> e, DateTime date, int index) {
    final subject = _name(e['Subject']);
    if (subject == null) return null;
    final isSubstitution = readBool(e['IsSubstitutionClass']);
    return Lesson(
      date: date,
      lessonNo: readInt(e['LessonNo']) ?? index,
      subjectName: subject,
      startTime: readString(e['HourFrom']),
      endTime: readString(e['HourTo']),
      teacherName: _person(e['Teacher']),
      classroom: _classroom(e['Classroom']),
      isCanceled: readBool(e['IsCanceled']),
      isSubstitution: isSubstitution,
      substitutionNote: readString(e['SubstitutionNote']),
      originalSubjectName: isSubstitution ? _name(e['OrgSubject']) : null,
      originalTeacherName: isSubstitution ? _person(e['OrgTeacher']) : null,
    );
  }

  static String? _name(Object? ref) =>
      ref is Map<String, dynamic> ? readString(ref['Name']) : null;

  static String? _person(Object? ref) {
    if (ref is! Map<String, dynamic>) return null;
    final name = [
      readString(ref['FirstName']),
      readString(ref['LastName']),
    ].whereType<String>().join(' ');
    return name.isEmpty ? null : name;
  }

  static String? _classroom(Object? ref) {
    if (ref is! Map<String, dynamic>) return null;
    return readString(ref['Symbol']) ?? readString(ref['Name']);
  }
}
