import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/message.dart';
import '../domain/message_draft.dart';
import '../domain/send_outcome.dart';

enum ComposeStatus { editing, sending, sent, rejected, unknown }

/// Stan formularza nowej wiadomości / odpowiedzi.
///
/// Zasady: wysyłka tylko z [send] (świadome kliknięcie), co najwyżej jedna
/// naraz, bez ponowień; szkic zapisany przed wysłaniem i usuwany dopiero po
/// potwierdzonym sukcesie; po wyniku niejednoznacznym kolejna próba wymaga
/// wyraźnego potwierdzenia.
class ComposeController extends ChangeNotifier {
  ComposeController({
    required this._draft,
    required this._send,
    required this._saveDraft,
    required this._deleteDraft,
    this.autosaveDelay = const Duration(milliseconds: 700),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Future<SendOutcome> Function(MessageDraft) _send;
  final Future<void> Function(MessageDraft) _saveDraft;
  final Future<void> Function(String id) _deleteDraft;
  final DateTime Function() _clock;
  final Duration autosaveDelay;

  MessageDraft _draft;
  ComposeStatus _status = ComposeStatus.editing;
  String? _statusMessage;
  List<String> _serverMessages = const [];
  String? _sentMessageId;
  List<DraftProblem> _problems = const [];
  bool _showProblems = false;
  Timer? _autosave;
  bool _disposed = false;

  MessageDraft get draft => _draft;
  ComposeStatus get status => _status;
  String? get statusMessage => _statusMessage;
  List<String> get serverMessages => _serverMessages;
  String? get sentMessageId => _sentMessageId;

  /// Błędy walidacji — widoczne po pierwszej próbie wysłania.
  List<DraftProblem> get problems => _showProblems ? _problems : const [];

  bool get isSending => _status == ComposeStatus.sending;
  bool get canEdit =>
      _status != ComposeStatus.sending && _status != ComposeStatus.sent;

  /// Poprzednia próba skończyła się niejednoznacznie (także sprzed restartu).
  bool get needsResendConfirmation => _draft.unknownSendAt != null;

  void update({
    String? topic,
    String? body,
    List<MessageRecipient>? recipients,
  }) {
    if (!canEdit) return;
    // Odpowiedź w wątku: adresat jest stały.
    if (_draft.isReply && recipients != null) return;
    _draft = _draft.copyWith(
      topic: topic,
      body: body,
      recipients: recipients,
      updatedAt: _clock(),
    );
    if (_showProblems) _problems = validateDraft(_draft);
    if (_status == ComposeStatus.rejected) {
      _status = ComposeStatus.editing;
      _statusMessage = null;
      _serverMessages = const [];
    }
    _autosave?.cancel();
    _autosave = Timer(autosaveDelay, () => unawaited(flush()));
    _notify();
  }

  void addRecipients(Iterable<MessageRecipient> added) {
    final ids = _draft.recipients.map((r) => r.accountId).toSet();
    update(
      recipients: [
        ..._draft.recipients,
        ...added.where((r) => ids.add(r.accountId)),
      ],
    );
  }

  void removeRecipient(String accountId) => update(
    recipients: _draft.recipients
        .where((r) => r.accountId != accountId)
        .toList(),
  );

  /// Zapisuje szkic teraz (np. przy wyjściu z formularza).
  Future<void> flush() async {
    _autosave?.cancel();
    if (_status == ComposeStatus.sent) return;
    await _trySave();
  }

  /// Ostatni zapis szkicu się nie udał (treść jest nadal w formularzu).
  bool get draftSaveFailed => _draftSaveFailed;
  bool _draftSaveFailed = false;

  Future<void> _trySave() async {
    try {
      await _saveDraft(_draft);
      _draftSaveFailed = false;
    } catch (_) {
      _draftSaveFailed = true;
    }
  }

  /// Zwraca `null`, gdy nic nie wysłano (trwa wysyłka, błędy formularza albo
  /// brak potwierdzenia po niejednoznacznym wyniku).
  Future<SendOutcome?> send({bool confirmedDespiteUnknown = false}) async {
    if (_status == ComposeStatus.sending || _status == ComposeStatus.sent) {
      return null;
    }
    _problems = validateDraft(_draft);
    _showProblems = true;
    if (_problems.isNotEmpty) {
      _notify();
      return null;
    }
    if (needsResendConfirmation && !confirmedDespiteUnknown) return null;

    _status = ComposeStatus.sending;
    _statusMessage = null;
    _serverMessages = const [];
    _notify();

    _autosave?.cancel();
    // Szkic zapisany przed wysłaniem; błąd zapisu nie blokuje wysyłki.
    await _trySave();
    final SendOutcome outcome;
    try {
      outcome = await _send(_draft);
    } catch (_) {
      // Nieoczekiwany błąd aplikacji — nie wiemy, czy żądanie wyszło.
      return _finishUnknown(
        'Wystąpił nieoczekiwany błąd. Nie wiadomo, czy wiadomość została wysłana.',
      );
    }
    switch (outcome) {
      case SendSucceeded(:final messageId):
        _status = ComposeStatus.sent;
        _sentMessageId = messageId;
        _statusMessage = _draft.isReply
            ? 'Odpowiedź została wysłana w wątku wiadomości.'
            : 'Wiadomość została wysłana.';
        try {
          await _deleteDraft(_draft.id);
        } catch (_) {
          // Wysłana; pozostały szkic użytkownik usunie ręcznie.
        }
      case SendRejected(:final reason, :final serverMessages):
        _status = ComposeStatus.rejected;
        _statusMessage = reason;
        _serverMessages = serverMessages;
      case SendUnknown(:final reason):
        return _finishUnknown(reason, outcome: outcome);
    }
    _notify();
    return outcome;
  }

  Future<SendOutcome> _finishUnknown(
    String reason, {
    SendOutcome? outcome,
  }) async {
    _status = ComposeStatus.unknown;
    _statusMessage = reason;
    _draft = _draft.copyWith(unknownSendAt: _clock(), updatedAt: _clock());
    await _trySave();
    _notify();
    return outcome ?? SendUnknown(reason);
  }

  /// Użytkownik sprawdził Wysłane i uznał, że wiadomość nie wyszła.
  void acknowledgeUnknown() {
    if (_status == ComposeStatus.sending || _status == ComposeStatus.sent) {
      return;
    }
    _status = ComposeStatus.editing;
    _statusMessage = null;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _autosave?.cancel();
    super.dispose();
  }
}
