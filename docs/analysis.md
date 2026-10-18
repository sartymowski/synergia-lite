# Analiza źródeł integracji z LIBRUS Synergia

Stan na **2026-10-18**. Wszystkie wnioski o projektach referencyjnych pochodzą
z lektury ich kodu i zgłoszeń (sklonowane tylko do odczytu, bez uruchamiania).
Zachowanie serwerów Librusa sprawdzono wyłącznie **bez logowania** (sekcja 4).

## 1. Projekty referencyjne

| | Librusek (SimonB50/librusek) | librus-api (Mati365/librus-api) |
|---|---|---|
| Licencja | **AGPL-3.0** | MIT |
| Technologia | Next.js + Capacitor (aplikacja mobilna) | Node.js, axios + tough-cookie |
| Ostatni commit | 2026-03-30 („Fixed auth”) | 2026-10-02 |
| Źródło danych | JSON: `synergia.librus.pl/gateway/api/2.0` | HTML stron Synergii (cheerio) |
| Wiadomości | `wiadomosci.librus.pl/api` | HTML + `wiadomosci.librus.pl` |
| Stan logowania | naprawione 2026-03-30; autor 2026-09-06 pisze, że nie ma jak testować z „nowym API Librusa” | naprawiane 2026-04-10/13 i 2026-09-13/18 (PR #108), potwierdzone w #88 (2026-09-24, wersja 2.18.1) |

### Jak oba projekty logują się dziś (2026)

Oba **emulują przeglądarkę** w przepływie OAuth portalu Librus Rodzina:

1. `GET https://synergia.librus.pl/loguj/portalRodzina?v=<timestamp>` z `Referer: https://portal.librus.pl/`
   → 302 do `api.librus.pl/OAuth/Authorization?client_id=46&response_type=code&scope=mydata&state=…`,
   ciasteczko `oauth_state`.
2. Wejście na formularz `api.librus.pl/OAuth/Authorization?client_id=46`.
3. `POST` formularza (`action=login`, `login`, `pass`) z nagłówkami `X-Requested-With`
   i **`x-baner`** — wartością liczoną przez skrypt strony z `Math.random()` i `Date.now()`.
   Komentujący w librus-api #88 opisują `x-baner` jako mechanizm zbliżony do antybotowego.
4. Łańcuch przekierowań `/OAuth/Authorization/2FA` → `PerformLogin` → `Grant` →
   powrót do `synergia.librus.pl/loguj/portalRodzina?code=…&state=…`.
5. Dopiero ten powrót ustawia **`oauth_token`** i aktywuje sesję. `DZIENNIKSID`
   i `SDZIENNIKSID` są ustawiane zawsze, także bez zalogowania (#88).

Librusek po zalogowaniu woła `gateway/api/2.0/Auth/TokenInfo`, `Auth/UserInfo/{id}`
oraz `synergia.librus.pl/wiadomosci2` (aktywacja modułu wiadomości). Odświeżanie:
`GET synergia.librus.pl/refreshToken`, a w razie błędu ponowne logowanie hasłem
(hasło trzyma w pamięci sesji aplikacji). Wylogowanie: `GET synergia.librus.pl/wyloguj`.

### Zmiany w 2026

- **Marzec/kwiecień 2026**: start przepływu przeniesiono na
  `synergia.librus.pl/loguj/portalRodzina`; stary bezpośredni URL OAuth przestał działać
  (librus-api #90, Librusek c1a8a0e). Doszedł nagłówek `x-baner` i krok 2FA/PerformLogin.
- **Wrzesień 2026**: librus-api musiało zatrzymywać przekierowania ręcznie, bo
  automatyczne podążanie gubiło `state` (PR #108); naprawiono też parsowanie danych
  z „bieżących kont” (#104) i dodano flagę odwołanych lekcji (#112).
- Formularz logowania zawiera **Cloudflare Turnstile** (`login-limit-exceeded-recaptcha-view`)
  włączany po przekroczeniu limitu prób — potwierdzone na żywo (sekcja 4).

### Konto rodzica: dwa warianty

- **Login Synergii wydany przez szkołę** (konto rodzica w danej szkole) — przepływ powyżej.
- **„Konto LIBRUS” (e-mail) w portalu Librus Rodzina** — według #88 osobny mechanizm:
  `portal.librus.pl/api/v3/SynergiaAccounts` zwraca konta dzieci z tokenami Bearer
  dla `api.librus.pl/3.0`; te tokeny **nie działają** na `gateway/api/2.0` (401).
  To API używane przez oficjalną aplikację mobilną, nieudokumentowane publicznie.

Synergia Lite startuje z punktu wejścia `synergia.librus.pl/loguj/portalRodzina` (adres portalu `portal.librus.pl/rodzina/synergia/loguj` przekierowuje dziś na stronę główną portalu),
więc obsłuży ten wariant, który użytkownik wybierze na stronie Librusa — **do potwierdzenia na żywo**.

### Pobieranie danych w Librusku (gateway/api/2.0)

Odpowiedź ma postać `{"<Zasób>": …, "Resources": …, "Url": …}`. Referencje to
`{"Id": …, "Url": …}`; słowniki pobierane są selektorami `Zasób/1,2,3`.

| Dane | Endpoint |
|---|---|
| Konto | `Me` |
| Oceny | `Grades`, `Grades/Categories/{ids}`, `Grades/Comments/{ids}` |
| Inne oceny | `PointGrades`, `TextGrades`, `BehaviourGrades` (+ kategorie/typy) |
| Przedmioty, nauczyciele | `Subjects/{ids}`, `Users/{ids}` |
| Plan | `Timetables?weekStart=YYYY-MM-DD` (dzień → sloty → wpisy), `TimetableEntries` |
| Terminy | `HomeWorks`, `HomeWorkAssignments` |
| Frekwencja | `Attendances`, `Attendances/Types/{ids}`, `Lessons/{ids}` |
| Inne | `Classes`, `Schools`, `SchoolNotices`, `LuckyNumbers`, `Notes`, `NotificationCenter` |

Pola planu wykorzystywane w UI Libruska: `Subject.Name`, `Teacher.FirstName/LastName`,
`HourFrom`, `HourTo`, `IsCanceled`, `IsSubstitutionClass`. Średnia w Librusku:
waga z kategorii, `+` = +0,5, `-` = −0,25, pomijanie `CountToTheAverage=false`.

### Co działa, a co może być nieaktualne

- **librus-api 2.18.1** — logowanie + oceny/plan/ogłoszenia/wiadomości potwierdzone
  przez zgłaszającego #88 (2026-09-24) **na jednym koncie ucznia**.
- **Librusek** — logowanie poprawione 2026-03-30, później brak potwierdzeń; zgłoszenia
  #102 (ciche błędy logowania), #101 (średnia przy ocenach punktowych — wontfix).
- **Brak w obu**: obsługi HTTP 401/429, ograniczania liczby żądań, rozróżnienia
  wygaśnięcia sesji od innych błędów (Librusek zwraca `null`/`false`, przez co pusta
  lista i błąd wyglądają tak samo).

## 2. Licencje i ponowne użycie

- **Librusek (AGPL-3.0)**: skopiowanie lub adaptacja kodu czyniłaby Synergię Lite
  utworem zależnym objętym AGPL — obowiązek udostępnienia całego kodu źródłowego na tej
  samej licencji każdemu odbiorcy aplikacji (a przy udostępnianiu przez sieć — także
  użytkownikom zdalnym). **Nie skopiowano żadnego kodu.** Wykorzystano wyłącznie fakty
  o interfejsie serwera (adresy, nazwy pól), które nie są utworem Libruska.
- **librus-api (MIT)**: dopuszcza ponowne użycie z zachowaniem noty licencyjnej;
  mimo to nie przeniesiono kodu (inny język, inny model logowania).
- Zależności Synergii Lite — zob. `docs/decisions.md`.

## 3. Regulamin i oficjalna integracja

**Regulamin serwisu LIBRUS Synergia v1.6 z 01.07.2024** (PDF pod
`https://synergia.librus.pl/regulamin`, przeczytany 2026-10-18):

- §1 (definicje SYSTEM): użytkownicy „mogą korzystać z SYSTEMU za pomocą SERWISU
  lub aplikacji wykorzystujących API SYSTEMU, w tym aplikacji mobilnych”; SERWIS to
  aplikacja w domenie `synergia.librus.pl` „udostępniająca po zalogowaniu interfejs www
  oraz API”.
- §3 ust. 10: „SYSTEM zapewnia UŻYTKOWNIKOWI nieodpłatny dostęp do API SYSTEMU
  umożliwiające komunikację z zewnętrznymi aplikacjami, w szczególności (na żądanie
  UŻYTKOWNIKA): (…) b. eksport w czasie rzeczywistym danych UŻYTKOWNIKA z SYSTEMU
  do zewnętrznych usług (przenoszenie danych)”.
- §4 ust. 3c: użytkownik nie ma prawa do „systematycznego i powtarzającego się
  pobierania danych z serwera mogącego znacząco zdestabilizować pracę serwerów”
  (atak typu DDoS lub podobny w skutkach); §4 ust. 4: naruszenie może skutkować
  zablokowaniem dostępu.
- Brak postanowień zakazujących korzystania z własnego klienta lub logowania przez
  przeglądarkę osadzoną w aplikacji.

**Wnioski:**
- Regulamin dopuszcza korzystanie z Synergii przez aplikacje zewnętrzne używające API
  i przewiduje eksport danych użytkownika na jego żądanie — to wspiera cel projektu.
- Regulamin **nie dokumentuje** procedury uzyskania dostępu do API (klient OAuth,
  dokumentacja). `gateway/api/2.0` to API frontendu Synergii, nie udokumentowane
  publicznie; `client_id=46` należy do Librusa. Status: dozwolone co do zasady,
  sposób techniczny niepotwierdzony przez Librusa.
- Wymóg §4 ust. 3c realizujemy przez: odświeżanie tylko na żądanie, brak automatycznych
  ponowień, kolejkowanie żądań z odstępem ≥ 300 ms, obsługę 429/503 z `Retry-After`.
- Rekomendacja przed publiczną dystrybucją: zapytać Librusa (librus@librus.pl) o dostęp
  do API wg §3 ust. 10 i o zarejestrowanie klienta OAuth (zob. decisions.md D1).

Starsze/inne dokumenty: dziennik.librus.pl/regulamin (e-Dziennik, 2018), regulamin
LibrusGO (inny produkt, 2023) — tylko kontekst.

## 3a. Aktualizacja: librus-api PR #108 i zgłoszenie #88 (stan 2026-10-18)

- **PR #108** „fix current Synergia OAuth redirect flow”, scalony 2026-09-18 (commit
  `5487bd9`): (1) zachowanie przekierowania niosącego `state` zamiast automatycznego
  podążania (które kończyło się `invalid_request`), (2) sesja po stronie API i wysłanie
  formularza z bieżącymi nagłówkami AJAX (`x-baner`, `X-Requested-With`), (3) ograniczony
  łańcuch przekierowań z walidacją hosta i ścieżki każdego kroku. Autor zweryfikował
  na żywo **konto rodzica** (tylko odczyt, 16 nagłówków skrzynki). Opiekun poprosił
  o usunięcie testów przepływu, o komentarz do `x-baner` i wydzielenie helperów.
- **#88**: 2026-09-24 zgłaszający potwierdził, że 2.18.1 (Node 26.7) loguje i zwraca
  login, oceny, plan, ogłoszenia, wiadomości i dane konta — sprawdził jedno z dwóch kont.
  Zgłoszenie zamknięte jako rozwiązane.
- Bieżąca wersja librus-api: 2.20.0 (2026-10-02), bez zmian w logowaniu po PR #108.
- Konsekwencja: przepływ `portalRodzina` jest aktualny dla konta rodzica; WebView
  wykonuje go w całości po stronie Librusa (łącznie z `x-baner`).

## 4. Weryfikacja na żywo bez logowania (2026-10-18)

Wykonane zapytania (bez danych logowania, wartości ciasteczek zredagowane):

| Zapytanie | Wynik |
|---|---|
| `GET synergia.librus.pl/loguj/portalRodzina?v=…` | 302 → `api.librus.pl/OAuth/Authorization?client_id=46&response_type=code&scope=mydata&state=…`; `Set-Cookie`: `DZIENNIKSID`, `SDZIENNIKSID`, `oauth_state` (Max-Age=3600, HttpOnly) |
| Podążenie za przekierowaniem | 302 → `/OAuth/Authorization?client_id=46`, formularz z polami `Login`, `Pass` |
| Strona formularza | skrypty `Authorization.js?0.29`, `app.min.js?v1.7`; blok **Cloudflare Turnstile** dla przekroczonego limitu prób; skrypt dołącza `captcha` do żądania logowania |
| `GET gateway/api/2.0/Me` bez sesji | **401** `{"Status":"Error","Message":"Request is denied"}`, `Content-Type: application/json`, nowy `DZIENNIKSID` w `Set-Cookie` |
| `GET api.librus.pl/3.0/Me` bez tokenu | **401** z tą samą treścią |
| `GET synergia.librus.pl/loguj/portalRodzina?v=…` **bez** Referer | 2 przekierowania → formularz `api.librus.pl/OAuth/Authorization?client_id=46` (pola `Login`, `Pass`), główna ramka, bez iframe |
| `GET portal.librus.pl/rodzina/synergia/loguj` | przekierowanie na `portal.librus.pl/rodzina` (strona główna portalu) |
| Certyfikat `services.gradle.org` na tej maszynie | wystawca `CN=Avast Web/Mail Shield Root` (przechwytywanie HTTPS przez antywirus) |

## Źródła

- https://github.com/SimonB50/librusek (commit c1a8a0e, zgłoszenia #97, #101, #102)
- https://github.com/Mati365/librus-api (zgłoszenia #88, #90, #83; PR #104, #108, #112)
- https://dziennik.librus.pl/regulamin (archiwalny regulamin e-Dziennika)
- https://librusgo.pl/home/regulamin_systemu_librusgo.pdf (inny produkt — tylko kontekst)
- https://synergia.librus.pl/regulamin (Regulamin serwisu LIBRUS Synergia v1.6, 01.07.2024)
- https://github.com/Mati365/librus-api/pull/108
- RFC 8252 — OAuth 2.0 for Native Apps (https://www.rfc-editor.org/rfc/rfc8252)
