# e-Usprawiedliwienia — integracja i stan weryfikacji

Stan na **2026-10-19**. Odczyt historii działa na Twoim koncie (8 zgłoszeń). Natywny
formularz jest gotowy, ale **natywne wysyłanie jest nieaktywne**: kontrakt żądania jest
ustalony, odpowiedź serwera nie (wymagałaby prawdziwego wysłania). Wysyłka — oficjalny
formularz („Nowe (Librus)”), który pozostaje pełnoprawną drogą.

## 0. Ustalenia z 2026-10-19 (Twoja sesja, tylko odczyt struktury)

Metoda: zdalne debugowanie WebView (tylko build debug) i skrypt odczytujący wyłącznie
strukturę DOM (metody, ścieżki, nazwy pól, nazwy nagłówków, długości tokenów) oraz
publiczne pliki JS strony. Żadnych wartości pól, tokenów ani danych ucznia.

| Element | Ustalenie |
|---|---|
| Adres przycisku „Nowe (Librus)” | `https://synergia.librus.pl/eusprawiedliwienia` (lista), formularz: `/eusprawiedliwienia/dodaj` |
| Technologia | klasyczny formularz HTML Synergii (jQuery); **nie** JSON API, **nie** Konto LIBRUS |
| Wysyłka | `POST /eusprawiedliwienia/dodaj`, `multipart/form-data`, pełne przesłanie formularza (`$("#formUsprawiedliwienie").submit()` w `eusprawiedliwienia_rodzic.js`) |
| Pola | `requestkey` (ukryty token, 72 znaki), `dodajUsprawiedliwienieDo` (ukryte, obecnie `1`), `datyLubLekcje` = `wgDat` / `wgGodzin`, `dataOd`, `dataDo` (RRRR-MM-DD), `usprawiedliwienie[RRRR-MM-DD][]` = numery lekcji, `powodNieobecnosci`, `attachment` (1 plik), `powiadomInnych` = `1` |
| Lekcje | AJAX `POST /eusprawiedliwienia_rodzic_godziny` (`dataOd`) zwraca fragment HTML z checkboxami 1–10; lekcje spoza planu dnia są zablokowane |
| CSRF | AJAX: nagłówek `requestkey` (`CsrfProtection.js`); formularz: pole `requestkey` |
| Walidacja strony | tryb wybrany; obie daty; `dataOd ≤ dataDo`; w trybie lekcji ≥ 1 lekcja i `dataDo = dataOd`; uzasadnienie **nie** jest wymagane przez stronę |
| Planowana nieobecność | `powiadomInnych` aktywne tylko gdy data (koniec zakresu / dzień) ≥ dziś |
| Potwierdzenie (`autoAkceptacja=1`) | dialog „Czy na pewno wysłać…” — u Ciebie `0` |
| Statusy (filtr listy) | `1` wysłane, `2` usprawiedliwione, `3` odrzucone; API: `send` = wysłane, `accept` = usprawiedliwione (**potwierdzone Twoim porównaniem**); wartość API dla „odrzucone” — nieznana |
| **Odpowiedź serwera** | ❌ nieznana (nie wysłano niczego) |

## Natywne wysyłanie (zaimplementowane, nieaktywne)

- Przy każdej próbie: odczyt historii → świeży `GET /eusprawiedliwienia/dodaj` → **ścisła
  kontrola struktury** formularza (inna struktura = nic nie wysyłamy) → token i stałe ze
  strony → **jeden** `POST` (bez ponowień) → potwierdzenie **wyłącznie** przez nowe
  zgłoszenie o tym samym zakresie w historii (2 odczyty). Sam kod HTTP nie jest dowodem.
- Wyniki: przyjęte / nie wysłano (zmieniony formularz, brak dostępu, odrzucona sesja,
  brak połączenia przed wysłaniem) / **nie wiadomo** (timeout po wysłaniu, 4xx/5xx bez
  nowego wpisu) — wtedy kolejna próba wymaga potwierdzenia.
- Załączniki: tylko w oficjalnym formularzu.
- Uzasadnienie wymagane przez aplikację (strona go nie wymusza); limit aplikacji 2000 znaków.
- Włączenie po Twojej decyzji o pierwszym teście:
  `flutter build apk --debug --dart-define=SYNERGIA_NATIVE_EXCUSE_SUBMIT=true`.
  Niezweryfikowane: czy brak części `attachment` w żądaniu jest akceptowany, czy token jest
  jednorazowy, jak wygląda odpowiedź przy błędzie walidacji.

## 1. Mechanizm (etap A, pierwotna analiza)

| Element | Ustalenie | Źródło / status |
|---|---|---|
| Gdzie w Librusie | web: górne menu Synergii „e-Usprawiedliwienia”, zielony przycisk „Wyślij usprawiedliwienie”; aplikacja: menu (wymaga Konta LIBRUS; „Mobilne dodatki”) | [artykuł Librusa](https://portal.librus.pl/rodzina/artykuly/jak-sprawnie-wysylac-e-usprawiedliwienia) |
| Rodzaje zgłoszeń | „Wybrane dni” (zakres dat) albo „Kilka godzin w wybranym dniu” (lekcje); można zgłosić planowaną nieobecność | artykuł (bez szczegółów technicznych) |
| Statusy w UI | „usprawiedliwione”, „odrzucone” | artykuł |
| **Odczyt historii** | `GET synergia.librus.pl/gateway/api/2.0/Justifications`, koperta `{"status":"OK","message","data":[…]}`; rekord: `id`, `messageFromParent`, `postDate`, `justificationStatus`, `dateFrom`, `dateTo`, `lessons[{number,date}]`, `justifiedAbsences`, `attachment`, `notifiedTeachers[{name}]` | ✅ librus-synergia (MIT), na żywo 2026-10-07; **u Ciebie ❌ niesprawdzone** |
| Wartości statusu | na żywo widziano **tylko `accept`** | jw.; inne wartości aplikacja pokazuje dosłownie („Status: …”), bez zgadywania |
| Szczegóły | brak osobnego endpointu; szczegóły = rekord z listy; brak pola z komentarzem szkoły | jw. |
| Strona `/eusprawiedliwienia` | bez sesji: „Brak dostępu” + link `/loguj/przenies/eusprawiedliwienia` → 302 `portal.librus.pl` (✅ sprawdzone przeze mnie bez logowania); z loginem Synergii również „Brak dostępu” | librus-synergia 2026-10-15 (tylko odczyt) |
| **Wysyłanie** | moduł działa w **Koncie LIBRUS** (portal), nie w Synergii; żądania, pola, CSRF i potwierdzenie — **nieznane, nikt ich nie zbadał** | ❌ |
| Librusek, librus-api, librus-rs | brak obsługi e-Usprawiedliwień | sprawdzone 2026-10-19 |

Wniosek: odczyt — natywnie przez istniejącą sesję; **zapis — rozwiązanie awaryjne:
oficjalny moduł w WebView** (formularz, CSRF, walidacja i potwierdzenie po stronie
Librusa; aplikacja nie czyta pól i nie wstrzykuje skryptów). Po powrocie aplikacja
odczytuje historię i porównuje identyfikatory, żeby potwierdzić przyjęcie zgłoszenia.

Natywny formularz (dni / lekcje / planowana nieobecność / podgląd) **nie został
zbudowany**: bez kontraktu zapisu nie miałby czego wysłać, a bramka odczytu nie jest
jeszcze spełniona. Domenowe `ExcuseSubmission` też celowo nie istnieje.

## 2. Jak ustalić kontrakt na Twojej sesji (bezpiecznie)

Diagnostyka (ikona tarczy) ma dwa nowe kroki tylko do odczytu:

- **„e-Usprawiedliwienia: Justifications”** — koperta, liczba zgłoszeń, wartości statusu,
  nazwy pól (bez uzasadnień i dat).
- **„e-Usprawiedliwienia: strona /eusprawiedliwienia”** — kod HTTP, czy „Brak dostępu”,
  ścieżki i metody formularzy oraz **nazwy** pól (ukryte oznaczone; wartości, w tym
  tokeny CSRF, nigdy nie trafiają do raportu).

Jeśli strona przy Twojej sesji pokazuje formularz (a nie „Brak dostępu”), raport pozwoli
zaprojektować natywny zapis; jego pierwsze wysłanie i tak wymagałoby Twojej zgody.

## 3. Bezpieczeństwo

- Moduł wykonuje wyłącznie żądania **GET** (test); brak POST w kodzie aplikacji.
- 401/403 na `Justifications` przy działającej sesji (sprawdzane przez `Me`) → „moduł
  niedostępny”, a nie wylogowanie.
- Historia tylko w pamięci (brak cache na dysku) — po wylogowaniu nic nie zostaje.
- Uzasadnienia nie są logowane ani wysyłane nigdzie poza Librusa.
- WebView: tylko `https://*.librus.pl` w głównej ramce, bez przechwytywania nawigacji
  (D11), bez dostępu do plików i geolokalizacji.

## 4. Checklista na telefonie

1. [ ] Zainstaluj nowy APK, zaloguj się.
2. [ ] Ikona tarczy → Diagnostyka → sekcje „e-Usprawiedliwienia: …” → „Kopiuj raport”
       i wklej w rozmowie (przejrzyj przed wysłaniem).
3. [ ] Zakładka „Usprawiedliwienia”: liczba zgłoszeń, okresy, statusy i uzasadnienia
       zgadzają się z historią w Synergii / aplikacji Librus.
4. [ ] Otwórz jedno zgłoszenie: zakres, lekcje (jeśli były), data wysłania, status.
5. [ ] Filtry: status i zakres dat zawężają listę poprawnie.
6. [ ] „Nowe (Librus)” → czy otwiera się oficjalny moduł, czy „Brak dostępu” / logowanie
       do Konta LIBRUS? **Niczego nie wysyłaj** bez decyzji — to prawdziwe zgłoszenie
       do szkoły.
7. [ ] (Tylko jeśli faktycznie trzeba usprawiedliwić nieobecność) wyślij je w oficjalnym
       module, wróć przyciskiem ✓ → komunikat „W historii jest nowe zgłoszenie …”.
8. [ ] Wyloguj → zakładka po ponownym zalogowaniu pobiera historię od nowa.
