#pragma once
#include <godot_cpp/classes/fast_noise_lite.hpp>
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/packed_byte_array.hpp>
#include <godot_cpp/variant/packed_float64_array.hpp>
#include <godot_cpp/variant/packed_int32_array.hpp>

#include <vector>

namespace godot {

// Rdzeń świata w C++: przygotowanie chunka (teren z danych modów, edycje, obwódka sąsiadów)
// i budowa siatki. Logika generowania musi być identyczna z game/scripts/terrain.gd.
// Po configure() obiekt jest tylko do odczytu, więc prepare() i build() można wołać z wielu wątków.
class VoxelMesher : public RefCounted {
	GDCLASS(VoxelMesher, RefCounted)

	Ref<FastNoiseLite> hills, detail, temperature, humidity, mountain;
	int64_t seed = 0;
	int beach = 7, window = 2, nb = 0, n_ores = 0;
	double max_sum = 0.0;
	std::vector<double> B, F, PL, O;
	std::vector<int32_t> T;
	std::vector<int32_t> tiles, props;
	int atlas_cols = 16, atlas_rows = 1;

protected:
	static void _bind_methods();

public:
	// noises: [hills, detail, temperature, humidity, mountain]; spec: wynik WorldgenSpec.compile
	void configure(const Array &noises, const Dictionary &spec, const PackedInt32Array &tiles,
			const PackedInt32Array &props, int atlas_cols, int atlas_rows);
	// Zwraca [padded (34^3), blocks (32^3)]. own i neighbors[i] mogą być puste.
	Array prepare(const Vector3i &cpos, const PackedByteArray &own, const Array &neighbors) const;
	// Wynik: [vertices, normals, uvs, colors, indices, collision_faces]
	Array build(const PackedByteArray &padded) const;

	struct Col { int h; int biome; };
	Col column(int x, int z) const;
	int block_for(int wy, int h, int biome) const;
	int feature_at(int x, int z, int h, int biome) const;
	int plant_at(int x, int z, int h, int biome) const;
	void fill_padded(const Vector3i &cpos, uint8_t *out) const;
};

} // namespace godot
