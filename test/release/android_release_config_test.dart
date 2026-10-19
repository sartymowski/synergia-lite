import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Strażnicy konfiguracji wydania — regresje tu oznaczałyby wyciek sesji
/// (kopia zapasowa, ruch jawnym tekstem) albo wydanie podpisane kluczem debug.
void main() {
  String read(String path) => File(path).readAsStringSync();

  test('manifest: bez kopii zapasowej, tylko HTTPS, konfiguracja sieci', () {
    final manifest = read('android/app/src/main/AndroidManifest.xml');
    expect(manifest, contains('android:allowBackup="false"'));
    expect(manifest, contains('android:fullBackupContent="false"'));
    expect(manifest, contains('android:usesCleartextTraffic="false"'));
    expect(
      manifest,
      contains('android:networkSecurityConfig="@xml/network_security_config"'),
    );
    expect(manifest, isNot(contains('android:debuggable')));
  });

  test('konfiguracja sieci: bez cleartext i bez certyfikatów użytkownika', () {
    final config = read(
      'android/app/src/main/res/xml/network_security_config.xml',
    );
    expect(config, contains('cleartextTrafficPermitted="false"'));
    expect(config, contains('<certificates src="system" />'));
    expect(config, isNot(contains('src="user"')));
    expect(config, isNot(contains('<domain-config')));
  });

  test('gradle: release nigdy nie jest podpisywany kluczem debug', () {
    final gradle = read('android/app/build.gradle.kts');
    expect(gradle, isNot(contains('getByName("debug")')));
    expect(gradle, contains('signingConfigs.findByName("release")'));
    expect(gradle, contains('preReleaseBuild'));
    // Hasła tylko ze zmiennych środowiskowych, nie z plików projektu.
    expect(gradle, isNot(contains('getProperty("storePassword")')));
    expect(gradle, isNot(contains('getProperty("keyPassword")')));
  });

  test('gitignore: klucze i konfiguracja podpisu poza repozytorium', () {
    final ignore = '${read('.gitignore')}\n${read('android/.gitignore')}';
    for (final pattern in [
      '*.jks',
      '*.keystore',
      'key.properties',
      '*.p12',
      'release-signing.properties',
      '/dist/',
    ]) {
      expect(ignore, contains(pattern), reason: pattern);
    }
  });

  test('wersja w pubspec: nazwa + rosnący versionCode', () {
    final match = RegExp(
      r'^version: (\d+\.\d+\.\d+(?:-[0-9A-Za-z.]+)?)\+(\d+)$',
      multiLine: true,
    ).firstMatch(read('pubspec.yaml'));
    expect(match, isNotNull);
    // 1 = dotychczasowe buildy debug (1.0.0+1); wydania muszą być wyżej.
    expect(int.parse(match!.group(2)!), greaterThan(1));
  });
}
