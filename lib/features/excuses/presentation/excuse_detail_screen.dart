import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../timetable/domain/lesson.dart';
import 'excuse_form_controller.dart' show lessonsOn;

import '../../../shared/format.dart';
import '../domain/excuse.dart';
import 'excuses_view.dart' show formatPeriod;

/// Szczegóły zgłoszenia. API historii nie ma osobnego endpointu szczegółów
/// ani pola z odpowiedzią wychowawcy — pokazujemy tylko to, co Librus podaje.
class ExcuseDetailScreen extends ConsumerWidget {
  const ExcuseDetailScreen({super.key, required this.excuse});

  final ExcuseRequest excuse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = excuse;
    final theme = Theme.of(context);
    final byDay = <DateTime, List<int?>>{};
    for (final l in e.lessons) {
      (byDay[l.date] ??= []).add(l.number);
    }
    final days = byDay.keys.toList()..sort();
    return Scaffold(
      appBar: AppBar(title: const Text('e-Usprawiedliwienie')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(formatPeriod(e), style: theme.textTheme.titleLarge),
          const SizedBox(height: 8),
          _Line('Status', e.status.label),
          if (e.postedAt != null) _Line('Wysłano', formatDateTime(e.postedAt!)),
          _Line(
            'Zakres',
            e.isLessonBased ? 'wybrane lekcje' : 'całe dni z okresu',
          ),
          if (e.justifiedAbsences > 0)
            _Line('Usprawiedliwione nieobecności', '${e.justifiedAbsences}'),
          if (e.notifiedTeachers.isNotEmpty)
            _Line('Powiadomieni', e.notifiedTeachers.join(', ')),
          if (e.hasAttachment)
            const _Line('Załącznik', 'tak (podgląd tylko w Librusie)'),
          if (days.isNotEmpty) ...[
            const Divider(height: 32),
            Text('Lekcje', style: theme.textTheme.titleSmall),
            for (final d in days)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.schedule),
                title: Text('${weekdayName(d)}, ${formatDate(d)}'),
                subtitle: Text(_lessonsText(ref, d, byDay[d]!)),
              ),
          ],
          const Divider(height: 32),
          Text('Uzasadnienie', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(e.reason.isEmpty ? '(bez uzasadnienia)' : e.reason),
          const SizedBox(height: 24),
          Text(
            'Librus nie udostępnia w tym widoku komentarza szkoły. Odpowiedź może przyjść '
            'jako wiadomość (zakładka Wiadomości).',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

/// Numery lekcji z nazwami przedmiotów z planu (gdy plan jest dostępny).
String _lessonsText(WidgetRef ref, DateTime day, List<int?> numbers) {
  final week = ref.watch(timetableWeekProvider(mondayOf(day))).value;
  final names = week == null
      ? const <int, String>{}
      : {for (final l in lessonsOn(week, day)) l.number: l.subjects};
  final sorted = [...numbers]..sort((a, b) => (a ?? 99).compareTo(b ?? 99));
  return sorted
      .map(
        (n) => n == null
            ? 'lekcja ?'
            : (names[n] == null ? 'lekcja $n' : '$n. ${names[n]}'),
      )
      .join('\n');
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value);

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
