#include "voxel_mesher.h"

#include <cmath>
#include <cstring>
#include <map>
#include <vector>

#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

using namespace godot;

namespace {
constexpr int S = 32;
constexpr int P = S + 2;

// bloki (zgodnie z game/scripts/blocks.gd)
enum : uint8_t {
	AIR = 0, GRASS = 1, DIRT = 2, STONE = 3, PLANKS = 4, SAND = 5, LOG = 6, LEAVES = 7,
	SNOW = 8, CACTUS = 9, TALL_GRASS = 10, FLOWER_RED = 11, FLOWER_YELLOW = 12
};
constexpr int P_OPAQUE = 1, P_CROSS = 2, P_SOLID = 4;
enum { MEADOW = 0, FOREST = 1, DESERT = 2, SNOWY = 3 };

const int NORMALS[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
const int CORNERS[6][4][3] = {
	{ { 1, 0, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 1, 0, 1 } },
	{ { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 }, { 0, 0, 0 } },
	{ { 0, 1, 0 }, { 0, 1, 1 }, { 1, 1, 1 }, { 1, 1, 0 } },
	{ { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 1 }, { 0, 0, 1 } },
	{ { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 }, { 0, 0, 1 } },
	{ { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } },
};
const float CROSS_CORNERS[2][4][3] = {
	{ { 0.1f, 0, 0.1f }, { 0.1f, 1, 0.1f }, { 0.9f, 1, 0.9f }, { 0.9f, 0, 0.9f } },
	{ { 0.1f, 0, 0.9f }, { 0.1f, 1, 0.9f }, { 0.9f, 1, 0.1f }, { 0.9f, 0, 0.1f } },
};
const float SIDE_UV[4][2] = { { 0, 1 }, { 0, 0 }, { 1, 0 }, { 1, 1 } };
const float TOP_UV[4][2] = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 0 } };
const float BOTTOM_UV[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
const float AO_LEVELS[4] = { 0.42f, 0.62f, 0.8f, 1.0f };
const float FACE_SHADE[6] = { 0.86f, 0.86f, 1.0f, 0.62f, 0.92f, 0.92f };
constexpr float PLANT_SHADE = 0.9f;

inline int idx(int x, int y, int z) { return x + P * (y + P * z); }
inline float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }
inline double clampd(double v, double a, double b) { return v < a ? a : (v > b ? b : v); }

inline double sm(double a, double b, double x) {
	const double t = clampd((x - a) / (b - a), 0.0, 1.0);
	return t * t * (3.0 - 2.0 * t);
}

inline double hash01(int x, int z, int64_t seed, int salt) {
	uint32_t h = uint32_t(x) * 374761393u + uint32_t(z) * 668265263u + uint32_t(seed) * 1274126177u + uint32_t(salt) * 2246822519u;
	h = (h ^ (h >> 13)) * 1274126177u;
	h = h ^ (h >> 16);
	return double(h) / 4294967296.0;
}

inline int biome_of(double temp, double humid) {
	if (temp > 0.3) return DESERT;
	if (temp < -0.3) return SNOWY;
	if (humid > 0.1) return FOREST;
	return MEADOW;
}

inline uint8_t block_for(int wy, int h, int biome) {
	if (wy > h) return AIR;
	if (biome == DESERT) return wy > h - 4 ? SAND : STONE;
	if (biome == SNOWY) {
		if (h >= 34) return wy == h ? SNOW : STONE;
		if (wy == h) return SNOW;
		return wy > h - 4 ? DIRT : STONE;
	}
	if (h <= 7) return wy > h - 4 ? SAND : STONE;
	if (wy == h) return GRASS;
	return wy > h - 4 ? DIRT : STONE;
}

struct Gen {
	Ref<FastNoiseLite> hills, detail, temperature, humidity, mountain;
	int64_t seed = 0;
	double hill = 1.0, density = 1.0;
	bool trees = true, plants = true;

	struct Col { int h; int biome; };

	Col column(int x, int z) const {
		const double temp = temperature->get_noise_2d(x, z);
		const double humid = humidity->get_noise_2d(x, z);
		const double desert_f = sm(0.15, 0.45, temp);
		const double cold_f = sm(-0.15, -0.45, temp);
		const double amp = 9.0 * hill * (1.0 - 0.6 * desert_f);
		const double h = 12.0 + double(hills->get_noise_2d(x, z)) * amp + double(detail->get_noise_2d(x, z)) * 1.5
				+ cold_f * (double(mountain->get_noise_2d(x, z)) * 0.5 + 0.5) * 30.0 * hill;
		return { int(std::round(h)), biome_of(temp, humid) };
	}

	int tree_at(int x, int z, int h, int biome) const {
		if (!trees || h <= 7) return 0;
		const double r = hash01(x, z, seed, 1);
		if (r >= 0.03 * density) return 0;
		switch (biome) {
			case FOREST: return 1;
			case MEADOW: return r < 0.004 * density ? 1 : 0;
			case SNOWY: return (r < 0.012 * density && h < 34) ? 2 : 0;
			case DESERT: return r < 0.006 * density ? 3 : 0;
		}
		return 0;
	}

	uint8_t plant_at(int x, int z, int h, int biome) const {
		if (!plants || h <= 7 || (biome != MEADOW && biome != FOREST)) return 0;
		const double r = hash01(x, z, seed, 2);
		if (biome == MEADOW) {
			if (r < 0.10) return TALL_GRASS;
			if (r < 0.125) return FLOWER_RED;
			if (r < 0.15) return FLOWER_YELLOW;
		} else {
			if (r < 0.18) return TALL_GRASS;
			if (r < 0.19) return FLOWER_RED;
		}
		return 0;
	}
};

inline int trunk_height(int kind, double hv) {
	if (kind == 1) return 4 + int(hv * 3.0);
	if (kind == 2) return 6 + int(hv * 3.0);
	return 2 + int(hv * 2.0);
}

inline void put(uint8_t *out, int x, int y, int z, uint8_t b, bool only_air) {
	if (x < 0 || y < 0 || z < 0 || x >= P || y >= P || z >= P) return;
	const int i = idx(x, y, z);
	if (only_air && out[i] != AIR) return;
	out[i] = b;
}

void fill_padded(const Gen &g, const Vector3i &cpos, uint8_t *out) {
	memset(out, 0, P * P * P);
	const int bx = cpos.x * S - 1, by = cpos.y * S - 1, bz = cpos.z * S - 1;
	std::vector<Gen::Col> cols(P * P);
	for (int z = 0; z < P; z++) {
		for (int x = 0; x < P; x++) {
			const Gen::Col c = g.column(bx + x, bz + z);
			cols[x + P * z] = c;
			const int top = c.h - by;
			if (top >= 0) {
				const int ymax = top + 1 < P ? top + 1 : P;
				for (int y = 0; y < ymax; y++) out[idx(x, y, z)] = block_for(by + y, c.h, c.biome);
			}
			const int py = c.h + 1 - by;
			if (py >= 0 && py < P && g.tree_at(bx + x, bz + z, c.h, c.biome) == 0) {
				const uint8_t pl = g.plant_at(bx + x, bz + z, c.h, c.biome);
				if (pl != 0) out[idx(x, py, z)] = pl;
			}
		}
	}
	struct Tree { int x, z, h, kind; double hv; };
	std::vector<Tree> found;
	if (g.trees) {
		for (int wz = bz - 2; wz < bz + P + 2; wz++) {
			for (int wx = bx - 2; wx < bx + P + 2; wx++) {
				if (hash01(wx, wz, g.seed, 1) >= 0.03 * g.density) continue;
				Gen::Col c;
				const int lx = wx - bx, lz = wz - bz;
				if (lx >= 0 && lz >= 0 && lx < P && lz < P) c = cols[lx + P * lz];
				else c = g.column(wx, wz);
				const int kind = g.tree_at(wx, wz, c.h, c.biome);
				if (kind != 0) found.push_back({ wx, wz, c.h, kind, hash01(wx, wz, g.seed, 3) });
			}
		}
	}
	for (const Tree &t : found) {
		const int th = trunk_height(t.kind, t.hv);
		const uint8_t blk = t.kind == 3 ? CACTUS : LOG;
		for (int k = 1; k <= th; k++) put(out, t.x - bx, t.h + k - by, t.z - bz, blk, false);
	}
	for (const Tree &t : found) {
		if (t.kind == 3) continue;
		const int th = trunk_height(t.kind, t.hv);
		const int tp = t.h + th;
		if (t.kind == 1) {
			for (int dy = -2; dy < 2; dy++) {
				const int r = dy <= -1 ? 2 : 1;
				for (int dz = -r; dz <= r; dz++)
					for (int dx = -r; dx <= r; dx++) {
						if (r == 2 && std::abs(dx) == 2 && std::abs(dz) == 2) continue;
						if (dy == 1 && std::abs(dx) + std::abs(dz) > 1) continue;
						put(out, t.x + dx - bx, tp + dy - by, t.z + dz - bz, LEAVES, true);
					}
			}
		} else {
			for (int y = tp + 1; y > t.h + 2; y--) {
				const int d = tp + 1 - y;
				const int r = d == 0 ? 0 : (d % 2 == 1 ? 1 : 2);
				for (int dz = -r; dz <= r; dz++)
					for (int dx = -r; dx <= r; dx++) {
						if (r == 2 && std::abs(dx) == 2 && std::abs(dz) == 2) continue;
						put(out, t.x + dx - bx, y - by, t.z + dz - bz, LEAVES, true);
					}
			}
		}
	}
}
} // namespace

void VoxelMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("prepare", "cpos", "noises", "params", "own", "neighbors"), &VoxelMesher::prepare);
	ClassDB::bind_method(D_METHOD("build", "padded", "tiles", "tile_count", "props"), &VoxelMesher::build);
}

Array VoxelMesher::prepare(const Vector3i &cpos, const Array &noises, const PackedFloat64Array &params,
		const PackedByteArray &own, const Array &neighbors) const {
	Gen g;
	g.hills = noises[0];
	g.detail = noises[1];
	g.temperature = noises[2];
	g.humidity = noises[3];
	g.mountain = noises[4];
	g.seed = int64_t(params[0]);
	g.hill = params[1];
	g.trees = params[2] > 0.5;
	g.density = params[3];
	g.plants = params[4] > 0.5;

	PackedByteArray padded;
	padded.resize(P * P * P);
	uint8_t *p = padded.ptrw();
	fill_padded(g, cpos, p);

	PackedByteArray blocks;
	blocks.resize(S * S * S);
	uint8_t *d = blocks.ptrw();
	if (own.size() == S * S * S) {
		const uint8_t *o = own.ptr();
		memcpy(d, o, S * S * S);
		for (int z = 0; z < S; z++)
			for (int y = 0; y < S; y++)
				for (int x = 0; x < S; x++) p[idx(x + 1, y + 1, z + 1)] = o[x + S * (y + S * z)];
	} else {
		for (int z = 0; z < S; z++)
			for (int y = 0; y < S; y++)
				for (int x = 0; x < S; x++) d[x + S * (y + S * z)] = p[idx(x + 1, y + 1, z + 1)];
	}
	for (int f = 0; f < 6 && f < neighbors.size(); f++) {
		if (neighbors[f].get_type() != Variant::PACKED_BYTE_ARRAY) continue;
		const PackedByteArray nd = neighbors[f];
		if (nd.size() != S * S * S) continue;
		const uint8_t *s = nd.ptr();
		for (int a = 0; a < S; a++) {
			for (int b = 0; b < S; b++) {
				int dst = 0, src = 0;
				switch (f) {
					case 0: dst = idx(P - 1, a + 1, b + 1); src = 0 + S * (a + S * b); break;
					case 1: dst = idx(0, a + 1, b + 1); src = (S - 1) + S * (a + S * b); break;
					case 2: dst = idx(a + 1, P - 1, b + 1); src = a + S * (0 + S * b); break;
					case 3: dst = idx(a + 1, 0, b + 1); src = a + S * ((S - 1) + S * b); break;
					case 4: dst = idx(a + 1, b + 1, P - 1); src = a + S * (b + S * 0); break;
					default: dst = idx(a + 1, b + 1, 0); src = a + S * (b + S * (S - 1)); break;
				}
				p[dst] = s[src];
			}
		}
	}
	Array out;
	out.append(padded);
	out.append(blocks);
	return out;
}

Array VoxelMesher::build(const PackedByteArray &padded, const PackedInt32Array &tiles, int tile_count,
		const PackedInt32Array &props) const {
	PackedVector3Array verts, norms, coll;
	PackedVector2Array uvs;
	PackedColorArray cols;
	PackedInt32Array indices;
	Array out;
	auto finish = [&]() {
		out.append(verts); out.append(norms); out.append(uvs); out.append(cols); out.append(indices); out.append(coll);
		return out;
	};
	if (padded.size() != P * P * P || tile_count <= 0) return finish();

	const uint8_t *p = padded.ptr();
	const int32_t *t = tiles.ptr();
	const int tile_entries = tiles.size();
	const int32_t *pr = props.ptr();
	const int prop_entries = props.size();
	auto prop = [&](uint8_t b) -> int { return b < prop_entries ? pr[b] : (P_OPAQUE | P_SOLID); };

	int air = 0;
	for (int i = 0; i < P * P * P; i++) air += (p[i] == 0);
	if (air == 0 || air == P * P * P) return finish();

	std::vector<uint8_t> op(P * P * P);
	for (int i = 0; i < P * P * P; i++) op[i] = (prop(p[i]) & P_OPAQUE) ? 1 : 0;

	const float inv = 1.0f / float(tile_count);
	const float eps = 0.002f;
	auto tile_of = [&](int ti) { return ti < tile_entries ? t[ti] : 0; };

	for (int z = 1; z <= S; z++) {
		for (int y = 1; y <= S; y++) {
			for (int x = 1; x <= S; x++) {
				const uint8_t b = p[idx(x, y, z)];
				if (b == 0) continue;
				const int bp = prop(b);
				if (bp & P_CROSS) {
					const int tile = tile_of(b * 6);
					for (int pl = 0; pl < 2; pl++) {
						const int base = verts.size();
						for (int k = 0; k < 4; k++) {
							const float *c = CROSS_CORNERS[pl][k];
							verts.push_back(Vector3(float(x - 1) + c[0], float(y - 1) + c[1], float(z - 1) + c[2]));
							norms.push_back(Vector3(0, 1, 0));
							uvs.push_back(Vector2((float(tile) + clampf(SIDE_UV[k][0], eps, 1.0f - eps)) * inv, clampf(SIDE_UV[k][1], eps, 1.0f - eps)));
							cols.push_back(Color(PLANT_SHADE, PLANT_SHADE, PLANT_SHADE));
						}
						const int q[12] = { 0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3 };
						for (int i = 0; i < 12; i++) indices.push_back(base + q[i]);
					}
					continue;
				}
				const bool solid = (bp & P_SOLID) != 0;
				for (int f = 0; f < 6; f++) {
					const int *n = NORMALS[f];
					const int fx = x + n[0], fy = y + n[1], fz = z + n[2];
					if (op[idx(fx, fy, fz)]) continue;
					const int tile = tile_of(b * 6 + f);
					const float(*uvset)[2] = f == 2 ? TOP_UV : (f == 3 ? BOTTOM_UV : SIDE_UV);
					const int base = verts.size();
					int ao[4];
					Vector3 v[4];
					for (int k = 0; k < 4; k++) {
						const int *c = CORNERS[f][k];
						int d1[3] = { 0, 0, 0 }, d2[3] = { 0, 0, 0 };
						if (n[0] != 0) { d1[1] = c[1] * 2 - 1; d2[2] = c[2] * 2 - 1; }
						else if (n[1] != 0) { d1[0] = c[0] * 2 - 1; d2[2] = c[2] * 2 - 1; }
						else { d1[0] = c[0] * 2 - 1; d2[1] = c[1] * 2 - 1; }
						const int s1 = op[idx(fx + d1[0], fy + d1[1], fz + d1[2])];
						const int s2 = op[idx(fx + d2[0], fy + d2[1], fz + d2[2])];
						const int cc = op[idx(fx + d1[0] + d2[0], fy + d1[1] + d2[1], fz + d1[2] + d2[2])];
						const int level = (s1 && s2) ? 0 : 3 - (s1 + s2 + cc);
						ao[k] = level;
						v[k] = Vector3(float(x - 1 + c[0]), float(y - 1 + c[1]), float(z - 1 + c[2]));
						verts.push_back(v[k]);
						norms.push_back(Vector3(float(n[0]), float(n[1]), float(n[2])));
						uvs.push_back(Vector2((float(tile) + clampf(uvset[k][0], eps, 1.0f - eps)) * inv, clampf(uvset[k][1], eps, 1.0f - eps)));
						const float shade = AO_LEVELS[level] * FACE_SHADE[f];
						cols.push_back(Color(shade, shade, shade));
					}
					// kolejność zgodna z ruchem wskazówek zegara (przód ściany w Godocie)
					static const int QA[6] = { 0, 2, 1, 0, 3, 2 };
					static const int QB[6] = { 1, 3, 2, 1, 0, 3 };
					const int *q = (ao[0] + ao[2] >= ao[1] + ao[3]) ? QA : QB;
					for (int i = 0; i < 6; i++) {
						indices.push_back(base + q[i]);
						if (solid) coll.push_back(v[q[i]]);
					}
				}
			}
		}
	}
	return finish();
}
