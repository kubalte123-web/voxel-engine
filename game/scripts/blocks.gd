class_name Blocks
## Definicje bloków, ich właściwości i generowany w kodzie atlas tekstur (16x16 pikseli na kafelek).

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const PLANKS := 4
const SAND := 5
const LOG := 6
const LEAVES := 7
const SNOW := 8
const CACTUS := 9
const TALL_GRASS := 10
const FLOWER_RED := 11
const FLOWER_YELLOW := 12
const COUNT := 13

const NAMES := ["Powietrze", "Trawa", "Ziemia", "Kamień", "Deski", "Piasek", "Pień", "Liście",
	"Śnieg", "Kaktus", "Wysoka trawa", "Mak", "Mlecz"]
# Stałe identyfikatory tekstowe (używane przez mody i ustawienia)
const KEYS := ["air", "grass", "dirt", "stone", "planks", "sand", "log", "leaves",
	"snow", "cactus", "tall_grass", "flower_red", "flower_yellow"]
const PLACEABLE := [GRASS, DIRT, STONE, PLANKS, SAND, LOG, LEAVES, SNOW]

# Właściwości (bity): 1 = nieprzezroczysty, 2 = roślina (dwie skrzyżowane ściany), 4 = kolizja
const OPAQUE := 1
const CROSS := 2
const SOLID := 4

# Kafelki w atlasie
const T_GRASS_TOP := 0
const T_GRASS_SIDE := 1
const T_DIRT := 2
const T_STONE := 3
const T_PLANKS := 4
const T_SAND := 5
const T_LOG_SIDE := 6
const T_LOG_TOP := 7
const T_LEAVES := 8
const T_SNOW := 9
const T_CACTUS_SIDE := 10
const T_CACTUS_TOP := 11
const T_TALL_GRASS := 12
const T_FLOWER_RED := 13
const T_FLOWER_YELLOW := 14
const TILES := 15
const TILE_PX := 16


static func props(block: int) -> int:
	match block:
		AIR:
			return 0
		TALL_GRASS, FLOWER_RED, FLOWER_YELLOW:
			return CROSS
	return OPAQUE | SOLID


static func prop_table() -> PackedInt32Array:
	var t := PackedInt32Array()
	t.resize(COUNT)
	for b in COUNT:
		t[b] = props(b)
	return t


# Kolejność ścian: 0 +X, 1 -X, 2 +Y, 3 -Y, 4 +Z, 5 -Z
static func tile(block: int, face: int) -> int:
	match block:
		GRASS:
			if face == 2:
				return T_GRASS_TOP
			if face == 3:
				return T_DIRT
			return T_GRASS_SIDE
		DIRT:
			return T_DIRT
		STONE:
			return T_STONE
		PLANKS:
			return T_PLANKS
		SAND:
			return T_SAND
		LOG:
			return T_LOG_TOP if face == 2 or face == 3 else T_LOG_SIDE
		LEAVES:
			return T_LEAVES
		SNOW:
			return T_SNOW
		CACTUS:
			return T_CACTUS_TOP if face == 2 or face == 3 else T_CACTUS_SIDE
		TALL_GRASS:
			return T_TALL_GRASS
		FLOWER_RED:
			return T_FLOWER_RED
		FLOWER_YELLOW:
			return T_FLOWER_YELLOW
	return T_STONE


## Tabela kafelków dla rdzenia: COUNT * 6 wpisów (blok * 6 + ściana).
static func tile_table() -> PackedInt32Array:
	var t := PackedInt32Array()
	t.resize(COUNT * 6)
	for b in COUNT:
		for f in 6:
			t[b * 6 + f] = tile(b, f)
	return t


static func _px(img: Image, tx: int, x: int, y: int, c: Color) -> void:
	img.set_pixel(tx * TILE_PX + x, y, c)


static func _mix(rng: RandomNumberGenerator, a: Color, b: Color) -> Color:
	return a.lerp(b, rng.randf())


static func make_atlas_image() -> Image:
	var img := Image.create(TILES * TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261104
	var grass_a := Color(0.25, 0.50, 0.19)
	var grass_b := Color(0.33, 0.59, 0.24)
	var dirt_a := Color(0.47, 0.32, 0.20)
	var dirt_b := Color(0.56, 0.39, 0.25)
	for y in TILE_PX:
		for x in TILE_PX:
			_px(img, T_GRASS_TOP, x, y, _mix(rng, grass_a, grass_b).darkened(0.12 if rng.randf() < 0.12 else 0.0))
			var dirt := _mix(rng, dirt_a, dirt_b)
			if rng.randf() < 0.08:
				dirt = Color(0.38, 0.26, 0.17)
			_px(img, T_DIRT, x, y, dirt)
			var edge := 3 + (1 if (x * 7 + 3) % 5 < 2 else 0) + (1 if x % 4 == 1 else 0)
			_px(img, T_GRASS_SIDE, x, y, _mix(rng, grass_a, grass_b) if y < edge else _mix(rng, dirt_a, dirt_b))
			var s := _mix(rng, Color(0.50, 0.50, 0.52), Color(0.60, 0.60, 0.62))
			if (x + y * 3) % 11 == 0 or (x * 5 + y) % 13 == 0:
				s = Color(0.40, 0.40, 0.43)
			_px(img, T_STONE, x, y, s)
			var row := y / 4
			var p := Color(0.66, 0.50, 0.30).lerp(Color(0.74, 0.57, 0.35), rng.randf() * 0.6)
			if y % 4 == 3:
				p = Color(0.45, 0.32, 0.18)
			elif (x + row * 5) % 16 == 0:
				p = Color(0.50, 0.36, 0.20)
			_px(img, T_PLANKS, x, y, p)
			_px(img, T_SAND, x, y, _mix(rng, Color(0.76, 0.68, 0.46), Color(0.82, 0.74, 0.50)))
			# pień: pionowe pasy kory, z góry słoje
			var bark := _mix(rng, Color(0.36, 0.25, 0.15), Color(0.44, 0.31, 0.19))
			if x % 4 == 0 or (x * 3 + y) % 7 == 0:
				bark = Color(0.28, 0.19, 0.11)
			_px(img, T_LOG_SIDE, x, y, bark)
			var dx := x - 7.5
			var dy := y - 7.5
			var ring := int(sqrt(dx * dx + dy * dy))
			var top := Color(0.70, 0.55, 0.34) if ring % 2 == 0 else Color(0.60, 0.46, 0.27)
			if ring >= 7:
				top = Color(0.36, 0.25, 0.15)
			_px(img, T_LOG_TOP, x, y, top)
			var leaf := _mix(rng, Color(0.17, 0.40, 0.15), Color(0.25, 0.50, 0.20))
			if rng.randf() < 0.15:
				leaf = Color(0.12, 0.30, 0.11)
			_px(img, T_LEAVES, x, y, leaf)
			_px(img, T_SNOW, x, y, _mix(rng, Color(0.90, 0.93, 0.96), Color(0.97, 0.98, 1.0)))
			# kaktus: zielone pasy z jasnymi kolcami
			var cac := Color(0.24, 0.52, 0.22) if x % 4 != 0 else Color(0.18, 0.40, 0.16)
			if (x % 4 == 2) and (y % 5 == 1):
				cac = Color(0.85, 0.85, 0.65)
			_px(img, T_CACTUS_SIDE, x, y, cac)
			_px(img, T_CACTUS_TOP, x, y, Color(0.30, 0.58, 0.26) if (x > 0 and x < 15 and y > 0 and y < 15) else Color(0.18, 0.40, 0.16))
	# rośliny: przezroczyste tło, źdźbła i kwiaty
	for i in 9:
		var bx := 1 + i * 2 - (i % 2)
		var h := 6 + (i * 5) % 8
		for k in h:
			var px := clampi(bx + (k / 4) * (1 if i % 2 == 0 else -1), 0, 15)
			_px(img, T_TALL_GRASS, px, 15 - k, _mix(rng, grass_a, grass_b).lightened(0.08))
	for t in [T_FLOWER_RED, T_FLOWER_YELLOW]:
		for k in 9:
			_px(img, t, 8, 15 - k, Color(0.22, 0.48, 0.18))
		_px(img, t, 7, 11, Color(0.22, 0.48, 0.18))
		_px(img, t, 9, 13, Color(0.22, 0.48, 0.18))
		var petal := Color(0.80, 0.16, 0.14) if t == T_FLOWER_RED else Color(0.95, 0.80, 0.18)
		for py in range(3, 7):
			for px in range(6, 11):
				if (px - 8) * (px - 8) + (py - 4.5) * (py - 4.5) <= 5.5:
					_px(img, t, px, py, petal)
		_px(img, t, 8, 5 if t == T_FLOWER_RED else 4, Color(0.15, 0.10, 0.08) if t == T_FLOWER_RED else Color(0.85, 0.50, 0.10))
	return img


static func make_atlas() -> ImageTexture:
	return ImageTexture.create_from_image(make_atlas_image())


## Mała ikona bloku do paska szybkiego dostępu.
static func icon(atlas: Texture2D, block: int) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = atlas
	a.region = Rect2(tile(block, 4) * TILE_PX, 0, TILE_PX, TILE_PX)
	return a
