class_name WorldgenSpec
## Zamienia opis świata z modów (biomy, drzewa, struktury, rośliny, rudy) na płaskie tablice liczb,
## które czytają oba generatory: Terrain (GDScript) i VoxelMesher (C++).
##
## Biom (BS liczb): temp, wilgotność, wysokość, wzgórza, chropowatość, góry, góra, wypełnienie, głębokość,
##   skała, plaża-góra, plaża-wypełnienie, szczyt-wysokość, szczyt-góra, szczyt-wypełnienie,
##   początek i liczba elementów, początek i liczba roślin.
## Element (FS): szansa, rodzaj (0 dąb, 1 świerk, 2 kolumna, 3 struktura), pień, liście, wys. min, wys. max,
##   promień, początek i liczba bloków struktury, min. i max. wysokość terenu.
## Struktura: po 5 liczb całkowitych na blok: dx, dy, dz, blok, tylko_w_powietrze.
## Ruda (ORE_S): blok, zastępowany blok, min y, max y, szansa na komórkę 16^3, rozmiar.

const BS := 19
const FS := 11
const ORE_S := 6
const SHAPES := {"oak": 0, "spruce": 1, "column": 2}
const MAX_WINDOW := 8


static func _num(d: Dictionary, k: String, def: float) -> float:
	var v: Variant = d.get(k, def)
	return float(v) if (v is float or v is int) else def


static func _block(reg: Registry, v: Variant, def: int, errors: Array) -> int:
	if v == null:
		return def
	var id := reg.id_of(str(v))
	if id < 0:
		errors.append("nieznany blok w generatorze świata: " + str(v))
		return def
	return id


static func compile(raw: Dictionary, reg: Registry, seed_value: int) -> Dictionary:
	var errors: Array = []
	var cfg: Dictionary = raw.get("config", {}) if raw.get("config") is Dictionary else {}
	var beach := int(_num(cfg, "beach_height", 7))
	var biomes := PackedFloat64Array()
	var features := PackedFloat64Array()
	var plants := PackedFloat64Array()
	var templates := PackedInt32Array()
	var ores := PackedFloat64Array()
	var names: Array[String] = []
	var bkeys: Array[String] = []
	var window := 0
	var max_sum := 0.0
	var structures: Dictionary = raw.get("structures", {}) if raw.get("structures") is Dictionary else {}
	var stone := reg.id_of("stone")
	for b in Registry.arr(raw.get("biomes")):
		if not b is Dictionary:
			continue
		names.append(str(b.get("name", b.get("key", "?"))))
		bkeys.append(str(b.get("key", "")))
		var beach_d: Dictionary = b.get("beach") if b.get("beach") is Dictionary else {}
		var peak_d: Dictionary = b.get("peak") if b.get("peak") is Dictionary else {}
		var top := _block(reg, b.get("top"), maxi(stone, 0), errors)
		var filler := _block(reg, b.get("filler"), top, errors)
		var rock := _block(reg, b.get("stone"), maxi(stone, 0), errors)
		var feat_start := features.size() / FS
		var sum := 0.0
		for f in Registry.arr(b.get("features")):
			if not f is Dictionary:
				continue
			var kind := -1
			var tpl_start := templates.size() / 5
			var tpl_count := 0
			var radius := int(_num(f, "radius", 2))
			if f.has("structure"):
				var s: Variant = structures.get(str(f.structure))
				if not s is Dictionary:
					errors.append("nieznana struktura: " + str(f.structure))
					continue
				kind = 3
				var only_air := 1 if bool(s.get("only_air", false)) else 0
				radius = 0
				for blk in Registry.arr(s.get("blocks")):
					var e: Array = Registry.arr(blk)
					if e.size() < 4:
						continue
					templates.append_array([int(e[0]), int(e[1]), int(e[2]), _block(reg, e[3], 0, errors) if str(e[3]) != "air" else 0, only_air])
					tpl_count += 1
					radius = maxi(radius, maxi(absi(int(e[0])), absi(int(e[2]))))
			else:
				kind = int(SHAPES.get(str(f.get("shape", "oak")), -1))
				if kind < 0:
					errors.append("nieznany kształt drzewa: " + str(f.get("shape")))
					continue
				if kind == 2:
					radius = 0
			var hr: Array = Registry.arr(f.get("height"))
			var hmin := int(hr[0]) if hr.size() > 0 else 4
			var hmax := int(hr[1]) if hr.size() > 1 else hmin
			var chance := _num(f, "chance", 0.0)
			sum += chance
			window = maxi(window, radius)
			features.append_array([chance, kind, _block(reg, f.get("trunk"), maxi(reg.id_of("log"), 0), errors),
				_block(reg, f.get("leaves"), maxi(reg.id_of("leaves"), 0), errors), hmin, hmax, radius,
				tpl_start, tpl_count, _num(f, "min_height", beach + 1), _num(f, "max_height", 100000)])
		max_sum = maxf(max_sum, sum)
		var plant_start := plants.size() / 2
		for p in Registry.arr(b.get("plants")):
			if p is Dictionary:
				plants.append_array([_num(p, "chance", 0.0), _block(reg, p.get("block"), 0, errors)])
		biomes.append_array([
			_num(b, "temperature", 0.0), _num(b, "humidity", 0.0), _num(b, "height", 12.0), _num(b, "hills", 9.0),
			_num(b, "roughness", 1.5), _num(b, "mountains", 0.0), top, filler, _num(b, "depth", 3.0), rock,
			_block(reg, beach_d.get("top"), -1, errors) if not beach_d.is_empty() else -1.0,
			_block(reg, beach_d.get("filler", beach_d.get("top")), -1, errors) if not beach_d.is_empty() else -1.0,
			_num(peak_d, "height", 1e9) if not peak_d.is_empty() else 1e9,
			_block(reg, peak_d.get("top"), top, errors) if not peak_d.is_empty() else top,
			_block(reg, peak_d.get("filler"), rock, errors) if not peak_d.is_empty() else filler,
			feat_start, features.size() / FS - feat_start, plant_start, plants.size() / 2 - plant_start])
	for o in Registry.arr(raw.get("ores")):
		if not o is Dictionary:
			continue
		ores.append_array([_block(reg, o.get("block"), 0, errors), _block(reg, o.get("replace", "stone"), maxi(stone, 0), errors),
			_num(o, "min_y", -1000), _num(o, "max_y", 1000), _num(o, "chance", 0.5), clampf(_num(o, "size", 2), 1, 6)])
	if names.is_empty():
		# bez biomów świat jest płaski z jednego bloku (np. gdy wyłączono mod base)
		names.append("Pustka")
		bkeys.append("void")
		biomes.append_array([0, 0, 0, 0, 0, 0, maxi(stone, 0), maxi(stone, 0), 3, maxi(stone, 0), -1, -1, 1e9, 0, 0, 0, 0, 0, 0])
	return {
		"biomes": biomes, "features": features, "plants": plants, "templates": templates, "ores": ores,
		"params": PackedFloat64Array([seed_value, beach, mini(window, MAX_WINDOW), names.size(), max_sum, ores.size() / ORE_S]),
		"biome_scale": _num(cfg, "biome_scale", 1.0), "names": names, "keys": bkeys, "errors": errors,
		"max_height": _max_height(biomes, names.size()),
	}


## Najwyższy możliwy teren (do wyliczenia, ile pionowych chunków generować).
static func _max_height(biomes: PackedFloat64Array, n: int) -> float:
	var m := 0.0
	for i in n:
		var o := i * BS
		m = maxf(m, biomes[o + 2] + absf(biomes[o + 3]) + absf(biomes[o + 4]) + absf(biomes[o + 5]))
	return m
