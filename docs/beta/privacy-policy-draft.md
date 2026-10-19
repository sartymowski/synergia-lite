# Synergia Lite — informacja o prywatności (SZKIC)

> **Szkic do przeglądu.** Opisuje rzeczywisty przepływ danych w wersji 1.0.0-beta.1
> (zweryfikowany w kodzie). Nie jest opinią prawną i nie przesądza o zgodności z RODO —
> przed szerszą dystrybucją wymaga przeglądu przez osobę z wiedzą prawną (zob. „Kwestie
> otwarte”). Pola w `< >` uzupełnia właściciel projektu.

## Kto udostępnia aplikację

Synergia Lite to nieoficjalna, niekomercyjna aplikacja udostępniana w zamkniętym teście
przez `<imię i nazwisko / kontakt e-mail>`. **Nie jest produktem firmy Librus** i nie
jest z nią związana. „LIBRUS” i „Synergia” to oznaczenia należące do ich właściciela.

## Najważniejsze w skrócie

- Aplikacja łączy się **wyłącznie z serwerami Librusa** (`*.librus.pl`), zawsze szyfrowanym
  połączeniem HTTPS. Nie ma własnego serwera.
- **Nie zbiera** danych do statystyk, reklam ani analityki; nie zawiera bibliotek
  reklamowych ani śledzących; nie wysyła raportów o błędach.
- Udostępniający aplikację **nie ma dostępu** do Twoich danych — nie trafiają one do niego.
- **Hasła nie zna**: logujesz się na stronie Librusa wyświetlonej w aplikacji.

## Jakie dane są przetwarzane i gdzie

| Dane | Skąd | Gdzie przechowywane | Jak długo |
|---|---|---|---|
| Login i hasło do Synergii | wpisujesz na stronie Librusa | **nie są zapisywane przez aplikację**; trafiają bezpośrednio do Librusa | — |
| Sesja logowania (ciasteczka Synergii) | Librus po zalogowaniu | telefon: zaszyfrowane kluczem z Android Keystore; dane przeglądarki logowania w katalogu aplikacji | do wylogowania lub wygaśnięcia sesji |
| Sesja serwisu wiadomości | Librus | tylko w pamięci RAM | do zamknięcia aplikacji |
| Oceny, plan lekcji, wiadomości, historia usprawiedliwień, imię ucznia | serwery Librusa, na Twoje żądanie | tylko w pamięci RAM podczas korzystania (bez kopii na dysku) | do zamknięcia ekranu / aplikacji |
| Wiadomości robocze | wpisujesz w aplikacji | telefon: zaszyfrowane (Android Keystore), przypisane do konta | do wysłania, usunięcia lub wylogowania |
| Ustawienia i stan powiadomień (identyfikatory ostatnio widzianych wiadomości, bez treści) | aplikacja | telefon: zaszyfrowane | do wylogowania |
| Pamięć podręczna przeglądarki (strona logowania, oficjalny formularz usprawiedliwień) | strony Librusa | katalog aplikacji w telefonie | do wylogowania |
| Treść usprawiedliwienia wpisana w oficjalnym formularzu Librusa | wpisujesz | wysyłana bezpośrednio do Librusa; aplikacja jej nie zapisuje | — |
| Formularz usprawiedliwienia w aplikacji (podgląd) | wpisujesz | tylko w pamięci, nie jest wysyłany | do zamknięcia formularza |

Powiadomienia (jeśli w przyszłości zostaną włączone) nie zawierają nadawcy ani tematu.
Aplikacja nie zapisuje w dzienniku systemowym haseł, ciasteczek, tokenów ani danych ucznia.

## Komu dane są przekazywane

Wyłącznie **Librusowi** — tak samo jak przy korzystaniu ze strony Synergii — w zakresie
potrzebnym do wyświetlenia danych i wykonania czynności, które zlecasz (np. wysłanie
wiadomości). Librus przetwarza je według własnych zasad i umowy ze szkołą.
Żadnym innym podmiotom.

## Kopie zapasowe i przenoszenie

Aplikacja **wyłącza** kopię zapasową Androida/Google — sesja i robocze nie trafiają do chmury
ani na nowy telefon. Na nowym telefonie trzeba się zalogować ponownie.

## Usunięcie danych

- **Wyloguj** — usuwa sesję, dane przeglądarki logowania, robocze wiadomości i stan
  powiadomień z telefonu oraz kończy sesję po stronie Librusa (o ile jest połączenie).
- **Odinstalowanie** — Android usuwa wszystkie dane aplikacji.
- Dane w Librusie (dziennik) nie są zmieniane — ich dotyczą zasady Librusa i szkoły.

## Uprawnienia Androida

| Uprawnienie | Po co |
|---|---|
| Internet, stan sieci | połączenie z Librusem; sprawdzanie dostępności sieci |
| Powiadomienia | tylko jeśli włączysz powiadomienia (w tej wersji sprawdzanie w tle jest wyłączone) |
| Uruchamianie po starcie telefonu, blokada uśpienia, wibracje | wymagane przez systemowe biblioteki harmonogramu i powiadomień; w tej wersji nieużywane do działań w tle |

Aplikacja **nie** ma dostępu do lokalizacji, kontaktów, aparatu, mikrofonu ani plików
(poza plikiem wybranym przez Ciebie jako załącznik w oficjalnym formularzu Librusa).

## Dzieci

Aplikacja jest przeznaczona dla **rodziców/opiekunów** korzystających z konta rodzica.
Wyświetla dane dziecka udostępnione rodzicowi przez szkołę w Synergii.

## Kontakt i zmiany

Pytania: `<e-mail>`. Zmiany tej informacji będą opisywane w liście zmian kolejnych wersji.

---

## Kwestie otwarte (do przeglądu, nie dla testerów)

1. **Rola w rozumieniu RODO.** Udostępniający nie przetwarza danych osobowych użytkowników
   (brak serwera, brak dostępu) — do potwierdzenia, czy w takim modelu ma obowiązki
   administratora; prawdopodobnie „przetwarzanie” zachodzi wyłącznie na urządzeniu
   użytkownika w celach osobistych. Wymaga opinii prawnej.
2. **Dane dzieci** — aplikacja wyświetla dane szczególnie chronionej grupy; ocenić
   wymogi informacyjne.
3. **Zgodność z regulaminem Synergii i umową szkoła–Librus** — zob. [docs/analysis.md §3](../analysis.md)
   i [docs/release-readiness.md](../release-readiness.md).
4. **Kanał kontaktu i zgłaszania naruszeń** — do ustalenia przed betą.
