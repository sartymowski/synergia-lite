import '../../../core/errors/synergia_exception.dart';
import '../../../core/network/synergia_api_client.dart';
import '../domain/excuse.dart';
import 'excuses_parser.dart';

/// Odczyt historii e-Usprawiedliwień przez istniejącą sesję Synergii.
///
/// Wysyłanie NIE jest tu zaimplementowane: przy loginie Synergii moduł
/// `/eusprawiedliwienia` odsyła do Konta LIBRUS (portal.librus.pl), a kontrakt
/// tamtejszego zapisu nie został ustalony (zob. docs/excuses.md). Nowe
/// zgłoszenia są wysyłane w oficjalnym module w WebView.
class ExcusesRepository {
  ExcusesRepository(this._api);

  final SynergiaApiClient _api;

  Future<List<ExcuseRequest>> fetchAll() async {
    try {
      return ExcusesParser.list(await _api.get('Justifications'));
    } on SessionExpiredException {
      // 401/403 na tym endpoincie może oznaczać brak modułu, a nie koniec
      // sesji — rozstrzyga odczyt Me (bez niepotrzebnego wylogowania).
      await _api.get('Me');
      throw const PermissionDeniedException();
    }
  }
}
