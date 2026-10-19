import 'package:dio/dio.dart';
import 'package:html/parser.dart' as html_parser;

import '../../../core/errors/synergia_exception.dart';
import '../../../core/network/synergia_api_client.dart';
import '../domain/excuse.dart';
import '../domain/excuse_submission.dart';
import 'excuses_repository.dart';

/// Wartości ze świeżo pobranej strony formularza (token jest jednorazowy/sesyjny
/// — nigdy nie zapisywany ani logowany).
class ExcuseFormContract {
  const ExcuseFormContract({required this.requestKey, required this.target});

  final String requestKey;
  final String target;

  static const formPath = 'eusprawiedliwienia/dodaj';
  static const formUrl = 'https://synergia.librus.pl/eusprawiedliwienia/dodaj';

  /// Sprawdza, że formularz ma DOKŁADNIE ustaloną strukturę (2026-10-19).
  /// Zwraca listę rozbieżności (puste = zgodny) — przy rozbieżności nic nie wysyłamy.
  static (ExcuseFormContract?, List<String>) parse(String html) {
    final doc = html_parser.parse(html);
    final form = doc.querySelector('form#formUsprawiedliwienie');
    if (form == null) {
      return (
        null,
        [
          html.contains('Brak dostępu')
              ? 'Brak dostępu do modułu'
              : 'brak formularza formUsprawiedliwienie',
        ],
      );
    }
    final problems = <String>[];
    if ((form.attributes['method'] ?? '').toLowerCase() != 'post') {
      problems.add('metoda formularza');
    }
    final action = Uri.tryParse(form.attributes['action'] ?? '');
    if (action == null ||
        (action.hasAuthority && action.host != 'synergia.librus.pl') ||
        !(action.path == '/eusprawiedliwienia/dodaj' ||
            (action.path.isEmpty && !action.hasAuthority))) {
      problems.add('adres formularza');
    }
    String? value(String name) =>
        form.querySelector('[name="$name"]')?.attributes['value'];
    final key = value('requestkey');
    final target = value('dodajUsprawiedliwienieDo');
    if (key == null || key.isEmpty) problems.add('brak requestkey');
    if (target == null || target.isEmpty) {
      problems.add('brak dodajUsprawiedliwienieDo');
    }
    final radios = form
        .querySelectorAll('input[name="datyLubLekcje"]')
        .map((e) => e.attributes['value'])
        .toSet();
    if (!radios.containsAll({'wgDat', 'wgGodzin'})) {
      problems.add('opcje datyLubLekcje');
    }
    for (final name in ['dataOd', 'dataDo']) {
      if (form.querySelector('input[name="$name"]') == null) {
        problems.add('pole $name');
      }
    }
    if (form.querySelector('textarea[name="powodNieobecnosci"]') == null) {
      problems.add('pole powodNieobecnosci');
    }
    if (form
            .querySelector('input[name="powiadomInnych"]')
            ?.attributes['value'] !=
        '1') {
      problems.add('pole powiadomInnych');
    }
    if (problems.isNotEmpty) return (null, problems);
    return (ExcuseFormContract(requestKey: key!, target: target!), const []);
  }

  /// Pola w kolejności formularza; bez załącznika (tylko w oficjalnym module).
  FormData toFormData(ExcuseSubmission s) {
    final from = isoDay(s.from!);
    final to = isoDay(s.effectiveTo!);
    return FormData()
      ..fields.addAll([
        MapEntry('requestkey', requestKey),
        MapEntry('dodajUsprawiedliwienieDo', target),
        MapEntry(
          'datyLubLekcje',
          s.mode == ExcuseMode.days ? 'wgDat' : 'wgGodzin',
        ),
        MapEntry('dataOd', from),
        MapEntry('dataDo', to),
        if (s.mode == ExcuseMode.lessons)
          for (final n in s.lessonNumbers.toList()..sort())
            MapEntry('usprawiedliwienie[$from][]', '$n'),
        MapEntry('powodNieobecnosci', s.reason.trim()),
        if (s.notifyTeachers) const MapEntry('powiadomInnych', '1'),
      ]);
  }
}

/// Jedna próba wysłania. NIGDY nie ponawia POST; przyjęcie potwierdza odczytem
/// historii (nowe zgłoszenie o tym samym zakresie), a nie kodem HTTP.
class ExcuseSubmitter {
  ExcuseSubmitter(
    this._api,
    this._history, {
    this.verifyDelay = const Duration(seconds: 2),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SynergiaApiClient _api;
  final ExcusesRepository _history;
  final Duration verifyDelay;
  final DateTime Function() _clock;

  Future<ExcuseSubmitOutcome> submit(ExcuseSubmission s) async {
    if (validateExcuse(s, today: _clock()).isNotEmpty) {
      return const ExcuseNotSent('Formularz zawiera błędy — nic nie wysłano.');
    }

    final List<ExcuseRequest> before;
    final ExcuseFormContract contract;
    try {
      before = await _history.fetchAll();
      final page = await _api.fetchPage(ExcuseFormContract.formPath);
      if (page.status != 200) {
        return ExcuseNotSent(
          'Strona formularza niedostępna (HTTP ${page.status}) — nic nie wysłano.',
        );
      }
      final (parsed, problems) = ExcuseFormContract.parse(page.body);
      if (parsed == null) {
        return ExcuseNotSent(
          'Formularz Librusa różni się od znanego (${problems.join(', ')}). Nic nie wysłano — '
          'użyj oficjalnego modułu.',
        );
      }
      contract = parsed;
    } on SynergiaException catch (e) {
      return ExcuseNotSent('${e.message} Nic nie wysłano.');
    }

    final ({int status, String? location, String body}) response;
    try {
      response = await _api.submitForm(
        ExcuseFormContract.formPath,
        contract.toFormData(s),
        referer: ExcuseFormContract.formUrl,
      );
    } on SessionExpiredException {
      return const ExcuseNotSent(
        'Sesja wygasła — nic nie wysłano. Zaloguj się ponownie.',
      );
    } on SubmitTransportException catch (e) {
      if (!e.requestMayHaveReachedServer) {
        return const ExcuseNotSent(
          'Brak połączenia z serwerem — nic nie wysłano.',
        );
      }
      return _verify(before, s, 'Połączenie przerwane po wysłaniu.');
    }

    final location = response.location == null
        ? null
        : Uri.tryParse(response.location!);
    final toLogin =
        location != null &&
        (location.path.startsWith('/loguj') ||
            location.host == 'portal.librus.pl' ||
            location.host == 'api.librus.pl');
    if (response.status == 401 || response.status == 403 || toLogin) {
      return const ExcuseNotSent(
        'Librus odrzucił sesję — zgłoszenie nie zostało przyjęte.',
      );
    }
    return _verify(before, s, 'Serwer odpowiedział (HTTP ${response.status}).');
  }

  /// Szuka nowego zgłoszenia o wysłanym zakresie (dwa odczyty, bez ponawiania POST).
  Future<ExcuseSubmitOutcome> _verify(
    List<ExcuseRequest> before,
    ExcuseSubmission s,
    String context,
  ) async {
    final known = before.map((e) => e.id).toSet();
    final from = DateTime(s.from!.year, s.from!.month, s.from!.day);
    final to = DateTime(
      s.effectiveTo!.year,
      s.effectiveTo!.month,
      s.effectiveTo!.day,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      if (attempt > 0) await Future<void>.delayed(verifyDelay);
      try {
        final after = await _history.fetchAll();
        for (final e in after) {
          final p = e.period;
          if (!known.contains(e.id) &&
              p != null &&
              p.from == from &&
              p.to == to) {
            return ExcuseSubmitted(e);
          }
        }
      } on SynergiaException {
        // odczyt historii nieudany — wynik niejednoznaczny
      }
    }
    return ExcuseUncertain(
      '$context Nowego zgłoszenia nie widać w historii. Nie wiadomo, czy zostało przyjęte — '
      'sprawdź historię (także w oficjalnym module) przed ponowną próbą.',
    );
  }
}
