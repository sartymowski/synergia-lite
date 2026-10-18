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
