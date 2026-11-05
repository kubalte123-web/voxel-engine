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
var prof := {}     # pomiar: czasy części _process w ostatniej klatce (ms)
var dirty := {}    # chunki do ponownej budowy po zakończeniu bieżącej
var sync_queue: Array[Vector3i] = []
var results: Array = []
var mutex := Mutex.new()
var save_mutex := Mutex.new()
var _write_queue := {}  # chunk -> dane czekające na zapis do pliku (wątek w tle)
var _writing := {}      # chunk -> dane zapisywane właśnie teraz
var _save_task := -1

const COLL_RADIUS := 4         # kolizja tylko dla chunków w tym promieniu (w chunkach) od graczy
var coll := {}                 # chunki z aktualną kolizją (albo bez ścian, więc jej nie potrzebują)
var apply_budget_ms := 4.0     # czas na wstawianie gotowych chunków w jednej klatce (main daje więcej przy wczytywaniu)
var _last_ring: Array = []     # kolumny chunków graczy przy ostatnim sprawdzeniu
var _scan_missing := true      # czy szukać chunków do zbudowania
var _scan_timer := 0.0
var _relight_check := true     # czy są nowi sąsiedzi, więc warto sprawdzić chunki do przeliczenia światła

var center := Vector3i(999999, 0, 0)
var extra_centers: Array[Vector3] = []  # serwer: pozycje graczy zdalnych (wokół nich też trzymamy chunki)
var remote := false                     # klient gry wieloosobowej: stan świata przychodzi z serwera
var logic: BlockLogic = null            # serwer: dane i aktualizacje bloków dla modów
var models: BlockModels                 # modele bloków z polem `model`
var apply_stats := {"full": 0, "light": 0, "us": 0}   # przebudowy z kolizją / tylko światło, czas w wątku głównym
var gen_pending := {}                   # chunk -> {indeks: blok} – zapisy generatora Lua do chunków jeszcze niewygenerowanych
var gen_chunk := Vector3i.ZERO          # chunk obrabiany teraz przez generator Lua
var gen_blocks := PackedByteArray()
var gen_changed := false
var geo_ver := {}                       # chunk -> wersja kształtu (rośnie przy każdej zmianie bloków, które go dotyczą)
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
	models = BlockModels.new()
	models.name = "BlockModels"
	models.setup(self)
	add_child(models)
	material = ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/terrain.gdshader")
	material.set_shader_parameter("atlas", atlas)
	material.set_shader_parameter("lod_map", reg.lod_map)
	material.set_shader_parameter("max_lod", reg.max_lod)
	material.set_shader_parameter("atlas_size", reg.atlas_size)
	remote = Net.is_client()
	if ClassDB.class_exists("VoxelMesher"):
		native = ClassDB.instantiate("VoxelMesher")
		native.call("configure", terrain.native_noises(), terrain.spec, tiles, props, reg.liquid, Registry.ATLAS_COLS, reg.atlas_rows)
		native.call("set_light_props", reg.lprops)
		native.call("set_shapes", reg.shape_index, reg.shape_boxes)
		native.call("set_tile_rects", reg.tile_rects)
		mesher_name = "C++"
	else:
		light_margin = 6  # wersja w GDScript (przeglądarka): mniejszy zasięg światła spoza chunka
	GDMesher.set_shapes(reg.shape_index, reg.shape_boxes)
	GDMesher.set_tile_rects(reg.tile_rects)
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
	_last_ring = []   # wymusza ponowne sprawdzenie, co wczytać, wyładować i gdzie ma być kolizja


func _exit_tree() -> void:
	flush_saves()


static func chunk_of(p: Vector3i) -> Vector3i:
	return Vector3i(floori(p.x / float(S)), floori(p.y / float(S)), floori(p.z / float(S)))


func update_center(world_pos: Vector3) -> void:
	var c := chunk_of(Vector3i(floori(world_pos.x), floori(world_pos.y), floori(world_pos.z)))
	center = Vector3i(c.x, 0, c.z)


func _process(_delta: float) -> void:
	if center.x == 999999:
		return
	var t0 := Time.get_ticks_usec()
	# pętle po wszystkich chunkach tylko wtedy, gdy któryś gracz przeszedł do innego chunka
	var ring := _ring_key()
	if ring != _last_ring:
		_last_ring = ring
		_unload_far()
		_update_collision_ring()
		_scan_missing = true
	var t1 := Time.get_ticks_usec()
	_collect_results()
	var t2 := Time.get_ticks_usec()
	_scan_timer -= _delta
	if _scan_missing or _scan_timer <= 0.0:
		_scan_timer = 1.0
		_schedule_missing()
	var t3 := Time.get_ticks_usec()
	if queued.size() < max_queued and _relight_check:
		_process_relight()
	var t4 := Time.get_ticks_usec()
	_pump_saves()
	prof = {"collect": (t2 - t1) / 1000.0, "schedule": (t3 - t2) / 1000.0, "relight": (t4 - t3) / 1000.0, "unload": (t1 - t0) / 1000.0}
	if not threaded and not sync_queue.is_empty():
		var c: Vector3i = sync_queue.pop_front()
		_job(c)


## Chunki, które skończyły wątki, wstawiamy do świata najbliższe pierwsze i tylko przez apply_budget_ms
## w jednej klatce (siatka i kolizja w wątku głównym); reszta czeka do następnej klatki.
func _collect_results() -> void:
	mutex.lock()
	var ready := results
	results = []
	mutex.unlock()
	if ready.is_empty():
		return
	if ready.size() > 1:
		ready.sort_custom(func(a: Array, b: Array) -> bool: return _ring_dist(a[0]) < _ring_dist(b[0]))
	var t_start := Time.get_ticks_usec()
	for i in ready.size():
		if i > 0 and Time.get_ticks_usec() - t_start > apply_budget_ms * 1000.0:
			mutex.lock()
			results = ready.slice(i) + results
			mutex.unlock()
			return
		var r: Array = ready[i]
		var tw := Time.get_ticks_usec()
		var regen: bool = r.size() > 8 and _worldgen(r[0], r[2], bool(r[8]))
		apply_stats.gen_us = int(apply_stats.get("gen_us", 0)) + Time.get_ticks_usec() - tw
		if regen:
			continue   # generator Lua zmienił chunk: budujemy go jeszcze raz
		_apply(r[0], r[1], r[2], r[3], r[7] if r.size() > 7 else -1)
		var tl := Time.get_ticks_usec()
		if r.size() > 4:
			_apply_light(r[0], r[4], r[5], r[6])
		apply_stats.light_us = int(apply_stats.get("light_us", 0)) + Time.get_ticks_usec() - tl


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
## Sprawdzamy tylko po wstawieniu nowego chunka (wtedy mogło przybyć sąsiadów), a nie co klatkę.
func _process_relight() -> void:
	_relight_check = false
	var budget := 2
	for c in relight.keys():
		if budget <= 0:
			_relight_check = true   # zostało więcej: dokończymy w następnej klatce
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
		if all and queued.has(c):
			_relight_check = true
		elif all:
			relight.erase(c)
			_remesh(c)
			budget -= 1


func _schedule_missing() -> void:
	var budget := max_queued - queued.size()
	if budget <= 0:
		return
	var cs: Array[Vector3i] = [center]
	for e in extra_centers:
		var ec := chunk_of(Vector3i(e.floor()))
		cs.append(Vector3i(ec.x, 0, ec.z))
	for o in offsets:
		for cc in cs:
			var c := Vector3i(cc.x + o.x, o.y, cc.z + o.z)
			if built.has(c) or queued.has(c):
				continue
			_schedule(c)
			budget -= 1
			if budget <= 0:
				return
	_scan_missing = false   # wszystko w zasięgu zbudowane albo w budowie: nie szukamy co klatkę


func _schedule(c: Vector3i) -> void:
	if not data.has(c):
		_load_chunk(c)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			ensure_heightmap(Vector2i(c.x + dx, c.z + dz))
	queued[c] = true
	if threaded:
		WorkerThreadPool.add_task(_job.bind(c, int(geo_ver.get(c, 0))))
	else:
		sync_queue.append(c)


## Kolumny chunków, w których stoją gracze (lokalny i zdalni na serwerze).
func _ring_key() -> Array:
	var k := [Vector2i(center.x, center.z)]
	for e in extra_centers:
		var ec := chunk_of(Vector3i(e.floor()))
		k.append(Vector2i(ec.x, ec.z))
	return k


## Odległość chunka (w chunkach, w poziomie) od najbliższego gracza.
func _ring_dist(c: Vector3i) -> int:
	var best := maxi(absi(c.x - center.x), absi(c.z - center.z))
	for e in extra_centers:
		var ec := chunk_of(Vector3i(e.floor()))
		best = mini(best, maxi(absi(c.x - ec.x), absi(c.z - ec.z)))
	return best


func _coll_wanted(c: Vector3i) -> bool:
	return _ring_dist(c) <= COLL_RADIUS


## Po przejściu gracza do innego chunka: chunki, które weszły w zasięg kolizji, przebudowujemy w tle
## (wynik doda kolizję), a dalekim zabieramy kolizję (mniej pracy dla fizyki).
func _update_collision_ring() -> void:
	for c in nodes:
		var want := _coll_wanted(c)
		if want and not coll.has(c):
			_remesh(c)
		elif not want and coll.has(c):
			var mi: Node = nodes[c]
			var body := mi.get_node_or_null("Body")
			if body:
				mi.remove_child(body)
				body.queue_free()
			coll.erase(c)


## Czy w tym miejscu działa fizyka (jest kolizja z terenem). Stworzenia i rzeczy dalej od graczy stoją w miejscu.
func has_collision(p: Vector3i) -> bool:
	var c := chunk_of(p)
	return built.has(c) and (coll.has(c) or not nodes.has(c)) and _coll_wanted(c)


func _far_from_all(c: Vector3i, limit: int) -> bool:
	if absi(c.x - center.x) <= limit and absi(c.z - center.z) <= limit:
		return false
	for e in extra_centers:
		var ec := chunk_of(Vector3i(e.floor()))
		if absi(c.x - ec.x) <= limit and absi(c.z - ec.z) <= limit:
			return false
	return true


func _unload_far() -> void:
	var limit := radius + 2
	for c in built.keys():
		if _far_from_all(c, limit):
			if queued.has(c):
				continue
			built.erase(c)
			if logic:
				logic.chunk_unloaded(c)
			models.chunk_unloaded(c)
			coll.erase(c)
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
func _job(c: Vector3i, gv := -1) -> void:
	if gv < 0 and not threaded:
		gv = int(geo_ver.get(c, 0))   # przeglądarka: budowa w wątku głównym
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
	results.append([c, arrays, blocks, ms, lres[1], lres[2], exact, gv, own == null])
	mutex.unlock()


## Serwer: nowy chunk (nie z dysku) przechodzi przez generatory modów (engine.worldgen.on_generate) i zaległe
## zapisy z sąsiednich chunków. Zwraca true, gdy bloki się zmieniły – wtedy chunk idzie do ponownej budowy.
func _worldgen(c: Vector3i, blocks: PackedByteArray, fresh: bool) -> bool:
	if remote:
		return false
	var has_pending := gen_pending.has(c)
	if not has_pending and not (fresh and Mods.worldgen_active()):
		return false
	if data.has(c):
		blocks = data[c]
	gen_chunk = c
	gen_blocks = blocks
	gen_changed = false
	if has_pending:
		var pend: Dictionary = gen_pending[c]
		gen_pending.erase(c)
		for i in pend:
			if gen_blocks[int(i)] != int(pend[i]):
				gen_blocks[int(i)] = int(pend[i])
				gen_changed = true
	if fresh:
		Mods.worldgen_generate(c)
	gen_chunk = Vector3i(0, -99999, 0)
	if not gen_changed:
		return false
	mutex.lock()
	data[c] = gen_blocks
	mutex.unlock()
	edited[c] = true
	unsaved[c] = true
	Net.block_changed(c * S, 0, c, true)
	queued.erase(c)
	_schedule(c)
	return true


## Generator Lua: blok w świecie podczas generowania (współrzędne świata).
func gen_get(p: Vector3i) -> int:
	if chunk_of(p) == gen_chunk:
		var l := p - gen_chunk * S
		return gen_blocks[l.x + S * (l.y + S * l.z)]
	return get_block(p)


## Zapis generatora: w bieżącym chunku od razu, w istniejącym sąsiednim przez set_block, a w jeszcze
## niewygenerowanym – gdy powstanie.
func gen_set(p: Vector3i, id: int) -> void:
	var c := chunk_of(p)
	var l := p - c * S
	var i := l.x + S * (l.y + S * l.z)
	if c == gen_chunk:
		if gen_blocks[i] != id:
			gen_blocks[i] = id
			gen_changed = true
	elif data.has(c) and not queued.has(c):
		set_block(p, id)
	else:
		if not gen_pending.has(c):
			gen_pending[c] = {}
		gen_pending[c][i] = id


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


func _apply(c: Vector3i, arrays: Array, blocks: PackedByteArray, ms: float, gv := -1) -> void:
	var t_apply := Time.get_ticks_usec()
	queued.erase(c)
	mesh_ms_total += ms
	mesh_count += 1
	if not data.has(c):
		data[c] = blocks
	if _far_from_all(c, radius + 1):
		if not edited.has(c):
			data.erase(c)
		return
	if not built.has(c):
		_relight_check = true   # nowy sąsiad: może da się już przeliczyć światło chunków obok
		if logic:
			logic.chunk_loaded(c)
		# nowy sąsiad może zmienić ściany na granicy: następna przebudowa sąsiadów odświeży też kolizję
		for n in GDMesher.NORMALS:
			geo_ver[c + n] = int(geo_ver.get(c + n, 0)) + 1
	built[c] = true
	models.sync_chunk(c)
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
	var t_mesh := Time.get_ticks_usec()
	apply_stats.pre_us = int(apply_stats.get("pre_us", 0)) + t_mesh - t_apply
	if verts.is_empty():
		coll.erase(c)
		if nodes.has(c):
			nodes[c].queue_free()
			nodes.erase(c)
	else:
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
		# węzły zostają; przy zmianie samego światła (ten sam kształt) nie przebudowujemy kolizji
		var mi: MeshInstance3D = nodes.get(c)
		var same_shape := mi != null and gv >= 0 and int(mi.get_meta("geo", -2)) == gv
		if mi == null:
			mi = MeshInstance3D.new()
			mi.position = Vector3(c * S)
			add_child(mi)
			nodes[c] = mi
		mi.mesh = mesh
		var t_coll := Time.get_ticks_usec()
		apply_stats.mesh_us = int(apply_stats.get("mesh_us", 0)) + t_coll - t_mesh
		# kolizja tylko blisko graczy (to ok. 4/5 kosztu wstawienia chunka); dalej sama siatka
		var want_coll := _coll_wanted(c)
		if not want_coll:
			var old_body := mi.get_node_or_null("Body")
			if old_body:
				mi.remove_child(old_body)
				old_body.queue_free()
			coll.erase(c)
		elif not same_shape or not coll.has(c):
			coll[c] = true
			var faces: PackedVector3Array = arrays[5]
			var body: StaticBody3D = mi.get_node_or_null("Body")
			if faces.is_empty():
				if body:
					mi.remove_child(body)
					body.queue_free()
			else:
				var shape := ConcavePolygonShape3D.new()
				shape.set_faces(faces)
				if body == null:
					body = StaticBody3D.new()
					body.name = "Body"
					var cs := CollisionShape3D.new()
					cs.name = "Shape"
					body.add_child(cs)
					mi.add_child(body)
				(body.get_node("Shape") as CollisionShape3D).shape = shape
			apply_stats.coll_us = int(apply_stats.get("coll_us", 0)) + Time.get_ticks_usec() - t_coll
		mi.set_meta("geo", gv)
		apply_stats["light" if same_shape else "full"] += 1
	apply_stats.us += Time.get_ticks_usec() - t_apply
	if dirty.has(c):
		dirty.erase(c)
		_schedule(c)


func is_ready_at(p: Vector3) -> bool:
	var c := chunk_of(Vector3i(floori(p.x), floori(p.y), floori(p.z)))
	return built.has(c) and built.has(c + Vector3i(0, -1, 0)) and not queued.has(c) and physics_ready(p)


## Czy w tym miejscu można się ruszać: chunk i chunk pod nim mają kolizję (albo są puste).
func physics_ready(p: Vector3) -> bool:
	var q := Vector3i(floori(p.x), floori(p.y), floori(p.z))
	if not has_collision(q):
		return false
	var below := q - Vector3i(0, S, 0)
	return chunk_of(below).y < y_min or has_collision(below)


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
	var old := d[l.x + S * (l.y + S * l.z)]
	d[l.x + S * (l.y + S * l.z)] = id
	data[c] = d
	mutex.unlock()
	if old != id:
		if logic:
			logic.block_changed(p, old, id)
		if models:
			models.block_changed(p, old, id)
	var first := not edited.has(c)
	edited[c] = true
	unsaved[c] = true
	pending[c] = true
	if not remote:
		Net.block_changed(p, id, c, first)
	_bump_geo(c)
	if l.x == 0: _bump_geo(c + Vector3i(-1, 0, 0))
	if l.x == S - 1: _bump_geo(c + Vector3i(1, 0, 0))
	if l.y == 0: _bump_geo(c + Vector3i(0, -1, 0))
	if l.y == S - 1: _bump_geo(c + Vector3i(0, 1, 0))
	if l.z == 0: _bump_geo(c + Vector3i(0, 0, -1))
	if l.z == S - 1: _bump_geo(c + Vector3i(0, 0, 1))
	return true


## Kształt chunka się zmienił: do przebudowy razem z kolizją.
func _bump_geo(c: Vector3i) -> void:
	geo_ver[c] = int(geo_ver.get(c, 0)) + 1
	pending[c] = true


func flush_pending() -> void:
	for c in pending:
		_remesh(c)
	pending.clear()


func is_loaded(p: Vector3i) -> bool:
	return data.has(chunk_of(p)) and built.has(chunk_of(p))


func set_block(p: Vector3i, id: int) -> bool:
	var old := get_block(p)
	if not set_block_quiet(p, id):
		return false
	flush_pending()
	# roślina bez podłoża znika razem z blokiem pod nią
	if id == Blocks.AIR or reg.is_liquid(id):
		var above := p + Vector3i(0, 1, 0)
		if Blocks.props(get_block(above)) & Blocks.CROSS:
			set_block(above, Blocks.AIR)
	_update_light_after_edit(p, id, old)
	if remote:
		return true
	# ciecze w pobliżu ruszają, bloki z grawitacją spadają
	liquids.activate_around(p)
	check_fall(p + Vector3i(0, 1, 0))
	check_fall(p)
	return true


# ---------- gra wieloosobowa: świat u klienta ----------

## Dane chunka do wysłania klientom (w pamięci albo z dysku).
func chunk_data(c: Vector3i) -> Variant:
	if data.has(c):
		return data[c]
	if not save_dir.is_empty() and FileAccess.file_exists(_chunk_path(c)):
		return FileAccess.get_file_as_bytes(_chunk_path(c)).decompress(S * S * S, FileAccess.COMPRESSION_ZSTD)
	return null


## Klient: zmiana bloku od serwera.
func apply_remote(p: Vector3i, id: int) -> void:
	var c := chunk_of(p)
	var l := p - c * S
	if Net.remote_chunks.has(c):
		var rc: PackedByteArray = Net.remote_chunks[c]
		rc[l.x + S * (l.y + S * l.z)] = id
		Net.remote_chunks[c] = rc
	if data.has(c) and built.has(c):
		var old := get_block(p)
		set_block_quiet(p, id)
		_update_light_after_edit(p, id, old)


## Klient: cały chunk od serwera (zmieniony po raz pierwszy).
func apply_remote_chunk(c: Vector3i, d: PackedByteArray) -> void:
	if not data.has(c):
		return
	mutex.lock()
	data[c] = d.duplicate()
	mutex.unlock()
	edited[c] = true
	_bump_geo(c)
	_remesh(c)
	for n in GDMesher.NORMALS:
		_bump_geo(c + n)
		_remesh(c + n)


## Po zmianie bloku: mapa wysokości nieba i przeliczenie światła w chunkach w zasięgu światła.
func _update_light_after_edit(p: Vector3i, id: int, old := -1) -> void:
	# ta sama przepuszczalność i świecenie: światło się nie zmienia, sąsiednich chunków nie ruszamy
	if old >= 0 and reg.lprops[old] == reg.lprops[id]:
		return
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
func raycast(origin: Vector3, dir: Vector3, max_dist: float, with_liquids: bool = false, solid_only: bool = false) -> Dictionary:
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
		if hb != Blocks.AIR and (with_liquids or not reg.is_liquid(hb)) and (not solid_only or (reg.props[hb] & Registry.SOLID) != 0 or reg.is_liquid(hb)):
			if (reg.props[hb] & Registry.BOXES) == 0:
				return {"hit": true, "pos": pos, "normal": normal, "dist": t, "point": origin + dir * t}
			# kształt z prostopadłościanów: trafienie tylko w jego części (półblok ma wolną połowę)
			var bh := _ray_boxes(pos, origin, dir)
			if not bh.is_empty() and float(bh.dist) <= max_dist:
				return {"hit": true, "pos": pos, "normal": bh.normal, "dist": bh.dist, "point": origin + dir * float(bh.dist)}
		if t_max.x < t_max.y and t_max.x < t_max.z:
			pos.x += step.x; t = t_max.x; t_max.x += t_delta.x; normal = Vector3i(-step.x, 0, 0)
		elif t_max.y < t_max.z:
			pos.y += step.y; t = t_max.y; t_max.y += t_delta.y; normal = Vector3i(0, -step.y, 0)
		else:
			pos.z += step.z; t = t_max.z; t_max.z += t_delta.z; normal = Vector3i(0, 0, -step.z)
	return {"hit": false}


## Prostopadłościany kształtu w komórce p (0..1 w bloku), z połączeniami z sąsiadami (płot, szyba).
func shape_aabbs(p: Vector3i) -> Array[AABB]:
	var out: Array[AABB] = []
	var b := get_block(p)
	var si := b * Registry.SHAPE_STRIDE
	var idx := reg.shape_index
	if (reg.props[b] & Registry.BOXES) == 0 or si + Registry.SHAPE_STRIDE > idx.size():
		return out
	var lists := [[idx[si], idx[si + 1]]]
	var group := idx[si + 2]
	for d in 4:
		var cnt := idx[si + 4 + d * 2]
		if cnt <= 0:
			continue
		var cd: Vector2i = GDMesher.CONN[d]
		var nb := get_block(p + Vector3i(cd.x, 0, cd.y))
		var nsi := nb * Registry.SHAPE_STRIDE
		var ng := idx[nsi + 2] if nsi + Registry.SHAPE_STRIDE <= idx.size() else 0
		if (reg.props[nb] & Registry.OPAQUE) != 0 or (group > 0 and ng == group):
			lists.append([idx[si + 3 + d * 2], cnt])
	var bx := reg.shape_boxes
	for li in lists:
		for i in int(li[1]):
			var o: int = (int(li[0]) + i) * 6
			var lo := Vector3(bx[o], bx[o + 1], bx[o + 2]) / 16.0
			out.append(AABB(lo, Vector3(bx[o + 3], bx[o + 4], bx[o + 5]) / 16.0 - lo))
	return out


func _ray_boxes(p: Vector3i, origin: Vector3, dir: Vector3) -> Dictionary:
	var best := INF
	var nrm := Vector3i.ZERO
	for a in shape_aabbs(p):
		var lo := Vector3(p) + a.position
		var hi := lo + a.size
		var t0 := -INF
		var t1 := INF
		var n0 := Vector3i.ZERO
		var ok := true
		for k in 3:
			if absf(dir[k]) < 0.0000001:
				if origin[k] < lo[k] or origin[k] > hi[k]:
					ok = false
					break
				continue
			var ta := (lo[k] - origin[k]) / dir[k]
			var tb := (hi[k] - origin[k]) / dir[k]
			var nk := Vector3i.ZERO
			nk[k] = -1 if dir[k] > 0 else 1
			if ta > tb:
				var tmp := ta
				ta = tb
				tb = tmp
			if ta > t0:
				t0 = ta
				n0 = nk
			t1 = minf(t1, tb)
		if ok and t0 <= t1 and t1 >= 0.0 and t0 < best:
			best = maxf(t0, 0.0)
			nrm = n0
	if best == INF:
		return {}
	return {"dist": best, "normal": nrm}


## Obrys kształtu do podświetlenia celu (cały blok dla zwykłych bloków).
func target_box(p: Vector3i) -> AABB:
	var list := shape_aabbs(p)
	if list.is_empty():
		return AABB(Vector3.ZERO, Vector3.ONE)
	var u: AABB = list[0]
	for a in list:
		u = u.merge(a)
	return u


# ---------- zapis ----------

func _chunk_path(c: Vector3i) -> String:
	return save_dir.path_join("chunks/%d_%d_%d.bin" % [c.x, c.y, c.z])


func _load_chunk(c: Vector3i) -> void:
	if remote and Net.remote_chunks.has(c):
		mutex.lock()
		data[c] = (Net.remote_chunks[c] as PackedByteArray).duplicate()
		mutex.unlock()
		edited[c] = true
		return
	if save_dir.is_empty():
		return
	var pend: Variant = _pending_save(c)
	if pend != null:
		mutex.lock()
		data[c] = pend
		mutex.unlock()
		edited[c] = true
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


## Zapis chunka: kopia danych idzie do kolejki, plik zapisuje wątek w tle (kompresja i dysk nie
## zatrzymują gry). Wczytanie chunka czekającego w kolejce bierze dane z kolejki, nie ze starego pliku.
func _save_chunk(c: Vector3i) -> void:
	unsaved.erase(c)
	if save_dir.is_empty() or not data.has(c):
		return
	save_mutex.lock()
	_write_queue[c] = data[c]   # tablice bajtów kopiują się przy zmianie, więc to migawka
	save_mutex.unlock()
	if not threaded:
		flush_saves()


## Uruchamia wątek zapisu, gdy są chunki w kolejce; sprząta po zakończonym.
func _pump_saves() -> void:
	if _save_task >= 0 and WorkerThreadPool.is_task_completed(_save_task):
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	if _save_task < 0:
		save_mutex.lock()
		var any := not _write_queue.is_empty()
		save_mutex.unlock()
		if any:
			_save_task = WorkerThreadPool.add_task(_write_pending)


## Zapisuje wszystko, co czeka, i wraca dopiero po zapisaniu (wyjście z gry, wysyłka świata do klienta).
func flush_saves() -> void:
	if _save_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_save_task)
		_save_task = -1
	_write_pending()


## W wątku w tle (albo z flush_saves): zapisuje chunki z kolejki, aż będzie pusta.
func _write_pending() -> void:
	if save_dir.is_empty():
		return
	DirAccess.make_dir_recursive_absolute(save_dir.path_join("chunks"))
	while true:
		save_mutex.lock()
		if _write_queue.is_empty():
			save_mutex.unlock()
			return
		var c: Vector3i = _write_queue.keys()[0]
		var d: PackedByteArray = _write_queue[c]
		_writing[c] = d
		_write_queue.erase(c)
		save_mutex.unlock()
		var f := FileAccess.open(_chunk_path(c), FileAccess.WRITE)
		if f:
			f.store_buffer(d.compress(FileAccess.COMPRESSION_ZSTD))
			f.close()
		save_mutex.lock()
		_writing.erase(c)
		save_mutex.unlock()


## Dane chunka, który czeka na zapis (albo właśnie się zapisuje); null, gdy nie czeka.
func _pending_save(c: Vector3i) -> Variant:
	save_mutex.lock()
	var d: Variant = _write_queue.get(c, _writing.get(c))
	save_mutex.unlock()
	return d


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


## Zapis zmienionych chunków. blocking = false (autozapis): pliki zapisuje wątek w tle.
func save_all(blocking := true) -> int:
	if logic:
		logic.save(save_dir)
	var n := unsaved.size()
	for c in unsaved.keys():
		_save_chunk(c)
	if blocking:
		flush_saves()
	else:
		_pump_saves()
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
