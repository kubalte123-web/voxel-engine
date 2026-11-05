class_name ModsScreen
extends VBoxContainer
## Ekran modów: ręczna kolejność ładowania, włączanie i pełne ustawienia każdego moda.
## Paczki modów są jedną pozycją: przełącznik włącza całą paczkę, „Otwórz” pokazuje jej moduły.
## Ustawienia wymuszone przez serwer są zablokowane i oznaczone.

var on_back: Callable
var selected := ""        # id moda albo "pack:<id>"
var open_pack := ""       # paczka otwarta w liście (pusta: lista główna)
var list_box: VBoxContainer
var details: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	ModManager.changed.connect(_refresh)
	_build()


func _build() -> void:
	UI.clear(self)
	add_child(UI.label("Mody", 30))
	add_child(UI.wrap("Paczka to cała rozgrywka – otwórz ją, żeby włączać i ustawiać pojedyncze moduły. Mody niżej na liście ładują się później i mogą nadpisywać wcześniejsze. Ustawienia generowania terenu zapisują się w świecie przy jego tworzeniu."))
	if not ModManager.server_profile.is_empty():
		add_child(UI.wrap("Połączono z serwerem: elementy oznaczone [serwer] są ustawione przez serwer i nie można ich zmienić.", 16, UI.LOCK))
	var narrow := UI.narrow(get_viewport_rect().size)
	var split: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(0 if narrow else 380, 180 if narrow else 360)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	left.add_child(list_box)

	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(0, 260 if narrow else 360)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	right.add_child(details)

	add_child(UI.button("Wróć", func(): if on_back.is_valid(): on_back.call()))
	if selected.is_empty():
		if not ModManager.packs.is_empty():
			selected = "pack:" + str(ModManager.packs.keys()[0])
		elif not ModManager.effective_order().is_empty():
			selected = ModManager.effective_order()[0]
	_refresh()


func _refresh() -> void:
	if list_box == null:
		return
	UI.clear(list_box)
	if open_pack != "" and not ModManager.packs.has(open_pack):
		open_pack = ""
	if open_pack == "":
		for pk in ModManager.packs:
			list_box.add_child(_pack_row(pk))
	else:
		var back := UI.button("◂ Wszystkie mody", func():
			selected = "pack:" + open_pack
			open_pack = ""
			_refresh())
		list_box.add_child(back)
		list_box.add_child(UI.label(str(ModManager.packs[open_pack].get("name", open_pack)), 20))
		if not ModManager.is_pack_enabled(open_pack):
			list_box.add_child(UI.wrap("Paczka jest wyłączona – moduły nie wczytają się, dopóki jej nie włączysz.", 15, UI.DANGER))
	var order := ModManager.effective_order()
	var shown: Array[String] = []
	for id in order:
		if str(ModManager.manifests[id].get("pack", "")) == open_pack:
			shown.append(id)
	if open_pack == "" and not shown.is_empty() and not ModManager.packs.is_empty():
		list_box.add_child(UI.label("Dodatki", 18, UI.MUTED))
	for i in shown.size():
		var id: String = shown[i]
		var m: Dictionary = ModManager.manifests[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.label("%d." % (i + 1), 17, UI.MUTED))
		var cb := CheckBox.new()
		cb.button_pressed = ModManager.is_checked(id)
		cb.disabled = ModManager.enabled_locked(id) or m.get("required", false)
		var by := ModManager.replacement_of(id)
		cb.tooltip_text = "Wymagany" if m.get("required", false) else ("Zastąpiony przez: " + by if by != "" else "Włącz lub wyłącz mod")
		cb.toggled.connect(func(on): ModManager.set_enabled(id, on))
		row.add_child(cb)
		var name_btn := Button.new()
		name_btn.text = str(m.get("name", id)) + ("  (zastąpiony)" if by != "" else "")
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.custom_minimum_size = Vector2(0, 46)
		if id == selected:
			name_btn.add_theme_stylebox_override("normal", UI._box(UI.ACCENT.darkened(0.35), 8, UI.ACCENT, 10))
		name_btn.pressed.connect(func(): selected = id; _refresh())
		row.add_child(name_btn)
		var up := Button.new()
		up.text = "Wyżej"
		up.custom_minimum_size = Vector2(72, 46)
		up.disabled = ModManager.order_locked() or i == 0
		up.pressed.connect(func(): ModManager.move(id, -1))
		row.add_child(up)
		var down := Button.new()
		down.text = "Niżej"
		down.custom_minimum_size = Vector2(72, 46)
		down.disabled = ModManager.order_locked() or i == shown.size() - 1
		down.pressed.connect(func(): ModManager.move(id, 1))
		row.add_child(down)
		list_box.add_child(row)
	if ModManager.order_locked():
		list_box.add_child(UI.wrap("[serwer] Kolejność ustawiona przez serwer.", 15, UI.LOCK))
	if open_pack == "":
		_resource_rows()
	_details()


## Paczki zasobów: włączone (na górze wyższe pierwszeństwo) i pozostałe znalezione w folderze.
func _resource_rows() -> void:
	list_box.add_child(UI.label("Paczki zasobów", 18, UI.MUTED))
	var all: Array = ModManager.resource_packs
	if all.is_empty():
		list_box.add_child(UI.wrap("Brak paczek zasobów. Wyeksportuj szablon i zmień w nim tekstury, modele albo dźwięki.", 15, UI.MUTED))
	var ids: Array = ModManager.resource_order.duplicate()
	for r in all:
		if not ids.has(r.id):
			ids.append(r.id)
	for id in ids:
		var r: Dictionary = ModManager.resource_pack(id)
		var on := ModManager.resource_order.has(id)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var cb := CheckBox.new()
		cb.button_pressed = on
		cb.toggled.connect(func(v): ModManager.set_resource_enabled(id, v))
		row.add_child(cb)
		var name_btn := Button.new()
		name_btn.text = str(r.get("name", id))
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.custom_minimum_size = Vector2(0, 46)
		if selected == "res:" + id:
			name_btn.add_theme_stylebox_override("normal", UI._box(UI.ACCENT.darkened(0.35), 8, UI.ACCENT, 10))
		name_btn.pressed.connect(func(): selected = "res:" + id; _refresh())
		row.add_child(name_btn)
		var k := ModManager.resource_order.find(id)
		for d in [[-1, "Wyżej"], [1, "Niżej"]]:
			var b := Button.new()
			b.text = d[1]
			b.custom_minimum_size = Vector2(72, 46)
			b.disabled = not on or (d[0] < 0 and k == 0) or (d[0] > 0 and k == ModManager.resource_order.size() - 1)
			var delta: int = d[0]
			b.pressed.connect(func(): ModManager.move_resource(id, delta))
			row.add_child(b)
		list_box.add_child(row)
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 8)
	tools.add_child(UI.button("Eksportuj szablon zasobów", _export_resources))
	if not OS.has_feature("web"):
		tools.add_child(UI.button("Otwórz folder", func(): OS.shell_open(ProjectSettings.globalize_path(ModManager.RES_DIR))))
	list_box.add_child(tools)


func _export_resources() -> void:
	var name := "szablon"
	var n := 2
	while DirAccess.dir_exists_absolute(ModManager.RES_DIR.path_join(name)):
		name = "szablon_%d" % n
		n += 1
	var dir := ModManager.RES_DIR.path_join(name)
	var reg: Registry = Mods.registry if Mods.is_running() else Mods.menu_registry()
	var c: Dictionary = ResourceExport.export(reg, dir)
	ModManager.scan()
	ModManager.load_user()
	selected = "res:" + name
	ModManager.changed.emit()
	UI.clear(details)
	details.add_child(UI.label("Szablon zapisany", 24))
	details.add_child(UI.wrap("Folder: %s\nBloki: %d, przedmioty: %d, dźwięki: %d, stworzenia: %d, języki: %d.\nZmień pliki, które chcesz, usuń resztę i włącz paczkę na liście." % [ProjectSettings.globalize_path(dir), c.blocks, c.items, c.sounds, c.entities, c.lang], 16, UI.TEXT))


## Wiersz paczki: przełącznik całej paczki, nazwa z liczbą włączonych modułów, „Otwórz”.
func _pack_row(pk: String) -> Control:
	var p: Dictionary = ModManager.packs[pk]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	var cb := CheckBox.new()
	cb.button_pressed = ModManager.is_pack_enabled(pk)
	cb.disabled = ModManager.order_locked() or ModManager.pack_required(pk)
	cb.tooltip_text = "Paczka z modułem wymaganym – zawsze włączona" if ModManager.pack_required(pk) else "Włącz lub wyłącz całą paczkę"
	cb.toggled.connect(func(on): ModManager.set_pack_enabled(pk, on))
	row.add_child(cb)
	var mods: Array = p.get("modules", [])
	var on := 0
	for id in mods:
		if ModManager.is_enabled(id):
			on += 1
	var name_btn := Button.new()
	name_btn.text = "%s  (%d/%d modułów)" % [str(p.get("name", pk)), on, mods.size()]
	name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_btn.custom_minimum_size = Vector2(0, 52)
	if selected == "pack:" + pk:
		name_btn.add_theme_stylebox_override("normal", UI._box(UI.ACCENT.darkened(0.35), 8, UI.ACCENT, 10))
	name_btn.pressed.connect(func(): selected = "pack:" + pk; _refresh())
	row.add_child(name_btn)
	var open := UI.button("Otwórz ▸", func():
		open_pack = pk
		var first := ModManager.siblings(mods[0]) if not mods.is_empty() else []
		selected = first[0] if not first.is_empty() else selected
		_refresh())
	open.custom_minimum_size = Vector2(110, 52)
	row.add_child(open)
	return row


func _pack_details(pk: String) -> void:
	var p: Dictionary = ModManager.packs[pk]
	details.add_child(UI.label("%s  %s" % [p.get("name", pk), p.get("version", "")], 24))
	details.add_child(UI.label("Autor: %s" % p.get("author", "nieznany"), 16, UI.MUTED))
	details.add_child(UI.wrap(str(p.get("description", "")), 17, UI.TEXT))
	var mods: Array = p.get("modules", [])
	var names := []
	var off := []
	for id in ModManager.siblings(mods[0]) if not mods.is_empty() else []:
		var n := str(ModManager.manifests[id].get("name", id))
		if ModManager.is_enabled(id):
			names.append(n)
		else:
			off.append(n)
	details.add_child(UI.wrap("Włączone moduły (%d): %s" % [names.size(), ", ".join(names)], 16, UI.MUTED))
	if not off.is_empty():
		details.add_child(UI.wrap("Wyłączone: " + ", ".join(off), 16, UI.MUTED))
	details.add_child(UI.button("Otwórz paczkę – moduły i ustawienia", func():
		open_pack = pk
		_refresh(), true))
	if not ModManager.order_locked():
		details.add_child(UI.button("Przywróć domyślne moduły paczki", func(): ModManager.reset_pack(pk)))


func _details() -> void:
	UI.clear(details)
	if selected.begins_with("res:"):
		var r: Dictionary = ModManager.resource_pack(selected.substr(4))
		if not r.is_empty():
			details.add_child(UI.label(str(r.name), 24))
			details.add_child(UI.wrap(str(r.description) if str(r.description) != "" else "Paczka zasobów (bez opisu).", 17, UI.TEXT))
			details.add_child(UI.wrap("Folder: " + ProjectSettings.globalize_path(str(r.path)), 15, UI.MUTED))
			details.add_child(UI.wrap("Paczka zasobów zmienia tylko wygląd, dźwięki i teksty. Zmiany widać po wczytaniu świata.", 15, UI.MUTED))
			return
	if selected.begins_with("pack:") and ModManager.packs.has(selected.substr(5)):
		_pack_details(selected.substr(5))
		return
	if not ModManager.manifests.has(selected):
		details.add_child(UI.wrap("Wybierz mod z listy."))
		return
	var m: Dictionary = ModManager.manifests[selected]
	details.add_child(UI.label("%s  %s" % [m.get("name", selected), m.get("version", "")], 24))
	details.add_child(UI.label("Autor: %s" % m.get("author", "nieznany"), 16, UI.MUTED))
	details.add_child(UI.wrap(m.get("description", ""), 17, UI.TEXT))
	if m.has("pack"):
		details.add_child(UI.wrap("Moduł paczki: " + str(ModManager.packs.get(m.pack, {}).get("name", m.pack)), 15, UI.MUTED))
	var by := ModManager.replacement_of(selected)
	if by != "":
		details.add_child(UI.wrap("Zastąpiony przez mod „%s” – ten moduł się nie wczyta." % ModManager.manifests[by].get("name", by), 15, UI.LOCK))
	var repl: Array = Registry.arr(m.get("replaces"))
	if not repl.is_empty():
		details.add_child(UI.wrap("Zastępuje: " + ", ".join(repl), 15, UI.MUTED))
	var conf: Array = Registry.arr(m.get("conflicts"))
	if not conf.is_empty():
		details.add_child(UI.wrap("Nie działa razem z: " + ", ".join(conf), 15, UI.MUTED))
	var reqs: Array = m.get("requires", [])
	if not reqs.is_empty():
		var names := []
		var ok := true
		var bad := []
		for req in reqs:
			var d := ModManager.dep_parse(str(req))
			var r: String = d[0]
			names.append(str(ModManager.manifests.get(r, {}).get("name", r + " (brak)")) + (" %s%s" % [d[1], d[2]] if d[1] != "" else ""))
			if not ModManager.is_enabled(r):
				ok = false
			var vp := ModManager.dep_version_problem(str(req))
			if vp != "":
				bad.append(vp)
		details.add_child(UI.wrap("Wymaga: " + ", ".join(names), 16, UI.MUTED if ok and bad.is_empty() else UI.DANGER))
		if not ok:
			details.add_child(UI.wrap("Włącz wymagane mody, inaczej ten mod się nie wczyta.", 15, UI.DANGER))
		if not bad.is_empty():
			details.add_child(UI.wrap("Zła wersja: " + ", ".join(bad), 15, UI.DANGER))
	var defs: Array = ModManager.setting_defs(selected)
	if defs.is_empty():
		details.add_child(UI.wrap("Ten mod nie ma ustawień."))
		return
	details.add_child(UI.label("Ustawienia", 20))
	for d in defs:
		details.add_child(_setting(selected, d))
	details.add_child(UI.button("Przywróć domyślne", func(): ModManager.reset(selected)))


func _setting(id: String, d: Dictionary) -> Control:
	var key: String = d.key
	var locked := ModManager.is_locked(id, key)
	var text: String = d.get("label", key)
	if d.get("world", false):
		text += " (nowe światy)"
	if locked:
		text = "[serwer] " + text
	var v: Variant = ModManager.get_value(id, key)
	match d.get("type", "float"):
		"block_toggles":
			return _block_toggles(id, key, text, v, d, locked)
		"bool":
			return UI.check_row(text, bool(v), func(on): ModManager.set_value(id, key, on), locked)
		"choice":
			return _choice(id, key, text, v, d, locked)
		"int":
			return UI.slider_row(text, d.get("min", 0), d.get("max", 100), d.get("step", 1), int(v),
				func(x): return str(int(x)), func(x): ModManager.set_value(id, key, int(x)), locked)
		_:
			return UI.slider_row(text, d.get("min", 0.0), d.get("max", 1.0), d.get("step", 0.1), float(v),
				func(x): return "%.1f" % x, func(x): ModManager.set_value(id, key, x), locked)


## Wybór jednej z opcji (lista "options" w mod.json); wartość to tekst opcji.
func _choice(id: String, key: String, text: String, v: Variant, d: Dictionary, locked: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UI.label(text, 17)
	l.custom_minimum_size = Vector2(220, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var ob := OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(160, 44)
	var options: Array = d.get("options", [])
	for o in options:
		ob.add_item(str(o))
	ob.selected = maxi(0, options.find(str(v)))
	ob.disabled = locked
	ob.item_selected.connect(func(i): ModManager.set_value(id, key, str(options[i])))
	row.add_child(ob)
	return row


## Ustawienie z przełącznikiem dla każdego bloku w grze (lista budowana z rejestru bloków).
func _block_toggles(id: String, key: String, text: String, v: Variant, d: Dictionary, locked: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UI.label(text, 17))
	var values: Dictionary = v if v is Dictionary else {}
	var def := bool(d.get("default", true))
	var grid := GridContainer.new()
	grid.columns = 1 if UI.narrow(get_viewport_rect().size) else 2
	var reg := Mods.menu_registry() if not Mods.is_running() else Mods.registry
	for b in range(1, reg.count()):
		var bkey: String = reg.keys[b]
		var on := bool(values.get(bkey, def))
		grid.add_child(UI.check_row(reg.names[b], on, func(state):
			var cur: Variant = ModManager.get_value(id, key)
			var dict: Dictionary = (cur as Dictionary).duplicate() if cur is Dictionary else {}
			dict[bkey] = state
			ModManager.set_value(id, key, dict), locked))
	box.add_child(grid)
	return box
