class_name FarTerrain
extends Node3D
## Dalekie widoki: za zasięgiem prawdziwych chunków teren jest rysowany z uproszczonych kafli
## (siatka wysokości co 4 bloki, kolor z wierzchniego bloku, woda jako płaska tafla, lasy jako
## ciemniejszy, lekko podniesiony kolor koron). Kafle liczą się w tle; wysokości daje rdzeń C++.
## Shader odrzuca piksele w zasięgu prawdziwych chunków, więc kafle nie zasłaniają świata.

const TILE := 64
const STEP := 4
const N := TILE / STEP + 1

var world: World
var radius_blocks := 0.0
var inner := 0.0
var tiles := {}      # Vector2i -> MeshInstance3D
var pending := {}    # Vector2i -> true (w trakcie liczenia)
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
	center = Vector2i(999999, 0)


func update_center(pos: Vector3) -> void:
	material.set_shader_parameter("center", pos)
	if radius_blocks <= 0.0:
		return
	var c := Vector2i(floori(pos.x / TILE), floori(pos.z / TILE))
	if c == center:
		return
	center = c
	var r := ceili(radius_blocks / TILE)
	var want := {}
	for tz in range(c.y - r, c.y + r + 1):
		for tx in range(c.x - r, c.x + r + 1):
			var k := Vector2i(tx, tz)
			var mid := Vector2((tx + 0.5) * TILE, (tz + 0.5) * TILE)
			var d := mid.distance_to(Vector2(pos.x, pos.z))
			if d > radius_blocks + TILE:
				continue
			if d + TILE * 0.71 < inner:
				continue  # kafel cały w zasięgu prawdziwych chunków
			want[k] = d
	for k in tiles.keys():
		if not want.has(k):
			tiles[k].queue_free()
			tiles.erase(k)
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


func _process(_delta: float) -> void:
	mutex.lock()
	var ready := results
	results = []
	mutex.unlock()
	var budget := 6
	for r in ready:
		var k: Vector2i = r[0]
		pending.erase(k)
		if budget <= 0:
			mutex.lock()
			results.append(r)
			mutex.unlock()
			continue
		budget -= 1
		if tiles.has(k):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = r[1]
		mi.material_override = material
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(k.x * TILE, -0.35, k.y * TILE)
		add_child(mi)
		tiles[k] = mi


func _job(k: Vector2i) -> void:
	var x0 := k.x * TILE
	var z0 := k.y * TILE
	var hb: PackedInt32Array
	if world.native != null:
		hb = world.native.call("heights", x0, z0, STEP, N)
	else:
		hb.resize(N * N * 2)
		for j in N:
			for i in N:
				var c := world.terrain.column(x0 + i * STEP, z0 + j * STEP)
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
				var hv := Terrain.hash01(x0 + i * STEP, z0 + j * STEP, 7, 9)
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
			v.append(Vector3(i * STEP, y, j * STEP))
			var l := hs[maxi(i - 1, 0) + N * j]
			var r := hs[mini(i + 1, N - 1) + N * j]
			var d := hs[i + N * maxi(j - 1, 0)]
			var u := hs[i + N * mini(j + 1, N - 1)]
			n.append(Vector3(l - r, 2.0 * STEP, d - u).normalized())
			cl.append(cols[i + N * j])
	for j in N - 1:
		for i in N - 1:
			var a := i + N * j
			idx.append_array([a, a + 1, a + N + 1, a, a + N + 1, a + N])
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
