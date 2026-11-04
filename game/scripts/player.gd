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
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			break_block()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			place_block()
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			select((selected + Blocks.PLACEABLE.size() - 1) % Blocks.PLACEABLE.size())
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			select((selected + 1) % Blocks.PLACEABLE.size())
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		look(event.relative * mouse_sensitivity)
	elif event.is_action_pressed("toggle_view"):
		toggle_view()
	else:
		for i in Blocks.PLACEABLE.size():
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
	spring.spring_length = 0.0 if first_person else ARM
	model.visible = not first_person


func _physics_process(delta: float) -> void:
	pivot.rotation = Vector3(pitch, yaw, 0)
	if frozen:
		if world.is_ready_at(global_position):
			frozen = false
		else:
			return

	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if touch_move.length() > 0.05:
		input = touch_move
	var forward := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := Vector3(cos(yaw), 0, -sin(yaw))
	var dir := right * input.x + forward * (-input.y)
	if dir.length() > 1.0:
		dir = dir.normalized()

	velocity.x = lerpf(velocity.x, dir.x * SPEED, minf(1.0, delta * 12.0))
	velocity.z = lerpf(velocity.z, dir.z * SPEED, minf(1.0, delta * 12.0))
	if is_on_floor():
		var want_jump := Input.is_action_pressed("jump") or touch_jump
		# automatyczny skok na stopień o wysokości jednego bloku
		if dir.length() > 0.3 and is_on_wall():
			want_jump = true
		if want_jump:
			velocity.y = JUMP
	else:
		velocity.y -= GRAVITY * delta
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
	var r: Dictionary = world.raycast(origin, dir, spring.spring_length + REACH + 1.0)
	if r.get("hit", false) and (Vector3(r.pos) + Vector3(0.5, 0.5, 0.5)).distance_to(head) <= REACH + 0.5:
		target = r
		highlight.visible = true
		highlight.global_position = Vector3(r.pos)
	else:
		target = {}
		highlight.visible = false


func break_block() -> void:
	if target.is_empty():
		return
	if world.set_block(target.pos, Blocks.AIR):
		model.do_swing()


func place_block() -> void:
	if target.is_empty() or target.normal == Vector3i.ZERO:
		return
	var p: Vector3i = target.pos + target.normal
	# nie stawiamy bloku tam, gdzie stoi gracz
	var a_min := global_position - Vector3(0.3, 0, 0.3)
	var a_max := global_position + Vector3(0.3, 1.8, 0.3)
	if a_max.x > p.x and a_min.x < p.x + 1 and a_max.y > p.y and a_min.y < p.y + 1 and a_max.z > p.z and a_min.z < p.z + 1:
		return
	if world.set_block(p, Blocks.PLACEABLE[selected]):
		model.do_swing()
