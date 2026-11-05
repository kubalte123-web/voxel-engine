class_name ItemModel
## Modele 3D przedmiotów z klocków: ikony w slotach (renderowane z modelu), przedmiot w ręce postaci,
## przedmiot w pierwszej osobie i przedmiot leżący na ziemi.
##
## Model wybiera pole `model` w definicji przedmiotu:
##   - nazwa wbudowanego modelu: pickaxe, axe, shovel, sword, hoe, stick, torch, fishing_rod, apple, steak,
##     drumstick, fish, bread, egg, ingot, nugget, gem, lump, bucket, potion, shears, leather, feather, wool,
##     seeds, wheat (kolory z `icon.color` i `icon.color2` albo z `model_colors = { "#rrggbb", "#rrggbb" }`),
##   - tabela { boxes = { { size = {x,y,z}, pos = {x,y,z}, color = "#rrggbb", rot = {x,y,z}, glow = true }, ... },
##     grip = {x, y, z}, kind = "tool" | "item" } – własny model moda (1 = jeden blok).
## Bez pola `model` model dobiera się do wzoru ikony (pickaxe, sword, food, potion…); przedmiot-blok to
## sześcian (albo kształt bloku) z teksturami bloku; inne przedmioty: obrazek ikony wyciągnięty w 3D.
## Układ modelu: punkt chwytu w (0,0,0), oś długa (od rękojeści do głowicy) to +Y, przód do -Z.

const WOOD := Color(0.48, 0.32, 0.18)
const WOOD_DARK := Color(0.36, 0.23, 0.12)
const BONE := Color(0.93, 0.9, 0.82)

## Z wzoru ikony do wbudowanego modelu (przedmioty bez pola `model`).
const BY_PATTERN := {
	"pickaxe": "pickaxe", "axe": "axe", "shovel": "shovel", "sword": "sword", "hoe": "hoe", "hammer": "pickaxe",
	"stick": "stick", "torch": "torch", "food": "apple", "potion": "potion", "gem": "gem", "ingot": "ingot",
	"seeds": "seeds", "plant": "wheat",
}

const NAMES := ["pickaxe", "axe", "shovel", "sword", "hoe", "stick", "torch", "fishing_rod", "apple", "steak",
	"drumstick", "fish", "bread", "egg", "ingot", "nugget", "gem", "lump", "bucket", "potion", "shears",
	"leather", "feather", "wool", "seeds", "wheat"]


static func _c(v: Variant, fallback: Color) -> Color:
	if v is Color:
		return v
	if v is String and v != "":
		return Color.from_string(v, fallback)
	return fallback


## Opis modelu przedmiotu: {"kind": "tool"|"item"|"block"|"sprite", "boxes": [...], "grip": Vector3, "block": id}.
## Klocek: [rozmiar, środek, kolor, obrót w stopniach, świeci].
static func spec(reg: Registry, key: String) -> Dictionary:
	var it: Dictionary = reg.items.get(key, {})
	var d: Dictionary = it.get("data", {}) if it.get("data") is Dictionary else {}
	var b := int(it.get("block", -1))
	var icon: Variant = d.get("icon")
	var c1 := Color(0.6, 0.6, 0.62)
	var c2 := Color(0.4, 0.4, 0.42)
	if icon is Dictionary:
		c1 = _c(icon.get("color"), c1)
		c2 = _c(icon.get("color2"), c2.darkened(0.0) if not icon.has("color") else c1.darkened(0.25))
	var mc: Variant = d.get("model_colors")
	if mc is Array and mc.size() > 0:
		c1 = _c(mc[0], c1)
		c2 = _c(mc[1], c2) if mc.size() > 1 else c1.darkened(0.25)
	var m: Variant = d.get("model")
	if m is Dictionary:
		return _custom(m)
	var name := str(m) if m is String else ""
	if name == "" and b > 0:
		return {"kind": "block", "block": b, "grip": Vector3(0, 0, 0)}
	if name == "" and icon is Dictionary:
		name = str(BY_PATTERN.get(str(icon.get("pattern", "")), ""))
	if name in NAMES:
		return _builtin(name, c1, c2, key)
	return {"kind": "sprite", "grip": Vector3.ZERO}


static func _custom(m: Dictionary) -> Dictionary:
	var boxes := []
	for bx in Registry.arr(m.get("boxes")):
		if not bx is Dictionary:
			continue
		boxes.append([Creature.vec(bx.get("size"), Vector3(0.1, 0.1, 0.1)), Creature.vec(bx.get("pos")),
			_c(bx.get("color"), Color.GRAY), Creature.vec(bx.get("rot")), bool(bx.get("glow", false))])
	return {"kind": str(m.get("kind", "item")), "boxes": boxes, "grip": Creature.vec(m.get("grip"))}


static func _bx(size: Vector3, pos: Vector3, col: Color, rot := Vector3.ZERO, glow := false) -> Array:
	return [size, pos, col, rot, glow]


## Wbudowane modele (kolory c1, c2 z ikony przedmiotu).
static func _builtin(name: String, c1: Color, c2: Color, key: String) -> Dictionary:
	var k := "item"
	var b := []
	var handle := func(len: float, y0: float) -> void:
		b.append(_bx(Vector3(0.1, len, 0.1), Vector3(0, y0 + len * 0.5, 0), WOOD))
		b.append(_bx(Vector3(0.11, 0.07, 0.11), Vector3(0, y0 + 0.1, 0), WOOD_DARK))   # owijka przy chwycie
	match name:
		"pickaxe":
			k = "tool"
			handle.call(0.92, -0.2)
			b.append(_bx(Vector3(0.2, 0.17, 0.15), Vector3(0, 0.7, 0), c2))
			b.append(_bx(Vector3(0.36, 0.13, 0.13), Vector3(-0.24, 0.66, 0), c1, Vector3(0, 0, -18)))
			b.append(_bx(Vector3(0.36, 0.13, 0.13), Vector3(0.24, 0.66, 0), c1, Vector3(0, 0, 18)))
			b.append(_bx(Vector3(0.14, 0.1, 0.11), Vector3(-0.44, 0.55, 0), c1.lightened(0.12), Vector3(0, 0, -38)))
			b.append(_bx(Vector3(0.14, 0.1, 0.11), Vector3(0.44, 0.55, 0), c1.lightened(0.12), Vector3(0, 0, 38)))
		"axe":
			k = "tool"
			handle.call(0.92, -0.2)
			b.append(_bx(Vector3(0.15, 0.2, 0.14), Vector3(0, 0.6, 0), c2))
			b.append(_bx(Vector3(0.24, 0.36, 0.09), Vector3(0.17, 0.6, 0), c1))
			b.append(_bx(Vector3(0.07, 0.44, 0.095), Vector3(0.31, 0.6, 0), c1.lightened(0.15)))
			b.append(_bx(Vector3(0.09, 0.12, 0.12), Vector3(-0.1, 0.62, 0), c2))
		"shovel":
			k = "tool"
			handle.call(0.76, -0.2)
			b.append(_bx(Vector3(0.14, 0.1, 0.14), Vector3(0, 0.59, 0), c2))
			b.append(_bx(Vector3(0.3, 0.34, 0.07), Vector3(0, 0.79, 0), c1))
			b.append(_bx(Vector3(0.2, 0.08, 0.07), Vector3(0, 0.99, 0), c1))
			b.append(_bx(Vector3(0.32, 0.04, 0.08), Vector3(0, 0.63, 0), c2))
		"sword":
			k = "tool"
			b.append(_bx(Vector3(0.1, 0.26, 0.1), Vector3(0, 0.0, 0), WOOD))
			b.append(_bx(Vector3(0.15, 0.1, 0.15), Vector3(0, -0.17, 0), c2))
			b.append(_bx(Vector3(0.44, 0.1, 0.14), Vector3(0, 0.17, 0), c2))
			b.append(_bx(Vector3(0.16, 0.74, 0.05), Vector3(0, 0.58, 0), c1))
			b.append(_bx(Vector3(0.05, 0.62, 0.06), Vector3(0, 0.55, 0), c1.darkened(0.2)))
			b.append(_bx(Vector3(0.11, 0.11, 0.05), Vector3(0, 0.96, 0), c1, Vector3(0, 0, 45)))
		"hoe":
			k = "tool"
			handle.call(0.92, -0.2)
			b.append(_bx(Vector3(0.32, 0.1, 0.11), Vector3(0.1, 0.68, 0), c1))
			b.append(_bx(Vector3(0.1, 0.18, 0.11), Vector3(0.23, 0.58, 0), c1.lightened(0.12)))
			b.append(_bx(Vector3(0.13, 0.13, 0.13), Vector3(0, 0.68, 0), c2))
		"stick":
			k = "tool"
			b.append(_bx(Vector3(0.1, 0.75, 0.1), Vector3(0, 0.2, 0), WOOD, Vector3(0, 0, 4)))
			b.append(_bx(Vector3(0.07, 0.14, 0.07), Vector3(0.07, 0.38, 0), WOOD_DARK, Vector3(0, 0, -35)))
		"torch":
			k = "tool"
			b.append(_bx(Vector3(0.08, 0.5, 0.08), Vector3(0, 0.08, 0), WOOD))
			b.append(_bx(Vector3(0.1, 0.1, 0.1), Vector3(0, 0.37, 0), Color(0.15, 0.12, 0.1)))
			b.append(_bx(Vector3(0.09, 0.13, 0.09), Vector3(0, 0.47, 0), Color(1.0, 0.75, 0.3), Vector3.ZERO, true))
			b.append(_bx(Vector3(0.05, 0.07, 0.05), Vector3(0, 0.56, 0), Color(1.0, 0.95, 0.6), Vector3.ZERO, true))
		"fishing_rod":
			k = "tool"
			b.append(_bx(Vector3(0.05, 1.15, 0.05), Vector3(0, 0.4, 0), c1))
			b.append(_bx(Vector3(0.07, 0.24, 0.07), Vector3(0, -0.02, 0), WOOD_DARK))
			b.append(_bx(Vector3(0.012, 0.5, 0.012), Vector3(0.0, 0.72, -0.03), c2, Vector3(0, 0, 0)))
			b.append(_bx(Vector3(0.05, 0.05, 0.05), Vector3(0.0, 0.47, -0.03), Color(0.85, 0.2, 0.2)))
		"apple":
			b.append(_bx(Vector3(0.3, 0.27, 0.3), Vector3(0, 0, 0), c1))
			b.append(_bx(Vector3(0.24, 0.05, 0.24), Vector3(0, 0.15, 0), c2))
			b.append(_bx(Vector3(0.24, 0.05, 0.24), Vector3(0, -0.15, 0), c2))
			b.append(_bx(Vector3(0.03, 0.09, 0.03), Vector3(0, 0.21, 0), WOOD_DARK))
			b.append(_bx(Vector3(0.09, 0.025, 0.05), Vector3(0.06, 0.21, 0), Color(0.3, 0.6, 0.25), Vector3(0, 0, 20)))
		"steak":
			var fat := Color(0.95, 0.88, 0.8) if c1.v > 0.6 else c1.lightened(0.25)
			b.append(_bx(Vector3(0.42, 0.3, 0.1), Vector3(0, 0, 0), c1))
			b.append(_bx(Vector3(0.3, 0.06, 0.105), Vector3(0.0, 0.17, 0), fat))
			b.append(_bx(Vector3(0.06, 0.22, 0.105), Vector3(-0.23, 0.0, 0), fat))
			b.append(_bx(Vector3(0.1, 0.07, 0.11), Vector3(0.06, -0.02, 0), c2))
			b.append(_bx(Vector3(0.08, 0.06, 0.08), Vector3(0.26, -0.1, 0), BONE))
		"drumstick":
			b.append(_bx(Vector3(0.26, 0.28, 0.22), Vector3(0, 0.14, 0), c1))
			b.append(_bx(Vector3(0.2, 0.1, 0.18), Vector3(0, 0.3, 0), c2))
			b.append(_bx(Vector3(0.07, 0.22, 0.07), Vector3(0, -0.1, 0), BONE))
			b.append(_bx(Vector3(0.13, 0.06, 0.08), Vector3(0, -0.22, 0), BONE))
		"fish":
			b.append(_bx(Vector3(0.42, 0.17, 0.08), Vector3(0, 0, 0), c1))
			b.append(_bx(Vector3(0.32, 0.06, 0.085), Vector3(0.02, -0.07, 0), c2.lightened(0.35)))
			b.append(_bx(Vector3(0.1, 0.22, 0.04), Vector3(-0.26, 0, 0), c2))
			b.append(_bx(Vector3(0.14, 0.05, 0.04), Vector3(0.0, 0.1, 0), c2))
			b.append(_bx(Vector3(0.035, 0.035, 0.09), Vector3(0.16, 0.03, 0), Color(0.08, 0.08, 0.1)))
		"bread":
			b.append(_bx(Vector3(0.44, 0.16, 0.2), Vector3(0, 0, 0), c1))
			b.append(_bx(Vector3(0.4, 0.06, 0.18), Vector3(0, 0.1, 0), c2))
			for i in 3:
				b.append(_bx(Vector3(0.04, 0.025, 0.19), Vector3(-0.12 + i * 0.12, 0.13, 0), c1.lightened(0.3), Vector3(0, 0, 20)))
		"egg":
			b.append(_bx(Vector3(0.18, 0.22, 0.18), Vector3(0, 0, 0), c1))
			b.append(_bx(Vector3(0.12, 0.06, 0.12), Vector3(0, 0.13, 0), c1))
			b.append(_bx(Vector3(0.14, 0.04, 0.14), Vector3(0, -0.12, 0), c2))
		"ingot":
			b.append(_bx(Vector3(0.4, 0.11, 0.2), Vector3(0, 0, 0), c2))
			b.append(_bx(Vector3(0.32, 0.05, 0.13), Vector3(0, 0.075, 0), c1))
		"nugget":
			b.append(_bx(Vector3(0.18, 0.15, 0.16), Vector3(-0.06, 0, 0), c1, Vector3(0, 20, 10)))
			b.append(_bx(Vector3(0.14, 0.12, 0.13), Vector3(0.09, -0.02, 0.02), c2, Vector3(10, -15, 0)))
			b.append(_bx(Vector3(0.1, 0.09, 0.1), Vector3(0.02, 0.09, -0.03), c1.lightened(0.2), Vector3(0, 30, 20)))
		"gem":
			b.append(_bx(Vector3(0.2, 0.2, 0.2), Vector3(0, 0, 0), c1, Vector3(45, 0, 45)))
			b.append(_bx(Vector3(0.1, 0.1, 0.1), Vector3(-0.03, 0.05, -0.08), c1.lightened(0.45), Vector3(45, 0, 45)))
		"lump":
			b.append(_bx(Vector3(0.24, 0.2, 0.22), Vector3(0, 0, 0), c1, Vector3(0, 15, 8)))
			b.append(_bx(Vector3(0.15, 0.14, 0.15), Vector3(0.1, 0.06, 0.02), c2, Vector3(10, -20, 0)))
		"bucket":
			var metal := Color(0.66, 0.66, 0.7)
			b.append(_bx(Vector3(0.3, 0.28, 0.3), Vector3(0, 0, 0), metal))
			b.append(_bx(Vector3(0.35, 0.05, 0.35), Vector3(0, 0.15, 0), metal.lightened(0.15)))
			b.append(_bx(Vector3(0.24, 0.04, 0.24), Vector3(0, -0.15, 0), metal.darkened(0.2)))
			if key != "bucket":
				b.append(_bx(Vector3(0.28, 0.02, 0.28), Vector3(0, 0.16, 0), c1))
			b.append(_bx(Vector3(0.025, 0.2, 0.025), Vector3(-0.17, 0.25, 0), metal.darkened(0.3), Vector3(0, 0, -20)))
			b.append(_bx(Vector3(0.025, 0.2, 0.025), Vector3(0.17, 0.25, 0), metal.darkened(0.3), Vector3(0, 0, 20)))
			b.append(_bx(Vector3(0.22, 0.025, 0.025), Vector3(0, 0.34, 0), metal.darkened(0.3)))
		"potion":
			var glass := Color(0.78, 0.88, 0.95, 0.45)
			b.append(_bx(Vector3(0.26, 0.24, 0.26), Vector3(0, 0, 0), glass))
			if c1.a > 0.05:
				b.append(_bx(Vector3(0.21, 0.17, 0.21), Vector3(0, -0.025, 0), Color(c1.r, c1.g, c1.b, 1.0)))
			b.append(_bx(Vector3(0.1, 0.12, 0.1), Vector3(0, 0.18, 0), glass))
			b.append(_bx(Vector3(0.08, 0.06, 0.08), Vector3(0, 0.26, 0), WOOD))
		"shears":
			k = "tool"
			b.append(_bx(Vector3(0.05, 0.32, 0.03), Vector3(-0.03, 0.22, 0), c1, Vector3(0, 0, 10)))
			b.append(_bx(Vector3(0.05, 0.32, 0.03), Vector3(0.03, 0.22, 0.02), c1.darkened(0.1), Vector3(0, 0, -10)))
			b.append(_bx(Vector3(0.12, 0.12, 0.04), Vector3(-0.07, -0.02, 0), Color(0.7, 0.2, 0.18)))
			b.append(_bx(Vector3(0.12, 0.12, 0.04), Vector3(0.07, -0.02, 0.02), Color(0.7, 0.2, 0.18)))
			b.append(_bx(Vector3(0.04, 0.04, 0.07), Vector3(0, 0.08, 0.01), Color(0.3, 0.3, 0.32)))
		"leather":
			b.append(_bx(Vector3(0.36, 0.3, 0.035), Vector3(0, 0, 0), c1))
			b.append(_bx(Vector3(0.1, 0.1, 0.035), Vector3(-0.2, 0.12, 0), c1, Vector3(0, 0, 30)))
			b.append(_bx(Vector3(0.1, 0.1, 0.035), Vector3(0.2, -0.12, 0), c1, Vector3(0, 0, 30)))
			b.append(_bx(Vector3(0.22, 0.16, 0.04), Vector3(0.02, 0.01, 0), c2))
		"feather":
			b.append(_bx(Vector3(0.022, 0.42, 0.022), Vector3(0, 0.05, 0), c2, Vector3(0, 0, -12)))
			b.append(_bx(Vector3(0.11, 0.32, 0.015), Vector3(0.03, 0.1, 0), c1, Vector3(0, 0, -12)))
		"wool":
			b.append(_bx(Vector3(0.28, 0.24, 0.26), Vector3(0, 0, 0), c1))
			b.append(_bx(Vector3(0.16, 0.12, 0.16), Vector3(0.08, 0.12, 0.02), c2))
			b.append(_bx(Vector3(0.14, 0.12, 0.14), Vector3(-0.1, 0.1, -0.04), c1.lightened(0.1)))
		"seeds":
			for i in 5:
				var a := i * 1.3
				b.append(_bx(Vector3(0.05, 0.07, 0.04), Vector3(cos(a) * 0.08, sin(a) * 0.08, 0), c1 if i % 2 == 0 else c2, Vector3(0, 0, i * 25)))
		"wheat":
			for i in 5:
				var x := -0.08 + i * 0.04
				b.append(_bx(Vector3(0.022, 0.38, 0.022), Vector3(x, 0, 0), c2, Vector3(0, 0, (i - 2) * 6)))
				b.append(_bx(Vector3(0.05, 0.12, 0.05), Vector3(x + (i - 2) * 0.02, 0.22, 0), c1, Vector3(0, 0, (i - 2) * 6)))
			b.append(_bx(Vector3(0.2, 0.04, 0.06), Vector3(0, -0.05, 0), WOOD))
	return {"kind": k, "boxes": b, "grip": Vector3.ZERO}


# ---------- siatki ----------

## Węzeł 3D przedmiotu (punkt chwytu w (0,0,0)). materials: lista materiałów do oświetlania (EntityLight).
static func build(reg: Registry, key: String, materials: Array = []) -> Node3D:
	var root := Node3D.new()
	root.name = "Item"
	var s := spec(reg, key)
	var mi := MeshInstance3D.new()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	match str(s.kind):
		"block":
			mi.mesh = block_mesh(reg, int(s.block))
			var m := StandardMaterial3D.new()
			m.albedo_texture = reg.atlas
			m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			m.vertex_color_use_as_albedo = true
			m.alpha_scissor_threshold = 0.5
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
			m.roughness = 0.9
			mi.material_override = m
			materials.append(m)
			mi.position = Vector3(-0.5, -0.5, -0.5) * 0.5   # sześcian 0.5 bloku, środek w punkcie chwytu
		"sprite":
			mi.mesh = sprite_mesh(reg.icon_image(key), materials)
			mi.position = Vector3(0, 0.1, 0)
		_:
			mi.mesh = boxes_mesh(s.boxes, materials)
			mi.position = -Vector3(s.grip)
	root.add_child(mi)
	root.set_meta("kind", str(s.kind))
	return root


static func _mat(transparent: bool, glow: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.8
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if glow:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## Klocki [rozmiar, środek, kolor, obrót°, świeci] w jednej siatce (osobne powierzchnie: zwykła, przezroczysta, świecąca).
static func boxes_mesh(boxes: Array, materials: Array) -> ArrayMesh:
	var groups := {"solid": [], "glass": [], "glow": []}
	for bx in boxes:
		var col: Color = bx[2]
		var g := "glow" if bool(bx[4]) else ("glass" if col.a < 0.99 else "solid")
		groups[g].append(bx)
	var mesh := ArrayMesh.new()
	for g in ["solid", "glass", "glow"]:
		if groups[g].is_empty():
			continue
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for bx in groups[g]:
			var size: Vector3 = bx[0]
			var rot: Vector3 = bx[3]
			var basis := Basis.from_euler(rot * (PI / 180.0))
			var xf := Transform3D(basis, bx[1])
			for f in 6:
				var nrm: Vector3 = (basis * BlockMesh.NORMALS[f]).normalized()
				var shade: float = [0.88, 0.88, 1.0, 0.7, 0.94, 0.94][f]
				var col: Color = bx[2]
				var c := Color(col.r * shade, col.g * shade, col.b * shade, col.a)
				var q: Array = BlockMesh.FACES[f]
				var pts := []
				for k in 4:
					pts.append(xf * ((q[k] - Vector3(0.5, 0.5, 0.5)) * size))
				for tri in [[0, 2, 1], [0, 3, 2]]:
					for k in tri:
						st.set_color(c)
						st.set_normal(nrm)
						st.add_vertex(pts[k])
		var m := _mat(g == "glass", g == "glow")
		materials.append(m)
		st.set_material(m)
		st.commit(mesh)
	return mesh


## Obrazek wyciągnięty w 3D: każdy nieprzezroczysty piksel to klocek (grubość 1/16), boki tylko na krawędziach.
static func sprite_mesh(img: Image, materials: Array) -> ArrayMesh:
	var im := img.duplicate() as Image
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() > 32:
		im.resize(32, 32, Image.INTERPOLATE_NEAREST)
	var w := im.get_width()
	var h := im.get_height()
	var px := 0.5 / float(maxi(w, h))   # cały obrazek: pół bloku
	var depth := 0.5 / 16.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var solid := func(x: int, y: int) -> bool:
		return x >= 0 and y >= 0 and x < w and y < h and im.get_pixel(x, y).a > 0.5
	for y in h:
		for x in w:
			if not solid.call(x, y):
				continue
			var col := im.get_pixel(x, y)
			var center := Vector3((x + 0.5 - w * 0.5) * px, (h * 0.5 - y - 0.5) * px, 0)
			var size := Vector3(px, px, depth)
			# przód i tył zawsze, boki tylko gdy sąsiad jest pusty
			var faces := [4, 5]
			if not solid.call(x + 1, y): faces.append(0)
			if not solid.call(x - 1, y): faces.append(1)
			if not solid.call(x, y - 1): faces.append(2)
			if not solid.call(x, y + 1): faces.append(3)
			for f in faces:
				var shade: float = [0.8, 0.8, 0.95, 0.65, 0.9, 1.0][f]
				var c := Color(col.r * shade, col.g * shade, col.b * shade, 1.0)
				var q: Array = BlockMesh.FACES[f]
				var pts := []
				for k in 4:
					pts.append(center + (q[k] - Vector3(0.5, 0.5, 0.5)) * size)
				for tri in [[0, 2, 1], [0, 3, 2]]:
					for k in tri:
						st.set_color(c)
						st.set_normal(BlockMesh.NORMALS[f])
						st.add_vertex(pts[k])
	var m := _mat(false, false)
	materials.append(m)
	st.set_material(m)
	return st.commit()


## Blok w ręce: jego klocki (albo cały sześcian) z teksturami z atlasu, rozmiar 0.5 bloku.
static func block_mesh(reg: Registry, block: int) -> ArrayMesh:
	var boxes := []
	if reg.props[block] & Registry.BOXES:
		for raw in Registry.arr(reg.defs[block].get("boxes")):
			var bx := Registry.arr(raw)
			if bx.size() >= 6:
				boxes.append([Vector3(float(bx[0]), float(bx[1]), float(bx[2])) / 16.0, Vector3(float(bx[3]), float(bx[4]), float(bx[5])) / 16.0])
	if boxes.is_empty():
		boxes = [[Vector3.ZERO, Vector3.ONE]]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cross := (reg.props[block] & (Registry.CROSS | Registry.THIN)) != 0
	for bx in boxes:
		var a: Vector3 = bx[0]
		var b: Vector3 = bx[1]
		for f in 6:
			if cross and f != 4 and f != 5:
				continue
			var t := reg.tiles[block * 6 + f]
			var q: Array = BlockMesh.FACES[f]
			var shade: float = BlockMesh.SHADE[f]
			var pts := []
			var uvs := []
			for k in 4:
				var p: Vector3 = q[k]
				var lp := Vector3(lerpf(a.x, b.x, p.x), lerpf(a.y, b.y, p.y), lerpf(a.z, b.z, p.z))
				if cross:
					lp.z = 0.5
				pts.append(lp * 0.5)
				# UV jak w siatce chunka: współrzędne ściany w obrębie bloku
				var u: Vector2
				match f:
					0, 1: u = Vector2(lp.z if f == 1 else 1.0 - lp.z, 1.0 - lp.y)
					2, 3: u = Vector2(lp.x, lp.z)
					_: u = Vector2(lp.x if f == 5 else 1.0 - lp.x, 1.0 - lp.y)
				if t * 4 + 3 < reg.tile_rects.size():
					uvs.append(Vector2(reg.tile_rects[t * 4] + clampf(u.x, 0.002, 0.998) * reg.tile_rects[t * 4 + 2],
						reg.tile_rects[t * 4 + 1] + clampf(u.y, 0.002, 0.998) * reg.tile_rects[t * 4 + 3]))
				else:
					uvs.append(Vector2.ZERO)
			for tri in [[0, 2, 1], [0, 3, 2]]:
				for k in tri:
					st.set_color(Color(shade, shade, shade))
					st.set_uv(uvs[k])
					st.set_normal(BlockMesh.NORMALS[f])
					st.add_vertex(pts[k])
	return st.commit()
