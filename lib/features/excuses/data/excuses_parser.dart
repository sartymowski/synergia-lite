import '../../../core/errors/synergia_exception.dart';
import '../../../shared/json_read.dart';
import '../domain/excuse.dart';

/// `Justifications` ma inną kopertę niż reszta gateway:
/// `{"status": "OK", "message": …, "data": [...]}` (librus-synergia, na żywo 10.2026).
abstract final class ExcusesParser {
  static List<ExcuseRequest> list(Map<String, dynamic> json) {
    final status = readString(json['status']);
    if (status != null && status.toUpperCase() != 'OK') {
      throw UnexpectedResponseException('Justifications: status=$status');
    }
    final data = json['data'];
    if (data is! List) {
      throw UnexpectedResponseException(
        'Justifications: brak listy data; klucze: ${(json.keys.toList()..sort()).join(', ')}',
      );
    }
    final items = [for (final item in data.whereType<Map>()) ?_item(item)];
    if (data.isNotEmpty && items.isEmpty) {
      throw UnexpectedResponseException(
        'Justifications: ${data.length} rekordów, żadnego nie odczytano',
      );
    }
    items.sort((a, b) {
      final pa = a.postedAt, pb = b.postedAt;
      if (pa == null || pb == null) return b.id.compareTo(a.id);
      return pb.compareTo(pa);
    });
    return items;
  }

  static ExcuseRequest? _item(Map item) {
    final id = readInt(item['id']);
    if (id == null) return null;
    final from = readDateTime(item['dateFrom']);
    final to = readDateTime(item['dateTo']) ?? from;
    return ExcuseRequest(
      id: id,
      status: ExcuseStatus.fromApi(readString(item['justificationStatus'])),
      reason: readString(item['messageFromParent']) ?? '',
      postedAt: readDateTime(item['postDate']),
      period: from == null || to == null
          ? null
          : ExcusePeriod(
              from: _day(from),
              to: _day(to.isBefore(from) ? from : to),
            ),
      lessons: [
        if (item['lessons'] case final List lessons)
          for (final l in lessons.whereType<Map>())
            if (readDateTime(l['date']) case final date?)
              ExcuseLesson(date: _day(date), number: readInt(l['number'])),
      ],
      justifiedAbsences: readInt(item['justifiedAbsences']) ?? 0,
      hasAttachment: readBool(item['attachment']),
      notifiedTeachers: [
        if (item['notifiedTeachers'] case final List teachers)
          for (final t in teachers.whereType<Map>()) ?readString(t['name']),
      ],
    );
  }

  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
}
