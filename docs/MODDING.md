# Tworzenie modów

Mod to folder z plikiem `mod.json` i skryptami w Lua 5.4. Gra wczytuje mody z dwóch miejsc:

- `res://mods/` – mody dołączone do gry,
- `user://mods/` – mody gracza (na Windowsie: `%APPDATA%/Godot/app_userdata/Voxel Engine/mods`).

Każdy mod działa we własnym, odizolowanym środowisku. Nie ma dostępu do plików, sieci ani systemu,
tylko do obiektu `engine` opisanego niżej.

## mod.json

```json
{
	"id": "moj_mod",
	"name": "Mój mod",
	"version": "0.1.0",
	"author": "Ty",
	"description": "Co robi mod.",
	"requires": ["modkit"],
	"scripts": ["main.lua"],
	"library": false,
	"required": false,
	"enabled_by_default": true,
	"settings": [
		{"key": "speed", "label": "Prędkość", "type": "float", "default": 1.0, "min": 0.5, "max": 3.0, "step": 0.1},
		{"key": "rows", "label": "Rzędy", "type": "int", "default": 3, "min": 1, "max": 6, "step": 1},
		{"key": "on", "label": "Włączone", "type": "bool", "default": true},
		{"key": "blocks", "label": "Bloki", "type": "block_toggles", "default": true}
	]
}
```

| Pole | Znaczenie |
| --- | --- |
| `id` | Stały identyfikator, małe litery i podkreślenia |
| `requires` | Mody, które muszą być włączone; wczytają się przed tym modem |
| `scripts` | Pliki Lua wykonywane po kolei przy starcie świata |
| `library` | Mod jest biblioteką dla innych (na liście trafia wyżej) |
| `settings` | Ustawienia widoczne w grze w ekranie Mody |

Rodzaje ustawień: `bool`, `int`, `float` oraz `block_toggles` (przełącznik dla każdego bloku w grze;
wartość to tabela `klucz_bloku -> true/false`, brak wpisu oznacza wartość `default`).
Ustawienie z `"world": true` zapisuje się w świecie przy jego tworzeniu.

Kolejność modów ustawia gracz w ekranie Mody. Serwer może ją wymusić razem z wartościami ustawień;
wtedy są one zablokowane i oznaczone „[serwer]”.

## Haki: zmiana zachowania silnika

Haki działają jak prefix i postfix w Harmony:

- `engine.hooks.before(nazwa, fn, priorytet)` – przed działaniem silnika. Funkcja dostaje tabelę `ctx`,
  może zmienić jej pola albo ustawić `ctx.cancel = true`, żeby silnik nic nie zrobił.
- `engine.hooks.after(nazwa, fn, priorytet)` – po działaniu silnika.

Wyższy priorytet działa wcześniej. Po `cancel` kolejne haki „before” się nie wykonują.

| Hak | Pola `ctx` |
| --- | --- |
| `block.break` | `pos` (Vector3i), `block` (id) |
| `block.place` | `pos`, `block` (można zmienić na inny), `slot` (1..8) |

## Zdarzenia

`engine.on(nazwa, fn)` reaguje na zdarzenie, `engine.emit(nazwa, dane)` wysyła własne zdarzenie do innych modów.

| Zdarzenie | Dane |
| --- | --- |
| `world_ready` | brak, po wczytaniu wszystkich modów |
| `tick` | `dt` (0.1 s), `time` (godzina) – 10 razy na sekundę |

## API `engine`

| Funkcja | Opis |
| --- | --- |
| `engine.log(...)`, `print(...)` | Zapis do dziennika moda |
| `engine.export(t)` / `engine.require(id)` | Udostępnienie tabeli innym modom / pobranie biblioteki |
| `engine.settings.get(klucz)` | Wartość ustawienia (serwer > gracz > domyślna) |
| `engine.storage.get(klucz, domyślna)` / `set(klucz, wartość)` | Dane moda zapisywane w świecie |
| `engine.blocks.id(klucz)`, `key(id)`, `name(id)`, `list()` | Rejestr bloków |
| `engine.world.get_block(pos)`, `set_block(pos, id)`, `biome(pos)`, `time()` | Świat |
| `engine.player.position()`, `set(stat, v)`, `get(stat)` | Gracz; statystyki: `speed`, `jump`, `gravity`, `reach`, `auto_jump` |
| `engine.camera.set(klucz, v)` | Kamera: `distance`, `fov_offset` |
| `engine.items.container(id, rozmiar, zapis)` | Tworzy kontener przedmiotów (domyślnie zapisywany w świecie) |
| `engine.items.get(id, i)`, `set(id, i, {block, count})`, `size(id)`, `max_stack()` | Miejsca w kontenerze, liczone od 1 |
| `engine.hotbar.bind(kontener, pierwsze, ile)`, `unbind()`, `selected()` | Pasek szybkiego dostępu z kontenera |
| `engine.ui.window(spec)`, `close(id)`, `is_open(id)`, `notify(tekst)` | Okna i powiadomienia |
| `engine.input.bind({id, key, label, on_press})` | Klawisz na PC i przycisk na telefonie |

Okno opisuje się danymi:

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
kit.inventory.add(kontener, blok, ile)            -- zwraca, ile się nie zmieściło
kit.inventory.add_many({"hotbar", "backpack"}, blok, ile)
kit.inventory.take(kontener, miejsce, ile)
kit.inventory.count(kontener, blok)
kit.after(sekundy, fn); kit.every(sekundy, fn)
kit.copy(t); kit.merge(a, b); kit.clamp(x, lo, hi)
```

## Przykład: szybsze bieganie na pustyni

```lua
engine.on("tick", function()
	local p = engine.player.position()
	if engine.world.biome(Vector3i(math.floor(p.x), 0, math.floor(p.z))) == "Pustynia" then
		engine.player.set("speed", 6.5)
	else
		engine.player.set("speed", 4.6)
	end
end)
```

## Co będzie dalej

- Rejestrowanie nowych bloków z własnymi teksturami i przedmiotów.
- Haki dla generowania świata (biomy i struktury opisane danymi, liczone w C++).
- Własne stworzenia z modelami i animacjami.
- Więcej haków: obrażenia, kamera, sterowanie, zasady gry.
