class_name Registry
extends RefCounted
## Rejestr treści zbudowany z danych zarejestrowanych przez mody w fazie content.lua:
## bloki (id, właściwości, kafelki atlasu), przedmioty z ikonami, dane generatora świata i animacje.
## Id bloków nadawane są w kolejności rejestracji; świat zapisuje paletę kluczy i przelicza id przy wczytaniu.

const OPAQUE := 1
const CROSS := 2
const SOLID := 4
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
var atlas: ImageTexture
var atlas_rows := 1

var items := {}                    # klucz -> {key, name, max_stack, block, mod, icon, data}
var item_keys: Array[String] = []
var placeable: Array[String] = []  # przedmioty-bloki do stawiania (tryb kreatywny)
var worldgen := {}
var animations := {}
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


func build(content: Dictionary, paths: Dictionary = {}) -> void:
	mod_paths = paths
	_tile({"pattern": "solid", "color": "#00000000"}, "")  # kafelek 0: pusty
	for d in arr(content.get("blocks")):
		if not d is Dictionary:
			continue
		var key := str(d.get("key", ""))
		if key == "" or index.has(key):
			continue
		if keys.size() >= MAX_BLOCKS:
			errors.append("Za dużo bloków (limit %d), pominięto: %s" % [MAX_BLOCKS, key])
			continue
		var id := keys.size()
		var mod_id := str(d.get("mod", ""))
		keys.append(key)
		names.append(str(d.get("name", key)))
		index[key] = id
		defs.append(d)
		var shape := str(d.get("shape", "cube"))
		var transparent := bool(d.get("transparent", false))
		var p := 0
		if shape == "cross":
			p = CROSS
			if bool(d.get("solid", false)):
				p |= SOLID
		else:
			if not transparent:
				p |= OPAQUE
			if bool(d.get("solid", true)):
				p |= SOLID
		props.append(p)
		var tex: Dictionary = d.get("textures", {}) if d.get("textures") is Dictionary else {}
		for f in 6:
			var spec: Variant = _face_spec(tex, f)
			tiles.append(_tile(spec, mod_id) if spec != null else _tile({"pattern": "noise"}, mod_id))
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
	_build_atlas()


func _build_atlas() -> void:
	atlas_rows = maxi(1, ceili(tile_images.size() / float(ATLAS_COLS)))
	var img := Image.create(ATLAS_COLS * PX, atlas_rows * PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for i in tile_images.size():
		img.blit_rect(tile_images[i], Rect2i(0, 0, PX, PX), Vector2i((i % ATLAS_COLS) * PX, (i / ATLAS_COLS) * PX))
	atlas = ImageTexture.create_from_image(img)


# ---------- zapytania ----------

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
	if b > 0:
		if props[b] & CROSS:
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
