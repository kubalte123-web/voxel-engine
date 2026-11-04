# Tworzenie modów

Gra jest pustym silnikiem: zna tylko powietrze. Bloki, przedmioty, biomy, drzewa, zasady i wygląd
dodają mody, łącznie z podstawowym światem (mod `base`). Każdy mod może zmienić to, co dodał inny.

Mod to folder z plikiem `mod.json` i skryptami w Lua 5.4. Gra wczytuje mody z dwóch miejsc:

- `res://mods/` – mody dołączone do gry,
- `user://mods/` – mody gracza (na Windowsie: `%APPDATA%/Godot/app_userdata/Voxel Engine/mods`).

Każdy mod działa we własnym, odizolowanym środowisku. Nie ma dostępu do plików, sieci ani systemu,
tylko do obiektu `engine` opisanego niżej.

## Dwie fazy: content i scripts

| Faza | Pliki w mod.json | Kiedy | Do czego |
| --- | --- | --- | --- |
| content | `"content": ["content.lua"]` | przed zbudowaniem świata, także w menu | rejestracja bloków, przedmiotów, biomów, rud, struktur, animacji; zmiany cudzych definicji |
| scripts | `"scripts": ["main.lua"]` | gdy świat i gracz już istnieją | haki, zdarzenia, okna, klawisze, paski na ekranie |

Oba rodzaje plików jednego moda dzielą środowisko (zmienne globalne moda). Funkcje `register` działają
tylko w fazie content; wywołane później zgłoszą błąd.

## mod.json

```json
{
	"id": "moj_mod",
	"name": "Mój mod",
	"version": "0.1.0",
	"author": "Ty",
	"description": "Co robi mod.",
	"requires": ["modkit"],
	"content": ["content.lua"],
	"scripts": ["main.lua"],
	"library": false,
	"required": false,
	"enabled_by_default": true,
	"settings": [
		{"key": "speed", "label": "Prędkość", "type": "float", "default": 1.0, "min": 0.5, "max": 3.0, "step": 0.1},
		{"key": "rows", "label": "Rzędy", "type": "int", "default": 3, "min": 1, "max": 6, "step": 1},
		{"key": "on", "label": "Włączone", "type": "bool", "default": true},
		{"key": "mode", "label": "Tryb", "type": "choice", "options": ["Łatwy", "Trudny"], "default": "Łatwy"},
		{"key": "blocks", "label": "Bloki", "type": "block_toggles", "default": true}
	]
}
```

| Pole | Znaczenie |
| --- | --- |
| `id` | Stały identyfikator, małe litery i podkreślenia |
| `requires` | Mody, które muszą być włączone; wczytają się przed tym modem |
| `content` | Pliki Lua fazy content (rejestracja treści) |
| `scripts` | Pliki Lua fazy scripts (logika w świecie) |
| `library` | Mod jest biblioteką dla innych (na liście trafia wyżej) |
| `settings` | Ustawienia widoczne w grze w ekranie Mody |

Rodzaje ustawień: `bool`, `int`, `float`, `choice` (lista `options`, wartość to tekst opcji) oraz
`block_toggles` (przełącznik dla każdego bloku w grze, także z innych modów; wartość to tabela
`klucz_bloku -> true/false`, brak wpisu oznacza wartość `default`).
Ustawienie z `"world": true` zapisuje się w świecie przy jego tworzeniu (np. wszystko, co zmienia teren).

Kolejność modów ustawia gracz w ekranie Mody. Serwer może ją wymusić razem z wartościami ustawień;
wtedy są one zablokowane i oznaczone „[serwer]”.

## Bloki

```lua
engine.blocks.register("ruby_ore", {
	name = "Ruda rubinu",
	texture = "textures/ruby_ore.png",          -- jedna tekstura na wszystkie ściany
	-- albo: textures = { top = "...", bottom = "...", side = "...", north/south/east/west = "..." }
	shape = "cube",          -- "cube" (domyślnie) albo "cross" (roślina z dwóch skrzyżowanych ścian)
	transparent = false,     -- true: blok nie zasłania sąsiadów (szkło, liście z dziurami)
	solid = true,            -- kolizja z graczem
	drops = "ruby",          -- łup: klucz przedmiotu, {item, count, chance}, lista takich albo false
	item = true,             -- czy blok ma przedmiot (do ekwipunku i stawiania)
	placeable = true,        -- czy pojawia się w trybie kreatywnym
})
```

Tekstura to plik PNG 16x16 w folderze moda albo wzór opisany danymi (bez rysowania):

```lua
texture = { pattern = "ore", color = "#7f7f84", color2 = "#96969b", spots = "#d0203a" }
```

Wzory: `solid`, `noise`, `speckle`, `bricks`, `planks`, `stripes`, `ore`, `glass` (bloki) oraz
`gem`, `ingot`, `food`, `plant` (ikony przedmiotów). Kolory w formacie `#rrggbb` albo `#rrggbbaa`.
Piksele z przezroczystością poniżej 50% są niewidoczne.

Zmiana bloku innego moda (w content.lua, mod musi wczytać się później):

```lua
engine.blocks.get("stone").drops = "cobblestone"
engine.blocks.get("leaves").drops = { { item = "apple", chance = 0.08 } }
```

Numer bloku (`id`) nadaje gra w kolejności rejestracji. W skryptach używaj kluczy tekstowych:
`engine.blocks.id("stone")`, `engine.blocks.key(id)`. Świat zapisuje listę kluczy i przelicza numery,
gdy zmieni się zestaw modów; bloki z wyłączonego moda stają się powietrzem.

## Przedmioty

Każdy blok z `item ~= false` ma przedmiot o tym samym kluczu. Inne przedmioty:

```lua
engine.items.register("apple", {
	name = "Jabłko",
	icon = { pattern = "food", color = "#d23a2a" },   -- albo "textures/apple.png"
	max_stack = 64,
	food = 4,              -- dowolne własne pola, czytane przez engine.items.def("apple").food
})
```

Miejsce w kontenerze to `{ item = "apple", count = 3 }` albo pusta tabela `{}`.

## Świat

```lua
engine.worldgen.config({ biome_scale = 1.0, beach_height = 7 })

engine.worldgen.biome("meadow", {
	name = "Łąki",
	temperature = 0.0, humidity = -0.25,   -- punkt na mapie klimatu (szum od około -0.7 do 0.7)
	height = 12, hills = 9, roughness = 1.5, mountains = 0,
	top = "grass", filler = "dirt", depth = 3, stone = "stone",
	beach = { top = "sand", filler = "sand" },        -- gdy teren jest nie wyżej niż beach_height
	peak = { height = 34, top = "snow", filler = "stone" },  -- od tej wysokości
	features = {
		{ shape = "oak", trunk = "log", leaves = "leaves", height = { 4, 6 }, radius = 2, chance = 0.004 },
		{ structure = "ruin", chance = 0.0004 },
	},
	plants = { { block = "tall_grass", chance = 0.10 } },
})
```

Każdy punkt świata dostaje biom o najbliższym klimacie; wysokość miesza się płynnie między biomami.
Kształty drzew: `oak` (kula liści), `spruce` (stożek), `column` (sam pień, np. kaktus).
Elementy mają też `min_height` i `max_height` (wysokość terenu, na której mogą powstać).

```lua
-- struktura z warstw: od dołu do góry; w warstwie wiersze to oś z, znaki to oś x
engine.worldgen.structure("ruin", {
	origin = { 2, 1, 2 },          -- przesunięcie: środek i zagłębienie w ziemię
	key = { c = "cobblestone", ["."] = "air" },   -- spacja = nie zmieniaj
	layers = { { "ccc", "ccc", "ccc" }, { "c.c", "...", "c.c" } },
	only_air = false,              -- true: nie niszczy istniejących bloków
})
engine.worldgen.add_feature("desert", { structure = "ruin", chance = 0.0005 })

-- żyły rud: chance = szansa na żyłę w komórce 16x16x16, size = największy promień (1..6)
engine.worldgen.ore("coal", { block = "coal_ore", replace = "stone", min_y = -64, max_y = 40, chance = 0.7, size = 2 })
```

Inne funkcje: `engine.worldgen.get_biome(klucz)` (tabela do zmiany), `remove_biome`, `biomes()`,
`add_plant(biom, {block, chance})`. Generator liczy się w C++ (na PC) z tych danych, więc
własne biomy i struktury nie spowalniają gry.

## Haki: zmiana zachowania silnika

Haki działają jak prefix i postfix w Harmony:

- `engine.hooks.before(nazwa, fn, priorytet)` – przed działaniem silnika. Funkcja dostaje tabelę `ctx`,
  może zmienić jej pola albo ustawić `ctx.cancel = true`, żeby silnik nic nie zrobił.
- `engine.hooks.after(nazwa, fn, priorytet)` – po działaniu silnika.

Wyższy priorytet działa wcześniej. Po `cancel` kolejne haki „before” się nie wykonują.

| Hak | Pola `ctx` |
| --- | --- |
| `block.break` | `pos`, `block` (id), `drops` (lista `{item, count}`, można zmienić), `item` (w ręce) |
| `block.place` | `pos`, `block` (można zmienić na inny), `slot` (1..8), `item` |
| `item.use` | `item`, `slot`, a gdy celujesz w blok: `pos`, `normal`, `block` |
| `player.damage` | `amount` (można zmienić), `cause` (`fall`, `hunger`, `void`, własne) |
| `player.respawn` | `pos` (Vector3, można zmienić) |
| `camera.update` | co klatkę (tylko `after`): `mode`, `yaw`, `pitch`, `distance`, `height`, `side`, `fov_offset` |

## Zdarzenia

`engine.on(nazwa, fn)` reaguje na zdarzenie, `engine.emit(nazwa, dane)` wysyła własne zdarzenie do innych modów.

| Zdarzenie | Dane |
| --- | --- |
| `world_ready` | brak, po wczytaniu wszystkich modów |
| `tick` | `dt` (0.1 s), `time` (godzina) – 10 razy na sekundę |
| `player.land` | `fall` (wysokość upadku w blokach), `speed` |
| `player.death` | `cause`, `pos` |

## API `engine`

| Funkcja | Opis |
| --- | --- |
| `engine.log(...)`, `print(...)` | Zapis do dziennika moda |
| `engine.export(t)` / `engine.require(id)` | Udostępnienie tabeli innym modom / pobranie biblioteki |
| `engine.settings.get(klucz)` | Wartość ustawienia (serwer > świat > gracz > domyślna) |
| `engine.storage.get(klucz, domyślna)` / `set(klucz, wartość)` | Dane moda zapisywane w świecie |
| `engine.random()`, `random(n)`, `random(a, b)` | Liczba 0..1 albo całkowita z zakresu |
| `engine.blocks.register(k, def)`, `get(k)` | Rejestracja i definicja bloku (content) |
| `engine.blocks.id(k)`, `key(id)`, `name(id)`, `list()` | Rejestr bloków |
| `engine.items.register(k, def)`, `def(k)`, `name(k)`, `block_of(k)`, `max_stack(k)` | Przedmioty |
| `engine.items.container(id, rozmiar, zapis)` | Tworzy kontener przedmiotów (domyślnie zapisywany w świecie) |
| `engine.items.get(id, i)`, `set(id, i, {item, count})`, `size(id)` | Miejsca w kontenerze, liczone od 1 |
| `engine.worldgen.*` | Biomy, struktury, rudy (content), opis wyżej |
| `engine.world.get_block(pos)`, `set_block(pos, id_lub_klucz)` | Bloki w świecie |
| `engine.world.biome(pos)`, `biome_key(pos)`, `height(x, z)`, `time()`, `set_time(h)` | Świat |
| `engine.player.position()`, `teleport(pos)`, `velocity()`, `push(v)` | Ruch gracza |
| `engine.player.set(stat, v)`, `get(stat)` | Statystyki: `speed`, `jump`, `gravity`, `reach`, `auto_jump`, `max_health`, `spawn` |
| `engine.player.health()`, `max_health()`, `set_health(v)`, `heal(n)`, `damage(n, przyczyna)` | Zdrowie |
| `engine.player.target()`, `selected_item()` | Blok, w który celuje gracz; przedmiot w ręce |
| `engine.player.animate(nazwa)`, `stop_animation()`, `colors(t)` | Animacje i kolory postaci |
| `engine.animation.register(nazwa, def)`, `override(stan, nazwa)` | Animacje klatkowe (content) i zamiana stanów `idle`, `walk`, `jump` |
| `engine.camera.set(k, v)`, `get(k)`, `mode(m)` | Kamera: `mode` (`third`, `first`, `shoulder`, `top`), `distance`, `height`, `side`, `pitch`, `pitch_min`, `pitch_max`, `fov_offset` |
| `engine.hotbar.bind(kontener, pierwsze, ile)`, `unbind()`, `selected()` | Pasek szybkiego dostępu z kontenera |
| `engine.ui.window(spec)`, `close(id)`, `is_open(id)`, `notify(tekst)` | Okna i powiadomienia |
| `engine.ui.bar({id, label, value, max, color})`, `text({id, text, color})`, `remove(id)` | Paski i napisy na ekranie gry |
| `engine.input.bind({id, key, label, on_press})` | Klawisz na PC i przycisk na telefonie |

### Animacje

```lua
engine.animation.register("wave", {
	length = 1.6, loop = false,
	tracks = {   -- części: body, head, arm_left, arm_right, leg_left, leg_right
		arm_right = { { 0, { 0, 0, 0 } }, { 0.3, { 0, 0, 160 } }, { 1.6, { 0, 0, 0 } } },
	},
})
engine.player.animate("wave")
engine.animation.override("idle", "idle_look")   -- własna animacja zamiast oddychania w miejscu
```

Klatka to `{czas, {x, y, z}}`: obrót części w stopniach. Między klatkami ruch jest płynny.

### Kolory postaci

`engine.player.colors({ tunic = "#a83a32", scarf = "#e0b040" })`. Części: `skin`, `tunic`, `tunic_dark`,
`trousers`, `boots`, `leather`, `scarf`, `hair`, `bedroll`, `gold`, `eye`, `mouth`, `nose`, `strap`.

### Okna

```lua
engine.ui.window({
	id = "moje_okno",
	title = "Tytuł",
	sections = {
		{ type = "character", lines = { "Linia 1", "Linia 2" } },
		{ type = "slots", container = "plecak", columns = 9, title = "Plecak" },
		{ type = "text", text = "Opis" },
		{ type = "button", id = "ok", text = "OK", on_press = function() engine.ui.close("moje_okno") end },
	},
})
```

## Biblioteka „Zestaw modera” (modkit)

```lua
local kit = engine.require("modkit")   -- w mod.json: "requires": ["modkit"]
kit.patch("block.break", { before = function(ctx) end, after = function(ctx) end })
kit.inventory.add(kontener, przedmiot, ile)              -- zwraca, ile się nie zmieściło
kit.inventory.add_many({"hotbar", "backpack"}, przedmiot, ile)
kit.inventory.take(kontener, miejsce, ile)
kit.inventory.remove({"hotbar", "backpack"}, przedmiot, ile)
kit.inventory.count({"hotbar", "backpack"}, przedmiot)
kit.after(sekundy, fn); kit.every(sekundy, fn)
kit.copy(t); kit.merge(a, b); kit.clamp(x, lo, hi)
```

Mod „Plecak i postać” udostępnia `engine.require("backpack").give(przedmiot, ile)`.

## Przykładowe mody w grze

| Mod | Co pokazuje |
| --- | --- |
| `base` | bloki z PNG, biomy, drzewa, rośliny – cały podstawowy świat |
| `modkit` | biblioteka dla innych modów |
| `backpack` | kontenery, pasek, okno postaci, łup z bloków |
| `ores` | bloki i przedmioty ze wzorów, rudy, struktury z warstw, zmiana bloku z innego moda |
| `survival` | zdrowie i głód na ekranie, obrażenia od upadku, jedzenie przez `item.use` |
| `emotes` | animacje klatkowe, zamiana animacji w miejscu, tryby kamery, hak kamery, kolory postaci |
| `destructible` | ustawienie `block_toggles` i anulowanie kopania |

## Co będzie dalej

- Woda, jaskinie i dalekie widoki (generator dostanie nowe pola).
- Własne stworzenia z modelami i animacjami.
- Gra wieloosobowa: haki i dane modów synchronizowane przez serwer.
- Limit czasu wykonania skryptów Lua (ochrona przed zawieszeniem gry przez błędny mod).
