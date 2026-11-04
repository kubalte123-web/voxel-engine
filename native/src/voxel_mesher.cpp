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

constexpr uint8_t AIR = 0;
constexpr int P_OPAQUE = 1, P_CROSS = 2, P_SOLID = 4;
// układ danych z game/scripts/content/worldgen_spec.gd
constexpr int BS = 19, FS = 11, OS = 6;

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

inline double hash01(int64_t x, int64_t z, int64_t seed, int64_t salt) {
	uint32_t h = uint32_t(x) * 374761393u + uint32_t(z) * 668265263u + uint32_t(seed) * 1274126177u + uint32_t(salt) * 2246822519u;
	h = (h ^ (h >> 13)) * 1274126177u;
	h = h ^ (h >> 16);
	return double(h) / 4294967296.0;
}

inline double hash3(int x, int y, int z, int64_t seed, int salt) { return hash01(x, z, seed, int64_t(salt) + int64_t(y) * 31); }

inline int floordiv16(int v) { return int(std::floor(double(v) / 16.0)); }

inline void put(uint8_t *out, int x, int y, int z, int b, bool only_air) {
	if (x < 0 || y < 0 || z < 0 || x >= P || y >= P || z >= P) return;
	const int i = idx(x, y, z);
	if (only_air && out[i] != AIR) return;
	out[i] = uint8_t(b);
}

template <typename V, typename A>
void copy_array(V &dst, const A &src) {
	dst.resize(src.size());
	for (int i = 0; i < src.size(); i++) dst[i] = src[i];
}
} // namespace

void VoxelMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("configure", "noises", "spec", "tiles", "props", "atlas_cols", "atlas_rows"), &VoxelMesher::configure);
	ClassDB::bind_method(D_METHOD("prepare", "cpos", "own", "neighbors"), &VoxelMesher::prepare);
	ClassDB::bind_method(D_METHOD("build", "padded"), &VoxelMesher::build);
}

void VoxelMesher::configure(const Array &noises, const Dictionary &spec, const PackedInt32Array &p_tiles,
		const PackedInt32Array &p_props, int p_cols, int p_rows) {
	hills = noises[0];
	detail = noises[1];
	temperature = noises[2];
	humidity = noises[3];
	mountain = noises[4];
	copy_array(B, PackedFloat64Array(spec["biomes"]));
	copy_array(F, PackedFloat64Array(spec["features"]));
	copy_array(PL, PackedFloat64Array(spec["plants"]));
	copy_array(O, PackedFloat64Array(spec["ores"]));
	copy_array(T, PackedInt32Array(spec["templates"]));
	const PackedFloat64Array prm = spec["params"];
	seed = int64_t(prm[0]);
	beach = int(prm[1]);
	window = int(prm[2]);
	nb = int(prm[3]);
	max_sum = prm[4];
	n_ores = int(prm[5]);
	copy_array(tiles, p_tiles);
	copy_array(props, p_props);
	atlas_cols = p_cols > 0 ? p_cols : 1;
	atlas_rows = p_rows > 0 ? p_rows : 1;
}

VoxelMesher::Col VoxelMesher::column(int x, int z) const {
	const double temp = temperature->get_noise_2d(x, z);
	const double humid = humidity->get_noise_2d(x, z);
	int best = 0;
	double bestd = 1e30, wsum = 0.0, base = 0.0, amp = 0.0, rough = 0.0, mount = 0.0;
	for (int i = 0; i < nb; i++) {
		const double *b = &B[i * BS];
		const double dt = temp - b[0];
		const double dh = humid - b[1];
		const double d = dt * dt + dh * dh;
		if (d < bestd) { bestd = d; best = i; }
		const double w = 1.0 / (d * d + 0.000001);
		wsum += w;
		base += w * b[2];
		amp += w * b[3];
		rough += w * b[4];
		mount += w * b[5];
	}
	base /= wsum;
	amp /= wsum;
	rough /= wsum;
	mount /= wsum;
	const double h = base + double(hills->get_noise_2d(x, z)) * amp + double(detail->get_noise_2d(x, z)) * rough
			+ mount * (double(mountain->get_noise_2d(x, z)) * 0.5 + 0.5);
	return { int(std::round(h)), best };
}

int VoxelMesher::block_for(int wy, int h, int biome) const {
	if (wy > h) return AIR;
	const double *b = &B[biome * BS];
	int top = int(b[6]), filler = int(b[7]);
	if (h >= b[12]) { top = int(b[13]); filler = int(b[14]); }
	else if (h <= beach && b[10] >= 0.0) { top = int(b[10]); filler = int(b[11]); }
	if (wy == h) return top;
	if (wy >= h - int(b[8])) return filler;
	return int(b[9]);
}

int VoxelMesher::feature_at(int x, int z, int h, int biome) const {
	const double r = hash01(x, z, seed, 1);
	if (r >= max_sum) return -1;
	const double *b = &B[biome * BS];
	const int start = int(b[15]), n = int(b[16]);
	double acc = 0.0;
	for (int k = 0; k < n; k++) {
		const double *f = &F[(start + k) * FS];
		acc += f[0];
		if (r < acc) return (h >= f[9] && h <= f[10]) ? start + k : -1;
	}
	return -1;
}

int VoxelMesher::plant_at(int x, int z, int h, int biome) const {
	if (h <= beach) return 0;
	const double *b = &B[biome * BS];
	const int start = int(b[17]), n = int(b[18]);
	if (n == 0) return 0;
	const double r = hash01(x, z, seed, 2);
	double acc = 0.0;
	for (int k = 0; k < n; k++) {
		acc += PL[(start + k) * 2];
		if (r < acc) return int(PL[(start + k) * 2 + 1]);
	}
	return 0;
}

void VoxelMesher::fill_padded(const Vector3i &cpos, uint8_t *out) const {
	memset(out, 0, P * P * P);
	if (nb <= 0) return;
	const int bx = cpos.x * S - 1, by = cpos.y * S - 1, bz = cpos.z * S - 1;
	std::vector<Col> cols(P * P);
	for (int z = 0; z < P; z++) {
		for (int x = 0; x < P; x++) {
			const Col c = column(bx + x, bz + z);
			cols[x + P * z] = c;
			const int top = c.h - by;
			if (top >= 0) {
				const int ymax = top + 1 < P ? top + 1 : P;
				for (int y = 0; y < ymax; y++) out[idx(x, y, z)] = uint8_t(block_for(by + y, c.h, c.biome));
			}
			const int py = c.h + 1 - by;
			if (py >= 0 && py < P && feature_at(bx + x, bz + z, c.h, c.biome) < 0) {
				const int pl = plant_at(bx + x, bz + z, c.h, c.biome);
				if (pl != 0) out[idx(x, py, z)] = uint8_t(pl);
			}
		}
	}
	// rudy: w każdej komórce 16^3 najwyżej jedna żyła
	for (int i = 0; i < n_ores; i++) {
		const double *o = &O[i * OS];
		const int blk = int(o[0]), rep = int(o[1]), size = int(o[5]);
		const int salt = 1000 + i * 7;
		for (int cz = floordiv16(bz - size); cz <= floordiv16(bz + P - 1 + size); cz++)
			for (int cy = floordiv16(by - size); cy <= floordiv16(by + P - 1 + size); cy++)
				for (int cx = floordiv16(bx - size); cx <= floordiv16(bx + P - 1 + size); cx++) {
					if (hash3(cx, cy, cz, seed, salt) >= o[4]) continue;
					const int ox = cx * 16 + int(hash3(cx, cy, cz, seed, salt + 1) * 16.0);
					const int oy = cy * 16 + int(hash3(cx, cy, cz, seed, salt + 2) * 16.0);
					const int oz = cz * 16 + int(hash3(cx, cy, cz, seed, salt + 3) * 16.0);
					if (oy < o[2] || oy > o[3]) continue;
					const int r = 1 + int(hash3(cx, cy, cz, seed, salt + 4) * double(size));
					for (int dz = -r; dz <= r; dz++)
						for (int dy = -r; dy <= r; dy++)
							for (int dx = -r; dx <= r; dx++) {
								if (dx * dx + dy * dy + dz * dz > r * r) continue;
								const int lx = ox + dx - bx, ly = oy + dy - by, lz = oz + dz - bz;
								if (lx < 0 || ly < 0 || lz < 0 || lx >= P || ly >= P || lz >= P) continue;
								uint8_t &cell = out[idx(lx, ly, lz)];
								if (cell == rep) cell = uint8_t(blk);
							}
				}
	}
	// drzewa i struktury z okna szerszego o promień największego elementu
	struct Found { int x, z, h, f; double hv; };
	std::vector<Found> found;
	if (max_sum > 0.0) {
		for (int wz = bz - window; wz < bz + P + window; wz++) {
			for (int wx = bx - window; wx < bx + P + window; wx++) {
				if (hash01(wx, wz, seed, 1) >= max_sum) continue;
				Col c;
				const int lx = wx - bx, lz = wz - bz;
				if (lx >= 0 && lz >= 0 && lx < P && lz < P) c = cols[lx + P * lz];
				else c = column(wx, wz);
				const int f = feature_at(wx, wz, c.h, c.biome);
				if (f >= 0) found.push_back({ wx, wz, c.h, f, hash01(wx, wz, seed, 3) });
			}
		}
	}
	for (int pass = 0; pass < 2; pass++) {
		const bool soft = pass == 1;
		for (const Found &t : found) {
			const double *f = &F[t.f * FS];
			const int kind = int(f[1]);
			if (kind == 3) {
				const int s = int(f[7]), n = int(f[8]);
				for (int k = 0; k < n; k++) {
					const int32_t *e = &T[(s + k) * 5];
					if ((e[4] == 1) != soft) continue;
					put(out, t.x + e[0] - bx, t.h + 1 + e[1] - by, t.z + e[2] - bz, e[3], soft);
				}
				continue;
			}
			const int hmin = int(f[4]), hmax = int(f[5]);
			const int th = hmin + int(t.hv * double(hmax - hmin + 1));
			if (!soft) {
				for (int k = 1; k <= th; k++) put(out, t.x - bx, t.h + k - by, t.z - bz, int(f[2]), false);
				continue;
			}
			const int leaves = int(f[3]), rad = int(f[6]);
			const int tp = t.h + th;
			if (kind == 0) {
				for (int dy = -2; dy < 2; dy++) {
					const int r = dy <= -1 ? rad : rad - 1;
					for (int dz = -r; dz <= r; dz++)
						for (int dx = -r; dx <= r; dx++) {
							if (r >= 2 && std::abs(dx) == r && std::abs(dz) == r) continue;
							if (dy == 1 && std::abs(dx) + std::abs(dz) > 1) continue;
							put(out, t.x + dx - bx, tp + dy - by, t.z + dz - bz, leaves, true);
						}
				}
			} else if (kind == 1) {
				for (int y = tp + 1; y > t.h + 2; y--) {
					const int d = tp + 1 - y;
					const int r = d == 0 ? 0 : (d % 2 == 1 ? 1 : rad);
					for (int dz = -r; dz <= r; dz++)
						for (int dx = -r; dx <= r; dx++) {
							if (r >= 2 && std::abs(dx) == r && std::abs(dz) == r) continue;
							put(out, t.x + dx - bx, y - by, t.z + dz - bz, leaves, true);
						}
				}
			}
		}
	}
}

Array VoxelMesher::prepare(const Vector3i &cpos, const PackedByteArray &own, const Array &neighbors) const {
	PackedByteArray padded;
	padded.resize(P * P * P);
	uint8_t *p = padded.ptrw();
	fill_padded(cpos, p);

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

Array VoxelMesher::build(const PackedByteArray &padded) const {
	PackedVector3Array verts, norms, coll;
	PackedVector2Array uvs;
	PackedColorArray cols;
	PackedInt32Array indices;
	Array out;
	auto finish = [&]() {
		out.append(verts); out.append(norms); out.append(uvs); out.append(cols); out.append(indices); out.append(coll);
		return out;
	};
	if (padded.size() != P * P * P) return finish();

	const uint8_t *p = padded.ptr();
	const int prop_entries = int(props.size());
	auto prop = [&](uint8_t b) -> int { return b < prop_entries ? props[b] : (P_OPAQUE | P_SOLID); };
	const int tile_entries = int(tiles.size());
	auto tile_of = [&](int ti) { return ti < tile_entries ? tiles[ti] : 0; };

	int air = 0;
	for (int i = 0; i < P * P * P; i++) air += (p[i] == 0);
	if (air == 0 || air == P * P * P) return finish();

	std::vector<uint8_t> op(P * P * P);
	for (int i = 0; i < P * P * P; i++) op[i] = (prop(p[i]) & P_OPAQUE) ? 1 : 0;

	const float iu = 1.0f / float(atlas_cols);
	const float iv = 1.0f / float(atlas_rows);
	const float eps = 0.002f;
	auto uv_of = [&](int tile, float u, float v) {
		return Vector2((float(tile % atlas_cols) + clampf(u, eps, 1.0f - eps)) * iu,
				(float(tile / atlas_cols) + clampf(v, eps, 1.0f - eps)) * iv);
	};

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
							uvs.push_back(uv_of(tile, SIDE_UV[k][0], SIDE_UV[k][1]));
							cols.push_back(Color(PLANT_SHADE, PLANT_SHADE, PLANT_SHADE));
						}
						const int q[12] = { 0, 2, 1, 0, 3, 2, 0, 1, 2, 0, 2, 3 };
						for (int i = 0; i < 12; i++) indices.push_back(base + q[i]);
					}
					continue;
				}
				const bool solid = (bp & P_SOLID) != 0;
				const bool see_through = (bp & P_OPAQUE) == 0;
				for (int f = 0; f < 6; f++) {
					const int *n = NORMALS[f];
					const int fx = x + n[0], fy = y + n[1], fz = z + n[2];
					const int ni = idx(fx, fy, fz);
					if (op[ni]) continue;
					// przezroczyste bloki tego samego rodzaju (szkło) nie mają ścian między sobą
					if (see_through && p[ni] == b) continue;
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
						uvs.push_back(uv_of(tile, uvset[k][0], uvset[k][1]));
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
