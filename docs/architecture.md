# Architektura

Feature-first, bez backendu: aplikacja łączy się z Synergią bezpośrednio z telefonu.

```
lib/
  main.dart                 ProviderScope bez automatycznych ponowień
  app/
    app.dart                MaterialApp.router, motyw jasny/ciemny
    router.dart             GoRouter: /splash, /login, / (przekierowania wg sesji)
    providers.dart          wiązanie zależności + AuthController
    home_screen.dart        powłoka: Oceny, Plan lekcji, Wiadomości (licznik nieprzeczytanych)
    theme.dart
  core/
    errors/                 SynergiaException (sealed) — komunikaty dla użytkownika
    network/
      session_cookies.dart  ciasteczka sesji, rotacja z Set-Cookie
      web_cookie.dart       ciasteczko z atrybutami (domena, ścieżka, flagi, wygaśnięcie)
      synergia_api_client.dart  klient gateway/api/2.0
      request_queue.dart    kolejka żądań z minimalnym odstępem
    storage/
      key_value_store.dart  zaszyfrowany magazyn klucz–wartość (szkice, stan powiadomień)
    security/
      session_store.dart    flutter_secure_storage / pamięć (testy)
  features/
    auth/
      data/                 AuthRepository, webview_session (adres startowy, filtr nawigacji,
                            kanał natywny do ciasteczek, czyszczenie)
      domain/               AccountInfo
      presentation/         LoginScreen (webview_flutter, eksperymentalnie — decisions D1)
    grades/
      data/                 GradesParser (JSON → domena), GradesRepository
      domain/               Grade, GradeCategory, Subject, Teacher, średnie, GradesOverview
      presentation/         GradesView
    timetable/
      data/ domain/ presentation/
    messages/
      data/                 MessagesApiClient (wiadomosci3, ciasteczka wiadomości w pamięci,
                            odnowienie sesji dla GET, POST bez ponowień), MessagesParser,
                            MessagesRepository (klasyfikacja wyniku wysyłki), DraftsStore
      domain/               MessageSummary, MessageDetail, MessageRecipient, MessageAttachment,
                            MessageDraft, MessageFolder, SendOutcome, bezpieczny parser treści
      presentation/         MessagesTab (Odebrane/Wysłane/Robocze), lista, szczegóły,
                            ComposeScreen + ComposeController, wybór odbiorców
    excuses/
      data/                 ExcusesParser, ExcusesRepository (GET Justifications)
      domain/               ExcuseRequest, ExcuseStatus (nieznane zachowane), ExcusePeriod,
                            ExcuseLesson, ExcuseFilter
      presentation/         lista z filtrami, szczegóły, oficjalny moduł w WebView
    notifications/
      data/                 MessageNotificationChecker (jedno sprawdzenie), stan synchronizacji,
                            LocalNotificationService, WorkManager (callbackDispatcher)
      domain/               detekcja nowych wiadomości, stan, payload, zasady (flaga tła)
      presentation/         SettingsScreen (Powiadomienia), providery, obsługa kliknięć
    diagnostics/
      data/                 IntegrationProbe (kontrola negatywna, Me, Grades, Timetables)
      domain/               DiagnosticReport — tylko struktura, bez wartości
      presentation/         DiagnosticsScreen (kopiowanie raportu)
  shared/
    json_read.dart          tolerancyjny odczyt (Id jako liczba lub tekst, lista lub obiekt)
    format.dart             daty i liczby po polsku
    widgets/                ErrorView, EmptyView
test/
  fixtures/                 wyłącznie fikcyjne dane
  helpers/fake_http.dart    adapter Dio bez sieci
  core/ features/
```

## Przepływ danych

```
LoginScreen (WebView, strona Librusa)
   └─ po zalogowaniu: CookieManager → SessionCookies
        └─ AuthRepository.completeLogin → SessionStore.write → GET Me (weryfikacja)

Widok → FutureProvider → Repository → SynergiaApiClient.get → gateway/api/2.0
                                     └─ Parser → modele domeny
```

- UI zna wyłącznie modele domeny; nazwy pól JSON żyją tylko w parserach `data/`.
- Błędy HTTP są mapowane na `SynergiaException` w jednym miejscu (`SynergiaApiClient`).
- `SessionExpiredException` z dowolnego providera → `AuthController.sessionExpired()`
  → usunięcie sesji → router przenosi na `/login` z komunikatem o wygaśnięciu.
- Parsery pomijają rekordy bez wymaganych pól, ale zgłaszają
  `UnexpectedResponseException`, gdy nie da się odczytać **żadnego** rekordu
  lub brakuje klucza głównego — żeby zmiana API nie wyglądała jak „brak ocen”.

## Świadomie pominięte w etapie A

Cache trwały i offline (etap E), dashboard i pozostałe moduły (etap D),
lokalizacja przez `intl`, powiadomienia.

## Część natywna (Android)

- `android/app/src/main/kotlin/.../MainActivity.kt` — kanał `pl.synergialite/cookies`:
  `getSynergiaCookies` (tylko `https://synergia.librus.pl/`) i `flush`.
- `AndroidManifest.xml`: `INTERNET`, `allowBackup=false`, `usesCleartextTraffic=false`.
- `tool/flutter_android.ps1` — uruchamianie Gradle przy przechwytywaniu HTTPS (decisions D9).
