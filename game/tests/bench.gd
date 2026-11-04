extends SceneTree
## Porównanie rdzenia C++ z GDScript: czas i zgodność świata (biomy, drzewa, rośliny) oraz siatek.
func _init() -> void:
	var terrain := Terrain.new(42, {})
	var tiles := Blocks.tile_table()
	var props := Blocks.prop_table()
	var cps: Array[Vector3i] = []
	for i in 12:
		cps.append(Vector3i(i * 7 - 40, 0, (i * 13) % 50 - 25))
	cps.append(Vector3i(3, 1, -2))
	var chunks: Array[PackedByteArray] = []
	var t0 := Time.get_ticks_usec()
	for c in cps:
		chunks.append(terrain.fill_padded(c))
	var gen := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	t0 = Time.get_ticks_usec()
	var faces_gd := 0
	for c in chunks:
		faces_gd += (GDMesher.build(c, tiles, Blocks.TILES, props)[0] as PackedVector3Array).size()
	var gd := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	print("BENCH generowanie GDScript: %.2f ms/chunk" % gen)
	print("BENCH siatka GDScript: %.2f ms/chunk" % gd)
	if not ClassDB.class_exists("VoxelMesher"):
		print("BENCH brak rdzenia C++")
		quit()
		return
	var m: Object = ClassDB.instantiate("VoxelMesher")
	var same := true
	var diff_at := ""
	t0 = Time.get_ticks_usec()
	var prepared: Array[PackedByteArray] = []
	for i in cps.size():
		var r: Array = m.call("prepare", cps[i], terrain.native_noises(), terrain.native_params(), PackedByteArray(), [null, null, null, null, null, null])
		prepared.append(r[0])
	var gen_c := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	for i in cps.size():
		if prepared[i] != chunks[i]:
			same = false
			diff_at = str(cps[i])
	t0 = Time.get_ticks_usec()
	var faces_c := 0
	for c in chunks:
		faces_c += (m.call("build", c, tiles, Blocks.TILES, props)[0] as PackedVector3Array).size()
	var cpp := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	var counts := {}
	for c in chunks:
		for b in [Blocks.LOG, Blocks.LEAVES, Blocks.CACTUS, Blocks.SNOW, Blocks.TALL_GRASS, Blocks.FLOWER_RED, Blocks.SAND]:
			counts[Blocks.NAMES[b]] = counts.get(Blocks.NAMES[b], 0) + c.count(b)
	print("BENCH generowanie C++: %.2f ms/chunk, swiat zgodny z GDScript: %s %s" % [gen_c, same, diff_at])
	print("BENCH siatka C++: %.2f ms/chunk, wierzcholki zgodne: %s" % [cpp, faces_c == faces_gd])
	print("BENCH bloki w probce: ", counts)
	quit()
