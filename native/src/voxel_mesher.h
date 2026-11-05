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

	Ref<FastNoiseLite> hills, detail, temperature, humidity, mountain, cave_a, cave_b, cave_c, lake;
	int64_t seed = 0;
	int beach = 7, window = 2, nb = 0, n_ores = 0;
	int sea = -100000, water = -1, cave_min_y = -56;
	bool caves = false;
	double cave_tw = 0.055, cave_tc = 0.6, lake_depth = 0.0, lake_t = 0.3;
	std::vector<int32_t> liquid;
	std::vector<int32_t> shape_index;
	std::vector<float> shape_boxes;
	std::vector<int32_t> lprops;  // id -> świecenie (0..15) | 16 nieprzezroczysty | 32 ciecz
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
			const PackedInt32Array &props, const PackedInt32Array &liquid, int atlas_cols, int atlas_rows);
	void set_light_props(const PackedInt32Array &lp);
	// kształty z prostopadłościanów: na id 11 liczb [przes, ile, grupa, N przes, N ile, E.., S.., W..],
	// prostopadłościany po 6 liczb (x1, y1, z1, x2, y2, z2) w szesnastkach bloku
	void set_shapes(const PackedInt32Array &index, const PackedFloat32Array &boxes);
	// Światło chunka cpos: obszar chunka z marginesem `margin` bloków (27 chunków: own i sąsiedzi, null =
	// brak danych, przybliżane mapą wysokości), skyh = najwyższy nieprzezroczysty blok w kolumnach obszaru.
	// Zwraca [światło obwódki P^3, światło wnętrza S^3, najwyższe nieprzezroczyste bloki kolumn chunka S^2];
	// bajt światła = niebo << 4 | bloki.
	Array light(const Vector3i &cpos, const Array &chunks, const PackedInt32Array &skyh, int margin) const;
	// Zwraca [padded (34^3), blocks (32^3)]. own i neighbors[i] mogą być puste.
	Array prepare(const Vector3i &cpos, const PackedByteArray &own, const Array &neighbors) const;
	// Wynik: [vertices, normals, uvs, colors, indices, collision_faces,
	//         ciecz: vertices, normals, uvs (kierunek prądu), colors (piana, głębokość, brzeg fali, rodzaj), indices]
	Array build(const PackedByteArray &padded, const PackedByteArray &plight) const;
	// Daleki widok: wysokość i biom w siatce n x n co `step` bloków od (x0, z0): [h0, b0, h1, b1, ...]
	PackedInt32Array heights(int x0, int z0, int step, int n) const;

	struct Col { int h; int biome; };
	Col column(int x, int z) const;
	int block_for(int wy, int h, int biome) const;
	int feature_at(int x, int z, int h, int biome) const;
	int plant_at(int x, int z, int h, int biome) const;
	void fill_padded(const Vector3i &cpos, uint8_t *out) const;
	void carve_caves(uint8_t *out, int bx, int by, int bz, const std::vector<Col> &cols) const;
};

} // namespace godot
