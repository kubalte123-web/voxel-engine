class_name Projectiles
extends Node3D
## Pociski z modów (engine.projectiles). Serwer liczy lot (prędkość, grawitacja) i trafienia wzdłuż całej
## drogi w danej klatce (pocisk nie przenika przez bloki przy dużej prędkości), a po trafieniu wywołuje
## obsługę moda (engine.projectiles.on_hit) w imieniu gracza, który strzelił. Klienci dostają tylko
## start i koniec lotu i liczą tor u siebie, żeby lot był płynny.
##
## Opis rodzaju (content.lua): speed, gravity, radius, lifetime, collision = {blocks, entities, players, liquids},
## visual = {type = "block" | "item" | "none", block, item, size, spin}, trail = nazwa cząsteczek.

var main: Node
var world: World
var list := {}       # id -> {type, def, pos, vel, owner, data, age, node, server}
var _next := 1


func _reg() -> Registry:
	return Mods.registry


# ---------- serwer ----------

## opts: position, direction, velocity, speed, owner (id gracza), data (tabela dla moda).
func spawn(type: String, opts: Dictionary) -> int:
	var def: Dictionary = _reg().projectiles.get(type, {})
	if def.is_empty():
		return -1
	var pos := Fx._v(opts.get("position"), Vector3.ZERO)
	var vel: Vector3
	if opts.has("velocity"):
		vel = Fx._v(opts.velocity, Vector3.ZERO)
	else:
		var dir := Fx._v(opts.get("direction"), Vector3.FORWARD).normalized()
		vel = dir * float(opts.get("speed", def.get("speed", 20.0)))
	var id := _next
	_next += 1
	var data: Dictionary = opts.get("data", {}) if opts.get("data") is Dictionary else {}
	var vis := visual_of(def, data)
	var p := {"type": type, "def": def, "pos": pos, "vel": vel, "owner": int(opts.get("owner", -1)),
		"data": data, "age": 0.0, "server": true, "gravity": float(def.get("gravity", 9.8)),
		"life": float(def.get("lifetime", 6.0)), "vis": vis}
	list[id] = p
	_make_node(id, p)
	if Net.online() and Net.is_server():
		Net.s_proj_spawn.rpc(id, pos, vel, p.gravity, p.life, vis)
	return id


func remove(id: int) -> void:
	_end(id, {"hit_type": "removed"}, false)


## Wygląd lotu: blok (z data.block albo visual.block), ikona przedmiotu albo nic; ślad cząsteczek.
static func visual_of(def: Dictionary, data: Dictionary) -> Dictionary:
	var v: Dictionary = def.get("visual", {}) if def.get("visual") is Dictionary else {}
	var out := {"type": str(v.get("type", "block")), "size": float(v.get("size", 0.4)), "spin": bool(v.get("spin", true)),
		"trail": str(def.get("trail", ""))}
	out["block"] = str(data.get("block", v.get("block", "")))
	out["item"] = str(data.get("item", v.get("item", "")))
	return out


func _physics_process(delta: float) -> void:
	for id in list.keys():
		if not list.has(id):
			continue
		var p: Dictionary = list[id]
		p.age += delta
		var vel: Vector3 = p.vel
		vel.y -= float(p.gravity) * delta
		p.vel = vel
		var step: Vector3 = vel * delta
		if p.server:
			var hit := _collide(p, step)
			if not hit.is_empty():
				p.pos = hit.point
				_end(id, hit, true)
				continue
			if p.age > float(p.life):
				_end(id, {"hit_type": "expire", "point": p.pos}, true)
				continue
		elif p.age > float(p.life) + 1.0:
			_end(id, {}, false)
			continue
		p.pos = (p.pos as Vector3) + step
		var n: Node3D = p.get("node")
		if n:
			n.position = p.pos
			if p.vis.spin:
				n.rotate_object_local(Vector3(1, 0.6, 0.3).normalized(), delta * 9.0)


## Trafienie na drodze `step` w tej klatce: najbliższe z bloków, stworzeń i graczy.
func _collide(p: Dictionary, step: Vector3) -> Dictionary:
	var def: Dictionary = p.def
	var col: Dictionary = def.get("collision", {}) if def.get("collision") is Dictionary else {}
	var radius := float(def.get("radius", 0.15))
	var from: Vector3 = p.pos
	var len := step.length()
	if len < 0.00001:
		return {}
	var best := {}
	var best_t := INF
	if bool(col.get("blocks", true)):
		var r := world.raycast(from, step / len, len + radius, bool(col.get("liquids", false)), true)
		if r.get("hit", false):
			var t: float = maxf(0.0, float(r.dist) - radius) / len
			if t <= 1.0:
				best_t = t
				best = {"hit_type": "block", "position": r.pos, "normal": r.normal, "block": world.get_block(r.pos),
					"place_pos": (r.pos as Vector3i) + (r.normal as Vector3i)}
	if bool(col.get("entities", true)) and main.entities:
		for e in main.entities.entities.values():
			if not (e is Creature) or e.dying > 0.0:
				continue
			var sz := Registry.arr(e.def.get("size"))
			var w: float = (float(sz[0]) if sz.size() > 0 else 0.8) * e.scale_factor * 0.5 + radius
			var h: float = (float(sz[1]) if sz.size() > 1 else 1.0) * e.scale_factor + radius
			var gp: Vector3 = e.global_position
			var t := _seg_box(from, step, gp - Vector3(w, radius, w), gp + Vector3(w, h, w))
			if t >= 0.0 and t < best_t:
				best_t = t
				best = {"hit_type": "entity", "entity": e.id, "entity_type": e.type}
	if bool(col.get("players", true)):
		for peer in main.players:
			var node: Node3D = main.players[peer]
			var s: Session = Mods.sessions.get(peer)
			if s == null or not s.logged_in or not node.visible:
				continue
			if peer == int(p.owner) and float(p.age) < 0.3:
				continue  # pocisk nie trafia strzelca zaraz po wystrzale
			var gp := node.global_position
			var t := _seg_box(from, step, gp - Vector3(0.3 + radius, radius, 0.3 + radius), gp + Vector3(0.3 + radius, 1.8 + radius, 0.3 + radius))
			if t >= 0.0 and t < best_t:
				best_t = t
				best = {"hit_type": "player", "player": peer}
	if best.is_empty():
		return {}
	best["point"] = from + step * best_t
	if not best.has("position"):
		best["position"] = Vector3i((best.point as Vector3).floor())
		best["normal"] = Vector3i.ZERO
		best["place_pos"] = best.position
	return best


## Przecięcie odcinka from..from+d z prostopadłościanem: t w [0, 1] albo -1.
static func _seg_box(from: Vector3, d: Vector3, lo: Vector3, hi: Vector3) -> float:
	var t0 := 0.0
	var t1 := 1.0
	for a in 3:
		if absf(d[a]) < 0.000001:
			if from[a] < lo[a] or from[a] > hi[a]:
				return -1.0
			continue
		var ta := (lo[a] - from[a]) / d[a]
		var tb := (hi[a] - from[a]) / d[a]
		t0 = maxf(t0, minf(ta, tb))
		t1 = minf(t1, maxf(ta, tb))
		if t0 > t1:
			return -1.0
	return t0


func _end(id: int, hit: Dictionary, notify: bool) -> void:
	var p: Dictionary = list.get(id, {})
	if p.is_empty():
		return
	list.erase(id)
	var n: Node3D = p.get("node")
	if n:
		n.queue_free()
	if not p.server:
		return
	if Net.online() and Net.is_server():
		Net.s_proj_end.rpc(id)
	if not notify:
		return
	var ctx := hit.duplicate()
	ctx["id"] = id
	ctx["type"] = p.type
	ctx["owner"] = p.owner
	ctx["data"] = p.data
	ctx["velocity"] = p.vel
	if not ctx.has("point"):
		ctx["point"] = p.pos
	if not ctx.has("position"):
		ctx["position"] = Vector3i((p.pos as Vector3).floor())
		ctx["normal"] = Vector3i.ZERO
		ctx["place_pos"] = ctx.position
	var owner := int(p.owner)
	if owner >= 0 and Mods.sessions.has(owner):
		Mods.as_player(owner, func(): Mods.projectile_hit(str(p.type), ctx))
	else:
		Mods.projectile_hit(str(p.type), ctx)


# ---------- klient i wygląd ----------

func client_spawn(id: int, pos: Vector3, vel: Vector3, gravity: float, life: float, vis: Dictionary) -> void:
	var p := {"type": "", "def": {}, "pos": pos, "vel": vel, "owner": -1, "data": {}, "age": 0.0,
		"server": false, "gravity": gravity, "life": life, "vis": vis}
	list[id] = p
	_make_node(id, p)


func client_end(id: int) -> void:
	_end(id, {}, false)


func _make_node(id: int, p: Dictionary) -> void:
	if Net.mode == "dedicated":
		return
	var vis: Dictionary = p.vis
	var root := Node3D.new()
	var size := float(vis.size)
	if vis.type == "block":
		var b := _reg().id_of(str(vis.block))
		if b > 0:
			var mi := MeshInstance3D.new()
			mi.mesh = BlockMesh.cube(_reg(), b, size)
			mi.material_override = world.material.duplicate()
			(mi.material_override as ShaderMaterial).set_shader_parameter("light_override", world.light_at(p.pos))
			mi.position = Vector3(-size, -size, -size) * 0.5
			root.add_child(mi)
	elif vis.type == "item" and str(vis.item) != "":
		var m := ItemModel.build(_reg(), str(vis.item))   # lecący przedmiot: model 3D
		m.scale = Vector3.ONE * size * 1.2
		root.add_child(m)
	if str(vis.trail) != "":
		var tr := Fx.build(str(vis.trail), {}, false)
		if tr:
			tr.emitting = true
			root.add_child(tr)
	add_child(root)
	root.position = p.pos
	p["node"] = root
