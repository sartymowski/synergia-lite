# Synergia Lite

Nieoficjalna, nowoczesna aplikacja na Androida (Flutter) do przeglądania
LIBRUS Synergia z istniejącego konta rodzica. Nie jest produktem Librusa.

> **Stan: przygotowanie zamkniętej bety Android `1.0.0-beta.1`.** Logowanie, oceny, plan
> lekcji, wiadomości i historia e-Usprawiedliwień zweryfikowane na żywym koncie (zakres:
> [docs/integration-status.md](docs/integration-status.md)); gotowość i ryzyka:
> [docs/release-readiness.md](docs/release-readiness.md).

## Jak to działa

- Logowanie odbywa się **na oficjalnej stronie Librusa** w osadzonym WebView —
  rozwiązanie **eksperymentalne** ([decisions D1](docs/decisions.md)). Aplikacja nie
  wstrzykuje skryptów i nie zapisuje hasła; CAPTCHA (Cloudflare Turnstile) i 2FA obsługuje Librus.
- Po zalogowaniu aplikacja przejmuje ciasteczka sesji Synergii, przechowuje je
  zaszyfrowane (Android Keystore) i czyta dane z JSON-owego API frontendu Synergii.
- Żadnego własnego serwera: połączenie wyłącznie telefon ↔ Librus.

## Wymagania

- Flutter 3.44+ (Dart 3.12+), Android SDK 36, JDK 21 (z Android Studio)
- Android 7.0+ (minSdk Fluttera); iOS — jeszcze nie ([plan](docs/ios-porting-plan.md))

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

### Flagi buildu (fail-closed — brak flagi = wyłączone)

| `--dart-define` | Działanie | Build dla testerów |
|---|---|---|
| `SYNERGIA_BACKGROUND_SYNC=true` | sprawdzanie wiadomości w tle | wyłączone |
| `SYNERGIA_NATIVE_EXCUSE_SUBMIT=true` | wysyłanie e-Usprawiedliwień z formularza aplikacji | wyłączone |
| `SYNERGIA_DIAGNOSTICS=true` | ekran diagnostyki w buildzie release | wyłączone |
| `SYNERGIA_VERSION=…` | wersja w „O aplikacji” (ustawia skrypt wydania) | ustawiane |

W buildach debug diagnostyka, log nawigacji i `chrome://inspect` są dostępne zawsze;
w release zdalne debugowanie WebView jest zawsze wyłączone.

## Wydanie (APK release)

```powershell
.\tool\create_release_keystore.ps1   # jednorazowo: klucz wydań poza repozytorium
.\tool\build_release.ps1             # testy + podpisany APK + SHA-256 + manifest w dist\
```

Szczegóły (podpis, kopia zapasowa klucza, wersjonowanie, wycofanie wydania):
[docs/release.md](docs/release.md). Dokumenty dla testerów: [docs/beta/](docs/beta/).

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
- [docs/release.md](docs/release.md) — wydania Androida: podpis, wersje, dystrybucja, wycofanie
- [docs/release-readiness.md](docs/release-readiness.md) — audyt bezpieczeństwa i gotowość bety, kwestie formalne
- [docs/beta/](docs/beta/) — instalacja, aktualizacja, testy, znane problemy, prywatność, zgłoszenia (dla rodziców)
- [docs/ios-porting-plan.md](docs/ios-porting-plan.md) — plan wersji iOS (TestFlight)

## Prywatność

Aplikacja nie loguje haseł, ciasteczek ani danych ucznia. Wylogowanie usuwa sesję,
ciasteczka, dane WebView, lokalne (zaszyfrowane) wiadomości robocze i stan powiadomień
z telefonu. Brak analityki, reklam i własnego serwera. Szkic informacji dla testerów:
[docs/beta/privacy-policy-draft.md](docs/beta/privacy-policy-draft.md).
Treść wiadomości jest wyświetlana bez WebView — bez JavaScriptu i bez pobierania obrazów.
