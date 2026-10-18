import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../domain/message.dart';
import 'messages_providers.dart';

/// Wybór odbiorców spośród pracowników szkoły dostępnych dla konta.
/// Zwraca listę wybranych przez `Navigator.pop`.
class RecipientPickerScreen extends ConsumerStatefulWidget {
  const RecipientPickerScreen({super.key, this.alreadySelected = const []});

  final List<MessageRecipient> alreadySelected;

  @override
  ConsumerState<RecipientPickerScreen> createState() =>
      _RecipientPickerScreenState();
}

class _RecipientPickerScreenState extends ConsumerState<RecipientPickerScreen> {
  late final _selected = <String, MessageRecipient>{
    for (final r in widget.alreadySelected) r.accountId: r,
  };
  RecipientGroup? _group;
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(recipientGroupsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wybierz odbiorców'),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_selected.values.toList()),
            child: Text('Gotowe (${_selected.length})'),
          ),
        ],
      ),
      body: groups.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          error: e,
          onRetry: () => ref.invalidate(recipientGroupsProvider),
        ),
        data: (list) {
          if (list.isEmpty) {
            return const EmptyView(
              message:
                  'Librus nie udostępnia temu kontu żadnej grupy odbiorców.',
            );
          }
          final group = _group ?? list.first;
          return Column(
            children: [
              SizedBox(
                height: 56,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  children: [
                    for (final g in list)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(g.name),
                          selected: g == group,
                          onSelected: (_) => setState(() => _group = g),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    labelText: 'Szukaj (imię, nazwisko, przedmiot)',
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: _GroupList(
                  group: group,
                  query: _query,
                  selected: _selected,
                  onToggle: _toggle,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  void _toggle(MessageRecipient r) => setState(() {
    if (_selected.remove(r.accountId) == null) _selected[r.accountId] = r;
  });
}

class _GroupList extends ConsumerWidget {
  const _GroupList({
    required this.group,
    required this.query,
    required this.selected,
    required this.onToggle,
  });

  final RecipientGroup group;
  final String query;
  final Map<String, MessageRecipient> selected;
  final void Function(MessageRecipient) onToggle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(groupRecipientsProvider(group));
    return people.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        error: e,
        onRetry: () => ref.invalidate(groupRecipientsProvider(group)),
      ),
      data: (list) {
        final visible = list.where((r) => r.matches(query)).toList();
        if (visible.isEmpty) {
          return EmptyView(
            message: list.isEmpty
                ? 'Ta grupa jest pusta.'
                : 'Brak wyników wyszukiwania.',
          );
        }
        return ListView.builder(
          itemCount: visible.length,
          itemBuilder: (context, i) {
            final r = visible[i];
            final details = [
              if (r.subjects.isNotEmpty) r.subjects.join(', '),
              if (!r.isAvailable)
                r.returnAt == null
                    ? 'nieobecny'
                    : 'nieobecny do ${formatDate(r.returnAt!)}',
            ].join(' · ');
            return CheckboxListTile(
              value: selected.containsKey(r.accountId),
              onChanged: (_) => onToggle(r),
              title: Text(r.label),
              subtitle: details.isEmpty ? null : Text(details),
            );
          },
        );
      },
    );
  }
}
