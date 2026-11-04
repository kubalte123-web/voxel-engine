# Voxel Engine (nazwa robocza)

Darmowa gra voxelowa na PC, w której cała rozgrywka powstaje z modów. Etap 1: szkielet.

- `game/` – projekt Godot 4.6 (GDScript): świat, gracz, interfejs, sterowanie dotykowe
- `native/` – rdzeń w C++ (GDExtension): przygotowanie chunków i budowa siatek
- `.github/workflows/build.yml` – automatyczne budowanie wersji na Windowsa i do przeglądarki

## Sterowanie

PC: WASD ruch, Spacja skok, LPM kop, PPM postaw, 1–5 lub kółko wybór bloku, V widok, Esc kursor.
Telefon: joystick po lewej, przeciąganie po prawej obraca kamerę, przyciski Skok, Kop, Postaw.

## Testy lokalne

`godot --headless --path game -s tests/bench.gd` porównuje budowę siatek w GDScript i C++.
