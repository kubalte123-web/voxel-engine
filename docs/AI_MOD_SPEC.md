# Specyfikacja modów – Voxel Engine (dla AI)

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

# Voxel Engine (nazwa robocza)

> Darmowa gra voxelowa w Godot 4.6, w której całą treść i rozgrywkę tworzą mody w Lua 5.4. Silnik zna tylko
> powietrze; bloki, przedmioty, biomy, zasady, kamera i animacje pochodzą z modów. Ten plik jest punktem
> startowym dla asystentów AI, które mają napisać mod.

Gra przychodzi jako paczka modów `game/mods/podstawowa/` (pack.json + moduły w `mods/`); nowy mod to dodatek
w `mods/<id>/` obok paczki, który może zastąpić moduł (`"replaces": ["horses"]`). Wygląd bez kodu zmieniają
paczki zasobów (`resourcepacks/<nazwa>/blocks/stone.png`, `entities/horse.glb` ...).

Mod to folder z `mod.json` i skryptami Lua w dwóch fazach: `content` (rejestracja bloków, przedmiotów,
biomów, rud, struktur i animacji, także zmiany cudzych definicji) oraz `scripts` (haki, zdarzenia, okna,
klawisze). Skrypty działają w piaskownicy: bez plików, sieci i systemu, tylko z obiektem `engine`.
Zachowanie silnika zmienia się hakami `engine.hooks.before/after` (jak prefix i postfix w Harmony),
a mody mogą udostępniać sobie biblioteki przez `engine.export` i `engine.require`.

## Dokumentacja

- [Pełna specyfikacja w jednym pliku](docs/AI_MOD_SPEC.md): skrót, instrukcja, lista kluczy i mody wzorcowe

- [Tworzenie modów](docs/MODDING.md): mod.json, fazy, bloki, przedmioty, świat, haki, zdarzenia, pełne API `engine`
- [Prelude API](game/scripts/mods/prelude.lua): implementacja obiektu `engine` po stronie Lua

## Przykładowe mody

- [Świat podstawowy](game/mods/podstawowa/mods/base/content.lua): bloki z PNG, biomy, drzewa, rośliny
- [Rudy i ruiny](game/mods/podstawowa/mods/ores/content.lua): tekstury ze wzorów, przedmioty, rudy, struktury z warstw, zmiana bloku innego moda
- [Przetrwanie](game/mods/podstawowa/mods/survival/main.lua): zdrowie i głód na ekranie, obrażenia od upadku, jedzenie przez hak item.use
- [Zwierzęta](game/mods/podstawowa/mods/animals/content.lua): modele stworzeń z klocków, AI, łup, pojawianie się ([skrypty](game/mods/podstawowa/mods/animals/main.lua): strzyżenie, jajka, rozmnażanie)
- [Luźne przedmioty](game/mods/podstawowa/mods/loose/content.lua): obiekty fizyczne (pchanie, toczenie, pływanie)
- [Gesty, kamera i wygląd](game/mods/podstawowa/mods/emotes/content.lua): animacje klatkowe, tryby kamery, kolory postaci ([skrypty](game/mods/podstawowa/mods/emotes/main.lua))
- [Zestaw modera](game/mods/podstawowa/mods/modkit/main.lua): biblioteka z łatkami, ekwipunkiem i licznikami czasu
- [Plecak i postać](game/mods/podstawowa/mods/backpack/main.lua): kontenery, pasek z kontenera, okno postaci, łup z bloków
- [Zniszczalność bloków](game/mods/podstawowa/mods/destructible/main.lua): hak `block.break` i ustawienie `block_toggles`
- [Konta graczy](game/mods/podstawowa/mods/accounts/main.lua): logowanie na serwer przez hak `player.login` i okno z polami
- [Narzędzia](game/mods/podstawowa/mods/tools/content.lua): przedmioty-narzędzia, pole `tool` bloków ([skrypt](game/mods/podstawowa/mods/tools/main.lua): hak `block.dig`)
- [Rzemiosło klasyczne](game/mods/podstawowa/mods/crafting_classic/main.lua): siatki 2×2/3×3, przepisy kształtowe, hak `slot.click`
- [Rzemiosło odkrywcze](game/mods/podstawowa/mods/crafting_discovery/main.lua): ukryte przepisy, wykuwanie w czasie, dane gracza
- [Uprawy](game/mods/podstawowa/mods/farming/content.lua): stany bloku (wiek, wilgotność) ([skrypt](game/mods/podstawowa/mods/farming/main.lua): losowe aktualizacje, sąsiad)
- [Skrzynie](game/mods/podstawowa/mods/storage/main.lua): kontener bloku, stan facing
- [Alchemia](game/mods/podstawowa/mods/alchemy/content.lua): blok z modelem GLB i klocków, animacje, emitery cząsteczek ([skrypt](game/mods/podstawowa/mods/alchemy/main.lua): wygląd z gry, mikstury)
- [Piec](game/mods/podstawowa/mods/smelting/main.lua): dane bloku, zaplanowane aktualizacje, wariant świecący ([treść](game/mods/podstawowa/mods/smelting/content.lua))
- [Budowanie](game/mods/podstawowa/mods/building/content.lua): kształty z prostopadłościanów – półbloki, schody, płoty, murki, szyby, własne `boxes`
- [Potwory](game/mods/podstawowa/mods/monsters/content.lua): wrogie zombie z modelem GLB i animacjami z pliku ([skrypt](game/mods/podstawowa/mods/monsters/main.lua): mózg `on_think`, polecenie `/zombie`)
- [Konie](game/mods/podstawowa/mods/horses/content.lua): jazda (`ride`), tłumaczenia `@klucz` ([skrypt](game/mods/podstawowa/mods/horses/main.lua): oswajanie hakiem `entity.interact`, `engine.t`)
- [Poradnik](game/mods/podstawowa/mods/handbook/main.lua): okno z zakładkami, listą, obrazkiem, suwakiem, przełącznikiem; kompas na ekranie z `anchor`
- [Głazy i ruiny](game/mods/podstawowa/mods/ruins/main.lua): generator świata w Lua (`engine.worldgen.on_generate`, szum, deterministyczny los)

## Zasady dla generowanego moda

- `register` tylko w plikach z pola `content`; logika w świecie w plikach z pola `scripts`.
- Tablice w Lua liczone od 1, miejsca w kontenerach też od 1.
- Przedmioty to klucze tekstowe; miejsce w kontenerze to `{item = "stone", count = 5}` albo `{}`.
- Pozycje bloków to `Vector3i(x, y, z)`; bloki w świecie to liczby, zamiana przez `engine.blocks.id("stone")` i `engine.blocks.key(id)`.
- Tekstury: PNG 16x16 w folderze moda albo wzór `{pattern = "ore", color = "#rrggbb", spots = "#rrggbb"}`.
- Klucze bloków moda base: grass, dirt, stone, planks, sand, log, leaves, snow, cactus, tall_grass, flower_red, flower_yellow, glass, bricks, gravel, ice, bedrock, water (płynąca: water~1 .. water~8).
- Przedmioty moda base: bucket, water_bucket. Stworzenia moda animals: sheep, cow, chicken.
- Kod moda ma limit czasu i pamięci; długie obliczenia rozkładaj na zdarzenia `tick`.
- Gra może być sieciowa: skrypty działają na serwerze w imieniu gracza. Dane gracza trzymaj w `engine.player.storage`
  albo kontenerach `engine.items.container(id, n, true, true)` tworzonych w zdarzeniu `player.join`;
  w `tick` i licznikach czasu używaj `engine.players.each(fn)`.
- Stan bloku = osobny wariant: `states = {...}` i `variant = function(state) return zmiany end` w definicji;
  w skryptach `engine.blocks.state/set_state`. Dane i kontener bloku: `engine.blocks.data/set_data/container`.
  Aktualizacje: `engine.blocks.on_update(klucz, fn)` (reason: random / scheduled / neighbor), `engine.blocks.schedule`.
- Blok z modelem: `shape = "model"`, `model = {file = "models/x.glb", parts, animations, emitters, collision, look}`;
  w skryptach `engine.blocks.look(pos, {colors, hide, anim, emitters})`, `engine.blocks.animate(pos, nazwa)`.
- Cząsteczki: `engine.particles.register` (content), `engine.particles.spawn(nazwa, pos, opts)`.
- Pociski: `engine.projectiles.register` (content), `spawn(rodzaj, {position, direction, data})`, `on_hit(rodzaj, fn)`.
- Celowanie: `engine.player.eye_position()`, `look_direction()`, `raycast(zasięg)`; `engine.world.raycast(...)`.
- Opis przedmiotu: pola `description` i `tooltip = {category, lines}`; dynamiczny: `engine.items.tooltip(klucz, fn)`.
  Dane egzemplarza: `data` w miejscu kontenera, `engine.items.data/set_data`.
- Dźwięki: `engine.sounds.register` (content), `engine.sound.play(nazwa, {pos = pos})`; pole bloku `sound` = grupa.
- Pozycje jako `{x =, y =, z =}` albo wektor. Mod opcjonalny: `"after"` w mod.json i `engine.optional(id)`.
- Przedmioty modów tools i crafting: stick, wooden_/stone_/iron_ + pickaxe/axe/shovel/sword, crafting_table, workbench.
- Klucze biomów moda base: meadow, forest, desert, snowy.
- Kształty bloków: `shape = "slab" | "stairs" | "fence" | "pane" | "wall"` albo `boxes = {{x1,y1,z1,x2,y2,z2}}` w szesnastkach.
- Stworzenia: `ai.hostile = {damage, range, sight}`, `ai.think`, mózg `engine.entities.on_think(rodzaj, fn)`,
  model z pliku `model = {file = "x.glb", animations = {idle, walk, attack}}`, jazda `ride = {seat, speed}`.
- Czat i polecenia: `engine.commands.register(nazwa, {permission, fn})`, `engine.chat.send`, hak `chat.message`,
  role `player` / `moderator` / `admin` (`engine.players.role`).
- Okna: sekcje `tabs`, `row`, `column`, `list`, `slider`, `toggle`, `dropdown`, `image`, `item_button`; `on_change(fields)`.
  Ekran: `engine.ui.bar/text/image` z `anchor` i `offset`.
- Generator w Lua: `engine.worldgen.on_generate(function(ch) ... end)`, `ch.set/get/height/biome/random`, `engine.worldgen.noise`.
- Pogoda `engine.weather.set("rain", 1)`, niebo `engine.sky.set{top, horizon}`; tłumaczenia `lang/pl.json` + `engine.t(klucz)`;
  rzeczy na postaci `engine.player.wear(id, {part, boxes})`; wersje zależności `"requires": ["modkit>=0.1"]`.


---

# Część 2. Instrukcja tworzenia modów (docs/MODDING.md)

## Tworzenie modów

Gra jest pustym silnikiem: zna tylko powietrze. Bloki, przedmioty, biomy, drzewa, zasady i wygląd
dodają mody, łącznie z podstawowym światem (mod `base`). Każdy mod może zmienić to, co dodał inny.

Mod to folder z plikiem `mod.json` i skryptami w Lua 5.4. Gra wczytuje mody z dwóch miejsc:

- `res://mods/` – mody dołączone do gry,
- `user://mods/` – mody gracza (na Windowsie: `%APPDATA%/Godot/app_userdata/Voxel Engine/mods`).

Każdy mod działa we własnym, odizolowanym środowisku. Nie ma dostępu do plików, sieci ani systemu,
tylko do obiektu `engine` opisanego niżej.

## Paczki modów

Gra przychodzi jako **paczka** – cała rozgrywka w jednym folderze z modułami (`game/mods/podstawowa/`):

```
mods/podstawowa/
  pack.json            nazwa, wersja, opis, "defaults": {"accounts": false} – moduły domyślnie wyłączone
  mods/base/  mods/backpack/  mods/horses/  ...   zwykłe mody (moduły paczki)
```

W menu Mody paczka jest jedną pozycją: przełącznik włącza całą paczkę, „Otwórz” pokazuje moduły, każdy
z własnym przełącznikiem i ustawieniami. Mody gracza (`mods/<id>/` obok paczek) są „dodatkami” i wczytują się
po modułach paczek. Własną paczkę robi się tak samo: folder z `pack.json` i podfolderem `mods/`.

Żeby zmienić fragment rozgrywki bez ruszania paczki, mod-dodatek wpisuje `"replaces": ["horses"]` – wtedy
zamiast modułu Konie działa ten mod (może zarejestrować własne stworzenie `horse` z innym modelem i AI).

## Paczki zasobów

Paczka zasobów zmienia wygląd, dźwięki i teksty bez kodu i działa także na cudzym serwerze. Leży w folderze
gry `resourcepacks/<nazwa>/` i podmienia rzeczy **po kluczu**, niezależnie od tego, który mod je dodał i czy
tekstura jest plikiem, czy wzorem:

```
blocks/stone.png                 tekstura bloku (16 × 16), też .top/.bottom/.side/.front albo .north/.east...
blocks/furnace[facing=north,lit=true].front.png   wygląd jednego stanu
blocks/cauldron.glb              model bloku
items/apple.png                  ikona przedmiotu
entities/horse.glb               model stworzenia (+ entities/horse.json: scale, offset, rotation, swing, head, animations)
sounds/cow.say.ogg               dźwięk (kilka wersji: cow.say.1.ogg, cow.say.2.ogg)
lang/pl.json                     teksty: {"horses:horse": "Rumak"}
```

W menu Mody → Paczki zasobów włącza się paczki i ustawia kolejność (wyższa wygrywa). Przycisk
**Eksportuj szablon zasobów** zapisuje wszystko, czego gra teraz używa, w tej strukturze (także tekstury ze
wzorów jako PNG i listę części każdego stworzenia do nazwania węzłów w Blenderze) – wystarczy zmienić pliki.


## Rozdzielczość tekstur

Kafelki bloków mają domyślnie 16 × 16 pikseli. Wyższą rozdzielczość można ustawić na trzy sposoby:

- **mod** w `content.lua`: `engine.textures.resolution(64)` – cała gra w 64 × 64 (tekstury 16 px i wzory są
  powiększane bez rozmywania, większe pliki zmniejszane),
- **paczka zasobów**: `"resolution": 64` w `pack.json` albo po prostu pliki 64 × 64 w `blocks/`,
- **pojedynczy blok**: `resolution = 128` w definicji – tylko ten blok jest ostry, reszta zostaje w swojej
  rozdzielczości (przykład: „Płyty marmurowe” w modzie `building`).

Gra bierze największą rozdzielczość z modów i włączonych paczek. Gracz może ją zmienić w opcjach
(„Rozdzielczość tekstur bloków”: automatycznie albo na sztywno 16–256; wtedy to także górna granica dla
pojedynczych bloków). W przeglądarce najwyżej 32. Kafelki różnych rozmiarów leżą w jednym atlasie, więc bloki
w wysokiej rozdzielczości są tak samo szybkie jak zwykłe; w oddali gra używa mipmap (bez migotania).
Rozdzielczość jest ustawieniem każdego gracza – na serwerze każdy może mieć inną.

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
| `requires` | Mody, które muszą być włączone; wczytają się przed tym modem. Z wersją: `"modkit>=0.2"`, `"ores^1.0"` (ta sama główna), `"base~0.3"` (ta sama główna i poboczna), `>`, `<`, `<=`, `=` |
| `after` | Mody opcjonalne: jeśli są włączone, wczytają się wcześniej (biblioteka przez `engine.optional(id)`) |
| `content` | Pliki Lua fazy content (rejestracja treści) |
| `scripts` | Pliki Lua fazy scripts (logika w świecie) |
| `library` | Mod jest biblioteką dla innych (na liście trafia wyżej) |
| `settings` | Ustawienia widoczne w grze w ekranie Mody |
| `replaces` | Moduły, które ten mod zastępuje (np. `["horses"]`): zastąpiony się nie wczytuje, a mody zależne od niego dostają ten mod (`engine.require("horses")` zwraca jego bibliotekę) |
| `conflicts` | Mody, z którymi ten nie może działać: włączenie jednego wyłącza drugi |

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
	shape = "cube",          -- "cube" (domyślnie), "cross" (roślina z dwóch skrzyżowanych ścian), "model",
	                         -- albo kształt z prostopadłościanów: "slab", "stairs", "fence", "pane", "wall", "boxes"
	transparent = false,     -- true: blok nie zasłania sąsiadów (szkło, liście z dziurami)
	solid = true,            -- kolizja z graczem
	drops = "ruby",          -- łup: klucz przedmiotu, {item, count, chance}, lista takich albo false
	item = true,             -- czy blok ma przedmiot (do ekwipunku i stawiania)
	placeable = true,        -- czy pojawia się w trybie kreatywnym
	hardness = 3.0,          -- sekundy kopania gołą ręką (rośliny domyślnie 0, reszta 1)
	breakable = true,        -- false: nie do wykopania
	gravity = false,         -- true: spada bez podparcia (piasek, żwir)
	loose = nil,             -- obiekt luźny (fizyczny), opis niżej
	light = 0,               -- świecenie 0..15 (pochodnia 14)
	sound = "stone",         -- grupa dźwięków (opis w „Dźwięki”)
	tool = "pickaxe",        -- narzędzie, które kopie szybciej (mod tools)
	random_tick = nil,       -- losowe aktualizacje średnio co tyle sekund (opis w „Aktualizacje bloków”)
	states = nil,            -- stany bloku, opis niżej
})
```

Tekstura z innego moda: `"base:textures/dirt.png"` (tak samo dźwięki: `"base:sounds/pop.ogg"`).

### Kształty bloków (półbloki, schody, płoty)

Blok może się składać z prostopadłościanów. Są częścią siatki chunka (szybkie jak zwykłe bloki), mają kolizję
w swoim kształcie, celownik trafia tylko w ich części, a ikona w ekwipunku pokazuje kształt.

```lua
engine.blocks.register("oak_slab",   { name = "Półblok", shape = "slab",   textures = { all = "base:textures/planks.png" } })
engine.blocks.register("oak_stairs", { name = "Schody",  shape = "stairs", textures = { all = "base:textures/planks.png" } })
engine.blocks.register("oak_fence",  { name = "Płot",    shape = "fence",  texture = "base:textures/planks.png" })
-- własny kształt: liczby w szesnastkach bloku {x1, y1, z1, x2, y2, z2}; przód kształtu to północ (-z)
engine.blocks.register("table", {
	name = "Stolik", texture = "base:textures/planks.png",
	boxes = { { 0, 14, 0, 16, 16, 16 }, { 7, 0, 7, 9, 14, 9 } },
	connect = { group = "table", north = { { 7, 14, 0, 9, 16, 1 } } },  -- opcjonalnie: łączenie z sąsiadami
})
```

| Kształt | Stany dodawane same | Zachowanie |
| --- | --- | --- |
| `slab` | `half` = bottom/top | górny półblok, gdy gracz klika spód bloku albo górną połowę ściany |
| `stairs` | `facing` (4 strony), `half` | stopień od strony, w którą patrzy gracz; pod sufitem do góry nogami |
| `fence` | – | słupek; łączy się z płotami i pełnymi blokami obok |
| `pane` | – | cienka szyba; łączy się z szybami i pełnymi blokami |
| `wall` | – | murek; łączy się z murkami i pełnymi blokami |
| `boxes` (albo samo pole `boxes`) | – | własne prostopadłościany, stan `facing` obraca je |

`connect = { group, north, east, south, west }`: części dodawane, gdy sąsiad z danej strony jest pełnym blokiem
albo ma tę samą grupę. Wystarczy podać `north` – pozostałe strony powstają przez obrót. Bloki kształtowe są
domyślnie przezroczyste dla światła (`transparent = true`); `solid = false` wyłącza kolizję.
Przykład: mod `building` (półbloki i schody z desek, kamienia, bruku i cegieł, płot, murek, szyba, stolik).

### Stany bloku

Blok może mieć stany, np. kierunek, wiek rośliny, zapalony/zgaszony. Każda kombinacja to osobny wariant
(osobny numer bloku), więc stan nic nie kosztuje przy rysowaniu i oświetleniu, a wariant może mieć inne
tekstury, światło, łup czy nazwę.

```lua
engine.blocks.register("furnace", {
	textures = { front = "furnace_front.png", side = "stone.png", top = "stone.png" },
	states = { facing = { "north", "east", "south", "west" }, lit = { false, true } },
	variant = function(state)               -- zmiany definicji dla wariantu (albo nil)
		if state.lit then return { light = 13, textures = { front = "furnace_lit.png" } } end
	end,
})
```

- Pierwsza wartość każdego stanu to stan domyślny; ten wariant ma klucz bloku (`furnace`), pozostałe
  `furnace[facing=east,lit=true]` i nie mają własnego przedmiotu (łup jest z bloku głównego).
- Stan `facing` obraca tekstury: `front` (przód), `back` (tył, domyślnie jak boki), `side`. Blok ze stanem
  `facing` gracz stawia przodem do siebie (`place_facing = false` to wyłącza).
- W skryptach: `engine.blocks.state(pos)` → `{facing = "east", lit = false}`,
  `engine.blocks.set_state(pos, {lit = true})`, `engine.blocks.with_state("furnace", {lit = true})` → numer wariantu,
  `engine.blocks.base(id)` → klucz bloku głównego (dla każdego wariantu ten sam).
- Liczba wszystkich bloków razem z wariantami jest ograniczona do 256 – nie przesadzaj z kombinacjami.

### Dane i kontenery bloku

Blok w świecie może mieć dane moda (np. postęp przetapiania) i własny kontener (np. skrzynia). Zapisują się
ze światem i znikają razem z blokiem (zmiana stanu ich nie usuwa).

```lua
engine.blocks.set_data(pos, "progress", 3)        -- nil usuwa wpis
local d = engine.blocks.data(pos)                 -- kopia: {progress = 3}
local c = engine.blocks.container(pos, 27)        -- id kontenera ("@x,y,z"), tworzy go przy pierwszym użyciu
engine.ui.window({ id = "chest", sections = { { type = "slots", container = c, columns = 9 } } })
```

Gdy blok zniknie, przedmioty z jego kontenera wypadają na ziemię, a mody dostają zdarzenie `block.removed`
z danymi bloku.

### Bloki z modelem

Blok z polem `model` nie jest sześcianem: silnik rysuje dla niego osobny model (np. kocioł, skrzynia
z wiekiem, maszyna). Model to plik GLB/glTF (np. z Blendera) i/lub części z prostopadłościanów opisane w Lua.

```lua
engine.blocks.register("cauldron", {
	shape = "model",
	icon = { pattern = "cauldron", color = "#3a3a42" },      -- ikona przedmiotu (wzór albo PNG)
	model = {
		file = "models/cauldron.glb",          -- nazwane węzły pliku są częściami (pot, liquid, ...)
		scale = 1, offset = { 0, 0, 0 },       -- środek dolnej ściany bloku to (0, 0, 0), blok ma 1 × 1 × 1
		parts = {                              -- części z klocków: jak w stworzeniach
			ladle = { pivot = { 0, 0.72, 0 }, boxes = {
				{ size = { 0.035, 0.6, 0.035 }, pos = { 0.17, 0.2, 0 }, rot = { 0, 0, -22 }, color = "#6a4424" },
				{ size = { 0.2, 0.03, 0.2 }, pos = { 0, 0, 0 }, color = "#ff7a20", tag = "embers", glow = true },
			} },
		},
		animations = {                         -- klatki: czas, rot (stopnie), pos (przesunięcie), scale
			stir = { length = 2.4, loop = true, tracks = {
				ladle = { { 0, rot = { 0, 0, 0 } }, { 1.2, rot = { 0, 180, 0 } }, { 2.4, rot = { 0, 360, 0 } } },
			} },
		},
		emitters = {                           -- ciągłe cząsteczki przypięte do modelu (włącza je wygląd)
			bubbles = { particle = "alchemy.bubble", pos = { 0, 0.73, 0 }, rate = 1, color_from = "liquid" },
		},
		collision = { { min = { 0.06, 0, 0.06 }, max = { 0.94, 0.87, 0.94 } } },
		look = { hide = { "liquid" }, colors = { liquid = "#3a78d8" } },   -- wygląd domyślny
	},
	states = { content = { "empty", "brewing" } },
	variant = function(s)                      -- wygląd zależny od stanu bloku
		if s.content == "brewing" then return { light = 11, look = { anim = "stir", emitters = { "bubbles" }, hide = {} } } end
	end,
})
```

- **Wygląd** (`look`): `anim` (zapętlona animacja), `emitters` (włączone emitery), `colors` (tag albo nazwa
  węzła pliku → kolor), `hide` (ukryte tagi i węzły). Składa się z `model.look`, `look` wariantu (stanu)
  i wyglądu ustawionego w skrypcie: `engine.blocks.look(pos, { colors = { liquid = "#70e060" } })`
  (dokłada zmiany; `nil` usuwa pole). Wygląd zapisuje się ze światem i trafia do wszystkich graczy.
- **Animacja jednorazowa**: `engine.blocks.animate(pos, "plop")` – potem wraca animacja z wyglądu.
- **Obrót**: model patrzy na północ (-Z); stan `facing` obraca go jak teksturę.
- Prostopadłościany bez tagu łączą się w jedną siatkę (mało wywołań rysowania), `glow = true` świeci
  w ciemności, tag pozwala zmieniać kolor i ukrywać.
- Światło: model jest oświetlany jak stworzenia (noc, pochodnie); świecenie bloku daje pole `light` wariantu.

**Model z Blendera**: zrób obiekty z nazwami (np. `pot`, `liquid`, `lid`), środek dołu bloku w (0, 0, 0),
blok to 1 × 1 × 1 m, przód w stronę -Y w Blenderze (po eksporcie -Z). Eksport: File → Export → glTF 2.0,
format „glTF Binary (.glb)”, z materiałami. Plik połóż w folderze moda, np. `models/`. Nazwy obiektów
to części: animacje z Lua nimi ruszają, `colors`/`hide` zmieniają ich wygląd. Przykład wygenerowany
skryptem: `game/tools/make_cauldron.gd` (kocioł toczony z profilu, 4096 trójkątów).

### Aktualizacje bloków

```lua
engine.blocks.on_update("wheat_crop", function(ctx)
	-- ctx: pos, block, key (blok główny), state, data, reason
	if ctx.reason == "random" then ... end     -- losowo, średnio co random_tick sekund (pole bloku)
	if ctx.reason == "scheduled" then ... end  -- po engine.blocks.schedule(pos, sekundy, tag); ctx.tag
	if ctx.reason == "neighbor" then ... end   -- zmienił się blok obok: ctx.from, ctx.from_block
end)
engine.blocks.schedule(pos, 1.5, "smelt")
```

Aktualizacje działają na serwerze, w chunkach wczytanych wokół graczy. Zaplanowane zapisują się ze światem,
więc np. piec pracuje dalej po wczytaniu gry. Losowe dostają tylko bloki z polem `random_tick` (sekundy
albo `true` = 60).

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

Wzory: `potion` (butelka, `color` = ciecz), `cauldron` (ikona kotła), `solid`, `noise`, `speckle`, `bricks`, `planks`, `stripes`, `ore`, `glass`, `lamp`, `chest`, `furnace`,
`furrows` (bloki), `crop` (uprawa, `stage` 1..4) oraz `gem`, `ingot`, `food`, `plant`, `seeds`, `torch`, `stick`,
`pickaxe`, `axe`, `shovel`, `sword`, `hoe`, `hammer` (ikony przedmiotów). Kolory w formacie `#rrggbb` albo `#rrggbbaa`.
Piksele z przezroczystością poniżej 50% są niewidoczne.

Zmiana bloku innego moda (w content.lua, mod musi wczytać się później):

```lua
engine.blocks.get("stone").drops = "cobblestone"
engine.blocks.get("leaves").drops = { { item = "apple", chance = 0.08 } }
```

Numer bloku (`id`) nadaje gra w kolejności rejestracji. W skryptach używaj kluczy tekstowych:
`engine.blocks.id("stone")`, `engine.blocks.key(id)`. Świat zapisuje listę kluczy i przelicza numery,
gdy zmieni się zestaw modów; bloki z wyłączonego moda stają się powietrzem.

## Dźwięki

Pliki OGG, WAV albo MP3 w folderze moda, rejestrowane w content.lua:

```lua
engine.sounds.register("sheep.say", {
	files = { "sounds/sheep1.ogg", "sounds/sheep2.ogg" },   -- losowo jeden z nich (albo file = "...")
	volume = 0.7, pitch = 1.0, pitch_random = 0.08, range = 20,   -- zasięg w blokach
})
```

W skryptach: `engine.sound.play("sheep.say", { pos = pos })` – słyszą gracze w pobliżu; bez `pos` słyszy tylko
gracz, w którego imieniu działa kod (dźwięki interfejsu); `player = id` – tylko ten gracz; `volume`, `pitch`;
`loop = true` zwraca id do `engine.sound.stop(id)`.

Silnik sam gra:
- dźwięki bloków z grupy z pola `sound`: `<grupa>.break` (niszczenie), `.place` (stawianie), `.dig` (kopanie),
  `.step` (kroki); brakujące `place` i `dig` zastępuje `break`. Mod base ma grupy `stone`, `dirt`, `grass`,
  `sand`, `gravel`, `snow`, `leaves`, `wood`, `glass`, a bloki bez `sound` brzmią jak `stone` (rośliny jak `leaves`),
- `water.splash`, `water.swim`, `item.pickup`, `player.hurt`, `ui.click`,
- odgłosy stworzeń z pola `sounds = { idle = "sheep.say", idle_every = 18, hurt = "..." }` (młode wyżej).

Gracz ustawia głośność w Opcjach.

## Statystyki gracza i efekty

Statystyki (`speed`, `jump`, `gravity`, `reach`, `max_health`, `break_speed`, `swim_speed`, `auto_jump`,
`damage`, `defense` i własne) mają wartość bazową i modyfikatory. Kilka modów może zmieniać tę samą
statystykę bez konfliktu: każdy dokłada modyfikator pod własną nazwą źródła, a silnik liczy
`(baza + suma add) × iloczyn mul`.

```lua
engine.player.modify("speed", "zbroja:ciezka", { mul = 0.8 })   -- -20% szybkości od zbroi
engine.player.unmodify("speed", "zbroja:ciezka")               -- zdjęcie modyfikatora
engine.player.get("speed")    -- wartość po modyfikatorach
engine.player.base("speed")   -- wartość bazowa; engine.player.set(stat, v) zmienia bazę (nil = domyślna)
```

Efekty (mikstury, trucizny, premie) to modyfikatory na czas z ikoną i odliczaniem na ekranie. Silnik
sam je odlicza, zdejmuje i zapisuje z kontem gracza (efekt trwa dalej po ponownym wejściu).

```lua
-- content.lua
engine.effects.register("alchemy.speed", {
	name = "Szybkość", color = "#40c8f0", negative = false,
	icon = { pattern = "potion", color = "#40c8f0" },
	stats = { speed = { mul = 1.6 }, jump = { add = 1 } },
})
-- skrypt (w imieniu gracza)
engine.effects.add("alchemy.speed", 45, 1.5)   -- sekundy, siła (mul: 1 + (1.6-1)×1.5, add × 1.5); ponowne dodanie odnawia
engine.effects.get("alchemy.speed")            -- {left, strength} albo nil
engine.effects.remove("alchemy.speed"); engine.effects.list()
```

Zdarzenia: `effect.start` (`name`, `strength`), `effect.end` (`name`).

## Celowanie i promień

```lua
local eye = engine.player.eye_position()      -- Vector3: oczy gracza (w imieniu którego działa kod)
local dir = engine.player.look_direction()    -- Vector3 o długości 1: kierunek celownika
local hit = engine.player.raycast(100)        -- pierwszy blok na linii wzroku do 100 bloków albo nil
-- to samo z dowolnego punktu: engine.world.raycast(skąd, kierunek, zasięg, { liquids = false, solid = true })
if hit then
	-- hit.position (blok), hit.normal (ściana trafienia), hit.place_pos (pole przed ścianą),
	-- hit.point (dokładny punkt), hit.distance, hit.block (numer), hit.key (klucz)
end
```

Domyślnie promień przechodzi przez rośliny, pochodnie i inne bloki bez kolizji oraz przez ciecze.
`engine.player.target()` działa tylko w zasięgu kopania; do dalekiego celowania używaj `raycast`.

## Pociski

Fizykę i trafienia liczy silnik na serwerze (wzdłuż całej drogi w każdej klatce, więc szybki pocisk nie
przenika przez bloki); klienci widzą lot. Mod opisuje rodzaj pocisku i reaguje na trafienie.

```lua
-- content.lua
engine.projectiles.register("block_gun.shot", {
	speed = 24, gravity = 9.8, radius = 0.15, lifetime = 5,              -- m/s, m/s², m, s
	collision = { blocks = true, entities = true, players = true, liquids = false },
	visual = { type = "block", size = 0.4, spin = true },               -- "block" | "item" | "none"
	trail = "alchemy.ember",                                             -- cząsteczki za pociskiem (opcjonalnie)
})

-- main.lua
local id = engine.projectiles.spawn("block_gun.shot", {
	position = engine.player.eye_position(),
	direction = engine.player.look_direction(),   -- albo velocity = {x, y, z}
	speed = 30,                                    -- opcjonalnie zamiast speed z rodzaju
	data = { block = "stone" },                    -- dowolne dane; data.block / data.item = wygląd w locie
})                                                 -- owner = bieżący gracz (można podać inny)

engine.projectiles.on_hit("block_gun.shot", function(ctx)
	-- ctx.hit_type: "block" | "entity" | "player" | "expire" (skończył się czas lotu)
	-- ctx.position (Vector3i trafionego bloku), ctx.normal, ctx.place_pos (= position + normal),
	-- ctx.point (Vector3), ctx.entity / ctx.entity_type, ctx.player, ctx.owner, ctx.data, ctx.velocity
	if ctx.hit_type == "block" and engine.world.get_block(ctx.place_pos) == 0 then
		engine.world.set_block(ctx.place_pos, ctx.data.block)
	elseif ctx.hit_type == "entity" then
		engine.entities.damage(ctx.entity, 4, "pocisk")
	end
end)
```

Obsługa trafienia działa w imieniu strzelca (`engine.player.*` to on). Pocisk nie trafia strzelca przez
pierwsze 0,3 s lotu. `engine.projectiles.remove(id)` usuwa pocisk bez trafienia.

## Cząsteczki

```lua
-- content.lua: opis efektu
engine.particles.register("alchemy.splash", {
	amount = 16,              -- sztuk w wybuchu (w emiterze: na sekundę)
	life = 0.6,               -- sekundy życia
	speed = { 1.0, 2.2 }, direction = { 0, 1, 0 }, spread = 40,   -- prędkość, kierunek, rozrzut (stopnie)
	gravity = 7,              -- w dół; ujemna unosi (dym, para)
	size = { 0.06, 0.02 },    -- rozmiar na początku i na końcu
	color = { "#4a8ae0", "#ffffff" },   -- kolory przez życie (na końcu zanika)
	box = { 0.1, 0, 0.1 },    -- obszar narodzin (pół-wymiary)
	shape = "round",          -- "round", "square", "spark"
	glow = false,             -- true: świeci (ogień, iskry)
	damping = 0,
})
-- skrypt: wybuch widziany przez graczy w pobliżu; opts: color (lista kolorów), amount (mnożnik)
engine.particles.spawn("alchemy.splash", pos, { color = { "#70e060" } })
```

Ciągłe efekty (ogień, para) robi się emiterami modelu bloku (opis wyżej).

## Przedmioty

Każdy blok z `item ~= false` ma przedmiot o tym samym kluczu. Inne przedmioty:

```lua
engine.items.register("apple", {
	name = "Jabłko",
	icon = { pattern = "food", color = "#d23a2a" },   -- albo "textures/apple.png"
	max_stack = 64,
	food = 4,              -- dowolne własne pola, czytane przez engine.items.def("apple").food
	description = "Soczyste, czerwone.",                         -- opis w dymku
	tooltip = { category = "Jedzenie", lines = { "Głód: +4" } },  -- kategoria i stałe linie dymka
})
```

Miejsce w kontenerze to `{ item = "apple", count = 3 }` albo pusta tabela `{}`. Może mieć też
`data` – dane tego egzemplarza (np. amunicja w broni) – i `info` – linie opisu policzone przez mod.

### Dymek z opisem

Gracz widzi opis po najechaniu na przedmiot w oknie (PC), w pasku u dołu okna po dotknięciu przedmiotu
(telefon) i nad paskiem przez 2 s po wybraniu przedmiotu. Opis to: nazwa, `[kategoria]`, `description`,
`tooltip.lines` i linie dynamiczne:

```lua
engine.items.tooltip("block_gun", function(slot)          -- slot = {item, count, data}
	local d = slot.data or {}
	return { "Załadowano: " .. (d.block or "nic"), "Amunicja: " .. (d.ammo or 0) }
end)
```

Funkcja działa na serwerze przy każdej zmianie miejsca z tym przedmiotem, a wynik trafia do graczy razem
z przedmiotem. Ma być szybka i nie może zmieniać ekwipunku.

### Dane egzemplarza przedmiotu

```lua
local hb, i = engine.require("backpack").HOTBAR, engine.hotbar.selected()
engine.items.set_data(hb, i, "ammo", 8)                  -- dopisuje pole do data tego miejsca
local d = engine.items.data(hb, i)                        -- {ammo = 8} (kopia)
engine.items.set(hb, i, { item = "block_gun", count = 1, data = { ammo = 8, block = "stone" } })
```

Stosy z różnymi `data` się nie łączą (`kit.inventory.add` dokłada tylko do stosów bez danych), a
`kit.inventory.take` zachowuje dane. Przedmiot upuszczony na ziemię (z rozbitej skrzyni, z kursora okna albo
`engine.entities.drop(item, n, pos, data)`) zachowuje dane: hak `item.pickup` dostaje je w `ctx.data`, a plecak
kładzie taki przedmiot na wolne miejsce.

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


### Generator w Lua

Oprócz opisu danymi (biomy, drzewa, rudy, struktury) mod może dorzucić własne generowanie w skryptach.
Funkcja dostaje każdy nowy chunk (32 × 32 × 32, nie wczytany z dysku) na serwerze, przed pokazaniem go graczom:

```lua
engine.worldgen.on_generate(function(ch)
	-- ch.x, ch.y, ch.z – chunk; ch.min, ch.max – narożniki w świecie; ch.seed
	local rng = ch.random("glazy")                       -- los zależny tylko od ziarna świata i chunka
	if rng:chance(0.3) then
		local x, z = ch.min.x + rng:int(2, 29), ch.min.z + rng:int(2, 29)
		local y = ch.height(x, z)                         -- powierzchnia z generatora
		if ch.biome(x, z) == "meadow" and ch.contains(x, y, z) then ch.set(x, y + 1, z, "cobblestone") end
	end
	if engine.worldgen.noise3(ch.min.x, ch.min.y, ch.min.z, 40, "jaskinie") > 0.5 then ... end
end)
```

`ch.get(x, y, z)` i `ch.set(x, y, z, blok)` (albo z pozycją: `ch.set(pos, "stone")`) działają na
współrzędnych świata. Bloki poza chunkiem też można stawiać: jeśli sąsiedni chunk już istnieje, zmienia się
od razu, a jeśli nie – zapis czeka, aż powstanie. `engine.worldgen.noise(x, z, skala, salt)` i
`noise3(x, y, z, skala, salt)` to szum -1..1 zależny od ziarna, `engine.worldgen.random(seed)` – los
z metodami `rng:next()`, `rng:int(a, b)`, `rng:chance(p)`, `rng:pick(lista)`. Gracze w grze sieciowej dostają
zmienione chunki z serwera. Przykład: mod `ruins` (głazy, ruiny, kryształowe żyły).

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

### Model z pliku GLB

Zamiast `parts` można podać model z Blendera (eksport glTF binarny `.glb`). Każdy nazwany węzeł pliku jest
częścią (animacje klatkowe modów, `show`/`color` po nazwie siatki), animacje z pliku grają według stanu:

```lua
model = {
	file = "models/zombie.glb",          -- albo "inny_mod:models/x.glb"
	scale = 1.0, offset = { 0, 0, 0 }, rotation = { 0, 180, 0 },
	animations = { idle = "Idle", walk = "Walk", run = "Run", attack = "Attack", hurt = "Hurt" },
	-- bez animacji w pliku: proceduralny ruch węzłów jak przy klockach
	swing = { LegL = 1, LegR = -1 }, wings = { WingL = 1 }, head = "Head", body = "Body",
},
```

`engine.entities.animate(id, "attack")` gra animację z pliku (rola albo nazwa klipu), a gdy jej nie ma –
animację klatkową moda. Przykład: mod `monsters` (model generuje `tools/make_zombie.gd`).

### Wrogowie i mózg w Lua

```lua
ai = {
	hostile = { damage = 3, range = 1.5, sight = 18, cooldown = 1.1, speed = 2.4, knockback = 4 },  -- albo true
	retaliate = true,   -- neutralne: atakuje dopiero zranione
	think = 0.5,        -- co ile sekund wołany jest mózg z Lua (domyślnie 1)
},
spawn = { night = true, max_light = 7, group = { 1, 2 }, max = 6 },  -- też day = true
```

Wrogie stworzenie widzi najbliższego gracza w promieniu `sight`, goni go (stan `chase`) i bije, gdy jest
w zasięgu `range`. Hak `entity.attack` (`ctx.player`, `ctx.amount`, `ctx.cancel`) zmienia albo blokuje cios,
a obrażenia przechodzą jeszcze przez `player.damage` (np. zbroja).

Mózg w Lua dostaje stan stworzenia co `ai.think` sekund (tylko na serwerze):

```lua
engine.entities.on_think("zombie", function(z)
	-- z.id, z.type, z.state, z.pos, z.health, z.max_health, z.data, z.target (gracz albo nil), z.rider,
	-- z.player (najbliższy gracz), z.player_distance, z.in_liquid, z.on_floor
	local l = engine.world.light(z.pos + Vector3(0, 1.7, 0))   -- {sky, block, day}
	if l.day > 0.5 and l.sky >= 14 then engine.entities.damage(z.id, 1, "sun") end
end)
```

Sterowanie: `engine.entities.set_state(id, stan, sekundy)` (`idle`, `wander`, `flee`, `follow`, `chase` albo
własna nazwa – stworzenie wtedy stoi), `attack(id, gracz)`, `target(id)`, `move_to(id, pos)`, `look_at(id, pos)`,
`push(id, wektor)`, `velocity(id)`, `nearest_player(pos, promień)` → `{id, distance, position}`.

### Jazda

```lua
ride = { seat = { 0, 0.95, 0 }, speed = 2.3, jump = 1.3, item = nil },
```

Kliknięcie stworzenia z polem `ride` sadza gracza (o ile hak `entity.interact` nie ustawił `ctx.cancel`;
`item` – wymagany przedmiot w ręce). Gracz steruje jak zwykle, tylko szybciej (`speed`, `jump` to mnożniki),
a stworzenie idzie z nim. Shift albo dotknięcie w powietrze zsiada. Z Lua: `engine.entities.mount(id[, gracz])`,
`dismount([gracz])`, `rider(id)`; zdarzenia `entity.mount` i `entity.dismount`, hak `entity.mount` może anulować.
Przykład: mod `horses` (oswajanie jabłkiem, siodło jako ukryty tag).

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
| `entity.attack` | wróg uderza gracza: `id`, `type`, `player`, `amount` (można zmienić albo anulować) |
| `entity.mount` | gracz wsiada na stworzenie: `id`, `type`, `player` (można anulować) |
| `item.pickup` | gracz podchodzi do przedmiotu: `item`, `count`; ustaw `ctx.taken` (ile zabrano) |
| `camera.update` | co klatkę (tylko `after`, tylko gracz lokalny): `mode`, `yaw`, `pitch`, `distance`, `height`, `side`, `fov_offset` |

## Zdarzenia

`engine.on(nazwa, fn)` reaguje na zdarzenie, `engine.emit(nazwa, dane)` wysyła własne zdarzenie do innych modów.

| Zdarzenie | Dane |
| --- | --- |
| `weather.changed` | `kind`, `from`, `intensity` – zmiana pogody |
| `player.pose` | `pose` – gracz kuca, pełza, siada albo wstaje |
| `world_ready` | brak, po wczytaniu wszystkich modów |
| `tick` | `dt` (0.1 s), `time` (godzina) – 10 razy na sekundę |
| `player.land` | `fall` (wysokość upadku w blokach), `speed` |
| `player.death` | `cause`, `pos` |
| `player.underwater` | `underwater` (oczy weszły pod ciecz albo z niej wyszły) |
| `entity.spawn` | `id`, `type`, `pos` |
| `entity.death` | `id`, `type`, `pos`, `cause`, `data` |
| `entity.tick` | raz na sekundę dla każdego stworzenia: `id`, `type`, `state`, `pos`, `data` |
| `entity.graze` | `id`, `type`, `pos` (blok, który stworzenie skubało) |
| `entity.mount`, `entity.dismount` | `id`, `type`, `player` – gracz wsiadł albo zsiadł |
| `block.removed` | `pos`, `block`, `key`, `data` – zniknął blok z danymi albo kontenerem |
| `player.join` | `id`, `name` (konto) – gracz wszedł do gry (po zalogowaniu); tu twórz kontenery gracza |
| `player.leave` | `id`, `name` – gracz wyszedł z serwera |
| `ui.closed` | `id` okna zamkniętego przez gracza |

## API `engine`

Pozycje można podawać jako wektor albo tabelę `{x = 1, y = 2, z = 3}`.

| Funkcja | Opis |
| --- | --- |
| `engine.log(...)`, `print(...)` | Zapis do dziennika moda |
| `engine.export(t)` / `engine.require(id)` | Udostępnienie tabeli innym modom / pobranie biblioteki |
| `engine.optional(id)` | Biblioteka moda albo `nil`, gdy jest wyłączony (w mod.json `"after": [id]`) |
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
| `engine.blocks.state/set_state/with_state/base` | Stany bloku (opis wyżej) |
| `engine.blocks.data/set_data/clear_data/container` | Dane i kontener bloku |
| `engine.blocks.on_update(klucze, fn)`, `schedule(pos, s, tag)` | Aktualizacje bloków |
| `engine.sound.play(nazwa, opts)`, `stop(id)`; `engine.sounds.register` | Dźwięki |
| `engine.blocks.look(pos, wygląd)`, `get_look(pos)`, `animate(pos, nazwa)` | Model bloku: wygląd i animacje |
| `engine.particles.register(nazwa, opis)`, `spawn(nazwa, pos, opts)` | Cząsteczki |
| `engine.projectiles.register/spawn/on_hit/remove` | Pociski |
| `engine.player.eye_position()`, `look_direction()`, `raycast(zasięg, opts)` | Celowanie |
| `engine.world.raycast(skąd, kierunek, zasięg, opts)` | Promień przez świat |
| `engine.items.data(c, i)`, `set_data(c, i, k, v)`, `tooltip(klucz, fn)` | Dane egzemplarza i opis dynamiczny |
| `engine.world.biome(pos)`, `biome_key(pos)`, `height(x, z)`, `time()`, `set_time(h)` | Świat |
| `engine.player.position()`, `teleport(pos)`, `velocity()`, `push(v)` | Ruch gracza |
| `engine.player.set(stat, v)`, `get(stat)`, `base(stat)`, `modify(stat, źródło, {add, mul})`, `unmodify(stat, źródło)` | Statystyki: `speed`, `jump`, `gravity`, `reach`, `auto_jump`, `max_health`, `spawn`, `break_speed`, `swim_speed` (opis wyżej) |
| `engine.effects.register/add/remove/get/list` | Efekty na czas |
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

Postać ma wbudowane animacje proceduralne, które płynnie przechodzą jedna w drugą: stanie i oddech, chód,
bieg (Ctrl), kucanie (Shift – wolniej i bez spadania z krawędzi), pełzanie (X – przejście szczeliną wysoką na
1 blok; nie wstanie, dopóki nad głową nie ma miejsca), siedzenie (Z), jazda, pływanie, skok, spadanie i
przysiad po lądowaniu. Do tego akcje: kopanie (pętla zamachów), machnięcie przy stawianiu, seria trzech ataków
(cięcie, cięcie odwrotne, uderzenie z góry – szybkie kliknięcia, trzecie zadaje 1,5× obrażeń) i odrzut po
zranieniu. Inni gracze widzą postawę i akcje. Na telefonie przycisk „Kucnij” zmienia postawę po kolei.

`engine.animation.override(stan, animacja)` działa dla stanów: `idle`, `walk`, `run`, `jump`, `crouch`,
`crawl`, `sit`, `swim`. `engine.player.pose()` zwraca postawę gracza, a zdarzenie `player.pose` mówi o zmianie.
Podgląd animacji: `tools/anim_preview.tscn` (obrazek z klatkami z boku i z przodu).

### Kolory postaci

`engine.player.colors({ tunic = "#a83a32", scarf = "#e0b040" })`. Części: `skin`, `tunic`, `tunic_dark`,
`trousers`, `boots`, `leather`, `scarf`, `hair`, `bedroll`, `gold`, `eye`, `mouth`, `nose`, `strap`.

### Przedmiot w ręce i rzeczy na postaci

Postać trzyma w prawej ręce wybrany przedmiot (ikona), widzą to wszyscy gracze. Mod może założyć na postać
własne klocki – hełm, plecak, pelerynę:

```lua
engine.player.wear("helm", { part = "head", boxes = {
	{ size = { 0.46, 0.2, 0.46 }, pos = { 0, 0.42, 0 }, color = "#8a8a94" },
	{ size = { 0.06, 0.18, 0.02 }, pos = { 0, 0.3, -0.23 }, color = "#6a6a74" },
} })
engine.player.wear("helm", nil)   -- zdejmuje
```

Części: `body`, `head`, `arm_left`, `arm_right`, `leg_left`, `leg_right`; `pos` względem punktu obrotu części
(głowa: szyja, ręce: bark, nogi: biodro). Przykład: kapelusz pod klawiszem K w modzie `emotes`.

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

Więcej sekcji (wszystkie można zagnieżdżać w `row`, `column` i zakładkach):

```lua
{ type = "tabs", id = "tab", selected = 1, on_change = fn, tabs = {
	{ title = "Przedmioty", sections = { ... } },
	{ title = "Ustawienia", sections = { ... } },
} },
{ type = "row", sections = { ... } },          -- obok siebie (na telefonie jedna pod drugą; wrap = false zostawia w rzędzie)
{ type = "column", sections = { ... } },       -- jedna pod drugą, np. kolumna w wierszu
{ type = "image", item = "ruby", size = { 96, 96 }, caption = "Rubin" },   -- albo image = "textures/mapa.png" / wzór
{ type = "list", id = "wybor", items = { { text = "Miecz", item = "iron_sword" }, "Tarcza" }, selected = 1, height = 200, on_change = fn },
{ type = "slider", id = "glosnosc", label = "Głośność", min = 0, max = 1, step = 0.05, value = 0.8, on_change = fn },
{ type = "toggle", id = "noc", text = "Tryb nocny", value = false, on_change = fn },
{ type = "dropdown", id = "trudnosc", label = "Trudność", options = { "Łatwy", "Normalny" }, selected = 2, on_change = fn },
{ type = "item_button", id = "kup", item = "bread", count = 3, text = "Kup chleb", on_press = fn },
{ type = "text", text = "Uwaga!", size = 22, color = "#ffd060", align = "center" },
{ type = "separator" }, { type = "space", size = 16 },
```

`fields` w `on_press` i `on_change` zawiera wartości wszystkich pól okna po `id`: tekst pól, liczby suwaków,
`true/false` przełączników, numer wybranej pozycji listy, listy rozwijanej i zakładki (od 1). `on_change`
wywołuje się po zmianie (suwak: po puszczeniu). Przykład: mod `handbook` (klawisz J).

### Elementy na ekranie gry

```lua
engine.ui.bar({ id = "mana", label = "Mana", value = 30, max = 50, color = "#4a8ae0" })
engine.ui.text({ id = "wynik", text = "Punkty: 12", color = "#ffffff", font_size = 18 })
engine.ui.image({ id = "kompas", item = "compass", size = { 28, 28 }, text = "N", alpha = 0.8,
	anchor = "top", offset = { 0, 12 } })   -- anchor: top_left, top, top_right, left, center, right, bottom_left, bottom, bottom_right
engine.ui.remove("kompas")
```

Bez `anchor` paski i obrazki stoją w lewym górnym rogu jeden pod drugim, napisy po prawej.

## Pogoda i niebo

```lua
engine.weather.set("rain", 0.8)       -- "clear", "rain", "snow", "storm"; siła 0..1
local w = engine.weather.get()        -- {kind, intensity, sky}
engine.sky.set({ top = "#4a2a5a", horizon = "#c0603a", fog = 2.0, sun = 0.6, ambient = 0.8 })
engine.sky.reset()
engine.on("weather.changed", function(e) ... end)   -- e.kind, e.from, e.intensity
```

Serwer ustawia pogodę, gracze widzą ją u siebie: deszcz w zimnych biomach pada jako śnieg, na pustyni nie
pada, a pod dachem opadów nie widać. Pogoda przyciemnia niebo i słońce, zagęszcza mgłę i zapisuje się w świecie.
Polecenie `/weather rain 0.5` (moderator).

## Tłumaczenia

Teksty moda mogą leżeć w plikach `lang/pl.json`, `lang/en.json` (płaski słownik klucz → tekst). Gracz wybiera
język w opcjach („Język tekstów modów”).

```lua
-- content.lua: nazwa z "@" pochodzi z pliku języka
engine.blocks.register("lamp", { name = "@lamp", ... })
-- skrypty: tekst w języku gracza, którego dotyczy (w grze sieciowej każdy może mieć inny)
engine.ui.notify(engine.t("welcome", { name = engine.player.name() }))   -- "Witaj, {name}!"
```

Brakujący klucz szuka się po kolei: w języku gracza, po polsku, po angielsku, w innych modach; na końcu zwracany
jest sam klucz. Przykłady: mody `horses` i `handbook`.

## Czat, polecenia i uprawnienia

T albo Enter otwiera czat (na telefonie: pauza → Czat). Tekst od `/` to polecenie. Wbudowane: `/help`, `/list`,
`/me`, `/mods`, `/tp`, `/give`, `/time`, `/kick`, `/op`, `/deop`, `/role`, `/reload`.

Role: `player` < `moderator` < `admin`. Gospodarz gry (gra lokalna i serwer z oknem) jest administratorem,
na serwerze dedykowanym administratorów podaje się przy starcie: `--admin=konto1,konto2`. Pozostałe role nadaje
`/op`, `/role konto moderator` albo mod (`engine.players.set_role`); zapisują się w świecie.

```lua
engine.commands.register("dom", {
	description = "przenosi do domu", usage = "/dom [ustaw]", permission = "player",
	fn = function(ctx)            -- ctx.player, ctx.name, ctx.args (lista słów), ctx.text, ctx.role
		if ctx.args[1] == "ustaw" then
			engine.player.storage.set("dom", engine.player.position())
			return "Dom ustawiony"
		end
		local p = engine.player.storage.get("dom")
		if not p then return "Najpierw /dom ustaw" end
		engine.player.teleport(p)
	end,                          -- zwrócony tekst widzi tylko ten gracz
})

engine.chat.send("Burza nadciąga!", { color = "#ffd060" })            -- do wszystkich
engine.chat.send("Tylko dla ciebie", { player = id, from = "Strażnik" })
engine.hooks.before("chat.message", function(c)                       -- c.player, c.name, c.text, c.color
	c.text = c.text:gsub("brzydkie", "***")                           -- albo c.cancel = true
end)
engine.hooks.before("command", function(c)                            -- c.player, c.name, c.args; c.cancel, c.reply
	if c.name == "tp" and engine.world.time() > 20 then c.cancel = true c.reply = "Nocą nie wolno" end
end)
engine.players.role(id)                    -- "player" | "moderator" | "admin"
engine.players.set_role("Ola", "moderator")
```

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

### Pobieranie modów z serwera

Gracz nie musi mieć modów serwera. Przy dołączaniu klient wysyła odciski (skróty zawartości) swoich modów;
jeśli serwer używa modu, którego gracz nie ma albo ma w innej wersji, gra pokazuje listę (nazwa, wersja, autor,
rozmiar, „nowy” albo „aktualizacja”) z przyciskami „Pobierz i dołącz” i „Anuluj”. Po zgodzie mody pobierają się
od serwera kawałkami (pasek postępu), trafiają do `user://server_mods/<id>@<odcisk>` i działają tylko na czas
gry na tym serwerze – własne mody gracza zostają nietknięte. Przy następnym wejściu (ten sam odcisk) nic się
już nie pobiera. Tak samo działa serwer gracza i serwer bez okna.

- W paczce są tylko pliki: `lua`, `json`, `png`, `txt`, `md`, `ogg`, `wav`, `mp3`, `glb`, `gltf`, `bin`, `cfg`
  (limit 64 MB na serwer). Ścieżki są sprawdzane, a u klienta działa tylko faza `content`, w piaskownicy.
- Odcisk liczy obrazy z pikseli, więc mod wbudowany w grę i ten sam mod z folderu mają ten sam odcisk.
- Wersja w `mod.json` służy do opisu; o pobraniu decyduje zawartość plików.

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
| `farming` | stany (wiek uprawy, wilgotność), losowe aktualizacje, aktualizacja od sąsiada, `item.use` z pozycją |
| `storage` | skrzynia: kontener bloku, stan `facing`, mody opcjonalne (`after`, `engine.optional`) |
| `alchemy` | kocioł: blok z modelem GLB i klocków, animacje, emitery cząsteczek, wygląd z gry, mikstury na czas |
| `monsters` | zombie: wróg (`ai.hostile`), model GLB z animacjami z pliku, mózg w Lua, pojawianie się nocą |
| `horses` | konie: jazda (`ride`), oswajanie przez hak `entity.interact`, ukryte siodło (tag) |
| `handbook` | bogatsze okna: zakładki, lista z ikonami, obrazek, suwak, przełącznik, lista rozwijana; kompas z `anchor` |
| `ruins` | generator w Lua: głazy, ruiny i kryształy z deterministycznego losu i szumu 3D |
| `building` | kształty z prostopadłościanów: półbloki, schody, płot, murek, szyba, własny kształt (stolik) |
| `smelting` | piec: dane bloku, zaplanowane aktualizacje, wariant świecący, okno odświeżane wszystkim patrzącym |

## Narzędzia modera

- **Konsola** (F2 albo `, na telefonie w menu pauzy): dziennik modów z błędami (na czerwono, ze śladem
  wywołań: plik i linia) oraz linia poleceń. Kod Lua wykonuje się na serwerze w imieniu Twojego gracza,
  np. `engine.player.position()`, `engine.effects.add("alchemy.speed", 30)`, `x = 5` i potem `x * 2`.
  W grze sieciowej tylko administrator. Strzałki w górę/dół – historia.
- **Przeładowanie modów**: `/reload` w konsoli zapisuje grę, wczytuje pliki modów od nowa (także nowe mody
  i zmienioną treść) i wraca do świata – bez wychodzenia z gry. Nie działa, gdy na serwerze są inni gracze.
- **Błędy**: w grze widać pierwszą linię, w konsoli pełny opis z miejscem w kodzie (`mojmod/main.lua:42`).
- **Podpowiedzi w edytorze**: plik `docs/engine_api.lua` opisuje całe API `engine` dla Lua Language Server.
  W VS Code zainstaluj rozszerzenie „Lua” (sumneko) i otwórz folder repozytorium albo `game/mods`
  (pliki `.luarc.json` już wskazują definicje) – edytor podpowie funkcje i argumenty.
  Po zmianach w API: `python3 tools/build_api_defs.py`.

## Bezpieczeństwo

Każde wywołanie kodu moda ma limit czasu (liczony w instrukcjach Lua, około 0,1–0,3 s na hak i kilka
sekund na wczytanie pliku) i limit pamięci (256 MB na wszystkie mody). Mod, który go przekroczy, np. przez
pętlę bez końca, zostaje wyłączony do końca gry, a gracz dostaje komunikat. Pliki modów wczytywane są tylko
jako tekst (bez binarnego bajtkodu), `pcall` nie połknie błędu limitu, korutyny też są pod limitem,
a wspólnej metatabeli tekstów nie da się zmienić. Test: `godot --headless --path game -s tests/lua_guard.gd`.

## Co będzie dalej

- Wymiary (osobne światy, np. jaskiniowy albo niebiański, z przejściem między nimi).
- Tłumaczenie interfejsu samej gry (teraz tłumaczą się teksty modów).
- Modele GLB dla przedmiotów w ręce i dla rzeczy zakładanych na postać.


---

# Część 3. Klucze istniejące w grze (mody dołączone do gry)

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

---

# Część 4. Najczęstsze pułapki

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

## Mod `storage`

`mod.json`

```json
{
	"id": "storage",
	"name": "Skrzynie",
	"version": "0.1.0",
	"author": "Jakub Lewicki",
	"description": "Skrzynia na 27 przedmiotów. Stawia się przodem do gracza, a po zniszczeniu jej zawartość wypada na ziemię. W grze wieloosobowej kilku graczy może korzystać z tej samej skrzyni. Przykład kontenera bloku i stanu facing.",
	"requires": ["backpack"],
	"after": ["crafting_classic", "crafting_discovery"],
	"content": ["content.lua"],
	"scripts": ["main.lua"],
	"settings": [
		{"key": "starter", "label": "Zestaw na start (skrzynie)", "type": "bool", "default": true}
	]
}
```

`content.lua`

```lua
-- Stan facing: silnik obraca teksturę "front" i stawia blok przodem do gracza.
engine.blocks.register("chest", {
	name = "Skrzynia",
	textures = {
		front = { pattern = "chest", color = "#a8743c", color2 = "#94622f", spots = "#d8c040" },
		side = { pattern = "planks", color = "#9a6a38", color2 = "#b07a40" },
		top = { pattern = "planks", color = "#8a5a2e", color2 = "#a06a36" },
	},
	states = { facing = { "north", "east", "south", "west" } },
	hardness = 2.0,
	tool = "axe",
	sound = "wood",
})
engine.sounds.register("chest.open", { files = { "base:sounds/wood_break1.ogg", "base:sounds/wood_break2.ogg" }, volume = 0.6, pitch = 0.6 })
```

`main.lua`

```lua
-- Skrzynia: kontener przypisany do bloku (engine.blocks.container) – silnik zapisuje go ze światem,
-- a po zniszczeniu bloku przedmioty wypadają.
local backpack = engine.require("backpack")
local SIZE = 27

engine.hooks.before("block.use", function(ctx)
	if engine.blocks.base(ctx.block) ~= "chest" then return end
	ctx.cancel = true
	local c = engine.blocks.container(ctx.pos, SIZE)
	engine.sound.play("chest.open", { pos = ctx.pos })
	engine.ui.window({
		id = "chest",
		title = "Skrzynia",
		sections = {
			{ type = "slots", container = c, columns = 9, title = "Skrzynia" },
			{ type = "slots", container = backpack.BACKPACK, columns = 9, title = "Plecak" },
			{ type = "slots", container = backpack.HOTBAR, columns = 8, title = "Pasek" },
		},
	})
end)

local classic = engine.optional("crafting_classic")
if classic then classic.shaped({ "PPP", "P P", "PPP" }, { P = "planks" }, "chest") end
local discovery = engine.optional("crafting_discovery")
if discovery then discovery.add("skrzynia", { planks = 8 }, "chest", 1, 4) end

-- zestaw na start (raz na konto; wyłączany w ustawieniach moda)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("started", false) then return end
	local bp = engine.require("backpack")
	if engine.items.def("chest") then bp.give("chest", 2) end
	engine.player.storage.set("started", true)
end)
```

## Mod `farming`

`mod.json`

```json
{
	"id": "farming",
	"name": "Uprawy",
	"version": "0.1.0",
	"author": "Jakub Lewicki",
	"description": "Motyka zamienia trawę i ziemię w pole uprawne, na którym rosną posiane nasiona pszenicy (nasiona wypadają z wysokiej trawy). Pole przy wodzie jest wilgotne i uprawy rosną na nim szybciej. Przykład stanów bloku (wiek uprawy, wilgotność pola), losowych aktualizacji i aktualizacji od sąsiada.",
	"requires": ["modkit", "backpack"],
	"after": ["animals", "tools", "crafting_classic", "crafting_discovery"],
	"content": ["content.lua"],
	"scripts": ["main.lua"],
	"settings": [
		{"key": "starter", "label": "Zestaw na start (motyka i nasiona)", "type": "bool", "default": true},
		{"key": "growth", "label": "Szybkość wzrostu", "type": "float", "default": 1.0, "min": 0.25, "max": 8.0}
	]
}
```

`content.lua`

```lua
-- Pole uprawne: stan moist (wilgotne przy wodzie). Losowe aktualizacje co ok. 20 s sprawdzają wodę.
engine.blocks.register("farmland", {
	name = "Pole uprawne",
	textures = { top = { pattern = "furrows", color = "#6e4c2e", color2 = "#5c3f24" }, side = "base:textures/dirt.png", bottom = "base:textures/dirt.png" },
	states = { moist = { false, true } },
	variant = function(s)
		if s.moist then return { textures = { top = { pattern = "furrows", color = "#4a311b", color2 = "#3a2614" } } } end
	end,
	random_tick = 20,
	drops = "dirt",
	item = false,
	hardness = 0.6,
	sound = "dirt",
	tool = "shovel",
})

-- Pszenica: stan age 0..3 (wygląd i łup zależą od wieku).
local GREEN, RIPE = "#5aa03a", "#e0c050"
engine.blocks.register("wheat_crop", {
	name = "Pszenica",
	shape = "cross",
	states = { age = { 0, 1, 2, 3 } },
	variant = function(s)
		local ripe = s.age == 3
		local v = {
			textures = { all = { pattern = "crop", stage = s.age + 1, color = ripe and "#9a9a40" or GREEN, color2 = ripe and RIPE or "#86c454" } },
		}
		if ripe then
			v.name = "Dojrzała pszenica"
			v.drops = { { item = "wheat", count = 1 }, { item = "wheat", count = 1, chance = 0.4 }, { item = "seeds", count = 1 }, { item = "seeds", count = 1, chance = 0.6 } }
		end
		return v
	end,
	drops = "seeds",
	item = false,
	random_tick = 30,
	hardness = 0,
	sound = "leaves",
})

engine.items.register("seeds", { name = "Nasiona pszenicy", icon = { pattern = "seeds", color = "#d8c070", color2 = "#9a8440" } })
if not engine.items.def("wheat") then
	engine.items.register("wheat", { name = "Pszenica", icon = { pattern = "plant", color = "#e0c050", color2 = "#b89a30" } })
end
engine.items.register("wooden_hoe", { name = "Drewniana motyka", hoe = true, max_stack = 1, icon = { pattern = "hoe", color = "#a8743c", color2 = "#7a5228" } })
engine.items.register("stone_hoe", { name = "Kamienna motyka", hoe = true, max_stack = 1, icon = { pattern = "hoe", color = "#8a8a8a", color2 = "#666666" } })

-- nasiona wypadają z wysokiej trawy (obok pszenicy z moda animals)
local tg = engine.blocks.get("tall_grass")
if tg then
	local drops = type(tg.drops) == "table" and tg.drops or {}
	if drops.item then drops = { drops } end
	drops[#drops + 1] = { item = "seeds", count = 1, chance = 0.15 }
	tg.drops = drops
end
```

`main.lua`

```lua
-- Uprawy: motyka, siew, wzrost (losowe aktualizacje), wilgotność pola, uprawa znika bez pola (aktualizacja od sąsiada).
local kit = engine.require("modkit")
local backpack = engine.require("backpack")

local function at(p, dy) return { x = p.x, y = p.y + dy, z = p.z } end
local function base_at(p) return engine.blocks.base(engine.world.get_block(p)) end
local function center(p) return { x = p.x + 0.5, y = p.y + 0.5, z = p.z + 0.5 } end
local growth = engine.settings.get("growth") or 1

local function water_near(p)
	for dx = -4, 4 do
		for dz = -4, 4 do
			for dy = 0, 1 do
				local k = engine.blocks.key(engine.world.get_block({ x = p.x + dx, y = p.y + dy, z = p.z + dz }))
				if k:sub(1, 5) == "water" then return true end
			end
		end
	end
	return false
end

engine.hooks.before("item.use", function(ctx)
	if not ctx.pos then return end
	local def = engine.items.def(ctx.item)
	local above = at(ctx.pos, 1)
	local free = engine.world.get_block(above) == 0
	-- motyka: trawa albo ziemia z wolnym miejscem nad nią
	if def and def.hoe then
		local k = base_at(ctx.pos)
		local plant = engine.blocks.base(engine.world.get_block(above))
		if (k == "grass" or k == "dirt") and (free or plant == "tall_grass") then
			if not free then engine.world.set_block(above, 0) end
			engine.world.set_block(ctx.pos, "farmland")
			engine.sound.play("dirt.place", { pos = ctx.pos })
			if water_near(ctx.pos) then engine.blocks.set_state(ctx.pos, { moist = true }) end
		end
		ctx.cancel = true
	-- nasiona: tylko na polu uprawnym
	elseif ctx.item == "seeds" then
		if base_at(ctx.pos) == "farmland" and free then
			engine.world.set_block(above, "wheat_crop")
			engine.sound.play("leaves.place", { pos = above })
			kit.inventory.take(backpack.HOTBAR, ctx.slot, 1)
		end
		ctx.cancel = true
	end
end)

engine.blocks.on_update("wheat_crop", function(ctx)
	local soil = at(ctx.pos, -1)
	if ctx.reason == "neighbor" then
		-- uprawa bez pola pod spodem znika i zostawia nasiona
		if base_at(soil) ~= "farmland" then
			engine.world.set_block(ctx.pos, 0)
			engine.entities.drop("seeds", 1, center(ctx.pos))
		end
	elseif ctx.reason == "random" and ctx.state.age < 3 then
		local moist = engine.blocks.state(soil).moist
		local chance = (moist and 1.0 or 0.35) * growth
		if engine.random() < chance then
			engine.blocks.set_state(ctx.pos, { age = math.min(3, ctx.state.age + (chance > 1 and engine.random() < chance - 1 and 2 or 1)) })
		end
	end
end)

engine.blocks.on_update("farmland", function(ctx)
	if ctx.reason == "random" then
		local wet = water_near(ctx.pos)
		if wet ~= ctx.state.moist then
			engine.blocks.set_state(ctx.pos, { moist = wet })
		elseif not wet and engine.world.get_block(at(ctx.pos, 1)) == 0 and engine.random() < 0.3 then
			engine.world.set_block(ctx.pos, "dirt")   -- suche, puste pole zarasta
		end
	elseif ctx.reason == "neighbor" and ctx.from.y == ctx.pos.y + 1 then
		-- blok postawiony na polu ugniata je z powrotem w ziemię
		local b = engine.world.get_block(ctx.from)
		if b ~= 0 and engine.blocks.base(b) ~= "wheat_crop" and not engine.blocks.key(b):find("water") then
			engine.world.set_block(ctx.pos, "dirt")
		end
	end
end)

-- przepisy, gdy są mody rzemiosła
local classic = engine.optional("crafting_classic")
if classic then
	classic.shaped({ "MM", " S", " S" }, { M = "planks", S = "stick" }, "wooden_hoe")
	classic.shaped({ "MM", " S", " S" }, { M = { "cobblestone", "stone" }, S = "stick" }, "stone_hoe")
	classic.shapeless({ wheat = 1 }, "seeds", 1)
end
local discovery = engine.optional("crafting_discovery")
if discovery then
	discovery.add("motyka_drewniana", { planks = 2, stick = 2, log = 1 }, "wooden_hoe", 1, 3)
	discovery.add("motyka_kamienna", { cobblestone = 2, stick = 2, log = 1 }, "stone_hoe", 1, 4)
end

-- zestaw na start (raz na konto; wyłączany w ustawieniach moda)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("started", false) then return end
	local bp = engine.require("backpack")
	if engine.items.def("wooden_hoe") then bp.give("wooden_hoe", 1) end
	if engine.items.def("seeds") then bp.give("seeds", 8) end
	engine.player.storage.set("started", true)
end)
```

