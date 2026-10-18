# Moduł Wiadomości — kontrakt API i stan weryfikacji

Stan na **2026-10-18**. Serwis wiadomości to osobna aplikacja `wiadomosci.librus.pl`
z własną sesją i API pod `https://wiadomosci.librus.pl/api/`. Starszy moduł
HTML `synergia.librus.pl/wiadomosci/...` (używany przez librus-api) **nie jest**
używany przez Synergię Lite.

Legenda: ✅L — potwierdzone na żywym koncie rodzica przez librus-synergia (MIT,
`docs/messages.md`, 10.2026) · ✅N — potwierdzone przeze mnie na żywo **bez sesji** ·
📖 — tylko z publicznego JS aplikacji Librusa (wg librus-synergia), bez testu na żywo ·
❌ — **niesprawdzone na Twoim koncie**. Żadnego endpointu nie sprawdzono jeszcze
na Twojej sesji — do tego służy diagnostyka (sekcja „Weryfikacja”).

## Uwierzytelnienie

1. `GET https://synergia.librus.pl/wiadomosci3` z ciasteczkami sesji Synergii (✅L, także
   librus-rs 04.2026 i librus_pyapi 09.2026).
2. Synergia przekierowuje (HTTP 3xx, mechanizm MultiDomainLogon) na `wiadomosci.librus.pl`,
   który ustawia własne ciasteczka sesji. Synergia Lite śledzi przekierowania ręcznie:
   wyłącznie `https://*.librus.pl`, maks. 10 kroków, ciasteczka Synergii tylko do
   `synergia.librus.pl`, ciasteczka wiadomości tylko do `wiadomosci.librus.pl`.
   Adresy z tokenem (`MultiDomainLogon?…`) nie są nigdzie zapisywane ani logowane.
3. Treść „Brak dostępu” → szkoła nie udostępnia modułu (✅L) → `MessagesUnavailableException`.
4. Przekierowanie na `portal.librus.pl`, `api.librus.pl` lub `/loguj` → sesja Synergii
   wygasła → `SessionExpiredException` (globalne ponowne logowanie).
5. Ciasteczka wiadomości są trzymane **tylko w pamięci**; sesja wiadomości wygasa
   niezależnie i często (✅L, czasem w ciągu godziny). GET po 401/403/3xx odnawia ją
   raz (ponowny krok 1) i powtarza odczyt; drugie 401 → `MessagesSessionExpiredException`
   (bez wylogowania z Synergii), drugie 403 → `PermissionDeniedException`.
6. Bez sesji API odpowiada `401 {}` (✅N). Strona aplikacji z mobilnym User-Agent
   przekierowuje na `/blad-urzadzenie-mobilne` (✅N) — klient wiadomości używa
   User-Agent bez słowa „Android”.

Nie ma CAPTCHA w tym przepływie; gdyby się pojawiła, aplikacja jej nie obchodzi.

## Endpointy używane przez aplikację

| Żądanie | Funkcja | Status |
|---|---|---|
| `GET me` | identyfikator konta (klucz wiadomości roboczych), kontrola sesji przed wysłaniem | ✅L, ✅N (401 bez sesji) |
| `GET inbox/unreadMessagesCount` | licznik na zakładce | ✅L |
| `GET inbox/messages?page=&limit=` | Odebrane: `{"data":[…],"total":N}` (bywa goła lista) | ✅L |
| `GET outbox/messages?page=&limit=` | Wysłane | ✅L |
| `GET inbox/messages/{id}` | szczegóły; **oznacza jako przeczytaną** | ✅L |
| `GET outbox/messages/{id}` | szczegóły wysłanej + odbiorcy ze statusem odczytu (`readed`) | ✅L |
| `GET receivers/types?includeClass=true` | grupy odbiorców | ✅L |
| `GET receivers/groups/school-employees?receiverType={id}` | osoby w grupie (`accountId`, `label`, dostępność) | ✅L |
| `GET receivers/student-subjects` | przedmioty nauczycieli (opcjonalne; 403 tolerowane) | ✅L |
| `POST messages/reply` | odpowiedź w wątku: treść jak niżej + `originalMessageId` (liczba) | ✅L (jedno wysłanie 2026-10-12) |
| `POST messages` | nowa wiadomość | 📖 |

Ciało `POST` (JSON): `{"receivers":{"schoolReceivers":[{"accountId":"…"}]},
"topic":<base64 UTF-8>, "content":<base64 UTF-8 tekstu z ucieczką HTML>,
"storageId":null, "category":"normal"}`. Odpowiedź na nową wiadomość wg JS Librusa:
`201 {"data":{"messageId":…,"status":"sent"}}` (📖); odpowiedź na reply: sukces bez
identyfikatora (✅L).

Treść: base64 UTF-8; pełna wiadomość w `<Message><Content><![CDATA[…]]></Content></Message>`;
HTML z linkami przepisanymi na `liblink.pl`; podgląd z listy ucięty po bajtach (✅L).

## Świadomie nieobsługiwane

- **„Odpowiedz wszystkim”** — dla wiadomości odebranych API nie podaje identyfikatorów
  kont pozostałych odbiorców; przycisk nie jest pokazywany.
- **Pobieranie załączników** — API to obsługuje (dwuetapowo przez `sandbox.librus.pl`, ✅L),
  ale wymaga zapisu i otwierania plików na urządzeniu; na razie aplikacja pokazuje
  nazwy załączników.
- **Dodawanie załączników, przekazywanie, wycofanie wiadomości** (`PUT messages/{id}/withdrawal`, 📖).
- **Inne skrzynki** (`notes`, `alerts`, `substitutions`, …), archiwum, grupy spoza
  pracowników szkoły (rady rodziców, własne grupy) — wymagają innych, niezweryfikowanych
  endpointów.
- Limity w aplikacji (50 odbiorców, temat 200, treść 10 000 znaków) są zachowawcze —
  Librus ich nie dokumentuje.

## Bezpieczeństwo

- Treść renderowana bez WebView: parser `package:html` → zwykły tekst z prostymi
  stylami; skrypty, ramki, formularze, style pomijane; obrazy nie są pobierane
  (opis „[obraz]”, piksele 1×1 pomijane); linki nie otwierają się same — adres można
  skopiować.
- Żadnych logów treści, nadawców, odbiorców, ciasteczek ani adresów z tokenami.
  Diagnostyka raportuje wyłącznie nazwy pól, liczby i kody statusu oraz **nie otwiera
  wiadomości**.
- Wiadomości robocze: `flutter_secure_storage` (Keystore), przypisane do `accountId`
  z `me`; inny właściciel → robocze usuwane; świadome wylogowanie usuwa wszystkie.
  Wygaśnięcie sesji ich nie usuwa (to samo konto zwykle loguje się ponownie).
- Lista i szczegóły są tylko w pamięci (brak trwałego cache wiadomości).

## Wysyłanie — zasady

- Tylko przycisk „Wyślij” + dialog potwierdzenia; podczas wysyłki przycisk i pola są
  zablokowane; jedna wysyłka naraz.
- Przed `POST` kontrola sesji odczytem `GET me`; sam `POST` **nigdy nie jest ponawiany**
  ani nie odnawia sesji.
- Wynik: **wysłano** (2xx bez błędów w treści) · **nie wysłano** (3xx/401/403/429/4xx,
  brak połączenia przed wysłaniem, nieudany odczyt kontrolny) · **nie wiadomo**
  (timeout lub zerwanie po wysłaniu, 5xx, 2xx z `errors`/`status: failed` albo z treścią
  inną niż JSON). Sam kod 200 nie wystarcza.
- Szkic zapisywany przed wysłaniem, usuwany dopiero po potwierdzonym sukcesie.
  Po „nie wiadomo” szkic dostaje znacznik i kolejna próba (także po restarcie aplikacji)
  wymaga dodatkowego potwierdzenia; przycisk „Sprawdź Wysłane” otwiera odświeżony folder.
  Aplikacja nigdy nie wysyła niczego sama po ponownym uruchomieniu.

## Źródła i licencje

| Projekt | Licencja | Wykorzystanie |
|---|---|---|
| [MichalZaniewicz/librus-synergia](https://github.com/MichalZaniewicz/librus-synergia) (`docs/messages.md`, 2026-10-15) | MIT | główne źródło kontraktu (fakty, bez kopiowania kodu) |
| [FlakM/librus-rs](https://github.com/FlakM/librus-rs) (2026-04-08) | MIT | potwierdzenie `wiadomosci3`, odczyt, base64 |
| [emsi/librus_pyapi](https://github.com/emsi/librus_pyapi) (2026-09-22) | **AGPL-3.0** | wyłącznie fakty (adresy endpointów); kod nieczytany pod kątem kopiowania |
| [SimonB50/librusek](https://github.com/SimonB50/librusek) | **AGPL-3.0** | wyłącznie fakty (endpointy odczytu) |
| [Mati365/librus-api](https://github.com/Mati365/librus-api) | MIT | stary moduł HTML — nieużywany |
| `package:html` 0.15.7 | MIT | bezpieczne parsowanie HTML treści |

## Weryfikacja na Twoim koncie

Zob. `docs/integration-status.md` → „Wiadomości — checklista”.
