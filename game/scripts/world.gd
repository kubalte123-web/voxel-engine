class_name World
extends Node3D
## Zarządza chunkami: generuje je i buduje siatki w tle, wczytuje wokół gracza, usuwa dalekie
## oraz zapisuje i wczytuje chunki zmienione przez gracza.

const S := 32
const P := S + 2

var terrain: Terrain
var reg: Registry
var tiles: PackedInt32Array
var props: PackedInt32Array
var atlas: Texture2D
var material: ShaderMaterial
var light := {}        # Vector3i -> PackedByteArray S^3 (niebo << 4 | bloki), do oświetlania stworzeń
var heightmap := {}    # Vector2i (kolumna chunków) -> PackedInt32Array S^2: najwyższy nieprzezroczysty blok
var relight := {}      # chunki policzone bez wszystkich sąsiadów: przeliczymy, gdy się wczytają
var light_margin := 15
var water_material: ShaderMaterial
var water_nodes := {}  # Vector3i -> MeshInstance3D (powierzchnia cieczy)
var liquids: LiquidSim
var falling: Node3D    # spadające bloki (piasek, żwir)
var save_dir := ""  # pusty = świat tymczasowy, bez zapisu

var radius := 6
var y_min := -2
var y_max := 1
var max_queued := 4
var threaded := true

var native: Object = null
var mesher_name := "GDScript"

var data := {}     # Vector3i -> PackedByteArray (S^3), bloki chunka
var edited := {}   # chunki zmienione przez gracza (nie usuwamy ich danych)
var unsaved := {}  # chunki zmienione od ostatniego zapisu
var nodes := {}    # Vector3i -> MeshInstance3D
var built := {}    # chunki gotowe (także puste, bez siatki)
var queued := {}   # chunki w trakcie budowy
var dirty := {}    # chunki do ponownej budowy po zakończeniu bieżącej
var sync_queue: Array[Vector3i] = []
var results: Array = []
var mutex := Mutex.new()

var center := Vector3i(999999, 0, 0)
var offsets: Array[Vector3i] = []
var mesh_ms_total := 0.0
var mesh_count := 0


func setup(t: Terrain, dir: String, registry: Registry) -> void:
	terrain = t
	save_dir = dir
	reg = registry
	y_max = terrain.max_chunk_y()


func _ready() -> void:
	if reg == null:
		reg = Blocks.reg
	if terrain == null:
		terrain = Terrain.new()
	tiles = reg.tiles
	props = reg.props
	atlas = reg.atlas
	water_material = make_water_material(reg)
	liquids = LiquidSim.new()
	liquids.world = self
	add_child(liquids)
	falling = Node3D.new()
	falling.name = "Falling"
	add_child(falling)
	material = ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/terrain.gdshader")
	material.set_shader_parameter("atlas", atlas)
	if ClassDB.class_exists("VoxelMesher"):
		native = ClassDB.instantiate("VoxelMesher")
		native.call("configure", terrain.native_noises(), terrain.spec, tiles, props, reg.liquid, Registry.ATLAS_COLS, reg.atlas_rows)
		native.call("set_light_props", reg.lprops)
		mesher_name = "C++"
	else:
		light_margin = 6  # wersja w GDScript (przeglądarka): mniejszy zasięg światła spoza chunka
	if OS.has_feature("web"):
		threaded = false
	max_queued = maxi(2, OS.get_processor_count())
	set_radius(Settings.render_distance)


func _build_offsets() -> void:
	offsets.clear()
	for x in range(-radius, radius + 1):
		for z in range(-radius, radius + 1):
			if x * x + z * z > radius * radius + 1:
				continue
			for y in range(y_min, y_max + 1):
				offsets.append(Vector3i(x, y, z))
	offsets.sort_custom(func(a: Vector3i, b: Vector3i) -> bool:
		return a.x * a.x + a.z * a.z + a.y * a.y * 4 < b.x * b.x + b.z * b.z + b.y * b.y * 4)


func set_radius(r: int) -> void:
	radius = r
	_build_offsets()


static func chunk_of(p: Vector3i) -> Vector3i:
	return Vector3i(floori(p.x / float(S)), floori(p.y / float(S)), floori(p.z / float(S)))


func update_center(world_pos: Vector3) -> void:
	var c := chunk_of(Vector3i(floori(world_pos.x), floori(world_pos.y), floori(world_pos.z)))
	center = Vector3i(c.x, 0, c.z)


func _process(_delta: float) -> void:
	if center.x == 999999:
		return
	_collect_results()
	_schedule_missing()
	if queued.size() < max_queued:
		_process_relight()
	_unload_far()
	if not threaded and not sync_queue.is_empty():
		var c: Vector3i = sync_queue.pop_front()
		_job(c)


func _collect_results() -> void:
	mutex.lock()
	var ready := results
	results = []
	mutex.unlock()
	for r in ready:
		_apply(r[0], r[1], r[2], r[3])
		if r.size() > 4:
			_apply_light(r[0], r[4], r[5], r[6])


func _apply_light(c: Vector3i, il: PackedByteArray, tops: PackedInt32Array, exact: bool) -> void:
	if not built.has(c):
		return
	light[c] = il
	var col := Vector2i(c.x, c.z)
	var hm: Variant = heightmap.get(col)
	if hm != null:
		var changed := false
		var h: PackedInt32Array = hm
		for i in S * S:
			if tops[i] > h[i]:
				h[i] = tops[i]
				changed = true
		if changed:
			mutex.lock()
			heightmap[col] = h
			mutex.unlock()
	if not exact and native != null:
		relight[c] = true
	else:
		relight.erase(c)


## Chunki policzone bez części sąsiadów przeliczamy, gdy sąsiedzi są już wczytani (bez szwów światła).
func _process_relight() -> void:
	var budget := 2
	for c in relight.keys():
		if budget <= 0:
			return
		if not built.has(c):
			relight.erase(c)
			continue
		var all := true
		for dz in range(-1, 2):
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var n: Vector3i = c + Vector3i(dx, dy, dz)
					if not data.has(n) and n.y >= y_min and n.y <= y_max:
						all = false
		if all and not queued.has(c):
			relight.erase(c)
			_remesh(c)
			budget -= 1


func _schedule_missing() -> void:
	var budget := max_queued - queued.size()
	if budget <= 0:
		return
	for o in offsets:
		var c := Vector3i(center.x + o.x, o.y, center.z + o.z)
		if built.has(c) or queued.has(c):
			continue
		_schedule(c)
		budget -= 1
		if budget <= 0:
			return


func _schedule(c: Vector3i) -> void:
	if not data.has(c):
		_load_chunk(c)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			ensure_heightmap(Vector2i(c.x + dx, c.z + dz))
	queued[c] = true
	if threaded:
		WorkerThreadPool.add_task(_job.bind(c))
	else:
		sync_queue.append(c)


func _unload_far() -> void:
	var limit := radius + 2
	for c in built.keys():
		if absi(c.x - center.x) > limit or absi(c.z - center.z) > limit:
			if queued.has(c):
				continue
			built.erase(c)
			if nodes.has(c):
				nodes[c].queue_free()
				nodes.erase(c)
			if water_nodes.has(c):
				water_nodes[c].queue_free()
				water_nodes.erase(c)
			light.erase(c)
			relight.erase(c)
			if unsaved.has(c):
				_save_chunk(c)
			if not edited.has(c) or not save_dir.is_empty():
				data.erase(c)
				edited.erase(c)


## Wykonywane w wątku roboczym: dane chunka z obwódką sąsiadów, potem budowa siatki.
func _job(c: Vector3i) -> void:
	var t0 := Time.get_ticks_usec()
	mutex.lock()
	var own: Variant = data.get(c)
	var neigh := []
	for n in GDMesher.NORMALS:
		neigh.append(data.get(c + n))
	var around := []
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				around.append(data.get(c + Vector3i(dx, dy, dz)))
	var hms := []
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			hms.append(heightmap.get(Vector2i(c.x + dx, c.z + dz)))
	mutex.unlock()
	var padded: PackedByteArray
	var blocks: PackedByteArray
	var arrays: Array
	if native != null:
		var prep: Array = native.call("prepare", c, own if own != null else PackedByteArray(), neigh)
		padded = prep[0]
		blocks = prep[1]
	else:
		padded = terrain.fill_padded(c)
		if own == null:
			blocks = Terrain.interior(padded)
		else:
			blocks = own
			Terrain.write_interior(padded, blocks)
		for i in 6:
			if neigh[i] != null:
				_copy_border(padded, neigh[i], i)
	# światło: chunk z marginesem; brakujący sąsiedzi są przybliżani mapą wysokości
	around[13] = blocks
	var exact := true
	for k in 27:
		var ny := c.y + (k / 3) % 3 - 1
		if around[k] == null and ny >= y_min and ny <= y_max:
			exact = false
	var skyh := _skyh_region(c, hms)
	var lres: Array
	if native != null:
		lres = native.call("light", c, around, skyh, light_margin)
		arrays = native.call("build", padded, lres[0])
	else:
		lres = LightCalc.compute(c, around, skyh, light_margin, reg.lprops)
		arrays = GDMesher.build(padded, tiles, Registry.ATLAS_COLS, reg.atlas_rows, props, reg.liquid, lres[0])
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	mutex.lock()
	results.append([c, arrays, blocks, ms, lres[1], lres[2], exact])
	mutex.unlock()


## Mapa wysokości nieba dla obszaru światła (N x N kolumn) z map 3 x 3 kolumn chunków.
func _skyh_region(c: Vector3i, hms: Array) -> PackedInt32Array:
	var M := light_margin
	var N := S + 2 * M
	var out := PackedInt32Array()
	out.resize(N * N)
	var ox := c.x * S - M
	var oz := c.z * S - M
	for iz in N:
		var wz := oz + iz
		var cz := floori(wz / float(S))
		var lz := wz - cz * S
		for ix in N:
			var wx := ox + ix
			var cx := floori(wx / float(S))
			var hm: Variant = hms[(cx - c.x + 1) + 3 * (cz - c.z + 1)]
			out[ix + N * iz] = hm[(wx - cx * S) + S * lz] if hm != null else 100000
	return out


## Mapa wysokości kolumny chunków: na start wysokość terenu z generatora (przed drzewami i edycjami).
func ensure_heightmap(col: Vector2i) -> void:
	if heightmap.has(col):
		return
	var hm := PackedInt32Array()
	hm.resize(S * S)
	if native != null:
		var hb: PackedInt32Array = native.call("heights", col.x * S, col.y * S, 1, S)
		for i in S * S:
			hm[i] = hb[i * 2]
	else:
		for z in S:
			for x in S:
				hm[x + S * z] = terrain.height(col.x * S + x, col.y * S + z)
	mutex.lock()
	heightmap[col] = hm
	mutex.unlock()


## Światło w punkcie: Vector2(niebo, bloki) w zakresie 0..1.
func light_at(p: Vector3) -> Vector2:
	var b := Vector3i(p.floor())
	var c := chunk_of(b)
	var l: Variant = light.get(c)
	if l == null:
		return Vector2(1, 0)
	var q := b - c * S
	var v: int = l[q.x + S * (q.y + S * q.z)]
	return Vector2(float(v >> 4) / 15.0, float(v & 15) / 15.0)


static func light_curve(v: float) -> float:
	return pow(0.8, (1.0 - v) * 15.0) if v > 0.01 else 0.0


## Kopiuje graniczną warstwę bloków sąsiada (z edycjami) do obwódki.
static func _copy_border(padded: PackedByteArray, nd: PackedByteArray, face: int) -> void:
	for a in S:
		for b in S:
			var dst := 0
			var src := 0
			match face:
				0:
					dst = (P - 1) + P * ((a + 1) + P * (b + 1)); src = 0 + S * (a + S * b)
				1:
					dst = 0 + P * ((a + 1) + P * (b + 1)); src = (S - 1) + S * (a + S * b)
				2:
					dst = (a + 1) + P * ((P - 1) + P * (b + 1)); src = a + S * (0 + S * b)
				3:
					dst = (a + 1) + P * (0 + P * (b + 1)); src = a + S * ((S - 1) + S * b)
				4:
					dst = (a + 1) + P * ((b + 1) + P * (P - 1)); src = a + S * (b + S * 0)
				5:
					dst = (a + 1) + P * ((b + 1) + P * 0); src = a + S * (b + S * (S - 1))
			padded[dst] = nd[src]


func _apply(c: Vector3i, arrays: Array, blocks: PackedByteArray, ms: float) -> void:
	queued.erase(c)
	mesh_ms_total += ms
	mesh_count += 1
	if not data.has(c):
		data[c] = blocks
	if absi(c.x - center.x) > radius + 1 or absi(c.z - center.z) > radius + 1:
		if not edited.has(c):
			data.erase(c)
		return
	built[c] = true
	if nodes.has(c):
		nodes[c].queue_free()
		nodes.erase(c)
	if water_nodes.has(c):
		water_nodes[c].queue_free()
		water_nodes.erase(c)
	if arrays.size() > 6 and not (arrays[6] as PackedVector3Array).is_empty():
		var warr := []
		warr.resize(Mesh.ARRAY_MAX)
		warr[Mesh.ARRAY_VERTEX] = arrays[6]
		warr[Mesh.ARRAY_NORMAL] = arrays[7]
		warr[Mesh.ARRAY_TEX_UV] = arrays[8]
		warr[Mesh.ARRAY_COLOR] = arrays[9]
		warr[Mesh.ARRAY_INDEX] = arrays[10]
		if arrays.size() > 11:
			warr[Mesh.ARRAY_TEX_UV2] = arrays[11]
		var wm := ArrayMesh.new()
		wm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, warr)
		wm.surface_set_material(0, water_material)
		var wmi := MeshInstance3D.new()
		wmi.mesh = wm
		wmi.position = Vector3(c * S)
		wmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(wmi)
		water_nodes[c] = wmi
	var verts: PackedVector3Array = arrays[0]
	if not verts.is_empty():
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = arrays[1]
		arr[Mesh.ARRAY_TEX_UV] = arrays[2]
		arr[Mesh.ARRAY_COLOR] = arrays[3]
		arr[Mesh.ARRAY_INDEX] = arrays[4]
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(0, material)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.position = Vector3(c * S)
		var faces: PackedVector3Array = arrays[5]
		if not faces.is_empty():
			var body := StaticBody3D.new()
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(faces)
			var cs := CollisionShape3D.new()
			cs.shape = shape
			body.add_child(cs)
			mi.add_child(body)
		add_child(mi)
		nodes[c] = mi
	if dirty.has(c):
		dirty.erase(c)
		_schedule(c)


func is_ready_at(p: Vector3) -> bool:
	var c := chunk_of(Vector3i(floori(p.x), floori(p.y), floori(p.z)))
	return built.has(c) and built.has(c + Vector3i(0, -1, 0)) and not queued.has(c)


func get_block(p: Vector3i) -> int:
	var c := chunk_of(p)
	var d: Variant = data.get(c)
	if d == null:
		var col := terrain.column(p.x, p.z)
		return terrain.block_for(p.y, col.x, col.y)
	var l := p - c * S
	return d[l.x + S * (l.y + S * l.z)]


## Zmiana bloku bez przebudowy siatki (dla symulacji cieczy): chunki do przebudowy trafiają do `pending`.
var pending := {}


func set_block_quiet(p: Vector3i, id: int) -> bool:
	var c := chunk_of(p)
	if not data.has(c) or not built.has(c):
		return false
	var l := p - c * S
	mutex.lock()
	var d: PackedByteArray = data[c]
	d[l.x + S * (l.y + S * l.z)] = id
	data[c] = d
	mutex.unlock()
	edited[c] = true
	unsaved[c] = true
	pending[c] = true
	if l.x == 0: pending[c + Vector3i(-1, 0, 0)] = true
	if l.x == S - 1: pending[c + Vector3i(1, 0, 0)] = true
	if l.y == 0: pending[c + Vector3i(0, -1, 0)] = true
	if l.y == S - 1: pending[c + Vector3i(0, 1, 0)] = true
	if l.z == 0: pending[c + Vector3i(0, 0, -1)] = true
	if l.z == S - 1: pending[c + Vector3i(0, 0, 1)] = true
	return true


func flush_pending() -> void:
	for c in pending:
		_remesh(c)
	pending.clear()


func is_loaded(p: Vector3i) -> bool:
	return data.has(chunk_of(p)) and built.has(chunk_of(p))


func set_block(p: Vector3i, id: int) -> bool:
	if not set_block_quiet(p, id):
		return false
	flush_pending()
	# roślina bez podłoża znika razem z blokiem pod nią
	if id == Blocks.AIR or reg.is_liquid(id):
		var above := p + Vector3i(0, 1, 0)
		if Blocks.props(get_block(above)) & Blocks.CROSS:
			set_block(above, Blocks.AIR)
	_update_light_after_edit(p, id)
	# ciecze w pobliżu ruszają, bloki z grawitacją spadają
	liquids.activate_around(p)
	check_fall(p + Vector3i(0, 1, 0))
	check_fall(p)
	return true


## Po zmianie bloku: mapa wysokości nieba i przeliczenie światła w chunkach w zasięgu światła.
func _update_light_after_edit(p: Vector3i, id: int) -> void:
	var col := Vector2i(floori(p.x / float(S)), floori(p.z / float(S)))
	var hm: Variant = heightmap.get(col)
	if hm != null:
		var h: PackedInt32Array = hm
		var i := (p.x - col.x * S) + S * (p.z - col.y * S)
		if (reg.lprops[id] & 16) != 0 and p.y > h[i]:
			h[i] = p.y
		elif (reg.lprops[id] & 16) == 0 and p.y == h[i]:
			var y := p.y - 1
			while y > p.y - 96 and (reg.lprops[get_block(Vector3i(p.x, y, p.z))] & 16) == 0:
				y -= 1
			h[i] = y
		mutex.lock()
		heightmap[col] = h
		mutex.unlock()
	var r := 15
	var c0 := chunk_of(p)
	for dz in range(-1, 2):
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var c := c0 + Vector3i(dx, dy, dz)
				if c == c0 or not built.has(c):
					continue
				var lo := Vector3(c * S)
				var hi := lo + Vector3(S, S, S)
				var q := Vector3(p).clamp(lo, hi)
				if q.distance_to(Vector3(p)) <= r:
					_remesh(c)


## Blok z grawitacją (piasek, żwir) bez podparcia zamienia się w spadający blok.
func check_fall(p: Vector3i) -> void:
	var b := get_block(p)
	if b <= 0 or not reg.has_gravity(b):
		return
	var below := get_block(p + Vector3i(0, -1, 0))
	if below != Blocks.AIR and (Blocks.props(below) & Blocks.SOLID) != 0:
		return
	if not set_block_quiet(p, Blocks.AIR):
		return
	flush_pending()
	var fb := FallingBlock.new()
	fb.world = self
	fb.block = b
	falling.add_child(fb)
	fb.global_position = Vector3(p) + Vector3(0.5, 0.0, 0.5)
	check_fall(p + Vector3i(0, 1, 0))


func _remesh(c: Vector3i) -> void:
	if not built.has(c):
		return
	if queued.has(c):
		dirty[c] = true
	elif not threaded:
		queued[c] = true
		sync_queue.push_front(c)
	else:
		_schedule(c)


## Przejście promienia przez siatkę bloków (DDA). Zwraca trafiony blok i ścianę wejścia.
func raycast(origin: Vector3, dir: Vector3, max_dist: float, with_liquids: bool = false) -> Dictionary:
	dir = dir.normalized()
	var pos := Vector3i(floori(origin.x), floori(origin.y), floori(origin.z))
	var step := Vector3i(int(signf(dir.x)), int(signf(dir.y)), int(signf(dir.z)))
	var t_delta := Vector3(
		INF if dir.x == 0.0 else absf(1.0 / dir.x),
		INF if dir.y == 0.0 else absf(1.0 / dir.y),
		INF if dir.z == 0.0 else absf(1.0 / dir.z))
	var t_max := Vector3(
		INF if dir.x == 0.0 else ((pos.x + 1 - origin.x) if dir.x > 0 else (origin.x - pos.x)) * t_delta.x,
		INF if dir.y == 0.0 else ((pos.y + 1 - origin.y) if dir.y > 0 else (origin.y - pos.y)) * t_delta.y,
		INF if dir.z == 0.0 else ((pos.z + 1 - origin.z) if dir.z > 0 else (origin.z - pos.z)) * t_delta.z)
	var normal := Vector3i.ZERO
	var t := 0.0
	while t <= max_dist:
		var hb := get_block(pos)
		if hb != Blocks.AIR and (with_liquids or not reg.is_liquid(hb)):
			return {"hit": true, "pos": pos, "normal": normal, "dist": t}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			pos.x += step.x; t = t_max.x; t_max.x += t_delta.x; normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			pos.y += step.y; t = t_max.y; t_max.y += t_delta.y; normal = Vector3i(0, -step.y, 0)
		else:
			pos.z += step.z; t = t_max.z; t_max.z += t_delta.z; normal = Vector3i(0, 0, -step.z)
	return {"hit": false}


# ---------- zapis ----------

func _chunk_path(c: Vector3i) -> String:
	return save_dir.path_join("chunks/%d_%d_%d.bin" % [c.x, c.y, c.z])


func _load_chunk(c: Vector3i) -> void:
	if save_dir.is_empty():
		return
	var path := _chunk_path(c)
	if not FileAccess.file_exists(path):
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return
	var raw := f.get_buffer(f.get_length())
	var d := raw.decompress(S * S * S, FileAccess.COMPRESSION_ZSTD)
	if d.size() == S * S * S:
		mutex.lock()
		data[c] = d
		mutex.unlock()
		edited[c] = true


func _save_chunk(c: Vector3i) -> void:
	unsaved.erase(c)
	if save_dir.is_empty() or not data.has(c):
		return
	DirAccess.make_dir_recursive_absolute(save_dir.path_join("chunks"))
	var f := FileAccess.open(_chunk_path(c), FileAccess.WRITE)
	if f:
		var d: PackedByteArray = data[c]
		f.store_buffer(d.compress(FileAccess.COMPRESSION_ZSTD))


## Przelicza id bloków we wszystkich zapisanych chunkach (gdy zmieniła się lista bloków z modów).
func migrate_palette(lut: PackedByteArray) -> int:
	if lut.is_empty() or save_dir.is_empty():
		return 0
	var dir := DirAccess.open(save_dir.path_join("chunks"))
	if dir == null:
		return 0
	var n := 0
	for fname in dir.get_files():
		var path := save_dir.path_join("chunks").path_join(fname)
		var raw := FileAccess.get_file_as_bytes(path)
		var d := raw.decompress(S * S * S, FileAccess.COMPRESSION_ZSTD)
		if d.size() != S * S * S:
			continue
		for i in d.size():
			d[i] = lut[d[i]]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(d.compress(FileAccess.COMPRESSION_ZSTD))
			n += 1
	return n


func save_all() -> int:
	var n := unsaved.size()
	for c in unsaved.keys():
		_save_chunk(c)
	return n


func stats() -> String:
	var avg := mesh_ms_total / maxf(1.0, float(mesh_count))
	return "chunki: %d  w kolejce: %d  budowa: %.1f ms/chunk (%s)" % [nodes.size(), queued.size(), avg, mesher_name]


static func make_water_material(r: Registry) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://scripts/shaders/water.gdshader")
	var sh := []
	var dp := []
	var fo := []
	var em := []
	for i in 8:
		var k: Dictionary = r.liquid_kinds[i] if i < r.liquid_kinds.size() else {}
		var c: Color = k.get("color", Color(0.16, 0.45, 0.78))
		var d: Color = k.get("deep", Color(0.04, 0.16, 0.36))
		sh.append(Color(c.r, c.g, c.b, 0.55 if c.a >= 0.99 else c.a))
		dp.append(Color(d.r, d.g, d.b, 0.88 if d.a >= 0.99 else d.a))
		fo.append(k.get("foam", Color(0.92, 0.96, 1.0)))
		em.append(float(k.get("emission", 0.0)))
	m.set_shader_parameter("shallow", sh)
	m.set_shader_parameter("deep", dp)
	m.set_shader_parameter("foam_color", fo)
	m.set_shader_parameter("emission", PackedFloat32Array(em))
	return m
