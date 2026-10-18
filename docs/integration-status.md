# Stan integracji

Ostatnia aktualizacja: **2026-10-18** (etap A, iteracja 2).

## Podsumowanie

| Obszar | Stan |
|---|---|
| Przepływ logowania Librusa (start, przekierowania, Turnstile) | ✅ potwierdzony na żywo **bez logowania** |
| Format błędu bez sesji (`401 {"Status":"Error",…}`) | ✅ potwierdzony na żywo |
| Build debug APK | ✅ `build\app\outputs\flutter-apk\app-debug.apk` (przez `tool\flutter_android.ps1`) |
| Uruchomienie na urządzeniu | ❌ **nie wykonano** — brak podłączonego urządzenia i emulatora |
| Logowanie w WebView i przejęcie ciasteczek | ⚠️ zaimplementowane (eksperymentalnie), **niesprawdzone na żywym koncie** |
| Uwierzytelniona sesja w `gateway/api/2.0` | ⚠️ diagnostyka gotowa, **niesprawdzone** |
| Oceny / plan lekcji z żywego konta | ⚠️ parsery przetestowane na **fikcyjnych** danych; zgodność z Synergią **niesprawdzona** |
| Wygaśnięcie sesji | ⚠️ 401/403/3xx → wylogowanie lokalne i ekran logowania; czas życia sesji **nieznany** |
| Odświeżanie sesji (`/refreshToken`) | ❌ nie zaimplementowane (zachowanie niezweryfikowane) |

**Bramka jakości etapu A nadal nie jest spełniona.** Bloker: test na Twoim telefonie
z prawdziwym kontem. Wszystko, co jest do tego potrzebne, jest gotowe (sekcja „Checklista”).

## Build Androida (Avast) — rozwiązane bez osłabiania TLS

**Diagnoza:** certyfikat widziany dla `services.gradle.org` jest wystawiony przez
`CN=Avast Web/Mail Shield Root` (odcisk `8BEC05D91F13A5F5279C68AE921B76E5CD0B38C2`),
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
| Nawigacja | Główna ramka tylko `https://*.librus.pl` (i `about:blank`); inne adresy, `http:`, `intent:`, `file:`, `javascript:` są blokowane. Ramki podrzędne (Turnstile) bez ograniczeń. |
| Ustawienia WebView | `allowFileAccess=false`, `allowContentAccess=false`, geolokalizacja wyłączona, ciasteczka stron trzecich wyłączone (cały przepływ w głównej ramce na `librus.pl`). |
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

## Checklista ręcznej weryfikacji

Przygotowanie (komputer):
- [ ] Telefon z Androidem 7+, włączone „Debugowanie USB”, podłączony kablem
      (lub zainstaluj `app-debug.apk` ręcznie).
- [ ] `.\tool\flutter_android.ps1 run` w `D:\Synergia Lite` (albo `adb install`).

Logowanie (telefon):
- [ ] Ekran „Logowanie do Synergii” pokazuje formularz `api.librus.pl` (adres nie jest
      widoczny — to jedno z ograniczeń WebView).
- [ ] Zaloguj się kontem rodzica; jeśli pojawi się Turnstile lub 2FA — wykonaj je.
- [ ] Wynik: (a) przejście do „Oceny/Plan lekcji” albo (b) komunikat
      „Logowanie nie zostało dokończone” z przyciskiem „Diagnostyka”.

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

_Brak — oczekuje na test na Twoim telefonie._
