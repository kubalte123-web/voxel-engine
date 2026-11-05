extends SceneTree
## Generuje mods/podstawowa/mods/building/textures/marble_tiles.png (128 × 128): przykład bloku w wyższej
## rozdzielczości (pole resolution = 128) obok zwykłych bloków 16 × 16.
## Uruchom: godot --headless --path game -s tools/make_marble.gd

func _initialize() -> void:
	var n := 128
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 7
	noise.frequency = 0.02
	noise.fractal_octaves = 5
	var vein := FastNoiseLite.new()
	vein.seed = 11
	vein.frequency = 0.035
	for y in n:
		for x in n:
			# cztery płyty marmuru z fugami
			var lx := x % 64
			var ly := y % 64
			var seam := lx < 2 or ly < 2
			var v := absf(sin((x * 0.06 + y * 0.03) + noise.get_noise_2d(x, y) * 6.0))
			var veins := pow(1.0 - v, 9.0) * 0.55 + maxf(0.0, vein.get_noise_2d(x * 1.7, y) - 0.45) * 0.6
			var base := Color(0.92, 0.9, 0.86).lerp(Color(0.78, 0.76, 0.74), noise.get_noise_2d(x * 2.0, y * 2.0) * 0.5 + 0.5)
			var c := base.lerp(Color(0.35, 0.36, 0.42), clampf(veins, 0.0, 1.0))
			if (x / 64 + y / 64) % 2 == 1:
				c = c.darkened(0.06)
			if seam:
				c = Color(0.55, 0.52, 0.48)
			elif lx < 4 or ly < 4:
				c = c.lightened(0.08)
			img.set_pixel(x, y, c)
	var path := "res://mods/podstawowa/mods/building/textures/marble_tiles.png"
	print("PNG ", img.save_png(ProjectSettings.globalize_path(path)))
	quit()
