class_name FallingBlock
extends Node3D
## Blok z grawitacją (piasek, żwir) bez podparcia: spada, w cieczy wolniej, i staje się zwykłym blokiem,
## gdy trafi na coś stałego.

var world: World
var block := 0
var speed := 0.0


func _ready() -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = BlockMesh.cube(world.reg, block, 1.0)
	mi.material_override = world.material.duplicate()
	mi.position = Vector3(-0.5, 0.0, -0.5)
	add_child(mi)
	mesh = mi


var mesh: MeshInstance3D


func _physics_process(delta: float) -> void:
	var here := Vector3i(floori(global_position.x), floori(global_position.y), floori(global_position.z))
	var in_liquid := world.reg.is_liquid(world.get_block(here))
	speed = minf(speed + 22.0 * delta, 3.0 if in_liquid else 30.0)
	var ny := global_position.y - speed * delta
	var below := Vector3i(here.x, floori(ny), here.z)
	var bb := world.get_block(below)
	if (bb != Blocks.AIR and (Blocks.props(bb) & Blocks.SOLID) != 0) or not world.is_loaded(below):
		var target := below + Vector3i(0, 1, 0)
		var tb := world.get_block(target)
		if tb == Blocks.AIR or world.reg.is_liquid(tb) or (Blocks.props(tb) & Blocks.SOLID) == 0:
			world.set_block(target, block)
		queue_free()
		return
	global_position.y = ny
	(mesh.material_override as ShaderMaterial).set_shader_parameter("light_override", world.light_at(global_position + Vector3(0, 0.5, 0)))
	if global_position.y < -120.0:
		queue_free()
