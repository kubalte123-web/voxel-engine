#include "voxel_mesher.h"

#include <cmath>
#include <cstring>
#include <algorithm>
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
constexpr int P_OPAQUE = 1, P_CROSS = 2, P_SOLID = 4, P_LIQUID = 8, P_THIN = 16;
// układ danych z game/scripts/content/worldgen_spec.gd
constexpr int BS = 21, FS = 11, OS = 6;
constexpr int CG = 11; // punkty siatki szumu jaskiń na oś

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
	ClassDB::bind_method(D_METHOD("configure", "noises", "spec", "tiles", "props", "liquid", "atlas_cols", "atlas_rows"), &VoxelMesher::configure);
	ClassDB::bind_method(D_METHOD("prepare", "cpos", "own", "neighbors"), &VoxelMesher::prepare);
	ClassDB::bind_method(D_METHOD("build", "padded", "plight"), &VoxelMesher::build);
	ClassDB::bind_method(D_METHOD("set_light_props", "lprops"), &VoxelMesher::set_light_props);
	ClassDB::bind_method(D_METHOD("light", "cpos", "chunks", "skyh", "margin"), &VoxelMesher::light);
	ClassDB::bind_method(D_METHOD("heights", "x0", "z0", "step", "n"), &VoxelMesher::heights);
}

void VoxelMesher::configure(const Array &noises, const Dictionary &spec, const PackedInt32Array &p_tiles,
		const PackedInt32Array &p_props, const PackedInt32Array &p_liquid, int p_cols, int p_rows) {
	hills = noises[0];
	detail = noises[1];
	temperature = noises[2];
	humidity = noises[3];
	mountain = noises[4];
	cave_a = noises[5];
	cave_b = noises[6];
	cave_c = noises[7];
	lake = noises[8];
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
	sea = int(prm[6]);
	water = int(prm[7]);
	caves = prm[8] > 0.5;
	cave_tw = prm[9];
	cave_tc = prm[10];
	cave_min_y = int(prm[11]);
	lake_depth = prm[12];
	lake_t = prm[13];
	copy_array(liquid, p_liquid);
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
	double h = base + double(hills->get_noise_2d(x, z)) * amp + double(detail->get_noise_2d(x, z)) * rough
			+ mount * (double(mountain->get_noise_2d(x, z)) * 0.5 + 0.5);
	if (lake_depth > 0.0) {
		const double v = double(lake->get_noise_2d(x, z));
		double t = (v - lake_t) / ((lake_t + 0.18) - lake_t);
		t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
		h -= t * t * (3.0 - 2.0 * t) * lake_depth;
	}
	return { int(std::round(h)), best };
}

void VoxelMesher::set_light_props(const PackedInt32Array &lp) { copy_array(lprops, lp); }

Array VoxelMesher::light(const Vector3i &cpos, const Array &chunks, const PackedInt32Array &skyh, int M) const {
	const int N = S + 2 * M;
	const int NN = N * N, NNN = N * N * N;
	const int ox = cpos.x * S - M, oy = cpos.y * S - M, oz = cpos.z * S - M;
	const int lp_n = int(lprops.size());
	// właściwości komórek obszaru: 0 = przepuszcza (osłabienie 1), 1 = ciecz (osłabienie 2), 2 = nieprzezroczysta
	std::vector<uint8_t> kind(NNN), emit(NNN);
	const uint8_t *cd[27];
	PackedByteArray keep[27];
	for (int i = 0; i < 27; i++) {
		cd[i] = nullptr;
		if (i < chunks.size() && chunks[i].get_type() == Variant::PACKED_BYTE_ARRAY) {
			keep[i] = chunks[i];
			if (keep[i].size() == S * S * S) cd[i] = keep[i].ptr();
		}
	}
	const int32_t *sh = skyh.ptr();
	for (int iz = 0; iz < N; iz++) {
		const int wz = oz + iz;
		const int cz = (wz >= cpos.z * S + S) ? 2 : (wz < cpos.z * S ? 0 : 1);
		const int lz = wz - (cpos.z + cz - 1) * S;
		for (int iy = 0; iy < N; iy++) {
			const int wy = oy + iy;
			const int cy = (wy >= cpos.y * S + S) ? 2 : (wy < cpos.y * S ? 0 : 1);
			const int ly = wy - (cpos.y + cy - 1) * S;
			for (int ix = 0; ix < N; ix++) {
				const int wx = ox + ix;
				const int cx = (wx >= cpos.x * S + S) ? 2 : (wx < cpos.x * S ? 0 : 1);
				const int lx = wx - (cpos.x + cx - 1) * S;
				const int ri = ix + N * (iy + N * iz);
				const uint8_t *c = cd[cx + 3 * (cy + 3 * cz)];
				if (c) {
					const uint8_t b = c[lx + S * (ly + S * lz)];
					const int v = b < lp_n ? lprops[b] : 16;
					kind[ri] = (v & 16) ? 2 : ((v & 32) ? 1 : 0);
					emit[ri] = uint8_t(v & 15);
				} else {
					kind[ri] = wy <= sh[ix + N * iz] ? 2 : 0;
					emit[ri] = 0;
				}
			}
		}
	}
	std::vector<uint8_t> sky(NNN, 0), blk(NNN, 0);
	std::vector<int32_t> q;
	q.reserve(NNN / 4);
	auto bfs = [&](std::vector<uint8_t> &L) {
		size_t head = 0;
		while (head < q.size()) {
			const int i = q[head++];
			const int v = L[i];
			const int ix = i % N, iy = (i / N) % N, iz = i / NN;
			const int nb[6] = { ix > 0 ? i - 1 : -1, ix < N - 1 ? i + 1 : -1, iy > 0 ? i - N : -1,
				iy < N - 1 ? i + N : -1, iz > 0 ? i - NN : -1, iz < N - 1 ? i + NN : -1 };
			for (int k = 0; k < 6; k++) {
				const int j = nb[k];
				if (j < 0 || kind[j] == 2) continue;
				const int nv = v - (kind[j] == 1 ? 2 : 1);
				if (nv > L[j]) {
					L[j] = uint8_t(nv);
					q.push_back(j);
				}
			}
		}
		q.clear();
	};
	// niebo: komórki ponad najwyższym nieprzezroczystym blokiem kolumny mają 15; do kolejki trafia tylko
	// „brzeg” (od najniższej oświetlonej komórki do wysokości sąsiednich kolumn), reszta i tak nic nie zmieni
	std::vector<int> lowest(NN, N);
	for (int iz = 0; iz < N; iz++)
		for (int ix = 0; ix < N; ix++) {
			const int hy = sh[ix + N * iz] - oy;
			for (int iy = N - 1; iy > hy && iy >= 0; iy--) {
				const int ri = ix + N * (iy + N * iz);
				if (kind[ri] != 0) break;
				sky[ri] = 15;
				lowest[ix + N * iz] = iy;
			}
		}
	for (int iz = 0; iz < N; iz++)
		for (int ix = 0; ix < N; ix++) {
			const int lo = lowest[ix + N * iz];
			if (lo >= N) continue;
			int top = sh[ix + N * iz] - oy;
			if (ix > 0) top = std::max(top, sh[ix - 1 + N * iz] - oy);
			if (ix < N - 1) top = std::max(top, sh[ix + 1 + N * iz] - oy);
			if (iz > 0) top = std::max(top, sh[ix + N * (iz - 1)] - oy);
			if (iz < N - 1) top = std::max(top, sh[ix + N * (iz + 1)] - oy);
			const int hi = std::min(N - 1, top + 1);
			for (int iy = lo; iy <= hi; iy++) {
				const int ri = ix + N * (iy + N * iz);
				if (sky[ri] == 15) q.push_back(ri);
			}
		}
	bfs(sky);
	for (int i = 0; i < NNN; i++)
		if (emit[i] > 0) {
			blk[i] = emit[i];  // także świecący blok nieprzezroczysty (lampa) świeci na sąsiadów
			q.push_back(i);
		}
	bfs(blk);
	PackedByteArray pl, il;
	pl.resize(P * P * P);
	il.resize(S * S * S);
	uint8_t *pp = pl.ptrw();
	uint8_t *ip = il.ptrw();
	for (int z = 0; z < P; z++)
		for (int y = 0; y < P; y++)
			for (int x = 0; x < P; x++) {
				const int ri = (x - 1 + M) + N * ((y - 1 + M) + N * (z - 1 + M));
				const uint8_t v = uint8_t((sky[ri] << 4) | blk[ri]);
				pp[idx(x, y, z)] = v;
				if (x >= 1 && x <= S && y >= 1 && y <= S && z >= 1 && z <= S) ip[(x - 1) + S * ((y - 1) + S * (z - 1))] = v;
			}
	// najwyższy nieprzezroczysty blok każdej kolumny tego chunka (do mapy wysokości nieba)
	PackedInt32Array tops;
	tops.resize(S * S);
	int32_t *tp = tops.ptrw();
	for (int z = 0; z < S; z++)
		for (int x = 0; x < S; x++) {
			int t = -100000;
			if (cd[13]) {
				for (int y = S - 1; y >= 0; y--) {
					const uint8_t b = cd[13][x + S * (y + S * z)];
					if (b < lp_n && (lprops[b] & 16)) { t = cpos.y * S + y; break; }
				}
			}
			tp[x + S * z] = t;
		}
	Array out;
	out.append(pl);
	out.append(il);
	out.append(tops);
	return out;
}

PackedInt32Array VoxelMesher::heights(int x0, int z0, int step, int n) const {
	PackedInt32Array out;
	out.resize(n * n * 2);
	int32_t *o = out.ptrw();
	for (int j = 0; j < n; j++)
		for (int i = 0; i < n; i++) {
			const Col c = nb > 0 ? column(x0 + i * step, z0 + j * step) : Col{ 0, 0 };
			o[(i + n * j) * 2] = c.h;
			o[(i + n * j) * 2 + 1] = c.biome;
		}
	return out;
}

int VoxelMesher::block_for(int wy, int h, int biome) const {
	if (wy > h) {
		if (wy <= sea) {
			const int ice = int(B[biome * BS + 19]);
			return (wy == sea && ice >= 0) ? ice : water;
		}
		return AIR;
	}
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
			const int top = (c.h > sea ? c.h : sea) - by;
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
	if (caves) carve_caves(out, bx, by, bz, cols);
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

static inline double lerpd(double a, double b, double t) { return a + (b - a) * t; }

static inline double tri(const std::vector<double> &n, int g, double tx, double ty, double tz) {
	const double c00 = lerpd(n[g], n[g + 1], tx);
	const double c10 = lerpd(n[g + CG], n[g + CG + 1], tx);
	const double c01 = lerpd(n[g + CG * CG], n[g + CG * CG + 1], tx);
	const double c11 = lerpd(n[g + CG * CG + CG], n[g + CG * CG + CG + 1], tx);
	return lerpd(lerpd(c00, c10, ty), lerpd(c01, c11, ty), tz);
}

void VoxelMesher::carve_caves(uint8_t *out, int bx, int by, int bz, const std::vector<Col> &cols) const {
	int maxh = -100000;
	for (const Col &c : cols) maxh = c.h > maxh ? c.h : maxh;
	if (by > maxh || by + P - 1 < cave_min_y) return;
	const int gx0 = int(std::floor(double(bx) / 4.0)), gy0 = int(std::floor(double(by) / 4.0)), gz0 = int(std::floor(double(bz) / 4.0));
	std::vector<double> na(CG * CG * CG), nb2(CG * CG * CG), nc(CG * CG * CG);
	for (int k = 0; k < CG; k++)
		for (int j = 0; j < CG; j++)
			for (int i = 0; i < CG; i++) {
				const double wx = double((gx0 + i) * 4);
				const double wy = double((gy0 + j) * 4) * 1.5;
				const double wz = double((gz0 + k) * 4);
				const int gi = i + CG * (j + CG * k);
				na[gi] = cave_a->get_noise_3d(wx, wy, wz);
				nb2[gi] = cave_b->get_noise_3d(wx, wy, wz);
				nc[gi] = cave_c->get_noise_3d(wx, wy, wz);
			}
	for (int z = 0; z < P; z++) {
		for (int x = 0; x < P; x++) {
			const int h = cols[x + P * z].h;
			const int top = h > sea + 3 ? h : h - 5;
			const int ymax = (P - 1) < (top - by) ? (P - 1) : (top - by);
			const int ymin = 0 > (cave_min_y - by) ? 0 : (cave_min_y - by);
			if (ymax < ymin) continue;
			const int rx = (bx + x) - gx0 * 4, rz = (bz + z) - gz0 * 4;
			const int ix = rx / 4, iz = rz / 4;
			const double tx = double(rx - ix * 4) / 4.0, tz = double(rz - iz * 4) / 4.0;
			for (int y = ymin; y <= ymax; y++) {
				const int i = idx(x, y, z);
				const uint8_t cur = out[i];
				if (cur == 0 || int(cur) == water) continue;
				const int ry = (by + y) - gy0 * 4;
				const int iy = ry / 4;
				const double ty = double(ry - iy * 4) / 4.0;
				const int g = ix + CG * (iy + CG * iz);
				const double a = tri(na, g, tx, ty, tz);
				const double b = tri(nb2, g, tx, ty, tz);
				const double c = tri(nc, g, tx, ty, tz);
				if ((std::fabs(a) < cave_tw && std::fabs(b) < cave_tw) || c > cave_tc) {
					out[i] = 0;
					if (by + y == h && y + 1 < P) out[i + P] = 0;
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

Array VoxelMesher::build(const PackedByteArray &padded, const PackedByteArray &plight) const {
	PackedVector3Array verts, norms, coll, wverts, wnorms;
	PackedVector2Array uvs, wuvs, wuv2;
	PackedColorArray cols, wcols;
	PackedInt32Array indices, windices;
	Array out;
	auto finish = [&]() {
		out.append(verts); out.append(norms); out.append(uvs); out.append(cols); out.append(indices); out.append(coll);
		out.append(wverts); out.append(wnorms); out.append(wuvs); out.append(wcols); out.append(windices);
		out.append(wuv2);
		return out;
	};
	if (padded.size() != P * P * P) return finish();

	const uint8_t *p = padded.ptr();
	const int prop_entries = int(props.size());
	auto prop = [&](uint8_t b) -> int { return b < prop_entries ? props[b] : (P_OPAQUE | P_SOLID); };
	const int tile_entries = int(tiles.size());
	auto tile_of = [&](int ti) { return ti < tile_entries ? tiles[ti] : 0; };
	const int liq_entries = int(liquid.size());
	auto lq = [&](int i) -> int { const uint8_t b = p[i]; return b < liq_entries ? liquid[b] : 0; };

	const bool has_light = plight.size() == P * P * P;
	const uint8_t *lp = has_light ? plight.ptr() : nullptr;
	auto lt = [&](int i) -> int { return has_light ? lp[i] : 0xF0; };
	int air = 0, opaque = 0;
	std::vector<uint8_t> op(P * P * P);
	for (int i = 0; i < P * P * P; i++) {
		air += (p[i] == 0);
		op[i] = (prop(p[i]) & P_OPAQUE) ? 1 : 0;
		opaque += op[i];
	}
	if (opaque == P * P * P || air == P * P * P) return finish();

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
				const int ci = idx(x, y, z);
				const uint8_t b = p[ci];
				if (b == 0) continue;
				const int bp = prop(b);
				if (bp & P_LIQUID) {
					// ---------- ciecz: osobna siatka z gładką powierzchnią ----------
					const int lv = lq(ci);
					const int kind = lv / 16;
					auto same = [&](int j) { const int w = lq(j); return w != 0 && w / 16 == kind; };
					auto hgt = [&](int w) { return double(w % 16) / 8.0 * 0.9; };
					const bool full_above = same(idx(x, y + 1, z));
					double ch[2][2];
					double foam[2][2];
					for (int cz = 0; cz < 2; cz++) {
						for (int cx = 0; cx < 2; cx++) {
							double sum = 0.0;
							int n = 0;
							bool full = full_above;
							bool solid = false;
							for (int dz = cz - 1; dz <= cz; dz++) {
								for (int dx = cx - 1; dx <= cx; dx++) {
									const int j = idx(x + dx, y, z + dz);
									if (same(j)) {
										if (same(j + P)) full = true;
										sum += hgt(lq(j));
										n++;
									} else if (!(prop(p[j]) & P_SOLID)) {
										n++;
									} else {
										solid = true;
									}
								}
							}
							ch[cx][cz] = full ? 1.0 : sum / double(n > 0 ? n : 1);
							foam[cx][cz] = solid ? 1.0 : 0.0;
						}
					}
					int d = 0;
					for (int yy = y - 1; yy >= 0 && same(idx(x, yy, z)); yy--) d++;
					const double depth = (d + 1) / 8.0 > 1.0 ? 1.0 : (d + 1) / 8.0;
					const double flow_foam = (lv % 16) < 8 ? 0.35 : 0.0;
					const float kind_a = float(kind) / 7.0f;
					if (!full_above) {
						const int corner[4][2] = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 0 } };
						const double fx = (ch[0][0] + ch[0][1]) - (ch[1][0] + ch[1][1]);
						const double fz = (ch[0][0] + ch[1][0]) - (ch[0][1] + ch[1][1]);
						const int base = wverts.size();
						for (int k = 0; k < 4; k++) {
							const int cx = corner[k][0], cz = corner[k][1];
							wverts.push_back(Vector3(float(double(x - 1 + cx)), float(double(y - 1) + ch[cx][cz]), float(double(z - 1 + cz))));
							wnorms.push_back(Vector3(0, 1, 0));
							wuvs.push_back(Vector2(float(fx), float(fz)));
							const double f = foam[cx][cz] > flow_foam ? foam[cx][cz] : flow_foam;
							wcols.push_back(Color(float(f), float(depth), 1.0f, kind_a));
							wuv2.push_back(Vector2(float(double(lt(ci) >> 4) / 15.0), float(double(lt(ci) & 15) / 15.0)));
						}
						static const int Q[6] = { 0, 2, 1, 0, 3, 2 };
						for (int i = 0; i < 6; i++) windices.push_back(base + Q[i]);
					}
					for (int f = 0; f < 6; f++) {
						if (f == 2) continue;
						const int *nn = NORMALS[f];
						const int j = idx(x + nn[0], y + nn[1], z + nn[2]);
						if (same(j) || op[j]) continue;
						double top[4];
						bool any = f == 3;
						for (int k = 0; k < 4; k++) {
							const int *c = CORNERS[f][k];
							top[k] = c[1] == 1 ? ch[c[0]][c[2]] : 0.0;
							if (top[k] > 0.0) any = true;
						}
						if (!any) continue;
						const int base = wverts.size();
						for (int k = 0; k < 4; k++) {
							const int *c = CORNERS[f][k];
							wverts.push_back(Vector3(float(double(x - 1 + c[0])), float(double(y - 1) + top[k]), float(double(z - 1 + c[2]))));
							wnorms.push_back(Vector3(float(nn[0]), float(nn[1]), float(nn[2])));
							wuvs.push_back(Vector2(0, 0));
							wcols.push_back(Color(0.0f, float(depth), c[1] == 1 && f != 3 ? 1.0f : 0.0f, kind_a));
							wuv2.push_back(Vector2(float(double(lt(ci) >> 4) / 15.0), float(double(lt(ci) & 15) / 15.0)));
						}
						static const int Q[6] = { 0, 2, 1, 0, 3, 2 };
						for (int i = 0; i < 6; i++) windices.push_back(base + Q[i]);
					}
					continue;
				}
				if (bp & P_THIN) {
					// cienki słupek (pochodnia): 2/16 szerokości, 10/16 wysokości, światło z własnej komórki
					const float sk = float(double(lt(ci) >> 4) / 15.0), bl = float(double(lt(ci) & 15) / 15.0);
					const float a = 7.0f / 16.0f, bb = 9.0f / 16.0f, h = 10.0f / 16.0f;
					for (int f = 0; f < 6; f++) {
						const int tile = tile_of(b * 6 + f);
						const int base = verts.size();
						for (int k = 0; k < 4; k++) {
							const int *cc = CORNERS[f][k];
							const float vx = cc[0] ? bb : a, vy = cc[1] ? h : 0.0f, vz = cc[2] ? bb : a;
							verts.push_back(Vector3(float(x - 1) + vx, float(y - 1) + vy, float(z - 1) + vz));
							norms.push_back(Vector3(float(NORMALS[f][0]), float(NORMALS[f][1]), float(NORMALS[f][2])));
							float u, v;
							if (f == 2 || f == 3) { u = cc[0] ? bb : a; v = (cc[2] ? 8.0f : 6.0f) / 16.0f; }
							else { u = (f == 0 || f == 1) ? (cc[2] ? bb : a) : (cc[0] ? bb : a); v = cc[1] ? 6.0f / 16.0f : 1.0f; }
							uvs.push_back(uv_of(tile, u, v));
							cols.push_back(Color(FACE_SHADE[f], sk, bl));
						}
						static const int Q[6] = { 0, 2, 1, 0, 3, 2 };
						for (int i = 0; i < 6; i++) indices.push_back(base + Q[i]);
					}
					continue;
				}
				if (bp & P_CROSS) {
					const int tile = tile_of(b * 6);
					const float sk = float(double(lt(ci) >> 4) / 15.0), bl = float(double(lt(ci) & 15) / 15.0);
					for (int pl = 0; pl < 2; pl++) {
						const int base = verts.size();
						for (int k = 0; k < 4; k++) {
							const float *c = CROSS_CORNERS[pl][k];
							verts.push_back(Vector3(float(x - 1) + c[0], float(y - 1) + c[1], float(z - 1) + c[2]));
							norms.push_back(Vector3(0, 1, 0));
							uvs.push_back(uv_of(tile, SIDE_UV[k][0], SIDE_UV[k][1]));
							cols.push_back(Color(PLANT_SHADE, sk, bl));
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
						// gładkie światło: średnia z komórek przed ścianą wokół wierzchołka (bez nieprzezroczystych)
						int lsum = 0, bsum = 0, ln = 0;
						const int cells[4] = { ni, idx(fx + d1[0], fy + d1[1], fz + d1[2]), idx(fx + d2[0], fy + d2[1], fz + d2[2]),
							idx(fx + d1[0] + d2[0], fy + d1[1] + d2[1], fz + d1[2] + d2[2]) };
						for (int m = 0; m < 4; m++) {
							if (m > 0 && op[cells[m]]) continue;
							if (m == 3 && s1 && s2) continue;
							lsum += lt(cells[m]) >> 4;
							bsum += lt(cells[m]) & 15;
							ln++;
						}
						v[k] = Vector3(float(x - 1 + c[0]), float(y - 1 + c[1]), float(z - 1 + c[2]));
						verts.push_back(v[k]);
						norms.push_back(Vector3(float(n[0]), float(n[1]), float(n[2])));
						uvs.push_back(uv_of(tile, uvset[k][0], uvset[k][1]));
						const float shade = AO_LEVELS[level] * FACE_SHADE[f];
						cols.push_back(Color(shade, float(double(lsum) / double(ln) / 15.0), float(double(bsum) / double(ln) / 15.0)));
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
