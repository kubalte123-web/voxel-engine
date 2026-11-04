#include "voxel_mesher.h"

#include <godot_cpp/core/class_db.hpp>
#include <cmath>
#include <cstring>
#include <godot_cpp/variant/packed_color_array.hpp>
#include <godot_cpp/variant/packed_vector2_array.hpp>
#include <godot_cpp/variant/packed_vector3_array.hpp>

using namespace godot;

namespace {
constexpr int S = 32;
constexpr int P = S + 2;

const int NORMALS[6][3] = { { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, -1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } };
const int CORNERS[6][4][3] = {
	{ { 1, 0, 0 }, { 1, 1, 0 }, { 1, 1, 1 }, { 1, 0, 1 } },
	{ { 0, 0, 1 }, { 0, 1, 1 }, { 0, 1, 0 }, { 0, 0, 0 } },
	{ { 0, 1, 0 }, { 0, 1, 1 }, { 1, 1, 1 }, { 1, 1, 0 } },
	{ { 0, 0, 0 }, { 1, 0, 0 }, { 1, 0, 1 }, { 0, 0, 1 } },
	{ { 1, 0, 1 }, { 1, 1, 1 }, { 0, 1, 1 }, { 0, 0, 1 } },
	{ { 0, 0, 0 }, { 0, 1, 0 }, { 1, 1, 0 }, { 1, 0, 0 } },
};
const float SIDE_UV[4][2] = { { 0, 1 }, { 0, 0 }, { 1, 0 }, { 1, 1 } };
const float TOP_UV[4][2] = { { 0, 0 }, { 0, 1 }, { 1, 1 }, { 1, 0 } };
const float BOTTOM_UV[4][2] = { { 0, 0 }, { 1, 0 }, { 1, 1 }, { 0, 1 } };
const float AO_LEVELS[4] = { 0.42f, 0.62f, 0.8f, 1.0f };
const float FACE_SHADE[6] = { 0.86f, 0.86f, 1.0f, 0.62f, 0.92f, 0.92f };

inline int idx(int x, int y, int z) { return x + P * (y + P * z); }
inline float clampf(float v, float a, float b) { return v < a ? a : (v > b ? b : v); }
} // namespace

void VoxelMesher::_bind_methods() {
	ClassDB::bind_method(D_METHOD("prepare", "cpos", "hills", "detail", "own", "neighbors"), &VoxelMesher::prepare);
	ClassDB::bind_method(D_METHOD("build", "padded", "tiles", "tile_count"), &VoxelMesher::build);
}

Array VoxelMesher::build(const PackedByteArray &padded, const PackedInt32Array &tiles, int tile_count) const {
	PackedVector3Array verts, norms, coll;
	PackedVector2Array uvs;
	PackedColorArray cols;
	PackedInt32Array indices;
	Array out;

	if (padded.size() != P * P * P || tile_count <= 0) {
		out.append(verts); out.append(norms); out.append(uvs); out.append(cols); out.append(indices); out.append(coll);
		return out;
	}
	const uint8_t *p = padded.ptr();
	const int32_t *t = tiles.ptr();
	const int tile_entries = tiles.size();

	int air = 0;
	for (int i = 0; i < P * P * P; i++) air += (p[i] == 0);
	if (air == 0 || air == P * P * P) {
		out.append(verts); out.append(norms); out.append(uvs); out.append(cols); out.append(indices); out.append(coll);
		return out;
	}

	const float inv = 1.0f / float(tile_count);
	const float eps = 0.002f;
	auto solid = [&](int x, int y, int z) -> int { return p[idx(x, y, z)] != 0 ? 1 : 0; };

	for (int z = 1; z <= S; z++) {
		for (int y = 1; y <= S; y++) {
			for (int x = 1; x <= S; x++) {
				const uint8_t b = p[idx(x, y, z)];
				if (b == 0) continue;
				for (int f = 0; f < 6; f++) {
					const int *n = NORMALS[f];
					const int fx = x + n[0], fy = y + n[1], fz = z + n[2];
					if (p[idx(fx, fy, fz)] != 0) continue;
					const int ti = b * 6 + f;
					const int tile = ti < tile_entries ? t[ti] : 0;
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
						const int s1 = solid(fx + d1[0], fy + d1[1], fz + d1[2]);
						const int s2 = solid(fx + d2[0], fy + d2[1], fz + d2[2]);
						const int cc = solid(fx + d1[0] + d2[0], fy + d1[1] + d2[1], fz + d1[2] + d2[2]);
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
					int q[6];
					if (ao[0] + ao[2] >= ao[1] + ao[3]) {
						const int a[6] = { 0, 2, 1, 0, 3, 2 };
						for (int i = 0; i < 6; i++) q[i] = a[i];
					} else {
						const int a[6] = { 1, 3, 2, 1, 0, 3 };
						for (int i = 0; i < 6; i++) q[i] = a[i];
					}
					for (int i = 0; i < 6; i++) {
						indices.push_back(base + q[i]);
						coll.push_back(v[q[i]]);
					}
				}
			}
		}
	}
	out.append(verts); out.append(norms); out.append(uvs); out.append(cols); out.append(indices); out.append(coll);
	return out;
}

namespace {
// Musi zgadzać się z Terrain.block_for w GDScript.
inline uint8_t block_for(int wy, int h) {
	if (wy > h) return 0;
	const bool sandy = h <= 7;
	if (wy == h) return sandy ? 5 : 1;
	if (wy > h - 4) return sandy ? 5 : 2;
	return 3;
}
} // namespace

Array VoxelMesher::prepare(const Vector3i &cpos, const Ref<FastNoiseLite> &hills, const Ref<FastNoiseLite> &detail,
		const PackedByteArray &own, const Array &neighbors) const {
	PackedByteArray padded;
	padded.resize(P * P * P);
	uint8_t *p = padded.ptrw();
	memset(p, 0, P * P * P);
	const int bx = cpos.x * S - 1, by = cpos.y * S - 1, bz = cpos.z * S - 1;
	for (int z = 0; z < P; z++) {
		for (int x = 0; x < P; x++) {
			const double n = 12.0 + hills->get_noise_2d(bx + x, bz + z) * 9.0 + detail->get_noise_2d(bx + x, bz + z) * 1.5;
			const int h = int(std::round(n));
			const int top = h - by;
			if (top < 0) continue;
			const int ymax = top + 1 < P ? top + 1 : P;
			for (int y = 0; y < ymax; y++) p[idx(x, y, z)] = block_for(by + y, h);
		}
	}
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
