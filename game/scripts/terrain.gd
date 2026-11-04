class_name Terrain
## Łagodny teren: wzgórza w górę i w dół, trawa na wierzchu, ziemia, kamień, piasek w dolinach.
## Wszystkie funkcje są tylko do odczytu, więc można je wywoływać z wątków roboczych.

const S := 32
const P := S + 2  # chunk z obwódką jednej warstwy sąsiadów

var hills := FastNoiseLite.new()
var detail := FastNoiseLite.new()


func _init(seed_value: int = 1337) -> void:
	hills.seed = seed_value
	hills.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	hills.frequency = 0.008
	hills.fractal_octaves = 3
	detail.seed = seed_value + 7
	detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	detail.frequency = 0.04
	detail.fractal_octaves = 1


func height(x: int, z: int) -> int:
	return int(round(12.0 + hills.get_noise_2d(x, z) * 9.0 + detail.get_noise_2d(x, z) * 1.5))


static func block_for(wy: int, h: int) -> int:
	if wy > h:
		return Blocks.AIR
	var sandy := h <= 7
	if wy == h:
		return Blocks.SAND if sandy else Blocks.GRASS
	if wy > h - 4:
		return Blocks.SAND if sandy else Blocks.DIRT
	return Blocks.STONE


## Tablica (S+2)^3 dla chunka cpos razem z jedną warstwą sąsiadów. Indeks: x + P*(y + P*z).
func fill_padded(cpos: Vector3i) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(P * P * P)
	var bx := cpos.x * S - 1
	var by := cpos.y * S - 1
	var bz := cpos.z * S - 1
	for z in P:
		for x in P:
			var h := height(bx + x, bz + z)
			var top := h - by  # lokalne y wierzchu
			if top < 0:
				continue
			for y in mini(top + 1, P):
				out[x + P * (y + P * z)] = block_for(by + y, h)
	return out


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
