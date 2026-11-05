extends Node
## Podgląd animacji postaci: klatki z boku (z prawej strony postaci) i z przodu do jednego obrazka.
## Uruchom (z oknem, np. xvfb-run): godot --path game res://tools/anim_preview.tscn -- --out=plik.png --poses=a,b,c
## Pozy: nazwa akcji/postawy; każda w 4 chwilach czasu.

var vp: SubViewport
var model: CharacterModel


func _ready() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var out := "/tmp/anim.png"
	var poses: PackedStringArray = ["stand"]
	var held := ""
	for a in args:
		if a.begins_with("--out="):
			out = a.trim_prefix("--out=")
		if a.begins_with("--poses="):
			poses = a.trim_prefix("--poses=").split(",")
		if a.begins_with("--held="):
			held = a.trim_prefix("--held=")   # przedmiot w ręce (wczytuje mody)
	if held != "":
		ModManager.scan()
		Mods.start_content("")
	vp = SubViewport.new()
	vp.size = Vector2i(220, 260)
	vp.own_world_3d = true
	vp.transparent_bg = false
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.55, 0.7, 0.85)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.7, 0.7, 0.75)
	vp.add_child(env)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	vp.add_child(light)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4, 4)
	ground.mesh = pm
	vp.add_child(ground)
	var cam := Camera3D.new()
	vp.add_child(cam)
	model = CharacterModel.new()
	vp.add_child(model)
	await get_tree().process_frame
	var cols := 4
	var sheet := Image.create(220 * cols * 2, 260 * poses.size(), false, Image.FORMAT_RGBA8)
	for pi in poses.size():
		var spec := poses[pi].split(":")
		var pose := spec[0]
		if held != "":
			# pozy z przedmiotem: "dig@iron_pickaxe" albo dla wszystkich --held=
			var item := held
			if "@" in pose:
				item = pose.get_slice("@", 1)
				pose = pose.get_slice("@", 0)
			model.set_held(item)
		var speed := float(spec[1]) if spec.size() > 1 else 0.0
		var step_t := float(spec[2]) if spec.size() > 2 else 0.12
		for side in 2:
			# kamera z prawego boku postaci (+X) albo od przodu (-Z)
			cam.position = Vector3(3.2, 1.0, 0) if side == 0 else Vector3(0, 1.0, -3.2)
			cam.look_at(Vector3(0, 0.8, 0))
			model.reset_pose()
			for c in cols:
				var tt := c * step_t
				model.preview(pose, speed, tt)
				await get_tree().process_frame
				await get_tree().process_frame
				var img := vp.get_texture().get_image()
				img.convert(Image.FORMAT_RGBA8)
				sheet.blit_rect(img, Rect2i(0, 0, 220, 260), Vector2i((side * cols + c) * 220, pi * 260))
	sheet.save_png(out)
	print("PODGLĄD ", out)
	get_tree().quit()
