import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../notifications/presentation/notifications_providers.dart';
import '../domain/message.dart';
import '../domain/message_draft.dart';

class MessageListState {
  const MessageListState({
    required this.items,
    required this.lastPage,
    required this.hasMore,
    required this.fetchedAt,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<MessageSummary> items;
  final int lastPage;
  final bool hasMore;
  final DateTime fetchedAt;
  final bool loadingMore;
  final Object? loadMoreError;

  MessageListState copyWith({
    List<MessageSummary>? items,
    int? lastPage,
    bool? hasMore,
    bool? loadingMore,
    Object? loadMoreError,
    bool clearError = false,
  }) => MessageListState(
    items: items ?? this.items,
    lastPage: lastPage ?? this.lastPage,
    hasMore: hasMore ?? this.hasMore,
    fetchedAt: fetchedAt,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: clearError ? null : (loadMoreError ?? this.loadMoreError),
  );
}

/// Lista folderu z doczytywaniem kolejnych stron na żądanie.
class MessageListController extends AsyncNotifier<MessageListState> {
  MessageListController(this.folder);

  final MessageFolder folder;

  @override
  Future<MessageListState> build() async {
    final page = await guardSession(
      ref,
      () => ref.watch(messagesRepositoryProvider).fetchPage(folder, 1),
    );
    if (folder == MessageFolder.inbox) {
      // Obejrzane w aplikacji nie wywołają później powiadomienia.
      unawaited(markInboxSeen(ref, page.items));
    }
    return MessageListState(
      items: page.items,
      lastPage: 1,
      hasMore: page.hasMore,
      fetchedAt: DateTime.now(),
    );
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || current.loadingMore || !current.hasMore) return;
    state = AsyncData(current.copyWith(loadingMore: true, clearError: true));
    try {
      final next = await guardSession(
        ref,
        () => ref
            .read(messagesRepositoryProvider)
            .fetchPage(folder, current.lastPage + 1),
      );
      final known = current.items.map((m) => m.id).toSet();
      state = AsyncData(
        current.copyWith(
          items: [
            ...current.items,
            ...next.items.where((m) => known.add(m.id)),
          ],
          lastPage: next.page,
          hasMore: next.hasMore && next.items.isNotEmpty,
          loadingMore: false,
        ),
      );
    } catch (e) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: e));
    }
  }

  /// Po otwarciu wiadomość jest przeczytana także po stronie Librusa.
  void markRead(String id) {
    final current = state.value;
    if (current == null) return;
    final now = DateTime.now();
    state = AsyncData(
      current.copyWith(
        items: [
          for (final m in current.items) m.id == id ? m.markedRead(now) : m,
        ],
      ),
    );
  }
}

final messageListProvider = AsyncNotifierProvider.autoDispose
    .family<MessageListController, MessageListState, MessageFolder>(
      MessageListController.new,
    );

final messageDetailProvider = FutureProvider.autoDispose
    .family<MessageDetail, ({MessageFolder folder, String id})>((
      ref,
      key,
    ) async {
      final detail = await guardSession(
        ref,
        () => ref
            .watch(messagesRepositoryProvider)
            .fetchDetail(key.folder, key.id),
      );
      if (key.folder == MessageFolder.inbox &&
          ref.exists(messageListProvider(MessageFolder.inbox))) {
        ref
            .read(messageListProvider(MessageFolder.inbox).notifier)
            .markRead(key.id);
        ref.invalidate(unreadCountProvider);
      }
      return detail;
    });

final unreadCountProvider = FutureProvider.autoDispose<int>(
  (ref) => guardSession(
    ref,
    () => ref.watch(messagesRepositoryProvider).unreadInboxCount(),
  ),
);

/// Klucz właściciela wiadomości roboczych (identyfikator konta wiadomości).
final messagesAccountKeyProvider = FutureProvider<String>(
  (ref) => guardSession(
    ref,
    () => ref.watch(messagesRepositoryProvider).accountKey(),
  ),
);

final recipientGroupsProvider =
    FutureProvider.autoDispose<List<RecipientGroup>>(
      (ref) => guardSession(
        ref,
        () => ref.watch(messagesRepositoryProvider).recipientGroups(),
      ),
    );

final groupRecipientsProvider = FutureProvider.autoDispose
    .family<List<MessageRecipient>, RecipientGroup>(
      (ref, group) => guardSession(
        ref,
        () => ref.watch(messagesRepositoryProvider).recipientsIn(group),
      ),
    );

class DraftsController extends AsyncNotifier<List<MessageDraft>> {
  @override
  Future<List<MessageDraft>> build() async {
    final owner = await ref.watch(messagesAccountKeyProvider.future);
    return ref.read(draftsStoreProvider).list(owner);
  }

  Future<void> save(MessageDraft draft) async {
    final owner = await ref.read(messagesAccountKeyProvider.future);
    await ref.read(draftsStoreProvider).save(owner, draft);
    ref.invalidateSelf();
  }

  Future<void> remove(String id) async {
    final owner = await ref.read(messagesAccountKeyProvider.future);
    await ref.read(draftsStoreProvider).remove(owner, id);
    ref.invalidateSelf();
  }
}

final draftsProvider =
    AsyncNotifierProvider<DraftsController, List<MessageDraft>>(
      DraftsController.new,
    );
