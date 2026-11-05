class_name BlockLogic
extends RefCounted
## Logika bloków po stronie serwera: dane bloków (np. zawartość pieca), kontenery bloków (skrzynie),
## aktualizacje bloków dla modów (losowe, zaplanowane, od zmiany sąsiada). Zapis w świecie: blocks.dat.
##
## Mody rejestrują obsługę przez engine.blocks.on_update(klucz, fn). Silnik wywołuje ją:
## - "random": losowo, średnio co `random_tick` sekund (pole w definicji bloku, np. uprawy),
## - "scheduled": po czasie z engine.blocks.schedule(pos, sekundy, tag),
## - "neighbor": gdy zmienił się blok obok (ctx.from to pozycja zmiany).

const FILE := "blocks.dat"
const NEIGHBORS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const MAX_UPDATES_PER_TICK := 512

var world: World
var main: Node
var data := {}          # Vector3i -> Dictionary (dane modów)
var containers := {}    # Vector3i -> id kontenera ("@x,y,z")
var looks := {}         # Vector3i -> wygląd modelu ustawiony przez mod (engine.blocks.look)
var scheduled := []     # [czas, pozycja, tag, klucz bazowy]
var listen := PackedByteArray()      # id bloku -> 1 gdy jakiś mod obsługuje jego aktualizacje
var random_rate := PackedFloat32Array()  # id bloku -> średni odstęp losowych aktualizacji (0 = brak)
var random_blocks := {} # chunk -> {pozycja: true} bloki z losowymi aktualizacjami
var queue := []         # [pozycja, powód, skąd]
var clock := 0.0
var _rng := RandomNumberGenerator.new()
var _any_random := false


func _init(w: World, m: Node) -> void:
	world = w
	main = m
	listen.resize(256)
	random_rate.resize(256)


# ---------- rejestracja ----------

## Mod obsługuje aktualizacje bloku `key` (wszystkich jego wariantów).
func add_listener(key: String) -> void:
	var reg := world.reg
	var base := reg.id_of(key)
	if base <= 0:
		return
	for id in reg.count():
		if reg.base_of(id) == base:
			listen[id] = 1
			var rt: Variant = reg.def_of(id).get("random_tick", 0)
			var interval := 60.0 if rt is bool and rt else float(rt) if (rt is float or rt is int) else 0.0
			if interval > 0.0:
				random_rate[id] = interval
				_any_random = true
	if _any_random:
		random_blocks.clear()
		for c in world.built:
			chunk_loaded(c)


# ---------- chunki: śledzenie bloków z losowymi aktualizacjami ----------

func chunk_loaded(c: Vector3i) -> void:
	if not _any_random or not world.data.has(c):
		return
	var d: PackedByteArray = world.data[c]
	var found := {}
	for id in 256:
		if random_rate[id] <= 0.0:
			continue
		var i := d.find(id)
		while i >= 0:
			found[c * World.S + Vector3i(i % World.S, (i / World.S) % World.S, i / (World.S * World.S))] = true
			i = d.find(id, i + 1)
	if found.is_empty():
		random_blocks.erase(c)
	else:
		random_blocks[c] = found


func chunk_unloaded(c: Vector3i) -> void:
	random_blocks.erase(c)


# ---------- zmiana bloku (wywoływana przez World na serwerze) ----------

func block_changed(p: Vector3i, old: int, id: int) -> void:
	var reg := world.reg
	if reg.base_of(old) != reg.base_of(id) and (data.has(p) or containers.has(p) or looks.has(p)):
		_removed(p, old)
	if _any_random:
		var c := world.chunk_of(p)
		if random_rate[id] > 0.0:
			if not random_blocks.has(c):
				random_blocks[c] = {}
			random_blocks[c][p] = true
		elif random_blocks.has(c):
			random_blocks[c].erase(p)
	for n in NEIGHBORS:
		var q: Vector3i = p + n
		if listen[world.get_block(q)]:
			queue.append([q, "neighbor", p])


## Blok zniknął (zniszczony albo zamieniony na inny): mody dostają jego dane, przedmioty z kontenera wypadają.
func _removed(p: Vector3i, old: int) -> void:
	var d: Dictionary = data.get(p, {})
	Mods.emit_event("block.removed", {"pos": p, "block": old, "key": world.reg.block_key(world.reg.base_of(old)), "data": d})
	data.erase(p)
	if looks.has(p):
		set_look(p, {}, true)
	if containers.has(p):
		var cid: String = containers[p]
		containers.erase(p)
		if Mods.containers.has(cid):
			for sl in Mods.container_slots(cid):
				if sl is Dictionary and not sl.is_empty() and main and main.entities:
					main.entities.drop_item(str(sl.item), int(sl.count), Vector3(p) + Vector3(0.5, 0.5, 0.5), sl.get("data", {}) if sl.get("data") is Dictionary else {})
			Mods.containers.erase(cid)


# ---------- dane i kontenery ----------

func get_data(p: Vector3i) -> Dictionary:
	return data.get(p, {})


func set_data(p: Vector3i, key: String, value: Variant) -> void:
	if world.get_block(p) == Blocks.AIR:
		return
	if not data.has(p):
		data[p] = {}
	if value == null:
		data[p].erase(key)
		if data[p].is_empty():
			data.erase(p)
	else:
		data[p][key] = value


func container(mod_id: String, p: Vector3i, size: int) -> String:
	var cid := "@%d,%d,%d" % [p.x, p.y, p.z]
	if world.get_block(p) == Blocks.AIR:
		return ""
	containers[p] = cid
	if not Mods.containers.has(cid):
		Mods.containers[cid] = {"owner": mod_id, "persist": true, "slots": []}
	var slots: Array = Mods.containers[cid].slots
	while slots.size() < size:
		slots.append({})
	return cid


# ---------- wygląd modeli ----------

## Wygląd modelu bloku: {anim, emitters, colors, hide}. merge = false zastępuje cały wygląd.
func set_look(p: Vector3i, look: Dictionary, replace := false) -> void:
	var cur: Dictionary = {} if replace else looks.get(p, {}).duplicate(true)
	for k in look:
		if k == "colors" and cur.get("colors") is Dictionary and look[k] is Dictionary:
			var c: Dictionary = cur.colors
			c.merge(look[k], true)
		elif look[k] == null:
			cur.erase(k)
		else:
			cur[k] = look[k]
	if cur.is_empty():
		looks.erase(p)
	else:
		looks[p] = cur
	world.models.set_look(p, cur)
	if Net.online() and Net.is_server():
		Net.s_block_look.rpc(p, cur)


func animate(p: Vector3i, name: String) -> void:
	world.models.play(p, name)
	if Net.online() and Net.is_server():
		for peer in Mods.sessions:
			var s: Session = Mods.sessions[peer]
			if not s.local and s.logged_in and s.node and s.node.global_position.distance_to(Vector3(p)) < 64.0:
				Net.s_block_anim.rpc_id(peer, p, name)


# ---------- aktualizacje ----------

func schedule(p: Vector3i, seconds: float, tag: String) -> void:
	var base := world.reg.base_of(world.get_block(p))
	scheduled.append([clock + maxf(0.05, seconds), p, tag, world.reg.block_key(base)])


## Wywoływane 10 razy na sekundę na serwerze.
func tick(dt: float) -> void:
	clock += dt
	# zaplanowane
	if not scheduled.is_empty():
		var due := []
		var keep := []
		for s in scheduled:
			(due if s[0] <= clock else keep).append(s)
		if not due.is_empty():
			scheduled = keep
			for s in due:
				var p: Vector3i = s[1]
				if not world.is_loaded(p):
					s[0] = clock + 1.0   # chunk nie jest wczytany: spróbujemy później
					scheduled.append(s)
					continue
				var id := world.get_block(p)
				if listen[id] and world.reg.block_key(world.reg.base_of(id)) == str(s[3]):
					_call(p, id, "scheduled", {"tag": s[2]})
	# losowe
	for c in random_blocks.keys():
		if not world.built.has(c):
			continue
		for p in random_blocks[c].keys():
			var id := world.get_block(p)
			var rate := random_rate[id]
			if rate <= 0.0:
				random_blocks[c].erase(p)
				continue
			if _rng.randf() < dt / rate:
				_call(p, id, "random", {})
	# od sąsiadów (kolejka, żeby łańcuchy zmian nie zawiesiły gry)
	var n := 0
	while not queue.is_empty() and n < MAX_UPDATES_PER_TICK:
		var q: Array = queue.pop_front()
		var p: Vector3i = q[0]
		var id := world.get_block(p)
		if listen[id] and world.is_loaded(p):
			_call(p, id, "neighbor", {"from": q[2], "from_block": world.get_block(q[2])})
		n += 1


func _call(p: Vector3i, id: int, reason: String, extra: Dictionary) -> void:
	var reg := world.reg
	var base := reg.base_of(id)
	var ctx := {"pos": p, "block": id, "key": reg.block_key(base), "state": reg.state_of(id), "reason": reason,
		"data": data.get(p, {})}
	ctx.merge(extra)
	Mods.block_update(reg.block_key(base), ctx)


# ---------- zapis ----------

func save(dir: String) -> void:
	if dir.is_empty():
		return
	var sched := []
	for s in scheduled:
		sched.append([float(s[0]) - clock, s[1], s[2], s[3]])
	var f := FileAccess.open(dir.path_join(FILE), FileAccess.WRITE)
	if f:
		f.store_var({"version": 1, "data": data, "containers": containers, "scheduled": sched, "looks": looks})


func load_from(dir: String) -> void:
	if dir.is_empty() or not FileAccess.file_exists(dir.path_join(FILE)):
		return
	var f := FileAccess.open(dir.path_join(FILE), FileAccess.READ)
	var v: Variant = f.get_var() if f else null
	if not v is Dictionary:
		return
	data = v.get("data", {})
	containers = v.get("containers", {})
	looks = v.get("looks", {})
	for p in looks:
		world.models.looks[p] = looks[p]
	scheduled = []
	for s in v.get("scheduled", []):
		scheduled.append([clock + float(s[0]), s[1], s[2], s[3]])
