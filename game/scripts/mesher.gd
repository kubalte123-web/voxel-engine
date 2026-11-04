class_name GDMesher
## Zapasowy budowniczy siatek w GDScript (używany, gdy rdzeń w C++ nie jest dostępny).
## Wynik ma ten sam format co VoxelMesher z C++:
## [vertices, normals, uvs, colors, indices, collision_faces]

const S := 32
const P := S + 2

const NORMALS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const CORNERS := [
	[Vector3i(1, 0, 0), Vector3i(1, 1, 0), Vector3i(1, 1, 1), Vector3i(1, 0, 1)],
	[Vector3i(0, 0, 1), Vector3i(0, 1, 1), Vector3i(0, 1, 0), Vector3i(0, 0, 0)],
	[Vector3i(0, 1, 0), Vector3i(0, 1, 1), Vector3i(1, 1, 1), Vector3i(1, 1, 0)],
	[Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(0, 0, 1)],
	[Vector3i(1, 0, 1), Vector3i(1, 1, 1), Vector3i(0, 1, 1), Vector3i(0, 0, 1)],
	[Vector3i(0, 0, 0), Vector3i(0, 1, 0), Vector3i(1, 1, 0), Vector3i(1, 0, 0)],
]
const CROSS_CORNERS := [
	[Vector3(0.1, 0, 0.1), Vector3(0.1, 1, 0.1), Vector3(0.9, 1, 0.9), Vector3(0.9, 0, 0.9)],
	[Vector3(0.1, 0, 0.9), Vector3(0.1, 1, 0.9), Vector3(0.9, 1, 0.1), Vector3(0.9, 0, 0.1)],
]
const SIDE_UV := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
const TOP_UV := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
const BOTTOM_UV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
const AO_LEVELS := [0.42, 0.62, 0.8, 1.0]
const FACE_SHADE := [0.86, 0.86, 1.0, 0.62, 0.92, 0.92]
const PLANT_SHADE := 0.9


static func build(padded: PackedByteArray, tiles: PackedInt32Array, cols_n: int, rows_n: int, props: PackedInt32Array) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var coll := PackedVector3Array()

	var zero := padded.count(0)
	if zero == padded.size() or zero == 0:
		return [verts, norms, uvs, cols, idx, coll]

	# tablica nieprzezroczystości całego chunka z obwódką (1 = zasłania sąsiada)
	var op := PackedByteArray()
	op.resize(padded.size())
	for i in padded.size():
		op[i] = props[padded[i]] & Blocks.OPAQUE

	var iu := 1.0 / float(cols_n)
	var iv := 1.0 / float(rows_n)
	var eps := 0.002
	for z in range(1, S + 1):
		for y in range(1, S + 1):
			for x in range(1, S + 1):
				var b := padded[x + P * (y + P * z)]
				if b == 0:
					continue
				var pr := props[b]
				if pr & Blocks.CROSS:
					_cross(x, y, z, tiles[b * 6], cols_n, iu, iv, eps, verts, norms, uvs, cols, idx)
					continue
				var solid := pr & Blocks.SOLID
				var see_through := (pr & Blocks.OPAQUE) == 0
				for f in 6:
					var n: Vector3i = NORMALS[f]
					var fx := x + n.x
					var fy := y + n.y
					var fz := z + n.z
					var ni := fx + P * (fy + P * fz)
					if op[ni] != 0:
						continue
					# przezroczyste bloki tego samego rodzaju (szkło) nie mają ścian między sobą
					if see_through and padded[ni] == b:
						continue
					var t := tiles[b * 6 + f]
					var corners: Array = CORNERS[f]
					var uvset: Array = SIDE_UV
					if f == 2:
						uvset = TOP_UV
					elif f == 3:
						uvset = BOTTOM_UV
					var base := verts.size()
					var ao := [0, 0, 0, 0]
					for k in 4:
						var c: Vector3i = corners[k]
						var d1 := Vector3i.ZERO
						var d2 := Vector3i.ZERO
						if n.x != 0:
							d1 = Vector3i(0, c.y * 2 - 1, 0)
							d2 = Vector3i(0, 0, c.z * 2 - 1)
						elif n.y != 0:
							d1 = Vector3i(c.x * 2 - 1, 0, 0)
							d2 = Vector3i(0, 0, c.z * 2 - 1)
						else:
							d1 = Vector3i(c.x * 2 - 1, 0, 0)
							d2 = Vector3i(0, c.y * 2 - 1, 0)
						var s1 := op[(fx + d1.x) + P * ((fy + d1.y) + P * (fz + d1.z))]
						var s2 := op[(fx + d2.x) + P * ((fy + d2.y) + P * (fz + d2.z))]
						var cc := op[(fx + d1.x + d2.x) + P * ((fy + d1.y + d2.y) + P * (fz + d1.z + d2.z))]
						var level := 0 if (s1 == 1 and s2 == 1) else 3 - (s1 + s2 + cc)
						ao[k] = level
						verts.append(Vector3(x - 1 + c.x, y - 1 + c.y, z - 1 + c.z))
						norms.append(Vector3(n))
						var uv: Vector2 = uvset[k]
						uvs.append(Vector2((t % cols_n + clampf(uv.x, eps, 1.0 - eps)) * iu, (t / cols_n + clampf(uv.y, eps, 1.0 - eps)) * iv))
						var shade: float = AO_LEVELS[level] * FACE_SHADE[f]
						cols.append(Color(shade, shade, shade))
					# kolejność zgodna z ruchem wskazówek zegara (przód ściany w Godocie);
					# przekątna czworokąta wybrana tak, żeby cienie w rogach były gładkie
					var q: Array
					if ao[0] + ao[2] >= ao[1] + ao[3]:
						q = [0, 2, 1, 0, 3, 2]
					else:
						q = [1, 3, 2, 1, 0, 3]
					for i in 6:
						idx.append(base + q[i])
						if solid:
							coll.append(verts[base + q[i]])
	return [verts, norms, uvs, cols, idx, coll]


## Roślina: dwie skrzyżowane ściany, każda widoczna z obu stron. Bez kolizji.
static func _cross(x: int, y: int, z: int, t: int, cols_n: int, iu: float, iv: float, eps: float,
		verts: PackedVector3Array, norms: PackedVector3Array, uvs: PackedVector2Array,
		cols: PackedColorArray, idx: PackedInt32Array) -> void:
	for plane in CROSS_CORNERS:
		var base := verts.size()
		for k in 4:
			var c: Vector3 = plane[k]
			verts.append(Vector3(x - 1, y - 1, z - 1) + c)
			norms.append(Vector3.UP)
			var uv: Vector2 = SIDE_UV[k]
			uvs.append(Vector2((t % cols_n + clampf(uv.x, eps, 1.0 - eps)) * iu, (t / cols_n + clampf(uv.y, eps, 1.0 - eps)) * iv))
			cols.append(Color(PLANT_SHADE, PLANT_SHADE, PLANT_SHADE))
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2,
			base, base + 1, base + 2, base, base + 2, base + 3])
