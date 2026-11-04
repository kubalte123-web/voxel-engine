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
const SIDE_UV := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
const TOP_UV := [Vector2(0, 0), Vector2(0, 1), Vector2(1, 1), Vector2(1, 0)]
const BOTTOM_UV := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
const AO_LEVELS := [0.42, 0.62, 0.8, 1.0]
const FACE_SHADE := [0.86, 0.86, 1.0, 0.62, 0.92, 0.92]


static func _solid(p: PackedByteArray, x: int, y: int, z: int) -> int:
	return 1 if p[x + P * (y + P * z)] != 0 else 0


static func build(padded: PackedByteArray, tiles: PackedInt32Array, tile_count: int) -> Array:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var cols := PackedColorArray()
	var idx := PackedInt32Array()
	var coll := PackedVector3Array()

	var zero := padded.count(0)
	if zero == padded.size() or zero == 0:
		return [verts, norms, uvs, cols, idx, coll]

	var inv := 1.0 / float(tile_count)
	var eps := 0.002
	for z in range(1, S + 1):
		for y in range(1, S + 1):
			for x in range(1, S + 1):
				var b := padded[x + P * (y + P * z)]
				if b == 0:
					continue
				for f in 6:
					var n: Vector3i = NORMALS[f]
					var fx := x + n.x
					var fy := y + n.y
					var fz := z + n.z
					if padded[fx + P * (fy + P * fz)] != 0:
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
						# dwie osie styczne do ściany, w stronę narożnika
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
						var s1 := _solid(padded, fx + d1.x, fy + d1.y, fz + d1.z)
						var s2 := _solid(padded, fx + d2.x, fy + d2.y, fz + d2.z)
						var cc := _solid(padded, fx + d1.x + d2.x, fy + d1.y + d2.y, fz + d1.z + d2.z)
						var level := 0 if (s1 == 1 and s2 == 1) else 3 - (s1 + s2 + cc)
						ao[k] = level
						var v := Vector3(x - 1 + c.x, y - 1 + c.y, z - 1 + c.z)
						verts.append(v)
						norms.append(Vector3(n))
						var uv: Vector2 = uvset[k]
						uvs.append(Vector2((t + clampf(uv.x, eps, 1.0 - eps)) * inv, clampf(uv.y, eps, 1.0 - eps)))
						var shade: float = AO_LEVELS[level] * FACE_SHADE[f]
						cols.append(Color(shade, shade, shade))
					# kolejność zgodna z ruchem wskazówek zegara (przód ściany w Godocie)
					# przekątna czworokąta wybrana tak, żeby cienie w rogach były gładkie
					if ao[0] + ao[2] >= ao[1] + ao[3]:
						idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
						coll.append_array([verts[base], verts[base + 2], verts[base + 1], verts[base], verts[base + 3], verts[base + 2]])
					else:
						idx.append_array([base + 1, base + 3, base + 2, base + 1, base, base + 3])
						coll.append_array([verts[base + 1], verts[base + 3], verts[base + 2], verts[base + 1], verts[base], verts[base + 3]])
	return [verts, norms, uvs, cols, idx, coll]
