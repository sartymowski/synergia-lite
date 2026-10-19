# Decyzje techniczne

## D1. Logowanie w osadzonym WebView — rozwiązanie EKSPERYMENTALNE (2026-10-18)

**Status: eksperyment do weryfikacji, nie potwierdzony docelowy mechanizm autoryzacji.**

**Co robimy:** WebView otwiera `portal.librus.pl/rodzina`; użytkownik wybiera „Zaloguj”,
a formularz OAuth `api.librus.pl` działa w iframe strony `/rodzina/synergia/loguj` —
dokładnie jak w przeglądarce (aktualizacja 2026-10-18, D11). Gdy Synergia pojawi się
w głównej ramce albo pojawi się ciasteczko `oauth_token`, aplikacja potwierdza sesję
zapytaniem `Me`.

**Dlaczego nie emulacja formularza (Librusek / librus-api):**
- formularz ma Cloudflare Turnstile — klient HTTP nie może go legalnie przejść;
- `x-baner` liczy skrypt strony; odtwarzanie go to udawanie przeglądarki wobec
  mechanizmu zbliżonego do antybotowego;
- przepływ zmieniał się w 2026 r. co najmniej dwa razy (marzec/kwiecień, wrzesień);
- 2FA i zgody obsługuje strona Librusa;
- aplikacja nie potrzebuje hasła i go nie przechowuje.

**Dlaczego to nie jest rozwiązanie docelowe:** RFC 8252 (OAuth 2.0 for Native Apps)
i praktyka dostawców tożsamości odradzają osadzone WebView: aplikacja-host technicznie
może odczytać wpisywane hasło, użytkownik nie widzi paska adresu ani certyfikatu,
nie działa współdzielona sesja przeglądarki, a dostawca może takie logowanie blokować.
Właściwa ścieżka (Custom Tabs + AppAuth + własny `redirect_uri`) **wymaga klienta
OAuth zarejestrowanego przez Librusa** — `client_id=46` należy do Librusa i wraca
na `synergia.librus.pl`, więc z Custom Tabs aplikacja nie otrzyma ani kodu, ani
ciasteczek. Do czasu odpowiedzi Librusa (§3 ust. 10 regulaminu mówi o dostępie do API
dla aplikacji zewnętrznych — warto zapytać o klienta OAuth) WebView zostaje
eksperymentem z ograniczeniami opisanymi w `integration-status.md`.

**Koszt:** po wygaśnięciu sesji trzeba zalogować się ponownie (hasła nie przechowujemy).

## D2. Dane z `gateway/api/2.0` (JSON), nie z HTML

JSON jest stabilniejszy niż selektory CSS i używa go frontend Synergii. Parsowanie
HTML (librus-api) psuło się wielokrotnie (#104, #110). Wymaga potwierdzenia, że
gateway przyjmuje ciasteczka z WebView (Librusek robi to samo z ciasteczkami
z własnego przepływu).

## D3. Brak automatycznych ponowień, kolejkowanie żądań

Klient wysyła żądania pojedynczo, z odstępem ≥ 300 ms, bez retry; Riverpod ma
wyłączone automatyczne ponawianie (`ProviderScope(retry: …)`). HTTP 429/503 →
komunikat z czasem z `Retry-After`. Odświeżanie wyłącznie na żądanie użytkownika.

## D4. Przechowywanie sesji

Ciasteczka `synergia.librus.pl` w `flutter_secure_storage` (klucz w Android Keystore).
`android:allowBackup="false"`, `usesCleartextTraffic="false"`. Wylogowanie: `GET /wyloguj`
(najlepsza próba), usunięcie sesji, ciasteczek, Web Storage i cache WebView.
`SessionCookies.toString()` nie ujawnia wartości.

## D5. Średnie liczone lokalnie i oznaczone jako orientacyjne

`+` = +0,5, `-` = −0,25, waga z kategorii; pomijane: oceny nieliczbowe, kategorie
z `CountToTheAverage=false`, kategorie bez wagi, `IsConstituent=false`, oceny
śródroczne/roczne i ich propozycje. Liczba pominiętych ocen jest raportowana.
Szkoły mogą mieć inne ustawienia — dlatego etykieta „orientacyjna”.

## D6. Zależności

| Pakiet | Wersja | Licencja | Po co |
|---|---|---|---|
| dio | 5.11.1 | MIT | HTTP: timeouty, adapter do testów bez sieci |
| webview_flutter (+ _android) | 4.14.1 | BSD-3-Clause | WebView logowania (D8) |
| flutter_secure_storage | 11.2.0 | BSD-3-Clause | sesja w Keystore |
| flutter_riverpod | 3.4.3 | MIT | stan |
| go_router | 18.1.0 | BSD-3-Clause | nawigacja z przekierowaniami zależnymi od sesji |
| html | 0.15.7 | MIT | bezpieczne parsowanie treści wiadomości (D12) |
| fake_async (dev) | 1.3.3 | BSD-3-Clause | testy autozapisu |

Wszystkie w najnowszych wersjach dostępnych 2026-10-18 (`flutter pub outdated`).
`flutter_inappwebview` usunięty (D8); ciasteczka odczytuje kanał natywny (`androidx.webkit` 1.15.0, Apache-2.0).
Celowo bez `cookie_jar` (jedna domena — wystarczy własna klasa) i bez Drift
(cache trwały dopiero w etapie E). Usunięto `cupertino_icons` (tylko Android).

## D7. Licencja projektu — do decyzji

Kod nie zawiera fragmentów Libruska (AGPL-3.0), więc licencja jest wolnym wyborem
właściciela. Do ustalenia przed publikacją repozytorium.

## D8. `webview_flutter` zamiast `flutter_inappwebview` (2026-10-18)

Audyt wykazał, że `flutter_inappwebview` 6.1.5 (Android 1.1.3) bezwarunkowo wstrzykuje
do każdej strony skrypty (polyfill Promise, most `window.flutter_inappwebview`
przez `addJavascriptInterface`, hook `print`, focus/blur) — także do formularza
logowania — i w tej wersji nie da się tego wyłączyć. Oficjalny `webview_flutter`
(4.14.1, BSD-3-Clause, flutter.dev) dodaje JS tylko na wyraźne żądanie.
Brakujący odczyt ciasteczek realizuje ~40 linii w `MainActivity.kt`
(`CookieManager` + `CookieManagerCompat.getCookieInfo`, `androidx.webkit` 1.15.0,
ta sama wersja co we wtyczce), ograniczone na sztywno do `https://synergia.librus.pl/`.

## D9. Build przy przechwytywaniu HTTPS przez antywirus (2026-10-18)

`tool/flutter_android.ps1` daje JVM osobny magazyn zaufania (rooty JDK + root
Avasta skopiowany z magazynu Windows) tylko na czas procesu. Bez `trustAll`,
bez zmian w JDK i konfiguracji globalnej. Szczegóły i odrzucone warianty:
`integration-status.md`. `kotlin.incremental=false` — obejście błędu cache Kotlina
przy projekcie i pub cache na różnych dyskach.

## D10. Diagnostyka bez danych wrażliwych (2026-10-18)

Uwierzytelnienie potwierdza para: `Me` z sesją (200 + obiekt konta) **i** `Me` bez
ciasteczek (401/403). Raport zawiera tylko kody HTTP, liczby, nazwy pól JSON i
nazwy/atrybuty ciasteczek; nigdy wartości, adresów z zapytaniem ani treści danych.
Kandydat na sesję z nieudanego logowania jest trzymany wyłącznie w pamięci ekranu.

## D11. Bez przechwytywania nawigacji WebView; start z portalu (2026-10-18)

Formularz Synergii działa tylko w iframe portalu (`redirectToPortalIfNotInIframe`),
a portal wpuszcza na `/rodzina/synergia/loguj` tylko z `Referer` z portalu.
`webview_flutter_android` z `onNavigationRequest` anuluje każdą nawigację głównej ramki
i ponawia ją `loadUrl` bez `Referer` — co dawało pętlę. Dlatego:
- brak `onNavigationRequest`; filtr domen działa reaktywnie (`onPageStarted` i in.) —
  obca strona może zacząć się ładować, ale jest natychmiast zamykana;
- start z `portal.librus.pl/rodzina` (+ jedno kliknięcie użytkownika) zamiast
  dokładania sztucznego `Referer`;
- koniec logowania w iframe wykrywany lokalnie po ciasteczku `oauth_token`;
  o sukcesie decyduje wyłącznie `Me`;
- nieudana weryfikacja nie czyści WebView.

## D12. Moduł Wiadomości: nowe API `wiadomosci.librus.pl`, sesja z istniejącej sesji Synergii (2026-10-18)

- Źródło kontraktu: librus-synergia (MIT, potwierdzenia na żywym koncie rodzica 10.2026),
  librus-rs (MIT); projekty AGPL tylko jako źródło faktów. Szczegóły: `docs/messages-api.md`.
- Bez ponownego logowania: `GET synergia.librus.pl/wiadomosci3` z ciasteczkami Synergii
  i ręcznie śledzone przekierowania (tylko `https://*.librus.pl`) — ten sam przepływ co
  przeglądarka. Nie przez WebView: przepływ to wyłącznie przekierowania HTTP, a klient HTTP
  pozwala kontrolować, które ciasteczka trafiają do której domeny.
- Ciasteczka wiadomości tylko w pamięci (sesja krótka, mniej danych na dysku); klient
  odtwarzany przy zmianie stanu logowania.
- Rotacja ciasteczek Synergii podczas inicjalizacji jest zapisywana, a główny klient
  porzuca swoją kopię w pamięci (`onSynergiaCookiesChanged`).
- Wysyłanie: jedna próba, trzy wyniki (wysłano / nie wysłano / nie wiadomo), szkic do
  potwierdzonego sukcesu, potwierdzenie przed ponowieniem po wyniku niejednoznacznym.
- Odpowiedź w wątku przez `messages/reply` + `originalMessageId`; „Odpowiedz wszystkim”
  niedostępne (brak identyfikatorów kont pozostałych odbiorców w API).
- Treść bez WebView: `package:html` (MIT) → tekst ze stylami; bez JS i zasobów zewnętrznych.
- Wiadomości robocze w `flutter_secure_storage`, przypisane do `accountId`; usuwane przy
  wylogowaniu i przy zmianie konta.
- Zależność dev `fake_async` (BSD-3, dart-lang) — testy autozapisu.

## D13. Powiadomienia lokalne; sprawdzanie w tle domyślnie wyłączone (2026-10-18)

- WorkManager (MIT) + flutter_local_notifications (BSD-3); bez FCM i serwera.
- Okresowe sprawdzanie skrzynki ma niepotwierdzoną dopuszczalność (regulamin nie mówi o nim
  wprost; w oficjalnej aplikacji natychmiastowe powiadomienia są płatne, a wersja darmowa
  odświeża ok. co 3 h). Decyzja użytkownika: **wyłączone** do potwierdzenia
  (`--dart-define=SYNERGIA_BACKGROUND_SYNC=true` włącza). Zob. `docs/notifications.md`.
- Gwarancja „co najwyżej raz”: zapis stanu przed pokazaniem + deterministyczne identyfikatory
  powiadomień zamiast blokad międzyprocesowych (izolaty jednego procesu nie dzielą blokad
  plików).
- Zadanie w tle nie loguje się nigdy; wygasła sesja wstrzymuje monitorowanie.
- `SynergiaApiClient`: przy 401 jedna próba z ciasteczkami z magazynu (rotacja w innym
  kontekście). `MessagesApiClient`: przekazywanie `Retry-After`.
- `KeyValueStore` przeniesiony do `core/storage` (używany przez wiadomości robocze i powiadomienia).

## D14. e-Usprawiedliwienia: natywny odczyt, wysyłanie w oficjalnym module (2026-10-19)

- Odczyt: `gateway/api/2.0/Justifications` przez istniejącą sesję (librus-synergia,
  na żywo 10.2026). Nieznane statusy zachowywane dosłownie — potwierdzono tylko `accept`.
- Wysyłanie: moduł działa w Koncie LIBRUS, kontrakt zapisu nieznany → bez natywnego POST.
  Oficjalny moduł w WebView (bez przechwytywania nawigacji, bez wstrzykiwania JS);
  przyjęcie weryfikowane porównaniem historii przed/po.
- 401/403 na `Justifications` przy działającym `Me` = brak modułu, bez wylogowania.
- `SynergiaApiClient.fetchPage` (GET HTML z hosta Synergii) wyłącznie dla diagnostyki
  struktury formularzy — nazwy pól, nigdy wartości.

## D15. e-Usprawiedliwienia: natywny formularz, wysyłka nieaktywna; HTTPS dla przekierowań Librusa (2026-10-19)

- Kontrakt żądania ustalony z oficjalnej strony (struktura DOM + publiczny JS) — zob.
  docs/excuses.md §0. Odpowiedź serwera nieznana → `SYNERGIA_NATIVE_EXCUSE_SUBMIT` = false.
- Przyjęcie potwierdzane wyłącznie historią (`Justifications`), nigdy kodem HTTP.
- Lekcje w formularzu i szczegółach: numer z formularza Librusa + przedmiot z planu lekcji.
- Wiadomości: `wiadomosci3` w kroku 3 przekierowuje na `http://wiadomosci.librus.pl` przy
  ponownej inicjalizacji. Dla hostów `*.librus.pl` (port domyślny) `http` → `https`;
  obce domeny i inne schematy nadal odrzucane. Komunikat błędu podaje tylko schemat i host.
