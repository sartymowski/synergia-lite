# Plan wersji iOS (TestFlight)

Stan na 2026-10-20: **wersja iOS nie istnieje** — repozytorium nie ma katalogu `ios/`,
nic nie zostało zbudowane ani przetestowane na iPhonie (brak macOS/Xcode w środowisku
projektu). Prace nad iOS **nie blokują** bety Androida.

## 1. Wymagania

| Element | Wymaganie |
|---|---|
| Komputer | Mac z aktualnym macOS i **Xcode** (wersja wymagana przez App Store Connect w danym momencie; sprawdzić przed startem). Alternatywy: wynajęty Mac w chmurze albo CI z runnerami macOS (Codemagic, GitHub Actions) — wtedy certyfikaty i profile jako sekrety CI |
| Konto | **Apple Developer Program** (99 USD/rok, osoba fizyczna lub organizacja; weryfikacja tożsamości) — wymagane do TestFlight |
| Urządzenie | iPhone z iOS w wersji wspieranej przez Fluttera (minimum ustala Flutter; obecnie iOS 13+) do testów przed TestFlight |
| Narzędzia | Flutter (ta sama wersja co Android), CocoaPods / Swift Package Manager (zależnie od wersji Fluttera) |

## 2. Analiza modułów

| Moduł | Android (stan) | iOS — co trzeba zrobić | Ryzyko |
|---|---|---|---|
| Szkielet | jest | `flutter create --platforms=ios --org pl.synergialite .`; Bundle ID np. `pl.synergialite.synergialite` (bez „librus”, bez podkreślenia — iOS nie dopuszcza `_`) | niskie |
| **Odczyt ciasteczek sesji** | `MainActivity.kt` → `CookieManagerCompat.getCookieInfo` dla `https://synergia.librus.pl/` | `AppDelegate.swift` (lub plugin w `ios/Runner`): ten sam kanał `pl.synergialite/cookies`, metody `getSynergiaCookies` / `flush`; implementacja: `WKWebsiteDataStore.default().httpCookieStore.getAllCookies` → filtr: domena `synergia.librus.pl` lub `.librus.pl` obejmująca ten host, ścieżka `/`; format jak na Androidzie (`name=value; Domain=…; Path=…; Secure; HttpOnly; Expires=…`) — `WebCookie.parse` bez zmian. WKHTTPCookieStore zwraca też ciasteczka HttpOnly. `getAllCookies` jest asynchroniczne → odpowiedź kanału w callbacku (wątek główny). | **średnie** — kluczowe dla logowania |
| Logowanie (WebView) | `webview_flutter` + `webview_flutter_android`; bez onNavigationRequest (D11) | `webview_flutter_wkwebview` (już w zależnościach przechodnich). Kod Dart: bloki `if (platform is AndroidWebViewController)` pomijają iOS — dodać odpowiednik dla `WebKitWebViewController` (np. `setInspectable(BuildConfig.webViewDebugging)`, iOS 16.4+). Sprawdzić: Cloudflare Turnstile w WKWebView, iframe formularza (ITP/„site” librus.pl — ten sam site, ciasteczka powinny działać), pętla portal ↔ logowanie (D11), `onUrlChange` | **wysokie** — do sprawdzenia na urządzeniu |
| Czyszczenie WebView | `WebViewCookieManager().clearCookies()`, `clearCache`, `clearLocalStorage`, `flush` | to samo API działa na iOS; `flush` w kanale iOS → no-op; dodatkowo `WKWebsiteDataStore.removeData(ofTypes: allWebsiteDataTypes, modifiedSince: .distantPast)` | niskie |
| Sesja | flutter_secure_storage → Android Keystore | iOS Keychain: ustawić `IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device, synchronizable: false)` — bez iCloud Keychain i bez migracji na inne urządzenie (odpowiednik `allowBackup=false`). **Uwaga:** Keychain przetrwa odinstalowanie aplikacji → przy pierwszym uruchomieniu po instalacji czyścić sesję (znacznik w `NSUserDefaults`/SharedPreferences, który znika przy odinstalowaniu) | średnie |
| Kopie zapasowe | `allowBackup=false` | Dane WebView (`Library/WebKit`) i cache trafiają do kopii iCloud/komputera — ciasteczka WebView zostają tam do wylogowania, więc katalogi z danymi WebView oznaczyć `isExcludedFromBackup` (do sprawdzenia, czy WKWebView to respektuje) albo czyścić magazyn WKWebView po przejęciu sesji. Decyzja w trakcie prac | średnie |
| Transport | `network_security_config` | ATS domyślnie wymaga HTTPS — nie dodawać wyjątków `NSAllowsArbitraryLoads` | niskie |
| Oceny, plan, wiadomości, usprawiedliwienia (Dart) | działają | bez zmian (czysty Dart + Dio). Sprawdzić User-Agent wiadomości (bez „Android”/„iPhone”, D12) | niskie |
| Oficjalny formularz e-Usprawiedliwień | WebView | jak logowanie; załącznik: WKWebView obsługuje `<input type=file>` natywnie (wymaga `NSPhotoLibraryUsageDescription`/`NSCameraUsageDescription`, jeśli wybór zdjęć) | średnie |
| Powiadomienia lokalne | flutter_local_notifications | konfiguracja `DarwinInitializationSettings`, prośba o zgodę; ikona/kanał inaczej | niskie |
| Synchronizacja w tle | WorkManager, **wyłączona** | `workmanager` na iOS = BGTaskScheduler (`BGAppRefreshTask`), terminy wyłącznie wg uznania iOS; wymaga `UIBackgroundModes: fetch` + `BGTaskSchedulerPermittedIdentifiers`. Pozostaje **wyłączona** (te same powody co na Androidzie) — w becie iOS nie dodawać trybów tła | — |
| Nawigacja | go_router | bez zmian; sprawdzić gest „wstecz” z krawędzi w WebView logowania | niskie |
| Konfiguracja buildu | `BuildConfig` (kDebugMode, dart-define) | bez zmian; `SYNERGIA_VERSION` przekazywać tak samo | niskie |

## 3. Kolejność prac

1. **Przygotowanie (Mac)**: Xcode, konto Apple Developer, `flutter doctor` bez błędów iOS.
2. **Szkielet**: `flutter create --platforms=ios`; Bundle ID; nazwa wyświetlana; minimalna
   wersja iOS; `Info.plist` (bez zbędnych uprawnień); commit.
3. **Kanał ciasteczek iOS** + testy jednostkowe po stronie Dart (format bez zmian) +
   ręczny test na urządzeniu: odczyt po zalogowaniu, `Me` = 200.
4. **WebView logowania**: ustawienia `WebKitWebViewController`, test pełnego logowania
   (Turnstile, iframe, brak pętli), wygaśnięcie sesji, wylogowanie (czyszczenie danych WKWebView).
5. **Keychain**: opcje dostępności, czyszczenie po reinstalacji, test.
6. **Moduły danych**: oceny, plan, wiadomości (odczyt, robocze, wysyłka — świadomy test),
   historia usprawiedliwień, oficjalny formularz.
7. **Powiadomienia** (bez tła), ekran ustawień, „O aplikacji”.
8. **Podpis i TestFlight**: certyfikat dystrybucyjny, App ID, profil (automatyczne
   zarządzanie w Xcode), `flutter build ipa --release --dart-define=SYNERGIA_VERSION=…`,
   wysyłka (Xcode Organizer / Transporter), formularz zgodności eksportowej
   (tylko standardowe szyfrowanie HTTPS → zwykle „exempt”; potwierdzić), opis prywatności
   aplikacji w App Store Connect (zgodny z [beta/privacy-policy-draft.md](beta/privacy-policy-draft.md)).
9. **Testerzy**: najpierw testerzy wewnętrzni (do 100 osób z kontem w zespole App Store
   Connect, bez Beta App Review), potem zewnętrzni (wymaga **Beta App Review**).

## 4. Ryzyka specyficzne dla Apple

- **Beta App Review / App Review**: nieoficjalny klient usługi firmy trzeciej z jej nazwą
  produktu w nazwie aplikacji może zostać odrzucony (wytyczne dot. własności intelektualnej
  i podszywania się). Przed zgłoszeniem: decyzja o nazwie, ewentualnie zgoda Librusa.
- Recenzent potrzebuje działającego konta testowego Synergii — konto demo bez danych
  prawdziwego ucznia (do uzgodnienia; nie używać konta własnego dziecka).
- Builde TestFlight wygasają po 90 dniach — plan regularnych wydań.

## 5. Kryteria akceptacji (iOS beta)

- [ ] Build `flutter build ipa` podpisany certyfikatem dystrybucyjnym, przesłany do App Store Connect.
- [ ] Na fizycznym iPhonie: logowanie przez portal działa ≥ 3 razy z rzędu, bez pętli.
- [ ] Sesja przetrwa zamknięcie aplikacji; po wylogowaniu: brak ciasteczek w WKWebView,
      brak sesji w Keychain; po odinstalowaniu i instalacji — wymagane logowanie.
- [ ] Oceny, plan, wiadomości (odczyt), historia usprawiedliwień zgodne z Librusem.
- [ ] Brak danych sesji w logach (Console.app) i brak `isInspectable` w release.
- [ ] Kopia zapasowa iPhone'a nie zawiera sesji (Keychain „ThisDeviceOnly”).
- [ ] Synchronizacja w tle i natywna wysyłka usprawiedliwień wyłączone.
- [ ] Testy automatyczne (wspólne z Androidem) zielone.
