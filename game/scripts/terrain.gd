class_name Terrain
## Generator świata opisany danymi z modów (WorldgenSpec): biomy dobierane z klimatu (temperatura,
## wilgotność), wysokość mieszana płynnie między biomami, warstwy, rudy, drzewa, struktury i rośliny.
## Wszystkie funkcje są tylko do odczytu, więc można je wywoływać z wątków roboczych.
## UWAGA: ta sama logika jest w native/src/voxel_mesher.cpp. Zmiany trzeba robić w obu miejscach;
## test tests/bench.gd sprawdza, czy oba dają identyczny świat.

const S := 32
const P := S + 2
const BS := WorldgenSpec.BS
const FS := WorldgenSpec.FS
const ORE_S := WorldgenSpec.ORE_S

var seed_value := 1337
var spec := {}
var B := PackedFloat64Array()   # biomy
var F := PackedFloat64Array()   # elementy (drzewa, struktury)
var PL := PackedFloat64Array()  # rośliny
var T := PackedInt32Array()     # bloki struktur
var O := PackedFloat64Array()   # rudy
var nb := 0
var beach := 7
var window := 2
var max_sum := 0.0
var n_ores := 0
var biome_names: Array[String] = []
var biome_keys: Array[String] = []

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var temperature := FastNoiseLite.new()
var humidity := FastNoiseLite.new()
var mountain := FastNoiseLite.new()


func _init(seed_in: int = 1337, compiled: Dictionary = {}) -> void:
	seed_value = seed_in
	spec = compiled
	if spec.is_empty():
		spec = WorldgenSpec.compile({}, Blocks.reg, seed_in)
	B = spec.biomes
	F = spec.features
	PL = spec.plants
	T = spec.templates
	O = spec.ores
	var prm: PackedFloat64Array = spec.params
	beach = int(prm[1])
	window = int(prm[2])
	nb = int(prm[3])
	max_sum = prm[4]
	n_ores = int(prm[5])
	biome_names = spec.names
	biome_keys = spec.keys
	var bs := float(spec.get("biome_scale", 1.0))
	_noise(hills, seed_value, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.008, 3)
	_noise(detail, seed_value + 7, FastNoiseLite.TYPE_SIMPLEX, 0.04, 1)
	_noise(temperature, seed_value + 101, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0022 / bs, 2)
	_noise(humidity, seed_value + 202, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.0028 / bs, 2)
	_noise(mountain, seed_value + 303, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.012, 3)


static func _noise(n: FastNoiseLite, s: int, type: int, freq: float, octaves: int) -> void:
	n.seed = s
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves


## Najwyższy pionowy chunk, który może zawierać bloki (z zapasem na drzewa).
func max_chunk_y() -> int:
	return int(floor((float(spec.get("max_height", 60.0)) + 14.0) / S))


## Dane dla rdzenia w C++ (VoxelMesher.configure).
func native_noises() -> Array:
	return [hills, detail, temperature, humidity, mountain]


static func sm(a: float, b: float, x: float) -> float:
	var t := clampf((x - a) / (b - a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


static func hash01(x: int, z: int, s: int, salt: int) -> float:
	var h := (x * 374761393 + z * 668265263 + s * 1274126177 + salt * 2246822519) & 0xFFFFFFFF
	h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
	h = h ^ (h >> 16)
	return float(h) / 4294967296.0


static func hash3(x: int, y: int, z: int, s: int, salt: int) -> float:
	return hash01(x, z, s, salt + y * 31)


## Wysokość i biom kolumny: Vector2i(h, indeks biomu).
## Biom to najbliższy punkt klimatu; parametry wysokości są średnią ważoną 1/d^4 wszystkich biomów,
## dzięki czemu granice biomów są płynne.
func column(x: int, z: int) -> Vector2i:
	var temp := temperature.get_noise_2d(x, z)
	var humid := humidity.get_noise_2d(x, z)
	var best := 0
	var bestd := 1e30
	var wsum := 0.0
	var base := 0.0
	var amp := 0.0
	var rough := 0.0
	var mount := 0.0
	for i in nb:
		var o := i * BS
		var dt := temp - B[o]
		var dh := humid - B[o + 1]
		var d := dt * dt + dh * dh
		if d < bestd:
			bestd = d
			best = i
		var w := 1.0 / (d * d + 0.000001)
		wsum += w
		base += w * B[o + 2]
		amp += w * B[o + 3]
		rough += w * B[o + 4]
		mount += w * B[o + 5]
	base /= wsum
	amp /= wsum
	rough /= wsum
	mount /= wsum
	var h := base + hills.get_noise_2d(x, z) * amp + detail.get_noise_2d(x, z) * rough \
		+ mount * (mountain.get_noise_2d(x, z) * 0.5 + 0.5)
	return Vector2i(int(round(h)), best)


func height(x: int, z: int) -> int:
	return column(x, z).x


func biome_name(i: int) -> String:
	return biome_names[i] if i >= 0 and i < biome_names.size() else ""


func block_for(wy: int, h: int, biome: int) -> int:
	if wy > h:
		return Blocks.AIR
	var o := biome * BS
	var top := int(B[o + 6])
	var filler := int(B[o + 7])
	if h >= B[o + 12]:
		top = int(B[o + 13])
		filler = int(B[o + 14])
	elif h <= beach and B[o + 10] >= 0.0:
		top = int(B[o + 10])
		filler = int(B[o + 11])
	if wy == h:
		return top
	if wy >= h - int(B[o + 8]):
		return filler
	return int(B[o + 9])


## Element (drzewo, struktura) w kolumnie: indeks w F albo -1.
func feature_at(x: int, z: int, h: int, biome: int) -> int:
	var r := hash01(x, z, seed_value, 1)
	if r >= max_sum:
		return -1
	var o := biome * BS
	var start := int(B[o + 15])
	var n := int(B[o + 16])
	var acc := 0.0
	for k in n:
		var f := (start + k) * FS
		acc += F[f]
		if r < acc:
			if h >= F[f + 9] and h <= F[f + 10]:
				return start + k
			return -1
	return -1


func plant_at(x: int, z: int, h: int, biome: int) -> int:
	if h <= beach:
		return 0
	var o := biome * BS
	var start := int(B[o + 17])
	var n := int(B[o + 18])
	if n == 0:
		return 0
	var r := hash01(x, z, seed_value, 2)
	var acc := 0.0
	for k in n:
		acc += PL[(start + k) * 2]
		if r < acc:
			return int(PL[(start + k) * 2 + 1])
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
			if py >= 0 and py < P and feature_at(bx + x, bz + z, h, c.y) < 0:
				var pl := plant_at(bx + x, bz + z, h, c.y)
				if pl != 0:
					out[x + P * (py + P * z)] = pl
	_ores(out, bx, by, bz)
	# drzewa i struktury z okna szerszego o promień największego elementu
	var found := []
	if max_sum > 0.0:
		for wz in range(bz - window, bz + P + window):
			for wx in range(bx - window, bx + P + window):
				if hash01(wx, wz, seed_value, 1) >= max_sum:
					continue
				var c: Vector2i = cols.get(Vector2i(wx, wz), Vector2i(-99999, 0))
				if c.x == -99999:
					c = column(wx, wz)
				var f := feature_at(wx, wz, c.x, c.y)
				if f >= 0:
					found.append([wx, wz, c.x, f, hash01(wx, wz, seed_value, 3)])
	# najpierw pnie i bloki stałe, potem liście (tylko w powietrze): wynik nie zależy od kolejności
	for t in found:
		_stamp(out, t, bx, by, bz, false)
	for t in found:
		_stamp(out, t, bx, by, bz, true)
	return out


func _trunk(f: int, hv: float) -> int:
	var hmin := int(F[f + 4])
	var hmax := int(F[f + 5])
	return hmin + int(hv * float(hmax - hmin + 1))


func _stamp(out: PackedByteArray, t: Array, bx: int, by: int, bz: int, soft: bool) -> void:
	var f: int = t[3] * FS
	var kind := int(F[f + 1])
	var x0: int = t[0]
	var z0: int = t[1]
	var h: int = t[2]
	if kind == 3:
		var s := int(F[f + 7])
		var n := int(F[f + 8])
		for k in n:
			var e := (s + k) * 5
			if (T[e + 4] == 1) != soft:
				continue
			_put(out, x0 + T[e] - bx, h + 1 + T[e + 1] - by, z0 + T[e + 2] - bz, T[e + 3], soft)
		return
	var th := _trunk(f, t[4])
	if not soft:
		var trunk := int(F[f + 2])
		for k in range(1, th + 1):
			_put(out, x0 - bx, h + k - by, z0 - bz, trunk, false)
		return
	var leaves := int(F[f + 3])
	var rad := int(F[f + 6])
	var tp := h + th
	if kind == 0:
		for dy in range(-2, 2):
			var r := rad if dy <= -1 else rad - 1
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if r >= 2 and absi(dx) == r and absi(dz) == r:
						continue
					if dy == 1 and absi(dx) + absi(dz) > 1:
						continue
					_put(out, x0 + dx - bx, tp + dy - by, z0 + dz - bz, leaves, true)
	elif kind == 1:
		for y in range(tp + 1, h + 2, -1):
			var d := tp + 1 - y
			var r := 0 if d == 0 else (1 if d % 2 == 1 else rad)
			for dz in range(-r, r + 1):
				for dx in range(-r, r + 1):
					if r >= 2 and absi(dx) == r and absi(dz) == r:
						continue
					_put(out, x0 + dx - bx, y - by, z0 + dz - bz, leaves, true)


## Rudy: w każdej komórce 16^3 może powstać jedna żyła (kula o promieniu 1..rozmiar).
func _ores(out: PackedByteArray, bx: int, by: int, bz: int) -> void:
	for i in n_ores:
		var o := i * ORE_S
		var blk := int(O[o])
		var rep := int(O[o + 1])
		var size := int(O[o + 5])
		var salt := 1000 + i * 7
		for cz in range(floori((bz - size) / 16.0), floori((bz + P - 1 + size) / 16.0) + 1):
			for cy in range(floori((by - size) / 16.0), floori((by + P - 1 + size) / 16.0) + 1):
				for cx in range(floori((bx - size) / 16.0), floori((bx + P - 1 + size) / 16.0) + 1):
					if hash3(cx, cy, cz, seed_value, salt) >= O[o + 4]:
						continue
					var ox := cx * 16 + int(hash3(cx, cy, cz, seed_value, salt + 1) * 16.0)
					var oy := cy * 16 + int(hash3(cx, cy, cz, seed_value, salt + 2) * 16.0)
					var oz := cz * 16 + int(hash3(cx, cy, cz, seed_value, salt + 3) * 16.0)
					if oy < O[o + 2] or oy > O[o + 3]:
						continue
					var r := 1 + int(hash3(cx, cy, cz, seed_value, salt + 4) * float(size))
					for dz in range(-r, r + 1):
						for dy in range(-r, r + 1):
							for dx in range(-r, r + 1):
								if dx * dx + dy * dy + dz * dz > r * r:
									continue
								var lx := ox + dx - bx
								var ly := oy + dy - by
								var lz := oz + dz - bz
								if lx < 0 or ly < 0 or lz < 0 or lx >= P or ly >= P or lz >= P:
									continue
								var idx := lx + P * (ly + P * lz)
								if out[idx] == rep:
									out[idx] = blk


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
