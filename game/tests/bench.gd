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
	GDMesher.set_shapes(reg.shape_index, reg.shape_boxes)
	var spec := WorldgenSpec.compile(reg.worldgen, reg, 42)
	print("BENCH bloki: %d, przedmioty: %d, biomy: %s, bledy: %s" % [reg.count(), reg.items.size(), spec.names, spec.errors])
	var terrain := Terrain.new(42, spec)
	print("BENCH parametry: ", spec.params)
	# kolumny pod poziomem morza w próbce
	var low := 0
	for i in 2000:
		if terrain.height(i * 3 - 3000, (i * 7) % 900 - 450) < 7:
			low += 1
	print("BENCH kolumny pod wodą: ", low, "/2000")
	var cps: Array[Vector3i] = []
	for i in 12:
		cps.append(Vector3i(i * 7 - 40, 0, (i * 13) % 50 - 25))
	cps.append(Vector3i(3, 1, -2))
	cps.append(Vector3i(5, -1, 4))
	cps.append(Vector3i(-3, -2, 7))
	cps.append(Vector3i(1, -1, 1))
	cps.append(Vector3i(-6, -1, 2))
	# chunki z wodą: szukamy kolumny pod poziomem morza
	for i in 4000:
		var x := i * 5 - 10000
		var z := (i * 37) % 2000 - 1000
		if terrain.height(x, z) < 4:
			cps.append(Vector3i(floori(x / 32.0), 0, floori(z / 32.0)))
			if cps.size() > 20:
				break
	var chunks: Array[PackedByteArray] = []
	var t0 := Time.get_ticks_usec()
	for c in cps:
		chunks.append(terrain.fill_padded(c))
	var gen := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	t0 = Time.get_ticks_usec()
	var faces_gd := 0
	var meshes_gd := []
	for c in chunks:
		var a := GDMesher.build(c, reg.tiles, Registry.ATLAS_COLS, reg.atlas_rows, reg.props, reg.liquid)
		meshes_gd.append(a)
		faces_gd += (a[0] as PackedVector3Array).size()
	var gd := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	print("BENCH generowanie GDScript: %.2f ms/chunk" % gen)
	print("BENCH siatka GDScript: %.2f ms/chunk" % gd)
	var counts := {}
	for c in chunks:
		for k in ["log", "leaves", "cactus", "snow", "tall_grass", "flower_red", "sand", "coal_ore", "iron_ore", "ruby_ore", "cobblestone", "water", "ice", "gravel"]:
			var id := reg.id_of(k)
			if id > 0:
				counts[k] = counts.get(k, 0) + c.count(id)
	var air_below := 0
	for c in chunks:
		air_below += c.count(0)
	counts["powietrze"] = air_below
	print("BENCH bloki w probce: ", counts)
	if not ClassDB.class_exists("VoxelMesher"):
		print("BENCH brak rdzenia C++")
		quit()
		return
	var m: Object = ClassDB.instantiate("VoxelMesher")
	m.call("configure", terrain.native_noises(), spec, reg.tiles, reg.props, reg.liquid, Registry.ATLAS_COLS, reg.atlas_rows)
	m.call("set_shapes", reg.shape_index, reg.shape_boxes)
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
	var water_faces := 0
	var mesh_same := true
	for i in chunks.size():
		var a: Array = m.call("build", chunks[i], PackedByteArray())
		faces_c += (a[0] as PackedVector3Array).size()
		for k in [0, 1, 4, 5, 6, 7, 8, 9, 10, 11]:
			if a[k] != meshes_gd[i][k]:
				if mesh_same:
					print("BENCH roznica w tablicy ", k, " chunk ", cps[i], " rozmiary ", a[k].size(), "/", meshes_gd[i][k].size())
				mesh_same = false
		water_faces += (a[6] as PackedVector3Array).size() / 4
		var ua: PackedVector2Array = a[2]
		var ub: PackedVector2Array = meshes_gd[i][2]
		for u in ua.size():
			if not ua[u].is_equal_approx(ub[u]):
				mesh_same = false
				break
		var ca: PackedColorArray = a[3]
		var cb: PackedColorArray = meshes_gd[i][3]
		for u in ca.size():
			if not ca[u].is_equal_approx(cb[u]):
				mesh_same = false
				break
	var cpp := (Time.get_ticks_usec() - t0) / 1000.0 / cps.size()
	print("BENCH generowanie C++: %.2f ms/chunk, swiat zgodny z GDScript: %s%s" % [gen_c, same, diff_at])
	# światło: ten sam obszar (chunk + margines 6, sąsiedzi przybliżeni mapą wysokości) w obu wersjach
	m.call("set_light_props", reg.lprops)
	var light_same := true
	var t_lc := 0.0
	var t_lg := 0.0
	var lit_dark := 0
	for i in cps.size():
		var c: Vector3i = cps[i]
		var around := []
		around.resize(27)
		around[13] = Terrain.interior(chunks[i])
		var M := 6
		var N := 32 + 2 * M
		var skyh := PackedInt32Array()
		skyh.resize(N * N)
		for iz in N:
			for ix in N:
				skyh[ix + N * iz] = terrain.height(c.x * 32 - M + ix, c.z * 32 - M + iz)
		var t1 := Time.get_ticks_usec()
		var lc: Array = m.call("light", c, around, skyh, M)
		t_lc += (Time.get_ticks_usec() - t1) / 1000.0
		t1 = Time.get_ticks_usec()
		var lg: Array = LightCalc.compute(c, around, skyh, M, reg.lprops)
		t_lg += (Time.get_ticks_usec() - t1) / 1000.0
		if lc[0] != lg[0] or lc[1] != lg[1] or lc[2] != lg[2]:
			light_same = false
		var ma: Array = m.call("build", chunks[i], lc[0])
		var mb: Array = GDMesher.build(chunks[i], reg.tiles, Registry.ATLAS_COLS, reg.atlas_rows, reg.props, reg.liquid, lg[0])
		if ma[0] != mb[0] or ma[11] != mb[11]:
			light_same = false
		var ca: PackedColorArray = ma[3]
		var cb: PackedColorArray = mb[3]
		for u in ca.size():
			if not ca[u].is_equal_approx(cb[u]):
				light_same = false
				break
		for v in (lc[1] as PackedByteArray):
			if v >> 4 < 4:
				lit_dark += 1
	print("BENCH swiatlo C++: %.2f ms/chunk, GDScript: %.2f ms/chunk, zgodne: %s, ciemnych komórek: %d" % [t_lc / cps.size(), t_lg / cps.size(), light_same, lit_dark])
	print("BENCH siatka C++: %.2f ms/chunk, siatki zgodne: %s (%d/%d), ściany wody: %d" % [cpp, mesh_same, faces_c, faces_gd, water_faces])
	# kształty z prostopadłościanów (półbloki, schody, płoty, szyby): losowo rozrzucone w chunku z ziemią
	var shape_ids := []
	for id in reg.count():
		if reg.props[id] & Registry.BOXES:
			shape_ids.append(id)
	if not shape_ids.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var sc: PackedByteArray = chunks[0].duplicate()
		var sl := PackedByteArray()
		sl.resize(sc.size())
		for i in sc.size():
			sl[i] = rng.randi_range(0, 255)
			if rng.randf() < 0.25:
				sc[i] = shape_ids[rng.randi() % shape_ids.size()]
			elif rng.randf() < 0.1:
				sc[i] = reg.id_of("stone")
		var sa: Array = m.call("build", sc, sl)
		var sb: Array = GDMesher.build(sc, reg.tiles, Registry.ATLAS_COLS, reg.atlas_rows, reg.props, reg.liquid, sl)
		var shp_same := true
		for k in [0, 1, 4, 5, 11]:
			if sa[k] != sb[k]:
				shp_same = false
				print("BENCH kształty: różnica w tablicy ", k, " rozmiary ", sa[k].size(), "/", sb[k].size())
		for k in [2, 3]:
			var xa: Array = Array(sa[k])
			var xb: Array = Array(sb[k])
			if xa.size() != xb.size():
				shp_same = false
				continue
			for u in xa.size():
				if not xa[u].is_equal_approx(xb[u]):
					shp_same = false
					print("BENCH kształty: różnica w tablicy ", k, " na ", u, ": ", xa[u], " / ", xb[u])
					break
		print("BENCH kształty (%d rodzajów): siatki zgodne: %s, ścian: %d" % [shape_ids.size(), shp_same, (sa[0] as PackedVector3Array).size() / 4])
	quit()
