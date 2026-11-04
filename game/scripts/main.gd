extends Node3D
## Rozgrywka: niebo i dzień/noc, świat, gracz, interfejs, pauza, autozapis i test automatyczny.

var world: World
var player: Player
var hud: Hud
var touch: TouchControls
var pause_menu: PauseMenu
var ui: CanvasLayer
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial

var info := {}
var time_of_day := 8.0       # godzina 0..24
var daynight := false
var day_minutes := 20.0
var dark_nights := false
var autosave_timer := 60.0


func _ready() -> void:
	_setup_input()
	var touch_mode := DisplayServer.is_touchscreen_available()
	info = GameState.current
	if info.is_empty():
		# uruchomienie sceny bez menu: świat tymczasowy
		info = {"name": "Tymczasowy", "seed": 1337, "mods": {"base": ModManager.snapshot("base")}}

	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_normal_bias = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	world = World.new()
	var base_opts: Dictionary = info.get("mods", {}).get("base", ModManager.snapshot("base"))
	world.setup(int(info.get("seed", 1337)), base_opts, GameState.current_dir)
	add_child(world)

	player = Player.new()
	player.world = world
	add_child(player)
	var ps: Dictionary = info.get("player", {})
	if ps.has("pos"):
		player.global_position = Vector3(ps.pos[0], ps.pos[1], ps.pos[2])
		player.yaw = ps.get("yaw", player.yaw)
		player.pitch = ps.get("pitch", player.pitch)
		player.selected = int(ps.get("selected", 0))
	else:
		player.respawn()
	world.update_center(player.global_position)

	daynight = ModManager.is_enabled("daynight")
	day_minutes = float(ModManager.get_value("daynight", "day_minutes"))
	dark_nights = bool(ModManager.get_value("daynight", "dark_nights"))
	var tod := float(info.get("time_of_day", -1.0))
	time_of_day = tod if tod >= 0.0 else float(ModManager.get_value("daynight", "start_hour"))
	if not daynight:
		time_of_day = 10.0
	_update_sky()

	ui = CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.player = player
	hud.world = world
	hud.main = self
	hud.touch_mode = touch_mode
	ui.add_child(hud)
	if touch_mode:
		touch = TouchControls.new()
		touch.player = player
		touch.main = self
		ui.add_child(touch)

	Settings.changed.connect(_apply_settings)
	_apply_settings()

	if not GameState.autotest_dir.is_empty():
		_autotest(GameState.autotest_dir)
	else:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shots="):
				_autotest(a.trim_prefix("--shots="))


func _apply_settings() -> void:
	world.set_radius(Settings.render_distance)
	player.camera.fov = Settings.fov
	player.mouse_sensitivity = 0.0028 * Settings.mouse_sensitivity
	sun.shadow_enabled = Settings.shadows and not OS.has_feature("web")
	var far := Settings.render_distance * 32.0
	env.fog_density = 2.2 / far
	player.camera.far = far + 64.0


func _process(delta: float) -> void:
	world.update_center(player.global_position)
	if daynight:
		time_of_day = fmod(time_of_day + delta * 24.0 / (day_minutes * 60.0), 24.0)
		_update_sky()
	autosave_timer -= delta
	if autosave_timer <= 0.0 and not GameState.current_dir.is_empty():
		autosave_timer = 60.0
		save_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and pause_menu == null:
		get_viewport().set_input_as_handled()
		open_pause()


## Słońce, kolory nieba, światło otoczenia i mgła w zależności od godziny.
func _update_sky() -> void:
	var angle := (time_of_day - 6.0) / 24.0 * TAU   # 6:00 wschód, 12:00 zenit, 18:00 zachód
	var elev := sin(angle)
	sun.rotation = Vector3(-asin(clampf(elev, -1.0, 1.0)) if elev > 0.0 else -0.15, -0.6 + angle * 0.15, 0)
	var day := Terrain.sm(-0.12, 0.25, elev)
	var dusk := clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0) * (1.0 if elev > -0.25 else 0.0)
	var night_top := Color(0.03, 0.05, 0.12) if dark_nights else Color(0.08, 0.12, 0.25)
	var night_hor := Color(0.06, 0.08, 0.16) if dark_nights else Color(0.14, 0.20, 0.34)
	var top := night_top.lerp(Color(0.36, 0.58, 0.88), day)
	var hor := night_hor.lerp(Color(0.70, 0.82, 0.94), day).lerp(Color(0.95, 0.62, 0.40), dusk * 0.6)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.4)
	sun.light_energy = 0.75 * day
	sun.light_color = Color(1, 1, 1).lerp(Color(1.0, 0.72, 0.5), dusk)
	sun.visible = day > 0.01
	env.ambient_light_energy = lerpf(0.08 if dark_nights else 0.2, 0.3, day)
	env.fog_light_color = hor


func time_text() -> String:
	return "%02d:%02d" % [int(time_of_day), int(fmod(time_of_day, 1.0) * 60.0)]


# ---------- pauza i zapis ----------

func open_pause() -> void:
	if pause_menu != null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu = PauseMenu.new()
	pause_menu.resume.connect(close_pause)
	pause_menu.save_and_exit.connect(func():
		save_game()
		GameState.back_to_menu())
	ui.add_child(pause_menu)
	get_tree().paused = true


func close_pause() -> void:
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false


func save_game() -> void:
	if GameState.current_dir.is_empty():
		return
	world.save_all()
	var p := player.global_position
	info["player"] = {"pos": [p.x, p.y, p.z], "yaw": player.yaw, "pitch": player.pitch, "selected": player.selected}
	info["time_of_day"] = time_of_day
	info["played"] = int(Time.get_unix_time_from_system())
	GameState.current = info
	GameState.write_info(GameState.current_dir, info)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "toggle_view": [KEY_V, KEY_F5],
	}
	for i in 9:
		keys["slot_%d" % (i + 1)] = [KEY_1 + i]
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


# ---------- test automatyczny: zrzuty ekranu i pomiary ----------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT ", name)


func _wait_loaded() -> void:
	var t0 := Time.get_ticks_msec()
	while player.frozen or world.queued.size() > 0 or world.nodes.size() < 12:
		await _wait(0.2)
		if Time.get_ticks_msec() - t0 > 120000:
			break
	print("LOADED ms=", Time.get_ticks_msec() - t0, " ", world.stats())


func _find_biome(biome: int) -> Vector2i:
	for r in range(0, 4000, 48):
		for k in 16:
			var a := k * TAU / 16.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			var c := world.terrain.column(x, z)
			if c.y == biome and c.x > 8 and world.terrain.column(x + 24, z).y == biome and world.terrain.column(x, z + 24).y == biome:
				return Vector2i(x, z)
	return Vector2i(999999, 0)


func _autotest(dir: String) -> void:
	Settings.render_distance = 4
	_apply_settings()
	await _wait_loaded()
	await _wait(1.0)
	await _shot(dir, "g1_start")

	# kopanie i stawianie, a potem sprawdzenie zapisu
	player.pitch = -0.75
	await _wait(0.3)
	var target: Dictionary = player.target.duplicate()
	player.break_block()
	await _wait(0.4)
	var dug: Vector3i = target.get("pos", Vector3i.ZERO)
	print("BREAK pos=", dug, " now=", world.get_block(dug))
	player.select(3)
	player.place_block()
	await _wait(0.4)
	var n := world.save_all()
	var check := World.new()
	check.save_dir = GameState.current_dir
	check._load_chunk(World.chunk_of(dug))
	var d: Variant = check.data.get(World.chunk_of(dug))
	var l := dug - World.chunk_of(dug) * World.S
	print("SAVE chunks=", n, " reloaded_block=", d[l.x + 32 * (l.y + 32 * l.z)] if d != null else "brak")
	check.free()

	# wycieczka po biomach
	for b in [Terrain.MEADOW, Terrain.FOREST, Terrain.DESERT, Terrain.SNOWY]:
		var at := _find_biome(b)
		if at.x == 999999:
			print("BIOME ", Terrain.BIOME_NAMES[b], " nie znaleziono")
			continue
		var h := world.terrain.height(at.x, at.y)
		player.global_position = Vector3(at.x + 0.5, h + 2.0, at.y + 0.5)
		player.velocity = Vector3.ZERO
		player.frozen = true
		world.update_center(player.global_position)
		await _wait_loaded()
		await _wait(0.8)
		player.spring.spring_length = 9.0
		player.pitch = -0.3
		player.yaw = 0.8
		await _wait(0.6)
		await _shot(dir, "g2_biome_%d" % b)
		player.spring.spring_length = Player.ARM
		print("BIOME ", Terrain.BIOME_NAMES[b], " at ", at)

	# zmierzch (dzień i noc)
	if daynight:
		time_of_day = 18.6
		_update_sky()
		await _wait(0.5)
		await _shot(dir, "g3_dusk")
		time_of_day = 10.0
		_update_sky()

	open_pause()
	await _wait(0.5)
	await _shot(dir, "g4_pause")
	close_pause()
	print("FPS ", Engine.get_frames_per_second(), " ", world.stats())
	get_tree().quit()
