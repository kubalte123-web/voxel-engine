class_name Registry
extends RefCounted
## Rejestr treści zbudowany z danych zarejestrowanych przez mody w fazie content.lua:
## bloki (id, właściwości, kafelki atlasu), przedmioty z ikonami, dane generatora świata i animacje.
## Id bloków nadawane są w kolejności rejestracji; świat zapisuje paletę kluczy i przelicza id przy wczytaniu.

const OPAQUE := 1
const CROSS := 2
const SOLID := 4
const LIQUID := 8
const THIN := 16           # cienki słupek (pochodnia)
const MODEL := 32          # blok z własnym modelem (bez ścian w siatce chunka)
const BOXES := 64          # kształt z prostopadłościanów w siatce chunka (półblok, schody, płot)
const SHAPE_STRIDE := 11
const LEVELS := 8          # poziomy cieczy: 1 (cienka warstwa) .. 8 (pełny blok)
const MAX_BLOCKS := 256
const ATLAS_COLS := 16
const PX := 16

var keys: Array[String] = ["air"]
var names: Array[String] = ["Powietrze"]
var index := {"air": 0}
var defs: Array = [{"key": "air", "name": "Powietrze", "drops": []}]
var props := PackedInt32Array([0])
var tiles := PackedInt32Array([0, 0, 0, 0, 0, 0])
var tile_images: Array[Image] = []
var liquid := PackedInt32Array([0])  # id bloku -> rodzaj cieczy * 16 + poziom (0 = nie ciecz)
var liquid_kinds: Array = []         # [{key, name, source, levels: [id dla poziomu 0..8], color, deep, viscosity, ...}]
var hardness := PackedFloat32Array([0.0])
var lprops := PackedInt32Array([0])  # id -> świecenie 0..15 | 16 nieprzezroczysty | 32 ciecz
var tile_colors: Array[Color] = []
var shape_index := PackedInt32Array()   # id -> [przes, ile, grupa, N przes, N ile, E.., S.., W..] (prostopadłościany)
var shape_boxes := PackedFloat32Array()  # po 6 liczb na prostopadłościan, w szesnastkach bloku
var _shape_groups := {}   # średni kolor kafelka (dalekie widoki, cząsteczki)
var atlas: ImageTexture
var atlas_rows := 1
## Rozdzielczość kafelków: domyślna dla wszystkich (texture_res, z modów, paczek zasobów albo opcji gracza)
## i własna dla bloków z polem resolution. Kafelki różnych rozmiarów są upakowane w jednym atlasie;
## siatki biorą położenie kafelka z tile_rects (u, v, szerokość, wysokość – po 4 liczby na kafelek).
var texture_res := 16
var texture_cap := 512
var tile_px := PackedInt32Array()       # docelowy rozmiar każdego kafelka
var tile_rects := PackedFloat32Array()
var lod_map: ImageTexture                # do ilu poziomów mipmap wolno zejść w danym miejscu atlasu
var max_lod := 0.0
var atlas_size := Vector2(256, 16)

var items := {}                    # klucz -> {key, name, max_stack, block, mod, icon, data}
var item_keys: Array[String] = []
var placeable: Array[String] = []  # przedmioty-bloki do stawiania (tryb kreatywny)
var worldgen := {}
var animations := {}
var effects := {}                  # efekt -> {name, icon, color, stats, negative}
var projectiles := {}              # rodzaj pocisku -> opis (fizyka, kolizje, wygląd)
var particles := {}                # nazwa efektu cząsteczek -> opis
var sounds := {}                   # nazwa dźwięku -> {file|files, volume, pitch, pitch_random, range, mod}
var entities := {}                 # rodzaj stworzenia -> definicja (części modelu, AI, łup, pojawianie się)
var errors: Array[String] = []

var mod_paths := {}  # id moda -> folder (do wczytywania tekstur)
var _icons := {}
var _tex_index := {}  # opis tekstury -> numer kafelka


static func arr(v: Variant) -> Array:
	if v is Array:
		return v
	return []


func _mod_path(mod_id: String) -> String:
	return str(mod_paths.get(mod_id, "res://mods/" + mod_id))


static func pow2(n: int) -> int:
	var p := 16
	while p < n:
		p *= 2
	return p


func _tile(spec: Variant, mod_id: String, res := 0) -> int:
	# tekstura z innego moda: "base:textures/dirt.png"
	if spec is String and spec.find(":") > 0 and not spec.begins_with("res:") and not spec.begins_with("user:"):
		var i: int = spec.find(":")
		mod_id = spec.substr(0, i)
		spec = spec.substr(i + 1)
	var cache_key := mod_id + "|" + var_to_str(spec) + "|" + str(res)
	if _tex_index.has(cache_key):
		return _tex_index[cache_key]
	var img := TexGen.load_spec(spec, _mod_path(mod_id))
	var px := texture_res
	if res > 0:
		px = mini(pow2(res), texture_cap)
	elif spec is String and str(spec).begins_with("user://resourcepacks") and img.get_width() > texture_res:
		px = mini(pow2(img.get_width()), texture_cap)   # plik z paczki zasobów większy niż reszta: zostaje ostry
	tile_px.append(px)
	tile_images.append(img)
	_tex_index[cache_key] = tile_images.size() - 1
	return tile_images.size() - 1


## Kafelek dla ściany: 0 +X (east), 1 -X (west), 2 góra, 3 dół, 4 +Z (south), 5 -Z (north).
func _face_spec(tex: Dictionary, face: int) -> Variant:
	var names_by_face := ["east", "west", "top", "bottom", "south", "north"]
	var own: String = names_by_face[face]
	if tex.has(own):
		return tex[own]
	if face != 2 and face != 3 and tex.has("side"):
		return tex["side"]
	return tex.get("all", null)


func _add_block(d: Dictionary, key: String, p: int, liq: int) -> int:
	if keys.size() >= MAX_BLOCKS:
		errors.append("Za dużo bloków (limit %d), pominięto: %s" % [MAX_BLOCKS, key])
		return -1
	var id := keys.size()
	var mod_id := str(d.get("mod", ""))
	keys.append(key)
	names.append(str(d.get("name", key)))
	index[key] = id
	defs.append(d)
	props.append(p)
	liquid.append(liq)
	var emit := clampi(int(d.get("light", 0)), 0, 15)
	lprops.append(emit | (16 if (p & OPAQUE) != 0 else 0) | (32 if liq != 0 else 0))
	var shape := str(d.get("shape", "cube"))
	var hd := float(d.get("hardness", 0.0 if (shape == "cross" or shape == "torch") else 1.0))
	if not bool(d.get("breakable", true)) or liq != 0:
		hd = -1.0  # nie do wykopania
	hardness.append(hd)
	var tex: Dictionary = d.get("textures", {}) if d.get("textures") is Dictionary else {}
	var res := int(d.get("resolution", 0))   # własna rozdzielczość bloku (np. 128)
	for f in 6:
		var spec: Variant = _face_spec(tex, f)
		tiles.append(_tile(spec, mod_id, res) if spec != null else _tile({"pattern": "noise"}, mod_id, res))
	return id


## res: domyślna rozdzielczość kafelków, cap: największa dozwolona (telefon/przeglądarka mniej).
func build(content: Dictionary, paths: Dictionary = {}, res := 16, cap := 512) -> void:
	mod_paths = paths
	texture_cap = maxi(16, pow2(cap))
	texture_res = mini(pow2(maxi(res, 16)), texture_cap)
	_tile({"pattern": "solid", "color": "#00000000"}, "")  # kafelek 0: pusty
	for d in arr(content.get("blocks")):
		if not d is Dictionary:
			continue
		var key := str(d.get("key", ""))
		if key == "" or index.has(key):
			continue
		if d.get("liquid") is Dictionary:
			_add_liquid(d, key)
			continue
		var shape := str(d.get("shape", "cube"))
		var transparent := bool(d.get("transparent", false))
		var p := 0
		if shape == "cross" or shape == "torch":
			p = CROSS if shape == "cross" else THIN
			if bool(d.get("solid", false)):
				p |= SOLID
		elif d.get("boxes") is Array and not (d.boxes as Array).is_empty():
			p = BOXES
			if bool(d.get("solid", true)):
				p |= SOLID
		elif shape == "model" or d.get("model") is Dictionary:
			p = MODEL
			if bool(d.get("solid", true)):
				p |= SOLID
		else:
			if not transparent:
				p |= OPAQUE
			if bool(d.get("solid", true)):
				p |= SOLID
		_add_block(d, key, p, 0)
	for d in arr(content.get("items")):
		if not d is Dictionary or str(d.get("key", "")) == "":
			continue
		var key := str(d.key)
		var block := int(index.get(str(d.get("block", "")), -1)) if d.get("block") is String else -1
		items[key] = {
			"key": key, "name": str(d.get("name", key)), "max_stack": int(d.get("max_stack", 64)),
			"block": block, "mod": str(d.get("mod", "")), "icon": d.get("icon"), "data": d,
		}
		item_keys.append(key)
		if block > 0 and bool(defs[block].get("placeable", true)):
			placeable.append(key)
	worldgen = content.get("worldgen", {}) if content.get("worldgen") is Dictionary else {}
	animations = content.get("animations", {}) if content.get("animations") is Dictionary else {}
	entities = content.get("entities", {}) if content.get("entities") is Dictionary else {}
	sounds = content.get("sounds", {}) if content.get("sounds") is Dictionary else {}
	particles = content.get("particles", {}) if content.get("particles") is Dictionary else {}
	projectiles = content.get("projectiles", {}) if content.get("projectiles") is Dictionary else {}
	effects = content.get("effects", {}) if content.get("effects") is Dictionary else {}
	_build_shapes()
	_build_atlas()


## Ciecz: blok źródłowy (klucz, nieskończony zbiornik z generatora) i 8 poziomów płynącej cieczy
## ("woda~1" .. "woda~8"), które zachowują objętość. Pole liquid w definicji:
## {color, deep, foam, viscosity (co ile kroków symulacji płynie), push (siła prądu), emission}.
func _add_liquid(d: Dictionary, key: String) -> void:
	var ld: Dictionary = d.liquid
	var kind := liquid_kinds.size()
	if kind >= 8:
		errors.append("Za dużo rodzajów cieczy (limit 8): " + key)
		return
	var info := {
		"key": key, "name": str(d.get("name", key)), "levels": [], "source": -1,
		"color": TexGen._col(ld.get("color"), Color(0.16, 0.45, 0.78)),
		"deep": TexGen._col(ld.get("deep"), Color(0.04, 0.16, 0.36)),
		"foam": TexGen._col(ld.get("foam"), Color(0.92, 0.96, 1.0)),
		"viscosity": maxi(1, int(ld.get("viscosity", 1))), "push": float(ld.get("push", 1.0)),
		"emission": float(ld.get("emission", 0.0)), "def": d,
	}
	liquid_kinds.append(info)
	var levels := [0]
	for lv in range(1, LEVELS + 1):
		var vd := d.duplicate()
		vd["item"] = false
		vd["flow_level"] = lv
		levels.append(_add_block(vd, "%s~%d" % [key, lv], LIQUID, kind * 16 + lv))
	info.levels = levels
	info.source = _add_block(d, key, LIQUID, kind * 16 + LEVELS)


## Tablice kształtów dla siatki (C++ i GDScript): prostopadłościany bloku i doklejane przy łączeniu z sąsiadem.
func _build_shapes() -> void:
	shape_index.resize(keys.size() * SHAPE_STRIDE)
	shape_index.fill(0)
	shape_boxes = PackedFloat32Array()
	for id in keys.size():
		if (props[id] & BOXES) == 0:
			continue
		var d: Dictionary = defs[id]
		var si := id * SHAPE_STRIDE
		shape_index[si] = shape_boxes.size() / 6
		shape_index[si + 1] = _add_boxes(d.get("boxes"))
		var con: Variant = d.get("connect")
		if con is Dictionary:
			var g := str(con.get("group", ""))
			if g != "":
				if not _shape_groups.has(g):
					_shape_groups[g] = _shape_groups.size() + 1
				shape_index[si + 2] = _shape_groups[g]
			var dirs := ["north", "east", "south", "west"]
			for k in 4:
				shape_index[si + 3 + k * 2] = shape_boxes.size() / 6
				shape_index[si + 4 + k * 2] = _add_boxes(con.get(dirs[k]))
	if shape_boxes.is_empty():
		shape_boxes.append_array([0, 0, 0, 0, 0, 0])


func _add_boxes(list: Variant) -> int:
	var n := 0
	for bx in arr(list):
		var a := arr(bx)
		if a.size() < 6:
			continue
		for i in 6:
			shape_boxes.append(float(a[i]))
		n += 1
	return n


func liquid_kind(id: int) -> int:
	var v := liquid[id] if id >= 0 and id < liquid.size() else 0
	return -1 if v == 0 else v / 16


func liquid_level(id: int) -> int:
	var v := liquid[id] if id >= 0 and id < liquid.size() else 0
	return v % 16


func is_source(id: int) -> bool:
	var k := liquid_kind(id)
	return k >= 0 and liquid_kinds[k].source == id


func is_liquid(id: int) -> bool:
	return id > 0 and id < liquid.size() and liquid[id] != 0


func def_of(id: int) -> Dictionary:
	return defs[id] if id >= 0 and id < defs.size() else {}


func has_gravity(id: int) -> bool:
	return bool(def_of(id).get("gravity", false))


func loose(id: int) -> Variant:
	var l: Variant = def_of(id).get("loose")
	return l if l is Dictionary else null


func _build_atlas() -> void:
	tile_colors.clear()
	# kafelki do docelowego rozmiaru: powiększanie bez rozmywania (piksele), zmniejszanie płynne
	for i in tile_images.size():
		var img: Image = tile_images[i]
		var px: int = tile_px[i]
		if img.get_width() != px:
			img = img.duplicate()
			img.resize(px, px, Image.INTERPOLATE_NEAREST if img.get_width() < px else Image.INTERPOLATE_LANCZOS)
			tile_images[i] = img
		var sum := Color(0, 0, 0, 0)
		var n := 0
		var step := maxi(1, px / 16)
		for y in range(0, px, step):
			for x in range(0, px, step):
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					sum += c
					n += 1
		tile_colors.append(sum / maxf(1.0, float(n)) if n > 0 else Color(0, 0, 0, 0))
	# pakowanie półkami: od największych, w rzędzie kafelki jednego rozmiaru, położenia wyrównane do rozmiaru
	# (dzięki temu mipmapy jednego kafelka nie mieszają się z sąsiadami)
	var order := range(tile_images.size())
	order.sort_custom(func(a, b): return tile_px[a] > tile_px[b] if tile_px[a] != tile_px[b] else a < b)
	var biggest := 16
	var area := 0
	for i in tile_images.size():
		biggest = maxi(biggest, tile_px[i])
		area += tile_px[i] * tile_px[i]
	var W := maxi(biggest, mini(8192, pow2(ceili(sqrt(float(area))))))
	if texture_res == 16 and biggest == 16:
		W = ATLAS_COLS * 16   # zwykła gra: ten sam atlas co zawsze
	var pos := []
	pos.resize(tile_images.size())
	var x := 0
	var y := 0
	var row_h := 0
	for i in order:
		var px: int = tile_px[i]
		if x + px > W or (row_h != 0 and px != row_h):
			x = 0
			y += row_h
			row_h = 0
		if row_h == 0:
			row_h = px
		pos[i] = Vector2i(x, y)
		x += px
	var H := maxi(16, y + row_h)
	if biggest > 16:
		H = pow2(H)
	var img := Image.create(W, H, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	tile_rects.resize(tile_images.size() * 4)
	var lods := Image.create(maxi(1, W / 16), maxi(1, H / 16), false, Image.FORMAT_R8)
	lods.fill(Color(0, 0, 0))
	max_lod = 0.0
	for i in tile_images.size():
		var px: int = tile_px[i]
		var p: Vector2i = pos[i]
		img.blit_rect(tile_images[i], Rect2i(0, 0, px, px), p)
		tile_rects[i * 4] = float(p.x) / W
		tile_rects[i * 4 + 1] = float(p.y) / H
		tile_rects[i * 4 + 2] = float(px) / W
		tile_rects[i * 4 + 3] = float(px) / H
		var lv := log(float(px) / 16.0) / log(2.0)
		max_lod = maxf(max_lod, lv)
		if lv > 0.0:
			lods.fill_rect(Rect2i(p / 16, Vector2i(px / 16, px / 16)), Color(lv * 32.0 / 255.0, 0, 0))
	atlas_rows = H / 16
	atlas_size = Vector2(W, H)
	if max_lod > 0.0:
		img.generate_mipmaps()
	atlas = ImageTexture.create_from_image(img)
	lod_map = ImageTexture.create_from_image(lods)


## Skrót treści: ten sam zestaw bloków, przedmiotów, stworzeń i opisu świata u klienta i serwera.
func content_hash() -> String:
	var ent := entities.keys()
	ent.sort()
	return var_to_str(_canon([keys, item_keys, ent, worldgen, lprops, props, shape_index, shape_boxes])).sha256_text()


## Postać niezależna od kolejności kluczy w słownikach (tabele Lua mają losową kolejność iteracji).
static func _canon(v: Variant) -> Variant:
	if v is Dictionary:
		var ks: Array = v.keys()
		ks.sort_custom(func(a, b): return str(a) < str(b))
		var out := []
		for k in ks:
			out.append([str(k), _canon(v[k])])
		return out
	if v is Array:
		var out := []
		for x in v:
			out.append(_canon(x))
		return out
	if v is float:
		return snappedf(v, 0.0001)
	return v


# ---------- zapytania ----------

## Stany bloku: wariant domyślny (klucz bloku), stan wariantu i wariant z innym stanem.
func base_of(id: int) -> int:
	var d := def_of(id)
	if d.has("variant_of"):
		return id_of(str(d.variant_of))
	return id


func state_of(id: int) -> Dictionary:
	var st: Variant = def_of(id).get("state")
	return st if st is Dictionary else {}


func with_state(id: int, changes: Dictionary) -> int:
	var base := base_of(id)
	if base <= 0:
		return id
	var bd := def_of(base)
	var states: Variant = bd.get("states")
	if not states is Dictionary:
		return id
	var st := state_of(id).duplicate()
	for k in changes:
		var allowed: Variant = states.get(str(k))
		if not allowed is Array:
			continue
		for v in allowed:
			if _sv(v) == _sv(changes[k]):
				st[str(k)] = v
	var parts := []
	var is_default := true
	for n in bd.get("state_names", []):
		var allowed: Array = states.get(n, [])
		if allowed.is_empty() or _sv(st.get(n)) != _sv(allowed[0]):
			is_default = false
		parts.append("%s=%s" % [n, _sv(st.get(n))])
	if is_default:
		return base
	return int(index.get("%s[%s]" % [keys[base], ",".join(parts)], id))


## Wartość stanu jako tekst, tak jak w Lua (tostring): 2 -> "2", true -> "true".
static func _sv(v: Variant) -> String:
	if v is float and v == floorf(v) and absf(v) < 1e9:
		return str(int(v))
	return str(v)


func id_of(key: String) -> int:
	return int(index.get(key, -1))


func block_name(id: int) -> String:
	return names[id] if id >= 0 and id < names.size() else ""


func block_key(id: int) -> String:
	return keys[id] if id >= 0 and id < keys.size() else ""


func count() -> int:
	return keys.size()


func drops(id: int) -> Array:
	if id <= 0 or id >= defs.size():
		return []
	return arr(defs[id].get("drops")).duplicate(true)


func item_block(item_key: String) -> int:
	return int(items.get(item_key, {}).get("block", -1))


var _effect_icons := {}


func effect_icon(name: String) -> Texture2D:
	if _effect_icons.has(name):
		return _effect_icons[name]
	var d: Dictionary = effects.get(name, {})
	var img: Image
	if d.has("icon"):
		img = TexGen.load_spec(d.icon, _mod_path(str(d.get("mod", ""))))
	else:
		img = TexGen.pattern({"pattern": "gem", "color": str(d.get("color", "#a0a0ff"))})
	var t := ImageTexture.create_from_image(img)
	_effect_icons[name] = t
	return t


## Opis przedmiotu (dymek): nazwa, kategoria, opis, stałe linie z definicji i linie policzone przez mod.
func tooltip(slot: Dictionary) -> String:
	var key := str(slot.get("item", ""))
	if key == "":
		return ""
	var d: Dictionary = items.get(key, {}).get("data", {})
	var lines: Array[String] = [item_name(key)]
	var tt: Variant = d.get("tooltip")
	if tt is Dictionary and str(tt.get("category", "")) != "":
		lines.append("[" + str(tt.category) + "]")
	if str(d.get("description", "")) != "":
		lines.append(str(d.description))
	if tt is Dictionary:
		for l in arr(tt.get("lines")):
			lines.append(str(l))
	for l in arr(slot.get("info")):
		lines.append(str(l))
	return "\n".join(lines)


func item_name(item_key: String) -> String:
	return str(items.get(item_key, {}).get("name", item_key))


func max_stack(item_key: String) -> int:
	return int(items.get(item_key, {}).get("max_stack", 64))


## Ikona przedmiotu: sześcian dla bloków, kafelek dla roślin, dla zwykłych przedmiotów najpierw obrazek,
## który zaraz potem zastępuje mała figura 3D wyrenderowana z modelu przedmiotu (ItemModel, IconRenderer);
## tekstura zmienia się w miejscu, więc sloty, które już ją pokazują, odświeżają się same.
func icon(item_key: String) -> Texture2D:
	if _icons.has(item_key):
		return _icons[item_key]
	var t := ImageTexture.create_from_image(icon_image(item_key))
	_icons[item_key] = t
	if IconRenderer.wants(self, item_key):
		IconRenderer.request(self, item_key, t)
	return t


## Obrazek ikony 2D (z bloku albo z definicji przedmiotu), bez renderowania 3D.
func icon_image(item_key: String) -> Image:
	var it: Dictionary = items.get(item_key, {})
	var img: Image
	var b := int(it.get("block", -1))
	var bicon: Variant = defs[b].get("icon") if b > 0 else null
	if b > 0 and bicon != null:
		img = TexGen.load_spec(bicon, _mod_path(str(defs[b].get("mod", ""))))   # ikona z definicji (np. blok z modelem)
	elif b > 0:
		if props[b] & (CROSS | THIN):
			img = tile_images[tiles[b * 6]]
		elif props[b] & BOXES:
			var bx := Registry.arr(defs[b].get("boxes")).duplicate()
			var con: Variant = defs[b].get("connect")
			if con is Dictionary:   # ogrodzenie i szyba na ikonie: połączone na wprost
				bx.append_array(Registry.arr(con.get("north")))
				bx.append_array(Registry.arr(con.get("south")))
			img = TexGen.boxes_icon(bx, tile_images[tiles[b * 6 + 2]], tile_images[tiles[b * 6 + 0]], tile_images[tiles[b * 6 + 4]])
		else:
			img = TexGen.cube_icon(tile_images[tiles[b * 6 + 2]], tile_images[tiles[b * 6 + 0]], tile_images[tiles[b * 6 + 4]])
	elif it.has("icon") and it.icon != null:
		img = TexGen.load_spec(it.icon, _mod_path(str(it.mod)))
	else:
		img = TexGen.pattern({"pattern": "gem", "color": "#888888"})
	return img


## Tablica przeliczenia id z palety zapisanej w świecie na bieżące id (brakujące bloki stają się powietrzem).
func remap_from(old_keys: Array) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(256)
	var identity := true
	for i in 256:
		var nid := 0
		if i < old_keys.size():
			nid = maxi(0, id_of(str(old_keys[i])))
		lut[i] = nid
		if nid != i and i < old_keys.size():
			identity = false
	return PackedByteArray() if identity else lut
