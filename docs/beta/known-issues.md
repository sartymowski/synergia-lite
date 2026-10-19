# Synergia Lite — znane problemy i ograniczenia

Lista aktualizowana przy każdym wydaniu. Nowe wpisy na górze sekcji.
Format: `[wersja, od której dotyczy] opis — obejście — status`.

## Wersja 1.0.0-beta.1 (versionCode 2)

### Funkcje eksperymentalne / ograniczone

- [beta.1] **Logowanie** odbywa się na stronie Librusa wewnątrz aplikacji. To rozwiązanie
  testowe: zmiana strony logowania przez Librusa może je zepsuć. Obejście: „Zacznij od nowa”
  (strzałka) na ekranie logowania; jeśli nie pomoże — zgłoś błąd. — otwarte
- [beta.1] **e-Usprawiedliwienia — wysyłanie** odbywa się przez **oficjalny formularz
  Librusa** (przycisk „Nowe (Librus)”). Formularz w aplikacji („Formularz”) pozwala
  przygotować zgłoszenie, ale **nie wysyła** go — wysyłka z aplikacji nie została jeszcze
  potwierdzona testem. — świadomie wyłączone
- [beta.1] **Załączniki do usprawiedliwień** — tylko w oficjalnym formularzu Librusa,
  jeśli w ogóle zadziała wybór pliku w tym widoku. — niezweryfikowane
- [beta.1] **Powiadomienia o nowych wiadomościach w tle są wyłączone.** Regulamin Synergii
  nie określa wprost, czy aplikacja może automatycznie sprawdzać skrzynkę. Nowe wiadomości
  widać po otwarciu zakładki „Wiadomości”. — świadomie wyłączone
- [beta.1] **Oceny**: aplikacja nie była jeszcze sprawdzona na koncie z ocenami w bieżącym
  roku (konto testowe ich nie miało). Średnie są **orientacyjne** (liczone w aplikacji,
  mogą różnić się od wyliczeń szkoły). Prosimy o porównanie z Librusem. — do weryfikacji
- [beta.1] **Usprawiedliwienia według lekcji** (nie całych dni) nie były jeszcze widziane
  na prawdziwych danych. — do weryfikacji
- [beta.1] **Wysyłanie nowej wiadomości** (nie odpowiedzi) nie było jeszcze potwierdzone na
  żywym koncie. Przed wysłaniem aplikacja pokazuje podsumowanie; jeśli wynik jest
  „nie wiadomo”, sprawdź folder „Wysłane”, zanim spróbujesz ponownie. — do weryfikacji
- [beta.1] Status usprawiedliwienia „odrzucone” — aplikacja nie zna jeszcze jego kodu
  i pokaże go dosłownie („Status: …”). — do weryfikacji

### Ograniczenia znane

- [beta.1] Jedno konto naraz. Zmiana konta = wyloguj i zaloguj innym kontem
  (robocze wiadomości poprzedniego konta są usuwane).
- [beta.1] Aplikacja działa tylko z internetem — nie przechowuje kopii danych offline.
- [beta.1] Brak trybu dla ucznia, brak frekwencji, terminarza i ogłoszeń (poza zakresem bety).
- [beta.1] Brak wersji na iPhone'a.
- [beta.1] Plik APK ma ok. 55 MB (jeden plik dla wszystkich telefonów).

## Historia zmian

### 1.0.0-beta.1 (versionCode 2) — pierwsza zamknięta beta

- Logowanie przez stronę Librusa, oceny, plan lekcji, wiadomości (odebrane, wysłane,
  robocze, nowa wiadomość, odpowiedź), historia e-Usprawiedliwień, oficjalny formularz.
- Ekran „O aplikacji” (wersja, licencje), wyłączone narzędzia diagnostyczne.
