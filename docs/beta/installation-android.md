# Synergia Lite — instalacja na Androidzie (beta)

Synergia Lite to **nieoficjalna** aplikacja do przeglądania dziennika LIBRUS Synergia
z konta rodzica. **Nie jest produktem firmy Librus** i nie jest z nią związana.
Działa na Androidzie 7.0 lub nowszym. Na iPhone'a na razie jej nie ma.

To wersja testowa (beta): może zawierać błędy. Dane szkolne zawsze sprawdzisz też
w oficjalnej aplikacji lub na stronie Librusa.

## 1. Skąd pobrać plik

Plik instalacyjny (`synergia-lite-1.0.0-beta.1-2.apk`) dostaniesz **wyłącznie** od
osoby prowadzącej test, z miejsca podanego w zaproszeniu.

- Nie pobieraj aplikacji z innych stron, grup ani komunikatorów.
- Nie instaluj pliku przesłanego przez kogoś innego, nawet jeśli nazwa się zgadza.

## 2. Jak sprawdzić, że plik jest prawdziwy

W wiadomości z zaproszeniem dostaniesz **sumę kontrolną SHA-256** (ciąg 64 znaków)
pobranego pliku. Wystarczy porównać kilka pierwszych i ostatnich znaków.

Na komputerze z Windows (PowerShell):

```powershell
Get-FileHash .\synergia-lite-1.0.0-beta.1-2.apk -Algorithm SHA256
```

Na telefonie: dowolna aplikacja do sum kontrolnych (np. „Hash Checker”) albo
pomiń ten krok, jeśli plik pobierasz bezpośrednio z miejsca z zaproszenia.

Jeśli suma się **nie zgadza — nie instaluj** i daj znać prowadzącemu.

Dla zaawansowanych: certyfikat podpisu aplikacji ma odcisk SHA-256
`<UZUPEŁNIĆ po utworzeniu klucza wydań>`
(sprawdzisz go poleceniem `apksigner verify --print-certs`). Każda aktualizacja ma ten
sam odcisk.

## 3. Zezwolenie na instalację

Android domyślnie blokuje aplikacje spoza Sklepu Play. Przy pierwszej instalacji:

1. Otwórz pobrany plik (np. z powiadomienia o pobraniu albo w aplikacji „Pliki”).
2. Android pokaże komunikat, że ta aplikacja (np. przeglądarka lub „Pliki”) nie może
   instalować aplikacji. Stuknij **Ustawienia** i włącz **Zezwalaj z tego źródła**.
3. Wróć i stuknij **Zainstaluj**.
4. Jeśli pojawi się ostrzeżenie Google Play Protect o nieznanej aplikacji, możesz wybrać
   **Więcej szczegółów → Zainstaluj mimo to**. To ostrzeżenie dotyczy każdej aplikacji
   spoza Sklepu Play.
5. Po instalacji możesz z powrotem wyłączyć „Zezwalaj z tego źródła” (zalecane).

Nazwy opcji mogą się nieco różnić w zależności od producenta telefonu.

## 4. Logowanie do Synergii

1. Otwórz Synergia Lite. Zobaczysz **stronę Librusa** (portal Librus Rodzina).
2. Stuknij **Zaloguj** → **LIBRUS Synergia** i zaloguj się jak zwykle: login i hasło
   do Synergii (konto rodzica). Jeśli Librus pokaże weryfikację „czy jesteś człowiekiem”,
   wykonaj ją.
3. Po zalogowaniu aplikacja sama przejdzie do ocen.

Ważne:

- Hasło wpisujesz **na stronie Librusa**. Aplikacja go nie zna, nie zapisuje i nigdzie nie wysyła.
- Aplikacja zapamiętuje tylko sesję (tak jak przeglądarka zapamiętuje zalogowanie),
  zaszyfrowaną w telefonie. Po wygaśnięciu sesji poprosi o ponowne logowanie.
- Logowanie przez stronę Librusa wewnątrz aplikacji jest **rozwiązaniem testowym** — jeśli
  Librus zmieni stronę logowania, może przestać działać do czasu poprawki.

## 5. Wylogowanie i usunięcie danych

- **Wyloguj** (ikona drzwi w prawym górnym rogu) usuwa z telefonu: sesję, dane strony
  logowania, wiadomości robocze i ustawienia powiadomień.
- Całkowite usunięcie: **Ustawienia Androida → Aplikacje → Synergia Lite → Odinstaluj**.
  Aplikacja nie przechowuje niczego poza telefonem — nie ma własnego serwera.
- Dane w Librusie (oceny, wiadomości, usprawiedliwienia) nie są przez to zmieniane.

## 6. Jeśli masz wersję deweloperską

Osoby, które miały wcześniejszą wersję testową „1.0.0” (instalowaną bezpośrednio przez
prowadzącego), muszą ją **raz odinstalować** przed instalacją bety — Android nie pozwoli
jej zaktualizować, bo była podpisana innym kluczem. Utracisz tylko zalogowanie i
ewentualne robocze wiadomości z tamtej wersji (skopiuj je wcześniej, jeśli są ważne).

## 7. Co dalej

- Aktualizacje: [updating-android.md](updating-android.md)
- Jak testować i co sprawdzić: [testing-guide.md](testing-guide.md)
- Znane problemy: [known-issues.md](known-issues.md)
- Zgłaszanie błędów: [feedback-template.md](feedback-template.md)
- Prywatność: [privacy-policy-draft.md](privacy-policy-draft.md)
