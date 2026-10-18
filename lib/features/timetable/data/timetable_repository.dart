import '../../../core/network/synergia_api_client.dart';
import '../domain/lesson.dart';
import 'timetable_parser.dart';

class TimetableRepository {
  TimetableRepository(this._api);

  final SynergiaApiClient _api;

  Future<TimetableWeek> fetchWeek(DateTime anyDay) async {
    final monday = mondayOf(anyDay);
    final weekStart =
        '${monday.year}-${_two(monday.month)}-${_two(monday.day)}';
    final json = await _api.get('Timetables', query: {'weekStart': weekStart});
    return TimetableParser.week(json, monday);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
