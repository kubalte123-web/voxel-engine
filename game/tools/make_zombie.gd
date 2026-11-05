extends SceneTree
## Generuje mods/podstawowa/mods/monsters/models/zombie.glb: postać z nazwanymi częściami (Head, ArmL, ArmR, LegL, LegR, Body)
## i animacjami w pliku (Idle, Walk, Attack, Hurt) – tak jak model zrobiony w Blenderze. Silnik odtwarza
## animacje z pliku według stanu stworzenia (model.animations w definicji).
## Uruchom: godot --headless --path game -s tools/make_zombie.gd

var mats := {}


func _mat(c: String) -> StandardMaterial3D:
	if not mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(c)
		m.roughness = 0.95
		mats[c] = m
	return mats[c]


## Prostopadłościan z lekko ściętymi krawędziami (bevel), środek w `pos`.
func box(name: String, size: Vector3, pos: Vector3, color: String, parent: Node3D, bevel := 0.02) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_material(_mat(color))
	var h := size * 0.5
	var b := minf(bevel, minf(h.x, minf(h.y, h.z)) * 0.5)
	# 6 ścian zmniejszonych o bevel + paski skosów między nimi (prosty „zaokrąglony” klocek)
	var dirs := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for n: Vector3 in dirs:
		var u := Vector3(n.y, n.z, n.x).abs()
		var v := n.cross(u)
		var hu := absf(h.dot(u)) - b
		var hv := absf(h.dot(v)) - b
		var c := n * absf(h.dot(n))
		var q := [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
		_quad(st, q, n)
		# skosy: krawędź tej ściany do sąsiedniej
		for e in 4:
			var a: Vector3 = q[e]
			var d: Vector3 = q[(e + 1) % 4]
			var mid := (a + d) * 0.5 - c
			var side := mid.normalized()
			var a2 := a - n * b + side * b
			var d2 := d - n * b + side * b
			_quad(st, [a, a2, d2, d], (n + side).normalized())
	st.index()
	var mi := MeshInstance3D.new()
	mi.name = name
	mi.mesh = st.commit()
	mi.position = pos
	parent.add_child(mi)
	return mi


func _quad(st: SurfaceTool, q: Array, n: Vector3) -> void:
	var nrm := ((q[1] - q[0]) as Vector3).cross(q[2] - q[0])
	var order := [0, 1, 2, 0, 2, 3] if nrm.dot(n) < 0 else [0, 2, 1, 0, 3, 2]
	for i in order:
		st.set_normal(n)
		st.add_vertex(q[i])


func pivot(name: String, pos: Vector3, parent: Node3D) -> Node3D:
	var p := Node3D.new()
	p.name = name
	p.position = pos
	parent.add_child(p)
	return p


func _initialize() -> void:
	var root := Node3D.new()
	root.name = "Zombie"
	var SKIN := "#6f9a5a"
	var SKIN_D := "#557a44"
	var SHIRT := "#3d6a8c"
	var SHIRT_D := "#2c5070"
	var PANTS := "#3a3550"
	var BOOT := "#2a2420"
	# tułów
	var body := pivot("Body", Vector3(0, 0.78, 0), root)
	box("Torso", Vector3(0.52, 0.66, 0.3), Vector3(0, 0.36, 0), SHIRT, body)
	box("ShirtTear", Vector3(0.2, 0.16, 0.02), Vector3(0.1, 0.12, -0.155), SKIN_D, body, 0.01)
	box("ShirtTear2", Vector3(0.12, 0.1, 0.02), Vector3(-0.14, 0.42, -0.155), SKIN, body, 0.01)
	box("Collar", Vector3(0.36, 0.06, 0.32), Vector3(0, 0.68, 0), SHIRT_D, body, 0.01)
	box("Belt", Vector3(0.54, 0.07, 0.32), Vector3(0, 0.03, 0), "#4a3a2a", body, 0.01)
	# głowa
	var head := pivot("Head", Vector3(0, 0.72, 0), body)
	box("HeadMesh", Vector3(0.42, 0.44, 0.42), Vector3(0, 0.22, 0), SKIN, head, 0.04)
	box("Brow", Vector3(0.4, 0.06, 0.04), Vector3(0, 0.3, -0.21), SKIN_D, head, 0.01)
	box("EyeL", Vector3(0.09, 0.07, 0.02), Vector3(-0.1, 0.24, -0.215), "#e8d040", head, 0.005)
	box("EyeR", Vector3(0.09, 0.07, 0.02), Vector3(0.1, 0.24, -0.215), "#e8d040", head, 0.005)
	box("Mouth", Vector3(0.2, 0.05, 0.02), Vector3(0, 0.09, -0.215), "#2a1a18", head, 0.005)
	box("Hair", Vector3(0.44, 0.08, 0.44), Vector3(0, 0.44, 0.01), "#2e2a22", head, 0.02)
	# ręce wyciągnięte do przodu (podstawowa poza zombie)
	for side in [-1, 1]:
		var arm := pivot("ArmL" if side < 0 else "ArmR", Vector3(0.34 * side, 0.6, 0), body)
		arm.rotation.x = -1.35
		box("Sleeve" + ("L" if side < 0 else "R"), Vector3(0.17, 0.3, 0.17), Vector3(0, -0.13, 0), SHIRT, arm)
		box("Hand" + ("L" if side < 0 else "R"), Vector3(0.15, 0.34, 0.15), Vector3(0, -0.44, 0), SKIN, arm)
	for side in [-1, 1]:
		var leg := pivot("LegL" if side < 0 else "LegR", Vector3(0.13 * side, 0.78, 0), root)
		box("Thigh" + ("L" if side < 0 else "R"), Vector3(0.2, 0.62, 0.22), Vector3(0, -0.33, 0), PANTS, leg)
		box("Boot" + ("L" if side < 0 else "R"), Vector3(0.22, 0.16, 0.28), Vector3(0, -0.7, -0.03), BOOT, leg)

	# animacje w pliku
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	var arm_base := Vector3(-1.35, 0, 0)
	lib.add_animation("Idle", _anim(1.6, true, {
		"Body/ArmL": [[0.0, arm_base + Vector3(0.05, 0, 0.05)], [0.8, arm_base + Vector3(-0.08, 0, 0.02)], [1.6, arm_base + Vector3(0.05, 0, 0.05)]],
		"Body/ArmR": [[0.0, arm_base + Vector3(-0.06, 0, -0.04)], [0.8, arm_base + Vector3(0.07, 0, -0.02)], [1.6, arm_base + Vector3(-0.06, 0, -0.04)]],
		"Body/Head": [[0.0, Vector3(0, 0, 0.12)], [0.8, Vector3(0.08, 0.1, 0.18)], [1.6, Vector3(0, 0, 0.12)]],
	}))
	lib.add_animation("Walk", _anim(1.0, true, {
		"LegL": [[0.0, Vector3(0.55, 0, 0)], [0.5, Vector3(-0.55, 0, 0)], [1.0, Vector3(0.55, 0, 0)]],
		"LegR": [[0.0, Vector3(-0.55, 0, 0)], [0.5, Vector3(0.55, 0, 0)], [1.0, Vector3(-0.55, 0, 0)]],
		"Body/ArmL": [[0.0, arm_base + Vector3(0.12, 0, 0)], [0.5, arm_base + Vector3(-0.12, 0, 0)], [1.0, arm_base + Vector3(0.12, 0, 0)]],
		"Body/ArmR": [[0.0, arm_base + Vector3(-0.12, 0, 0)], [0.5, arm_base + Vector3(0.12, 0, 0)], [1.0, arm_base + Vector3(-0.12, 0, 0)]],
		"Body": [[0.0, Vector3(0.06, 0.08, 0.04)], [0.5, Vector3(0.06, -0.08, -0.04)], [1.0, Vector3(0.06, 0.08, 0.04)]],
		"Body/Head": [[0.0, Vector3(0, 0, 0.15)], [0.5, Vector3(0, 0, 0.08)], [1.0, Vector3(0, 0, 0.15)]],
	}))
	lib.add_animation("Attack", _anim(0.6, false, {
		"Body/ArmL": [[0.0, arm_base], [0.2, Vector3(-2.4, 0, 0)], [0.35, Vector3(-0.6, 0, 0)], [0.6, arm_base]],
		"Body/ArmR": [[0.0, arm_base], [0.2, Vector3(-2.4, 0, 0)], [0.35, Vector3(-0.6, 0, 0)], [0.6, arm_base]],
		"Body": [[0.0, Vector3.ZERO], [0.2, Vector3(-0.15, 0, 0)], [0.35, Vector3(0.25, 0, 0)], [0.6, Vector3.ZERO]],
	}))
	lib.add_animation("Hurt", _anim(0.35, false, {
		"Body": [[0.0, Vector3.ZERO], [0.1, Vector3(-0.35, 0, 0.1)], [0.35, Vector3.ZERO]],
		"Body/Head": [[0.0, Vector3.ZERO], [0.1, Vector3(-0.4, 0, 0)], [0.35, Vector3.ZERO]],
	}))
	ap.add_animation_library("", lib)
	# eksport
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_scene(root, state)
	var path := "res://mods/podstawowa/mods/monsters/models/zombie.glb"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://mods/podstawowa/mods/monsters/models"))
	if err == OK:
		err = doc.write_to_filesystem(state, ProjectSettings.globalize_path(path))
	print("GLB ", path, " błąd=", err, " animacji=", lib.get_animation_list().size())
	# sprawdzenie: wczytanie z powrotem
	var doc2 := GLTFDocument.new()
	var st2 := GLTFState.new()
	if doc2.append_from_file(ProjectSettings.globalize_path(path), st2) == OK:
		var sc := doc2.generate_scene(st2)
		var players := sc.find_children("*", "AnimationPlayer", true, false)
		if not players.is_empty():
			print("Wczytane animacje: ", (players[0] as AnimationPlayer).get_animation_list())
		print("Węzły: ", sc.find_children("*", "Node3D", true, false).map(func(n): return n.name).slice(0, 12))
	quit()


## Animacja obrotów: ścieżka węzła -> [[czas, kąty w radianach]].
func _anim(length: float, loop: bool, tracks: Dictionary) -> Animation:
	var a := Animation.new()
	a.length = length
	a.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	for path in tracks:
		var ti := a.add_track(Animation.TYPE_ROTATION_3D)
		a.track_set_path(ti, NodePath(str(path)))
		for k in tracks[path]:
			a.rotation_track_insert_key(ti, float(k[0]), Quaternion.from_euler(k[1]))
	return a
