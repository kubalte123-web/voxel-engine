extends SceneTree
## Porównanie budowy siatek: GDScript i C++ na tych samych chunkach (bez renderowania).
func _init() -> void:
	var terrain := Terrain.new()
	var tiles := Blocks.tile_table()
	var chunks: Array[PackedByteArray] = []
	var t0 := Time.get_ticks_usec()
	for i in 16:
		chunks.append(terrain.fill_padded(Vector3i(i, 0, i % 3)))
	var gen := (Time.get_ticks_usec() - t0) / 16000.0
	t0 = Time.get_ticks_usec()
	var faces_gd := 0
	for c in chunks:
		faces_gd += (GDMesher.build(c, tiles, Blocks.TILES)[0] as PackedVector3Array).size() / 4
	var gd := (Time.get_ticks_usec() - t0) / 16000.0
	var cpp := -1.0
	var faces_cpp := 0
	if ClassDB.class_exists("VoxelMesher"):
		var m: Object = ClassDB.instantiate("VoxelMesher")
		t0 = Time.get_ticks_usec()
		for c in chunks:
			faces_cpp += (m.call("build", c, tiles, Blocks.TILES)[0] as PackedVector3Array).size() / 4
		cpp = (Time.get_ticks_usec() - t0) / 16000.0
	if ClassDB.class_exists("VoxelMesher"):
		var m2: Object = ClassDB.instantiate("VoxelMesher")
		var same := true
		var t1 := Time.get_ticks_usec()
		for i in 16:
			var r: Array = m2.call("prepare", Vector3i(i, 0, i % 3), terrain.hills, terrain.detail, PackedByteArray(), [null, null, null, null, null, null])
			if r[0] != chunks[i]:
				same = false
		print("BENCH generowanie C++: %.2f ms/chunk, zgodne z GDScript: %s" % [(Time.get_ticks_usec() - t1) / 16000.0, same])
	print("BENCH generowanie (GDScript): %.2f ms/chunk" % gen)
	print("BENCH siatka GDScript: %.2f ms/chunk, scianki %d" % [gd, faces_gd / 16])
	print("BENCH siatka C++:      %.2f ms/chunk, scianki %d" % [cpp, faces_cpp / 16])
	quit()
