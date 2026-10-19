# Gotowość do zamkniętej bety Android (1.0.0-beta.1)

Audyt z 2026-10-20. Model zagrożeń: aplikacja na prywatnych telefonach 20–50 rodziców,
dane dzieci (oceny, wiadomości z nauczycielami, uzasadnienia nieobecności), dystrybucja
ręczna APK, brak własnego serwera. Najważniejsze ryzyka: przejęcie sesji Synergii,
wyciek danych dziecka z telefonu (kopia zapasowa, logi, inne aplikacje, powiadomienia),
podrobiony APK, niezamierzone wysłanie wiadomości/usprawiedliwienia, przeciążenie
Synergii (regulamin §4 ust. 3c).

## 1. Ustalenia i poprawki

| # | Obszar | Ustalenie | Waga | Stan |
|---|---|---|---|---|
| 1 | Podpis | `release` podpisywany **kluczem debug** (szablon Fluttera) | krytyczna dla dystrybucji | ✅ poprawione: osobny klucz wydań poza repozytorium, hasło tylko w zmiennej procesu; bez klucza build release kończy się błędem |
| 2 | Diagnostyka | Ekran „Diagnostyka integracji” dostępny w release (ikona na ekranie głównym i przycisk po nieudanym logowaniu) — pokazuje nazwy ciasteczek i strukturę API | średnia | ✅ ukryty w release (`BuildConfig.diagnostics`), flaga `SYNERGIA_DIAGNOSTICS` tylko świadomie |
| 3 | Sieć | Brak `network_security_config`: WebView na części wersji Androida ignoruje `usesCleartextTraffic`; brak jawnego wykluczenia CA użytkownika | niska–średnia | ✅ dodano: `cleartextTrafficPermitted=false`, tylko systemowe CA |
| 4 | Wylogowanie | Błąd jednego kroku (np. wtyczki WebView) przerywał resztę — mogły zostać robocze wiadomości lub ciasteczka WebView | średnia | ✅ kroki niezależne; WebView czyszczony także po błędzie magazynu; test regresji |
| 5 | Licencje | Brak ekranu licencji (MIT/BSD wymagają dołączenia notki w dystrybucji binarnej) | formalna | ✅ „Ustawienia → O aplikacji → Licencje bibliotek” |
| 6 | Wersja | `1.0.0+1` = buildy deweloperskie | — | ✅ `1.0.0-beta.1+2`, wersja widoczna w „O aplikacji” |

## 2. Zweryfikowane bez zmian (kod + build release)

**Autoryzacja i sesja**
- WebView logowania: JavaScript wymagany przez Librusa; **brak** mostów JS
  (`addJavaScriptChannel`), brak wstrzykiwania skryptów, brak dostępu do plików,
  treści i geolokalizacji, ciasteczka stron trzecich wyłączone.
- Zdalne debugowanie WebView: `enableDebugging(BuildConfig.webViewDebugging)` = tylko debug
  (logowanie i oficjalny formularz).
- Główna ramka WebView: tylko `https://*.librus.pl`; inne strony są zamykane (D11).
- Kanał natywny ciasteczek (`MainActivity.kt`): tylko odczyt dla stałego
  `https://synergia.librus.pl/`, niczego nie loguje, nie przyjmuje adresu od Darta.
- Sesja zapisywana dopiero po potwierdzeniu `Me`; przechowywanie: flutter_secure_storage
  (Android Keystore). Hasło nigdy nie trafia do aplikacji.
- Transport ciasteczek: klient API ma stałe adresy `https://synergia.librus.pl/…`,
  `followRedirects=false`; nagłówek `Cookie` Synergii jest dołączany wyłącznie dla hosta
  `synergia.librus.pl`, ciasteczka wiadomości wyłącznie dla `wiadomosci.librus.pl`;
  przekierowania inicjalizacji wiadomości: tylko HTTPS + `*.librus.pl` (http dla hostów
  Librusa podnoszony do https **przed** wysłaniem żądania, więc ciasteczka nigdy nie idą
  jawnym tekstem; inne schematy/domeny odrzucane). Dodatkowo system blokuje cleartext.
- Rotacja ciasteczek (`Set-Cookie`) scalana i zapisywana; obce domeny ignorowane.
- Wiele kont: jedno konto naraz; robocze przypisane do właściciela (inne konto ich nie
  zobaczy), stan powiadomień czyszczony przy wylogowaniu, klient wiadomości odtwarzany
  przy zmianie stanu logowania.

**Dane lokalne**
- Na dysku tylko: sesja, robocze, ustawienia/stan powiadomień — wszystko zaszyfrowane.
  Dane szkolne (oceny, plan, wiadomości, usprawiedliwienia) wyłącznie w pamięci.
- Cache WebView (strony Librusa) — czyszczony przy wylogowaniu.
- `allowBackup=false`, `fullBackupContent=false` (bez kopii Google/adb).
- Logi: brak `print`; jedyny `debugPrint` (log nawigacji) tylko w debug; Dio bez
  `LogInterceptor`; komunikaty wyjątków bez wartości ciasteczek/tokenów (testy).
- Powiadomienia: bez nadawcy i tematu.
- Brak analityki, reklam, raportowania awarii.

**Uprawnienia (scalony manifest release, `aapt2`)**
INTERNET, POST_NOTIFICATIONS, ACCESS_NETWORK_STATE, WAKE_LOCK, RECEIVE_BOOT_COMPLETED
(WorkManager), VIBRATE (flutter_local_notifications; wymagane przy powiadomieniach na
Androidzie < 8), `DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (AndroidX, poziom podpisu).
Usunięte wcześniej: FOREGROUND_SERVICE*. Brak lokalizacji, kontaktów, plików, aparatu,
`REQUEST_INSTALL_PACKAGES`. WAKE_LOCK/RECEIVE_BOOT_COMPLETED zostawione, bo ich
usunięcie mogłoby powodować błędy WorkManagera przy przyszłym włączeniu synchronizacji
(niskie ryzyko — uprawnienia „normal”).

**Funkcje beta (fail-closed)**
- `SYNERGIA_BACKGROUND_SYNC` — wyłączona (bez zmian).
- `SYNERGIA_NATIVE_EXCUSE_SUBMIT` — wyłączona. **Nie** jest bezpieczna do udostępnienia:
  odpowiedź serwera na wysłanie nie została nigdy zaobserwowana (zob. [excuses.md](excuses.md)).
  Pozostaje wyłączona w becie 1; oficjalny formularz („Nowe (Librus)”) działa jako droga główna.
- `SYNERGIA_DIAGNOSTICS` — wyłączona.
- `tool/build_release.ps1` nie przekazuje żadnej z nich; ekran „O aplikacji” pokazuje stan.

## 3. Ryzyka nierozwiązane

| Ryzyko | Ocena | Ograniczenie |
|---|---|---|
| Logowanie przez WebView jest nieoficjalne; zmiana strony Librusa może je zepsuć | średnie (dostępność) | komunikat „tryb eksperymentalny”, „Zacznij od nowa”; szybka ścieżka wydania poprawki |
| Nieudokumentowane endpointy (`gateway/api/2.0`, `wiadomosci.librus.pl/api`) | średnie (prawne/dostępność) | regulamin §3 ust. 10 dopuszcza aplikacje zewnętrzne, ale sposób techniczny niepotwierdzony — zapytanie do Librusa przed szerszą dystrybucją |
| Nazwa „Synergia Lite” zawiera nazwę produktu Librusa | do oceny | aplikacja wszędzie opisana jako nieoficjalna; rozważyć zmianę nazwy przed dystrybucją poza zamkniętą grupę (applicationId bez „librus”) |
| Podrobiony APK | niskie w zamkniętej grupie | jeden kanał, SHA-256 w osobnej wiadomości, stały certyfikat (Android odrzuci aktualizację innym kluczem) |
| Utrata klucza wydań | średnie | procedura kopii zapasowej ([release.md](release.md) §3) |
| Root/malware na telefonie testera | poza zakresem | Keystore utrudnia, ale nie wyklucza odczytu sesji na zrootowanym urządzeniu |
| Wysyłanie nowej wiadomości (nie odpowiedzi) niepotwierdzone na żywo | niskie | podsumowanie przed wysłaniem, wynik „nie wiadomo” zamiast ponowienia |
| Oceny niesprawdzone na koncie z ocenami | średnie (poprawność) | testerzy proszeni o porównanie; parser odporny na nieznane pola |
| Weryfikacja deweloperów Androida (Google) | patrz §4 | |

## 4. Formalności (kwestie otwarte — wymagają zewnętrznego potwierdzenia)

1. **Regulamin Synergii v1.6** ([analysis.md §3](analysis.md)): §1 i §3 ust. 10 dopuszczają
   aplikacje korzystające z API; §4 ust. 3c zakazuje obciążania serwerów — aplikacja
   odświeża tylko na żądanie, bez automatycznych ponowień, z kolejką ≥ 300 ms i obsługą
   429/503. **Otwarte:** czy rozpowszechnianie klienta innym rodzicom i użycie
   nieudokumentowanych endpointów jest akceptowane przez Librusa. Rekomendacja: zapytanie
   do Librusa przed rozesłaniem poza najbliższe grono. Techniczna możliwość ≠ zgoda.
2. **Znaki towarowe** „LIBRUS”, „Synergia”: aplikacja nie używa logo ani kolorystyki
   Librusa; nazwa zawiera „Synergia”. **Otwarte:** zasady Librusa dot. nazwy — nie znaleziono
   publicznych wytycznych; ocena prawna lub zmiana nazwy.
3. **Licencje**: zależności Dart — BSD-3 (72 pakiety, m.in. Flutter, webview_flutter,
   flutter_local_notifications, go_router), MIT (16: dio, riverpod, html, workmanager…),
   Apache-2.0 (4), BSD-2 (timezone), MPL-2.0 (`dbus` — tylko Linux, nie trafia do APK).
   Android: AndroidX (Apache-2.0), `desugar_jdk_libs` (GPLv2 + Classpath Exception —
   wyjątek pozwala na dystrybucję). Brak licencji copyleft wpływającej na kod aplikacji.
   Licencja samego projektu — nadal do decyzji (D7).
4. **Weryfikacja deweloperów Androida (Google)** — wg [Android Developers Blog, 06.2026](https://android-developers.googleblog.com/2026/06/android-developer-verification.html):
   od 30.09.2026 rejestracja wymagana dla instalacji ze sklepów uczestniczących
   w Brazylii, Indonezji, Singapurze i Tajlandii; **globalnie (w tym Polska) od 2027**.
   Instalacja przez adb i „advanced flow” dla niezweryfikowanych deweloperów pozostaje.
   Konta „limited distribution” (bez opłaty i dokumentu) — do **20 urządzeń**, za mało
   na 20–50 testerów. **Otwarte:** przed rozszerzeniem w 2027 — rejestracja jako deweloper
   (dane osobowe, dokument, opłata) albo dystrybucja przez Google Play (test zamknięty).
5. **RODO** — zob. [beta/privacy-policy-draft.md](beta/privacy-policy-draft.md), „Kwestie otwarte”.

## 5. Ocena gotowości

**Technicznie: gotowe do zamkniętej bety po spełnieniu warunków blokujących:**

1. Utworzenie klucza wydań i jego kopii zapasowej (wymaga właściciela — hasło).
2. Build `.\tool\build_release.ps1` z czystego commitu.
3. Instalacja na telefonie i ręczne testy z [beta/release-checklist.md](beta/release-checklist.md)
   (logowanie, wylogowanie, oceny, plan, wiadomości, usprawiedliwienia, brak sieci,
   ponowne uruchomienie) — testy widgetowe i mocki **nie zastępują** tego kroku.
4. Decyzja właściciela w sprawie kwestii formalnych §4 pkt 1–2 (zalecane: zacząć od
   kilku zaufanych rodziców, zapytać Librusa równolegle).

Brak znanych problemów krytycznych dla bezpieczeństwa w kodzie.
