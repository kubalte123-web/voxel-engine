class_name Blocks
## Definicje bloków i generowany w kodzie atlas tekstur (16x16 pikseli na kafelek).

const AIR := 0
const GRASS := 1
const DIRT := 2
const STONE := 3
const PLANKS := 4
const SAND := 5
const COUNT := 6

const NAMES := ["Powietrze", "Trawa", "Ziemia", "Kamień", "Deski", "Piasek"]
const PLACEABLE := [GRASS, DIRT, STONE, PLANKS, SAND]

# Kafelki w atlasie
const T_GRASS_TOP := 0
const T_GRASS_SIDE := 1
const T_DIRT := 2
const T_STONE := 3
const T_PLANKS := 4
const T_SAND := 5
const TILES := 6
const TILE_PX := 16

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


static func make_atlas_image() -> Image:
	var img := Image.create(TILES * TILE_PX, TILE_PX, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261104
	for y in TILE_PX:
		for x in TILE_PX:
			# trawa z góry
			var g := rng.randf()
			_px(img, T_GRASS_TOP, x, y, Color(0.25, 0.50, 0.19).lerp(Color(0.33, 0.59, 0.24), g).darkened(0.12 if rng.randf() < 0.12 else 0.0))
			# ziemia
			var d := rng.randf()
			var dirt := Color(0.47, 0.32, 0.20).lerp(Color(0.56, 0.39, 0.25), d)
			if rng.randf() < 0.08:
				dirt = Color(0.38, 0.26, 0.17)
			_px(img, T_DIRT, x, y, dirt)
			# bok trawy: ziemia z poszarpanym zielonym brzegiem
			var edge := 3 + (1 if (x * 7 + 3) % 5 < 2 else 0) + (1 if x % 4 == 1 else 0)
			if y < edge:
				_px(img, T_GRASS_SIDE, x, y, Color(0.26, 0.52, 0.20).lerp(Color(0.33, 0.59, 0.24), rng.randf()))
			else:
				_px(img, T_GRASS_SIDE, x, y, Color(0.47, 0.32, 0.20).lerp(Color(0.56, 0.39, 0.25), rng.randf()))
			# kamień
			var s := Color(0.50, 0.50, 0.52).lerp(Color(0.60, 0.60, 0.62), rng.randf())
			if (x + y * 3) % 11 == 0 or (x * 5 + y) % 13 == 0:
				s = Color(0.40, 0.40, 0.43)
			_px(img, T_STONE, x, y, s)
			# deski
			var row := y / 4
			var p := Color(0.66, 0.50, 0.30).lerp(Color(0.74, 0.57, 0.35), rng.randf() * 0.6)
			if y % 4 == 3:
				p = Color(0.45, 0.32, 0.18)
			elif (x + row * 5) % 16 == 0:
				p = Color(0.50, 0.36, 0.20)
			_px(img, T_PLANKS, x, y, p)
			# piasek
			_px(img, T_SAND, x, y, Color(0.80, 0.73, 0.50).lerp(Color(0.86, 0.79, 0.55), rng.randf()))
	return img


static func make_atlas() -> ImageTexture:
	return ImageTexture.create_from_image(make_atlas_image())


## Mała ikona bloku do paska szybkiego dostępu.
static func icon(atlas: Texture2D, block: int) -> AtlasTexture:
	var a := AtlasTexture.new()
	a.atlas = atlas
	a.region = Rect2(tile(block, 4) * TILE_PX, 0, TILE_PX, TILE_PX)
	return a
