# Stan integracji

Ostatnia aktualizacja: **2026-10-18** (etap A zamknięty wg testu użytkownika; moduł Wiadomości).

## Podsumowanie

| Obszar | Stan |
|---|---|
| Przepływ logowania Librusa (start, przekierowania, Turnstile) | ✅ potwierdzony na żywo **bez logowania** |
| Format błędu bez sesji (`401 {"Status":"Error",…}`) | ✅ potwierdzony na żywo |
| Build debug APK | ✅ `build\app\outputs\flutter-apk\app-debug.apk` (przez `tool\flutter_android.ps1`) |
| Uruchomienie na urządzeniu | ✅ wg użytkownika (SM-S921B, Android 17) |
| Logowanie w WebView i przejęcie ciasteczek | ✅ **działa wg testu użytkownika** (eksperymentalne, D1) |
| Uwierzytelniona sesja w `gateway/api/2.0` | ✅ wg użytkownika (plan lekcji pobrany na żywo) |
| Plan lekcji z żywego konta | ✅ pobierany wg użytkownika; szczegółowe porównanie z Synergią — do potwierdzenia |
| Oceny z żywego konta | ⚠️ zapytanie bez błędów, ale konto ma **0 ocen** — parsowanie prawdziwych ocen niesprawdzone |
| Wiadomości — odczyt, odbiorcy | ⚠️ zaimplementowane; kontrakt potwierdzony na żywo przez librus-synergia (inne konto), **na Twoim koncie niesprawdzone** — diagnostyka gotowa |
| Wiadomości — odpowiedź w wątku | ⚠️ zaimplementowane; potwierdzone na żywo przez librus-synergia, **u Ciebie niesprawdzone** |
| Powiadomienia o nowych wiadomościach | ⚠️ zaimplementowane; **tło wyłączone** (dopuszczalność niepotwierdzona); na urządzeniu sprawdzono tylko start aplikacji i brak zarejestrowanego zadania — zob. `docs/notifications.md` |
| Wiadomości — nowa wiadomość (`POST messages`) | ⚠️ zaimplementowane wg JS Librusa; **nikt nie potwierdził na żywo** — test ręczny wg checklisty |
| Wygaśnięcie sesji | ⚠️ 401/403/3xx → wylogowanie lokalne i ekran logowania; czas życia sesji **nieznany** |
| Odświeżanie sesji (`/refreshToken`) | ❌ nie zaimplementowane (zachowanie niezweryfikowane) |

**Bramka etapu A** spełniona wg zgłoszenia użytkownika (logowanie + plan lekcji na żywych
danych). Wyniki zgłoszone przez użytkownika nie były obserwowane przez agenta.

## Build Androida (Avast) — rozwiązane bez osłabiania TLS

**Diagnoza:** certyfikat widziany dla `services.gradle.org` jest wystawiony przez
`CN=Avast Web/Mail Shield Root` (certyfikat generowany lokalnie przez Avasta),
zainstalowany w `LocalMachine\Root` i `CurrentUser\Root`. JDK z Android Studio
ma własny `cacerts` bez tego rootu → `PKIX path building failed`.

**Rozwiązanie:** `tool\flutter_android.ps1` tworzy osobny magazyn
`%LOCALAPPDATA%\SynergiaLite\gradle-truststore.p12` = domyślne rooty JDK + ten jeden
root skopiowany z magazynu Windows, i wskazuje go przez `JAVA_TOOL_OPTIONS` **tylko
w procesie builda**. Weryfikacja łańcucha i nazwy hosta pozostaje pełna. Nie są
zmieniane: `cacerts` JDK, `~/.gradle/gradle.properties`, ustawienia Avasta.
Magazyn jest odtwarzany, gdy zmieni się JDK albo root Avasta.

Odrzucone: `trustAll` / wyłączenie weryfikacji (osłabia TLS); `Windows-ROOT`
(działa dla wrappera Gradle, ale klient HTTP Gradle zgłasza „Windows-ROOT not found”);
modyfikacja `cacerts` JDK (trwała zmiana współdzielonej instalacji).
Alternatywa bez skryptu: wyjątek w Avaście dla `services.gradle.org`, `dl.google.com`,
`repo.maven.apache.org`, `plugins.gradle.org`, `storage.googleapis.com`.

Dodatkowo `android/gradle.properties`: `kotlin.incremental=false` — przyrostowe cache
Kotlina psują się na Windows, gdy projekt (D:) i pub cache (C:) są na różnych dyskach.

```powershell
.\tool\flutter_android.ps1 build apk --debug
.\tool\flutter_android.ps1 run            # z podłączonym telefonem
```

## Audyt autoryzacji (2026-10-18)

| Pytanie | Ustalenie |
|---|---|
| Czy aplikacja przechwytuje hasło? | Nie. Nie ma `runJavaScript`, `addJavaScriptChannel` ani odczytu pól. Hasło wpisuje się w formularz `api.librus.pl`. **Ograniczenie zasadnicze:** host WebView technicznie *mógłby* je odczytać, a użytkownik nie może tego zweryfikować — dlatego rozwiązanie jest eksperymentalne (D1). |
| Czy wykonuje niepotrzebny JS? | Poprzednio **tak**: `flutter_inappwebview` 6.1.5 bezwarunkowo wstrzykiwał do każdej strony polyfill Promise, most `window.flutter_inappwebview` (`addJavascriptInterface`), hook `print` i zdarzenia focus/blur. **Usunięty** na rzecz `webview_flutter` (zero wstrzykniętych skryptów). JavaScript strony jest włączony, bo wymaga go formularz i Turnstile. |
| Czy zapisuje dane logowania? | Aplikacja: nie. Android Autofill (menedżer haseł użytkownika) może zaproponować zapis — to decyzja użytkownika w jego menedżerze, nie aplikacji. Formularz WebView (`saveFormData`) jest wyłączony domyślnie od Androida 8. |
| Nawigacja | Główna ramka tylko `https://*.librus.pl` (i `about:blank`) — od 2026-10-18 egzekwowane **po rozpoczęciu ładowania** (obca strona → powrót na start), bo przechwytywanie psuło logowanie (D11). Ramki podrzędne (iframe logowania, Turnstile) bez ograniczeń. |
| Ustawienia WebView | `allowFileAccess=false`, `allowContentAccess=false`, geolokalizacja wyłączona, ciasteczka stron trzecich wyłączone (iframe logowania na subdomenach `librus.pl` to ten sam „site” co portal). |
| Odczyt ciasteczek | Kanał `pl.synergialite/cookies` w `MainActivity` zwraca wyłącznie ciasteczka dla `https://synergia.librus.pl/` (adres na sztywno w kodzie natywnym), z atrybutami przez `CookieManagerCompat.getCookieInfo`, gdy WebView to obsługuje. |
| Domena / ścieżka | Do API wysyłane są tylko ciasteczka hosta Synergii. Klient odrzuca ścieżki absolutne (`://`, `/…`, `..`), więc ciasteczka nie mogą trafić pod inny adres. `Set-Cookie` z obcą `Domain` jest ignorowane. Atrybut `Path` nie jest rozróżniany (wszystkie obserwowane ciasteczka mają `path=/`). |
| Czas życia | `DZIENNIKSID`/`SDZIENNIKSID` — sesyjne (obserwowane na żywo); `oauth_state` — `Max-Age=3600`; `oauth_token` — **nieznane** (pojawi się w raporcie diagnostyki). Przeterminowane `Expires`/`Max-Age=0`/`deleted` usuwa ciasteczko. O ważności decyduje serwer: 401 → ponowne logowanie. |
| Przechowywanie | Tylko pary nazwa=wartość w `flutter_secure_storage` (Keystore); `allowBackup=false`. Wylogowanie: `GET /wyloguj`, usunięcie sesji, ciasteczek WebView (+`flush`), cache i Web Storage. |
| Adresy z tokenami | `code`/`state` OAuth są tylko w adresie powrotu `/loguj/portalRodzina?…` — aplikacja go nie zapisuje ani nie pokazuje; diagnostyka używa `redactUrl` (bez zapytania i fragmentu). |
| Logi | Kod aplikacji niczego nie loguje (`print`/`debugPrint` nieużywane). |

### Porównanie z librus-api (PR #108, zgłoszenie #88)

- PR #108 (scalony 2026-09-18, wersja 2.18.x): zatrzymuje automatyczne przekierowania,
  żeby zachować `state`, wysyła formularz z `x-baner`, ręcznie przechodzi zweryfikowany
  łańcuch przekierowań (host + ścieżka) do Synergii. Autor sprawdził na żywo
  **konto rodzica** (tylko odczyt, nagłówki skrzynki). Testy przepływu usunięto na prośbę
  opiekuna.
- #88: zgłaszający potwierdził 2026-09-24, że 2.18.1 loguje i zwraca oceny, plan,
  ogłoszenia, wiadomości i dane konta — **na jednym z dwóch kont**.
- Wniosek dla nas: przepływ `portalRodzina` działa dla konta rodzica we wrześniu 2026;
  WebView przechodzi go tak jak przeglądarka, więc nie musimy odtwarzać kroków ani
  `x-baner`. librus-api czyta HTML, nie `gateway/api/2.0` — **działanie gateway
  z ciasteczkami z tego przepływu potwierdza tylko kod Libruska (marzec 2026)**.

## Diagnostyka (w aplikacji)

Ekran „Diagnostyka integracji” (ikona tarczy na ekranie głównym albo przycisk
„Diagnostyka” po nieudanym logowaniu) wykonuje ~7 zapytań:

1. ciasteczka WebView — nazwy i atrybuty, **bez wartości**;
2. **kontrola negatywna**: `Me` bez ciasteczek — oczekiwane 401;
3. `Me` z sesją — 200 **i** obiekt konta (`Account`/`User`);
4. `Auth/TokenInfo` — informacyjnie;
5. `Grades` + kategorie + przedmioty — liczby rekordów, nazwy pól, pokrycie słowników;
6. `Timetables` bieżącego tygodnia — liczba dni/lekcji/odwołań/zastępstw, nazwy pól.

Werdykt **„Sesja uwierzytelniona (potwierdzone)”** wymaga jednocześnie (2) = 401/403
i (3) = 200 z kontem. Sama obecność `oauth_token` nie wystarcza.
Raport zawiera wyłącznie kody HTTP, liczby, nazwy kluczy JSON i nazwy/atrybuty
ciasteczek — test `integration_probe_test.dart` sprawdza, że nie wycieka żadna wartość.

## Błąd: pętla portal ↔ logowanie (zgłoszony 2026-10-18) — przyczyna i poprawka

**Objaw:** WebView pokazywał `portal.librus.pl`; „Zaloguj” → `/rodzina/synergia/loguj`
wracało na stronę portalu, formularz się nie pojawiał.

**Przyczyny (potwierdzone analizą stron Librusa i kodu wtyczki):**

1. Formularz `api.librus.pl/OAuth/Authorization?client_id=46` (wariant `synergia.rodzina`)
   zawiera `redirectToPortalIfNotInIframe("https://portal.librus.pl/rodzina")` — gdy jest
   stroną główną (`self == top`), przekierowuje na portal. Działa wyłącznie w iframe
   `#caLoginIframe` strony `portal.librus.pl/rodzina/synergia/loguj`. Dodatkowo
   `breakFrameIfNotAllowedOrigin` wyrywa go z ramki, gdy `document.referrer` nie pochodzi
   z dozwolonego źródła — wtedy też ląduje na portalu. Nasz start z
   `synergia.librus.pl/loguj/portalRodzina` w głównej ramce nie mógł więc działać
   (curl tego nie pokazał, bo nie wykonuje JS).
2. `portal.librus.pl/rodzina/synergia/loguj` zwraca formularz tylko przy przejściu
   z portalu: z ciasteczkami portalu i `Referer` → **200**; bez `Referer` → **302 → /rodzina**
   (sprawdzone curl-em 2026-10-18).
3. `webview_flutter_android` po ustawieniu `onNavigationRequest` **anuluje każdą
   nawigację głównej ramki** (`shouldOverrideUrlLoading` → `true`) i po decyzji „navigate”
   wykonuje ją ponownie przez `loadUrl(url)` — bez `Referer`, jako nawigację przeglądarki.
   Kliknięcie „Zaloguj” stawało się więc żądaniem bez Referer → 302 → portal → pętla.

**Poprawka:**
- usunięty `onNavigationRequest` — nawigacja jest natywna (Referer, POST, przekierowania);
- ograniczenie do `https://*.librus.pl` egzekwowane w `onPageStarted`/`onPageFinished`/
  `onUrlChange`: obca strona → powrót na start + komunikat;
- start: `https://portal.librus.pl/rodzina` (oficjalna strona; użytkownik wybiera
  „Zaloguj” → LIBRUS Synergia). Odrzucono ręczne dokładanie nagłówka `Referer`, żeby wejść
  od razu na `/rodzina/synergia/loguj` — to podrabianie przejścia z portalu;
- detektor pętli: ta sama strona (host+ścieżka) ≥ 4 razy w 30 s → zatrzymanie
  automatycznych działań i czytelny komunikat;
- koniec logowania: (a) strona główna lub zmiana adresu na Synergię poza `/loguj`,
  albo (b) pojawienie się / zmiana ciasteczka `oauth_token` (lokalny odczyt co 2 s —
  logowanie odbywa się w iframe, którego nawigacji Android nie raportuje),
  albo (c) przycisk „Sprawdź logowanie”. Sesja jest zapisywana **dopiero po `Me` z kontem**;
- nieudane sprawdzenie **nie czyści już WebView** (wcześniej `completeLogin` kasował
  ciasteczka, w tym `oauth_state` trwającego logowania) i nie przeładowuje strony;
- debug: log nawigacji (ikona robaka na ekranie logowania, `adb logcat`, prefiks
  `[SynergiaNav]`) + `chrome://inspect` (`enableDebugging` tylko w debug).

**Audyt pozostałych punktów:**

| Sprawdzenie | Wynik |
|---|---|
| Anulowanie przekierowań OAuth | było (pkt 3) — usunięte |
| Ponowne ładowanie startu po przekierowaniu | brak; start ładowany przy utworzeniu kontrolera, „Zacznij od nowa” i po zamknięciu obcej strony |
| Błędne uznanie przekierowania za sukces | nie — tylko sygnał; decyduje `Me` z kontem |
| Nawigacja w trakcie `build` | brak; reakcje wyłącznie w callbackach WebView |
| Nowy kontroler przy przebudowie | nie — `late final` w `State`, tworzony raz |
| `target="_blank"` / `window.open` | wtyczka ma `supportMultipleWindows=true`; nowe okno ładuje URL w tym samym WebView (`loadUrl`) → podlega filtrowi głównej ramki. `onCreateWindow` nie jest wystawiony w API Darta |
| Przekierowania w ramkach | nieraportowane przez Androida (początkowe ładowanie iframe i 3xx); obsłużone sygnałem z ciasteczka |
| Ciasteczka | dozwolone (pierwszej strony); iframe `synergia`/`api.librus.pl` w `portal.librus.pl` to ten sam „site” — ciasteczka stron trzecich wyłączone; magazyn: globalny `CookieManager` WebView (ten sam, z którego czyta kanał natywny); brak czyszczenia w trakcie logowania |
| `onHttpError` | logowany kod HTTP i host+ścieżka (bez rozróżnienia ramki — API go nie podaje) |

**Weryfikacja na telefonie (2026-10-18, SM-S921B, Android 17, WebView 155):** debug APK
zainstalowany przez ADB; bezpośrednio po instalacji **Avast Mobile Security wyświetlił
„Malware found”** (`MalwareFoundActivity`) nad aplikacją — aplikacja nie wczytała strony,
więc odtworzenia na urządzeniu **nie przeprowadzono**. Na ekranie Avasta nic nie było
klikane — decyzja należy do właściciela telefonu (to niepodpisany build debug ładowany
spoza sklepu).

## Checklista ręcznej weryfikacji

Przygotowanie (komputer):
- [ ] Telefon z Androidem 7+, włączone „Debugowanie USB” (kablem lub bezprzewodowo).
- [ ] `.\tool\flutter_android.ps1 run` w `D:\Synergia Lite` (albo `adb install -r build\app\outputs\flutter-apk\app-debug.apk`).
- [ ] Jeśli Avast Mobile Security zgłosi aplikację — sprawdź, że chodzi o
      `pl.synergialite.synergia_lite`, i sam zdecyduj, czy ją dopuścić.
- [ ] (opcjonalnie) log na komputerze: `adb logcat -s flutter | findstr SynergiaNav`

Logowanie (telefon):
- [ ] Widać stronę `portal.librus.pl/rodzina`. Wybierz „Zaloguj” → LIBRUS Synergia.
- [ ] Pojawia się formularz „Zaloguj się do systemu Synergia” (w ramce strony portalu).
- [ ] Zaloguj się kontem rodzica; jeśli pojawi się Turnstile lub 2FA — wykonaj je.
- [ ] Wynik: (a) przejście do „Oceny/Plan lekcji” albo (b) komunikat
      „Synergia nie potwierdziła jeszcze sesji” — wtedy „Sprawdź logowanie”
      (ikona tarczy), a gdy nadal źle — „Diagnostyka”.
- [ ] Jeśli formularz się nie pojawia lub widzisz komunikat o pętli: ikona robaka →
      „Kopiuj log” i wklej log w rozmowie (zawiera tylko hosty, ścieżki, nazwy
      callbacków i kody HTTP — mimo to przejrzyj go przed wysłaniem).

Weryfikacja sesji:
- [ ] Otwórz „Diagnostyka integracji”. Werdykt to „Sesja uwierzytelniona (potwierdzone)”?
- [ ] „Kopiuj raport” i wklej go w rozmowie — raport nie zawiera danych osobowych,
      ale **przejrzyj go przed wysłaniem**.

Zgodność danych (porównaj z Synergią w przeglądarce, niczego nie przepisuj do rozmowy):
- [ ] liczba przedmiotów i ocen w semestrze;
- [ ] wartości, kategorie, wagi i daty kilku ocen;
- [ ] oceny śródroczne/propozycje oznaczone innym kolorem;
- [ ] średnie — „orientacyjne”, różnice zapisz jako „zgodne / różne o ok. X”;
- [ ] plan bieżącego i następnego tygodnia: godziny, sale, zastępstwa, odwołania.

Sesja i wylogowanie:
- [ ] Zamknij i otwórz aplikację — dane ładują się bez logowania?
- [ ] Po kilku godzinach bez użycia — czy pojawia się ekran „Sesja wygasła”? (zanotuj czas)
- [ ] „Wyloguj” → ekran logowania; ponowne logowanie wymaga hasła.

## Interpretacja wyników

| Objaw | Interpretacja / następny krok |
|---|---|
| Werdykt „uwierzytelniona” i dane zgodne | Bramka spełniona → etap B |
| Werdykt „uwierzytelniona”, dane niezgodne | Błąd parsera — nazwy pól z raportu wystarczą do poprawki |
| `Me` 401, `TokenInfo` 200 | Gateway wymaga innego kroku aktywacji — dodać go w `completeLogin` |
| `Me` 401, brak `oauth_token` | WebView nie dokończył przepływu OAuth (np. Konto LIBRUS, wybór dziecka) |
| Strona logowania się nie wczytuje / blokada WebView | Udokumentować bloker; Custom Tabs nie dają dostępu do ciasteczek |
| Kontrola negatywna ≠ 401 | Nie da się potwierdzić logowania przez `Me` — wybrać inny endpoint |

## Wyniki testów na żywym koncie


- 2026-10-18 (zgłoszenie użytkownika): logowanie działa; plan lekcji pobierany
  poprawnie; oceny pobierane bez błędów, konto nie ma jeszcze ocen.

## Wiadomości — checklista

Kontrakt i statusy endpointów: `docs/messages-api.md`.

**Krok 1 — odczyt (bez skutków ubocznych):**
- [ ] Zainstaluj nowy APK, zaloguj się, ikona tarczy „Diagnostyka integracji”.
- [ ] Sekcje „Wiadomości: …” mają `[OK]`: inicjalizacja, `me`, `unreadMessagesCount`,
      `inbox/messages`, `outbox/messages`, `receivers/types`. Diagnostyka **nie otwiera**
      wiadomości (nie oznacza ich jako przeczytanych) i niczego nie wysyła.
- [ ] „Kopiuj raport” → wklej w rozmowie (tylko nazwy pól, liczby, kody; przejrzyj przed wysłaniem).
- [ ] Zakładka „Wiadomości” → Odebrane: liczba, nadawcy, tematy, daty i oznaczenie
      nieprzeczytanych zgadzają się z Synergią; „Wczytaj starsze” działa.
- [ ] Otwórz jedną wiadomość (uwaga: zostanie oznaczona jako przeczytana — także w Synergii):
      treść, nadawca, data, załączniki (nazwy).
- [ ] Wysłane: lista i szczegóły (odbiorcy, status odczytu).
- [ ] „Nowa” → „Dodaj odbiorców”: grupy (Wychowawcy, Nauczyciele…), osoby, wyszukiwanie.
      **Na tym etapie niczego nie wysyłaj.**

**Krok 2 — jedna wiadomość testowa (tylko za Twoją decyzją):**
- [ ] Wybierz uprawnionego odbiorcę, który wie o teście (np. wychowawcę po uprzedzeniu).
- [ ] Temat np. „Test aplikacji — proszę zignorować”, krótka treść z polskimi znakami i nową linią.
- [ ] „Wyślij” → sprawdź treść dialogu → „Wyślij”. Nie wychodź z ekranu do wyniku.
- [ ] Wynik „Wiadomość została wysłana.” → otwórz Wysłane w aplikacji **i** w Synergii:
      jest dokładnie jedna kopia, temat i treść (polskie znaki, nowa linia) poprawne.
- [ ] Jeśli „Nie wiadomo, czy wiadomość została wysłana” → **nie ponawiaj**; „Sprawdź Wysłane”
      i zapisz, co widać.
- [ ] (Opcjonalnie, osobno) odpowiedź: otwórz wiadomość od odbiorcy → „Odpowiedz” →
      w Synergii odpowiedź jest w tym samym wątku.
- [ ] Kopie robocze: zacznij nową wiadomość, wyjdź → „Robocze” ją pokazuje; usuń ją.
- [ ] „Wyloguj” → po ponownym zalogowaniu folder „Robocze” jest pusty.

Zgłoś tylko wynik (zgodne / niezgodne / komunikat), bez treści wiadomości i danych osób.
