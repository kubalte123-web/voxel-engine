#pragma once
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

// Buduje siatkę chunka 32^3 z tablicy z obwódką (34^3). Ten sam format wyniku co GDMesher:
// [vertices, normals, uvs, colors, indices, collision_faces]
class VoxelMesher : public RefCounted {
	GDCLASS(VoxelMesher, RefCounted)

protected:
	static void _bind_methods();

public:
	// Dane chunka z obwódką: teren z szumu, nałożone edycje chunka i graniczne warstwy sąsiadów.
	// Zwraca [padded (34^3), blocks (32^3)]. own i neighbors[i] mogą być puste.
	Array prepare(const Vector3i &cpos, const Ref<FastNoiseLite> &hills, const Ref<FastNoiseLite> &detail,
			const PackedByteArray &own, const Array &neighbors) const;
	Array build(const PackedByteArray &padded, const PackedInt32Array &tiles, int tile_count) const;
};

} // namespace godot
