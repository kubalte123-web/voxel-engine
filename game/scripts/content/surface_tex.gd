class_name SurfaceTex
## Faktury powierzchni dla klocków postaci, stworzeń i rzeczy zakładanych: szare wzory 16×16 (tkanina, skóra,
## sierść, wełna, pióra…), które mnożą kolor materiału – kolory z modów dalej działają, a powierzchnia nie jest
## już płaska. Mapowanie trójplanarne w układzie klocka: ok. 32 piksele faktury na blok, piksele jak w świecie.
##
## Nazwy: fabric (tkanina), twill (spodnie, diagonal), leather (skóra), fur (sierść), wool (wełna),
## feathers (pióra), hide (krótka sierść), hair (włosy), skin (skóra ludzka), knit (dzianina), plaid (krata),
## metal, scales (łuski), none (bez faktury).

const NAMES := ["fabric", "twill", "leather", "fur", "wool", "feathers", "hide", "hair", "skin", "knit", "plaid", "metal", "scales"]
const PX := 16

static var _cache := {}


static func texture(name: String) -> Texture2D:
	if name == "" or name == "none" or not name in NAMES:
		return null
	if not _cache.has(name):
		_cache[name] = ImageTexture.create_from_image(image(name))
	return _cache[name]


## Nakłada fakturę na materiał (kolor zostaje w albedo_color). density: powtórzeń faktury na blok.
static func apply(m: StandardMaterial3D, name: String, density := 2.0) -> void:
	var t := texture(name)
	if t == null:
		return
	m.albedo_texture = t
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.uv1_triplanar = true
	m.uv1_world_triplanar = false
	m.uv1_triplanar_sharpness = 8.0
	m.uv1_scale = Vector3.ONE * density


## Szary obrazek faktury (średnio ok. 0.93, żeby kolory nie ciemniały).
static func image(name: String) -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = name.hash()
	var noise := func(a: float) -> float: return rng.randf_range(-a, a)
	# gładki szum (wartości w siatce 4×4, interpolowane) do plam i kłębków
	var grid := []
	for i in 25:
		grid.append(rng.randf())
	var smooth := func(x: int, y: int) -> float:
		var fx := x / 4.0
		var fy := y / 4.0
		var ix := int(fx) % 4
		var iy := int(fy) % 4
		var tx: float = fx - floorf(fx)
		var ty: float = fy - floorf(fy)
		var g := func(a: int, b: int) -> float: return grid[(b % 4) * 5 + (a % 4)]
		var top := lerpf(g.call(ix, iy), g.call(ix + 1, iy), tx)
		var bot := lerpf(g.call(ix, iy + 1), g.call(ix + 1, iy + 1), tx)
		return lerpf(top, bot, ty)
	var col_tone := []
	var row_tone := []
	for i in PX:
		col_tone.append(rng.randf())
		row_tone.append(rng.randf())
	for y in PX:
		for x in PX:
			var v := 0.94
			match name:
				"fabric":
					v = 0.93 + noise.call(0.035)
					if (x % 2 == 0) != (y % 2 == 0):
						v += 0.035
					if y % 8 == 7:
						v -= 0.05   # szew
				"twill":
					v = 0.94 + noise.call(0.03)
					if (x + y) % 4 == 0:
						v -= 0.09
					elif (x + y) % 4 == 1:
						v += 0.03
				"leather":
					v = 0.92 + noise.call(0.05) + (smooth.call(x, y) - 0.5) * 0.12
					if rng.randf() < 0.06:
						v -= 0.12
					if y == 0:
						v += 0.05
				"fur":
					v = 0.86 + float(col_tone[x]) * 0.12 + noise.call(0.04)
					if (y + int(col_tone[x] * 5.0)) % 5 == 4:
						v -= 0.1   # końce włosów
				"wool":
					v = 0.84 + float(smooth.call(x, y)) * 0.16 + noise.call(0.04)
					if rng.randf() < 0.08:
						v += 0.06
				"feathers":
					var off := 2 if (y / 4) % 2 == 1 else 0
					var u := (x + off) % 4
					v = 0.95 + noise.call(0.03)
					if y % 4 == 3 or (y % 4 == 2 and (u == 0 or u == 3)):
						v -= 0.13   # łuska pióra
				"hide":
					v = 0.93 + noise.call(0.05)
					if rng.randf() < 0.1:
						v -= 0.07
				"hair":
					v = 0.9 + float(row_tone[y]) * 0.08 + noise.call(0.03)
					if (x + int(row_tone[y] * 7.0)) % 7 == 0:
						v -= 0.1
				"skin":
					v = 0.96 + noise.call(0.025)
				"knit":
					var k := absi((x % 4) - 2)
					v = 0.93 + noise.call(0.03) + (0.05 if (y + k) % 2 == 0 else -0.05)
				"plaid":
					v = 0.95 + noise.call(0.03)
					if x % 8 < 2:
						v -= 0.1
					if y % 8 < 2:
						v -= 0.1
				"metal":
					v = 0.88 + float(y) / float(PX) * 0.1 + noise.call(0.03)
					if rng.randf() < 0.05:
						v += 0.12
				"scales":
					var o := 2 if (y / 3) % 2 == 1 else 0
					v = 0.93 + noise.call(0.03)
					if y % 3 == 2 or (x + o) % 4 == 0:
						v -= 0.1
			v = clampf(v, 0.0, 1.0)
			img.set_pixel(x, y, Color(v, v, v))
	return img
