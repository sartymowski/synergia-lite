import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../domain/message.dart';
import '../domain/message_draft.dart';
import 'compose_screen.dart';
import 'message_body_view.dart';
import 'messages_providers.dart';

class MessageDetailScreen extends ConsumerWidget {
  const MessageDetailScreen({
    super.key,
    required this.folder,
    required this.id,
  });

  final MessageFolder folder;
  final String id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = messageDetailProvider((folder: folder, id: id));
    final detail = ref.watch(provider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          folder == MessageFolder.inbox ? 'Wiadomość' : 'Wysłana wiadomość',
        ),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(provider)),
        data: (m) => _DetailBody(message: m),
      ),
      bottomNavigationBar: switch (detail.value) {
        final MessageDetail m when m.canReply => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              icon: const Icon(Icons.reply),
              label: const Text('Odpowiedz'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ComposeScreen(
                    initial: MessageDraft.create(
                      replyTo: ReplyContext(
                        originalMessageId: m.id,
                        originalTopic: m.topic,
                      ),
                      to: MessageRecipient(
                        accountId: m.senderId!,
                        label: m.senderName,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        _ => null,
      },
    );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.message});

  final MessageDetail message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final m = message;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SelectableText(m.topic, style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (m.folder == MessageFolder.inbox)
          _Line(label: 'Od', value: [m.senderName, ?m.senderGroup].join(' · ')),
        if (m.folder == MessageFolder.outbox) ...[
          _Line(
            label: 'Do',
            value: m.receivers.isEmpty
                ? '${m.receiversCount ?? '?'} odbiorców'
                : m.receivers.map((r) => r.name).join(', '),
          ),
          if (m.receivers.isNotEmpty)
            _Line(
              label: 'Odczytano',
              value:
                  '${m.receivers.where((r) => r.readAt != null).length} z ${m.receivers.length}',
            ),
        ],
        if (m.sentAt != null)
          _Line(label: 'Data', value: formatDateTime(m.sentAt!)),
        if (m.noReply && m.folder == MessageFolder.inbox)
          const _Line(
            label: 'Uwaga',
            value: 'Nadawca wyłączył możliwość odpowiedzi.',
          ),
        const Divider(height: 32),
        MessageBodyView(html: m.bodyHtml),
        if (m.attachments.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Załączniki', style: theme.textTheme.titleSmall),
          for (final a in m.attachments)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.attach_file),
              title: Text(a.filename),
              subtitle: const Text(
                'Pobieranie w aplikacji jeszcze niedostępne — pobierz w Synergii.',
              ),
            ),
        ],
        if (m.folder == MessageFolder.outbox && m.receivers.isNotEmpty) ...[
          const Divider(height: 32),
          Text('Status odczytu', style: theme.textTheme.titleSmall),
          for (final r in m.receivers)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(r.readAt != null ? Icons.done_all : Icons.schedule),
              title: Text(r.name),
              subtitle: Text(
                r.readAt != null
                    ? 'Odczytano ${formatDateTime(r.readAt!)}'
                    : 'Nieodczytana',
              ),
            ),
        ],
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          TextSpan(text: value),
        ],
      ),
    ),
  );
}
