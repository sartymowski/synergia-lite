import '../../../core/errors/synergia_exception.dart';
import '../../../core/security/session_store.dart';
import '../../messages/data/messages_repository.dart';
import '../../messages/domain/message.dart';
import '../domain/new_message_detector.dart';
import '../domain/ports.dart';
import '../domain/sync_state.dart';
import 'sync_state_repository.dart';

enum SyncTrigger {
  /// Okresowe zadanie WorkManagera — wymaga włączonych powiadomień.
  background,

  /// Przycisk „Sprawdź teraz” / pierwsza synchronizacja po włączeniu.
  manual,
}

sealed class SyncOutcome {
  const SyncOutcome();

  /// Wynik dla WorkManagera: `false` = ponów z backoffem (tylko błędy
  /// przejściowe i nie więcej niż kilka razy z rzędu).
  bool get workSucceeded => true;

  /// Dalsze okresowe sprawdzanie nie ma sensu bez działania użytkownika.
  bool get stopsMonitoring => false;

  String get label;
}

enum SkipReason { disabled, signedOut, noPermission, rateLimited, busy, paused }

final class SyncSkipped extends SyncOutcome {
  const SyncSkipped(this.reason);

  final SkipReason reason;

  @override
  bool get stopsMonitoring =>
      reason == SkipReason.disabled || reason == SkipReason.signedOut;

  @override
  String get label => switch (reason) {
    SkipReason.disabled => 'Powiadomienia wyłączone — pominięto.',
    SkipReason.signedOut => 'Brak sesji — pominięto.',
    SkipReason.noPermission => 'Brak uprawnienia do powiadomień — pominięto.',
    SkipReason.rateLimited =>
      'Serwer poprosił o przerwę (HTTP 429) — pominięto.',
    SkipReason.busy => 'Trwa inna synchronizacja — pominięto.',
    SkipReason.paused => 'Monitorowanie wstrzymane — pominięto.',
  };
}

final class SyncBaseline extends SyncOutcome {
  const SyncBaseline(this.known);

  final int known;

  @override
  String get label =>
      'Pierwsza synchronizacja: zapamiętano $known wiadomości, bez powiadomień.';
}

final class SyncNoNew extends SyncOutcome {
  const SyncNoNew();

  @override
  String get label => 'Brak nowych wiadomości.';
}

final class SyncNotified extends SyncOutcome {
  const SyncNotified(this.count);

  final int count;

  @override
  String get label => 'Nowe wiadomości: $count — pokazano powiadomienie.';
}

/// Np. wylogowanie w trakcie — nic nie pokazano.
final class SyncAborted extends SyncOutcome {
  const SyncAborted();

  @override
  String get label =>
      'Przerwano (zmiana sesji lub ustawień) — bez powiadomienia.';
}

final class SyncPaused extends SyncOutcome {
  const SyncPaused(this.reason, {required this.newlyPaused});

  /// `sessionExpired` albo `moduleUnavailable`.
  final String reason;
  final bool newlyPaused;

  @override
  bool get stopsMonitoring => true;

  @override
  String get label => reason == pausedSessionExpired
      ? 'Sesja wygasła — zaloguj się ponownie, aby wznowić.'
      : 'Moduł Wiadomości niedostępny dla konta.';
}

final class SyncFailed extends SyncOutcome {
  const SyncFailed(
    this.kind, {
    required this.transient,
    required this.failures,
  });

  final String kind;
  final bool transient;
  final int failures;

  @override
  bool get workSucceeded =>
      !(transient && failures <= SyncPolicyLimits.maxWorkRetries);

  @override
  String get label => 'Błąd: $kind.';
}

const pausedSessionExpired = 'sessionExpired';
const pausedModuleUnavailable = 'moduleUnavailable';

abstract final class SyncPolicyLimits {
  /// Ile razy z rzędu WorkManager może ponowić przy błędzie przejściowym;
  /// potem czekamy na zwykły termin okresowy.
  static const maxWorkRetries = 3;

  /// Jeśli cała pierwsza strona to nowe wiadomości, doczytujemy kolejne —
  /// najwyżej tyle stron w jednym uruchomieniu.
  static const maxPages = 3;

  static const defaultRetryAfter = Duration(minutes: 30);
  static const maxRetryAfter = Duration(hours: 6);
}

/// Jedno uruchomienie synchronizacji (wspólne dla WorkManagera i „Sprawdź teraz”).
///
/// Gwarancje (zob. docs/notifications.md): co najwyżej jedno powiadomienie na
/// wiadomość (stan zapisywany PRZED pokazaniem; identyfikatory powiadomień
/// deterministyczne), brak powiadomień historycznych, brak powiadomienia po
/// wylogowaniu w trakcie. Rzadko możliwa utrata powiadomienia (awaria między
/// zapisem stanu a wyświetleniem) — nigdy lawina duplikatów.
class MessageNotificationChecker {
  MessageNotificationChecker({
    required this._messages,
    required this._session,
    required this._state,
    required this._settings,
    required this._notifier,
    DateTime Function()? clock,
    this.leaseDuration = const Duration(minutes: 2),
    this.coalesceInIsolate = true,
  }) : _clock = clock ?? DateTime.now;

  final MessagesRepository _messages;
  final SessionStore _session;
  final MessageSyncStateRepository _state;
  final NotificationSettingsRepository _settings;
  final MessageNotifier _notifier;
  final DateTime Function() _clock;
  final Duration leaseDuration;

  /// W jednym izolacie równoległe wywołania dostają ten sam wynik.
  final bool coalesceInIsolate;
  static Future<SyncOutcome>? _inFlight;

  Future<SyncOutcome> run({required SyncTrigger trigger}) {
    if (!coalesceInIsolate) return _run(trigger);
    final running = _inFlight;
    if (running != null) return running;
    final result = _run(trigger).whenComplete(() => _inFlight = null);
    return _inFlight = result;
  }

  Future<bool> _stillValid(
    SyncTrigger trigger,
    String owner, {
    required bool hadState,
  }) async {
    final session = await _session.read();
    if (session == null || session.isEmpty) return false;
    if (trigger == SyncTrigger.background &&
        !(await _settings.read()).enabled) {
      return false;
    }
    final current = await _state.readAny();
    // Stan usunięty (wylogowanie) albo przejęty przez inne konto.
    if (hadState && current?.owner != owner) return false;
    return true;
  }

  Future<SyncOutcome> _run(SyncTrigger trigger) async {
    final now = _clock();
    if (trigger == SyncTrigger.background &&
        !(await _settings.read()).enabled) {
      return const SyncSkipped(SkipReason.disabled);
    }
    final session = await _session.read();
    if (session == null || session.isEmpty) {
      return const SyncSkipped(SkipReason.signedOut);
    }
    if (!await _notifier.canNotify()) {
      return const SyncSkipped(SkipReason.noPermission);
    }

    final any = await _state.readAny();
    if (any != null) {
      if (any.retryNotBefore?.isAfter(now) ?? false) {
        return const SyncSkipped(SkipReason.rateLimited);
      }
      if (any.leaseUntil?.isAfter(now) ?? false) {
        return const SyncSkipped(SkipReason.busy);
      }
      if (trigger == SyncTrigger.background && any.pausedReason != null) {
        return const SyncSkipped(SkipReason.paused);
      }
      await _state.write(
        any.copyWith(leaseUntil: now.add(leaseDuration), lastAttemptAt: now),
      );
    }

    try {
      final owner = await _messages.accountKey();
      final previous = await _state.read(owner);
      final first = await _messages.fetchPage(MessageFolder.inbox, 1);

      if (previous == null) {
        if (!await _stillValid(trigger, owner, hadState: false)) {
          return const SyncAborted();
        }
        await _state.write(
          MessageSyncState.baseline(
            owner,
            [for (final m in first.items) m.id],
            newestSentAt(first.items),
            now,
          ),
        );
        return SyncBaseline(first.items.length);
      }

      // Wszystko na stronie nowe → mogło przyjść więcej; doczytaj do zakładki.
      final items = [...first.items];
      var page = first;
      final known = previous.knownIds.toSet();
      while (page.hasMore &&
          page.page < SyncPolicyLimits.maxPages &&
          page.items.isNotEmpty &&
          page.items.every((m) => !known.contains(m.id))) {
        page = await _messages.fetchPage(MessageFolder.inbox, page.page + 1);
        items.addAll(page.items);
      }

      final detection = detectNewMessages(previous, items);
      if (!await _stillValid(trigger, owner, hadState: true)) {
        return const SyncAborted();
      }
      await _state.commit(
        previous.copyWith(
          knownIds: detection.knownIds,
          watermark: detection.watermark,
          lastSuccessAt: now,
          lastAttemptAt: now,
          clearError: true,
          consecutiveFailures: 0,
          clearRetry: true,
          clearLease: true,
          clearPaused: true,
        ),
      );
      if (detection.newMessages.isEmpty) return const SyncNoNew();
      // Ostatnia kontrola tuż przed pokazaniem (wylogowanie w trakcie).
      if (!await _stillValid(trigger, owner, hadState: true)) {
        return const SyncAborted();
      }
      await _notifier.showNewMessages(owner, detection.newMessages);
      return SyncNotified(detection.newMessages.length);
    } on SessionExpiredException {
      return _pause(pausedSessionExpired, now);
    } on MessagesUnavailableException {
      return _pause(pausedModuleUnavailable, now);
    } on RateLimitedException catch (e) {
      final wait = clampRetryAfter(e.retryAfter);
      final failures = await _recordFailure(
        'HTTP 429',
        now,
        retryNotBefore: now.add(wait),
      );
      return SyncFailed(
        'HTTP 429 (przerwa ${wait.inMinutes} min)',
        transient: false,
        failures: failures,
      );
    } on SynergiaException catch (e) {
      final (kind, transient) = switch (e) {
        NetworkException() => ('brak połączenia', true),
        RequestTimeoutException() => ('przekroczony czas', true),
        MessagesSessionExpiredException() => (
          'sesja wiadomości odrzucona',
          true,
        ),
        ServerException(:final statusCode) when statusCode >= 500 => (
          'HTTP $statusCode',
          true,
        ),
        ServerException(:final statusCode) => ('HTTP $statusCode', false),
        PermissionDeniedException() => ('HTTP 403', false),
        UnexpectedResponseException() => (
          'nieoczekiwany format odpowiedzi',
          false,
        ),
        _ => (e.runtimeType.toString(), false),
      };
      final failures = await _recordFailure(kind, now);
      return SyncFailed(kind, transient: transient, failures: failures);
    }
  }

  Future<SyncOutcome> _pause(String reason, DateTime now) async {
    final any = await _state.readAny();
    if (any == null) return SyncPaused(reason, newlyPaused: true);
    await _state.write(
      any.copyWith(
        pausedReason: reason,
        lastError: reason,
        lastAttemptAt: now,
        clearLease: true,
      ),
    );
    return SyncPaused(reason, newlyPaused: any.pausedReason != reason);
  }

  Future<int> _recordFailure(
    String kind,
    DateTime now, {
    DateTime? retryNotBefore,
  }) async {
    final any = await _state.readAny();
    if (any == null) return 1;
    final failures = any.consecutiveFailures + 1;
    await _state.write(
      any.copyWith(
        lastError: kind,
        lastAttemptAt: now,
        consecutiveFailures: failures,
        retryNotBefore: retryNotBefore,
        clearLease: true,
      ),
    );
    return failures;
  }

  /// Wiadomości obejrzane w aplikacji (pierwsza strona Odebranych) nie powinny
  /// już wywołać powiadomienia. Działa tylko, gdy istnieje stan tego konta.
  Future<void> markSeen(String owner, List<MessageSummary> items) async {
    final current = await _state.read(owner);
    if (current == null || items.isEmpty) return;
    final detection = detectNewMessages(current, items);
    await _state.commit(
      current.copyWith(
        knownIds: detection.knownIds,
        watermark: detection.watermark,
      ),
    );
  }
}

/// `Retry-After` z HTTP 429 w rozsądnych granicach (1 min – 6 h; brak = 30 min).
Duration clampRetryAfter(Duration? retryAfter) {
  final wait = retryAfter ?? SyncPolicyLimits.defaultRetryAfter;
  if (wait > SyncPolicyLimits.maxRetryAfter) {
    return SyncPolicyLimits.maxRetryAfter;
  }
  if (wait < const Duration(minutes: 1)) return const Duration(minutes: 1);
  return wait;
}
