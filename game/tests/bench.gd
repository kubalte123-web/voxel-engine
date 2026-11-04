extends SceneTree
## Porównanie rdzenia C++ z GDScript: czas i zgodność świata (biomy, rudy, drzewa, struktury, rośliny)
## oraz siatek. Świat opisują mody (faza content), tak jak w grze.
## Uruchomienie: godot --headless --path game -s tests/bench.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mods: Node = root.get_node("/root/Mods")
	var mm: Node = root.get_node("/root/ModManager")
	for id in mm.manifests:
		mm.enabled[id] = true  # wszystkie mody, żeby sprawdzić też rudy i struktury
	var reg: Registry = mods.start_content("")
	var spec := WorldgenSpec.compile(reg.worldgen, reg, 42)
	print("BENCH bloki: %d, przedmioty: %d, biomy: %s, bledy: %s" % [reg.count(), reg.items.size(), spec.names, spec.errors])
	var terrain := Terrain.new(42, spec)
	var cps: Array[Vector3i] = []
	for i in 12:
		cps.append(Vector3i(i * 7 - 40, 0, (i * 13) % 50 - 25))
	cps.append(Vector3i(3, 1, -2))
	cps.append(Vector3i(5, -1, 4))
	cps.append(Vector3i(-3, -2, 7))
	var chunks: Array[PackedByteArray] = []
	var t0 := Time.get_ticks_usec()
	for c in cps:
		chunks.append(terrain.fill_padded(c))
	var gen := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	t0 = Time.get_ticks_usec()
	var faces_gd := 0
	var meshes_gd := []
	for c in chunks:
		var a := GDMesher.build(c, reg.tiles, Registry.ATLAS_COLS, reg.atlas_rows, reg.props)
		meshes_gd.append(a)
		faces_gd += (a[0] as PackedVector3Array).size()
	var gd := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	print("BENCH generowanie GDScript: %.2f ms/chunk" % gen)
	print("BENCH siatka GDScript: %.2f ms/chunk" % gd)
	var counts := {}
	for c in chunks:
		for k in ["log", "leaves", "cactus", "snow", "tall_grass", "flower_red", "sand", "coal_ore", "iron_ore", "ruby_ore", "cobblestone"]:
			var id := reg.id_of(k)
			if id > 0:
				counts[k] = counts.get(k, 0) + c.count(id)
	print("BENCH bloki w probce: ", counts)
	if not ClassDB.class_exists("VoxelMesher"):
		print("BENCH brak rdzenia C++")
		quit()
		return
	var m: Object = ClassDB.instantiate("VoxelMesher")
	m.call("configure", terrain.native_noises(), spec, reg.tiles, reg.props, Registry.ATLAS_COLS, reg.atlas_rows)
	var same := true
	var diff_at := ""
	t0 = Time.get_ticks_usec()
	var prepared: Array[PackedByteArray] = []
	for i in cps.size():
		var r: Array = m.call("prepare", cps[i], PackedByteArray(), [null, null, null, null, null, null])
		prepared.append(r[0])
	var gen_c := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	for i in cps.size():
		if prepared[i] != chunks[i]:
			same = false
			var n := 0
			for k in chunks[i].size():
				if chunks[i][k] != prepared[i][k]:
					n += 1
			diff_at += " %s(%d)" % [str(cps[i]), n]
	t0 = Time.get_ticks_usec()
	var faces_c := 0
	var mesh_same := true
	for i in chunks.size():
		var a: Array = m.call("build", chunks[i])
		faces_c += (a[0] as PackedVector3Array).size()
		if a[0] != meshes_gd[i][0] or a[4] != meshes_gd[i][4] or a[5] != meshes_gd[i][5]:
			mesh_same = false
	var cpp := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	print("BENCH generowanie C++: %.2f ms/chunk, swiat zgodny z GDScript: %s%s" % [gen_c, same, diff_at])
	print("BENCH siatka C++: %.2f ms/chunk, siatki zgodne: %s (%d/%d)" % [cpp, mesh_same, faces_c, faces_gd])
	quit()
