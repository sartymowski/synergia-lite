import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/synergia_exception.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../domain/excuse.dart';
import 'excuse_detail_screen.dart';
import 'excuse_form_screen.dart';
import 'excuses_providers.dart';
import 'official_excuses_screen.dart';

String formatPeriod(ExcuseRequest e) {
  final p = e.period;
  if (p == null) return 'Okres nieznany';
  return p.isSingleDay
      ? formatDate(p.from)
      : '${formatDate(p.from)} – ${formatDate(p.to)}';
}

/// Historia e-Usprawiedliwień z filtrami; nowe zgłoszenie w oficjalnym module.
class ExcusesView extends ConsumerStatefulWidget {
  const ExcusesView({super.key});

  @override
  ConsumerState<ExcusesView> createState() => _ExcusesViewState();
}

class _ExcusesViewState extends ConsumerState<ExcusesView> {
  ExcuseFilter _filter = const ExcuseFilter();

  Future<void> _refresh() => ref.refresh(excusesProvider.future);

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _filter.from == null || _filter.to == null
          ? null
          : DateTimeRange(start: _filter.from!, end: _filter.to!),
      helpText: 'Zakres dat',
    );
    if (range != null) {
      setState(
        () => _filter = ExcuseFilter(
          statusKey: _filter.statusKey,
          from: range.start,
          to: range.end,
        ),
      );
    }
  }

  /// Oficjalny moduł → po powrocie porównanie historii (weryfikacja przyjęcia).
  Future<void> _openOfficial() async {
    List<ExcuseRequest>? before;
    try {
      before = await ref.read(excusesProvider.future);
    } catch (_) {
      before = null;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const OfficialExcusesScreen()),
    );
    if (!mounted) return;
    ref.invalidate(excusesProvider);
    String message;
    try {
      final after = await ref.read(excusesProvider.future);
      message = switch (before == null
          ? const NoNewExcuses()
          : compareHistory(before, after)) {
        NewExcusesFound(:final newOnes) =>
          'W historii jest nowe zgłoszenie (${newOnes.map(formatPeriod).join(', ')}).',
        NoNewExcuses() =>
          'Nie widać nowego zgłoszenia w historii. Jeśli zostało wysłane, sprawdź ponownie za chwilę.',
      };
    } catch (_) {
      message = 'Nie udało się odświeżyć historii — sprawdź ją ręcznie.';
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final excuses = ref.watch(excusesProvider);
    return Scaffold(
      body: excuses.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => e is PermissionDeniedException
            ? EmptyView(
                message:
                    'e-Usprawiedliwienia są niedostępne dla tego konta w Synergii. '
                    'Możesz otworzyć oficjalny moduł Librusa przyciskiem poniżej.',
              )
            : ErrorView(error: e, onRetry: _refresh),
        data: (all) => _list(all),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'excuse-native-form',
            icon: const Icon(Icons.edit_note),
            label: const Text('Formularz'),
            tooltip: 'Przygotuj usprawiedliwienie w aplikacji',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ExcuseFormScreen()),
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            heroTag: 'excuse-official',
            icon: const Icon(Icons.open_in_browser),
            label: const Text('Nowe (Librus)'),
            tooltip: 'Wyślij usprawiedliwienie w oficjalnym module Librusa',
            onPressed: _openOfficial,
          ),
        ],
      ),
    );
  }

  Widget _list(List<ExcuseRequest> all) {
    final statuses = <String, String>{
      for (final e in all) e.status.key: e.status.label,
    };
    final visible = _filter.apply(all);
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 160),
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Wszystkie'),
                  selected: _filter.statusKey == null,
                  onSelected: (_) => setState(
                    () => _filter = ExcuseFilter(
                      from: _filter.from,
                      to: _filter.to,
                    ),
                  ),
                ),
                for (final MapEntry(:key, :value) in statuses.entries)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: ChoiceChip(
                      label: Text(value),
                      selected: _filter.statusKey == key,
                      onSelected: (_) => setState(
                        () => _filter = ExcuseFilter(
                          statusKey: key,
                          from: _filter.from,
                          to: _filter.to,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.date_range, size: 18),
                  label: Text(
                    _filter.from == null
                        ? 'Zakres dat'
                        : '${formatDate(_filter.from!)} – ${formatDate(_filter.to!)}',
                  ),
                  onPressed: _pickDates,
                ),
                if (_filter.from != null)
                  IconButton(
                    tooltip: 'Wyczyść zakres dat',
                    icon: const Icon(Icons.clear),
                    onPressed: () => setState(
                      () =>
                          _filter = ExcuseFilter(statusKey: _filter.statusKey),
                    ),
                  ),
              ],
            ),
          ),
          if (all.isEmpty)
            const EmptyView(message: 'Brak wysłanych e-Usprawiedliwień.')
          else if (visible.isEmpty)
            const EmptyView(message: 'Brak zgłoszeń spełniających filtr.'),
          for (final e in visible)
            ListTile(
              leading: Icon(e.isLessonBased ? Icons.schedule : Icons.event),
              title: Text(
                [
                  formatPeriod(e),
                  if (e.isLessonBased) 'lekcje: ${e.lessons.length}',
                ].join(' · '),
              ),
              subtitle: Text(
                e.reason.isEmpty ? '(bez uzasadnienia)' : e.reason,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: _StatusChip(status: e.status),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ExcuseDetailScreen(excuse: e),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final ExcuseStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      label: Text(status.label),
      backgroundColor: status is ExcuseAccepted
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest,
      visualDensity: VisualDensity.compact,
    );
  }
}
