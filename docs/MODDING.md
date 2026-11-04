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
	hardness = 3.0,          -- sekundy kopania gołą ręką (rośliny domyślnie 0, reszta 1)
	breakable = true,        -- false: nie do wykopania
	gravity = false,         -- true: spada bez podparcia (piasek, żwir)
	loose = nil,             -- obiekt luźny (fizyczny), opis niżej
})
```

### Ciecze

```lua
engine.blocks.register("water", {
	name = "Woda",
	item = false,
	liquid = { color = "#2a78c8", deep = "#0a2a5c", foam = "#e8f4ff", viscosity = 1, push = 1.0, emission = 0 },
})
```

Ciecz ma 8 poziomów i zachowuje objętość: wylany blok (8 poziomów) spada, a potem wyrównuje się z sąsiadami,
aż zostanie kałuża co najmniej 2 poziomów; cienkie warstwy powoli wysychają. Silnik rejestruje sam bloki
`water~1` .. `water~8` (płynąca ciecz). Blok `water` to zbiornik z generatora (morze, jezioro): oddaje ciecz bez końca.
`viscosity` mówi, co ile kroków symulacji ciecz płynie (np. lawa 4), `push` to siła prądu,
`emission` to świecenie (lawa). Prąd spycha gracza, stworzenia i obiekty luźne.
Powierzchnia ma fale, pianę przy brzegach i kolor zależny od głębokości (shader `scripts/shaders/water.gdshader`).

### Obiekty luźne

Blok z polem `loose` nie trafia do siatki świata: po postawieniu staje się bryłą fizyczną, którą można pchać,
kopnąć (lewy przycisk) i podnieść (prawy przycisk). W cieczy działa wyporność: gęstość poniżej 1 pływa, powyżej tonie.

```lua
loose = { shape = "box" | "ball" | "cylinder", size = 0.9, mass = 10, density = 0.6, bounce = 0.1, friction = 0.8 }
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
engine.worldgen.config({
	biome_scale = 1.0, beach_height = 9,
	sea_level = 8, water = "water",                 -- woda do tej wysokości (morza i jeziora)
	lakes = { depth = 11, amount = 1.0 },           -- niecki jezior obniżające teren
	caves = { tunnels = 1.0, caverns = 1.0, min_y = -56 },   -- jaskinie: tunele i komory
})

engine.worldgen.biome("meadow", {
	name = "Łąki",
	temperature = 0.0, humidity = -0.25,   -- punkt na mapie klimatu (szum od około -0.7 do 0.7)
	height = 12, hills = 9, roughness = 1.5, mountains = 0,
	top = "grass", filler = "dirt", depth = 3, stone = "stone",
	beach = { top = "sand", filler = "sand" },        -- gdy teren jest nie wyżej niż beach_height
	peak = { height = 34, top = "snow", filler = "stone" },  -- od tej wysokości
	water_surface = "ice",                         -- powierzchnia wody w tym biomie zamarza
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

## Stworzenia

Stworzenie to model z klockowych części (jak postać gracza), zachowanie i łup. Silnik sam animuje nogi,
skrzydła i głowę oraz prowadzi proste AI; mody dokładają zachowania w Lua.

```lua
engine.entities.register("sheep", {
	name = "Owca", health = 8, speed = 1.1, panic_speed = 2.8,
	size = { 0.85, 1.2 },                         -- szerokość i wysokość kolizji
	parts = {
		body = { pivot = { 0, 0.62, 0 }, boxes = {
			{ size = { 0.74, 0.58, 1.02 }, pos = { 0, 0.12, 0 }, color = "#eceae2", tag = "wool" },
		} },
		head = { parent = "body", pivot = { 0, 0.3, -0.5 }, look = true, boxes = { ... } },
		leg_fl = { pivot = { -0.2, 0.42, -0.3 }, swing = 1, boxes = { ... } },
		wing_l = { parent = "body", pivot = { ... }, wing = -1, boxes = { ... } },
	},
	ai = { wander = true, flee = true, follow = "wheat", swim = true, slow_fall = false, avoid_cliffs = true,
		graze = { from = "grass", to = "dirt", chance = 0.5 } },
	drops = { { item = "mutton", count = 1, max = 2, chance = 1.0, adult_only = true } },
	spawn = { biomes = { "meadow" }, on = { "grass" }, group = { 2, 4 }, max = 6, babies = 0.15 },
})
```

Przód modelu to -Z. `pivot` to punkt obrotu części (względem rodzica), `pos` klocka jest względem punktu
obrotu. `swing` kołysze nogą przy chodzie, `wing` trzepocze przy spadaniu, `look` obraca głowę do gracza
i schyla ją przy skubaniu. `tag` pozwala ukryć albo przekolorować klocki (`engine.entities.show/color`).
Animacje klatkowe (`engine.animation.register`) działają też na części stworzeń (`engine.entities.animate`).

AI: stanie, wędrówka, skubanie (`graze` zmienia blok pod spodem i wysyła zdarzenie `entity.graze`),
ucieczka po zranieniu, podążanie za graczem z przedmiotem `follow`, pływanie i omijanie urwisk.
Dalekie stworzenia są usypiane i wracają, gdy gracz się zbliży; wszystko zapisuje się w świecie.

## Haki: zmiana zachowania silnika

Haki działają jak prefix i postfix w Harmony:

- `engine.hooks.before(nazwa, fn, priorytet)` – przed działaniem silnika. Funkcja dostaje tabelę `ctx`,
  może zmienić jej pola albo ustawić `ctx.cancel = true`, żeby silnik nic nie zrobił.
- `engine.hooks.after(nazwa, fn, priorytet)` – po działaniu silnika.

Wyższy priorytet działa wcześniej. Po `cancel` kolejne haki „before” się nie wykonują.

| Hak | Pola `ctx` |
| --- | --- |
| `block.break` | `pos`, `block` (id), `drops` (lista `{item, count}`, można zmienić), `item` (w ręce) |
| `block.dig` | `pos`, `block`, `time` (sekundy kopania, można zmienić, np. narzędzia), `item` |
| `block.place` | `pos`, `block` (można zmienić na inny), `slot` (1..8), `item` |
| `block.use` | prawy przycisk na bloku, przed użyciem przedmiotu: `pos`, `normal`, `block`, `item`, `slot`; `cancel` zatrzymuje stawianie (np. stół otwiera okno) |
| `item.use` | `item`, `slot`, a gdy celujesz w blok: `pos`, `normal`, `block` |
| `slot.click` | kliknięcie w miejsce w oknie: `container` (id bez konta), `index` (od 1), `right`, `held` (przedmiot pod kursorem); `cancel` przejmuje kliknięcie, np. pole wyniku rzemiosła |
| `player.login` | gracz dołączył do serwera: `id`, `name`; `ctx.wait = true` zatrzymuje go do `engine.players.accept`, `cancel` + `reason` wyrzuca |
| `player.damage` | `amount` (można zmienić), `cause` (`fall`, `hunger`, `void`, własne) |
| `player.respawn` | `pos` (Vector3, można zmienić) |
| `entity.damage` | `id`, `type`, `amount` (można zmienić), `cause` |
| `entity.interact` | prawy przycisk na stworzeniu: `id`, `type`, `item`, `slot` |
| `item.pickup` | gracz podchodzi do przedmiotu: `item`, `count`; ustaw `ctx.taken` (ile zabrano) |
| `camera.update` | co klatkę (tylko `after`, tylko gracz lokalny): `mode`, `yaw`, `pitch`, `distance`, `height`, `side`, `fov_offset` |

## Zdarzenia

`engine.on(nazwa, fn)` reaguje na zdarzenie, `engine.emit(nazwa, dane)` wysyła własne zdarzenie do innych modów.

| Zdarzenie | Dane |
| --- | --- |
| `world_ready` | brak, po wczytaniu wszystkich modów |
| `tick` | `dt` (0.1 s), `time` (godzina) – 10 razy na sekundę |
| `player.land` | `fall` (wysokość upadku w blokach), `speed` |
| `player.death` | `cause`, `pos` |
| `player.underwater` | `underwater` (oczy weszły pod ciecz albo z niej wyszły) |
| `entity.spawn` | `id`, `type`, `pos` |
| `entity.death` | `id`, `type`, `pos`, `cause`, `data` |
| `entity.tick` | raz na sekundę dla każdego stworzenia: `id`, `type`, `state`, `pos`, `data` |
| `entity.graze` | `id`, `type`, `pos` (blok, który stworzenie skubało) |
| `player.join` | `id`, `name` (konto) – gracz wszedł do gry (po zalogowaniu); tu twórz kontenery gracza |
| `player.leave` | `id`, `name` – gracz wyszedł z serwera |
| `ui.closed` | `id` okna zamkniętego przez gracza |

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
| `engine.items.container(id, rozmiar, zapis, na_gracza)` | Tworzy kontener przedmiotów (domyślnie zapisywany w świecie); `na_gracza = true` daje każdemu kontu osobną kopię pod tym samym id |
| `engine.items.get(id, i)`, `set(id, i, {item, count})`, `size(id)` | Miejsca w kontenerze, liczone od 1 |
| `engine.worldgen.*` | Biomy, struktury, rudy (content), opis wyżej |
| `engine.world.get_block(pos)`, `set_block(pos, id_lub_klucz)` | Bloki w świecie |
| `engine.world.biome(pos)`, `biome_key(pos)`, `height(x, z)`, `time()`, `set_time(h)` | Świat |
| `engine.player.position()`, `teleport(pos)`, `velocity()`, `push(v)` | Ruch gracza |
| `engine.player.set(stat, v)`, `get(stat)` | Statystyki: `speed`, `jump`, `gravity`, `reach`, `auto_jump`, `max_health`, `spawn`, `break_speed`, `swim_speed` |
| `engine.player.health()`, `max_health()`, `set_health(v)`, `heal(n)`, `damage(n, przyczyna)` | Zdrowie |
| `engine.player.target(z_cieczami)`, `selected_item()` | Blok, w który celuje gracz; przedmiot w ręce |
| `engine.player.in_liquid()`, `eyes_in_liquid()` | Czy gracz pływa / ma głowę pod cieczą |
| `engine.entities.register(rodzaj, def)`, `def(rodzaj)` | Stworzenia (content) |
| `engine.entities.spawn(rodzaj, pos, dane, skala)`, `remove(id)`, `exists(id)`, `list(rodzaj, promień)` | Tworzenie i lista stworzeń |
| `engine.entities.type/position/health/state/scale(id)`, `data(id)`, `set_data(id, k, v)` | Stan stworzenia i jego dane (zapisywane) |
| `engine.entities.move_to(id, pos)`, `teleport(id, pos)`, `set_scale(id, s)`, `damage(id, n)`, `animate(id, nazwa)` | Sterowanie stworzeniem |
| `engine.entities.show(id, tag, on)`, `color(id, tag, kolor)` | Wygląd części oznaczonych tagiem |
| `engine.entities.drop(przedmiot, ile, pos)` | Przedmiot leżący na ziemi |
| `engine.player.animate(nazwa)`, `stop_animation()`, `colors(t)` | Animacje i kolory postaci |
| `engine.animation.register(nazwa, def)`, `override(stan, nazwa)` | Animacje klatkowe (content) i zamiana stanów `idle`, `walk`, `jump` |
| `engine.camera.set(k, v)`, `get(k)`, `mode(m)` | Kamera: `mode` (`third`, `first`, `shoulder`, `top`), `distance`, `height`, `side`, `pitch`, `pitch_min`, `pitch_max`, `fov_offset` |
| `engine.hotbar.bind(kontener, pierwsze, ile)`, `unbind()`, `selected()` | Pasek szybkiego dostępu z kontenera |
| `engine.ui.window(spec)`, `close(id)`, `is_open(id)`, `notify(tekst)` | Okna i powiadomienia |
| `engine.ui.bar({id, label, value, max, color})`, `text({id, text, color})`, `remove(id)` | Paski i napisy na ekranie gry |
| `engine.input.bind({id, key, label, on_press})` | Klawisz na PC i przycisk na telefonie |
| `engine.ui.held()`, `set_held(slot)` | Przedmiot trzymany kursorem w oknie |
| `engine.player.id()`, `name()`, `is_host()` | Kim jest gracz, w którego imieniu działa kod (nazwa = konto) |
| `engine.player.storage.get(k, domyślna)`, `set(k, v)` | Dane moda osobne dla każdego konta (zapisywane w świecie) |
| `engine.players.list()`, `each(fn)`, `accept(id, konto)`, `kick(id, powód)` | Gracze na serwerze; `each` wywołuje `fn(id)` w imieniu każdego gracza |
| `engine.as_player(id, fn)` | Wywołuje `fn` w imieniu gracza `id` (np. z licznika czasu) |
| `engine.is_multiplayer()`, `engine.hash(tekst)` | Czy gra jest sieciowa; skrót SHA-256 (np. haseł) |

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
		{ type = "input", id = "imie", label = "Imię", placeholder = "...", secret = false },
		{ type = "progress", label = "Postęp", value = 0.4 },
		{ type = "button", id = "ok", text = "OK", on_press = function(fields)
			engine.log(fields.imie)   -- wartości pól „input” trafiają do przycisku
			engine.ui.close("moje_okno")
		end },
	},
	closable = false,   -- bez przycisku „Zamknij” i klawisza Esc (np. logowanie)
})
```

Okno o tym samym `id` otwarte ponownie odświeża się na miejscu (tekst wpisany w pola zostaje).

## Gra wieloosobowa

Do 8 graczy. Serwer jest jedynym miejscem, gdzie działają skrypty modów, ciecze, stworzenia i zapis świata.
Klienci wczytują tylko fazę `content` (bloki, tekstury, generator) i sami liczą teren z ziarna; serwer
wysyła im zmienione bloki. Przy dołączaniu klient dostaje od serwera kolejność, włączenie i ustawienia modów
i porównuje skrót całej treści – gracz z innymi modami nie wejdzie i dostaje komunikat. Dlatego mod napisany
zgodnie z tą instrukcją działa w sieci bez dodatkowej pracy, o ile wszyscy mają te same mody.

Co trzeba wiedzieć, pisząc skrypty:

- Kod moda zawsze działa „w imieniu” jakiegoś gracza: hak kopania – tego, kto kopie; przycisk w oknie – tego,
  kto go nacisnął. `engine.player.*`, `engine.hotbar.*`, `engine.ui.*` i kamera dotyczą tego gracza.
- Liczniki czasu i `tick` nie mają gracza: użyj `engine.players.each(fn)` albo `engine.as_player(id, fn)`.
- Dane gracza trzymaj w `engine.player.storage` albo w kontenerach z `na_gracza = true`, a nie w `engine.storage`
  (to jedne dane świata dla wszystkich). Kontenery gracza twórz w zdarzeniu `player.join`.
- Gracz ma nazwę z ustawień gry (widoczną nad głową, gdy ktoś na niego patrzy). Mod „Konta graczy” (`accounts`)
  przez hak `player.login` pyta o login i hasło i wpuszcza gracza na wybrane konto – ekwipunek, pozycja
  i dane modów należą do konta, więc można wejść na nie z innego urządzenia pod inną nazwą.

Serwer bez okna: `godot --headless --path game -- --server=nazwa_świata [--port=7777] [--seed=42] [--enable=accounts]`.
Gra z oknem: menu „Gra wieloosobowa” (dołącz po adresie albo „Graj na serwerze” na własnym świecie).

## Rzemiosło i narzędzia

- `tools` – patyk i narzędzia (drewniane, kamienne, żelazne). Blok z polem `tool = "pickaxe"` kopie się
  `tool_speed` razy szybciej właściwym narzędziem; obrażenia broni w `data.damage` przedmiotu.
- `crafting_classic` – siatka 2×2 w oknie postaci i 3×3 przy stole rzemieślniczym, przepisy kształtowe
  (z odbiciem lustrzanym) i bezkształtne. Własne przepisy z innego moda:

```lua
local craft = engine.require("crafting_classic")   -- "requires": ["crafting_classic"]
craft.shaped({ "RR", "RR" }, { R = "ruby" }, "ruby_block", 1)
craft.shapeless({ ruby = 1, stick = 1 }, "ruby_wand", 1)
```

- `crafting_discovery` (domyślnie wyłączony) – warsztat z czterema polami: składniki bez kolejności, przepisy
  ukryte do odkrycia, podpowiedzi („Prawie!”), wykuwanie trwa (ogień w pobliżu przyspiesza), premia za pierwsze
  odkrycie i księga przepisów gracza. Przepis z innego moda:
  `engine.require("crafting_discovery").add("id", { ruby = 2, stick = 1 }, "ruby_wand", 1, 4)` (ostatnie: sekundy).
  Zdarzenia: `crafting.discovered`, `crafting.crafted`.

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
| `survival` | zdrowie, głód i powietrze na ekranie, upadki i topienie, jedzenie przez `item.use` |
| `animals` | owce, krowy, kurczaki: modele, AI, strzyżenie, dojenie, jajka, rozmnażanie, młode |
| `loose` | obiekty luźne (skrzynie, beczki, piłki, głazy) i flaga luźności dla zwykłych bloków |
| `emotes` | animacje klatkowe, zamiana animacji w miejscu, tryby kamery, hak kamery, kolory postaci |
| `destructible` | ustawienie `block_toggles` i anulowanie kopania |
| `accounts` | logowanie na serwer (hak `player.login`, okno z polami, hasła jako skrót z solą) |
| `tools` | narzędzia, pole `tool` bloków, hak `block.dig` |
| `crafting_classic` | rzemiosło jak w MC: hak `slot.click`, `block.use`, zdarzenie `ui.closed`, eksport przepisów |
| `crafting_discovery` | rzemiosło odkrywcze: przycisk z polami, pasek postępu, dane gracza, `engine.as_player` |

## Bezpieczeństwo

Każde wywołanie kodu moda ma limit czasu (liczony w instrukcjach Lua, około 0,1–0,3 s na hak i kilka
sekund na wczytanie pliku) i limit pamięci (256 MB na wszystkie mody). Mod, który go przekroczy, np. przez
pętlę bez końca, zostaje wyłączony do końca gry, a gracz dostaje komunikat. Pliki modów wczytywane są tylko
jako tekst (bez binarnego bajtkodu), `pcall` nie połknie błędu limitu, korutyny też są pod limitem,
a wspólnej metatabeli tekstów nie da się zmienić. Test: `godot --headless --path game -s tests/lua_guard.gd`.

## Co będzie dalej

- Piece i przetapianie rud, zbroja, więcej stworzeń.
- Pobieranie brakujących modów z serwera przy dołączaniu.
