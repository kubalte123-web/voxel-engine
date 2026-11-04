class_name Player
extends CharacterBody3D
## Gracz: ruch, kamera z trzeciej osoby (lub pierwszej), kopanie i stawianie bloków.

signal selection_changed(index: int)

var world: World
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

const SPEED := 4.6
const JUMP := 7.6
const GRAVITY := 24.0
const REACH := 6.0
const ARM := 4.2


func _ready() -> void:
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 1.8, 0.6)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = 0.9
	add_child(cs)
	floor_snap_length = 0.3

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
			break_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			place_block()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select((selected + hotbar_size() - 1) % hotbar_size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select((selected + 1) % hotbar_size())
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
	pitch = clampf(pitch - delta.y, -1.45, 1.2)


func select(i: int) -> void:
	selected = i
	selection_changed.emit(i)


func toggle_view() -> void:
	first_person = not first_person
	model.visible = not first_person


## Statystyki gracza: wartość domyślna albo nadpisana przez mod (engine.player.set).
func stat(name: String) -> Variant:
	var defaults := {"speed": SPEED, "jump": JUMP, "gravity": GRAVITY, "reach": REACH, "auto_jump": true}
	return Mods.player_stats.get(name, defaults.get(name))


func hotbar_size() -> int:
	return Mods.hotbar.count if Mods.hotbar.container != "" else Blocks.PLACEABLE.size()


## Blok wybrany na pasku: z kontenera moda albo z listy trybu kreatywnego.
func current_block() -> int:
	var b := Mods.hotbar_block(selected)
	if b < 0:
		return Blocks.PLACEABLE[selected % Blocks.PLACEABLE.size()]
	return b


func _physics_process(delta: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	var arm: float = 0.0 if first_person else float(Mods.camera_stats.get("distance", ARM))
	spring.spring_length = lerpf(spring.spring_length, arm, minf(1.0, delta * 10.0))
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
	velocity.x = lerpf(velocity.x, dir.x * speed, minf(1.0, delta * 12.0))
	velocity.z = lerpf(velocity.z, dir.z * speed, minf(1.0, delta * 12.0))
	if is_on_floor():
		var want_jump := (Input.is_action_pressed("jump") and not ui_blocked) or touch_jump
		# automatyczny skok na stopień o wysokości jednego bloku
		if dir.length() > 0.3 and is_on_wall() and bool(stat("auto_jump")):
			want_jump = true
		if want_jump:
			velocity.y = float(stat("jump"))
	else:
		velocity.y -= float(stat("gravity")) * delta
	move_and_slide()

	if global_position.y < -80.0:
		respawn()

	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.3:
		var target_yaw := atan2(-velocity.x, -velocity.z)
		model.rotation.y = lerp_angle(model.rotation.y, target_yaw, minf(1.0, delta * 10.0))
	elif first_person:
		model.rotation.y = yaw
	model.animate(delta, hspeed, is_on_floor(), pitch)
	_update_target()


func respawn() -> void:
	var h := world.terrain.height(0, 0)
	global_position = Vector3(0.5, h + 2.0, 0.5)
	velocity = Vector3.ZERO


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


## Kopanie przechodzi przez haki modów: „block.break” przed (można anulować) i po.
func break_block() -> void:
	if target.is_empty():
		return
	var ctx := Mods.before("block.break", {"pos": target.pos, "block": world.get_block(target.pos)})
	if ctx.get("cancel", false):
		return
	if world.set_block(target.pos, Blocks.AIR):
		model.do_swing()
		Mods.after("block.break", ctx)


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
	var ctx := Mods.before("block.place", {"pos": p, "block": block, "slot": selected + 1})
	if ctx.get("cancel", false):
		return
	if world.set_block(p, int(ctx.get("block", block))):
		model.do_swing()
		Mods.after("block.place", ctx)
