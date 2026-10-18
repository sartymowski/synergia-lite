# Powiadomienia o nowych wiadomościach

Stan na **2026-10-18**. Lokalne powiadomienia Androida (bez FCM i własnego serwera).
**Sprawdzanie w tle jest domyślnie wyłączone** — patrz „Dopuszczalność”.
Działanie w tle **nie zostało potwierdzone na urządzeniu**.

## 1. Audyt sesji w tle (etap A)

| Pytanie | Ustalenie |
|---|---|
| Czy zadanie w tle odczyta sesję bez WebView? | **Tak.** Ciasteczka Synergii są w `flutter_secure_storage` (`SecureSessionStore`); klient wiadomości odtwarza swoją sesję z nich (`GET synergia.librus.pl/wiadomosci3`, MultiDomainLogon). WebView nie jest potrzebny. |
| Kontekst wykonania | WorkManager uruchamia zadanie w osobnym silniku Fluttera (izolat), a jednorazowe zadania mogą działać w głównym silniku. Zadanie nie korzysta z providerów, widżetów ani pamięci aplikacji — wszystko tworzy od nowa (`runBackgroundSync`). |
| Ryzyko znalezione w audycie | Inicjalizacja wiadomości w tle może zrotować `DZIENNIKSID` w magazynie, a główny klient aplikacji trzymał ciasteczka w pamięci → po 401 wylogowałby użytkownika. **Poprawka:** `SynergiaApiClient` przy 401/403/3xx raz porównuje ciasteczka z magazynem i ponawia zapytanie z aktualnymi (test regresyjny). |
| Hasło | Nie jest zapisywane; zadanie w tle nigdy się nie loguje. Wygasła sesja → monitorowanie wstrzymane, jedna informacja, czekamy na zalogowanie przez użytkownika. |
| Znaleziony błąd | `MessagesApiClient` nie przekazywał nagłówka `Retry-After` przy HTTP 429 — poprawione (test regresyjny). |
| Ustawienia | W aplikacji nie było ekranu ustawień — dodano minimalny (ikona koła zębatego) z sekcją „Powiadomienia”. |
| Środowisko | Flutter 3.44.2, Android compileSdk 36 / minSdk 24, Gradle 9.1, AGP 9.0.1, Kotlin 2.3.20. |

## 2. Dopuszczalność okresowego odpytywania (etap 2)

- Regulamin serwisu LIBRUS Synergia v1.6 (01.07.2024): §3 ust. 10 — nieodpłatny dostęp do
  API dla aplikacji zewnętrznych; §4 ust. 3c — zakaz „systematycznego i powtarzającego się
  pobierania danych z serwera mogącego znacząco zdestabilizować pracę serwerów”.
  O automatycznym, okresowym sprawdzaniu skrzynki regulamin nie mówi wprost.
- W oficjalnej aplikacji natychmiastowe powiadomienia push to **płatny dodatek**
  („Mobilne Dodatki”); wersja bezpłatna odświeża dane ok. co 3 godziny
  ([komputronik](https://nano.komputronik.pl/n/librus-co-to-jest-edziennik/),
  [interia](https://biznes.interia.pl/finanse/news-platny-librus-i-eduvulcan-tak-mozesz-skorzystac-z-dziennikow,nId,23525131)).
- Obciążenie przy włączeniu: jedno sprawdzenie ≈ 5 żądań (`wiadomosci3` + 2 przekierowania,
  `me`, `inbox/messages`), domyślnie co ~30 min → ok. 240 żądań/dobę na konto.
  Okresowe sprawdzanie prawdopodobnie podtrzymuje też sesję Synergii (jak aktywne
  korzystanie) — niezweryfikowane.
- **Ocena: niejasne / niepotwierdzone.** Zgodnie z decyzją użytkownika (2026-10-18)
  okresowe zadanie jest **wyłączone** flagą kompilacji; przełącznik w ustawieniach jest
  nieaktywny z objaśnieniem. Rekomendacja: zapytać Librusa (librus@librus.pl) o zgodę
  i dopuszczalny interwał.
- Włączenie po potwierdzeniu (bez zmian w kodzie):
  `.\tool\flutter_android.ps1 build apk --debug --dart-define=SYNERGIA_BACKGROUND_SYNC=true`
  (stała `BackgroundSyncPolicy.allowed`). Build bez flagi samoczynnie wyrejestrowuje zadanie,
  gdyby zostało po buildzie z flagą.

## 3. Architektura

```
WorkManager (co ~30 min, sieć wymagana)        Ustawienia → „Sprawdź teraz (debug)”
        │ callbackDispatcher                              │
        ▼                                                 ▼
  runBackgroundSync ──────────────►  MessageNotificationChecker.run(trigger)
        │ (anuluje zadanie, gdy:              │ 1. kontrole lokalne (bez sieci): ustawienia,
        │  brak sesji / wyłączone /           │    sesja, uprawnienie, przerwa po 429, blokada
        │  wygasła sesja)                     │ 2. GET me → właściciel (konto)
        ▼                                     │ 3. GET inbox/messages (do 3 stron, gdy cała
  SyncScheduler (WorkmanagerSyncScheduler)    │    strona jest nowa)
                                              │ 4. detectNewMessages (czysta funkcja)
                                              │ 5. ponowna kontrola (wylogowanie?) → zapis stanu
                                              │ 6. ponowna kontrola → MessageNotifier.showNewMessages
                                              ▼
       MessageSyncStateRepository / NotificationSettingsRepository  (flutter_secure_storage)
       LocalNotificationService (flutter_local_notifications, kanał synergia_messages)
```

| Komponent | Plik |
|---|---|
| Wykrywanie (czyste) | `lib/features/notifications/domain/new_message_detector.dart` |
| Stan synchronizacji | `domain/sync_state.dart`, `data/sync_state_repository.dart` |
| Jedno uruchomienie | `data/message_notification_checker.dart` |
| Powiadomienia Androida | `data/local_notification_service.dart` |
| WorkManager + punkt wejścia | `data/background_sync.dart` |
| Zasady (flaga, interwał) | `domain/background_policy.dart` |
| Payload i identyfikatory | `domain/notification_intent.dart` |
| Ustawienia, uzgadnianie, kliknięcia | `presentation/settings_screen.dart`, `presentation/notifications_providers.dart`, `lib/app/home_screen.dart` |

Istniejące `MessagesRepository` i `MessagesApiClient` są używane bez duplikowania.

### Wykrywanie nowych wiadomości

- Pierwsza synchronizacja konta (włączenie przełącznika lub pierwsze „Sprawdź teraz”) zapisuje
  identyfikatory z pierwszej strony Odebranych — **bez powiadomień**.
- Nowa = identyfikator nieznany **i** data wysłania nie starsza niż najnowsza znana minus
  24 h (stara wiadomość przywrócona z kosza nie budzi alarmu).
- Status przeczytania jest ignorowany. Znane identyfikatory tylko przybywają (do 300
  najnowszych), więc pusta lub częściowa odpowiedź nie powoduje ponownych powiadomień.
- Błąd sieci, timeout, 5xx lub niepoprawna odpowiedź → stan bez zmian (nie „pusta skrzynka”).
- Jeśli cała strona to nowe wiadomości, doczytywane są kolejne (maks. 3 strony = 60).
- Wiadomości obejrzane w aplikacji (pierwsza strona Odebranych) są oznaczane jako znane.
- Stan jest przypisany do `accountId` z `me`; inne konto → nowy stan bazowy (bez powiadomień).

### Gwarancje dostarczenia

- **Co najwyżej jedno powiadomienie na wiadomość:** stan zapisywany jest **przed** pokazaniem;
  identyfikator powiadomienia jest deterministyczny (`FNV-1a(konto, id)`), więc nawet
  równoległe uruchomienie w innym kontekście zastępuje to samo powiadomienie zamiast tworzyć
  duplikat (`onlyAlertOnce`). W jednym izolacie równoległe wywołania dzielą wynik;
  między kontekstami działa miękka blokada (2 min).
- **Możliwa rzadka utrata** powiadomienia: awaria procesu między zapisem stanu a wyświetleniem.
  Wybrano ją świadomie zamiast ryzyka duplikatów.
- **Brak gwarancji terminu:** Android decyduje, kiedy uruchomić zadanie (Doze, oszczędzanie
  baterii, ograniczenia producenta). Brak dokładnych alarmów i usług pierwszoplanowych
  (uprawnienia FGS dokładane przez workmanager są usunięte z manifestu).
- Wiadomości, które przyszły, gdy brakowało uprawnienia lub trwała przerwa po 429, są zgłaszane
  przy najbliższym udanym sprawdzeniu (jeśli nie zostały obejrzane w aplikacji).

### Błędy w tle

| Sytuacja | Zachowanie |
|---|---|
| Brak sesji / wylogowany / powiadomienia wyłączone | zadanie anuluje się samo, bez zapytań |
| Wygasła sesja Synergii | wstrzymanie, anulowanie, **jedna** informacja „Powiadomienia wstrzymane” (kanał „Stan powiadomień”); wznowienie po zalogowaniu |
| HTTP 429 | przerwa wg `Retry-After` (1 min – 6 h; domyślnie 30 min), bez ponawiania |
| Sieć / timeout / 5xx / sesja wiadomości odrzucona | `Result.retry()` z wykładniczym backoffem od 10 min, maks. 3 razy z rzędu |
| Niepoprawna odpowiedź / 403 / inne 4xx | bez ponawiania, czekamy na zwykły termin |

### Powiadomienia i kliknięcia

- Kanał `synergia_messages` „Nowe wiadomości”. Jedna: „Nowa wiadomość w Synergii” / „Masz
  nową wiadomość.”; kilka: „Masz N nowe/nowych wiadomości w Synergii.” Bez nadawcy, tematu
  i treści; widoczność `private`.
- Payload: `{"v":1,"k":"m","o":<skrót konta>,"id":<id>}` — bez ciasteczek i tokenów.
- Zimny start: `getNotificationAppLaunchDetails`; ciepły start / wznowienie:
  `onDidReceiveNotificationResponse`. Cel czeka w providerze do zalogowania (gdy sesja
  wygasła, po zalogowaniu nawigacja jest wykonywana, jeśli konto się zgadza; inne konto →
  tylko Odebrane).

### Wylogowanie

Anulowanie zadania, usunięcie ustawień i stanu synchronizacji, usunięcie wyświetlonych
powiadomień — przed usunięciem sesji. Trwające zadanie sprawdza sesję, ustawienia i stan
tuż przed zapisem i przed pokazaniem powiadomienia, więc nie pokaże spóźnionego powiadomienia.

## 4. Zależności

| Pakiet | Wersja | Licencja | Uwagi |
|---|---|---|---|
| workmanager | 0.10.10 | MIT | wymaga Flutter ≥ 3.38 |
| flutter_local_notifications | 22.3.2 | BSD-3-Clause | wymaga desugaringu (`desugar_jdk_libs` 2.1.4) i compileSdk ≥ 35 |

Build zgłasza ostrzeżenie o migracji wtyczek do „Built-in Kotlin” — informacyjne, nie blokuje.
Nowe artefakty Gradle wymagają `tool\flutter_android.ps1` przy przechwytywaniu HTTPS przez Avast.

## 5. Checklista na telefonie

### Część 1 — teraz (wersja domyślna, tło wyłączone)

- [ ] Ikona koła zębatego → Ustawienia → „Powiadomienia”: przełącznik nieaktywny z objaśnieniem.
- [ ] „Uprawnienie Androida” → „Nadaj” → systemowe okno → zezwól.
- [ ] „Sprawdź teraz (debug)” → „Pierwsza synchronizacja: zapamiętano N wiadomości, bez
      powiadomień.” — **brak** powiadomień o starych wiadomościach.
- [ ] Ponownie „Sprawdź teraz” → „Brak nowych wiadomości.”
- [ ] Poproś uprawnioną osobę o wiadomość testową (albo poczekaj na nową). **Nie otwieraj jej
      w aplikacji** (otwarcie listy Odebranych oznacza ją jako znaną).
- [ ] „Sprawdź teraz” → powiadomienie „Nowa wiadomość w Synergii / Masz nową wiadomość.”
      (bez nadawcy i tematu, także na ekranie blokady).
- [ ] Zminimalizuj aplikację, kliknij powiadomienie → otwiera się ta wiadomość.
- [ ] Zamknij aplikację (usuń z ostatnich), kliknij inne powiadomienie testowe → aplikacja
      startuje i otwiera wiadomość.
- [ ] „Sprawdź teraz” jeszcze raz → brak ponownego powiadomienia.
- [ ] Wyloguj → po zalogowaniu „Ostatnia udana synchronizacja: Jeszcze nie było”.

### Część 2 — dopiero po potwierdzeniu dopuszczalności (build z flagą)

`.\tool\flutter_android.ps1 build apk --debug --dart-define=SYNERGIA_BACKGROUND_SYNC=true`
i `adb install -r build\app\outputs\flutter-apk\app-debug.apk`.

1. [ ] Włącz „Powiadomienia o nowych wiadomościach” (prośba o uprawnienie, jeśli brak).
2. [ ] Uprawnienie przyznane; „Ostatnia udana synchronizacja” = teraz (stan bazowy).
3. [ ] Brak powiadomień historycznych.
4. [ ] Nowa wiadomość na koncie (od uprawnionej osoby).
5. [ ] Wykrycie po okresowym sprawdzeniu (do ~30–45 min; Android może opóźnić). Do testu można
       wymusić zadanie: `adb shell dumpsys jobscheduler | findstr synergia` → numer zadania →
       `adb shell cmd jobscheduler run -f pl.synergialite.synergia_lite <numer>` (jednorazowo,
       nie w pętli).
6. [ ] Powiadomienie po zminimalizowaniu aplikacji.
7. [ ] Po **usunięciu z listy ostatnich** sprawdzanie działa dalej. Uwaga: **„Wymuś
       zatrzymanie”** w ustawieniach Androida wstrzymuje zadania do ponownego uruchomienia
       aplikacji — to oczekiwane zachowanie systemu.
8. [ ] Po restarcie telefonu (WorkManager przywraca zadanie) — sprawdzanie wraca.
9. [ ] Kliknięcie powiadomienia otwiera wiadomość.
10. [ ] Brak powtórnych powiadomień o tej samej wiadomości.
11. [ ] Wylogowanie → `adb shell dumpsys jobscheduler | findstr synergia` nie pokazuje zadania
        aplikacji; brak kolejnych powiadomień.

Zgłoś tylko wynik i ewentualne komunikaty z ekranu Ustawień — bez treści wiadomości.
