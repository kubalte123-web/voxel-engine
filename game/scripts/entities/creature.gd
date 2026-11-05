class_name Creature
extends CharacterBody3D
## Stworzenie opisane danymi z moda (engine.entities.register): model z klockowych części jak postać,
## animacje proceduralne (nogi, skrzydła, głowa, oddech) i klatkowe, oraz prosta sztuczna inteligencja:
## stanie, wędrówka, skubanie trawy, ucieczka po zranieniu, podążanie za graczem z jedzeniem w ręce,
## pływanie i omijanie urwisk. Mody mogą sterować stworzeniem z Lua (move_to, animate, dane, własny mózg
## engine.entities.on_think). Stworzenia wrogie (ai.hostile) gonią i atakują graczy; z polem ride można
## na nich jeździć. Model może pochodzić z pliku GLB (model = {file = ...}) z animacjami z pliku.

const LAYER := 2

var manager: Node
var world: World
var id := 0
var type := ""
var def := {}
var ai := {}
var data := {}
var health := 8.0
var max_health := 8.0
var scale_factor := 1.0

var model: Node3D
var parts := {}      # nazwa -> Node3D (punkt obrotu)
var tagged := {}     # znacznik -> [MeshInstance3D]
var mats := {}       # kolor (tekst) -> materiał
var legs: Array = [] # [Node3D, kierunek]
var wings: Array = []
var head: Node3D

var state := "idle"
var state_time := 2.0
var target := Vector3.ZERO
var has_target := false
var flee_from := Vector3.ZERO
var follow: Node3D = null
var walk_phase := 0.0
var t := 0.0
var hurt := 0.0
var dying := 0.0
var think_timer := 0.0
var anim := {}       # animacja klatkowa: {def, time}
var rng := RandomNumberGenerator.new()
var in_liquid := false
var stuck_time := 0.0
var light_timer := 0.0
var light_value := Vector2(1, 0)
var puppet := false          # kukła u klienta gry wieloosobowej: pozycja z serwera, bez AI i fizyki
var net_pos := Vector3.ZERO
var net_rot := Vector3.ZERO
var interp := NetInterp.new(0.15)   # stany stworzeń co 0,1 s
var _puppet_vel := Vector3.ZERO
var hidden_tags := {}
# model z pliku GLB
var anim_player: AnimationPlayer = null
var glb_anims := {}          # rola (idle, walk, run, attack, hurt) -> nazwa animacji w pliku
var glb_mats: Array = []
var anim_lock := 0.0         # czas jednorazowej animacji z pliku
var lunge := 0.0             # wypad do przodu przy ataku (modele bez animacji ataku)
var head_base := Vector3.ZERO
var body_base_y := 0.0
var body_part: Node3D = null
# wróg i mózg z Lua
var target_peer := -1
var attack_cd := 0.0
var think_every := 1.0
var look_point := Vector3.ZERO
var look_time := 0.0
# jazda
var rider := -1


func setup(p_manager: Node, p_world: World, p_id: int, p_type: String, p_def: Dictionary) -> void:
	manager = p_manager
	world = p_world
	id = p_id
	type = p_type
	def = p_def
	ai = def.get("ai", {}) if def.get("ai") is Dictionary else {}
	max_health = float(def.get("health", 8.0))
	health = max_health
	rng.seed = hash(id) + Time.get_ticks_usec()
	think_every = maxf(0.1, float(ai.get("think", 1.0)))


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 1 | 4
	floor_snap_length = 0.3
	var size: Array = Registry.arr(def.get("size"))
	var w := float(size[0]) if size.size() > 0 else 0.8
	var h := float(size[1]) if size.size() > 1 else 1.0
	var shape := BoxShape3D.new()
	shape.size = Vector3(w, h, w) * scale_factor
	var cs := CollisionShape3D.new()
	cs.shape = shape
	cs.position.y = h * 0.5 * scale_factor
	add_child(cs)
	model = Node3D.new()
	model.scale = Vector3.ONE * scale_factor
	add_child(model)
	_build_model()
	rotation.y = rng.randf() * TAU


static func vec(v: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	var a := Registry.arr(v)
	if a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fallback


func _mat(color: String) -> StandardMaterial3D:
	if not mats.has(color):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_string(color, Color.WHITE)
		m.roughness = 0.9
		mats[color] = m
	return mats[color]


## Części: {pivot = {x,y,z}, parent = "body", boxes = {{size, pos, color, tag}}, swing = 1|-1, wing = 1|-1, look = true}
func _build_model() -> void:
	if def.get("model") is Dictionary and str(def.model.get("file", "")) != "":
		_build_glb(def.model)
		return
	var pdefs: Dictionary = def.get("parts", {}) if def.get("parts") is Dictionary else {}
	var pending := pdefs.keys()
	var guard := 0
	while not pending.is_empty() and guard < 50:
		guard += 1
		for name in pending.duplicate():
			var pd: Dictionary = pdefs[name]
			var parent_name := str(pd.get("parent", ""))
			if parent_name != "" and not parts.has(parent_name) and pdefs.has(parent_name):
				continue
			var parent: Node3D = parts.get(parent_name, model)
			var pivot := Node3D.new()
			pivot.name = str(name)
			pivot.position = vec(pd.get("pivot"))
			parent.add_child(pivot)
			for bd in Registry.arr(pd.get("boxes")):
				if not bd is Dictionary:
					continue
				var mi := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = vec(bd.get("size"), Vector3(0.2, 0.2, 0.2))
				mi.mesh = bm
				mi.position = vec(bd.get("pos"))
				mi.rotation_degrees = vec(bd.get("rot"))
				mi.material_override = _mat(str(bd.get("color", "#ffffff")))
				pivot.add_child(mi)
				if bd.has("tag"):
					var tg := str(bd.tag)
					if not tagged.has(tg):
						tagged[tg] = []
					tagged[tg].append(mi)
			parts[name] = pivot
			if pd.has("swing"):
				legs.append([pivot, float(pd.swing), 0.0])
			if pd.has("wing"):
				wings.append([pivot, float(pd.wing), 0.0])
			if bool(pd.get("look", false)):
				head = pivot
			if str(name) == "body":
				body_part = pivot
				body_base_y = pivot.position.y
			pending.erase(name)


## Model z pliku GLB: model = {file, scale, offset, rotation, swing = {Węzeł = 1|-1}, wings = {...}, head = "Węzeł",
## body = "Węzeł", animations = {idle = "Idle", walk = "Walk", run = "Run", attack = "Attack", hurt = "Hurt"}}.
## Każdy nazwany węzeł pliku jest częścią (animacje klatkowe modów, ukrywanie i kolor po nazwie siatki).
func _build_glb(md: Dictionary) -> void:
	var inst := BlockModel.instance_glb(world.reg, str(def.get("mod", "")), str(md.file))
	if inst == null:
		return
	inst.scale = Vector3.ONE * float(md.get("scale", 1.0))
	inst.position = vec(md.get("offset"))
	inst.rotation_degrees = vec(md.get("rotation"))
	model.add_child(inst)
	_collect_glb(inst)
	var sw: Dictionary = md.get("swing", {}) if md.get("swing") is Dictionary else {}
	for n in sw:
		if parts.has(n):
			legs.append([parts[n], float(sw[n]), (parts[n] as Node3D).rotation.x])
	var wg: Dictionary = md.get("wings", {}) if md.get("wings") is Dictionary else {}
	for n in wg:
		if parts.has(n):
			wings.append([parts[n], float(wg[n]), (parts[n] as Node3D).rotation.z])
	if parts.has(str(md.get("head", ""))):
		head = parts[str(md.head)]
		head_base = head.rotation
	if parts.has(str(md.get("body", ""))):
		body_part = parts[str(md.body)]
		body_base_y = body_part.position.y
	glb_anims = md.get("animations", {}) if md.get("animations") is Dictionary else {}
	if anim_player:
		for role in ["idle", "walk", "run"]:
			var clip := str(glb_anims.get(role, ""))
			if clip != "" and anim_player.has_animation(clip):
				anim_player.get_animation(clip).loop_mode = Animation.LOOP_LINEAR


func _collect_glb(n: Node) -> void:
	if n is AnimationPlayer and anim_player == null:
		anim_player = n
	elif n is Node3D:
		parts[str(n.name)] = n
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var key := str(mi.name)
		if not tagged.has(key):
			tagged[key] = []
		tagged[key].append(mi)
		for si in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(si)
			if m is StandardMaterial3D:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				c.set_meta("base", c.albedo_color)
				glb_mats.append(c)
				mi.set_surface_override_material(si, c)
	for ch in n.get_children():
		_collect_glb(ch)


func show_tag(tag: String, on: bool) -> void:
	for mi in tagged.get(tag, []):
		mi.visible = on
	if on:
		hidden_tags.erase(tag)
	else:
		hidden_tags[tag] = true


func color_tag(tag: String, c: Color) -> void:
	for mi in tagged.get(tag, []):
		if mi.material_override == null:
			for si in (mi as MeshInstance3D).mesh.get_surface_count():
				var sm := (mi as MeshInstance3D).get_surface_override_material(si) as StandardMaterial3D
				if sm:
					sm.set_meta("base", c)
					sm.albedo_color = c
			light_timer = 0.0
			continue
		var m: StandardMaterial3D = (mi.material_override as StandardMaterial3D).duplicate()
		m.albedo_color = c
		m.set_meta("base", c)
		mi.material_override = m


func set_scale_factor(s: float) -> void:
	scale_factor = s
	if model:
		model.scale = Vector3.ONE * s
		for c in get_children():
			if c is CollisionShape3D:
				var size: Array = Registry.arr(def.get("size"))
				var w := float(size[0]) if size.size() > 0 else 0.8
				var h := float(size[1]) if size.size() > 1 else 1.0
				(c.shape as BoxShape3D).size = Vector3(w, h, w) * s
				c.position.y = h * 0.5 * s


func play(name: String) -> void:
	if anim_player:
		var clip := str(glb_anims.get(name, name))
		if anim_player.has_animation(clip):
			anim_player.play(clip, 0.1)
			anim_lock = anim_player.get_animation(clip).length
			return
	if name == "attack":
		lunge = 0.35
	var adef: Variant = Mods.registry.animations.get(name) if Mods.registry else null
	if adef is Dictionary:
		anim = {"def": adef, "time": 0.0}
	else:
		anim = {}


# ---------- sztuczna inteligencja ----------

func speed() -> float:
	var s := float(def.get("speed", 1.2))
	if state == "flee":
		s = float(def.get("panic_speed", s * 2.0))
	elif state == "chase":
		s = float(hostile().get("speed", s * 1.4))
	return s * (0.6 if in_liquid else 1.0)


## Ustawienia ataku: ai.hostile = true albo {damage, range, sight, cooldown, speed, knockback}.
func hostile() -> Dictionary:
	var h: Variant = ai.get("hostile")
	var out := {"damage": 2.0, "range": 1.6, "sight": 16.0, "cooldown": 1.0, "knockback": 4.0}
	if h is Dictionary:
		out.merge(h, true)
	return out


func is_hostile() -> bool:
	var h: Variant = ai.get("hostile")
	return h is Dictionary or (h is bool and h)


## Gonienie gracza (peer) – przez wrogie stworzenie albo na polecenie moda (engine.entities.attack).
func chase(peer: int, time := 30.0) -> void:
	target_peer = peer
	set_state("chase", time)


func set_state(s: String, time: float) -> void:
	state = s
	state_time = time
	has_target = false


## Cel podany z Lua (engine.entities.move_to): stworzenie idzie tam, dopóki go nie osiągnie.
func move_to(p: Vector3) -> void:
	state = "script"
	state_time = 20.0
	target = p
	has_target = true


func _pick_wander_target() -> void:
	for i in 6:
		var a := rng.randf() * TAU
		var d := rng.randf_range(3.0, 9.0)
		var p := global_position + Vector3(cos(a), 0, sin(a)) * d
		var x := floori(p.x)
		var z := floori(p.z)
		var gy := _ground_y(x, z, floori(global_position.y) + 3)
		if gy == -99999 or absi(gy - floori(global_position.y)) > 3:
			continue
		if not bool(ai.get("swim", true)) and world.reg.is_liquid(world.get_block(Vector3i(x, gy, z))):
			continue
		if world.reg.is_liquid(world.get_block(Vector3i(x, gy, z))) and not in_liquid and rng.randf() < 0.8:
			continue  # zwierzęta raczej omijają wodę
		target = Vector3(x + 0.5, gy + 1, z + 0.5)
		has_target = true
		return


## Najwyższy blok stały albo ciecz pod (x, z), szukając od y w dół.
func _ground_y(x: int, z: int, from_y: int) -> int:
	for y in range(from_y, from_y - 8, -1):
		var b := world.get_block(Vector3i(x, y, z))
		if b != Blocks.AIR and ((Blocks.props(b) & Blocks.SOLID) != 0 or world.reg.is_liquid(b)):
			return y
	return -99999


func _think() -> void:
	# wróg: najbliższy gracz w zasięgu wzroku
	if is_hostile() and state != "chase" and state != "script" and rider < 0:
		var pl: Node3D = manager.nearest_player(global_position)
		if pl and float(pl.health) > 0.0 and pl.global_position.distance_to(global_position) < float(hostile().sight):
			chase(EntityManager.peer_of(pl))
	# podążanie za graczem z ulubionym jedzeniem w ręce
	var food := str(ai.get("follow", ""))
	var pl: Node3D = manager.nearest_player(global_position)
	if food != "" and pl and state != "flee" and state != "script":
		var held := str(pl.current_item().get("item", ""))
		var d := pl.global_position.distance_to(global_position)
		if held == food and d < 10.0:
			follow = pl
			set_state("follow", 3.0)
			return
	if state == "follow":
		follow = null
	var snd: Variant = def.get("sounds")
	if snd is Dictionary and snd.has("idle") and dying <= 0.0 and randf() < 1.0 / maxf(1.0, float(snd.get("idle_every", 14.0))):
		Sfx.emit(str(snd.idle), global_position + Vector3(0, 0.8, 0), 1.0, _voice())
	if Mods.entity_brains.has(type):
		var near: Node3D = manager.nearest_player(global_position)
		var ctx := {"id": id, "type": type, "state": state, "pos": global_position, "health": health,
			"max_health": max_health, "data": data, "target": target_peer, "rider": rider, "in_liquid": in_liquid,
			"on_floor": is_on_floor()}
		if near:
			ctx["player"] = EntityManager.peer_of(near)
			ctx["player_distance"] = near.global_position.distance_to(global_position)
		Mods.entity_think(type, ctx)
	if Mods.has_hook("event", "entity.tick"):
		Mods.emit_event("entity.tick", {"id": id, "type": type, "state": state, "pos": global_position, "data": data})


func _brain(delta: float) -> void:
	state_time -= delta
	think_timer -= delta
	attack_cd -= delta
	look_time -= delta
	if think_timer <= 0.0:
		think_timer = think_every * (1.0 + rng.randf() * 0.3)
		_think()
	match state:
		"idle":
			if state_time <= 0.0:
				var r := rng.randf()
				if ai.has("graze") and r < 0.25:
					set_state("graze", 2.5)
				elif r < 0.8 and bool(ai.get("wander", true)):
					set_state("wander", 8.0)
					_pick_wander_target()
				else:
					set_state("idle", rng.randf_range(2.0, 5.0))
		"wander":
			if not has_target or state_time <= 0.0:
				set_state("idle", rng.randf_range(1.5, 5.0))
		"graze":
			if state_time <= 0.0:
				_graze()
				set_state("idle", rng.randf_range(1.0, 3.0))
		"flee":
			if state_time <= 0.0:
				set_state("idle", 1.0)
			elif not has_target or global_position.distance_to(target) < 1.5:
				var away := (global_position - flee_from)
				away.y = 0
				away = away.normalized() if away.length() > 0.01 else Vector3(1, 0, 0)
				away = away.rotated(Vector3.UP, rng.randf_range(-0.7, 0.7))
				target = global_position + away * 6.0
				has_target = true
		"follow":
			if follow == null or state_time <= 0.0:
				set_state("idle", 1.0)
			else:
				var d := follow.global_position.distance_to(global_position)
				has_target = d > 2.2
				target = follow.global_position
		"script":
			if not has_target or state_time <= 0.0:
				set_state("idle", 1.0)
		"chase":
			var pl: Node3D = manager.player_node(target_peer)
			var h := hostile()
			var d := pl.global_position.distance_to(global_position) if pl else INF
			if pl == null or float(pl.health) <= 0.0 or state_time <= 0.0 or d > float(h.sight) * 1.6:
				target_peer = -1
				set_state("idle", 1.0)
			else:
				target = pl.global_position
				has_target = d > float(h.range) * 0.7
				if not has_target:
					var to := pl.global_position - global_position
					rotation.y = lerp_angle(rotation.y, atan2(-to.x, -to.z), minf(1.0, delta * 8.0))
				if d <= float(h.range) and attack_cd <= 0.0 and absf(pl.global_position.y - global_position.y) < 2.0:
					_attack(pl, h)
		_:
			# stan ustawiony przez mod (engine.entities.set_state): stoi, aż minie czas
			if state_time <= 0.0 and state != "ridden":
				set_state("idle", 1.0)


func _attack(pl: Node3D, h: Dictionary) -> void:
	attack_cd = float(h.cooldown)
	var peer := EntityManager.peer_of(pl)
	var ctx := Mods.before("entity.attack", {"id": id, "type": type, "player": peer, "amount": float(h.damage)})
	if ctx.get("cancel", false):
		return
	play("attack")
	Net.entity_anim(id, "attack")
	var amount := float(ctx.get("amount", h.damage))
	Mods.as_player(peer, func(): pl.damage(amount, "entity:" + type))
	var push := pl.global_position - global_position
	push.y = 0.0
	pl.push(push.normalized() * float(h.knockback) + Vector3(0, 3.0, 0))
	Mods.after("entity.attack", ctx)


## Skubanie trawy: blok pod stworzeniem może się zmienić (np. trawa w ziemię), mod dostaje zdarzenie.
func _graze() -> void:
	var g: Dictionary = ai.graze if ai.get("graze") is Dictionary else {}
	var below := Vector3i(floori(global_position.x), floori(global_position.y - 0.5), floori(global_position.z))
	var b := world.get_block(below)
	if Blocks.key(b) != str(g.get("from", "grass")):
		return
	var to := Blocks.id(str(g.get("to", "")))
	if to >= 0 and rng.randf() < float(g.get("chance", 0.5)):
		world.set_block(below, to)
	Mods.emit_event("entity.graze", {"id": id, "type": type, "pos": below})


# ---------- ruch i animacja ----------

## Kukła u klienta: płynnie z bufora interpolacji, co klatkę ekranu (jazda gracza lokalnego ustawia pozycję sama).
func _process(delta: float) -> void:
	if not puppet or dying > 0.0 or (manager.player and manager.player.mount_id == id):
		return
	_puppet_vel = EntityManager.puppet_follow(self, interp, net_pos, net_rot, delta, false)


func _physics_process(delta: float) -> void:
	t += delta
	if dying > 0.0:
		dying -= delta
		model.scale = Vector3.ONE * scale_factor * maxf(0.05, dying / 0.4)
		model.rotation.z = (1.0 - dying / 0.4) * 1.4
		if dying <= 0.0:
			manager.remove(id)
		return
	# jazda: stworzenie idzie razem z jeźdźcem (gracz steruje, stworzenie daje prędkość i wygląd)
	var mounted_by: Node3D = null
	if rider >= 0:
		mounted_by = manager.player_node(rider)
		if mounted_by == null or float(mounted_by.health) <= 0.0:
			manager.dismount(rider)
			mounted_by = null
	elif puppet and manager.player and manager.player.mount_id == id:
		mounted_by = manager.player
	if mounted_by:
		collision_layer = 0
		global_position = mounted_by.global_position
		rotation.y = lerp_angle(rotation.y, float(mounted_by.yaw), minf(1.0, delta * 12.0))
		var mv: Vector3 = mounted_by.velocity
		velocity = mv
		_animate(delta, Vector2(mv.x, mv.z).length())
		return
	if collision_layer == 0 and rider < 0:
		collision_layer = LAYER
	if puppet:
		_animate(delta, Vector2(_puppet_vel.x, _puppet_vel.z).length())   # pozycja i obrót w _process
		return
	if not world.physics_ready(global_position):
		return  # chunk niegotowy albo daleko od graczy (bez kolizji): stoimy w miejscu
	_brain(delta)
	var feet := Vector3i(floori(global_position.x), floori(global_position.y + 0.2), floori(global_position.z))
	var mid := Vector3i(feet.x, floori(global_position.y + 0.6 * scale_factor), feet.z)
	in_liquid = world.reg.is_liquid(world.get_block(feet)) or world.reg.is_liquid(world.get_block(mid))
	var dir := Vector3.ZERO
	if has_target:
		var to := target - global_position
		to.y = 0
		if to.length() < 0.6:
			has_target = false
		else:
			dir = to.normalized()
			# urwisko przed nami: nie idziemy dalej
			if bool(ai.get("avoid_cliffs", true)) and is_on_floor():
				var ahead := global_position + dir * 0.9
				var gy := _ground_y(floori(ahead.x), floori(ahead.z), floori(global_position.y))
				if gy == -99999 or global_position.y - gy > 3.5:
					has_target = false
					dir = Vector3.ZERO
	var sp := speed()
	var flow := world.liquids.flow_at(feet) * 1.6 if in_liquid else Vector3.ZERO
	velocity.x = lerpf(velocity.x, dir.x * sp + flow.x, minf(1.0, delta * 8.0))
	velocity.z = lerpf(velocity.z, dir.z * sp + flow.z, minf(1.0, delta * 8.0))
	if in_liquid:
		# zwierzęta unoszą się na wodzie i wychodzą na brzeg
		velocity.y = lerpf(velocity.y, 1.2, minf(1.0, delta * 3.0))
		if is_on_wall() and dir.length() > 0.1:
			velocity.y = 5.0
	elif is_on_floor():
		if is_on_wall() and dir.length() > 0.1:
			velocity.y = 6.2 * clampf(scale_factor, 0.7, 1.0)
	else:
		velocity.y -= 22.0 * delta
		if bool(ai.get("slow_fall", false)):
			velocity.y = maxf(velocity.y, -2.0)  # kurczak trzepocze skrzydłami
	if hurt > 0.0:
		hurt -= delta
	move_and_slide()
	# utknięcie przy ścianie: nowy cel
	if dir.length() > 0.1 and Vector2(velocity.x, velocity.z).length() < 0.2:
		stuck_time += delta
		if stuck_time > 1.5:
			stuck_time = 0.0
			has_target = false
	else:
		stuck_time = 0.0
	if global_position.y < -90.0:
		manager.remove(id)
		return
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if hspeed > 0.2:
		rotation.y = lerp_angle(rotation.y, atan2(-velocity.x, -velocity.z), minf(1.0, delta * 6.0))
	_animate(delta, hspeed)


func _animate(delta: float, hspeed: float) -> void:
	var moving := clampf(hspeed / maxf(0.5, float(def.get("speed", 1.2))), 0.0, 1.6)
	walk_phase += delta * (3.0 + hspeed * 3.5) * (1.0 if moving > 0.05 else 0.0)
	var s := sin(walk_phase)
	for l in legs:
		var node: Node3D = l[0]
		node.rotation.x = lerpf(node.rotation.x, float(l[2]) + s * 0.75 * moving * float(l[1]), minf(1.0, delta * 12.0))
	var flap := not is_on_floor() and not in_liquid
	for w in wings:
		var node: Node3D = w[0]
		var want := (sin(t * 26.0) * 0.9 + 0.9) * float(w[1]) if flap else 0.0
		node.rotation.z = lerpf(node.rotation.z, float(w[2]) + want, minf(1.0, delta * 14.0))
	if head:
		var hp := 0.0
		if state == "graze":
			hp = -0.9 + sin(t * 9.0) * 0.12
		elif look_time > 0.0 or (_look_target() and _look_target().global_position.distance_to(global_position) < 6.0):
			var to: Vector3 = (look_point if look_time > 0.0 else _look_target().global_position) - global_position
			var local := to.rotated(Vector3.UP, -rotation.y)
			head.rotation.y = lerp_angle(head.rotation.y, head_base.y + clampf(atan2(-local.x, -local.z), -0.8, 0.8), minf(1.0, delta * 4.0))
		else:
			head.rotation.y = lerp_angle(head.rotation.y, head_base.y, minf(1.0, delta * 3.0))
		head.rotation.x = lerpf(head.rotation.x, head_base.x + hp, minf(1.0, delta * 6.0))
	if body_part:
		body_part.position.y = body_base_y + absf(s) * 0.04 * moving + sin(t * 2.0) * 0.01
	# wypad do przodu przy ataku
	if lunge > 0.0:
		lunge = maxf(0.0, lunge - delta)
		model.rotation.x = -sin(lunge / 0.35 * PI) * 0.3
	# animacje z pliku: chód albo spoczynek, chyba że trwa jednorazowa (atak, zranienie)
	if anim_player:
		if anim_lock > 0.0:
			anim_lock -= delta
		else:
			var role := "idle"
			if hspeed > 0.3:
				role = "run" if hspeed > float(def.get("speed", 1.2)) * 1.6 and glb_anims.has("run") else "walk"
			var clip := str(glb_anims.get(role, ""))
			if clip != "" and anim_player.has_animation(clip):
				if anim_player.current_animation != clip:
					anim_player.play(clip, 0.2)
				anim_player.speed_scale = clampf(hspeed / maxf(0.3, float(def.get("speed", 1.2))), 0.6, 2.5) if role != "idle" else 1.0
	# światło z mapy światła i czerwony błysk po zranieniu
	light_timer -= delta
	if light_timer <= 0.0 or hurt > 0.0:
		light_timer = 0.25
		light_value = world.light_at(global_position + Vector3(0, 0.6, 0))
		var all_mats := mats.values()
		all_mats.append_array(glb_mats)
		for list in tagged.values():
			for mi in list:
				if not all_mats.has(mi.material_override):
					all_mats.append(mi.material_override)
		EntityLight.apply(all_mats, light_value, Color(0.5, 0.05, 0.05) if hurt > 0.0 else Color(0, 0, 0))
	if not anim.is_empty():
		var adef: Dictionary = anim.def
		var length := maxf(0.05, float(adef.get("length", 1.0)))
		anim.time += delta
		if anim.time > length:
			if bool(adef.get("loop", false)):
				anim.time = fmod(anim.time, length)
			else:
				anim = {}
				return
		var tracks: Dictionary = adef.get("tracks", {}) if adef.get("tracks") is Dictionary else {}
		for pn in tracks:
			if parts.has(pn):
				var smp := CharacterModel._sample(Registry.arr(tracks[pn]), anim.time)
				if not smp.is_empty():
					(parts[pn] as Node3D).rotation = smp.rot * (PI / 180.0)


var _look_cache: Node3D = null
var _look_t := 0.0


func _look_target() -> Node3D:
	if Time.get_ticks_msec() / 1000.0 - _look_t > 0.5:
		_look_t = Time.get_ticks_msec() / 1000.0
		_look_cache = manager.nearest_player(global_position) if not puppet else manager.player
	return _look_cache if is_instance_valid(_look_cache) else null


# ---------- obrażenia ----------

func hit(amount: float, from: Vector3, cause: String) -> void:
	if dying > 0.0:
		return
	var ctx := Mods.before("entity.damage", {"id": id, "type": type, "amount": amount, "cause": cause})
	if ctx.get("cancel", false):
		return
	health -= float(ctx.get("amount", amount))
	hurt = 0.3
	var snd: Variant = def.get("sounds")
	if snd is Dictionary and (snd.has("hurt") or snd.has("idle")):
		Sfx.emit(str(snd.get("hurt", snd.get("idle"))), global_position + Vector3(0, 0.8, 0), 1.0, _voice() * 1.15)
	var push := global_position - from
	push.y = 0
	velocity += push.normalized() * 5.0 + Vector3(0, 4.0, 0)
	Mods.after("entity.damage", ctx)
	if health <= 0.0:
		die(cause)
		return
	if anim_player and glb_anims.has("hurt"):
		play("hurt")
	if is_hostile() or bool(ai.get("retaliate", false)):
		var pl: Node3D = manager.nearest_player(from)
		if pl and pl.global_position.distance_to(from) < 3.0:
			chase(EntityManager.peer_of(pl), 20.0)
			return
	if bool(ai.get("flee", not is_hostile())):
		flee_from = from
		set_state("flee", 5.0)


## Wysokość głosu: młode (mniejsze) piszczą wyżej.
func _voice() -> float:
	return clampf(1.0 / sqrt(maxf(0.3, scale_factor)), 0.7, 1.8)


func die(cause: String) -> void:
	if dying > 0.0:
		return
	dying = 0.4
	Mods.emit_event("entity.death", {"id": id, "type": type, "pos": global_position, "cause": cause, "data": data})
	var rng2 := RandomNumberGenerator.new()
	rng2.randomize()
	for d in Registry.arr(def.get("drops")):
		if d is Dictionary and (not d.has("chance") or rng2.randf() < float(d.chance)):
			var n := int(d.get("count", 1))
			if d.has("max"):
				n = rng2.randi_range(n, int(d.max))
			if n > 0 and not (bool(d.get("adult_only", false)) and scale_factor < 0.9):
				manager.drop_item(str(d.item), n, global_position + Vector3(0, 0.5, 0))


func save_state() -> Dictionary:
	var p := global_position
	return {"type": type, "pos": [p.x, p.y, p.z], "yaw": rotation.y, "health": health, "data": data, "scale": scale_factor}
