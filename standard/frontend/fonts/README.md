# frontend/fonts/

Silver nie potrafi narysować żadnego tekstu bez załadowanego fontu
(patrz `app::with_font` w `silver-main/src/app.h#` i uwaga w README
biblioteki `silver`). Ten katalog jest celowo pusty w repozytorium —
dodaj tu dowolny plik `.ttf` przed uruchomieniem `standard-edition`,
np.:

```
curl -L -o frontend/fonts/DejaVuSans.ttf \
    https://github.com/dejavu-fonts/dejavu-fonts/raw/master/ttf/DejaVuSans.ttf
```

i upewnij się, że `standard/src/main.h#` wskazuje na właściwą nazwę
pliku w wywołaniu:

```
a = app::with_font(a, "frontend/fonts/DejaVuSans.ttf", 16)
```

Instalator używa polskich znaków diakrytycznych (ą, ć, ę, ł, ń, ó, ś,
ź, ż) w interfejsie — wybierz font, który je obsługuje (DejaVu Sans,
Noto Sans itp.).
