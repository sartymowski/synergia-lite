import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../domain/lesson.dart';

class TimetableView extends ConsumerStatefulWidget {
  const TimetableView({super.key});

  @override
  ConsumerState<TimetableView> createState() => _TimetableViewState();
}

class _TimetableViewState extends ConsumerState<TimetableView> {
  DateTime _monday = mondayOf(DateTime.now());

  void _shift(int weeks) => setState(
    () => _monday = DateTime(
      _monday.year,
      _monday.month,
      _monday.day + 7 * weeks,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final provider = timetableWeekProvider(_monday);
    final week = ref.watch(provider);
    Future<void> refresh() => ref.refresh(provider.future);
    final sunday = DateTime(_monday.year, _monday.month, _monday.day + 6);

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Poprzedni tydzień',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _shift(-1),
            ),
            Expanded(
              child: Text(
                '${formatDate(_monday)} – ${formatDate(sunday)}',
                textAlign: TextAlign.center,
              ),
            ),
            IconButton(
              tooltip: 'Następny tydzień',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _shift(1),
            ),
          ],
        ),
        Expanded(
          child: week.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: refresh),
            data: (w) => RefreshIndicator(
              onRefresh: refresh,
              child: w.isEmpty
                  ? ListView(
                      children: const [
                        EmptyView(message: 'Brak lekcji w tym tygodniu.'),
                      ],
                    )
                  : ListView(
                      children: [
                        for (final day in w.days.keys.toList()..sort())
                          if (w.days[day]!.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                              child: Text(
                                '${weekdayName(day)}, ${formatDate(day)}',
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            for (final l in w.days[day]!)
                              _LessonTile(lesson: l),
                          ],
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LessonTile extends StatelessWidget {
  const _LessonTile({required this.lesson});

  final Lesson lesson;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = [
      lesson.startTime,
      lesson.endTime,
    ].whereType<String>().join('–');
    final details = [
      if (time.isNotEmpty) time,
      ?lesson.teacherName,
      if (lesson.classroom != null) 'sala ${lesson.classroom}',
    ].join(' · ');
    final status = [
      if (lesson.isCanceled) 'Odwołana',
      if (lesson.isSubstitution) 'Zastępstwo',
      if (lesson.originalSubjectName != null)
        'zamiast: ${lesson.originalSubjectName}',
      if (lesson.originalTeacherName != null)
        'za: ${lesson.originalTeacherName}',
      ?lesson.substitutionNote,
    ].join(' · ');
    return ListTile(
      leading: CircleAvatar(child: Text('${lesson.lessonNo}')),
      title: Text(
        lesson.subjectName,
        style: lesson.isCanceled
            ? const TextStyle(decoration: TextDecoration.lineThrough)
            : null,
      ),
      subtitle: Text(
        [details, status].where((s) => s.isNotEmpty).join('\n'),
        style: status.isNotEmpty ? TextStyle(color: scheme.error) : null,
      ),
    );
  }
}
