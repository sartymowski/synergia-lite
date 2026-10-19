# Wydania Androida — procedura dla prowadzącego projekt

Dotyczy ręcznej dystrybucji APK (zamknięta beta). Dokumenty dla testerów:
[docs/beta/](beta/). Checklista każdego wydania: [docs/beta/release-checklist.md](beta/release-checklist.md).

## 1. Zasady

- Każde wydanie jest podpisane **tym samym kluczem wydań**. Klucz debug nigdy nie
  podpisuje wydań — Gradle przerywa build release bez klucza wydań
  (`android/app/build.gradle.kts`, zadanie `preReleaseBuild`).
- Klucz, jego hasło i konfiguracja podpisu **nigdy** nie trafiają do repozytorium
  (`.gitignore`: `*.jks`, `*.keystore`, `*.p12`, `key.properties`,
  `release-signing.properties`, `/dist/`).
- Hasło nie jest zapisywane w żadnym pliku: podaje się je przy budowaniu (pytanie
  w terminalu) albo w zmiennej `SYNERGIA_KEYSTORE_PASSWORD` bieżącej sesji.
- Build dla testerów nie ma żadnej flagi eksperymentalnej (fail-closed, `lib/app/build_config.dart`).
- APK odpowiada commitowi: skrypt odmawia budowania przy niezacommitowanych zmianach.

## 2. Identyfikator i wersje

| Element | Wartość / zasada |
|---|---|
| `applicationId` | `pl.synergialite.synergia_lite` — bez słowa „librus”; **nie zmieniać** po pierwszym wydaniu (zmiana = inna aplikacja, testerzy tracą aktualizacje) |
| Wersja widoczna | `versionName` z `pubspec.yaml`, np. `1.0.0-beta.1` (SemVer z sufiksem bety) |
| `versionCode` | liczba po `+` w `pubspec.yaml`; **każde** wydanie o 1 wyżej niż poprzednie. `1` zajęły buildy deweloperskie, pierwsza beta: `2` |
| Numer buildu | = `versionCode` |
| Nazwa wydania | `Synergia Lite <versionName>` (manifest wydania) |
| Data wydania | `builtAtUtc` w manifeście wydania |

Przykład kolejnych wydań: `1.0.0-beta.1+2` → `1.0.0-beta.2+3` → `1.0.0-beta.3+4` → `1.0.0+5`.
Skrypt odmawia zbudowania wydania o `versionCode` nie wyższym niż ostatnie w `dist\`.

> Uwaga o zgodności: buildy deweloperskie (`1.0.0+1`) były podpisane kluczem debug.
> Wydania beta (klucz wydań) **nie zainstalują się na nich jako aktualizacja** — trzeba
> raz odinstalować wersję deweloperską (zob. [installation-android.md](beta/installation-android.md#jeśli-masz-wersję-deweloperską)).

## 3. Klucz wydań — pierwsze utworzenie (jednorazowo)

W **swoim** terminalu PowerShell (skrypt pyta o hasło, niewidoczne podczas wpisywania):

```powershell
cd "D:\Synergia Lite"
.\tool\create_release_keystore.ps1
```

Powstaje (poza repozytorium):

- `%USERPROFILE%\.synergia-lite\synergia-lite-release.p12` — klucz (RSA 4096, PKCS12, ważny ~27 lat),
- `%USERPROFILE%\.synergia-lite\release-signing.properties` — ścieżka i alias, **bez haseł**.

Skrypt nie nadpisze istniejącego klucza. Wypisuje odcisk SHA-256 certyfikatu —
wpisz go do [installation-android.md](beta/installation-android.md) (to wartość publiczna;
testerzy porównują ją z podpisem APK).

### Hasło

Wymyśl długie hasło (≥ 12 znaków, najlepiej fraza z 4–5 słów) i zapisz je w menedżerze
haseł (np. Bitwarden, KeePassXC, menedżer w przeglądarce z hasłem głównym). Nie zapisuj
go w repozytorium, w notatce na pulpicie ani w czacie.

### Kopia zapasowa (obowiązkowa)

Utrata klucza **albo** hasła = testerzy nie zainstalują aktualizacji bez odinstalowania
(i utraty lokalnych danych). Dlatego:

1. Skopiuj `synergia-lite-release.p12` w **dwa** niezależne miejsca, np. zaszyfrowany
   pendrive trzymany w domu + zaszyfrowany sejf w menedżerze haseł (załącznik do wpisu)
   albo zaszyfrowane archiwum 7-Zip (AES-256) w chmurze.
2. Hasło przechowuj osobno od pliku (menedżer haseł). Plik bez hasła jest bezużyteczny
   dla złodzieja, ale i dla Ciebie.
3. Zanotuj w menedżerze haseł: alias `synergia-lite-release`, odcisk SHA-256, datę utworzenia.
4. Raz na kwartał sprawdź, że kopia się otwiera:
   `keytool -list -keystore <kopia>.p12` (pyta o hasło).

### Odtworzenie na nowym komputerze

1. Zainstaluj Flutter, Android Studio (JDK + Android SDK, build-tools) i Git.
2. Sklonuj repozytorium, `flutter pub get`.
3. Skopiuj `synergia-lite-release.p12` z kopii do `%USERPROFILE%\.synergia-lite\`.
4. Utwórz `%USERPROFILE%\.synergia-lite\release-signing.properties`:
   ```properties
   storeFile=C:/Users/<użytkownik>/.synergia-lite/synergia-lite-release.p12
   keyAlias=synergia-lite-release
   ```
5. `.\tool\build_release.ps1` — skrypt porówna certyfikat APK z kluczem; porównaj też
   odcisk z zapisanym w menedżerze haseł / w [installation-android.md](beta/installation-android.md).

Inna lokalizacja konfiguracji: parametr `-SigningProperties` albo zmienna `SYNERGIA_SIGNING_PROPERTIES`.

## 4. Budowanie wydania

```powershell
# 1. podnieś version w pubspec.yaml (versionName i versionCode), uzupełnij CHANGELOG
#    w docs/beta/known-issues.md / opis wydania, commit
# 2. build
.\tool\build_release.ps1
```

Skrypt kolejno:

1. sprawdza narzędzia (Flutter, Git, keytool, apksigner, aapt2),
2. sprawdza wersję i to, że `versionCode` rośnie względem `dist\`,
3. sprawdza konfigurację podpisu (plik bez haseł, keystore poza repozytorium), pyta o
   hasło i otwiera klucz (złe hasło = koniec przed kompilacją; klucz debug odrzucany),
4. wymaga czystego stanu Git,
5. `dart format --set-exit-if-changed`, `flutter analyze`, `flutter test`,
6. `flutter build apk --release` (przez `tool\flutter_android.ps1` — magazyn zaufania
   dla Avasta, bez wyłączania TLS) z jedyną flagą `SYNERGIA_VERSION`,
7. `apksigner verify`: podpis v2, jeden sygnatariusz, certyfikat = klucz wydań, nie debug;
   `aapt2`: pakiet, wersja zgodna z pubspec, brak `debuggable`, lista uprawnień,
8. zapisuje do `dist\`:
   - `synergia-lite-<versionName>-<versionCode>.apk`,
   - `….apk.sha256` (format `sha256sum`),
   - `….release.json` — wersja, `versionCode`, `applicationId`, SHA-256 pliku i
     certyfikatu, rozmiar, data UTC, commit, uprawnienia, flagi (bez sekretów).

Na koniec usuwa hasło ze zmiennych środowiskowych i zatrzymuje demona Gradle.
Istniejący plik w `dist\` nigdy nie jest nadpisywany.

APK jest uniwersalny (arm64, armv7, x86_64; ok. 55 MB) — jeden plik dla wszystkich
telefonów, prostszy dla testerów niż pliki na architekturę.

## 5. Tag wydania

Dopiero **po** przejściu [release-checklist.md](beta/release-checklist.md):

```powershell
git tag -a v1.0.0-beta.1 -m "Synergia Lite 1.0.0-beta.1 (versionCode 2), SHA-256 APK: <sha256>"
```

Bez `git push` i bez publikowania release'u, dopóki właściciel projektu tego nie zdecyduje.

## 6. Dystrybucja i aktualizacje (ręczne)

- Kanał: jeden, z góry znany testerom (np. folder współdzielony na Dysku Google /
  OneDrive tylko dla zaproszonych osób). Obok APK: plik `.sha256` i lista zmian.
  Wiadomość do testerów zawiera wersję i SHA-256 (drugi kanał niż plik — np. e-mail
  lub grupa rodziców), żeby podmiana pliku była wykrywalna.
- Aktualizacja = nowy APK, ten sam klucz, wyższy `versionCode`; Android instaluje go
  na poprzednim **z zachowaniem danych** (sesja, robocze). Instrukcja: [updating-android.md](beta/updating-android.md).
- Aplikacja nie pobiera ani nie instaluje aktualizacji sama (świadomie — brak serwera,
  brak uprawnienia `REQUEST_INSTALL_PACKAGES`).

### Wycofanie wadliwego wydania

Android **nie pozwala** zainstalować niższego `versionCode` na wyższym bez odinstalowania
(co usuwa dane lokalne i sesję). Dlatego wycofanie = wydanie poprawki do przodu:

1. Usuń wadliwy APK z folderu dystrybucji (zostaw notkę „wycofane: <wersja>, powód”).
2. Powiadom testerów: czego nie robić do czasu poprawki (np. „nie używaj formularza X”).
3. Zbuduj poprawkę: kod poprzedniej dobrej wersji (np. `git revert` wadliwego commitu)
   z **wyższym** `versionCode`, np. `1.0.0-beta.3+5` po wadliwym `beta.2+4`.
4. Opisz w [known-issues.md](beta/known-issues.md) i w liście zmian.

Odinstalowanie i instalacja starszej wersji to ostateczność dla pojedynczej osoby
(utrata sesji i roboczych wiadomości; dane szkolne zostają w Librusie).

## 7. Sprawdzenie aktualizacji (przed pierwszą betą i przy zmianie procesu)

Na telefonie testowym: zainstaluj wydanie N, zaloguj się, utwórz roboczą wiadomość;
zainstaluj N+1 (`adb install -r` albo z pliku) — oczekiwane: brak pytania o
odinstalowanie, sesja i robocza wiadomość zostają. Wynik wpisz do release-checklist.
