# HackerOS-Installer

Instalator HackerOS — dwie edycje, jedna wspólna logika.

```
HackerOS-Installer/
├── Bytes.hk              workspace bytes (member: main, standard, server-edition)
├── main/                 rdzeń instalatora — H#, biblioteka (emit => lib)
│   └── src/
│       ├── lib.h#         punkt wejścia pakietu / re-eksport modułów
│       ├── model.h#        model danych (Step, Disk, UserAccount, InstallConfig, InstallResult)
│       ├── steps.h#         kolejność kroków kreatora + nawigacja
│       ├── system_scan.h#    wykrywanie dysków / RAM / UEFI / hostname
│       ├── locales.h#         listy język / klawiatura / strefa czasowa
│       ├── validate.h#         walidacja per krok
│       ├── plan.h#              plan powłoki (partycjonowanie, fstab, chroot, GRUB, konto)
│       ├── installer_run.h#      wykonanie planu + log + raport
│       └── config_io.h#           zapis podsumowania (JSON) + linie na ekran Summary
├── standard/              Standard Edition — GUI, w 100% Silver + H#
│   ├── Bytes.hk             -> include => ../main/src, deps: silver
│   ├── src/main.h#           WYŁĄCZNIE interfejs (żadnej logiki instalacji)
│   └── frontend/
│       ├── index.html         statyczny podgląd/dev fallback (patrz main.h#)
│       ├── style.css           arkusz stylów
│       └── fonts/                 dodaj tu .ttf przed uruchomieniem, patrz fonts/README.md
└── server-edition/        Server Edition — TTY/TUI, oparty o `tui`
    ├── Bytes.hk             -> include => ../main/src, deps: tui
    └── src/main.h#            WYŁĄCZNIE interfejs (żadnej logiki instalacji)
```

## Zasada podziału

Cała logika instalacji — model danych, wykrywanie sprzętu, budowa
planu partycjonowania/formatowania/bootloadera, wykonywanie komend,
walidacja i serializacja podsumowania — żyje wyłącznie w `main/`.
Ani `standard/src/main.h#`, ani `server-edition/src/main.h#` nie
wywołują `process::run`/`fs::*` do celów instalacji bezpośrednio —
obie edycje dołączają `main/src` przez `-> include` w swoim `Bytes.hk`
i korzystają z tych samych modułów (`model`, `steps`, `system_scan`,
`locales`, `validate`, `installer_run`, `config_io`). Różnią się
wyłącznie interfejsem:

* **standard** — Silver (GUI okienkowe, HTML/CSS renderowane własnym
  silnikiem), cały ekran generowany dynamicznie w `main.h#` i
  podmieniany przez `app::load_html_str` przy każdej interakcji;
  wybór z listy (język/klawiatura/strefa/dysk) to "karuzela" ◀ / ▶,
  bo silnik Silver nie potrafi wyrenderować listy o dynamicznej
  długości.
* **server-edition** — `tui` (Model→Update→View, terminal/TTY, bez
  X-a/Waylanda), ta sama lista wyboru korzysta wprost z gotowego
  `tui::ListModel` (strzałki ↑/↓).

Obie edycje mają identyczną kolejność kroków (Welcome → Language →
Keyboard → Timezone → Disk → Account → Summary → Installing → Done,
patrz `main/src/steps.h#`) i identyczną walidację — zmiana reguł w
`main/src/validate.h#` albo `main/src/plan.h#` działa jednocześnie
w obu interfejsach.

## Budowanie

```
bytes build --release                    # cały workspace
bytes build --release standard           # tylko GUI
bytes build --release server-edition     # tylko TUI
```

Tryb deweloperski (bez pełnego builda):

```
cd standard        && bytes run
cd server-edition   && bytes run
```

`standard` wymaga pliku `.ttf` w `standard/frontend/fonts/` — patrz
`standard/frontend/fonts/README.md`.

## Ograniczenia (v0.1)

* Partycjonowanie obsługuje wyłącznie tryb "wymaż cały dysk"
  (`erase_disk = true`) — ręczny podział na partycje nie jest jeszcze
  obsługiwany (patrz `main/src/plan.h#`).
* Żadna z dwóch edycji nie ma dostępu do wątków w tym środowisku —
  `installer_run::run_install` jest wywoływane synchronicznie z
  ekranu Summary, więc interfejs (GUI i TTY) nie odpowiada przez czas
  trwania rzeczywistej instalacji. Oba ekrany informują o tym wprost
  przed startem.
* Zakłada system bazowy dostarczany jako `/run/hackeros/airootfs.sfs`
  na nośniku live oraz toolchain typu arch-install-scripts
  (`arch-chroot`, `genfstab`) w środowisku live.
