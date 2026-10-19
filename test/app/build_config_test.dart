import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:synergia_lite/app/build_config.dart';
import 'package:synergia_lite/features/excuses/domain/excuse_submission.dart';
import 'package:synergia_lite/features/notifications/domain/background_policy.dart';
import 'package:synergia_lite/features/notifications/presentation/settings_screen.dart';

const _release = BuildConfig(
  debugBuild: false,
  diagnosticsDefine: false,
  backgroundSync: false,
  nativeExcuseSubmit: false,
  version: '1.0.0-beta.1+2',
);

void main() {
  test(
    'build release bez flag: narzędzia programisty i diagnostyka ukryte',
    () {
      expect(_release.diagnostics, isFalse);
      expect(_release.developerTools, isFalse);
      expect(_release.webViewDebugging, isFalse);
      expect(_release.experimentalFeatures, isEmpty);
    },
  );

  test(
    'fail-closed: bez --dart-define funkcje eksperymentalne są wyłączone',
    () {
      // Testy uruchamiane są bez flag — dokładnie jak build dla testerów.
      expect(BackgroundSyncPolicy.allowed, isFalse);
      expect(ExcuseSubmitPolicy.nativeSubmitEnabled, isFalse);
      expect(BuildConfig.current.backgroundSync, isFalse);
      expect(BuildConfig.current.nativeExcuseSubmit, isFalse);
      expect(BuildConfig.current.diagnosticsDefine, isFalse);
    },
  );

  test('jawnie włączona diagnostyka w release jest widoczna na liście', () {
    const config = BuildConfig(
      debugBuild: false,
      diagnosticsDefine: true,
      backgroundSync: false,
      nativeExcuseSubmit: true,
      version: '',
    );
    expect(config.diagnostics, isTrue);
    expect(config.webViewDebugging, isFalse, reason: 'nigdy w release');
    expect(config.experimentalFeatures, [
      'natywne wysyłanie e-Usprawiedliwień',
      'diagnostyka integracji',
    ]);
    expect(config.versionLabel, 'wersja deweloperska');
  });

  test('build debug: narzędzia programisty dostępne', () {
    const config = BuildConfig(
      debugBuild: true,
      diagnosticsDefine: false,
      backgroundSync: false,
      nativeExcuseSubmit: false,
      version: '',
    );
    expect(config.diagnostics, isTrue);
    expect(config.developerTools, isTrue);
    expect(config.experimentalFeatures, isEmpty);
  });

  testWidgets('„O aplikacji”: wersja, charakter nieoficjalny, brak flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AboutSection(config: _release)),
      ),
    );
    expect(find.text('Synergia Lite 1.0.0-beta.1+2'), findsOneWidget);
    expect(find.textContaining('niezwiązana z firmą Librus'), findsOneWidget);
    expect(find.textContaining('Wyłączone'), findsOneWidget);
  });
}
