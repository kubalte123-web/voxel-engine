class_name FarTerrain
extends Node3D
## Dalekie widoki: za zasięgiem prawdziwych chunków teren jest rysowany z uproszczonych kafli
## (siatka wysokości co 4 bloki, kolor z wierzchniego bloku, woda jako płaska tafla, lasy jako
## ciemniejszy, lekko podniesiony kolor koron). Kafle liczą się w tle; wysokości daje rdzeń C++.
## Shader odrzuca piksele w zasięgu prawdziwych chunków, więc kafle nie zasłaniają świata.
## Kafle tworzą drzewo czwórkowe: dalej od gracza są większe (64, 128, 256… bloków) przy tej samej
## liczbie wierzchołków, więc przy dużym zasięgu jest ich kilkaset zamiast tysięcy (mniej wywołań rysowania).
## Krawędzie kafli mają opuszczone „spódniczki”, które zasłaniają szczeliny między kaflami różnej wielkości.

const TILE := 64        # najmniejszy kafel (poziom 0)
const STEP := 4         # odstęp wierzchołków na poziomie 0
const N := TILE / STEP + 1
const MAX_LEVEL := 6    # największy kafel: 64 * 2^6 = 4096 bloków
const SPLIT := 3.0      # kafel dzielimy na 4, gdy gracz jest bliżej niż SPLIT * jego rozmiar

var world: World
var radius_blocks := 0.0
var inner := 0.0
var tiles := {}      # Vector3i(poziom, x, z) -> MeshInstance3D
var pending := {}    # Vector3i -> true (w trakcie liczenia)
var want := {}       # kafle potrzebne przy obecnej pozycji gracza
var doomed := {}     # kafle już niepotrzebne: znikają, gdy nowe w tym miejscu są gotowe (bez dziur)
var _pos := Vector3.ZERO
var results: Array = []
var mutex := Mutex.new()
var material: ShaderMaterial
var center := Vector2i(999999, 0)
var top_colors := []     # biom -> [kolor wierzchu, kolor koron, pokrycie lasem]
var water_color := Color(0.16, 0.42, 0.72)


func setup(w: World) -> void:
	world = w
	material = ShaderMaterial.new()
	material.shader = load("res://scripts/shaders/far.gdshader")
	var t := world.terrain
	var reg := world.reg
	for b in t.nb:
		var o := b * Terrain.BS
		var top := int(t.B[o + 6])
		var col := _tile_color(top, 2)
		var cover := 0.0
		var canopy := col
		var fs := int(t.B[o + 15])
		for k in int(t.B[o + 16]):
			var f := (fs + k) * Terrain.FS
			if int(t.F[f + 1]) <= 1:
				cover += t.F[f]
				canopy = _tile_color(int(t.F[f + 3]), 2)
		top_colors.append([col, canopy, clampf(cover * 22.0, 0.0, 0.85)])
	if not reg.liquid_kinds.is_empty():
		water_color = reg.liquid_kinds[0].color


func _tile_color(block: int, face: int) -> Color:
	var reg := world.reg
	if block <= 0 or block >= reg.count():
		return Color(0.5, 0.5, 0.5)
	return reg.tile_colors[reg.tiles[block * 6 + face]]


func set_radius(near_chunks: int, factor: int) -> void:
	inner = (near_chunks - 0.5) * World.S
	radius_blocks = 0.0 if factor <= 0 else near_chunks * World.S * (factor + 1)
	material.set_shader_parameter("inner", inner)
	if radius_blocks <= 0.0:
		for k in tiles.keys():
			tiles[k].queue_free()
		tiles.clear()
		doomed.clear()
		want.clear()
	center = Vector2i(999999, 0)


static func _size(k: Vector3i) -> int:
	return TILE << k.x


## Najmniejsza i największa odległość (w poziomie) od punktu do kwadratu kafla.
static func _dist_range(k: Vector3i, p: Vector2) -> Vector2:
	var s := float(_size(k))
	var x0 := k.y * s
	var z0 := k.z * s
	var dx := maxf(maxf(x0 - p.x, 0.0), p.x - (x0 + s))
	var dz := maxf(maxf(z0 - p.y, 0.0), p.y - (z0 + s))
	var fx := maxf(absf(p.x - x0), absf(p.x - (x0 + s)))
	var fz := maxf(absf(p.y - z0), absf(p.y - (z0 + s)))
	return Vector2(Vector2(dx, dz).length(), Vector2(fx, fz).length())


func _select(k: Vector3i, p: Vector2, out: Dictionary) -> void:
	var dr := _dist_range(k, p)
	if dr.x > radius_blocks:
		return            # cały za zasięgiem dalekiego widoku
	if dr.y < inner:
		return            # cały w zasięgu prawdziwych chunków
	if k.x > 0 and dr.x < SPLIT * _size(k):
		for j in 2:
			for i in 2:
				_select(Vector3i(k.x - 1, k.y * 2 + i, k.z * 2 + j), p, out)
		return
	out[k] = dr.x


func update_center(pos: Vector3) -> void:
	material.set_shader_parameter("center", pos)
	if radius_blocks <= 0.0:
		return
	var c := Vector2i(floori(pos.x / TILE), floori(pos.z / TILE))
	if c == center:
		return
	center = c
	_pos = pos
	var p := Vector2(pos.x, pos.z)
	var top := float(TILE << MAX_LEVEL)
	var r := ceili(radius_blocks / top)
	var cx := floori(pos.x / top)
	var cz := floori(pos.z / top)
	want = {}
	for tz in range(cz - r, cz + r + 1):
		for tx in range(cx - r, cx + r + 1):
			_select(Vector3i(MAX_LEVEL, tx, tz), p, want)
	for k in tiles.keys():
		if not want.has(k):
			doomed[k] = true
	for k in doomed.keys():
		if want.has(k):
			doomed.erase(k)   # wrócił do użytku zanim zniknął
	var order := want.keys()
	order.sort_custom(func(a, b): return want[a] < want[b])
	for k in order:
		if tiles.has(k) or pending.has(k):
			continue
		pending[k] = true
		if world.threaded:
			WorkerThreadPool.add_task(_job.bind(k))
		else:
			_job(k)
	_retire()


## Usuwa niepotrzebne kafle, których miejsce pokrywają już gotowe nowe kafle.
func _retire() -> void:
	if doomed.is_empty():
		return
	for k in doomed.keys():
		var s := _size(k)
		var r := Rect2i(k.y * s, k.z * s, s, s)
		var covered := true
		for w in want:
			if tiles.has(w):
				continue
			var ws := _size(w)
			if r.intersects(Rect2i(w.y * ws, w.z * ws, ws, ws)):
				covered = false
				break
		if covered:
			if tiles.has(k):
				tiles[k].queue_free()
				tiles.erase(k)
			doomed.erase(k)


func _process(_delta: float) -> void:
	mutex.lock()
	var ready := results
	results = []
	mutex.unlock()
	var budget := 6
	var added := false
	for r in ready:
		var k: Vector3i = r[0]
		if budget <= 0:
			mutex.lock()
			results.append(r)
			mutex.unlock()
			continue
		pending.erase(k)
		budget -= 1
		if tiles.has(k) or not want.has(k):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = r[1]
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var s := _size(k)
		mi.position = Vector3(k.y * s, -0.35, k.z * s)
		add_child(mi)
		tiles[k] = mi
		added = true
	if added:
		_retire()


func _job(k: Vector3i) -> void:
	var step := STEP << k.x
	var x0 := k.y * _size(k)
	var z0 := k.z * _size(k)
	var hb: PackedInt32Array
	if world.native != null:
		hb = world.native.call("heights", x0, z0, step, N)
	else:
		hb.resize(N * N * 2)
		for j in N:
			for i in N:
				var c := world.terrain.column(x0 + i * step, z0 + j * step)
				hb[(i + N * j) * 2] = c.x
				hb[(i + N * j) * 2 + 1] = c.y
	var sea := world.terrain.sea
	var hs := PackedFloat32Array()
	hs.resize(N * N)
	var cols := PackedColorArray()
	cols.resize(N * N)
	for j in N:
		for i in N:
			var q := (i + N * j) * 2
			var h := hb[q]
			var b := hb[q + 1]
			var top := world.terrain.block_for(h, h, b)
			var col := _tile_color(top, 2)
			var y := float(h) + 1.0
			var tc: Array = top_colors[b] if b < top_colors.size() else [col, col, 0.0]
			if h < sea:
				col = water_color.darkened(clampf((sea - h) * 0.06, 0.0, 0.5))
				y = float(sea) + 0.85
			elif float(tc[2]) > 0.0 and h > world.terrain.beach:
				# las z daleka: kolor koron i drzewa podnoszą teren
				var hv := Terrain.hash01(x0 + i * step, z0 + j * step, 7, 9)
				var cover: float = tc[2] * (0.6 + 0.8 * hv)
				col = col.lerp((tc[1] as Color).darkened(0.1), clampf(cover, 0.0, 1.0))
				y += cover * 4.5
			hs[i + N * j] = y
			cols[i + N * j] = col
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var cl := PackedColorArray()
	var idx := PackedInt32Array()
	for j in N:
		for i in N:
			var y := hs[i + N * j]
			v.append(Vector3(i * step, y, j * step))
			var l := hs[maxi(i - 1, 0) + N * j]
			var r := hs[mini(i + 1, N - 1) + N * j]
			var d := hs[i + N * maxi(j - 1, 0)]
			var u := hs[i + N * mini(j + 1, N - 1)]
			n.append(Vector3(l - r, 2.0 * step, d - u).normalized())
			cl.append(cols[i + N * j])
	for j in N - 1:
		for i in N - 1:
			var a := i + N * j
			idx.append_array([a, a + 1, a + N + 1, a, a + N + 1, a + N])
	# spódniczka: obwód kafla powtórzony niżej i połączony z krawędzią (zasłania szczeliny przy sąsiadach innej wielkości)
	var drop := 6.0 + float(step) * 2.0
	var ring: Array[int] = []
	for i in N:
		ring.append(i)
	for j in range(1, N):
		ring.append(N - 1 + N * j)
	for i in range(N - 2, -1, -1):
		ring.append(i + N * (N - 1))
	for j in range(N - 2, 0, -1):
		ring.append(N * j)
	var base := v.size()
	for a in ring:
		v.append(v[a] - Vector3(0, drop, 0))
		n.append(n[a])
		cl.append(cl[a].darkened(0.15))
	for e in ring.size():
		var a: int = ring[e]
		var b: int = ring[(e + 1) % ring.size()]
		var a2 := base + e
		var b2 := base + (e + 1) % ring.size()
		idx.append_array([a, b, b2, a, b2, a2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_COLOR] = cl
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mutex.lock()
	results.append([k, m])
	mutex.unlock()
