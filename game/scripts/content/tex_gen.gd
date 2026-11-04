class_name TexGen
## Tekstury bloków i przedmiotów 16x16: z pliku PNG moda albo z prostego wzoru opisanego danymi.
##
## Wzory (pole "pattern"): solid, noise, speckle, bricks, planks, stripes, ore, glass, lamp, gem, ingot, food, plant, torch.
## Kolory: "color" (główny), "color2" (drugi), "spots" (plamki, np. ruda), "seed" (losowość).

const PX := 16


static func load_spec(spec: Variant, mod_path: String) -> Image:
	if spec is String:
		return _from_file(mod_path.path_join(spec))
	if spec is Dictionary:
		return pattern(spec)
	return _missing()


static func _from_file(path: String) -> Image:
	var img: Image = null
	if FileAccess.file_exists(path):
		img = Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			img = null
	elif ResourceLoader.exists(path):
		# mody wbudowane w grę: Godot przy eksporcie zamienia PNG na zaimportowaną teksturę
		var tex := load(path) as Texture2D
		if tex:
			img = tex.get_image()
			if img and img.is_compressed():
				img.decompress()
	if img == null:
		push_warning("Brak tekstury: " + path)
		return _missing()
	img.convert(Image.FORMAT_RGBA8)
	if img.get_width() != PX or img.get_height() != PX:
		img.resize(PX, PX, Image.INTERPOLATE_NEAREST)
	return img


## Szachownica fioletowo-czarna: brakująca tekstura od razu rzuca się w oczy.
static func _missing() -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	for y in PX:
		for x in PX:
			img.set_pixel(x, y, Color(0.8, 0.1, 0.8) if (x / 4 + y / 4) % 2 == 0 else Color(0.1, 0.05, 0.1))
	return img


static func _col(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and v != "":
		return Color.from_string(v, fallback)
	return fallback


static func pattern(d: Dictionary) -> Image:
	var img := Image.create(PX, PX, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var a := _col(d.get("color"), Color(0.6, 0.6, 0.6))
	var b := _col(d.get("color2"), a.darkened(0.15))
	var spots := _col(d.get("spots"), Color(0.9, 0.2, 0.2))
	var rng := RandomNumberGenerator.new()
	rng.seed = int(d.get("seed", 7)) + str(d.get("pattern", "")).hash()
	var kind := str(d.get("pattern", "noise"))
	for y in PX:
		for x in PX:
			var c := a
			match kind:
				"solid":
					c = a
				"noise":
					c = a.lerp(b, rng.randf())
				"speckle":
					c = a.lerp(b, rng.randf() * 0.5)
					if rng.randf() < 0.12:
						c = spots
				"bricks":
					var row := y / 4
					var mortar := y % 4 == 3 or (x + (4 if row % 2 == 1 else 0)) % 8 == 0
					c = b.darkened(0.3) if mortar else a.lerp(b, rng.randf() * 0.4)
				"planks":
					c = a.lerp(b, rng.randf() * 0.5)
					if y % 4 == 3:
						c = a.darkened(0.35)
					elif (x + (y / 4) * 5) % 16 == 0:
						c = a.darkened(0.2)
				"stripes":
					c = a if (x / 2) % 2 == 0 else b
				"glass":
					# rama i dwa refleksy, środek przezroczysty
					var edge := x == 0 or y == 0 or x == PX - 1 or y == PX - 1
					var glint := (x - y == 3 and x > 4 and x < 9) or (x - y == 6 and x > 8 and x < 12)
					c = a if edge else (b if glint else Color(0, 0, 0, 0))
				"lamp":
					# świecący blok: jasny środek, ciemniejsza rama i kratka
					var edge := x == 0 or y == 0 or x == PX - 1 or y == PX - 1
					var grid := x == 7 or x == 8 or y == 7 or y == 8
					c = b if edge else (a.darkened(0.25) if grid else a.lerp(a.lightened(0.3), rng.randf()))
				"ore":
					c = a.lerp(b, rng.randf() * 0.5)
					var cx := (x + 3) % 6
					var cy := (y + (x / 6) * 2) % 6
					if (cx - 2) * (cx - 2) + (cy - 2) * (cy - 2) <= 1 + int(rng.randf() < 0.3):
						c = spots.lerp(spots.lightened(0.3), rng.randf() * 0.5)
			img.set_pixel(x, y, c)
	if kind in ["gem", "ingot", "food", "plant", "torch", "stick", "pickaxe", "axe", "shovel", "sword", "hammer"]:
		_shape(img, kind, a, b, rng)
	return img


## Kształty przedmiotów rysowane na przezroczystym tle.
static func _shape(img: Image, kind: String, a: Color, b: Color, rng: RandomNumberGenerator) -> void:
	img.fill(Color(0, 0, 0, 0))
	match kind:
		"gem":
			for y in range(3, 14):
				var w := (y - 2) if y < 7 else (14 - y)
				for x in range(8 - w, 8 + w):
					var c := a.lightened(0.35) if x < 8 and y < 8 else (a if x < 8 else b)
					img.set_pixel(x, y, c)
			img.set_pixel(6, 5, Color(1, 1, 1, 0.9))
		"ingot":
			for y in range(6, 12):
				for x in range(2 + (11 - y) / 2, 14 - (11 - y) / 2):
					img.set_pixel(x, y, a.lightened(0.25) if y == 6 else (a if y < 10 else b))
		"food":
			for y in range(4, 15):
				for x in range(2, 14):
					var dx := x - 7.5
					var dy := y - 9.0
					if dx * dx + dy * dy * 1.1 <= 30.0:
						img.set_pixel(x, y, a.lightened(0.25) if dx + dy < -4 else a.lerp(b, rng.randf() * 0.3))
			for y in range(1, 4):
				img.set_pixel(8, y, Color(0.35, 0.22, 0.1))
			img.set_pixel(9, 2, Color(0.25, 0.55, 0.2))
			img.set_pixel(10, 2, Color(0.25, 0.55, 0.2))
		"stick", "pickaxe", "axe", "shovel", "sword", "hammer":
			# narzędzia: trzonek po przekątnej i głowica w kolorze materiału (color)
			var wood := Color(0.55, 0.38, 0.2)
			var wood2 := Color(0.42, 0.28, 0.14)
			var top := 2 if kind == "stick" else 5
			if kind == "sword":
				top = 12
			for k in range(top, 15):
				img.set_pixel(15 - k, k, wood if k % 2 == 0 else wood2)
				img.set_pixel(clampi(16 - k, 0, 15), k, wood2)
			match kind:
				"pickaxe":
					for x in range(3, 14):
						var y := 3 + int(absf(x - 8.5) * 0.45)
						img.set_pixel(x, y, a)
						img.set_pixel(x, y + 1, b)
				"axe":
					for y in range(1, 8):
						for x in range(8, 13 - absi(y - 4) / 2):
							img.set_pixel(x, y, a if x < 11 else b)
				"shovel":
					for y in range(1, 6):
						for x in range(10, 15):
							if absf(x - 12) + absf(y - 3) <= 2.6:
								img.set_pixel(x, y, a if y < 3 else b)
				"sword":
					for k in range(1, 12):
						img.set_pixel(k + 3, 12 - k, a)
						img.set_pixel(k + 4, 12 - k, b)
					for k in range(-2, 3):
						img.set_pixel(4 + k, 11 + k, Color(0.4, 0.3, 0.15))
				"hammer":
					for y in range(1, 6):
						for x in range(8, 15):
							img.set_pixel(x, y, a if y < 4 else b)
		"torch":
			# patyk (kolumny 7-8, wiersze 6-15) i płomień nad nim; ściany pochodni biorą ten wycinek
			for y in range(6, 16):
				img.set_pixel(7, y, Color(0.42, 0.28, 0.14))
				img.set_pixel(8, y, Color(0.34, 0.22, 0.1))
			for y in range(2, 7):
				for x in range(6, 10):
					var hot := y >= 4 and x >= 7 and x <= 8
					img.set_pixel(x, y, Color(1.0, 0.95, 0.6) if hot else Color(1.0, 0.62, 0.15))
			img.set_pixel(7, 6, Color(1.0, 0.9, 0.5))
			img.set_pixel(8, 6, Color(1.0, 0.8, 0.3))
			img.set_pixel(7, 7, Color(1.0, 0.85, 0.4))
			img.set_pixel(8, 7, Color(1.0, 0.75, 0.3))
		"plant":
			for i in 7:
				var bx := 2 + i * 2
				var h := 6 + (i * 5) % 8
				for k in h:
					img.set_pixel(clampi(bx + (k / 4) * (1 if i % 2 == 0 else -1), 0, 15), 15 - k, a.lerp(b, rng.randf()))


## Ikona bloku: mały sześcian w rzucie izometrycznym (góra jaśniejsza, boki ciemniejsze).
static func cube_icon(top: Image, side: Image, front: Image) -> Image:
	var n := 32
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for y in n:
		for x in n:
			var fx := float(x) + 0.5
			var fy := float(y) + 0.5
			# górny romb: środek (16, 8), połowa szerokości 15, wysokość 7.5
			var u := (fx - 16.0) / 15.0
			var v := (fy - 8.5) / 7.5
			if absf(u) + absf(v) <= 1.0:
				var tu := clampf((u + v) * 0.5 + 0.5, 0.0, 0.999)
				var tv := clampf((v - u) * 0.5 + 0.5, 0.0, 0.999)
				img.set_pixel(x, y, top.get_pixel(int(tu * 16), int(tv * 16)))
				continue
			# lewa ściana
			if fx >= 1.0 and fx < 16.0:
				var k := (fx - 1.0) / 15.0
				var y0 := 8.5 + 7.5 * k
				if fy >= y0 and fy < y0 + 15.0:
					var c := front.get_pixel(int(k * 15.99), int((fy - y0) / 15.0 * 15.99))
					img.set_pixel(x, y, Color(c.r * 0.78, c.g * 0.78, c.b * 0.78, c.a))
					continue
			# prawa ściana
			if fx >= 16.0 and fx < 31.0:
				var k := (fx - 16.0) / 15.0
				var y0 := 16.0 - 7.5 * k
				if fy >= y0 and fy < y0 + 15.0:
					var c := side.get_pixel(int(k * 15.99), int((fy - y0) / 15.0 * 15.99))
					img.set_pixel(x, y, Color(c.r * 0.6, c.g * 0.6, c.b * 0.6, c.a))
	return img
