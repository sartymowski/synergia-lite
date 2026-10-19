import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../shared/format.dart';
import '../../../shared/widgets/async_states.dart';
import '../../timetable/domain/lesson.dart';
import '../domain/excuse_submission.dart';
import 'excuse_form_controller.dart';
import 'excuses_providers.dart';
import 'official_excuses_screen.dart';

/// Natywny formularz e-Usprawiedliwienia. Wysyłanie jest aktywne tylko przy
/// [ExcuseSubmitPolicy.nativeSubmitEnabled]; inaczej podsumowanie prowadzi do
/// oficjalnego formularza Librusa.
class ExcuseFormScreen extends ConsumerStatefulWidget {
  const ExcuseFormScreen({super.key});

  @override
  ConsumerState<ExcuseFormScreen> createState() => _ExcuseFormScreenState();
}

class _ExcuseFormScreenState extends ConsumerState<ExcuseFormScreen> {
  late final ExcuseFormController _c;

  @override
  void initState() {
    super.initState();
    _c = ExcuseFormController(submit: ref.read(excuseSubmitterProvider).submit)
      ..addListener(_changed);
  }

  void _changed() => setState(() {});

  @override
  void dispose() {
    _c
      ..removeListener(_changed)
      ..dispose();
    super.dispose();
  }

  DateTime get _today => DateUtils.dateOnly(DateTime.now());

  Future<void> _pickRange() async {
    final s = _c.submission;
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(_today.year - 1, 9),
      lastDate: DateTime(_today.year + 1, 8, 31),
      initialDateRange: s.from == null
          ? null
          : DateTimeRange(start: s.from!, end: s.to ?? s.from!),
      helpText: 'Wybrane dni',
    );
    if (range != null) _c.setRange(range.start, range.end);
  }

  Future<void> _pickDay() async {
    final day = await showDatePicker(
      context: context,
      firstDate: DateTime(_today.year - 1, 9),
      lastDate: DateTime(_today.year + 1, 8, 31),
      initialDate: _c.submission.from ?? _today,
      helpText: 'Dzień nieobecności',
    );
    if (day != null) _c.setDay(day);
  }

  void _openOfficial() => Navigator.of(context).pushReplacement(
    MaterialPageRoute<void>(builder: (_) => const OfficialExcusesScreen()),
  );

  String _rangeText(ExcuseSubmission s) {
    if (s.from == null) return 'nie wybrano';
    final to = s.effectiveTo!;
    return DateUtils.isSameDay(s.from, to)
        ? formatDate(s.from!)
        : '${formatDate(s.from!)} – ${formatDate(to)}';
  }

  Future<void> _summary(List<LessonChoice> lessons) async {
    if (!_c.validate()) return;
    final s = _c.submission;
    final student =
        ref.read(accountProvider).value?.studentFirstName ?? '(nieznany)';
    final chosen = [
      for (final l in lessons)
        if (s.lessonNumbers.contains(l.number)) '${l.number}. ${l.subjects}',
    ];
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Podsumowanie usprawiedliwienia'),
        content: SingleChildScrollView(
          child: Text(
            [
              'Uczeń: $student',
              'Zakres: ${s.mode == ExcuseMode.days ? 'wybrane dni' : 'lekcje w wybranym dniu'}, ${_rangeText(s)}',
              if (s.mode == ExcuseMode.lessons) 'Lekcje: ${chosen.join(', ')}',
              if (s.isPlanned(_today))
                'Planowana nieobecność${s.notifyTeachers ? ' — powiadom nauczycieli' : ''}',
              'Uzasadnienie: ${s.reason.trim()}',
              if (!_c.submitEnabled)
                '\nNatywne wysyłanie jest jeszcze nieaktywne (odpowiedź serwera Librusa nie została '
                    'potwierdzona). Wyślij w oficjalnym formularzu — dane trzeba tam wpisać ponownie.',
            ].join('\n'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Wróć'),
          ),
          if (_c.submitEnabled)
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Wyślij'),
            )
          else
            FilledButton(
              onPressed: () {
                Navigator.pop(context, false);
                _openOfficial();
              },
              child: const Text('Oficjalny formularz'),
            ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    var again = false;
    if (_c.needsConfirmationAfterUncertain) {
      again =
          await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Poprzednia próba mogła dotrzeć'),
              content: const Text(
                'Nie wiadomo, czy poprzednie zgłoszenie zostało przyjęte. Sprawdź historię — '
                'ponowne wysłanie może utworzyć duplikat.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Anuluj'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Wyślij mimo to'),
                ),
              ],
            ),
          ) ==
          true;
      if (!again || !mounted) return;
    }
    await _c.send(confirmedAfterUncertain: again);
    if (_c.status == ExcuseFormStatus.submitted) {
      ref.invalidate(excusesProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _c.submission;
    final problems = _c.problems.toSet();
    final scheme = Theme.of(context).colorScheme;
    String? err(Set<ExcuseProblem> of) {
      final p = problems.intersection(of);
      return p.isEmpty
          ? null
          : p.map((e) => excuseProblemMessages[e]).join(' ');
    }

    final week = s.mode == ExcuseMode.lessons && s.from != null
        ? ref.watch(timetableWeekProvider(mondayOf(s.from!)))
        : null;
    final lessons = week?.value == null
        ? const <LessonChoice>[]
        : lessonsOn(week!.value!, s.from!);
    final editable = _c.canEdit;

    return Scaffold(
      appBar: AppBar(title: const Text('Nowe usprawiedliwienie')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ?_statusCard(scheme),
          if (!_c.submitEnabled)
            Card(
              color: scheme.tertiaryContainer,
              child: ListTile(
                leading: const Icon(Icons.info_outline),
                title: const Text('Wysyłanie z aplikacji jeszcze nieaktywne'),
                subtitle: const Text(
                  'Formularz pozwala przygotować i sprawdzić zgłoszenie. Wysyłka — w oficjalnym '
                  'formularzu Librusa (przycisk „Nowe (Librus)”).',
                ),
                trailing: TextButton(
                  onPressed: _openOfficial,
                  child: const Text('Otwórz'),
                ),
              ),
            ),
          SegmentedButton<ExcuseMode>(
            segments: const [
              ButtonSegment(value: ExcuseMode.days, label: Text('Wybrane dni')),
              ButtonSegment(
                value: ExcuseMode.lessons,
                label: Text('Kilka lekcji w dniu'),
              ),
            ],
            selected: {s.mode},
            onSelectionChanged: editable ? (v) => _c.setMode(v.first) : null,
          ),
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.date_range),
            title: Text(s.mode == ExcuseMode.days ? 'Zakres dni' : 'Dzień'),
            subtitle: Text(
              _rangeText(s),
              style:
                  err({ExcuseProblem.noDates, ExcuseProblem.invalidRange}) ==
                      null
                  ? null
                  : TextStyle(color: scheme.error),
            ),
            trailing: TextButton(
              onPressed: editable
                  ? (s.mode == ExcuseMode.days ? _pickRange : _pickDay)
                  : null,
              child: const Text('Wybierz'),
            ),
          ),
          if (err({ExcuseProblem.noDates, ExcuseProblem.invalidRange})
              case final e?)
            Text(e, style: TextStyle(color: scheme.error)),
          if (s.mode == ExcuseMode.lessons && s.from != null) ...[
            Text(
              'Lekcje według planu',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            if (week!.isLoading) const LinearProgressIndicator(),
            if (week.hasError)
              ErrorView(
                error: week.error!,
                onRetry: () =>
                    ref.invalidate(timetableWeekProvider(mondayOf(s.from!))),
              ),
            if (week.hasValue && lessons.isEmpty)
              const Text('Brak lekcji w planie tego dnia.'),
            for (final l in lessons)
              CheckboxListTile(
                value: s.lessonNumbers.contains(l.number),
                onChanged: editable ? (_) => _c.toggleLesson(l.number) : null,
                title: Text('${l.number}. ${l.subjects}'),
                subtitle: l.canceled ? const Text('Odwołana w planie') : null,
              ),
            if (err({ExcuseProblem.noLessons}) case final e?)
              Text(e, style: TextStyle(color: scheme.error)),
          ],
          const SizedBox(height: 12),
          TextField(
            enabled: editable,
            minLines: 3,
            maxLines: null,
            maxLength: ExcuseSubmitPolicy.maxReasonLength,
            onChanged: _c.setReason,
            decoration: InputDecoration(
              labelText: 'Uzasadnienie',
              alignLabelWithHint: true,
              errorText: err({
                ExcuseProblem.noReason,
                ExcuseProblem.reasonTooLong,
              }),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            value: s.notifyTeachers,
            onChanged: editable && _c.canNotifyTeachers
                ? (v) => _c.setNotifyTeachers(v ?? false)
                : null,
            title: const Text('Powiadom nauczycieli o planowanej nieobecności'),
            subtitle: Text(
              _c.canNotifyTeachers
                  ? 'Dostępne dla nieobecności dziś lub w przyszłości.'
                  : 'Niedostępne dla nieobecności z przeszłości.',
            ),
          ),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.attach_file),
            title: Text('Załącznik'),
            subtitle: Text(
              'Dodanie załącznika jest możliwe tylko w oficjalnym formularzu Librusa.',
            ),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            icon: _c.isSending
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.preview),
            label: Text(_c.isSending ? 'Wysyłanie…' : 'Podsumowanie'),
            onPressed: _c.isSending || _c.status == ExcuseFormStatus.submitted
                ? null
                : () => _summary(lessons),
          ),
        ],
      ),
    );
  }

  Widget? _statusCard(ColorScheme scheme) => switch (_c.status) {
    ExcuseFormStatus.editing => null,
    ExcuseFormStatus.sending => const Card(
      child: ListTile(
        leading: CircularProgressIndicator(),
        title: Text('Wysyłanie… nie zamykaj ekranu.'),
      ),
    ),
    ExcuseFormStatus.submitted => Card(
      color: scheme.primaryContainer,
      child: ListTile(
        leading: const Icon(Icons.check_circle),
        title: Text(_c.message ?? 'Przyjęte.'),
      ),
    ),
    ExcuseFormStatus.notSent => Card(
      color: scheme.errorContainer,
      child: ListTile(
        leading: const Icon(Icons.error_outline),
        title: Text(_c.message ?? 'Nie wysłano.'),
      ),
    ),
    ExcuseFormStatus.uncertain => Card(
      color: scheme.tertiaryContainer,
      child: ListTile(
        leading: const Icon(Icons.help_outline),
        title: const Text('Nie wiadomo, czy zgłoszenie zostało przyjęte'),
        subtitle: Text(_c.message ?? ''),
        trailing: TextButton(
          onPressed: () {
            _c.acknowledgeUncertain();
            Navigator.of(context).pop();
          },
          child: const Text('Sprawdź historię'),
        ),
      ),
    ),
  };
}
