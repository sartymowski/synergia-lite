import 'dart:convert';

import '../../../core/storage/key_value_store.dart';
import '../domain/message_draft.dart';

export '../../../core/storage/key_value_store.dart';

/// Lokalne wiadomości robocze, przypisane do jednego konta wiadomości.
/// Inne konto nie zobaczy cudzych roboczych — przy zmianie właściciela są
/// usuwane. Wylogowanie usuwa wszystkie ([clearAll]).
class DraftsStore {
  DraftsStore(this._kv);

  static const _key = 'message_drafts_v1';
  final KeyValueStore _kv;

  Future<List<MessageDraft>> list(String owner) async =>
      (await _load(owner)).drafts;

  Future<void> save(String owner, MessageDraft draft) async {
    final current = await _load(owner);
    final others = current.drafts.where((d) => d.id != draft.id);
    final drafts = [if (!draft.isEmpty) draft, ...others]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await _store(owner, drafts);
  }

  Future<void> remove(String owner, String id) async {
    final current = await _load(owner);
    await _store(owner, current.drafts.where((d) => d.id != id).toList());
  }

  Future<void> clearAll() => _kv.delete(_key);

  Future<({List<MessageDraft> drafts})> _load(String owner) async {
    final raw = await _kv.read(_key);
    if (raw == null) return (drafts: <MessageDraft>[]);
    try {
      final json = jsonDecode(raw);
      if (json is! Map || json['owner'] != owner) {
        // Robocze innego konta (albo uszkodzony zapis) — nie pokazujemy ich.
        await clearAll();
        return (drafts: <MessageDraft>[]);
      }
      final list = json['drafts'];
      return (
        drafts: [
          if (list is List)
            for (final d in list) ?MessageDraft.fromJson(d),
        ],
      );
    } on FormatException {
      await clearAll();
      return (drafts: <MessageDraft>[]);
    }
  }

  Future<void> _store(String owner, List<MessageDraft> drafts) async {
    if (drafts.isEmpty) {
      await clearAll();
      return;
    }
    await _kv.write(
      _key,
      jsonEncode({
        'owner': owner,
        'drafts': [for (final d in drafts) d.toJson()],
      }),
    );
  }
}
