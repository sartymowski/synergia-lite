# Decyzje techniczne

## D1. Logowanie w osadzonym WebView — rozwiązanie EKSPERYMENTALNE (2026-10-18)

**Status: eksperyment do weryfikacji, nie potwierdzony docelowy mechanizm autoryzacji.**

**Co robimy:** WebView otwiera `synergia.librus.pl/loguj/portalRodzina?v=<czas>` —
ten sam punkt wejścia co przeglądarka — i prowadzi przez oficjalny formularz OAuth
na `api.librus.pl`. Gdy główna ramka trafi do `synergia.librus.pl` poza `/loguj`,
aplikacja odczytuje ciasteczka Synergii i potwierdza sesję zapytaniem `Me`.

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
