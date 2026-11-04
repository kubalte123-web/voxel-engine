#pragma once
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

namespace godot {

// Rdzeń świata w C++: przygotowanie chunka (teren, biomy, drzewa, edycje, obwódka sąsiadów)
// i budowa siatki. Logika generowania musi być identyczna z game/scripts/terrain.gd.
class VoxelMesher : public RefCounted {
	GDCLASS(VoxelMesher, RefCounted)

protected:
	static void _bind_methods();

public:
	// noises: [hills, detail, temperature, humidity, mountain]
	// params: [seed, hill, trees (0/1), density, plants (0/1)]
	// Zwraca [padded (34^3), blocks (32^3)]. own i neighbors[i] mogą być puste.
	Array prepare(const Vector3i &cpos, const Array &noises, const PackedFloat64Array &params,
			const PackedByteArray &own, const Array &neighbors) const;
	// Wynik: [vertices, normals, uvs, colors, indices, collision_faces]
	Array build(const PackedByteArray &padded, const PackedInt32Array &tiles, int tile_count,
			const PackedInt32Array &props) const;
};

} // namespace godot
