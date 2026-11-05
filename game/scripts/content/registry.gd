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
var tile_colors: Array[Color] = []   # średni kolor kafelka (dalekie widoki, cząsteczki)
var atlas: ImageTexture
var atlas_rows := 1

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


func _tile(spec: Variant, mod_id: String) -> int:
	# tekstura z innego moda: "base:textures/dirt.png"
	if spec is String and spec.find(":") > 0 and not spec.begins_with("res:") and not spec.begins_with("user:"):
		var i: int = spec.find(":")
		mod_id = spec.substr(0, i)
		spec = spec.substr(i + 1)
	var cache_key := mod_id + "|" + var_to_str(spec)
	if _tex_index.has(cache_key):
		return _tex_index[cache_key]
	var img := TexGen.load_spec(spec, _mod_path(mod_id))
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
	for f in 6:
		var spec: Variant = _face_spec(tex, f)
		tiles.append(_tile(spec, mod_id) if spec != null else _tile({"pattern": "noise"}, mod_id))
	return id


func build(content: Dictionary, paths: Dictionary = {}) -> void:
	mod_paths = paths
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
	for img in tile_images:
		var sum := Color(0, 0, 0, 0)
		var n := 0
		for y in PX:
			for x in PX:
				var c := img.get_pixel(x, y)
				if c.a > 0.5:
					sum += c
					n += 1
		tile_colors.append(sum / maxf(1.0, float(n)) if n > 0 else Color(0, 0, 0, 0))
	atlas_rows = maxi(1, ceili(tile_images.size() / float(ATLAS_COLS)))
	var img := Image.create(ATLAS_COLS * PX, atlas_rows * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in tile_images.size():
		img.blit_rect(tile_images[i], Rect2i(0, 0, PX, PX), Vector2i((i % ATLAS_COLS) * PX, (i / ATLAS_COLS) * PX))
	atlas = ImageTexture.create_from_image(img)


## Skrót treści: ten sam zestaw bloków, przedmiotów, stworzeń i opisu świata u klienta i serwera.
func content_hash() -> String:
	var ent := entities.keys()
	ent.sort()
	return var_to_str(_canon([keys, item_keys, ent, worldgen, lprops, props])).sha256_text()


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


## Ikona przedmiotu: sześcian dla bloków, kafelek dla roślin, obrazek dla zwykłych przedmiotów.
func icon(item_key: String) -> Texture2D:
	if _icons.has(item_key):
		return _icons[item_key]
	var it: Dictionary = items.get(item_key, {})
	var img: Image
	var b := int(it.get("block", -1))
	var bicon: Variant = defs[b].get("icon") if b > 0 else null
	if b > 0 and bicon != null:
		img = TexGen.load_spec(bicon, _mod_path(str(defs[b].get("mod", ""))))   # ikona z definicji (np. blok z modelem)
	elif b > 0:
		if props[b] & (CROSS | THIN):
			img = tile_images[tiles[b * 6]]
		else:
			img = TexGen.cube_icon(tile_images[tiles[b * 6 + 2]], tile_images[tiles[b * 6 + 0]], tile_images[tiles[b * 6 + 4]])
	elif it.has("icon") and it.icon != null:
		img = TexGen.load_spec(it.icon, _mod_path(str(it.mod)))
	else:
		img = TexGen.pattern({"pattern": "gem", "color": "#888888"})
	var t := ImageTexture.create_from_image(img)
	_icons[item_key] = t
	return t


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
