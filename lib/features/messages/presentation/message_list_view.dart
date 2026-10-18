import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/synergia_exception.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../domain/message.dart';
import 'message_detail_screen.dart';
import 'messages_providers.dart';

/// Odebrane albo Wysłane: lista z doczytywaniem i odświeżaniem ręcznym.
class MessageListView extends ConsumerWidget {
  const MessageListView({super.key, required this.folder});

  final MessageFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = messageListProvider(folder);
    final list = ref.watch(provider);
    Future<void> refresh() => ref.read(provider.notifier).refresh();

    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => e is MessagesUnavailableException
          ? EmptyView(message: e.message)
          : ErrorView(error: e, onRetry: refresh),
      data: (state) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView.builder(
          itemCount: state.items.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  'Pobrano: ${formatDateTime(state.fetchedAt)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              );
            }
            if (i == state.items.length + 1) {
              return _Footer(state: state, folder: folder);
            }
            return MessageTile(message: state.items[i - 1]);
          },
        ),
      ),
    );
  }
}

class _Footer extends ConsumerWidget {
  const _Footer({required this.state, required this.folder});

  final MessageListState state;
  final MessageFolder folder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (state.items.isEmpty) {
      return EmptyView(
        message: folder == MessageFolder.inbox
            ? 'Brak odebranych wiadomości.'
            : 'Brak wysłanych wiadomości.',
      );
    }
    if (state.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final error = state.loadMoreError;
    if (error != null) {
      return ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(
          error is SynergiaException
              ? error.message
              : 'Nie udało się wczytać kolejnej strony.',
        ),
        trailing: TextButton(
          onPressed: () =>
              ref.read(messageListProvider(folder).notifier).loadMore(),
          child: const Text('Ponów'),
        ),
      );
    }
    if (!state.hasMore) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: Text('To wszystkie wiadomości.')),
      );
    }
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Center(
        child: OutlinedButton(
          onPressed: () =>
              ref.read(messageListProvider(folder).notifier).loadMore(),
          child: const Text('Wczytaj starsze'),
        ),
      ),
    );
  }
}

class MessageTile extends StatelessWidget {
  const MessageTile({super.key, required this.message});

  final MessageSummary message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = message.isUnread;
    final bold = unread ? const TextStyle(fontWeight: FontWeight.bold) : null;
    final prefix = message.folder == MessageFolder.outbox ? 'Do: ' : '';
    return Semantics(
      label: unread ? 'Nieprzeczytana wiadomość' : null,
      child: ListTile(
        leading: Icon(
          unread ? Icons.mark_email_unread : Icons.mail_outline,
          color: unread ? theme.colorScheme.primary : null,
        ),
        title: Text(
          '$prefix${message.counterpart}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: bold,
        ),
        subtitle: Text(
          [
            message.topic,
            if (message.preview.isNotEmpty) message.preview,
          ].join('\n'),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
        ),
        isThreeLine: message.preview.isNotEmpty,
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (message.sentAt != null)
              Text(
                formatListDate(message.sentAt!),
                style: theme.textTheme.bodySmall,
              ),
            if (message.hasAttachments)
              const Icon(
                Icons.attach_file,
                size: 16,
                semanticLabel: 'Załącznik',
              ),
          ],
        ),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) =>
                MessageDetailScreen(folder: message.folder, id: message.id),
          ),
        ),
      ),
    );
  }
}
