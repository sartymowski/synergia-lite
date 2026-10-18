import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../domain/grade.dart';
import '../domain/grades_overview.dart';

class GradesView extends ConsumerWidget {
  const GradesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grades = ref.watch(gradesOverviewProvider);
    Future<void> refresh() => ref.refresh(gradesOverviewProvider.future);

    return grades.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: refresh),
      data: (overview) => RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            ListTile(
              leading: const Icon(Icons.sync),
              title: Text('Pobrano: ${formatDateTime(overview.fetchedAt)}'),
              subtitle: Text(
                '${overview.gradeCount} ocen z ${overview.subjects.length} przedmiotów',
              ),
            ),
            if (overview.subjects.isEmpty)
              const EmptyView(
                message:
                    'Synergia nie zwróciła żadnych ocen. Jeśli w Synergii '
                    'widzisz oceny, zgłoś to — może to oznaczać zmianę API.',
              ),
            for (final s in overview.subjects) _SubjectTile(subject: s),
          ],
        ),
      ),
    );
  }
}

class _SubjectTile extends StatelessWidget {
  const _SubjectTile({required this.subject});

  final SubjectGrades subject;

  @override
  Widget build(BuildContext context) {
    final semesters = subject.averageBySemester.keys.toList()..sort();
    final averages = [
      for (final sem in semesters)
        if (subject.averageBySemester[sem]!.value case final v?)
          'sem. $sem: ${formatAverage(v)}',
    ].join(' · ');
    return ExpansionTile(
      title: Text(subject.subject.name),
      subtitle: Text(
        averages.isEmpty
            ? '${subject.entries.length} ocen'
            : 'Śr. orientacyjna $averages',
      ),
      children: [
        for (final sem in semesters) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Semestr $sem',
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
          ),
          for (final e in subject.forSemester(sem)) _GradeRow(entry: e),
        ],
      ],
    );
  }
}

class _GradeRow extends StatelessWidget {
  const _GradeRow({required this.entry});

  final GradeEntry entry;

  static const _kindLabels = {
    GradeKind.semesterProposal: 'propozycja śródroczna',
    GradeKind.semester: 'ocena śródroczna',
    GradeKind.finalProposal: 'propozycja roczna',
    GradeKind.finalGrade: 'ocena roczna',
  };

  @override
  Widget build(BuildContext context) {
    final g = entry.grade;
    final scheme = Theme.of(context).colorScheme;
    final weight = entry.category?.weight;
    final details = [
      ?entry.category?.name,
      if (weight != null && entry.category!.countsToAverage) 'waga $weight',
      if (entry.category?.countsToAverage == false) 'nie liczy się do średniej',
      ?_kindLabels[g.kind],
      if (g.date != null) formatDate(g.date!),
      ?entry.teacher?.displayName,
    ].join(' · ');
    return ListTile(
      leading: Semantics(
        label: 'Ocena ${g.value}',
        excludeSemantics: true,
        child: CircleAvatar(
          backgroundColor: g.kind.isSummary
              ? scheme.tertiaryContainer
              : scheme.primaryContainer,
          child: Text(
            g.value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      ),
      title: Text(details.isEmpty ? 'Ocena' : details),
    );
  }
}
