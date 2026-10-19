import 'package:flutter/foundation.dart';

import '../features/excuses/domain/excuse_submission.dart';
import '../features/notifications/domain/background_policy.dart';

/// Funkcje zależne od rodzaju buildu (docs/release.md). Zasada fail-closed:
/// brak `--dart-define` oznacza wyłączenie; build release dla testerów
/// (tool/build_release.ps1) nie przekazuje żadnej z flag.
class BuildConfig {
  const BuildConfig({
    required this.debugBuild,
    required this.diagnosticsDefine,
    required this.backgroundSync,
    required this.nativeExcuseSubmit,
    required this.version,
  });

  /// Konfiguracja tego buildu.
  static const current = BuildConfig(
    debugBuild: kDebugMode,
    diagnosticsDefine: bool.fromEnvironment('SYNERGIA_DIAGNOSTICS'),
    backgroundSync: BackgroundSyncPolicy.allowed,
    nativeExcuseSubmit: ExcuseSubmitPolicy.nativeSubmitEnabled,
    version: String.fromEnvironment('SYNERGIA_VERSION'),
  );

  final bool debugBuild;
  final bool diagnosticsDefine;
  final bool backgroundSync;
  final bool nativeExcuseSubmit;

  /// Wersja z pubspec.yaml przekazana przez skrypt wydania (pusta w buildach
  /// deweloperskich).
  final String version;

  /// Ekran „Diagnostyka integracji” pokazuje strukturę sesji (nazwy
  /// ciasteczek, kody odpowiedzi) — tylko dla programisty.
  bool get diagnostics => debugBuild || diagnosticsDefine;

  /// Log nawigacji logowania, przycisk „Sprawdź teraz”, chrome://inspect.
  bool get developerTools => debugBuild;

  /// Zdalne debugowanie WebView (dostęp do ciasteczek przez USB) — nigdy
  /// w buildach release.
  bool get webViewDebugging => debugBuild;

  String get versionLabel => version.isEmpty ? 'wersja deweloperska' : version;

  /// Włączone funkcje eksperymentalne (do ekranu „O aplikacji”).
  List<String> get experimentalFeatures => [
    if (backgroundSync) 'sprawdzanie wiadomości w tle',
    if (nativeExcuseSubmit) 'natywne wysyłanie e-Usprawiedliwień',
    if (diagnosticsDefine && !debugBuild) 'diagnostyka integracji',
  ];
}
