class_name Terrain
## Generator świata: biomy (łąki, las, pustynia, ośnieżone góry), drzewa, kaktusy, trawa i kwiaty.
## Wszystkie funkcje są tylko do odczytu, więc można je wywoływać z wątków roboczych.
## UWAGA: ta sama logika jest w native/src/voxel_mesher.cpp (prepare). Zmiany trzeba robić w obu miejscach;
## test tests/bench.gd sprawdza, czy oba dają identyczny świat.

const S := 32
const P := S + 2

const MEADOW := 0
const FOREST := 1
const DESERT := 2
const SNOWY := 3
const BIOME_NAMES := ["Łąki", "Las", "Pustynia", "Ośnieżone góry"]

var seed_value := 1337
var hill := 1.0
var biome_size := 1.0
var trees := true
var density := 1.0
var plants := true

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var temperature := FastNoiseLite.new()
var humidity := FastNoiseLite.new()
var mountain := FastNoiseLite.new()


func _init(seed_in: int = 1337, opts: Dictionary = {}) -> void:
	seed_value = seed_in
	hill = float(opts.get("hill_height", 1.0))
	biome_size = float(opts.get("biome_size", 1.0))
	trees = bool(opts.get("trees", true))
	density = float(opts.get("tree_density", 1.0))
	plants = bool(opts.get("plants", true))
	_noise(hills, seed_value, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.008, 3)
	_noise(detail, seed_value + 7, FastNoiseLite.TYPE_SIMPLEX, 0.04, 1)
	_noise(temperature, seed_value + 101, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0022 / biome_size, 2)
	_noise(humidity, seed_value + 202, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0028 / biome_size, 2)
	_noise(mountain, seed_value + 303, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 3)


static func _noise(n: FastNoiseLite, s: int, type: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves


## Najwyższy pionowy chunk, który może zawierać bloki (z zapasem na drzewa).
func max_chunk_y() -> int:
	return int(floor((13.5 + 39.0 * hill + 10.0) / S))


## Szumy i parametry przekazywane do rdzenia w C++.
func native_noises() -> Array:
	return [hills, detail, temperature, humidity, mountain]


func native_params() -> PackedFloat64Array:
	return PackedFloat64Array([seed_value, hill, 1.0 if trees else 0.0, density, 1.0 if plants else 0.0])


static func sm(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func hash01(x: int, z: int, s: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + s * 1274126177 + salt * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0


static func biome_of(temp: float, humid: float) -> int:
	if temp > 0.3:
		return DESERT
	if temp < -0.3:
		return SNOWY
	if humid > 0.1:
		return FOREST
	return MEADOW


## Wysokość i biom kolumny: [h, biom].
func column(x: int, z: int) -> Vector2i:
	var temp := temperature.get_noise_2d(x, z)
	var humid := humidity.get_noise_2d(x, z)
	var desert_f := sm(0.15, 0.45, temp)
	var cold_f := sm(-0.15, -0.45, temp)
	var amp := 9.0 * hill * (1.0 - 0.6 * desert_f)
	var h := 12.0 + hills.get_noise_2d(x, z) * amp + detail.get_noise_2d(x, z) * 1.5 \
		+ cold_f * (mountain.get_noise_2d(x, z) * 0.5 + 0.5) * 30.0 * hill
	return Vector2i(int(round(h)), biome_of(temp, humid))


func height(x: int, z: int) -> int:
	return column(x, z).x


static func block_for(wy: int, h: int, biome: int) -> int:
	if wy > h:
		return Blocks.AIR
	if biome == DESERT:
		return Blocks.SAND if wy > h - 4 else Blocks.STONE
	if biome == SNOWY:
		if h >= 34:
			return Blocks.SNOW if wy == h else Blocks.STONE
		if wy == h:
			return Blocks.SNOW
		return Blocks.DIRT if wy > h - 4 else Blocks.STONE
	if h <= 7:
		return Blocks.SAND if wy > h - 4 else Blocks.STONE
	if wy == h:
		return Blocks.GRASS
	return Blocks.DIRT if wy > h - 4 else Blocks.STONE


## Rodzaj drzewa w kolumnie: 0 brak, 1 dąb, 2 świerk, 3 kaktus.
func tree_at(x: int, z: int, h: int, biome: int) -> int:
	if not trees or h <= 7:
		return 0
	var r := hash01(x, z, seed_value, 1)
	if r >= 0.03 * density:
		return 0
	match biome:
		FOREST:
			return 1
		MEADOW:
			return 1 if r < 0.004 * density else 0
		SNOWY:
			return 2 if (r < 0.012 * density and h < 34) else 0
		DESERT:
			return 3 if r < 0.006 * density else 0
	return 0


func plant_at(x: int, z: int, h: int, biome: int) -> int:
	if not plants or h <= 7 or (biome != MEADOW and biome != FOREST):
		return 0
	var r := hash01(x, z, seed_value, 2)
	if biome == MEADOW:
		if r < 0.10: return Blocks.TALL_GRASS
		if r < 0.125: return Blocks.FLOWER_RED
		if r < 0.15: return Blocks.FLOWER_YELLOW
	else:
		if r < 0.18: return Blocks.TALL_GRASS
		if r < 0.19: return Blocks.FLOWER_RED
	return 0


## Tablica (S+2)^3 dla chunka cpos razem z jedną warstwą sąsiadów. Indeks: x + P*(y + P*z).
func fill_padded(cpos: Vector3i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(P * P * P)
	var bx := cpos.x * S - 1
	var by := cpos.y * S - 1
	var bz := cpos.z * S - 1
	var cols := {}
	for z in P:
		for x in P:
			var c := column(bx + x, bz + z)
			cols[Vector2i(bx + x, bz + z)] = c
			var h := c.x
			var top := h - by
			if top >= 0:
				for y in mini(top + 1, P):
					out[x + P * (y + P * z)] = block_for(by + y, h, c.y)
			# roślina na wierzchu
			var py := h + 1 - by
			if py >= 0 and py < P and tree_at(bx + x, bz + z, h, c.y) == 0:
				var pl := plant_at(bx + x, bz + z, h, c.y)
				if pl != 0:
					out[x + P * (py + P * z)] = pl
	# drzewa z okna o 2 kolumny szerszego, żeby korony sąsiadów sięgały do chunka
	var found := []
	for wz in range(bz - 2, bz + P + 2):
		for wx in range(bx - 2, bx + P + 2):
			if hash01(wx, wz, seed_value, 1) >= 0.03 * density or not trees:
				continue
			var c: Vector2i = cols.get(Vector2i(wx, wz), Vector2i(-99999, 0))
			if c.x == -99999:
				c = column(wx, wz)
			var kind := tree_at(wx, wz, c.x, c.y)
			if kind != 0:
				found.append([wx, wz, c.x, kind, hash01(wx, wz, seed_value, 3)])
	# najpierw pnie, potem liście (tylko w powietrze), więc wynik nie zależy od kolejności
	for t in found:
		var th := _trunk_height(t[3], t[4])
		var blk := Blocks.CACTUS if t[3] == 3 else Blocks.LOG
		for k in range(1, th + 1):
			_put(out, t[0] - bx, t[2] + k - by, t[1] - bz, blk, false)
	for t in found:
		if t[3] == 3:
			continue
		var th := _trunk_height(t[3], t[4])
		var tp: int = t[2] + th
		if t[3] == 1:
			for dy in range(-2, 2):
				var r := 2 if dy <= -1 else 1
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if r == 2 and absi(dx) == 2 and absi(dz) == 2:
							continue
						if dy == 1 and absi(dx) + absi(dz) > 1:
							continue
						_put(out, t[0] + dx - bx, tp + dy - by, t[1] + dz - bz, Blocks.LEAVES, true)
		else:
			for y in range(tp + 1, t[2] + 2, -1):
				var d := tp + 1 - y
				var r := 0 if d == 0 else (1 if d % 2 == 1 else 2)
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						if r == 2 and absi(dx) == 2 and absi(dz) == 2:
							continue
						_put(out, t[0] + dx - bx, y - by, t[1] + dz - bz, Blocks.LEAVES, true)
	return out


static func _trunk_height(kind: int, hv: float) -> int:
	if kind == 1:
		return 4 + int(hv * 3.0)
	if kind == 2:
		return 6 + int(hv * 3.0)
	return 2 + int(hv * 2.0)


static func _put(out: PackedByteArray, x: int, y: int, z: int, b: int, only_air: bool) -> void:
	if x < 0 or y < 0 or z < 0 or x >= P or y >= P or z >= P:
		return
	var i := x + P * (y + P * z)
	if only_air and out[i] != Blocks.AIR:
		return
	out[i] = b


static func interior(padded: PackedByteArray) -> PackedByteArray:
	var d := PackedByteArray()
	d.resize(S * S * S)
	for z in S:
		for y in S:
			var src := 1 + P * ((y + 1) + P * (z + 1))
			var dst := S * (y + S * z)
			for x in S:
				d[dst + x] = padded[src + x]
	return d


## Nakłada dane chunka (z edycjami gracza) na wnętrze tablicy z obwódką.
static func write_interior(padded: PackedByteArray, data: PackedByteArray) -> void:
	for z in S:
		for y in S:
			var dst := 1 + P * ((y + 1) + P * (z + 1))
			var src := S * (y + S * z)
			for x in S:
				padded[dst + x] = data[src + x]
