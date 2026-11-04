extends Control
## Menu główne: nowy świat, wczytaj świat, mody, opcje.

var panel: PanelContainer
var content: VBoxContainer
var hills: Array = []  # pikselowe wzgórza tła: [kolor, wysokości kolumn]


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_make_hills()
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	panel = PanelContainer.new()
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	get_viewport().size_changed.connect(_fit)
	show_main()
	if not Net.last_error.is_empty():
		_error(Net.last_error)
		Net.last_error = ""
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--server="):
			_dedicated(a.trim_prefix("--server="), args)
			return
		if a.begins_with("--join="):
			_auto_join(a.trim_prefix("--join="), args)
			return
	for a in args:
		if a.begins_with("--shots="):
			_autotest(a.trim_prefix("--shots="))


## Panel dopasowany do ekranu: szeroki na PC, prawie cały ekran na telefonie.
func _fit() -> void:
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 32.0, 520.0 if content.get_meta("wide", false) == false else 1040.0)
	panel.custom_minimum_size = Vector2(w, 0)
	var scroll: ScrollContainer = panel.get_child(0)
	var want := content.get_combined_minimum_size().y + 4.0
	scroll.custom_minimum_size = Vector2(w - 48.0, minf(vs.y - 80.0, maxf(want, 120.0)))


func _screen(wide: bool = false) -> void:
	UI.clear(content)
	content.set_meta("wide", wide)
	_fit()
	_fit.call_deferred()


# ---------- ekrany ----------

func show_main() -> void:
	_screen()
	var title := UI.label("VOXEL ENGINE", 46)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(title)
	var sub := UI.label("nazwa robocza · etap 6", 16, UI.MUTED)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	content.add_child(sub)
	content.add_child(_gap(8))
	content.add_child(UI.button("Nowy świat", show_new_world, true))
	var load_btn := UI.button("Wczytaj świat", show_load)
	load_btn.disabled = GameState.list_worlds().is_empty()
	content.add_child(load_btn)
	content.add_child(UI.button("Gra wieloosobowa", show_multiplayer))
	content.add_child(UI.button("Mody", show_mods))
	content.add_child(UI.button("Opcje", show_options))
	if not OS.has_feature("web"):
		content.add_child(UI.button("Wyjdź", func(): get_tree().quit()))


func show_new_world() -> void:
	_screen()
	content.add_child(UI.label("Nowy świat", 30))
	content.add_child(UI.label("Nazwa", 16, UI.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = "Nowy świat %d" % (GameState.list_worlds().size() + 1)
	name_edit.custom_minimum_size = Vector2(0, 48)
	content.add_child(name_edit)
	content.add_child(UI.label("Ziarno świata", 16, UI.MUTED))
	var seed_edit := LineEdit.new()
	seed_edit.placeholder_text = "puste = losowe"
	seed_edit.custom_minimum_size = Vector2(0, 48)
	content.add_child(seed_edit)
	content.add_child(UI.wrap("To samo ziarno daje ten sam świat. Ustawienia terenu z modów (np. wysokość wzgórz) zapiszą się w tym świecie."))
	content.add_child(UI.button("Utwórz i graj", func():
		var dir := GameState.create_world(name_edit.text, seed_edit.text)
		GameState.start(dir), true))
	content.add_child(UI.button("Wróć", show_main))


func show_load() -> void:
	_screen()
	content.add_child(UI.label("Wczytaj świat", 30))
	var worlds := GameState.list_worlds()
	if worlds.is_empty():
		content.add_child(UI.wrap("Nie masz jeszcze żadnego świata. Utwórz pierwszy w „Nowy świat”."))
	for w in worlds:
		var card := PanelContainer.new()
		card.add_theme_stylebox_override("panel", UI._box(Color(1, 1, 1, 0.04), 8, UI.PANEL_EDGE, 14))
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 8)
		card.add_child(col)
		col.add_child(UI.label(w.get("name", "Świat"), 22))
		var played := Time.get_datetime_string_from_unix_time(int(w.get("played", 0)) + _tz(), true)
		col.add_child(UI.label("Ostatnio: %s · ziarno %s" % [played, str(int(w.get("seed", 0)))], 15, UI.MUTED))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var play := UI.button("Graj", func(): GameState.start(w.dir), true)
		play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(play)
		var del := UI.danger(UI.button("Usuń", func(): pass))
		del.pressed.connect(func():
			if del.text == "Usuń":
				del.text = "Na pewno?"
			else:
				GameState.delete_world(w.dir)
				show_load())
		row.add_child(del)
		col.add_child(row)
		content.add_child(card)
	content.add_child(UI.button("Wróć", show_main))


func _error(text: String) -> void:
	var l := UI.wrap(text, 16, UI.DANGER)
	content.add_child(l)
	content.move_child(l, 0)
	_fit.call_deferred()


## Gra wieloosobowa: nazwa gracza, założenie serwera na swoim świecie albo dołączenie do serwera.
func show_multiplayer() -> void:
	_screen()
	content.add_child(UI.label("Gra wieloosobowa", 30))
	content.add_child(UI.label("Twoja nazwa (widoczna nad głową)", 16, UI.MUTED))
	var name_edit := LineEdit.new()
	name_edit.text = Settings.player_name
	name_edit.max_length = 24
	name_edit.custom_minimum_size = Vector2(0, 48)
	name_edit.text_changed.connect(func(t):
		Settings.player_name = t.strip_edges() if not t.strip_edges().is_empty() else "Gracz"
		Settings.save_settings())
	content.add_child(name_edit)
	var status := UI.wrap("", 16, UI.LOCK)
	content.add_child(status)
	if not Net.status.is_connected(_on_net_status):
		Net.status.connect(_on_net_status)
	status.set_meta("net_status", true)

	content.add_child(UI.label("Dołącz do serwera", 22))
	var addr := LineEdit.new()
	addr.text = Settings.last_address
	addr.placeholder_text = "adres serwera, np. 192.168.1.10"
	addr.custom_minimum_size = Vector2(0, 48)
	content.add_child(addr)
	var port := LineEdit.new()
	port.text = str(Settings.last_port)
	port.custom_minimum_size = Vector2(0, 48)
	content.add_child(port)
	content.add_child(UI.button("Dołącz", func():
		Settings.last_address = addr.text.strip_edges()
		Settings.last_port = int(port.text) if port.text.is_valid_int() else Net.DEFAULT_PORT
		Settings.save_settings()
		var err := Net.join(Settings.last_address, Settings.last_port)
		if err != "":
			status.text = err, true))

	content.add_child(UI.label("Załóż serwer na swoim świecie", 22))
	content.add_child(UI.wrap("Inni gracze dołączają podając twój adres w sieci i port. Muszą mieć te same mody (włączy się u nich ten sam zestaw i ustawienia)."))
	var worlds := GameState.list_worlds()
	if worlds.is_empty():
		content.add_child(UI.wrap("Najpierw utwórz świat w „Nowy świat”."))
	for w in worlds:
		content.add_child(UI.button("Graj na serwerze: " + str(w.get("name", "Świat")), func():
			var pnum := int(port.text) if port.text.is_valid_int() else Net.DEFAULT_PORT
			var err := Net.host(pnum)
			if err != "":
				status.text = err
				return
			GameState.start(w.dir)))
	content.add_child(UI.button("Wróć", show_main))


func _on_net_status(text: String) -> void:
	for c in content.get_children():
		if c is Label and c.has_meta("net_status"):
			c.text = text


## Serwer bez okna: godot --headless --path game -- --server=nazwa_swiata [--port=7777] [--seed=123]
func _dedicated(world_name: String, args: PackedStringArray) -> void:
	var port := Net.DEFAULT_PORT
	var seed_text := ""
	for a in args:
		if a.begins_with("--port="):
			port = int(a.trim_prefix("--port="))
		if a.begins_with("--seed="):
			seed_text = a.trim_prefix("--seed=")
	var dir := ""
	for w in GameState.list_worlds():
		if str(w.get("name", "")) == world_name or str(w.dir).get_file() == world_name:
			dir = w.dir
	if dir.is_empty():
		dir = GameState.create_world(world_name, seed_text)
	var err := Net.host(port, true)
	if err != "":
		printerr(err)
		get_tree().quit(1)
		return
	print("SERWER świat=", dir, " port=", port)
	GameState.start(dir)


## Dołączenie z linii poleceń (testy): --join=adres:port
func _auto_join(target: String, args: PackedStringArray) -> void:
	for a in args:
		if a.begins_with("--name="):
			Settings.player_name = a.trim_prefix("--name=")
		if a.begins_with("--shots="):
			GameState.autotest_dir = a.trim_prefix("--shots=")
	var parts := target.split(":")
	var err := Net.join(parts[0], int(parts[1]) if parts.size() > 1 else Net.DEFAULT_PORT)
	if err != "":
		printerr(err)


func show_mods() -> void:
	_screen(true)
	var m := ModsScreen.new()
	m.on_back = show_main
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(m)


func show_options() -> void:
	_screen()
	var o := OptionsPanel.new()
	o.on_back = show_main
	content.add_child(o)


static func _gap(h: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


static func _tz() -> int:
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60


# ---------- tło: niebo i pikselowe wzgórza ----------

func _make_hills() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var layers := [[Color(0.47, 0.62, 0.74), 0.55, 18.0], [Color(0.33, 0.50, 0.40), 0.66, 14.0], [Color(0.24, 0.40, 0.25), 0.78, 10.0]]
	for l in layers:
		var hs := []
		var h := 0.0
		for i in 200:
			h = clampf(h + rng.randf_range(-1.0, 1.0), -3.0, 3.0)
			hs.append(h)
		hills.append([l[0], l[1], l[2], hs])


func _draw() -> void:
	var vs := size
	var steps := 24
	for i in steps:
		var c := Color(0.30, 0.52, 0.82).lerp(Color(0.72, 0.84, 0.94), float(i) / steps)
		draw_rect(Rect2(0, vs.y * i / steps, vs.x, vs.y / steps + 1), c)
	for l in hills:
		var px: float = l[2] * 2.0
		var cols := int(vs.x / px) + 2
		var hs: Array = l[3]
		for i in cols:
			var top: float = vs.y * l[1] + float(hs[i % hs.size()]) * px * 2.0
			draw_rect(Rect2(i * px, top, px + 1, vs.y - top), l[0])


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


# ---------- test automatyczny ----------

func _shot(dir: String, name: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT ", name)


func _autotest(dir: String) -> void:
	GameState.autotest_dir = dir
	await _shot(dir, "m1_menu")
	show_new_world()
	await _shot(dir, "m2_new_world")
	show_mods()
	await _shot(dir, "m3_mods")
	ModManager.apply_server_profile({"settings": {"base": {"hill_height": 1.4}}, "enabled": {"daynight": true}})
	show_mods()
	await _shot(dir, "m4_mods_server")
	ModManager.apply_server_profile({})
	ModManager.set_enabled("destructible", true)
	ModManager.set_value("destructible", "breakable", {"stone": false, "snow": false})
	show_mods()
	var ms: ModsScreen = content.get_child(0)
	ms.selected = "destructible"
	ms._refresh()
	await _shot(dir, "m4b_mods_blocks")
	ms.selected = "backpack"
	ms._refresh()
	await _shot(dir, "m4c_mods_backpack")
	ms.selected = "emotes"
	ms._refresh()
	await _shot(dir, "m4d_mods_emotes")
	show_options()
	await _shot(dir, "m5_options")
	var d := GameState.create_world("Test", "42")
	show_load()
	await _shot(dir, "m6_load")
	GameState.start(d)
