import 'dart:convert';

import '../../../core/storage/key_value_store.dart';
import '../domain/sync_state.dart';

/// Stan wykrywania nowych wiadomości. Przechowywany jest stan jednego konta
/// (aplikacja obsługuje jedną sesję naraz); stan innego właściciela jest
/// ignorowany i nadpisywany nowym stanem bazowym.
class MessageSyncStateRepository {
  MessageSyncStateRepository(this._kv);

  static const _key = 'message_sync_state_v1';
  final KeyValueStore _kv;

  /// Stan dowolnego właściciela (np. do pokazania daty w ustawieniach).
  Future<MessageSyncState?> readAny() async {
    final raw = await _kv.read(_key);
    if (raw == null) return null;
    try {
      return MessageSyncState.fromJson(jsonDecode(raw));
    } on FormatException {
      return null;
    }
  }

  Future<MessageSyncState?> read(String owner) async {
    final state = await readAny();
    return state?.owner == owner ? state : null;
  }

  Future<void> write(MessageSyncState state) =>
      _kv.write(_key, jsonEncode(state.toJson()));

  /// Zapis z ponownym odczytem tuż przed zapisem: znane identyfikatory z
  /// równolegle zapisanego stanu tego samego konta są zachowywane (suma).
  Future<void> commit(MessageSyncState state) async {
    final current = await read(state.owner);
    final merged = current == null
        ? state
        : state.copyWith(knownIds: [...state.knownIds, ...current.knownIds]);
    await write(merged);
  }

  /// Po ponownym zalogowaniu lub włączeniu: wznów wstrzymane monitorowanie.
  Future<void> clearPause() async {
    final current = await readAny();
    if (current?.pausedReason == null) return;
    await write(current!.copyWith(clearPaused: true, clearError: true));
  }

  Future<void> clear() => _kv.delete(_key);
}

class NotificationSettings {
  const NotificationSettings({required this.enabled, this.changedAt});

  /// Użytkownik świadomie włączył powiadomienia o nowych wiadomościach.
  final bool enabled;
  final DateTime? changedAt;
}

class NotificationSettingsRepository {
  NotificationSettingsRepository(this._kv);

  static const _key = 'notification_settings_v1';
  final KeyValueStore _kv;

  /// Domyślnie wyłączone — monitorowanie tylko z decyzji użytkownika.
  Future<NotificationSettings> read() async {
    final raw = await _kv.read(_key);
    if (raw == null) return const NotificationSettings(enabled: false);
    try {
      final json = jsonDecode(raw);
      if (json is Map && json['enabled'] == true) {
        return NotificationSettings(
          enabled: true,
          changedAt: DateTime.tryParse('${json['changedAt']}')?.toLocal(),
        );
      }
    } on FormatException {
      // uszkodzony zapis = wyłączone
    }
    return const NotificationSettings(enabled: false);
  }

  Future<void> setEnabled(bool enabled, {DateTime? now}) => _kv.write(
    _key,
    jsonEncode({
      'enabled': enabled,
      'changedAt': (now ?? DateTime.now()).toUtc().toIso8601String(),
    }),
  );

  Future<void> clear() => _kv.delete(_key);
}
