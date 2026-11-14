# frontend/fonts/

Silver rysuje tekst fontem ładowanym przez `app::with_font`
(`standard/src/main.h#` → `frontend/fonts/DejaVuSans.ttf`).

W repozytorium jest **DejaVu Sans 2.37** (wydanie oficjalne, licencja w
`DejaVu-LICENSE.txt` — swobodna redystrybucja). Zawiera polskie znaki
diakrytyczne (ą ć ę ł ń ó ś ź ż) oraz symbole używane w interfejsie
(✓ • · — „ ” … →).

Chcesz inny font? Podmień plik `.ttf` o tej samej nazwie albo zmień
`font_path()` w `standard/src/main.h#`. Wybierz font, który obsługuje
polskie znaki (DejaVu Sans, Noto Sans itp.). Gdy pliku nie ma, GUI
startuje bez `with_font` (domyślny font Silvera) — ale wtedy nie mamy
gwarancji, że wszystkie polskie znaki się wyświetlą.
