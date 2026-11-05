extends Node
## Arkusz ikon wszystkich przedmiotów (do oglądania): godot --path game res://tools/icon_sheet.tscn -- --out=plik.png
## Mody wczytuje tak jak gra (pierwsza faza: rejestr), ikony w powiększeniu ×4 z nazwami.

func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := "user://icons.png"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	ModManager.scan()
	var reg := Mods.start_content("")
	var keys: Array = reg.items.keys()
	keys.sort()
	var cell := 72
	var cols := 16
	var rows := ceili(keys.size() / float(cols))
	var sheet := Image.create(cols * cell, rows * cell, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.17, 0.2, 0.25))
	var texs := []
	for k in keys:
		texs.append(reg.icon(str(k)))
	# ikony 3D renderują się w tle: czekamy, aż kolejka się opróżni
	for i in 300:
		await get_tree().process_frame
		if IconRenderer._queue.is_empty() and (IconRenderer._node == null or not IconRenderer._node.busy) and i > 5:
			break
	for i in keys.size():
		var tex: Texture2D = texs[i]
		var img := tex.get_image()
		img.convert(Image.FORMAT_RGBA8)
		img.resize(64, 64, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(img, Rect2i(0, 0, 64, 64), Vector2i((i % cols) * cell + 4, (i / cols) * cell + 4))
	sheet.save_png(out)
	print("IKONY ", keys.size(), " ", out)
	print("KLUCZE ", ", ".join(keys))
	get_tree().quit()
