# Voxel Engine (nazwa robocza)

Darmowa gra voxelowa na PC, w której cała treść i rozgrywka powstaje z modów w Lua. Silnik zna tylko
powietrze: bloki, przedmioty, biomy, zasady, kamera i animacje pochodzą z modów (także podstawowy świat).

- `game/` – projekt Godot 4.6 (GDScript): świat, gracz, interfejs, menu, system modów
- `game/mods/` – mody dołączone do gry (podstawowy świat i przykłady)
- `native/` – rdzeń w C++ (GDExtension): generowanie świata z danych modów i budowa siatek
- `docs/MODDING.md` – instrukcja tworzenia modów, `llms.txt` – punkt startowy dla AI
- `.github/workflows/build.yml` – automatyczne budowanie wersji na Windowsa i do przeglądarki

## Sterowanie

PC: WASD ruch, Spacja skok, LPM kop, PPM postaw lub użyj przedmiotu, 1–9 lub kółko wybór przedmiotu,
V widok, Esc pauza. Klawisze z modów: E plecak, G machnięcie, H taniec, C tryb kamery.
Telefon: joystick po lewej, przeciąganie po prawej obraca kamerę, przyciski akcji i przyciski modów u góry.

## Testy lokalne

- `godot --headless --path game -s tests/bench.gd` – czy generator i siatki w C++ dają to samo co GDScript.
- `godot --path game -- --shots=FOLDER` – przejście przez menu i grę ze zrzutami ekranu.
