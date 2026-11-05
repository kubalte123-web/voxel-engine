class_name ItemDrop
extends Node3D
## Przedmiot leżący na ziemi (np. łup ze zwierzęcia): obraca się, spada, a gdy gracz podejdzie,
## silnik pyta mody hakiem "item.pickup" (ctx.taken = ile zabrano; plecak dodaje do ekwipunku).

var manager: Node
var world: World
var id := 0
var item := ""
var count := 1
var data := {}       # dane egzemplarza (np. amunicja broni) – zostają po wyrzuceniu i podniesieniu
var vy := 2.5
var age := 0.0
var sprite: Sprite3D
var puppet := false
var net_pos := Vector3.ZERO
var net_rot := Vector3.ZERO


func _ready() -> void:
	sprite = Sprite3D.new()
	sprite.texture = world.reg.icon(item)
	sprite.pixel_size = 0.4 / maxf(1.0, float(sprite.texture.get_width()))
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	add_child(sprite)


func _physics_process(delta: float) -> void:
	age += delta
	if puppet:
		global_position = global_position.lerp(net_pos, minf(1.0, delta * 10.0))
		sprite.rotation.y += delta * 2.0
		return
	var below := Vector3i((global_position - Vector3(0, 0.15, 0)).floor())
	var bb := world.get_block(below)
	var on_ground := bb != Blocks.AIR and (Blocks.props(bb) & Blocks.SOLID) != 0
	if world.reg.is_liquid(world.get_block(Vector3i(global_position.floor()))):
		vy = lerpf(vy, 0.8, delta * 3.0)  # przedmioty wypływają
	elif on_ground and vy <= 0.0:
		vy = 0.0
		global_position.y = float(below.y + 1) + 0.15
	else:
		vy -= 18.0 * delta
	global_position.y += vy * delta
	sprite.rotation.y += delta * 2.0
	if int(age * 4.0) != int((age - delta) * 4.0):
		var f := EntityLight.factors(world.light_at(global_position + Vector3(0, 0.3, 0)))
		var v := clampf(f.x + f.y, 0.0, 1.0)
		sprite.modulate = Color(v, v * (0.9 if f.y > f.x else 1.0), v * (0.8 if f.y > f.x else 1.0))
	sprite.position.y = 0.15 + sin(age * 2.5) * 0.06
	var near: Node3D = manager.nearest_player(global_position)
	if age > 0.6 and near and near.global_position.distance_to(global_position) < 1.6:
		var ctx: Dictionary = Mods.as_player(EntityManager.peer_of(near), func(): return Mods.before("item.pickup", {"item": item, "count": count, "data": data} if not data.is_empty() else {"item": item, "count": count}))
		var taken := int(ctx.get("taken", 0))
		if taken > 0:
			Sfx.emit("item.pickup", global_position, 0.7)
			count -= taken
			if count <= 0:
				manager.remove(id)
				return
	if age > 300.0 or global_position.y < -90.0:
		manager.remove(id)


func save_state() -> Dictionary:
	var p := global_position
	return {"item": item, "count": count, "pos": [p.x, p.y, p.z], "data": data}
