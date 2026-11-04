class_name EntityManager
extends Node3D
## Wszystkie obiekty w świecie poza blokami: stworzenia, obiekty luźne (fizyczne) i przedmioty na ziemi.
## Pojawianie się stworzeń według opisu z modów, usypianie dalekich (zapis i przywrócenie, gdy gracz
## wróci), zapis do entities.json i wybieranie celownikiem.

const SAVE_FILE := "entities.json"
const MAX_DORMANT := 400

var world: World
var player: Player
var next_id := 1
var entities := {}      # id -> Node3D
var dormant: Array = [] # uśpione stworzenia (stan do przywrócenia)
var spawn_timer := 1.0
var spawned_initial := false
var rng := RandomNumberGenerator.new()


func setup(w: World, p: Player) -> void:
	world = w
	player = p
	rng.randomize()


func defs() -> Dictionary:
	return Mods.registry.entities if Mods.registry else {}


# ---------- tworzenie i usuwanie ----------

func spawn_creature(type: String, pos: Vector3, data: Dictionary = {}, scale_f: float = 1.0) -> int:
	var d: Variant = defs().get(type)
	if not d is Dictionary:
		return -1
	var c := Creature.new()
	var id := next_id
	next_id += 1
	c.setup(self, world, id, type, d)
	c.data = data
	c.scale_factor = scale_f
	add_child(c)
	c.global_position = pos
	entities[id] = c
	Mods.emit_event("entity.spawn", {"id": id, "type": type, "pos": pos})
	return id


func spawn_prop(block: int, pos: Vector3, rot: Vector3 = Vector3.ZERO) -> int:
	if world.reg.loose(block) == null:
		return -1
	var p := Prop.new()
	var id := next_id
	next_id += 1
	p.setup(self, world, id, block)
	add_child(p)
	p.global_position = pos
	p.rotation = rot
	entities[id] = p
	return id


func drop_item(item: String, count: int, pos: Vector3) -> int:
	if not world.reg.items.has(item):
		return -1
	var d := ItemDrop.new()
	var id := next_id
	next_id += 1
	d.manager = self
	d.world = world
	d.id = id
	d.item = item
	d.count = count
	add_child(d)
	d.global_position = pos
	entities[id] = d
	return id


func remove(id: int) -> void:
	var e: Node = entities.get(id)
	if e:
		entities.erase(id)
		e.queue_free()


func get_entity(id: int) -> Node3D:
	var e: Variant = entities.get(id)
	return e if is_instance_valid(e) else null


func list(type: String = "", near: Vector3 = Vector3.ZERO, radius: float = 0.0) -> Array:
	var out := []
	for id in entities:
		var e: Node3D = entities[id]
		if not e is Creature:
			continue
		if type != "" and e.type != type:
			continue
		if radius > 0.0 and e.global_position.distance_to(near) > radius:
			continue
		out.append(id)
	return out


## Obiekt pod celownikiem: {"node", "dist"} albo {}.
func pick(origin: Vector3, dir: Vector3, dist: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(origin, origin + dir.normalized() * dist, 1 | 2 | 4)
	q.exclude = [player.get_rid()]
	var r := space.intersect_ray(q)
	if r.is_empty() or not (r.collider is Creature or r.collider is Prop):
		return {}
	return {"node": r.collider, "dist": origin.distance_to(r.position)}


## Podniesienie obiektu luźnego: przedmiot trafia do ekwipunku przez hak "item.pickup".
func pickup_prop(p: Prop) -> bool:
	var key := Blocks.key(p.block)
	var ctx := Mods.before("item.pickup", {"item": key, "count": 1})
	if int(ctx.get("taken", 0)) > 0:
		remove(p.id)
		return true
	return false


# ---------- pojawianie się i usypianie ----------

func _process(delta: float) -> void:
	if player == null or player.frozen:
		return
	spawn_timer -= delta
	if spawn_timer > 0.0:
		return
	spawn_timer = 0.5 if not spawned_initial else 3.0
	_sleep_and_wake()
	_spawn_cycle()


func _near_radius() -> float:
	return float(world.radius) * World.S


func _sleep_and_wake() -> void:
	var pp := player.global_position
	var far := _near_radius() + 24.0
	for id in entities.keys():
		var e: Node3D = entities[id]
		if e is Creature and Vector2(e.global_position.x - pp.x, e.global_position.z - pp.z).length() > far:
			dormant.append(e.save_state())
			remove(id)
		elif e is ItemDrop and e.global_position.distance_to(pp) > far:
			remove(id)
	while dormant.size() > MAX_DORMANT:
		dormant.pop_front()
	var near := _near_radius() - 16.0
	for i in range(dormant.size() - 1, -1, -1):
		var s: Dictionary = dormant[i]
		var pos := Vector3(s.pos[0], s.pos[1], s.pos[2])
		if Vector2(pos.x - pp.x, pos.z - pp.z).length() < near and world.is_loaded(Vector3i(pos.floor())):
			dormant.remove_at(i)
			_restore(s)


func _restore(s: Dictionary) -> void:
	var id := spawn_creature(str(s.type), Vector3(s.pos[0], s.pos[1], s.pos[2]), s.get("data", {}) if s.get("data") is Dictionary else {}, float(s.get("scale", 1.0)))
	var c := get_entity(id) as Creature
	if c:
		c.health = float(s.get("health", c.max_health))
		c.rotation.y = float(s.get("yaw", 0.0))


## Opis pojawiania się: spawn = {biomes = {"meadow"}, on = {"grass"}, group = {2, 4}, max = 8}
func _spawn_cycle() -> void:
	var pp := player.global_position
	var all_ready := true
	for type in defs():
		var d: Dictionary = defs()[type]
		var sp: Dictionary = d.get("spawn") if d.get("spawn") is Dictionary else {}
		if sp.is_empty():
			continue
		var count := list(type, pp, _near_radius()).size()
		if count >= int(sp.get("max", 6)):
			continue
		all_ready = false
		var biomes: Array = Registry.arr(sp.get("biomes"))
		var on: Array = Registry.arr(sp.get("on"))
		for attempt in 4:
			var a := rng.randf() * TAU
			var dist := rng.randf_range(16.0, maxf(20.0, _near_radius() - 8.0))
			var x := floori(pp.x + cos(a) * dist)
			var z := floori(pp.z + sin(a) * dist)
			var gy := _surface(x, z, floori(pp.y) + 24)
			if gy == -99999:
				continue
			if not biomes.is_empty() and not biomes.has(_biome_key(x, z)):
				continue
			if not on.is_empty() and not on.has(Blocks.key(world.get_block(Vector3i(x, gy, z)))):
				continue
			var g: Array = Registry.arr(sp.get("group"))
			var n := rng.randi_range(int(g[0]) if g.size() > 0 else 1, int(g[1]) if g.size() > 1 else 3)
			for k in n:
				var gx := x + rng.randi_range(-2, 2)
				var gz := z + rng.randi_range(-2, 2)
				var y2 := _surface(gx, gz, gy + 3)
				if y2 != -99999 and absi(y2 - gy) <= 2:
					var baby := rng.randf() < float(sp.get("babies", 0.15))
					spawn_creature(type, Vector3(gx + 0.5, y2 + 1.05, gz + 0.5), {"baby": true} if baby else {}, 0.55 if baby else 1.0)
			break
	if all_ready:
		spawned_initial = true


func _biome_key(x: int, z: int) -> String:
	var t := world.terrain
	var i: int = t.column(x, z).y
	return t.biome_keys[i] if i < t.biome_keys.size() else ""


## Najwyższy blok stały z powietrzem nad sobą (w załadowanym chunku).
func _surface(x: int, z: int, from_y: int) -> int:
	for y in range(from_y, from_y - 48, -1):
		var p := Vector3i(x, y, z)
		if not world.is_loaded(p):
			continue
		var b := world.get_block(p)
		if b != Blocks.AIR and (Blocks.props(b) & Blocks.SOLID) != 0:
			return y if world.get_block(p + Vector3i(0, 1, 0)) == Blocks.AIR and world.get_block(p + Vector3i(0, 2, 0)) == Blocks.AIR else -99999
		if world.reg.is_liquid(b):
			return -99999
	return -99999


# ---------- zapis ----------

func save(dir: String) -> void:
	if dir.is_empty():
		return
	var cr := dormant.duplicate()
	var props := []
	var drops := []
	for id in entities:
		var e: Node3D = entities[id]
		if e is Creature and e.dying <= 0.0:
			cr.append(e.save_state())
		elif e is Prop:
			props.append(e.save_state())
		elif e is ItemDrop:
			drops.append(e.save_state())
	var f := FileAccess.open(dir.path_join(SAVE_FILE), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"creatures": cr, "props": props, "drops": drops, "spawned": spawned_initial}))


func load_from(dir: String) -> void:
	if dir.is_empty() or not FileAccess.file_exists(dir.path_join(SAVE_FILE)):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(dir.path_join(SAVE_FILE)))
	if not d is Dictionary:
		return
	spawned_initial = bool(d.get("spawned", false))
	for s in d.get("creatures", []):
		if s is Dictionary and defs().has(str(s.get("type", ""))):
			dormant.append(s)  # obudzą się, gdy ich chunk będzie gotowy
	for s in d.get("props", []):
		if s is Dictionary:
			var b := Blocks.id(str(s.get("block", "")))
			if b > 0:
				spawn_prop(b, Vector3(s.pos[0], s.pos[1], s.pos[2]), Vector3(s.rot[0], s.rot[1], s.rot[2]))
	for s in d.get("drops", []):
		if s is Dictionary:
			drop_item(str(s.item), int(s.count), Vector3(s.pos[0], s.pos[1], s.pos[2]))
