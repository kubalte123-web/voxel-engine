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
var sprite: Node3D           # model 3D przedmiotu (ItemModel), obraca się
var mats: Array = []
var puppet := false
var net_pos := Vector3.ZERO
var net_rot := Vector3.ZERO
var interp := NetInterp.new(0.15)   # stany obiektów co 0,1 s


func _ready() -> void:
	sprite = Node3D.new()
	add_child(sprite)
	var m := ItemModel.build(world.reg, item, mats)
	# narzędzia leżą w skos, inne przedmioty stoją; środek modelu nad ziemią
	if str(m.get_meta("kind", "")) == "tool":
		m.rotation_degrees = Vector3(0, 0, -45)
		m.scale = Vector3.ONE * 0.42
		m.position = Vector3(-0.1, 0.0, 0)
	else:
		m.scale = Vector3.ONE * 0.55
	sprite.add_child(m)


func _process(delta: float) -> void:
	if puppet:
		var s := interp.sample()
		if s.is_empty():
			global_position = global_position.lerp(net_pos, minf(1.0, delta * 10.0))
		else:
			global_position = s[0]
		sprite.rotation.y += delta * 2.0


func _physics_process(delta: float) -> void:
	age += delta
	if puppet:
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
	if int(age * 4.0) != int((age - delta) * 4.0) or age <= delta:
		EntityLight.apply(mats, world.light_at(global_position + Vector3(0, 0.3, 0)))
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
