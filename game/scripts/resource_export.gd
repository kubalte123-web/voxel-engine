class_name ResourceExport
## Szablon paczki zasobów: zapisuje wszystko, czego gra teraz używa (tekstury bloków także ze wzorów,
## ikony przedmiotów, dźwięki, teksty, nazwy części stworzeń) w strukturze, którą rozumieją paczki zasobów.
## Grafik zmienia pliki, które chce, resztę usuwa – i ma gotową paczkę bez szukania, który mod co dodał.

const FACES := ["east", "west", "top", "bottom", "south", "north"]


static func export(reg: Registry, dir: String) -> Dictionary:
	var counts := {"blocks": 0, "items": 0, "sounds": 0, "entities": 0, "lang": 0}
	for sub in ["blocks", "items", "sounds", "entities", "lang"]:
		DirAccess.make_dir_recursive_absolute(dir.path_join(sub))
	_text(dir.path_join("pack.json"), JSON.stringify({"name": "Moja paczka zasobów", "description": "Opis paczki"}, "\t"))
	_text(dir.path_join("README.txt"), README)
	# bloki: jedna tekstura, albo góra/dół/boki, albo każda strona osobno
	for id in range(1, reg.count()):
		var key: String = reg.keys[id]
		if "~" in key or reg.is_liquid(id):
			continue
		var t := []
		for f in 6:
			t.append(reg.tiles[id * 6 + f])
		var base := reg.base_of(id)
		var facing: Variant = reg.state_of(id).get("facing")
		if base != id and facing != null and str(facing) != "north":
			continue   # obrócone warianty: wystarczy tekstura dla kierunku północnego
		if base != id:
			var same := true
			for f in 6:
				if reg.tiles[base * 6 + f] != t[f]:
					same = false
			if same:
				continue   # wariant wygląda jak blok podstawowy
		var img := func(f: int) -> Image: return reg.tile_images[t[f]]
		if t.count(t[0]) == 6:
			_png(img.call(0), dir.path_join("blocks/%s.png" % key))
		elif t[0] == t[1] and t[0] == t[4] and t[0] == t[5]:
			_png(img.call(0), dir.path_join("blocks/%s.side.png" % key))
			_png(img.call(2), dir.path_join("blocks/%s.top.png" % key))
			_png(img.call(3), dir.path_join("blocks/%s.bottom.png" % key))
		else:
			for f in 6:
				_png(img.call(f), dir.path_join("blocks/%s.%s.png" % [key, FACES[f]]))
		counts.blocks += 1
	# przedmioty (bez bloków: ich ikona powstaje z tekstur bloku)
	for key in reg.items:
		if int(reg.items[key].get("block", -1)) > 0:
			continue
		var tex := reg.icon(str(key))
		if tex:
			_png(tex.get_image(), dir.path_join("items/%s.png" % key))
			counts.items += 1
	# dźwięki: pierwszy plik każdego dźwięku (gdy da się go odczytać)
	for name in reg.sounds:
		var d: Dictionary = reg.sounds[name]
		var files: Array = d.files if d.get("files") is Array else ([d.file] if d.has("file") else [])
		for i in files.size():
			var src := _source(reg, str(d.get("mod", "")), str(files[i]))
			if src != "" and FileAccess.file_exists(src):
				var suffix := ".%d" % (i + 1) if files.size() > 1 else ""
				_copy(src, dir.path_join("sounds/%s%s.%s" % [name, suffix, src.get_extension()]))
				counts.sounds += 1
	# stworzenia: nazwy części, które musi mieć model GLB (albo animacje Idle/Walk/Attack)
	for type in reg.entities:
		var d: Dictionary = reg.entities[type]
		var lines := ["Stworzenie: %s (%s)" % [str(d.get("name", type)), type],
			"Model: zapisz jako entities/%s.glb. Przód modelu to -Z, 1 jednostka = 1 blok." % type,
			"Animacje w pliku (opcjonalne): Idle, Walk, Run, Attack, Hurt.",
			"Bez animacji w pliku podaj w entities/%s.json części do kołysania, np. {\"swing\": {\"LegL\": 1, \"LegR\": -1}, \"head\": \"Head\"}." % type,
			"", "Części modelu z klocków (nazwa: punkt obrotu):"]
		var parts: Dictionary = d.get("parts", {}) if d.get("parts") is Dictionary else {}
		for pn in parts:
			var pd: Dictionary = parts[pn]
			var role := " (noga)" if pd.has("swing") else (" (skrzydło)" if pd.has("wing") else (" (głowa)" if pd.get("look", false) else ""))
			lines.append("  %s: %s%s" % [pn, str(pd.get("pivot", [0, 0, 0])), role])
		_text(dir.path_join("entities/%s.txt" % type), "\n".join(lines))
		counts.entities += 1
	# teksty modów: klucze "mod:klucz" ze wszystkich plików lang
	var mods: Node = (Engine.get_main_loop() as SceneTree).root.get_node("/root/Mods")
	for lang in ["pl", "en"]:
		var all := {}
		for mod_id in mods.order:
			var t: Dictionary = mods._lang(mod_id, lang)
			for k in t:
				all["%s:%s" % [mod_id, k]] = t[k]
		if not all.is_empty():
			_text(dir.path_join("lang/%s.json" % lang), JSON.stringify(all, "\t"))
			counts.lang += 1
	return counts


static func _source(reg: Registry, mod: String, file: String) -> String:
	if file.find(":") > 0 and not file.begins_with("res:") and not file.begins_with("user:"):
		mod = file.substr(0, file.find(":"))
		file = file.substr(file.find(":") + 1)
	if file.begins_with("res://") or file.begins_with("user://"):
		return file
	return reg._mod_path(mod).path_join(file)


static func _png(img: Image, path: String) -> void:
	if img:
		img.save_png(path)


static func _text(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)


static func _copy(src: String, dst: String) -> void:
	var f := FileAccess.open(dst, FileAccess.WRITE)
	if f:
		f.store_buffer(FileAccess.get_file_as_bytes(src))


const README := """Paczka zasobów – szablon wyeksportowany z gry.

Zmień pliki, które chcesz, a resztę usuń (paczka podmienia tylko to, co zawiera).
Paczki leżą w folderze resourcepacks gry; włączasz je w menu Mody → Paczki zasobów.
Paczka wyżej na liście ma pierwszeństwo.

blocks/<klucz>.png                 tekstura bloku na wszystkie ściany (16 × 16 pikseli)
blocks/<klucz>.top.png / .bottom / .side   góra, dół, boki
blocks/<klucz>.front.png           przód bloku z kierunkiem (piec, skrzynia)
blocks/<klucz>.north.png ...       konkretna strona (north, south, east, west)
blocks/<klucz>[stan=wartość].png   wygląd jednego stanu, np. furnace[facing=north,lit=true].front.png
blocks/<klucz>.glb                 model bloku z polem model (np. kocioł)
items/<klucz>.png                  ikona przedmiotu
entities/<rodzaj>.glb              model stworzenia (opis części w entities/<rodzaj>.txt)
entities/<rodzaj>.json             ustawienia modelu: scale, offset, rotation, swing, head, animations
sounds/<nazwa>.ogg                 dźwięk (kilka wersji: <nazwa>.1.ogg, <nazwa>.2.ogg ...)
lang/pl.json, lang/en.json         teksty modów: "mod:klucz": "tekst"

Paczka zasobów zmienia tylko wygląd i dźwięk – działa też na cudzym serwerze i nie wpływa na zgodność świata.
"""
