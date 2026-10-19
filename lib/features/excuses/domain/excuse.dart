/// Modele e-Usprawiedliwień. Nie znają nazw pól API — mapowanie z odpowiedzi
/// `gateway/api/2.0/Justifications` jest w `data/excuses_parser.dart`.
library;

/// Status zgłoszenia. Potwierdzone (2026-10-19, porównanie z oficjalnym filtrem
/// „Status” przez użytkownika): `accept` = „usprawiedliwione”, `send` = „wysłane”.
/// Wartość API dla „odrzucone” nie jest znana — inne wartości są zachowywane
/// dosłownie, bez zgadywania znaczenia.
sealed class ExcuseStatus {
  const ExcuseStatus();

  factory ExcuseStatus.fromApi(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.toLowerCase() == 'accept') return const ExcuseAccepted();
    if (value.toLowerCase() == 'send') return const ExcuseSent();
    if (value.isEmpty) return const ExcuseStatusMissing();
    return ExcuseStatusOther(value);
  }

  String get label;

  /// Klucz do filtrowania (stabilny dla tej samej wartości z API).
  String get key;
}

final class ExcuseAccepted extends ExcuseStatus {
  const ExcuseAccepted();

  @override
  String get label => 'Usprawiedliwione';

  @override
  String get key => 'accept';

  @override
  bool operator ==(Object other) => other is ExcuseAccepted;

  @override
  int get hashCode => key.hashCode;
}

/// Wysłane, czeka na rozpatrzenie przez szkołę (oficjalna etykieta „wysłane”).
final class ExcuseSent extends ExcuseStatus {
  const ExcuseSent();

  @override
  String get label => 'Wysłane';

  @override
  String get key => 'send';

  @override
  bool operator ==(Object other) => other is ExcuseSent;

  @override
  int get hashCode => key.hashCode;
}

/// Wartość, której znaczenia nie potwierdzono — pokazujemy ją dosłownie.
final class ExcuseStatusOther extends ExcuseStatus {
  const ExcuseStatusOther(this.raw);

  final String raw;

  @override
  String get label => 'Status: $raw';

  @override
  String get key => 'raw:$raw';

  @override
  bool operator ==(Object other) =>
      other is ExcuseStatusOther && other.raw == raw;

  @override
  int get hashCode => key.hashCode;
}

final class ExcuseStatusMissing extends ExcuseStatus {
  const ExcuseStatusMissing();

  @override
  String get label => 'Brak statusu';

  @override
  String get key => 'missing';

  @override
  bool operator ==(Object other) => other is ExcuseStatusMissing;

  @override
  int get hashCode => key.hashCode;
}

/// Zakres dni objętych zgłoszeniem (włącznie).
class ExcusePeriod {
  const ExcusePeriod({required this.from, required this.to});

  final DateTime from;
  final DateTime to;

  bool get isSingleDay =>
      from.year == to.year && from.month == to.month && from.day == to.day;

  bool overlaps(DateTime start, DateTime end) =>
      !to.isBefore(start) && !from.isAfter(end);
}

/// Pojedyncza lekcja wskazana w zgłoszeniu (pusta lista = całe dni z okresu).
class ExcuseLesson {
  const ExcuseLesson({required this.date, this.number});

  final DateTime date;
  final int? number;
}

/// Zgłoszone e-Usprawiedliwienie (pozycja historii; ten sam obiekt służy do
/// widoku szczegółów — API nie ma osobnego endpointu szczegółów).
class ExcuseRequest {
  const ExcuseRequest({
    required this.id,
    required this.status,
    required this.reason,
    this.postedAt,
    this.period,
    this.lessons = const [],
    this.justifiedAbsences = 0,
    this.hasAttachment = false,
    this.notifiedTeachers = const [],
  });

  final int id;
  final ExcuseStatus status;

  /// Uzasadnienie wpisane przez rodzica.
  final String reason;
  final DateTime? postedAt;
  final ExcusePeriod? period;
  final List<ExcuseLesson> lessons;

  /// Liczba nieobecności usprawiedliwionych tym zgłoszeniem (wg Librusa).
  final int justifiedAbsences;
  final bool hasAttachment;
  final List<String> notifiedTeachers;

  /// Konkretne lekcje (a nie całe dni).
  bool get isLessonBased => lessons.isNotEmpty;
}

/// Filtr listy: status (klucz) i zakres dat nachodzący na okres zgłoszenia.
class ExcuseFilter {
  const ExcuseFilter({this.statusKey, this.from, this.to});

  final String? statusKey;
  final DateTime? from;
  final DateTime? to;

  bool get isActive => statusKey != null || from != null || to != null;

  bool matches(ExcuseRequest e) {
    if (statusKey != null && e.status.key != statusKey) return false;
    if (from == null && to == null) return true;
    final start = from ?? DateTime(1970);
    final end = to ?? DateTime(9999);
    final period = e.period;
    if (period != null) return period.overlaps(start, end);
    final posted = e.postedAt;
    return posted != null &&
        !posted.isBefore(start) &&
        !posted.isAfter(end.add(const Duration(days: 1)));
  }

  List<ExcuseRequest> apply(Iterable<ExcuseRequest> all) =>
      all.where(matches).toList();
}
