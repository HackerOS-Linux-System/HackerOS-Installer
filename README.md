# HackerOS-Installer 0.2

Instalator HackerOS — dwie edycje, jedna wspólna logika. Wersja 0.2 działa na
**Silver 0.4**, buduje się przez **Bit** (`Bit.hk`) i nie zamraża interfejsu
podczas instalacji.

```
HackerOS-Installer/
├── Bit.hk                    workspace Bit (members: main, standard, server-edition)
├── build.hl
├── main/                     rdzeń — H#, biblioteka (hlib), bez żadnego UI
│   ├── Bit.hk
│   ├── runtime/runner.sh      wykonawca planu (powłoka; testowany prawdziwym sh)
│   └── src/
│       ├── lib.h#              punkt wejścia pakietu
│       ├── model.h#             model danych
│       ├── util.h#              sh_quote, run_rc (prawdziwy kod wyjścia), kv_get
│       ├── steps.h#             kolejność kroków + nawigacja (Partycje tylko w trybie ręcznym)
│       ├── system_scan.h#       dyski, partycje, wolne miejsce, os-prober, UEFI
│       ├── network.h#           Wi-Fi (nmcli), test sieci, serwery lustrzane
│       ├── profiles.h#          profile: minimal / desktop / server-tools
│       ├── locales.h#           język / klawiatura / strefa
│       ├── validate.h#          walidacja per krok
│       ├── plan.h#              plan: auto / obok innych systemów / ręczny, LUKS, GRUB, hooki
│       ├── runner_embed.h#      GENEROWANY z runtime/runner.sh (tools/embed_runner.py)
│       ├── installer_run.h#     start/poll/result/probe + preview_plan
│       └── config_io.h#         JSON (zapis/odczyt do wznawiania) + linie Summary
├── standard/                 GUI — Silver 0.4
├── server-edition/           TTY — tui
├── tools/embed_runner.py     runner.sh → runner_embed.h#
└── tests/test_runner.sh      testy wykonawcy (sh)
```

## Kroki kreatora

Welcome → Język → Klawiatura → Strefa → **Sieć** → **Dysk** → *Partycje (tylko tryb ręczny)* → **Profil** → Konto → Podsumowanie → Instalacja → Gotowe

## Co nowego w 0.2

**Partycjonowanie**
- Trzy tryby: *wymaż cały dysk*, *obok istniejących systemów* (dual-boot), *ręcznie*.
- Dual-boot: `os-prober` wykrywa inne systemy; instalator tworzy partycje w największym wolnym obszarze, istniejące zostają nietknięte, a istniejącą partycję EFI używa bez formatowania. GRUB dostaje włączony os-prober.
- Tryb ręczny: punkt montowania, system plików i „formatuj / zachowaj dane” per partycja, z walidacją (`/`, EFI w UEFI, `/boot` przy LUKS, brak duplikatów, tylko partycje wybranego dysku).
- LUKS2 (hasło + potwierdzenie) z osobną niezaszyfrowaną `/boot`; hook `encrypt`/`sd-encrypt` (mkinitcpio) lub `rd.luks.*` (dracut), crypttab, parametry jądra.
- ESP montowane w `/boot/efi` (kernel zostaje na partycji root, dzięki czemu współdzielone ESP nie jest zaśmiecane).

**Instalacja bez zamrażania UI**
- `installer_run::start` zapisuje plan i uruchamia `runner.sh` w tle; interfejsy odpytują `poll()` w `on_tick` (Silver) / w komunikacie „tick” (tui). Zamknięcie okna nie zabija instalacji.

**Odporność na błędy**
- Prawdziwe kody wyjścia: `runner.sh` uruchamia każdy krok w podpowłoce i zapisuje `rc` (koniec z heurystyką `looks_like_failure`). Kroki mają flagi: `c` (miękki błąd → ostrzeżenie), `s` (sekretne: nie logowane), `a` (zawsze przy wznawianiu).
- Wznawianie: checkpoint + odcisk planu (bez kroków sekretnych). Zmiana konfiguracji = bezpieczny start od zera. Config zapisywany przez `config_io::save_resume` (bez haseł); Welcome oferuje jego wczytanie.
- Hasła haszowane (`openssl passwd -6`, przez stdin), `chpasswd -e`; wszystko od użytkownika przechodzi przez `util::sh_quote` — usunięty błąd z zagnieżdżonymi cudzysłowami w `useradd -c`.
- Ochrona przed wyborem dysku z nośnikiem live (`hos_check_target`).

**Sieć**: ekran Wi-Fi (skan, hasło, łączenie w tle przez `nmcli`) i wybór serwera lustrzanego (domyślny / reflector / lista z `/etc/hackeros-installer/mirrors.conf` / własny URL).

**Pakiety**: profile `minimal` / `desktop` / `server-tools` (własny obraz `.sfs` z fallbackiem do `airootfs.sfs` + pakiety; nadpisywalne `/etc/hackeros-installer/profiles.conf`) oraz hooki post-install instalujące **H#** i **bit** w nowym systemie.

**UX**: osobne pole hasła roota (puste = zablokowany), potwierdzenia haseł, prawdziwe pola `type=password` w GUI i maskowanie w TTY, rozwijany podgląd pełnego planu (`installer_run::preview_plan`) na Summary.

## Budowanie

```
bit build                 # cały workspace
cd standard && bit run     # GUI (wymaga .ttf w frontend/fonts/, patrz fonts/README.md)
cd server-edition && bit run   # TTY — tylko interpreter (patrz README biblioteki tui)
```

Po zmianie `main/runtime/runner.sh`:

```
python3 tools/embed_runner.py     # albo: bit embed
sh tests/test_runner.sh           # albo: bit test
```

## Pliki konfiguracyjne (opcjonalne, na ISO live)

| Plik | Format linii |
|---|---|
| `/etc/hackeros-installer/profiles.conf` | `id\|etykieta\|opis\|obraz.sfs\|pakiet1 pakiet2 …` |
| `/etc/hackeros-installer/mirrors.conf`  | `id\|etykieta\|bazowy URL` (bez `/$repo/os/$arch`) |

Obrazy profili: `/run/hackeros/<obraz>.sfs`; gdy brak, używany jest `airootfs.sfs`.

## Ograniczenia

- Kod H# **nie był kompilowany** w środowisku, w którym powstał (brak toolchainu `h#`/`bit`); sprawdzono natomiast `runner.sh` testami na prawdziwym `sh` oraz statyczną kontrolą składni bloków H#. Pierwszy build może wskazać drobne literówki.
- Wolne miejsce w trybie dual-boot wykrywa `parted`; zmniejszanie istniejących partycji (np. NTFS) robisz osobno (GParted) — instalator tego nie robi.
- Szyfrowanie: root na LUKS2 wymaga niezaszyfrowanej `/boot`; GRUB nie odblokowuje LUKS.
- Serwer lustrzany zapisywany jest do `/etc/pacman.d/mirrorlist` nowego systemu.
- Znaki spoza ASCII wpisywane w TTY nie przechodzą przez `tui` poprawnie (ograniczenie interpretera H#, opisane w README `tui`).
