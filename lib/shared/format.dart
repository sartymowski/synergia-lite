String _two(int v) => v.toString().padLeft(2, '0');

const _weekdays = [
  'Poniedziałek',
  'Wtorek',
  'Środa',
  'Czwartek',
  'Piątek',
  'Sobota',
  'Niedziela',
];

String formatDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

String formatDateTime(DateTime d) =>
    '${formatDate(d)}, ${_two(d.hour)}:${_two(d.minute)}';

String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

/// Polski zapis z przecinkiem: `4,57`.
String formatAverage(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

/// Na liście: dziś „HH:mm”, wcześniej „dd.MM.yyyy”.
String formatListDate(DateTime d, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final sameDay = d.year == n.year && d.month == n.month && d.day == n.day;
  return sameDay ? '${_two(d.hour)}:${_two(d.minute)}' : formatDate(d);
}
