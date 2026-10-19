# Synergia Lite

Nieoficjalna, nowoczesna aplikacja na Androida (Flutter) do przeglądania
LIBRUS Synergia z istniejącego konta rodzica. Nie jest produktem Librusa.

> **Stan: etap A — prototyp integracji.** APK się buduje; integracja nie została
> jeszcze potwierdzona na żywym koncie. Szczegóły: [docs/integration-status.md](docs/integration-status.md).

## Jak to działa

- Logowanie odbywa się **na oficjalnej stronie Librusa** w osadzonym WebView —
  rozwiązanie **eksperymentalne** ([decisions D1](docs/decisions.md)). Aplikacja nie
  wstrzykuje skryptów i nie zapisuje hasła; CAPTCHA (Cloudflare Turnstile) i 2FA obsługuje Librus.
- Po zalogowaniu aplikacja przejmuje ciasteczka sesji Synergii, przechowuje je
  zaszyfrowane (Android Keystore) i czyta dane z JSON-owego API frontendu Synergii.
- Żadnego własnego serwera: połączenie wyłącznie telefon ↔ Librus.

## Wymagania

- Flutter 3.44+ (Dart 3.12+), Android SDK 36, JDK 21 (z Android Studio)
- Android 7.0+ (minSdk Fluttera)

## Uruchomienie

```powershell
flutter pub get
.\tool\flutter_android.ps1 run                # telefon z debugowaniem USB
.\tool\flutter_android.ps1 build apk --debug  # build\app\outputs\flutter-apk\app-debug.apk
```

`tool\flutter_android.ps1` jest potrzebny, gdy antywirus (np. Avast) przechwytuje HTTPS
(`PKIX path building failed`): daje Gradle osobny magazyn zaufania tylko na czas
procesu, bez wyłączania weryfikacji certyfikatów. Bez takiego antywirusa wystarczy `flutter run`.

Test na żywym koncie i diagnostyka: [checklista](docs/integration-status.md#checklista-ręcznej-weryfikacji).

## Testy i jakość

```sh
dart format lib test
flutter analyze
flutter test
```

Testy nie wymagają sieci ani danych logowania; fixture'y w `test/fixtures` są fikcyjne.

## Dokumentacja

- [docs/analysis.md](docs/analysis.md) — analiza Libruska, librus-api i mechanizmu logowania
- [docs/architecture.md](docs/architecture.md) — struktura aplikacji
- [docs/integration-status.md](docs/integration-status.md) — co działa, co niesprawdzone, jak testować
- [docs/decisions.md](docs/decisions.md) — decyzje techniczne i zależności
- [docs/messages-api.md](docs/messages-api.md) — moduł Wiadomości: kontrakt API i stan weryfikacji
- [docs/notifications.md](docs/notifications.md) — powiadomienia: audyt, dopuszczalność, gwarancje, checklista
- [docs/excuses.md](docs/excuses.md) — e-Usprawiedliwienia: mechanizm, stan weryfikacji, checklista

## Prywatność

Aplikacja nie loguje haseł, ciasteczek ani danych ucznia. Wylogowanie usuwa sesję,
ciasteczka, dane WebView oraz lokalne (zaszyfrowane) wiadomości robocze z telefonu.
Treść wiadomości jest wyświetlana bez WebView — bez JavaScriptu i bez pobierania obrazów.
