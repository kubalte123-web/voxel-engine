#!/usr/bin/env python3
"""Buduje docs/AI_MOD_SPEC.md: jedną specyfikację modów dla innych AI (llms.txt + MODDING.md + klucze + przykłady).
Uruchom z katalogu repozytorium: python3 tools/build_ai_spec.py"""
import os

def r(p):
    return open(p, encoding="utf-8").read()

INTRO = """# Specyfikacja modów – Voxel Engine (dla AI)

Ten plik wystarcza do napisania moda bez znajomości kodu gry. Zawiera: zasady i skrót (część 1),
pełną instrukcję tworzenia modów (część 2), listę kluczy istniejących w grze (część 3), najczęstsze
pułapki (część 4) i dwa wzorcowe mody (część 5).

## Jak oddać mod

Mod to folder `game/mods/<id>/` z plikami. Oddaj pełną treść każdego pliku, z nazwą pliku nad nim:
- `mod.json` (obowiązkowo; `id` = nazwa folderu, małe litery i podkreślenia),
- `content.lua` (rejestracja bloków, przedmiotów, dźwięków, cząsteczek, pocisków, przepisów świata),
- `main.lua` (logika: haki, zdarzenia, okna, aktualizacje bloków, trafienia pocisków),
- opcjonalnie tekstury PNG 16×16 – zamiast plików najlepiej używać wzorów (`{ pattern = "...", color = "#rrggbb" }`),
  bo plików binarnych nie da się przekazać w tekście; dźwięki – istniejące z innych modów.

Najważniejsze zasady (szczegóły niżej):
- Używaj WYŁĄCZNIE funkcji, pól i kluczy opisanych w tym pliku. Jeśli czegoś brakuje, nie zgaduj – napisz, czego brakuje.
- Lua 5.4 w piaskownicy: brak `io`, `os`, `require`, `load`, `debug`. Tylko obiekt `engine` i biblioteki
  standardowe `string`, `table`, `math`, `utf8`, `coroutine`, `pcall`.
- `register` działa tylko w plikach z pola `content`; reszta w plikach z pola `scripts`.
- Gra jest wieloosobowa: skrypty działają na serwerze „w imieniu” gracza; dane gracza trzymaj w
  `engine.player.storage` albo w kontenerach `engine.items.container(id, n, true, true)` tworzonych w `player.join`.
- Każde wywołanie moda ma limit czasu – nie rób długich pętli, rozkładaj pracę na `tick` albo `engine.blocks.schedule`.
- Teksty w grze po polsku.

---

# Część 1. Skrót dla AI (llms.txt)

"""

KEYS = """# Część 3. Klucze istniejące w grze (mody dołączone do gry)

Używaj tylko tych kluczy z innych modów (albo zarejestruj własne). Jeśli korzystasz z bloku/przedmiotu
innego moda, dodaj ten mod do `"requires"` (twarda zależność) albo `"after"` i sprawdź istnienie
przez `engine.items.def(klucz)` (miękka zależność). Czego nie ma na liście, tego nie ma w grze
(np. nie ma nici `string`, cukru, prochu, łuku ani strzał).

- **Bloki** – base: grass, dirt, stone, planks, sand, log, leaves, snow, cactus, tall_grass, flower_red,
  flower_yellow, glass, bricks, gravel, ice, bedrock, torch, lamp, water (płynąca: water~1 .. water~8);
  ores: cobblestone, coal_ore, iron_ore, ruby_ore; loose: crate, barrel, ball, boulder;
  crafting_classic: crafting_table; crafting_discovery: workbench; storage: chest; smelting: furnace;
  farming: farmland, wheat_crop; alchemy: cauldron.
- **Przedmioty** (oprócz przedmiotów-bloków o tych samych kluczach) – base: bucket, water_bucket;
  ores: coal, raw_iron, ruby; animals: wool, mutton, beef, chicken_meat, leather, feather, egg, milk_bucket,
  wheat, shears; survival: apple, bread; tools: stick, wooden_/stone_/iron_ + pickaxe/axe/shovel/sword;
  farming: seeds, wooden_hoe, stone_hoe; smelting: iron_ingot, cooked_beef, cooked_mutton, cooked_chicken;
  alchemy: glass_bottle, potion_speed, potion_jump, potion_feather, potion_heal (+ wersje _strong);
  fishing: raw_fish, cooked_fish, fishing_rod.
- **Stworzenia** (animals): sheep, cow, chicken.
- **Biomy** (base): meadow, forest, desert, snowy.
- **Grupy dźwięków bloków** (pole `sound`): stone, dirt, grass, sand, gravel, snow, leaves, wood, glass, water.
- **Dźwięki** (nazwy do `engine.sound.play`): `<grupa>.break`, `<grupa>.place`, `<grupa>.dig`, `<grupa>.step`,
  water.splash, water.swim, item.pickup, player.hurt, ui.click, sheep.say, cow.say, chicken.say, chest.open,
  furnace.fire, alchemy.bubbling, alchemy.done, alchemy.drink, alchemy.fail, alchemy.fill, alchemy.plop,
  fishing.splash. Pliki moda base (tylko do `engine.sounds.register`, jako `"base:sounds/..."`):
  sounds/<grupa>_break1..3.ogg, sounds/<grupa>_step1..3.ogg, sounds/pop.ogg, sounds/click.ogg, sounds/hurt.ogg,
  sounds/water_splash1..2.ogg, sounds/water_swim1..2.ogg.
- **Cząsteczki** (alchemy): alchemy.fire, alchemy.ember, alchemy.bubble, alchemy.steam, alchemy.glint,
  alchemy.splash, alchemy.sparkle, alchemy.smoke, alchemy.drink. Mod, który ich używa, dopisuje "alchemy" do "after".
- **Animacje postaci** (emotes): wave, dance, idle_look; (animals): animals_happy.
- **Biblioteki** (`engine.require` / `engine.optional`) i ich funkcje:
  - modkit: `kit.inventory.add(kontener, przedmiot, ile)` → ile się nie zmieściło; `add_many({kontenery}, przedmiot, ile)`;
    `take(kontener, miejsce, ile)` → ile zabrano; `remove({kontenery}, przedmiot, ile)`; `count({kontenery}, przedmiot)`;
    `kit.after(sekundy, fn)`, `kit.every(sekundy, fn)`, `kit.copy`, `kit.merge`, `kit.clamp`, `kit.patch`.
  - backpack: `give(przedmiot, ile)` → ile się nie zmieściło (pasek, potem plecak; nadmiar przepada z komunikatem „Plecak jest pełny”), stałe `HOTBAR`, `BACKPACK`, `EQUIPMENT`
    (id kontenerów gracza), `add_section(fn)`, `open()`.
  - crafting_classic: `shaped(wzór, klucz, wynik, ile)`, `shapeless({przedmiot = ile}, wynik, ile)`.
  - crafting_discovery: `add(id, {przedmiot = ile}, wynik, ile, sekundy)`.
  - smelting: `recipe(surowiec, wynik, ile_sztuk_wyniku)`, `fuel(przedmiot, sekundy_palenia)`.
  - alchemy: `recipes`, `ingredients`, `colors` (tabele tylko do odczytu).
- **Tekstury moda base** (jako `"base:textures/..."`): dirt.png, stone.png, planks.png, sand.png, leaves.png, snow.png,
  grass_top.png, grass_side.png, log_side.png, log_top.png, cactus_side.png, cactus_top.png, tall_grass.png,
  flower_red.png, flower_yellow.png. Innych plików nie ma (cegły, szkło, rudy itp. są rysowane wzorami).
"""

PITFALLS = """# Część 4. Najczęstsze pułapki

- `engine.blocks.id(klucz)` zwraca **-1** (nie `nil`), gdy klucz nie jest blokiem. Sprawdzaj `id > 0`.
- `engine.items.def(klucz)` zwraca `nil`, gdy przedmiotu nie ma – tak sprawdzaj miękkie zależności.
- `engine.sound.play(nazwa)` przyjmuje **nazwę zarejestrowanego dźwięku**, nie ścieżkę pliku. Ścieżki plików
  podaje się tylko w `engine.sounds.register`.
- Tekstury: wzór (`pattern`) albo plik wymieniony w Części 3 albo PNG własnego moda. Plik, którego nie ma,
  daje fioletową szachownicę.
- Argumenty funkcji bibliotek – patrz Część 3 (np. trzeci argument `smelting.recipe` to liczba sztuk wyniku).
- Zabieraj przedmioty z ekwipunku dopiero, gdy akcja się udała (najpierw sprawdź miejsce, cel, amunicję).
- Gracz celuje dalej niż zasięg kopania? Używaj `engine.player.raycast(zasięg)`, a nie `engine.player.target()`.
- Stan gracza w zmiennych Lua indeksuj `engine.player.id()` (gra wieloosobowa). W `tick` i licznikach czasu
  nie ma „bieżącego gracza” – używaj `engine.players.each(fn)`.
- Hak `before` przerywa działanie silnika tylko przez `ctx.cancel = true`. Hak na `slot.click` działa przy
  każdym kliknięciu w dowolnym oknie – sprawdzaj `ctx.container`.
- Każdy mod, którego klucze/cząsteczki/dźwięki/biblioteki używasz, wpisz do `"requires"` albo `"after"`.

---

# Część 5. Mody wzorcowe

"""

def example(mod):
    out = f"## Mod `{mod}`\n\n"
    for f in ["mod.json", "content.lua", "main.lua"]:
        p = f"game/mods/{mod}/{f}"
        if os.path.exists(p):
            lang = "json" if f.endswith(".json") else "lua"
            out += f"`{f}`\n\n```{lang}\n{r(p).rstrip()}\n```\n\n"
    return out

spec = (INTRO + r("llms.txt")
        + "\n\n---\n\n# Część 2. Instrukcja tworzenia modów (docs/MODDING.md)\n\n"
        + r("docs/MODDING.md").replace("# Tworzenie modów", "## Tworzenie modów", 1)
        + "\n\n---\n\n" + KEYS + "\n---\n\n" + PITFALLS + example("storage") + example("farming"))
open("docs/AI_MOD_SPEC.md", "w", encoding="utf-8").write(spec)
print(len(spec), "znaków,", spec.count("\n"), "linii")
