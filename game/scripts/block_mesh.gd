class_name BlockMesh
## Siatki pojedynczych bloków poza chunkami: spadające bloki, obiekty luźne, przedmioty w świecie.

const FACES := [
	[Vector3(1, 0, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(1, 0, 1)],
	[Vector3(0, 0, 1), Vector3(0, 1, 1), Vector3(0, 1, 0), Vector3(0, 0, 0)],
	[Vector3(0, 1, 0), Vector3(0, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, 0)],
	[Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)],
	[Vector3(1, 0, 1), Vector3(1, 1, 1), Vector3(0, 1, 1), Vector3(0, 0, 1)],
	[Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 0, 0)],
]
const NORMALS := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 1, 0), Vector3(0, -1, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
const UV := [Vector2(0, 1), Vector2(0, 0), Vector2(1, 0), Vector2(1, 1)]
const SHADE := [0.86, 0.86, 1.0, 0.62, 0.92, 0.92]


## Sześcian od (0,0,0) do (size,size,size) z teksturami bloku z atlasu (materiał świata).
static func cube(reg: Registry, block: int, size: float) -> ArrayMesh:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var idx := PackedInt32Array()
	var iu := 1.0 / Registry.ATLAS_COLS
	var iv := 1.0 / reg.atlas_rows
	for f in 6:
		var t := reg.tiles[block * 6 + f]
		var base := v.size()
		for k in 4:
			v.append(FACES[f][k] * size)
			n.append(NORMALS[f])
			var u: Vector2 = UV[k]
			uv.append(Vector2((t % Registry.ATLAS_COLS + clampf(u.x, 0.002, 0.998)) * iu, (t / Registry.ATLAS_COLS + clampf(u.y, 0.002, 0.998)) * iv))
			col.append(Color(SHADE[f], 1.0, 0.0))
		idx.append_array([base, base + 2, base + 1, base, base + 3, base + 2])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Materiał z jedną teksturą bloku (do kul i walców).
static func tile_material(reg: Registry, block: int, face: int) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = ImageTexture.create_from_image(reg.tile_images[reg.tiles[block * 6 + face]])
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.roughness = 0.9
	m.albedo_color = Color(0.85, 0.85, 0.85)
	m.uv1_scale = Vector3(3, 2, 1)
	return m
