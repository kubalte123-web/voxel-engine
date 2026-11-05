extends SceneTree
## Generuje mods/alchemy/models/cauldron.glb: kocioł z toczonego profilu (jak w Blenderze „Screw”/„Spin”),
## miedzianą obręcz, dwa uchwyty i powierzchnię cieczy. Każdy element to osobny, nazwany węzeł –
## silnik szuka węzłów po nazwie (animacje, kolory, ukrywanie). Uruchom: godot --headless --path game -s tools/make_cauldron.gd

const SEG := 64


func _mat(c: Color, metal: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.metallic = metal
	m.roughness = rough
	return m


## Bryła obrotowa z profilu [promień, wysokość] (od dołu na zewnątrz, przez brzeg, do środka).
func lathe(profile: Array, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for i in profile.size() - 1:
		var a: Vector2 = profile[i]
		var b: Vector2 = profile[i + 1]
		for s in SEG:
			var t0 := TAU * s / SEG
			var t1 := TAU * (s + 1) / SEG
			var p00 := Vector3(cos(t0) * a.x, a.y, sin(t0) * a.x)
			var p01 := Vector3(cos(t1) * a.x, a.y, sin(t1) * a.x)
			var p10 := Vector3(cos(t0) * b.x, b.y, sin(t0) * b.x)
			var p11 := Vector3(cos(t1) * b.x, b.y, sin(t1) * b.x)
			for v in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(v)
	st.index()
	st.generate_normals()
	return st.commit()


func torus_arc(center: Vector3, axis_angle: float, r_big: float, r_small: float, from: float, to: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	var n1 := 24
	var n2 := 10
	var pt := func(u: float, v: float) -> Vector3:
		var ang := from + (to - from) * u
		var ring := Vector3(cos(ang) * r_big, sin(ang) * r_big, 0)
		var dir := ring.normalized()
		var p := ring + dir * cos(v) * r_small + Vector3(0, 0, sin(v) * r_small)
		return center + p.rotated(Vector3.UP, axis_angle)
	for i in n1:
		for j in n2:
			var u0 := float(i) / n1
			var u1 := float(i + 1) / n1
			var v0 := TAU * j / n2
			var v1 := TAU * (j + 1) / n2
			for q in [[u0, v0], [u1, v0], [u1, v1], [u0, v0], [u1, v1], [u0, v1]]:
				st.add_vertex(pt.call(q[0], q[1]))
	st.index()
	st.generate_normals()
	return st.commit()


func disc(r: float, y: float, mat: Material) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(mat)
	for s in SEG:
		var t0 := TAU * s / SEG
		var t1 := TAU * (s + 1) / SEG
		# lekko wypukła powierzchnia (falowanie robi animacja)
		st.add_vertex(Vector3(0, y + 0.008, 0))
		st.add_vertex(Vector3(cos(t0) * r, y, sin(t0) * r))
		st.add_vertex(Vector3(cos(t1) * r, y, sin(t1) * r))
	st.index()
	st.generate_normals()
	return st.commit()


func node(name: String, mesh: Mesh, parent: Node) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = mesh
	parent.add_child(mi)
	mi.owner = parent if parent.owner == null else parent.owner
	return mi


func _init() -> void:
	var iron := _mat(Color(0.2, 0.2, 0.23), 0.6, 0.45)
	var copper := _mat(Color(0.72, 0.42, 0.2), 0.8, 0.35)
	var liquid := _mat(Color(0.25, 0.5, 0.9), 0.0, 0.15)
	var root := Node3D.new()
	root.name = "Cauldron"
	# profil kotła: dno, brzuch, przewężenie, wywinięty brzeg, ścianka wewnętrzna, dno wewnętrzne
	var outer := [
		Vector2(0.0, 0.2), Vector2(0.16, 0.205), Vector2(0.28, 0.23), Vector2(0.37, 0.29), Vector2(0.425, 0.38),
		Vector2(0.445, 0.48), Vector2(0.44, 0.58), Vector2(0.415, 0.68), Vector2(0.395, 0.76), Vector2(0.41, 0.8),
		Vector2(0.45, 0.83), Vector2(0.46, 0.855), Vector2(0.44, 0.87), Vector2(0.395, 0.86), Vector2(0.375, 0.8),
		Vector2(0.39, 0.7), Vector2(0.41, 0.58), Vector2(0.4, 0.45), Vector2(0.35, 0.33), Vector2(0.25, 0.27),
		Vector2(0.12, 0.25), Vector2(0.0, 0.245),
	]
	node("pot", lathe(outer, iron), root)
	node("band", lathe([Vector2(0.44, 0.5), Vector2(0.455, 0.505), Vector2(0.458, 0.56), Vector2(0.443, 0.565)], copper), root)
	node("handle_l", torus_arc(Vector3(-0.47, 0.7, 0), 0.0, 0.07, 0.018, -PI / 2, PI / 2, iron), root)
	node("handle_r", torus_arc(Vector3(0.47, 0.7, 0), PI, 0.07, 0.018, -PI / 2, PI / 2, iron), root)
	node("liquid", disc(0.392, 0.72, liquid), root)
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	var path := "res://mods/alchemy/models/cauldron.glb"
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	var tris := 0
	for c in root.get_children():
		tris += (c as MeshInstance3D).mesh.surface_get_array_index_len(0) / 3
	print("GLB ", path, " błąd=", err, " trójkątów=", tris)
	quit()
