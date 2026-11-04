class_name World
extends Node3D
## Zarządza chunkami: generuje je i buduje siatki w tle, wczytuje wokół gracza, usuwa dalekie
## oraz zapisuje i wczytuje chunki zmienione przez gracza.

const S := 32
const P := S + 2

var terrain: Terrain
var tiles := Blocks.tile_table()
var props := Blocks.prop_table()
var atlas: ImageTexture
var material: StandardMaterial3D
var save_dir := ""  # pusty = świat tymczasowy, bez zapisu

var radius := 6
var y_min := -1
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


func setup(seed_value: int, opts: Dictionary, dir: String) -> void:
	terrain = Terrain.new(seed_value, opts)
	save_dir = dir
	y_max = terrain.max_chunk_y()


func _ready() -> void:
	if terrain == null:
		terrain = Terrain.new()
	atlas = Blocks.make_atlas()
	material = StandardMaterial3D.new()
	material.albedo_texture = atlas
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.vertex_color_use_as_albedo = true
	material.vertex_color_is_srgb = true
	material.roughness = 1.0
	material.albedo_color = Color(0.8, 0.8, 0.8)
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	material.alpha_scissor_threshold = 0.5
	if ClassDB.class_exists("VoxelMesher"):
		native = ClassDB.instantiate("VoxelMesher")
		mesher_name = "C++"
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
	mutex.unlock()
	var padded: PackedByteArray
	var blocks: PackedByteArray
	var arrays: Array
	if native != null:
		var prep: Array = native.call("prepare", c, terrain.native_noises(), terrain.native_params(),
			own if own != null else PackedByteArray(), neigh)
		padded = prep[0]
		blocks = prep[1]
		arrays = native.call("build", padded, tiles, Blocks.TILES, props)
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
		arrays = GDMesher.build(padded, tiles, Blocks.TILES, props)
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	mutex.lock()
	results.append([c, arrays, blocks, ms])
	mutex.unlock()


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
		return Terrain.block_for(p.y, col.x, col.y)
	var l := p - c * S
	return d[l.x + S * (l.y + S * l.z)]


func set_block(p: Vector3i, id: int) -> bool:
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
	_remesh(c)
	if l.x == 0: _remesh(c + Vector3i(-1, 0, 0))
	if l.x == S - 1: _remesh(c + Vector3i(1, 0, 0))
	if l.y == 0: _remesh(c + Vector3i(0, -1, 0))
	if l.y == S - 1: _remesh(c + Vector3i(0, 1, 0))
	if l.z == 0: _remesh(c + Vector3i(0, 0, -1))
	if l.z == S - 1: _remesh(c + Vector3i(0, 0, 1))
	# roślina bez podłoża znika razem z blokiem pod nią
	if id == Blocks.AIR:
		var above := p + Vector3i(0, 1, 0)
		if props[get_block(above)] & Blocks.CROSS:
			set_block(above, Blocks.AIR)
	return true


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
func raycast(origin: Vector3, dir: Vector3, max_dist: float) -> Dictionary:
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
		if get_block(pos) != Blocks.AIR:
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


func save_all() -> int:
	var n := unsaved.size()
	for c in unsaved.keys():
		_save_chunk(c)
	return n


func stats() -> String:
	var avg := mesh_ms_total / maxf(1.0, float(mesh_count))
	return "chunki: %d  w kolejce: %d  budowa: %.1f ms/chunk (%s)" % [nodes.size(), queued.size(), avg, mesher_name]
