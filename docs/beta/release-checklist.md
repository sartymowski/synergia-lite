# Checklista wydania (Android)

Kopiuj tę listę do opisu każdego wydania i odhaczaj. **Tag `v<wersja>` i rozesłanie
APK dopiero, gdy wszystkie punkty „blokujące” (B) są spełnione.** Procedura: [docs/release.md](../release.md).

Wydanie: `__________` (versionCode `___`) · commit `________` · data `________`

## 1. Przed buildem

- [ ] (B) `version` w `pubspec.yaml` podniesiona; `versionCode` > poprzedni
- [ ] (B) lista zmian i [known-issues.md](known-issues.md) zaktualizowane
- [ ] (B) wszystkie zmiany zacommitowane, brak sekretów w diffie
      (`git diff <poprzedni-tag>..HEAD` — szukaj: hasło, cookie, token, DZIENNIKSID, oauth, nazwiska)
- [ ] (B) flagi eksperymentalne nie są przekazywane (skrypt wydania tego pilnuje)

## 2. Build (`.\tool\build_release.ps1`)

- [ ] (B) format, analiza, testy — zielone
- [ ] (B) `apksigner`: podpis v2 OK, certyfikat = klucz wydań (odcisk zgodny z [installation-android.md](installation-android.md))
- [ ] (B) `aapt2`: `applicationId` `pl.synergialite.synergia_lite`, wersja zgodna, brak `debuggable`
- [ ] (B) uprawnienia bez zmian względem poprzedniego wydania albo zmiana uzasadniona
      (beta.1: INTERNET, POST_NOTIFICATIONS, ACCESS_NETWORK_STATE, WAKE_LOCK,
      RECEIVE_BOOT_COMPLETED, VIBRATE, `…DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION`)
- [ ] `dist\…release.json` i `.sha256` zapisane

## 3. Instalacja na telefonie testowym

- [ ] (B) czysta instalacja (`adb install dist\….apk` albo z pliku) — aplikacja startuje
- [ ] (B) aktualizacja z poprzedniego wydania: bez odinstalowania, sesja i robocze zostają
      (przy pierwszej becie: aktualizacja beta.1 → testowy build beta.1 z wyższym `versionCode`, zob. release.md §7)
- [ ] (B) „Ustawienia → O aplikacji”: właściwa wersja, „Funkcje eksperymentalne: Wyłączone”
- [ ] (B) brak ikony diagnostyki na ekranie głównym; brak przycisków „debug”
- [ ] (B) `chrome://inspect` na komputerze **nie** pokazuje WebView aplikacji

## 4. Testy ręczne (prawdziwe konto, bez wysyłania niczego automatycznie)

Szczegóły kroków: [testing-guide.md](testing-guide.md). Wynik: OK / BŁĄD (nr zgłoszenia) / nie dotyczy.

| # | Scenariusz | Wynik |
|---|---|---|
| 1 | (B) Logowanie przez portal → oceny | |
| 2 | (B) Ponowne uruchomienie aplikacji — nadal zalogowany | |
| 3 | (B) Oceny: lista i średnie zgodne z Librusem (lub „brak ocen”) | |
| 4 | (B) Plan lekcji: bieżący i następny tydzień | |
| 5 | (B) Wiadomości: odebrane, szczegóły, wysłane | |
| 6 | Nowa wiadomość: robocza zapisuje się; **wysłanie tylko świadomie, do siebie/testowo** | |
| 7 | (B) e-Usprawiedliwienia: historia i szczegóły zgodne z Librusem | |
| 8 | (B) „Nowe (Librus)” otwiera oficjalny formularz (bez wysyłania) | |
| 9 | (B) „Formularz” w aplikacji: przycisk wysyłki nieaktywny, informacja o oficjalnym formularzu | |
| 10 | (B) Tryb samolotowy: czytelny komunikat, brak awarii, po powrocie sieci „Odśwież” działa | |
| 11 | Wygasła sesja (np. wylogowanie na komputerze z „wyloguj wszędzie” lub po kilku godzinach): powrót do logowania z komunikatem | |
| 12 | (B) Wylogowanie: powrót do logowania, ponowne logowanie wymaga hasła | |
| 13 | Przełączenie konta (drugie konto rodzica, jeśli dostępne): brak danych/roboczych poprzedniego | |
| 14 | Ustawienia: przełącznik powiadomień w tle wyłączony z wyjaśnieniem | |
| 15 | Ciemny motyw i duża czcionka systemowa — czytelność | |

## 5. Po teście

- [ ] (B) brak otwartych błędów krytycznych (utrata danych, wyciek danych, wysłanie bez potwierdzenia, awaria przy starcie)
- [ ] tag: `git tag -a v<wersja> -m "…SHA-256…"` (bez push bez zgody właściciela)
- [ ] APK + `.sha256` + lista zmian w kanale dystrybucji; SHA-256 w wiadomości do testerów
- [ ] poprzednie wydanie oznaczone jako zastąpione
