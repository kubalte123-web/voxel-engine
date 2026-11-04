extends Node3D
## Punkt startowy: niebo, światło, świat, gracz, interfejs i (opcjonalnie) automatyczny test.

var world: World
var player: Player
var hud: Hud
var touch: TouchControls
var sun: DirectionalLight3D


func _ready() -> void:
	_setup_input()
	var is_web := OS.has_feature("web")
	var touch_mode := DisplayServer.is_touchscreen_available()

	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.36, 0.58, 0.88)
	sky_mat.sky_horizon_color = Color(0.70, 0.82, 0.94)
	sky_mat.ground_horizon_color = Color(0.70, 0.82, 0.94)
	sky_mat.ground_bottom_color = Color(0.45, 0.55, 0.65)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.3
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_light_color = Color(0.70, 0.82, 0.94)
	env.fog_density = 0.008 if is_web else 0.0035
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	sun = DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -35, 0)
	sun.light_energy = 0.75
	sun.shadow_enabled = not is_web
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_normal_bias = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	world = World.new()
	add_child(world)

	player = Player.new()
	player.world = world
	add_child(player)
	player.respawn()
	world.update_center(player.global_position)

	var ui := CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.player = player
	hud.world = world
	hud.touch_mode = touch_mode
	ui.add_child(hud)
	if touch_mode:
		touch = TouchControls.new()
		touch.player = player
		ui.add_child(touch)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			_autotest(a.trim_prefix("--shots="))


func _process(_delta: float) -> void:
	world.update_center(player.global_position)


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "toggle_view": [KEY_V, KEY_F5],
		"slot_1": [KEY_1], "slot_2": [KEY_2], "slot_3": [KEY_3], "slot_4": [KEY_4], "slot_5": [KEY_5],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


# ---------- automatyczny test: zrzuty ekranu i pomiary ----------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(dir: String, name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT ", name)


func _autotest(dir: String) -> void:
	var t0 := Time.get_ticks_msec()
	while player.frozen or world.queued.size() > 0 or world.nodes.size() < 20:
		await _wait(0.2)
		if Time.get_ticks_msec() - t0 > 120000:
			break
	print("LOADED ms=", Time.get_ticks_msec() - t0, " ", world.stats())
	await _wait(1.0)
	await _shot(dir, "1_start")

	# idzie do przodu: ujęcie w trakcie kroku
	player.yaw = 0.9
	player.pitch = -0.25
	Input.action_press("move_forward")
	await _wait(1.3)
	await _shot(dir, "2_walk")
	Input.action_release("move_forward")
	await _wait(0.6)

	# kopanie i stawianie: patrzy w ziemię przed sobą
	player.pitch = -0.75
	await _wait(0.3)
	var before: Dictionary = player.target.duplicate()
	player.break_block()
	await _wait(0.2)
	player.break_block()
	await _wait(0.4)
	print("BREAK target=", before.get("pos"), " now=", world.get_block(before.get("pos", Vector3i.ZERO)))
	player.select(3)
	player.place_block()
	await _wait(0.6)
	await _shot(dir, "3_dig_place")

	# szeroki widok z góry
	player.spring.spring_length = 14.0
	player.pitch = -0.55
	player.yaw = 2.4
	await _wait(0.8)
	await _shot(dir, "4_wide")
	player.spring.spring_length = Player.ARM

	# pierwsza osoba
	player.toggle_view()
	player.pitch = -0.1
	await _wait(0.5)
	await _shot(dir, "5_first_person")
	player.toggle_view()

	# zbliżenie na postać od przodu
	player.yaw = player.model.rotation.y + PI
	player.pitch = -0.15
	player.spring.spring_length = 2.6
	await _wait(0.6)
	await _shot(dir, "6_character")
	print("FPS ", Engine.get_frames_per_second(), " ", world.stats())
	get_tree().quit()
