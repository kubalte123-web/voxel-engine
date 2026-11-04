class_name Player
extends CharacterBody3D
## Gracz: ruch, kamera (tryby: third, first, shoulder, top), kopanie i stawianie bloków,
## używanie przedmiotów, zdrowie, upadki i odrodzenie. Prawie wszystko przechodzi przez haki modów.

signal selection_changed(index: int)
signal health_changed(value: float, max_value: float)
signal died(cause: String)

var world: World
var entities: EntityManager
var model: CharacterModel
var pivot: Node3D
var spring: SpringArm3D
var camera: Camera3D
var highlight: MeshInstance3D

var yaw := 0.6
var pitch := -0.35
var first_person := false
var mouse_sensitivity := 0.0028
var touch_move := Vector2.ZERO   # z joysticka dotykowego
var touch_jump := false
var selected := 0
var target: Dictionary = {}
var frozen := true
var ui_blocked := false  # otwarte okno moda: gracz nie reaguje na mysz
var health := 20.0
var in_liquid := false     # ciało w cieczy (pływanie)
var eyes_in_liquid := false
var digging := false       # przycisk kopania wciśnięty
var dig_pos := Vector3i(0, -99999, 0)
var dig_time := 0.0        # ile sekund trzeba kopać bieżący blok (-1 = nie da się)
var dig_progress := 0.0
var dig_cooldown := 0.0
var swing_timer := 0.0
var light_timer := 0.0
var crack: MeshInstance3D
static var crack_mats: Array[StandardMaterial3D] = []
var fall_top := 0.0      # najwyższy punkt od oderwania od ziemi
var was_on_floor := true
var _rng := RandomNumberGenerator.new()

const SPEED := 4.6
const JUMP := 7.6
const GRAVITY := 24.0
const REACH := 6.0
const ARM := 4.2
const MAX_HEALTH := 20.0
const CAMERA_MODES := {
	"third": {"distance": 4.2, "height": 1.55, "side": 0.0},
	"first": {"distance": 0.0, "height": 1.6, "side": 0.0},
	"shoulder": {"distance": 2.4, "height": 1.65, "side": 0.75},
	"top": {"distance": 15.0, "height": 1.0, "side": 0.0, "pitch": -1.05},
}


func _ready() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.8, 0.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)
	floor_snap_length = 0.3
	collision_layer = 8          # gracz
	collision_mask = 1 | 4       # świat i obiekty luźne (stworzenia przechodzą obok)

	model = CharacterModel.new()
	add_child(model)

	pivot = Node3D.new()
	pivot.position.y = 1.55
	add_child(pivot)
	spring = SpringArm3D.new()
	spring.spring_length = ARM
	spring.margin = 0.2
	spring.add_excluded_object(get_rid())
	pivot.add_child(spring)
	camera = Camera3D.new()
	camera.fov = 72.0
	camera.far = 400.0
	spring.add_child(camera)

	highlight = MeshInstance3D.new()
	highlight.mesh = _wire_cube()
	var hm := StandardMaterial3D.new()
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hm.albedo_color = Color(0.05, 0.05, 0.05)
	highlight.material_override = hm
	highlight.visible = false
	highlight.top_level = true
	add_child(highlight)

	crack = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3.ONE * 1.006
	crack.mesh = bm
	crack.top_level = true
	crack.visible = false
	crack.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(crack)
	if crack_mats.is_empty():
		crack_mats = _make_crack_materials()


## Pięć etapów pęknięć rysowanych w kodzie: coraz więcej ciemnych rys.
static func _make_crack_materials() -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	for stage in 5:
		for line in 3 + stage * 2:
			var x := rng.randi_range(2, 13)
			var y := rng.randi_range(2, 13)
			for k in 2 + stage:
				img.set_pixel(clampi(x, 0, 15), clampi(y, 0, 15), Color(0.05, 0.04, 0.03, 0.85))
				x += rng.randi_range(-1, 1)
				y += rng.randi_range(-1, 1)
		var m := StandardMaterial3D.new()
		m.albedo_texture = ImageTexture.create_from_image(img.duplicate())
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		out.append(m)
	return out


static func _wire_cube() -> ArrayMesh:
	var e := 0.004
	var a := -e
	var b := 1.0 + e
	var p := [Vector3(a, a, a), Vector3(b, a, a), Vector3(b, a, b), Vector3(a, a, b),
		Vector3(a, b, a), Vector3(b, b, a), Vector3(b, b, b), Vector3(a, b, b)]
	var pairs := [0, 1, 1, 2, 2, 3, 3, 0, 4, 5, 5, 6, 6, 7, 7, 4, 0, 4, 1, 5, 2, 6, 3, 7]
	var v := PackedVector3Array()
	for i in pairs:
		v.append(p[i])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	return m


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	# zdarzenia myszy udawane z dotyku obsługuje sterowanie dotykowe, nie gracz
	if (event is InputEventMouse) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if ui_blocked:
		return
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			start_digging()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			use_item()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select((selected + hotbar_size() - 1) % hotbar_size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select((selected + 1) % hotbar_size())
	elif event is InputEventMouseButton and not event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		stop_digging()
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * mouse_sensitivity)
	elif event.is_action_pressed("toggle_view"):
		toggle_view()
	else:
		for i in mini(hotbar_size(), 9):
			if event.is_action_pressed("slot_%d" % (i + 1)):
				select(i)


func look(delta: Vector2) -> void:
	yaw -= delta.x
	pitch = clampf(pitch - delta.y, float(Mods.camera_stats.get("pitch_min", -1.45)), float(Mods.camera_stats.get("pitch_max", 1.2)))


func select(i: int) -> void:
	selected = i
	selection_changed.emit(i)


## Klawisz V przełącza widok z trzeciej osoby na pierwszą i z powrotem (zdejmuje tryb ustawiony przez mod).
func toggle_view() -> void:
	if Mods.camera_stats.has("mode"):
		Mods.camera_stats.erase("mode")
		first_person = false
	else:
		first_person = not first_person


func camera_mode() -> String:
	var m := str(Mods.camera_stats.get("mode", ""))
	if CAMERA_MODES.has(m):
		return m
	return "first" if first_person else "third"


func _cam(key: String) -> float:
	var mode: Dictionary = CAMERA_MODES[camera_mode()]
	if Mods.camera_stats.has(key):
		return float(Mods.camera_stats[key])
	return float(mode.get(key, 0.0))


## Statystyki gracza: wartość domyślna albo nadpisana przez mod (engine.player.set).
func stat(name: String) -> Variant:
	var defaults := {"speed": SPEED, "jump": JUMP, "gravity": GRAVITY, "reach": REACH, "auto_jump": true,
		"max_health": MAX_HEALTH, "spawn": null, "break_speed": 1.0, "swim_speed": 1.0}
	return Mods.player_stats.get(name, defaults.get(name))


func hotbar_size() -> int:
	if Mods.hotbar.container != "":
		return Mods.hotbar.count
	return clampi(Blocks.reg.placeable.size(), 1, 9)


## Przedmiot wybrany na pasku: {item, count} z kontenera moda albo z listy bloków (tryb kreatywny).
func current_item() -> Dictionary:
	var sl: Variant = Mods.hotbar_item(selected)
	if sl == null:
		var list := Blocks.reg.placeable
		if list.is_empty():
			return {}
		return {"item": list[selected % list.size()], "count": 1}
	return sl


func current_block() -> int:
	var it := current_item()
	if it.is_empty():
		return 0
	return maxi(0, Blocks.reg.item_block(str(it.item)))


func _update_camera(delta: float) -> void:
	var mode := camera_mode()
	var cam := {"mode": mode, "yaw": yaw, "pitch": pitch, "distance": _cam("distance"), "height": _cam("height"),
		"side": _cam("side"), "fov_offset": float(Mods.camera_stats.get("fov_offset", 0.0))}
	if CAMERA_MODES[mode].has("pitch") and not Mods.camera_stats.has("pitch"):
		cam.pitch = CAMERA_MODES[mode].pitch
	elif Mods.camera_stats.has("pitch"):
		cam.pitch = float(Mods.camera_stats.pitch)
	if Mods.has_hook("after", "camera.update"):
		cam = Mods.after("camera.update", cam)
	pivot.position = Vector3(0, float(cam.height), 0) + Vector3(cos(yaw), 0, -sin(yaw)) * float(cam.side)
	pivot.rotation = Vector3(float(cam.pitch), float(cam.yaw), 0)
	spring.spring_length = lerpf(spring.spring_length, float(cam.distance), minf(1.0, delta * 10.0))
	camera.fov = Settings.fov + float(cam.fov_offset)
	model.visible = mode != "first"


func _physics_process(delta: float) -> void:
	_update_camera(delta)
	if selected >= hotbar_size():
		select(0)
	if frozen:
		if world.is_ready_at(global_position):
			frozen = false
		else:
			return

	var input := Vector2.ZERO if ui_blocked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > 0.05:
		input = touch_move
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := right * input.x + forward * (-input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()

	var speed := float(stat("speed"))
	var reg := Blocks.reg
	var feet := Vector3i(floori(global_position.x), floori(global_position.y + 0.3), floori(global_position.z))
	var body_cell := Vector3i(feet.x, floori(global_position.y + 0.9), feet.z)
	in_liquid = reg.is_liquid(world.get_block(feet)) or reg.is_liquid(world.get_block(body_cell))
	var eye := camera.global_position if camera_mode() == "first" else global_position + Vector3(0, 1.6, 0)
	eyes_in_liquid = reg.is_liquid(world.get_block(Vector3i(eye.floor())))
	var flow := Vector3.ZERO
	if in_liquid:
		speed *= 0.55 * float(stat("swim_speed"))
		flow = world.liquids.flow_at(feet) * 2.2
	velocity.x = lerpf(velocity.x, dir.x * speed + flow.x, minf(1.0, delta * 12.0))
	velocity.z = lerpf(velocity.z, dir.z * speed + flow.z, minf(1.0, delta * 12.0))
	if in_liquid:
		# pływanie: lekkie tonięcie, Spacja wynosi w górę, przy brzegu wyskok na ląd
		var up := (Input.is_action_pressed("jump") and not ui_blocked) or touch_jump
		var want_y := 3.2 if up else -1.2
		velocity.y = lerpf(velocity.y, want_y + flow.y, minf(1.0, delta * 4.0))
		if up and is_on_wall() and dir.length() > 0.3:
			velocity.y = 6.0
		reset_fall()
	elif is_on_floor():
		var want_jump := (Input.is_action_pressed("jump") and not ui_blocked) or touch_jump
		# automatyczny skok na stopień o wysokości jednego bloku
		if dir.length() > 0.3 and is_on_wall() and bool(stat("auto_jump")):
			want_jump = true
		if want_jump:
			velocity.y = float(stat("jump"))
	else:
		velocity.y -= float(stat("gravity")) * delta
	var fall_speed := -velocity.y
	move_and_slide()
	_track_fall(fall_speed)
	# pchanie obiektów luźnych
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		var body := col.get_collider()
		if body is RigidBody3D:
			var push := -col.get_normal()
			push.y = 0.0
			body.apply_central_impulse(push * 3.0 * delta * body.mass)

	if global_position.y < -80.0:
		die("void")

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.3:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(1.0, delta * 10.0))
	elif camera_mode() == "first":
		model.rotation.y = yaw
	model.animate(delta, hspeed, is_on_floor() or in_liquid, pitch)
	light_timer -= delta
	if light_timer <= 0.0:
		light_timer = 0.2
		model.set_light(world.light_at(global_position + Vector3(0, 1.2, 0)))
	_update_target()
	_update_digging(delta)


# ---------- zdrowie, upadki, śmierć ----------

func reset_fall() -> void:
	fall_top = global_position.y


## Upadek: silnik tylko mierzy wysokość i wysyła zdarzenie "player.land"; obrażenia zadają mody.
func _track_fall(speed: float) -> void:
	var on := is_on_floor()
	if not on:
		fall_top = maxf(fall_top, global_position.y)
	elif not was_on_floor:
		var fall := fall_top - global_position.y
		if fall > 0.6:
			Mods.emit_event("player.land", {"fall": fall, "speed": speed})
		fall_top = global_position.y
	else:
		fall_top = global_position.y
	was_on_floor = on


func set_health(v: float) -> void:
	var mx := float(stat("max_health"))
	health = clampf(v, 0.0, mx)
	health_changed.emit(health, mx)


## Obrażenia przechodzą przez hak "player.damage" (np. zbroja może zmniejszyć ctx.amount).
func damage(amount: float, cause: String) -> void:
	if frozen or health <= 0.0:
		return
	var ctx := Mods.before("player.damage", {"amount": amount, "cause": cause})
	if ctx.get("cancel", false):
		return
	set_health(health - float(ctx.get("amount", amount)))
	Mods.after("player.damage", ctx)
	if health <= 0.0:
		die(cause)


func die(cause: String) -> void:
	Mods.emit_event("player.death", {"cause": cause, "pos": global_position})
	died.emit(cause)
	respawn()


func spawn_point() -> Vector3:
	var sp: Variant = stat("spawn")
	if sp is Vector3:
		return sp
	var h := world.terrain.height(0, 0)
	return Vector3(0.5, h + 2.0, 0.5)


func respawn() -> void:
	var ctx := Mods.before("player.respawn", {"pos": spawn_point()})
	global_position = Vector3(ctx.get("pos", spawn_point()))
	velocity = Vector3.ZERO
	reset_fall()
	set_health(float(stat("max_health")))
	Mods.after("player.respawn", ctx)


## Cel z uwzględnieniem cieczy (np. dla wiadra).
func target_with_liquids() -> Dictionary:
	var head := global_position + Vector3(0, 1.55, 0)
	var reach := float(stat("reach"))
	var r: Dictionary = world.raycast(camera.global_position, -camera.global_basis.z, spring.spring_length + reach + 1.0, true)
	if r.get("hit", false) and (Vector3(r.pos) + Vector3(0.5, 0.5, 0.5)).distance_to(head) <= reach + 0.5:
		return r
	return {}


func _update_target() -> void:
	var origin := camera.global_position
	var dir := -camera.global_basis.z
	var head := global_position + Vector3(0, 1.55, 0)
	var reach := float(stat("reach"))
	var r: Dictionary = world.raycast(origin, dir, spring.spring_length + reach + 1.0)
	if r.get("hit", false) and (Vector3(r.pos) + Vector3(0.5, 0.5, 0.5)).distance_to(head) <= reach + 0.5:
		target = r
		highlight.visible = true
		highlight.global_position = Vector3(r.pos)
	else:
		target = {}
		highlight.visible = false


# ---------- kopanie w czasie ----------

## Stworzenie albo obiekt luźny pod celownikiem, jeśli jest bliżej niż blok.
func entity_target() -> Dictionary:
	if entities == null:
		return {}
	var reach := float(stat("reach"))
	var e := entities.pick(camera.global_position, -camera.global_basis.z, spring.spring_length + reach + 1.0)
	if e.is_empty():
		return {}
	var node: Node3D = e.node
	if node.global_position.distance_to(global_position + Vector3(0, 1.0, 0)) > reach + 1.0:
		return {}
	if not target.is_empty() and float(target.get("dist", 999.0)) < float(e.dist) - 0.3:
		return {}
	return e


func start_digging() -> void:
	var e := entity_target()
	if not e.is_empty():
		model.do_swing()
		var node: Node3D = e.node
		if node is Creature:
			var it := str(current_item().get("item", ""))
			var dmg := float(Blocks.reg.items.get(it, {}).get("data", {}).get("damage", 1.0)) if it != "" else 1.0
			node.hit(dmg, global_position, "player")
		elif node is Prop:
			node.kick(-camera.global_basis.z, 6.0)
		return
	digging = true
	dig_pos = Vector3i(0, -99999, 0)


func stop_digging() -> void:
	digging = false
	dig_progress = 0.0
	dig_pos = Vector3i(0, -99999, 0)
	crack.visible = false


## Czas kopania bloku: twardość z definicji bloku podzielona przez szybkość kopania gracza.
## Hak „block.dig” może go zmienić (np. narzędzia) albo zabronić kopania (cancel).
func _dig_time(pos: Vector3i) -> float:
	var block := world.get_block(pos)
	var hd := Blocks.reg.hardness[block] if block < Blocks.reg.hardness.size() else 1.0
	if hd < 0.0:
		return -1.0
	var t := hd / maxf(0.01, float(stat("break_speed")))
	if Mods.has_hook("before", "block.dig"):
		var ctx := Mods.before("block.dig", {"pos": pos, "block": block, "time": t, "item": str(current_item().get("item", ""))})
		if ctx.get("cancel", false):
			return -1.0
		t = float(ctx.get("time", t))
	return t


func _update_digging(delta: float) -> void:
	dig_cooldown = maxf(0.0, dig_cooldown - delta)
	if not digging or target.is_empty() or ui_blocked:
		crack.visible = false
		if target.is_empty():
			dig_progress = 0.0
		return
	if target.pos != dig_pos:
		dig_pos = target.pos
		dig_progress = 0.0
		dig_time = _dig_time(dig_pos)
	if dig_time < 0.0 or dig_cooldown > 0.0:
		crack.visible = false
		return
	swing_timer -= delta
	if swing_timer <= 0.0:
		swing_timer = 0.3
		model.do_swing()
	dig_progress += delta / maxf(dig_time, 0.0001)
	if dig_progress >= 1.0 or dig_time <= 0.05:
		break_block()
		dig_progress = 0.0
		dig_pos = Vector3i(0, -99999, 0)
		dig_cooldown = 0.15 if dig_time > 0.05 else 0.25
		crack.visible = false
		return
	crack.visible = true
	crack.global_position = Vector3(dig_pos) + Vector3(0.5, 0.5, 0.5)
	crack.material_override = crack_mats[clampi(int(dig_progress * 5.0), 0, 4)]


## Kopanie przechodzi przez haki modów: „block.break” przed (można anulować, zmienić łup) i po.
func break_block() -> void:
	if target.is_empty():
		return
	var block := world.get_block(target.pos)
	var drops := []
	for d in Blocks.reg.drops(block):
		if not d.has("chance") or _rng.randf() < float(d.chance):
			drops.append({"item": str(d.item), "count": int(d.get("count", 1))})
	var ctx := Mods.before("block.break", {"pos": target.pos, "block": block, "drops": drops,
		"item": str(current_item().get("item", ""))})
	if ctx.get("cancel", false):
		return
	if world.set_block(target.pos, Blocks.AIR):
		model.do_swing()
		Mods.after("block.break", ctx)


## Prawy przycisk: przedmiot-blok stawia blok, inny przedmiot wywołuje hak „item.use”.
func use_item() -> void:
	var e := entity_target()
	if not e.is_empty():
		var node: Node3D = e.node
		if node is Creature:
			var ctx := Mods.before("entity.interact", {"id": node.id, "type": node.type,
				"item": str(current_item().get("item", "")), "slot": selected + 1})
			if not ctx.get("cancel", false):
				Mods.after("entity.interact", ctx)
			model.do_swing()
			return
		if node is Prop:
			if entities.pickup_prop(node):
				model.do_swing()
			return
	var it := current_item()
	var key := str(it.get("item", ""))
	if key != "" and Blocks.reg.item_block(key) <= 0:
		var ctx := {"item": key, "slot": selected + 1}
		if not target.is_empty():
			ctx["pos"] = target.pos
			ctx["normal"] = target.normal
			ctx["block"] = world.get_block(target.pos)
		ctx = Mods.before("item.use", ctx)
		if ctx.get("cancel", false):
			return
		model.do_swing()
		Mods.after("item.use", ctx)
		return
	place_block()


func place_block() -> void:
	if target.is_empty() or target.normal == Vector3i.ZERO:
		return
	var p: Vector3i = target.pos + target.normal
	# nie stawiamy bloku tam, gdzie stoi gracz
	var a_min := global_position - Vector3(0.3, 0, 0.3)
	var a_max := global_position + Vector3(0.3, 1.8, 0.3)
	if a_max.x > p.x and a_min.x < p.x + 1 and a_max.y > p.y and a_min.y < p.y + 1 and a_max.z > p.z and a_min.z < p.z + 1:
		return
	var block := current_block()
	if block <= 0:
		return
	var ctx := Mods.before("block.place", {"pos": p, "block": block, "slot": selected + 1,
		"item": str(current_item().get("item", ""))})
	if ctx.get("cancel", false):
		return
	var placed := int(ctx.get("block", block))
	# blok luźny nie trafia do siatki świata, tylko staje się obiektem fizycznym
	if Blocks.reg.loose(placed) != null and entities:
		if entities.spawn_prop(placed, Vector3(p) + Vector3(0.5, 0.5, 0.5), Vector3(0, yaw, 0)) >= 0:
			model.do_swing()
			Mods.after("block.place", ctx)
		return
	if world.set_block(p, placed):
		model.do_swing()
		Mods.after("block.place", ctx)
