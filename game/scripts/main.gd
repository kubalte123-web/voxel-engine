extends Node3D
## Rozgrywka: niebo i dzień/noc, świat, gracz, interfejs, pauza, autozapis i test automatyczny.

var world: World
var far: FarTerrain
var entities: EntityManager
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
var tick_timer := 0.0
var windows := {}  # id okna moda -> ModWindow
var fog_base := 0.01
var was_underwater := false


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

	# faza 1 modów: rejestr bloków, przedmiotów i opisu świata
	var reg := Mods.start_content(GameState.current_dir)
	var seed_value := int(info.get("seed", 1337))
	var spec := WorldgenSpec.compile(reg.worldgen, reg, seed_value)
	world = World.new()
	world.setup(Terrain.new(seed_value, spec), GameState.current_dir, reg)
	# id bloków mogą się zmienić, gdy gracz włączy lub wyłączy mody: przeliczamy zapisane chunki
	var old_palette: Array = info.get("palette", [])
	if old_palette.is_empty() and int(info.get("version", 3)) < 3:
		old_palette = Blocks.LEGACY_KEYS
	if not old_palette.is_empty():
		var moved := world.migrate_palette(reg.remap_from(old_palette))
		if moved > 0:
			print("PALETA przeliczone chunki: ", moved)
	info["palette"] = reg.keys.duplicate()
	info["version"] = 3
	if not GameState.current_dir.is_empty():
		GameState.write_info(GameState.current_dir, info)
	add_child(world)
	far = FarTerrain.new()
	far.setup(world)
	add_child(far)

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
	entities = EntityManager.new()
	entities.name = "Entities"
	entities.setup(world, player)
	player.entities = entities
	add_child(entities)

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

	# faza 2 modów: skrypty, po zbudowaniu świata i gracza
	Mods.ui_window_requested.connect(_open_mod_window)
	Mods.ui_close_requested.connect(_close_mod_window)
	Mods.start_scripts(self)
	entities.load_from(GameState.current_dir)
	player.set_health(float(ps.get("health", player.stat("max_health"))))
	for e in spec.errors:
		hud.notify("Generator świata: " + str(e))
	for id in Mods.load_errors:
		hud.notify("Mod „%s” nie wczytał się: %s" % [ModManager.manifests.get(id, {}).get("name", id), str(Mods.load_errors[id]).left(120)])
	if touch:
		touch.refresh_binds()

	if not GameState.autotest_dir.is_empty():
		_autotest(GameState.autotest_dir)
	else:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shots="):
				_autotest(a.trim_prefix("--shots="))


func _apply_settings() -> void:
	world.set_radius(Settings.render_distance)
	far.set_radius(Settings.render_distance, Settings.far_view)
	world.water_material.set_shader_parameter("wave", 1.0 if Settings.water_waves else 0.0)
	player.camera.fov = Settings.fov
	player.mouse_sensitivity = 0.0028 * Settings.mouse_sensitivity
	sun.shadow_enabled = Settings.shadows and not OS.has_feature("web")
	var dist := maxf(Settings.render_distance * 32.0, far.radius_blocks)
	fog_base = 2.2 / dist
	env.fog_density = fog_base
	player.camera.far = dist + 64.0


func _process(delta: float) -> void:
	world.update_center(player.global_position)
	far.update_center(player.global_position)
	if daynight:
		time_of_day = fmod(time_of_day + delta * 24.0 / (day_minutes * 60.0), 24.0)
		_update_sky()
	_update_underwater()
	tick_timer -= delta
	if tick_timer <= 0.0:
		tick_timer = 0.1
		Mods.emit_event("tick", {"dt": 0.1, "time": time_of_day})
	autosave_timer -= delta
	if autosave_timer <= 0.0 and not GameState.current_dir.is_empty():
		autosave_timer = 60.0
		save_game()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and pause_menu == null and windows.is_empty():
		get_viewport().set_input_as_handled()
		open_pause()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := OS.get_keycode_string(event.physical_keycode).to_upper()
		for b in Mods.binds:
			if b.key == key:
				get_viewport().set_input_as_handled()
				Mods.press_bind(b.id)
				return


# ---------- okna modów ----------

func _open_mod_window(spec: Dictionary) -> void:
	var id := str(spec.get("id", ""))
	if windows.has(id):
		windows[id].build(spec)
		return
	var w := ModWindow.new()
	w.spec = spec
	w.closed.connect(_on_window_closed)
	ui.add_child(w)
	windows[id] = w
	player.ui_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_mod_window(id: String) -> void:
	if windows.has(id):
		windows[id].close()


func _on_window_closed(id: String) -> void:
	windows.erase(id)
	Mods.open_windows.erase(id)
	player.ui_blocked = not windows.is_empty()


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


## Widok pod wodą: gęsta mgła w kolorze cieczy i lekkie zabarwienie ekranu.
func _update_underwater() -> void:
	var under := player.eyes_in_liquid
	if under:
		var b := world.get_block(Vector3i(player.camera.global_position.floor()))
		var k := Blocks.reg.liquid_kind(b)
		var deep: Color = Blocks.reg.liquid_kinds[k].deep if k >= 0 else Color(0.05, 0.2, 0.4)
		env.fog_density = 0.09
		env.fog_light_color = deep.lightened(0.15)
		hud.tint = Color(deep.r, deep.g, deep.b, 0.28)
	elif was_underwater:
		env.fog_density = fog_base
		hud.tint = Color(0, 0, 0, 0)
		_update_sky()
	if under != was_underwater:
		Mods.emit_event("player.underwater", {"underwater": under})
	was_underwater = under


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
		Mods.stop()
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
	Mods.save_data(GameState.current_dir)
	entities.save(GameState.current_dir)
	var p := player.global_position
	info["player"] = {"pos": [p.x, p.y, p.z], "yaw": player.yaw, "pitch": player.pitch, "selected": player.selected,
		"health": player.health}
	info["palette"] = Mods.registry.keys.duplicate()
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


func _inv_total() -> int:
	var n := 0
	for c in ["hotbar", "backpack"]:
		for sl in Mods.container_slots(c):
			n += int(sl.get("count", 0))
	return n


func _find_biome(biome: int) -> Vector2i:
	var t := world.terrain
	for r in range(0, 4000, 48):
		for k in 16:
			var a := k * TAU / 16.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			var c := t.column(x, z)
			if c.y == biome and c.x > 8 and t.column(x + 24, z).y == biome and t.column(x, z + 24).y == biome:
				return Vector2i(x, z)
	return Vector2i(999999, 0)


## Szuka kolumny ze strukturą (element rodzaju 3) w pobliżu startu.
func _find_structure() -> Vector3i:
	var t := world.terrain
	for r in range(0, 1500, 4):
		for k in 32:
			var a := k * TAU / 32.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			if Terrain.hash01(x, z, t.seed_value, 1) >= t.max_sum:
				continue
			var c := t.column(x, z)
			var f := t.feature_at(x, z, c.x, c.y)
			if f >= 0 and int(t.F[f * Terrain.FS + 1]) == 3:
				return Vector3i(x, c.x, z)
	return Vector3i(999999, 0, 0)


func _find_lake() -> Vector3i:
	var t := world.terrain
	for r in range(0, 900, 6):
		for k in 24:
			var a := k * TAU / 24.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			if t.height(x, z) < t.sea - 2 and t.height(x + 3, z) < t.sea - 1 and t.height(x, z + 3) < t.sea - 1:
				return Vector3i(x, t.height(x, z), z)
	return Vector3i(999999, 0, 0)


func _water_volume(center: Vector3i, r: int) -> Array:
	var vol := 0
	var cells := 0
	for x in range(center.x - r, center.x + r + 1):
		for z in range(center.z - r, center.z + r + 1):
			for y in range(center.y - 4, center.y + 6):
				var b := world.get_block(Vector3i(x, y, z))
				if Blocks.reg.is_liquid(b):
					vol += Blocks.reg.liquid_level(b)
					cells += 1
	return [vol, cells]


func _look_at_point(p: Vector3) -> void:
	var to := p - (player.global_position + Vector3(0, 1.55, 0))
	player.yaw = atan2(-to.x, -to.z)
	player.pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.4, 1.1)


func _test_stage5(dir: String) -> void:
	var reg := Blocks.reg
	# twardość: czas kopania
	print("KOPANIE czas [s]: ziemia=", reg.hardness[Blocks.id("dirt")], " kamień=", reg.hardness[Blocks.id("stone")], " woda=", reg.hardness[Blocks.id("water")])
	# woda wylana na płaskim terenie: objętość się zachowuje (8 poziomów = 1 blok)
	var p0 := Vector3i(player.global_position.floor())
	var spot := p0 + Vector3i(4, 0, 0)
	var gy := entities._surface(spot.x, spot.z, p0.y + 6)
	var pour := Vector3i(spot.x, gy + 3, spot.z)
	world.set_block(pour, Blocks.id("water~8"))
	world.set_block(pour + Vector3i(0, 0, 1), Blocks.id("water~8"))
	await _wait(0.4)
	var v1 := _water_volume(Vector3i(spot.x, gy, spot.z), 6)
	await _wait(3.0)
	var v2 := _water_volume(Vector3i(spot.x, gy, spot.z), 6)
	print("WODA wylane=16 po 0.4 s=", v1, " po 3.4 s=", v2, " zmian symulacji=", world.liquids.moved_total)
	_look_at_point(Vector3(spot.x, gy, spot.z))
	await _wait(0.3)
	await _shot(dir, "g10_water_poured")
	# grawitacja: piasek w powietrzu spada
	var sand_at := Vector3i(spot.x - 2, gy + 4, spot.z - 2)
	world.set_block(sand_at, Blocks.id("sand"))
	await _wait(2.0)
	var landed := -1
	for y in range(gy - 2, gy + 6):
		if world.get_block(Vector3i(sand_at.x, y, sand_at.z)) == Blocks.id("sand"):
			landed = y
	print("GRAWITACJA piasek z y=", sand_at.y, " wylądował na y=", landed, " (teren ", gy, ")")

	# jezioro: obiekty luźne pływają albo toną, gracz pływa
	var lake := _find_lake()
	if lake.x != 999999:
		var sea := world.terrain.sea
		await _goto(lake.x + 0.5, sea + 1.5, lake.z + 6.5)
		await _wait(0.5)
		var ids := {}
		for k in ["crate", "barrel", "ball", "boulder"]:
			ids[k] = entities.spawn_prop(Blocks.id(k), Vector3(lake.x + 0.5 + ids.size() * 1.3 - 2.0, sea + 2.5, lake.z + 0.5), Vector3.ZERO)
		await _wait(5.0)
		var ys := {}
		for k in ids:
			var e := entities.get_entity(ids[k])
			ys[k] = snappedf(e.global_position.y, 0.01) if e else "brak"
		print("PŁYWANIE poziom wody=", sea + 1, " wysokości obiektów: ", ys)
		_look_at_point(Vector3(lake.x + 0.5, sea + 1, lake.z + 0.5))
		player.global_position.y = sea + 3.0
		await _wait(0.5)
		await _shot(dir, "g11_lake_props")
		# pod wodą
		player.global_position = Vector3(lake.x + 0.5, sea - 1.2, lake.z + 3.5)
		player.velocity = Vector3.ZERO
		player.first_person = true
		await _wait(0.6)
		print("PŁYWA gracz w cieczy=", player.in_liquid, " oczy pod wodą=", player.eyes_in_liquid)
		await _shot(dir, "g12_underwater")
		player.first_person = false
		await _wait(1.5)
	else:
		print("JEZIORO nie znaleziono")

	# zwierzęta: czekamy, aż się pojawią, i patrzymy na najbliższe
	await _goto(0.5, world.terrain.height(0, 0) + 2.0, 0.5)
	var t0 := Time.get_ticks_msec()
	while entities.list().size() < 4 and Time.get_ticks_msec() - t0 < 30000:
		await _wait(0.5)
	var by_type := {}
	for id in entities.list():
		var c: Creature = entities.get_entity(id)
		by_type[c.type] = by_type.get(c.type, 0) + 1
	print("ZWIERZĘTA ", by_type)
	for type in ["sheep", "cow", "chicken"]:
		var lst := entities.list(type)
		if lst.is_empty():
			continue
		var c: Creature = entities.get_entity(lst[0])
		for id in lst:
			var cc: Creature = entities.get_entity(id)
			if cc.scale_factor >= 1.0:
				c = cc
				break
		var cp := c.global_position
		var hh := world.terrain.height(floori(cp.x) + 2, floori(cp.z) + 2)
		await _goto(cp.x + 2.2, maxf(cp.y, hh + 1.0) + 0.5, cp.z + 2.2)
		Mods.camera_stats["mode"] = "first"
		for i in 6:
			await _wait(0.25)
			cp = c.global_position
			_look_at_point(cp + Vector3(0, 0.3, 0))
		await _shot(dir, "g13_animal_" + type)
		Mods.camera_stats.erase("mode")
		if type == "sheep":
			var before := _inv_total()
			Mods.set_slot("backpack", 20, {"item": "shears", "count": 1})
			player.select(7)
			var ctx := Mods.before("entity.interact", {"id": c.id, "type": "sheep", "item": "shears", "slot": 8})
			await _wait(2.0)
			print("STRZYŻENIE ostrzyżona=", c.data.get("sheared", false), " wełna na ziemi/plecaku: przed=", before, " po=", _inv_total())
			var hp := c.health
			c.hit(2.0, player.global_position, "test")
			print("UDERZENIE zdrowie owcy ", hp, " -> ", c.health, " stan=", c.state)

	# jaskinia: kolumna z pustką pod powierzchnią
	var cave := Vector3i(999999, 0, 0)
	for x in range(-60, 60, 3):
		for z in range(-60, 60, 3):
			var h := world.terrain.height(x, z)
			for y in range(h - 30, h - 6):
				if world.is_loaded(Vector3i(x, y, z)) and world.get_block(Vector3i(x, y, z)) == Blocks.AIR \
						and world.get_block(Vector3i(x, y + 1, z)) == Blocks.AIR and world.get_block(Vector3i(x, y - 1, z)) != Blocks.AIR:
					cave = Vector3i(x, y, z)
					break
			if cave.x != 999999:
				break
		if cave.x != 999999:
			break
	if cave.x != 999999:
		player.global_position = Vector3(cave.x + 0.5, cave.y + 0.05, cave.z + 0.5)
		player.velocity = Vector3.ZERO
		Mods.camera_stats["distance"] = 2.0
		player.pitch = -0.1
		await _wait(1.0)
		await _shot(dir, "g14_cave")
		Mods.camera_stats.erase("distance")
		print("JASKINIA w ", cave)

	# daleki widok z wysoka
	var hz := world.terrain.height(0, 0)
	Mods.player_stats["gravity"] = 0.0
	await _goto(0.5, hz + 30.0, 0.5)
	player.velocity = Vector3.ZERO
	player.pitch = -0.12
	player.yaw = 0.9
	await _wait(3.0)
	await _shot(dir, "g15_far_view")
	print("DALEKI WIDOK kafle=", far.tiles.size())
	Mods.player_stats.erase("gravity")
	player.respawn()


func _goto(x: float, y: float, z: float) -> void:
	player.global_position = Vector3(x, y, z)
	player.velocity = Vector3.ZERO
	player.frozen = true
	player.reset_fall()
	world.update_center(player.global_position)
	await _wait_loaded()


func _autotest(dir: String) -> void:
	Settings.render_distance = 4
	_apply_settings()
	await _wait_loaded()
	await _wait(1.0)
	await _shot(dir, "g1_start")

	print("MODS loaded=", Mods.loaded, " errors=", Mods.load_errors, " binds=", Mods.binds.size())
	print("REJESTR bloki=", Mods.registry.count(), " przedmioty=", Mods.registry.items.size(), " biomy=", world.terrain.biome_names)
	# kopanie i stawianie przez haki modów (plecak dostaje łup bloku, stawianie zużywa przedmiot)
	player.pitch = -0.75
	await _wait(0.3)
	var target: Dictionary = player.target.duplicate()
	var before_inv := _inv_total()
	player.break_block()
	await _wait(0.4)
	var dug: Vector3i = target.get("pos", Vector3i.ZERO)
	print("BREAK pos=", dug, " now=", world.get_block(dug), " plecak przed=", before_inv, " po=", _inv_total())
	player.select(0)
	var planks_before := int(Mods.hotbar_item(0).get("count", 0))
	var place_at: Vector3i = player.target.pos + player.target.normal if not player.target.is_empty() else Vector3i.ZERO
	player.use_item()
	await _wait(0.4)
	print("PLACE at=", place_at, " block=", Blocks.key(world.get_block(place_at)), " deski przed=", planks_before, " po=", int(Mods.hotbar_item(0).get("count", 0)))
	var stone_try := Mods.before("block.break", {"pos": dug, "block": Blocks.id("stone"), "drops": []})
	print("DESTRUCTIBLE kamień anulowany=", stone_try.get("cancel", false))
	# przetrwanie: upadek zadaje obrażenia, jedzenie przy pełnym żołądku jest anulowane
	var hp := player.health
	Mods.emit_event("player.land", {"fall": 6.0, "speed": 12.0})
	print("FALL zdrowie przed=", hp, " po=", player.health)
	Mods.set_slot("hotbar", 2, {"item": "apple", "count": 3})
	var eat := Mods.before("item.use", {"item": "apple", "slot": 3})
	print("ITEM.USE jabłko anulowane (pełny żołądek)=", eat.get("cancel", false))
	Mods.press_bind("backpack:toggle")
	await _wait(0.8)
	await _shot(dir, "g5_backpack")
	if windows.has("character"):
		windows["character"]._click("hotbar", 0, false)
		windows["character"]._click("backpack", 4, false)
		await _wait(0.4)
		await _shot(dir, "g6_backpack_moved")
		windows["character"].close()
	await _wait(0.3)
	var n := world.save_all()
	var check := World.new()
	check.save_dir = GameState.current_dir
	check._load_chunk(World.chunk_of(dug))
	var d: Variant = check.data.get(World.chunk_of(dug))
	var l := dug - World.chunk_of(dug) * World.S
	print("SAVE chunks=", n, " reloaded_block=", Blocks.key(d[l.x + 32 * (l.y + 32 * l.z)]) if d != null else "brak")
	check.free()

	# wystawa nowych bloków przed graczem, gest i tryby kamery
	var p0 := Vector3i(player.global_position.floor())
	var show := ["glass", "bricks", "cobblestone", "coal_ore", "iron_ore", "ruby_ore"]
	var fwd := Vector3i(roundi(-sin(player.yaw) * 3), 0, roundi(-cos(player.yaw) * 3))
	var side := Vector3i(roundi(cos(player.yaw)), 0, roundi(-sin(player.yaw)))
	for i in show.size():
		var id := Blocks.id(show[i])
		if id > 0:
			world.set_block(p0 + fwd + side * (i - 2) + Vector3i(0, 1, 0), id)
			world.set_block(p0 + fwd + side * (i - 2) + Vector3i(0, 2, 0), id)
	var cc := World.chunk_of(p0 + fwd + Vector3i(0, 1, 0))
	var vc_before: int = (world.nodes[cc].mesh as ArrayMesh).surface_get_array_len(0) if world.nodes.has(cc) else -1
	await _wait(1.0)
	var vc_after: int = (world.nodes[cc].mesh as ArrayMesh).surface_get_array_len(0) if world.nodes.has(cc) else -1
	print("REMESH chunk ", cc, " wierzchołki przed=", vc_before, " po=", vc_after, " blok=", Blocks.key(world.get_block(p0 + fwd + Vector3i(0, 1, 0))))
	player.pitch = -0.2
	Mods.press_bind("emotes:wave")
	await _wait(0.5)
	await _shot(dir, "g7_blocks_wave")
	for m in ["shoulder", "top"]:
		Mods.press_bind("emotes:camera")
		await _wait(0.8)
		await _shot(dir, "g8_camera_" + m)
	Mods.camera_stats.erase("mode")

	# rudy w załadowanych chunkach
	var ore_counts := {}
	for k in ["coal_ore", "iron_ore", "ruby_ore"]:
		var id := Blocks.id(k)
		for c in world.data:
			ore_counts[k] = ore_counts.get(k, 0) + (world.data[c] as PackedByteArray).count(id)
	print("ORES ", ore_counts)

	await _test_stage5(dir)

	# struktura (ruiny albo studnia)
	var st := _find_structure()
	if st.x != 999999:
		await _goto(st.x + 6.5, st.y + 4.0, st.z + 6.5)
		await _wait(0.8)
		Mods.camera_stats["distance"] = 8.0
		player.yaw = 0.8
		player.pitch = -0.6
		await _wait(0.6)
		await _shot(dir, "g9_structure")
		Mods.camera_stats.erase("distance")
		print("STRUCTURE at ", st, " biom ", world.terrain.biome_name(world.terrain.column(st.x, st.z).y))
	else:
		print("STRUCTURE nie znaleziono")

	# wycieczka po biomach
	for b in world.terrain.nb:
		var at := _find_biome(b)
		if at.x == 999999:
			print("BIOME ", world.terrain.biome_name(b), " nie znaleziono")
			continue
		var h := world.terrain.height(at.x, at.y)
		await _goto(at.x + 0.5, h + 2.0, at.y + 0.5)
		await _wait(0.8)
		Mods.camera_stats["distance"] = 9.0
		player.pitch = -0.3
		player.yaw = 0.8
		await _wait(0.6)
		await _shot(dir, "g2_biome_%d" % b)
		Mods.camera_stats.erase("distance")
		print("BIOME ", world.terrain.biome_name(b), " at ", at)

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
