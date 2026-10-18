import '../core/errors/synergia_exception.dart';

/// Tolerancyjny odczyt pól z API Synergii. Identyfikatory przychodzą
/// raz jako liczby, raz jako tekst, a referencje mają postać `{"Id": …}`.

/// Lista obiektów spod [key]. Jeśli serwer zwrócił pojedynczy obiekt
/// (np. dla jednego selektora), opakowuje go w listę.
List<Map<String, dynamic>> readList(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value is List) return value.whereType<Map<String, dynamic>>().toList();
  if (value is Map<String, dynamic>) return [value];
  final single = json.entries
      .where((e) => e.key != 'Resources' && e.key != 'Url')
      .map((e) => e.value)
      .whereType<Map<String, dynamic>>()
      .where((m) => m.containsKey('Id'))
      .toList();
  if (single.length == 1) return single;
  throw UnexpectedResponseException(
    'brak klucza "$key"; klucze: ${json.keys.join(', ')}',
  );
}

int? readInt(Object? value) => switch (value) {
  int v => v,
  num v => v.toInt(),
  String v => int.tryParse(v.trim()),
  _ => null,
};

/// Identyfikator z referencji `{"Id": 5, "Url": …}` albo z wartości wprost.
int? readRefId(Object? ref) =>
    ref is Map<String, dynamic> ? readInt(ref['Id']) : readInt(ref);

String? readString(Object? value) {
  if (value == null) return null;
  final s = '$value'.trim();
  return s.isEmpty ? null : s;
}

bool readBool(Object? value) => switch (value) {
  bool v => v,
  num v => v != 0,
  String v => v == '1' || v.toLowerCase() == 'true',
  _ => false,
};

/// `2025-10-01` albo `2025-10-01 12:34:56` (czas lokalny szkoły).
DateTime? readDateTime(Object? value) {
  final s = readString(value);
  if (s == null) return null;
  return DateTime.tryParse(s.replaceFirst(' ', 'T'));
}
