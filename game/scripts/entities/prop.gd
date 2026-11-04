class_name Prop
extends RigidBody3D
## Obiekt luźny: blok z flagą `loose`, który nie przyczepia się do siatki świata. Fizyka bryły sztywnej:
## można go pchać, kopnąć, toczy się (kula, walec), a w cieczy działa wyporność według gęstości
## (gęstość < 1 pływa, > 1 tonie) i prąd go znosi.
## loose = {shape = "box"|"ball"|"cylinder", size = 1.0, mass = 10, density = 0.6, bounce = 0.1, friction = 0.8}

const LAYER := 4

var manager: Node
var world: World
var id := 0
var block := 0
var spec := {}
var size := 1.0
var density := 0.6
var shape_kind := "box"
var sleeping_far := false
var mesh_node: MeshInstance3D
var light_timer := 0.0


func setup(p_manager: Node, p_world: World, p_id: int, p_block: int) -> void:
	manager = p_manager
	world = p_world
	id = p_id
	block = p_block
	var l: Variant = world.reg.loose(block)
	spec = l if l is Dictionary else {}
	size = float(spec.get("size", 0.9))
	density = float(spec.get("density", 0.6))
	shape_kind = str(spec.get("shape", "box"))
	mass = float(spec.get("mass", 10.0))


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1 | 2 | 4 | 8
	var pm := PhysicsMaterial.new()
	pm.bounce = float(spec.get("bounce", 0.1))
	pm.friction = float(spec.get("friction", 0.8))
	physics_material_override = pm
	angular_damp = 0.6
	linear_damp = 0.1
	can_sleep = true
	var cs := CollisionShape3D.new()
	var mi := MeshInstance3D.new()
	match shape_kind:
		"ball":
			var sh := SphereShape3D.new()
			sh.radius = size * 0.5
			cs.shape = sh
			var sm := SphereMesh.new()
			sm.radius = size * 0.5
			sm.height = size
			sm.radial_segments = 16
			sm.rings = 8
			mi.mesh = sm
			mi.material_override = BlockMesh.tile_material(world.reg, block, 0)
		"cylinder":
			var sh := CylinderShape3D.new()
			sh.radius = size * 0.45
			sh.height = size
			cs.shape = sh
			var cm := CylinderMesh.new()
			cm.top_radius = size * 0.45
			cm.bottom_radius = size * 0.45
			cm.height = size
			cm.radial_segments = 14
			mi.mesh = cm
			mi.material_override = BlockMesh.tile_material(world.reg, block, 0)
		_:
			var sh := BoxShape3D.new()
			sh.size = Vector3.ONE * size
			cs.shape = sh
			mi.mesh = BlockMesh.cube(world.reg, block, size)
			mi.material_override = world.material
			mi.position = Vector3.ONE * -size * 0.5
	add_child(cs)
	add_child(mi)
	mesh_node = mi


func _update_light(delta: float) -> void:
	light_timer -= delta
	if light_timer > 0.0:
		return
	light_timer = 0.3
	var l := world.light_at(global_position + Vector3(0, 0.3, 0))
	if mesh_node.material_override is ShaderMaterial:
		mesh_node.set_instance_shader_parameter("light_override", l)
	else:
		EntityLight.apply([mesh_node.material_override], l)


func _physics_process(delta: float) -> void:
	_update_light(delta)
	var cell := Vector3i(global_position.floor())
	# chunk pod spodem niegotowy albo usunięty: zamrażamy, żeby nie spaść przez świat
	var ready := world.is_loaded(cell) and world.is_loaded(cell + Vector3i(0, -1, 0))
	if freeze != (not ready):
		freeze = not ready
	if freeze:
		return
	var reg := world.reg
	var b := reg.is_liquid(world.get_block(cell))
	if b or reg.is_liquid(world.get_block(Vector3i((global_position - Vector3(0, size * 0.4, 0)).floor()))):
		# zanurzona część: od dna bryły do powierzchni cieczy w tym bloku
		var lv := reg.liquid_level(world.get_block(cell))
		var surface := float(cell.y) + (float(lv) / 8.0 * 0.9 if b else 0.0)
		if reg.is_liquid(world.get_block(cell + Vector3i(0, 1, 0))):
			surface = float(cell.y) + 1.5
		var bottom := global_position.y - size * 0.5
		var sub := clampf((surface - bottom) / size, 0.0, 1.0)
		var g := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.8))
		apply_central_force(Vector3.UP * mass * g * sub / maxf(0.05, density))
		var flow := world.liquids.flow_at(cell)
		apply_central_force(flow * mass * 2.0)
		# opór wody
		linear_velocity = linear_velocity.lerp(Vector3.ZERO, minf(1.0, delta * 1.2 * sub))
		angular_velocity = angular_velocity.lerp(Vector3.ZERO, minf(1.0, delta * 1.5 * sub))
		sleeping = false
	if global_position.y < -90.0:
		manager.remove(id)


func kick(dir: Vector3, strength: float) -> void:
	sleeping = false
	apply_central_impulse(dir.normalized() * strength * mass * 0.5 + Vector3.UP * mass * 0.8)


func save_state() -> Dictionary:
	var p := global_position
	var r := rotation
	return {"block": Blocks.key(block), "pos": [p.x, p.y, p.z], "rot": [r.x, r.y, r.z]}
