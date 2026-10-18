/// Zasady synchronizacji w tle.
///
/// DOPUSZCZALNOŚĆ (2026-10-18, zob. docs/notifications.md): regulamin Synergii
/// v1.6 dopuszcza aplikacje zewnętrzne korzystające z API (§3 ust. 10) i zakazuje
/// tylko pobierania mogącego znacząco zdestabilizować serwery (§4 ust. 3c), ale
/// nie mówi wprost o okresowym, automatycznym sprawdzaniu. W oficjalnej
/// aplikacji natychmiastowe powiadomienia są płatnym dodatkiem, a wersja
/// darmowa odświeża dane ok. co 3 godziny. Status: NIEPOTWIERDZONY.
///
/// Dlatego okresowe zadanie jest domyślnie WYŁĄCZONE. Włączenie wymaga świadomej
/// decyzji przy budowaniu:
/// `flutter build apk --dart-define=SYNERGIA_BACKGROUND_SYNC=true`
abstract final class BackgroundSyncPolicy {
  static const allowed = bool.fromEnvironment('SYNERGIA_BACKGROUND_SYNC');

  /// Domyślny odstęp; minimum WorkManagera to 15 min, a Android i tak może
  /// opóźniać zadania (Doze, oszczędzanie baterii).
  static const interval = Duration(minutes: 30);

  /// Opóźnienie ponowienia po błędzie przejściowym (WorkManager, wykładniczo).
  static const backoffDelay = Duration(minutes: 10);
}
