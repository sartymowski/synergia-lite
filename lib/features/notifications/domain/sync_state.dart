/// Trwały stan wykrywania nowych wiadomości dla JEDNEGO konta wiadomości.
/// Zawiera wyłącznie identyfikatory i znaczniki czasu — nigdy treści,
/// tematów ani nadawców.
class MessageSyncState {
  const MessageSyncState({
    required this.owner,
    required this.knownIds,
    required this.baselineAt,
    this.watermark,
    this.lastSuccessAt,
    this.lastAttemptAt,
    this.lastError,
    this.consecutiveFailures = 0,
    this.retryNotBefore,
    this.leaseUntil,
    this.pausedReason,
  });

  /// Pierwsza synchronizacja konta: zapamiętaj stan skrzynki bez powiadomień.
  factory MessageSyncState.baseline(
    String owner,
    List<String> ids,
    DateTime? watermark,
    DateTime now,
  ) => MessageSyncState(
    owner: owner,
    knownIds: _cap(ids),
    baselineAt: now,
    watermark: watermark,
    lastSuccessAt: now,
    lastAttemptAt: now,
  );

  /// Identyfikator konta wiadomości (`me.accountId`) — stan innego konta nie
  /// jest nigdy używany.
  final String owner;

  /// Znane identyfikatory, od najnowszych; lista ograniczona do [maxKnown].
  final List<String> knownIds;
  final DateTime baselineAt;

  /// Najpóźniejsza data wysłania spośród znanych wiadomości — chroni przed
  /// powiadomieniem o starej wiadomości przywróconej np. z kosza.
  final DateTime? watermark;
  final DateTime? lastSuccessAt;
  final DateTime? lastAttemptAt;

  /// Rodzaj ostatniego błędu (bez treści odpowiedzi).
  final String? lastError;
  final int consecutiveFailures;

  /// Po HTTP 429 — do tej chwili nie odpytujemy serwera.
  final DateTime? retryNotBefore;

  /// Miękka blokada między kontekstami wykonania (aplikacja / WorkManager).
  final DateTime? leaseUntil;

  /// Monitorowanie wstrzymane (np. wygasła sesja) do czasu działania użytkownika.
  final String? pausedReason;

  static const maxKnown = 300;

  MessageSyncState copyWith({
    List<String>? knownIds,
    DateTime? watermark,
    DateTime? lastSuccessAt,
    DateTime? lastAttemptAt,
    String? lastError,
    bool clearError = false,
    int? consecutiveFailures,
    DateTime? retryNotBefore,
    bool clearRetry = false,
    DateTime? leaseUntil,
    bool clearLease = false,
    String? pausedReason,
    bool clearPaused = false,
  }) => MessageSyncState(
    owner: owner,
    knownIds: knownIds == null ? this.knownIds : _cap(knownIds),
    baselineAt: baselineAt,
    watermark: watermark ?? this.watermark,
    lastSuccessAt: lastSuccessAt ?? this.lastSuccessAt,
    lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
    lastError: clearError ? null : (lastError ?? this.lastError),
    consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
    retryNotBefore: clearRetry ? null : (retryNotBefore ?? this.retryNotBefore),
    leaseUntil: clearLease ? null : (leaseUntil ?? this.leaseUntil),
    pausedReason: clearPaused ? null : (pausedReason ?? this.pausedReason),
  );

  Map<String, Object?> toJson() => {
    'v': 1,
    'owner': owner,
    'knownIds': knownIds,
    'baselineAt': _iso(baselineAt),
    'watermark': _iso(watermark),
    'lastSuccessAt': _iso(lastSuccessAt),
    'lastAttemptAt': _iso(lastAttemptAt),
    'lastError': lastError,
    'consecutiveFailures': consecutiveFailures,
    'retryNotBefore': _iso(retryNotBefore),
    'leaseUntil': _iso(leaseUntil),
    'pausedReason': pausedReason,
  };

  static MessageSyncState? fromJson(Object? json) {
    if (json is! Map || json['v'] != 1) return null;
    final owner = json['owner'];
    final ids = json['knownIds'];
    final baseline = _date(json['baselineAt']);
    if (owner is! String || ids is! List || baseline == null) return null;
    return MessageSyncState(
      owner: owner,
      knownIds: _cap([for (final i in ids) ?(i is String ? i : null)]),
      baselineAt: baseline,
      watermark: _date(json['watermark']),
      lastSuccessAt: _date(json['lastSuccessAt']),
      lastAttemptAt: _date(json['lastAttemptAt']),
      lastError: json['lastError'] is String
          ? json['lastError'] as String
          : null,
      consecutiveFailures: json['consecutiveFailures'] is int
          ? json['consecutiveFailures'] as int
          : 0,
      retryNotBefore: _date(json['retryNotBefore']),
      leaseUntil: _date(json['leaseUntil']),
      pausedReason: json['pausedReason'] is String
          ? json['pausedReason'] as String
          : null,
    );
  }

  static List<String> _cap(List<String> ids) {
    final seen = <String>{};
    final unique = [
      for (final id in ids)
        if (seen.add(id)) id,
    ];
    return unique.length <= maxKnown ? unique : unique.sublist(0, maxKnown);
  }

  static String? _iso(DateTime? d) => d?.toUtc().toIso8601String();

  static DateTime? _date(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;
}
