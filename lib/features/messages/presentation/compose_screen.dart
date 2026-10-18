import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../domain/message.dart';
import '../domain/message_draft.dart';
import 'compose_controller.dart';
import 'message_list_view.dart';
import 'messages_providers.dart';
import 'recipient_picker_screen.dart';

/// Nowa wiadomość albo odpowiedź w wątku. Wysyła wyłącznie przycisk
/// „Wyślij” po potwierdzeniu; treść jest zapisywana lokalnie na bieżąco.
class ComposeScreen extends ConsumerStatefulWidget {
  const ComposeScreen({super.key, required this.initial});

  final MessageDraft initial;

  @override
  ConsumerState<ComposeScreen> createState() => _ComposeScreenState();
}

class _ComposeScreenState extends ConsumerState<ComposeScreen> {
  late final ComposeController _c;
  late final _topic = TextEditingController(text: widget.initial.topic);
  late final _body = TextEditingController(text: widget.initial.body);

  @override
  void initState() {
    super.initState();
    final drafts = ref.read(draftsProvider.notifier);
    final repo = ref.read(messagesRepositoryProvider);
    _c = ComposeController(
      draft: widget.initial,
      send: repo.send,
      saveDraft: drafts.save,
      deleteDraft: drafts.remove,
    )..addListener(_onChange);
    _topic.addListener(() => _c.update(topic: _topic.text));
    _body.addListener(() => _c.update(body: _body.text));
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    _c.flush();
    _c
      ..removeListener(_onChange)
      ..dispose();
    _topic.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _pickRecipients() async {
    final picked = await Navigator.of(context).push<List<MessageRecipient>>(
      MaterialPageRoute(
        builder: (_) =>
            RecipientPickerScreen(alreadySelected: _c.draft.recipients),
      ),
    );
    if (picked != null) _c.update(recipients: picked);
  }

  Future<void> _send() async {
    final d = _c.draft;
    if (validateDraft(d).isNotEmpty) {
      await _c.send(); // pokazuje błędy formularza, niczego nie wysyła
      return;
    }
    final names = d.recipients.map((r) => r.label).join(', ');
    final ok = await _confirm(
      title: d.isReply ? 'Wysłać odpowiedź?' : 'Wysłać wiadomość?',
      body: 'Do: $names\nTemat: ${d.topic.trim()}',
      action: 'Wyślij',
    );
    if (ok != true || !mounted) return;
    var confirmedDespiteUnknown = false;
    if (_c.needsResendConfirmation) {
      final again = await _confirm(
        title: 'Poprzednia próba mogła się udać',
        body:
            'Nie wiadomo, czy poprzednia próba wysłania tej wiadomości się powiodła. '
            'Sprawdź folder Wysłane — ponowne wysłanie może utworzyć duplikat.',
        action: 'Wyślij mimo to',
      );
      if (again != true || !mounted) return;
      confirmedDespiteUnknown = true;
    }
    await _c.send(confirmedDespiteUnknown: confirmedDespiteUnknown);
    if (_c.status == ComposeStatus.sent) {
      ref.invalidate(messageListProvider(MessageFolder.outbox));
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String body,
    required String action,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Anuluj'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(action),
        ),
      ],
    ),
  );

  void _openOutbox() {
    ref.invalidate(messageListProvider(MessageFolder.outbox));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => Scaffold(
          appBar: AppBar(title: const Text('Wysłane')),
          body: const MessageListView(folder: MessageFolder.outbox),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final d = _c.draft;
    final problems = _c.problems.toSet();
    String? error(Set<DraftProblem> of) {
      final p = problems.intersection(of);
      return p.isEmpty ? null : p.map((e) => draftProblemMessages[e]).join(' ');
    }

    final editable = _c.canEdit;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(d.isReply ? 'Odpowiedź' : 'Nowa wiadomość')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ?_statusCard(scheme),
          if (d.isReply)
            Card(
              child: ListTile(
                leading: const Icon(Icons.forum_outlined),
                title: Text('Odpowiedź w wątku: „${d.replyTo!.originalTopic}”'),
                subtitle: const Text(
                  'Zostanie wysłana jako odpowiedź powiązana z oryginalną wiadomością, '
                  'do jej nadawcy.',
                ),
              ),
            ),
          Text('Do', style: Theme.of(context).textTheme.labelLarge),
          Wrap(
            spacing: 8,
            children: [
              for (final r in d.recipients)
                InputChip(
                  label: Text(r.label),
                  onDeleted: editable && !d.isReply
                      ? () => _c.removeRecipient(r.accountId)
                      : null,
                ),
              if (!d.isReply)
                ActionChip(
                  avatar: const Icon(Icons.person_add_alt),
                  label: const Text('Dodaj odbiorców'),
                  onPressed: editable ? _pickRecipients : null,
                ),
            ],
          ),
          if (error({
                DraftProblem.noRecipients,
                DraftProblem.tooManyRecipients,
                DraftProblem.duplicateRecipient,
              })
              case final e?)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(e, style: TextStyle(color: scheme.error)),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _topic,
            enabled: editable,
            maxLength: MessageLimits.maxTopicLength,
            decoration: InputDecoration(
              labelText: 'Temat',
              errorText: error({
                DraftProblem.noTopic,
                DraftProblem.topicTooLong,
              }),
            ),
          ),
          TextField(
            controller: _body,
            enabled: editable,
            minLines: 6,
            maxLines: null,
            maxLength: MessageLimits.maxBodyLength,
            keyboardType: TextInputType.multiline,
            decoration: InputDecoration(
              labelText: 'Treść',
              alignLabelWithHint: true,
              errorText: error({DraftProblem.noBody, DraftProblem.bodyTooLong}),
            ),
          ),
          if (_c.draftSaveFailed)
            Text(
              'Nie udało się zapisać kopii roboczej na telefonie — nie zamykaj formularza przed wysłaniem.',
              style: TextStyle(color: scheme.error),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            icon: _c.isSending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send),
            label: Text(_c.isSending ? 'Wysyłanie…' : 'Wyślij'),
            onPressed: _c.isSending || _c.status == ComposeStatus.sent
                ? null
                : _send,
          ),
          const SizedBox(height: 8),
          Text(
            'Kopia robocza zapisuje się automatycznie na tym telefonie (zaszyfrowana) '
            'i znika po potwierdzonym wysłaniu.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget? _statusCard(ColorScheme scheme) {
    switch (_c.status) {
      case ComposeStatus.editing:
        return null;
      case ComposeStatus.sending:
        return const Card(
          child: ListTile(
            leading: CircularProgressIndicator(),
            title: Text('Wysyłanie…'),
            subtitle: Text('Nie zamykaj aplikacji do czasu potwierdzenia.'),
          ),
        );
      case ComposeStatus.sent:
        return Card(
          color: scheme.primaryContainer,
          child: ListTile(
            leading: const Icon(Icons.check_circle),
            title: Text(_c.statusMessage ?? 'Wysłano.'),
            subtitle: const Text('Librus potwierdził przyjęcie wiadomości.'),
            trailing: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Zamknij'),
            ),
          ),
        );
      case ComposeStatus.rejected:
        return Card(
          color: scheme.errorContainer,
          child: ListTile(
            leading: const Icon(Icons.error_outline),
            title: Text(_c.statusMessage ?? 'Nie wysłano.'),
            subtitle: _c.serverMessages.isEmpty
                ? const Text(
                    'Treść została zachowana. Możesz poprawić i spróbować ponownie.',
                  )
                : Text(_c.serverMessages.join('\n')),
          ),
        );
      case ComposeStatus.unknown:
        return Card(
          color: scheme.tertiaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.help_outline),
                  title: Text('Nie wiadomo, czy wiadomość została wysłana'),
                ),
                Text(_c.statusMessage ?? ''),
                const SizedBox(height: 8),
                const Text(
                  'Zanim spróbujesz ponownie, sprawdź folder Wysłane — ponowna próba '
                  'może utworzyć duplikat. Treść jest zachowana w kopii roboczej.',
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _openOutbox,
                      child: const Text('Sprawdź Wysłane'),
                    ),
                    TextButton(
                      onPressed: _c.acknowledgeUnknown,
                      child: const Text('Nie ma jej w Wysłanych'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
    }
  }
}
