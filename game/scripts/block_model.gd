class_name BlockModel
extends Node3D
## Model jednego bloku w świecie (blok z polem `model`). Model składa się z pliku glTF/GLB (np. z Blendera)
## i/lub części z prostopadłościanów opisanych w Lua. Części i węzły pliku mają nazwy: animacje ruszają nimi,
## a wygląd (`look`) zmienia kolory, ukrywa je i włącza emitery cząsteczek.
##
## model = {
##   file = "models/kociol.glb", scale = 1, offset = {0, 0, 0},
##   parts = { chochla = { pivot = {x, y, z}, parent = "...", boxes = { {size, pos, rot, color, tag, glow} } } },
##   animations = { mieszanie = { length = 2, loop = true, tracks = { chochla = { {0, rot = {0, 0, 0}, pos = {...}}, ... } } } },
##   emitters = { bable = { particle = "nazwa", pos = {x, y, z}, rate = 1, color_from = "ciecz" } },
##   collision = { { min = {0, 0, 0}, max = {1, 1, 1} } },
##   look = { anim = "...", emitters = {...}, colors = { tag = "#rrggbb" }, hide = { "tag" } },
## }
## Model jest zwrócony przodem na północ (-Z); stan `facing` bloku go obraca.

const FACING := {"north": 0.0, "east": -PI / 2, "south": PI, "west": PI / 2}

static var _glb_cache := {}  # ścieżka -> Node3D (wzór do kopiowania)

var world: World
var pos := Vector3i.ZERO
var block := 0
var md := {}               # opis modelu
var root: Node3D
var parts := {}            # nazwa -> Node3D
var base_xform := {}       # nazwa -> Transform3D (pozycja spoczynkowa)
var tagged := {}           # tag/nazwa węzła -> [MeshInstance3D]
var lit_mats: Array = []   # materiały z pliku oświetlane mapą światła (StandardMaterial3D)
var box_mats: Array = []   # materiały części z klocków (shader model.gdshader)
var emitters := {}         # nazwa -> CPUParticles3D
var dynamic_look := {}     # wygląd ustawiony przez mod (engine.blocks.look)
var loop_anim := ""
var anim := {}             # {def, time, loop}
var _light_t := 0.0
var _vertex_mat: ShaderMaterial
var _glow_mat: StandardMaterial3D

static var _shader: Shader
static var force_fx := false   # testy wydajności: emitery także bez okna


func setup(w: World, p: Vector3i, id: int) -> void:
	world = w
	pos = p
	block = id
	var reg := world.reg
	md = reg.def_of(reg.base_of(id)).get("model", {})
	position = Vector3(p) + Vector3(0.5, 0.0, 0.5)


func _ready() -> void:
	root = Node3D.new()
	root.position = Creature.vec(md.get("offset"))
	root.scale = Vector3.ONE * float(md.get("scale", 1.0))
	add_child(root)
	_vertex_mat = _box_mat(Color.WHITE)
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.vertex_color_use_as_albedo = true
	if md.has("file"):
		_load_file(str(md.file))
	_build_parts()
	_build_collision()
	for n in md.get("emitters", {}):
		_make_emitter(str(n), md.emitters[n])
	set_block(block)
	_update_light()


## Materiał części z klocków: kolor z wierzchołków razy tint, światło ustawiane w _update_light.
func _box_mat(tint: Color) -> ShaderMaterial:
	if _shader == null:
		_shader = load("res://scripts/shaders/model.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	box_mats.append(m)
	return m


# ---------- plik GLB/glTF ----------

func _load_file(rel: String) -> void:
	var mod := str(world.reg.def_of(world.reg.base_of(block)).get("mod", ""))
	if rel.find(":") > 0 and not rel.begins_with("res:") and not rel.begins_with("user:"):
		mod = rel.substr(0, rel.find(":"))
		rel = rel.substr(rel.find(":") + 1)
	var path := world.reg._mod_path(mod).path_join(rel)
	var tpl: Node3D = _glb_cache.get(path)
	if tpl == null:
		if FileAccess.file_exists(path):
			var doc := GLTFDocument.new()
			var state := GLTFState.new()
			if doc.append_from_file(path, state) == OK:
				tpl = doc.generate_scene(state) as Node3D
		elif ResourceLoader.exists(path):
			var ps := load(path) as PackedScene   # mod wbudowany w wyeksportowaną grę
			if ps:
				tpl = ps.instantiate() as Node3D
		if tpl == null:
			push_warning("Nie można wczytać modelu: " + path)
			return
		_glb_cache[path] = tpl
	var inst := tpl.duplicate() as Node3D
	root.add_child(inst)
	_collect(inst)


## Węzły pliku: każdy nazwany węzeł jest częścią (do animacji), siatki dostają własne kopie materiałów.
func _collect(n: Node) -> void:
	if n is Node3D and n != root:
		parts[str(n.name)] = n
		base_xform[str(n.name)] = (n as Node3D).transform
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		var key := str(mi.name)
		if not tagged.has(key):
			tagged[key] = []
		tagged[key].append(mi)
		for s in mi.mesh.get_surface_count():
			var m: Material = mi.get_active_material(s)
			if m is StandardMaterial3D:
				var c := (m as StandardMaterial3D).duplicate() as StandardMaterial3D
				if c.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED and not c.emission_enabled:
					c.set_meta("base", c.albedo_color)
					lit_mats.append(c)
				mi.set_surface_override_material(s, c)
	for ch in n.get_children():
		_collect(ch)


# ---------- części z prostopadłościanów ----------

## Prostopadłościany jednej części łączymy w jedną siatkę (mniej wywołań rysowania): osobno tylko te z tagiem
## (kolor zmieniany w grze) i świecące.
func _build_parts() -> void:
	var pdefs: Dictionary = md.get("parts", {}) if md.get("parts") is Dictionary else {}
	var pending := pdefs.keys()
	var guard := 0
	while not pending.is_empty() and guard < 64:
		guard += 1
		for name in pending.duplicate():
			var pd: Dictionary = pdefs[name]
			var parent_name := str(pd.get("parent", ""))
			if parent_name != "" and not parts.has(parent_name) and pdefs.has(parent_name):
				continue
			var parent: Node3D = parts.get(parent_name, root)
			var pivot := Node3D.new()
			pivot.name = str(name)
			pivot.position = Creature.vec(pd.get("pivot"))
			pivot.rotation_degrees = Creature.vec(pd.get("rot"))
			parent.add_child(pivot)
			parts[str(name)] = pivot
			base_xform[str(name)] = pivot.transform
			var groups := {}   # klucz -> [boxy]
			for bd in Registry.arr(pd.get("boxes")):
				if not bd is Dictionary:
					continue
				var key := ""
				if bd.has("tag"):
					key = ("glow|" if bool(bd.get("glow", false)) else "tag|") + str(bd.tag) + "|" + str(bd.get("color", ""))
				elif bool(bd.get("glow", false)):
					key = "glowall"
				if not groups.has(key):
					groups[key] = []
				groups[key].append(bd)
			for key in groups:
				var st := SurfaceTool.new()
				st.begin(Mesh.PRIMITIVE_TRIANGLES)
				var single: bool = key.begins_with("tag|")
				for bd in groups[key]:
					_add_box(st, bd, Color.WHITE if single else TexGen._col(bd.get("color"), Color.WHITE))
				st.generate_normals()
				var mi := MeshInstance3D.new()
				mi.mesh = st.commit()
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				pivot.add_child(mi)
				var first: Dictionary = groups[key][0]
				if key == "":
					mi.material_override = _vertex_mat
				elif key.begins_with("glow"):
					mi.material_override = _glow_mat
				else:
					mi.material_override = _box_mat(TexGen._col(first.get("color"), Color.WHITE))
				if true:
					if first.has("tag"):
						var tg := str(first.tag)
						if not tagged.has(tg):
							tagged[tg] = []
						tagged[tg].append(mi)
			pending.erase(name)


func _add_box(st: SurfaceTool, bd: Dictionary, col: Color) -> void:
	var size := Creature.vec(bd.get("size"), Vector3(0.2, 0.2, 0.2))
	var xf := Transform3D(Basis.from_euler(Creature.vec(bd.get("rot")) * (PI / 180.0)), Creature.vec(bd.get("pos")))
	var h := size * 0.5
	var faces := [
		[Vector3(1, 0, 0), [Vector3(h.x, -h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(-1, 0, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, h.y, -h.z), Vector3(-h.x, -h.y, -h.z)]],
		[Vector3(0, 1, 0), [Vector3(-h.x, h.y, -h.z), Vector3(-h.x, h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(h.x, h.y, -h.z)]],
		[Vector3(0, -1, 0), [Vector3(-h.x, -h.y, h.z), Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z), Vector3(h.x, -h.y, h.z)]],
		[Vector3(0, 0, 1), [Vector3(h.x, -h.y, h.z), Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z), Vector3(-h.x, -h.y, h.z)]],
		[Vector3(0, 0, -1), [Vector3(-h.x, -h.y, -h.z), Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z), Vector3(h.x, -h.y, -h.z)]],
	]
	var shade := [0.86, 0.86, 1.0, 0.62, 0.92, 0.92]
	for i in 6:
		var q: Array = faces[i][1]
		var c := Color(col.r * shade[i], col.g * shade[i], col.b * shade[i], col.a)
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_color(c)
			st.add_vertex(xf * (q[k] as Vector3))


func _build_collision() -> void:
	if (world.reg.props[block] & Registry.SOLID) == 0:
		return
	var body := StaticBody3D.new()
	add_child(body)
	var boxes := Registry.arr(md.get("collision"))
	if boxes.is_empty():
		boxes = [{"min": [0, 0, 0], "max": [1, 1, 1]}]
	for b in boxes:
		var lo := Creature.vec(b.get("min"), Vector3.ZERO)
		var hi := Creature.vec(b.get("max"), Vector3.ONE)
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = (hi - lo).abs()
		cs.shape = sh
		cs.position = (lo + hi) * 0.5 - Vector3(0.5, 0.0, 0.5)
		body.add_child(cs)


func _make_emitter(name: String, ed: Variant) -> void:
	if not ed is Dictionary:
		return
	var opts := {"amount": float(ed.get("rate", 1.0))}
	var p := Fx.build(str(ed.get("particle", "")), opts, false)
	if p == null:
		return
	p.position = Creature.vec(ed.get("pos"))
	p.emitting = false
	p.set_meta("def", ed)
	root.add_child(p)
	emitters[name] = p


# ---------- wygląd ----------

## Nowy wariant bloku (zmiana stanu): obrót i wygląd z definicji wariantu.
func set_block(id: int) -> void:
	block = id
	var st := world.reg.state_of(id)
	rotation.y = float(FACING.get(str(st.get("facing", "north")), 0.0))
	_apply_look()


func set_dynamic_look(look: Dictionary) -> void:
	dynamic_look = look
	_apply_look()


func _apply_look() -> void:
	if root == null:
		return
	var d := world.reg.def_of(block)
	var look := {}
	for src in [md.get("look", {}), d.get("look", {}), dynamic_look]:
		if src is Dictionary:
			for k in src:
				if k == "colors" and look.get("colors") is Dictionary and src[k] is Dictionary:
					var c: Dictionary = look.colors.duplicate()
					c.merge(src[k], true)
					look.colors = c
				else:
					look[k] = src[k]
	var hide := Registry.arr(look.get("hide"))
	for tg in tagged:
		for mi in tagged[tg]:
			mi.visible = not hide.has(tg)
	var colors: Dictionary = look.get("colors", {}) if look.get("colors") is Dictionary else {}
	for tg in colors:
		var c := TexGen._col(colors[tg], Color.WHITE)
		for mi in tagged.get(tg, []):
			var m: Variant = mi.material_override
			if m == null and mi.mesh and mi.mesh.get_surface_count() > 0:
				m = mi.get_surface_override_material(0)
			if m is ShaderMaterial:
				(m as ShaderMaterial).set_shader_parameter("tint", Vector3(c.r, c.g, c.b))
			elif m is StandardMaterial3D:
				if m.has_meta("base"):
					m.set_meta("base", c)
				else:
					m.albedo_color = c
	var on := Registry.arr(look.get("emitters"))
	for n in emitters:
		var p: CPUParticles3D = emitters[n]
		var want := on.has(n) and (DisplayServer.get_name() != "headless" or force_fx)
		var ed: Dictionary = p.get_meta("def")
		if want and ed.has("color_from") and colors.has(str(ed.color_from)):
			var c := TexGen._col(colors[str(ed.color_from)], Color.WHITE)
			var g := (p.color_ramp as Gradient).duplicate() as Gradient
			for i in g.get_point_count():
				var o := g.get_color(i)
				g.set_color(i, Color(c.r, c.g, c.b, o.a))
			p.color_ramp = g
		if p.emitting != want:
			p.emitting = want
	var la := str(look.get("anim", ""))
	if la != loop_anim:
		loop_anim = la
		if anim.is_empty() or bool(anim.get("loop", false)):
			_start(la, true)
	_light_t = 0.0


# ---------- animacje ----------

func play(name: String) -> void:
	_start(name, false)


func _start(name: String, looping: bool) -> void:
	var anims: Dictionary = md.get("animations", {}) if md.get("animations") is Dictionary else {}
	if name == "" or not anims.has(name):
		anim = {}
		_reset_pose()
		return
	var ad: Dictionary = anims[name]
	anim = {"def": ad, "time": 0.0, "loop": looping or bool(ad.get("loop", false))}


func _reset_pose() -> void:
	for n in base_xform:
		if parts.has(n):
			(parts[n] as Node3D).transform = base_xform[n]


func _process(delta: float) -> void:
	_light_t -= delta
	if _light_t <= 0.0:
		_light_t = 0.3
		_update_light()
	if anim.is_empty():
		return
	var ad: Dictionary = anim.def
	var length := maxf(0.05, float(ad.get("length", 1.0)))
	anim.time += delta
	if anim.time > length:
		if anim.loop:
			anim.time = fmod(anim.time, length)
		else:
			anim = {}
			_reset_pose()
			_start(loop_anim, true)
			return
	var tracks: Dictionary = ad.get("tracks", {}) if ad.get("tracks") is Dictionary else {}
	for pn in tracks:
		if not parts.has(pn):
			continue
		var node: Node3D = parts[pn]
		var b: Transform3D = base_xform[pn]
		var smp := _sample(Registry.arr(tracks[pn]), anim.time)
		var rot: Vector3 = smp.get("rot", Vector3.ZERO)
		var off: Vector3 = smp.get("pos", Vector3.ZERO)
		var sc: Vector3 = smp.get("scale", Vector3.ONE)
		node.transform = Transform3D(b.basis * Basis.from_euler(rot * (PI / 180.0)).scaled(sc), b.origin + off)


## Klatki: {czas, {rx, ry, rz}} albo {czas, rot = {...}, pos = {...}, scale = {...}}; między klatkami płynnie.
static func _sample(keys: Array, time: float) -> Dictionary:
	var prev: Dictionary = {}
	for k in keys:
		var e := _key(k)
		if e.is_empty():
			continue
		if e.t >= time:
			if prev.is_empty():
				return e
			var f: float = (float(time) - float(prev.t)) / maxf(0.0001, float(e.t) - float(prev.t))
			var out := {}
			for ch in ["rot", "pos", "scale"]:
				var fb: Vector3 = Vector3.ONE if ch == "scale" else Vector3.ZERO
				out[ch] = (prev.get(ch, fb) as Vector3).lerp(e.get(ch, fb), f)
			return out
		prev = e
	return prev


static func _key(k: Variant) -> Dictionary:
	if k is Dictionary:
		var e := {"t": float(k.get("t", k.get(1, 0.0)))}
		if k.has(2) and not k.has("rot"):
			e.rot = Creature.vec(k[2])
		for ch in ["rot", "pos", "scale"]:
			if k.has(ch):
				e[ch] = Creature.vec(k[ch], Vector3.ONE if ch == "scale" else Vector3.ZERO)
		return e
	var a := Registry.arr(k)
	if a.size() >= 2:
		return {"t": float(a[0]), "rot": Creature.vec(a[1])}
	return {}


func _update_light() -> void:
	if world == null:
		return
	var l := world.light_at(position + Vector3(0, 0.5, 0))
	EntityLight.apply(lit_mats, l)
	var f := EntityLight.factors(l)
	var torch := Vector3(EntityLight.TORCH.r, EntityLight.TORCH.g, EntityLight.TORCH.b) * f.y
	for m in box_mats:
		m.set_shader_parameter("sky", f.x)
		m.set_shader_parameter("torch", torch)
