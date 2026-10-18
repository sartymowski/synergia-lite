import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/synergia_exception.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../domain/message.dart';
import '../domain/message_draft.dart';
import 'compose_screen.dart';
import 'message_list_view.dart';
import 'messages_providers.dart';

class MessagesTab extends StatefulWidget {
  const MessagesTab({super.key});

  @override
  State<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends State<MessagesTab> {
  MessageFolder _folder = MessageFolder.inbox;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: SegmentedButton<MessageFolder>(
            segments: [
              for (final f in MessageFolder.values)
                ButtonSegment(value: f, label: Text(f.label)),
            ],
            selected: {_folder},
            onSelectionChanged: (s) => setState(() => _folder = s.first),
          ),
        ),
        Expanded(
          child: switch (_folder) {
            MessageFolder.drafts => const DraftsView(),
            final f => MessageListView(key: ValueKey(f), folder: f),
          },
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton.extended(
      icon: const Icon(Icons.edit),
      label: const Text('Nowa'),
      tooltip: 'Nowa wiadomość',
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ComposeScreen(initial: MessageDraft.create()),
        ),
      ),
    ),
  );
}

class DraftsView extends ConsumerWidget {
  const DraftsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);
    return drafts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => e is MessagesUnavailableException
          ? EmptyView(message: e.message)
          : ErrorView(error: e, onRetry: () => ref.invalidate(draftsProvider)),
      data: (list) {
        if (list.isEmpty) {
          return const EmptyView(
            message:
                'Brak kopii roboczych. Niedokończone wiadomości zapisują się tu automatycznie.',
          );
        }
        return ListView(
          children: [
            for (final d in list)
              ListTile(
                leading: Icon(
                  d.unknownSendAt != null
                      ? Icons.help_outline
                      : (d.isReply ? Icons.reply : Icons.drafts_outlined),
                ),
                title: Text(
                  d.topic.trim().isEmpty ? '(bez tematu)' : d.topic,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (d.recipients.isNotEmpty)
                      'Do: ${d.recipients.map((r) => r.label).join(', ')}',
                    'Zmieniono ${formatDateTime(d.updatedAt)}',
                    if (d.unknownSendAt != null)
                      'Nie wiadomo, czy wysłano — sprawdź Wysłane',
                  ].join('\n'),
                ),
                isThreeLine: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ComposeScreen(initial: d),
                  ),
                ),
                trailing: IconButton(
                  tooltip: 'Usuń kopię roboczą',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Usunąć kopię roboczą?'),
                        content: const Text(
                          'Tej operacji nie można cofnąć. Wiadomość nie zostanie wysłana.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Anuluj'),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('Usuń'),
                          ),
                        ],
                      ),
                    );
                    if (ok == true) {
                      await ref.read(draftsProvider.notifier).remove(d.id);
                    }
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}
