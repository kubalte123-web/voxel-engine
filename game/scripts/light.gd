class_name LightCalc
## Rozchodzenie się światła (wersja GDScript, ta sama co VoxelMesher.light w C++).
## Obszar = chunk z marginesem M bloków z każdej strony. Światło nieba: komórki ponad najwyższym
## nieprzezroczystym blokiem kolumny mają 15, a dalej światło rozchodzi się na boki i w dół, słabnąc o 1
## na blok (w cieczy o 2). Światło bloków (pochodnie, lampy) rozchodzi się tak samo od źródeł.
## Bajt wyniku: niebo << 4 | bloki.

const S := 32
const P := S + 2


## chunks: 27 tablic S^3 (albo null) w kolejności (dx+1) + 3*((dy+1) + 3*(dz+1)); skyh: N*N wysokości.
static func compute(cpos: Vector3i, chunks: Array, skyh: PackedInt32Array, M: int, lprops: PackedInt32Array) -> Array:
	var N := S + 2 * M
	var NN := N * N
	var NNN := NN * N
	var ox := cpos.x * S - M
	var oy := cpos.y * S - M
	var oz := cpos.z * S - M
	var kind := PackedByteArray()
	kind.resize(NNN)
	var emit := PackedByteArray()
	emit.resize(NNN)
	var lp_n := lprops.size()
	for iz in N:
		var wz := oz + iz
		var cz := 2 if wz >= cpos.z * S + S else (0 if wz < cpos.z * S else 1)
		var lz := wz - (cpos.z + cz - 1) * S
		for iy in N:
			var wy := oy + iy
			var cy := 2 if wy >= cpos.y * S + S else (0 if wy < cpos.y * S else 1)
			var ly := wy - (cpos.y + cy - 1) * S
			for ix in N:
				var wx := ox + ix
				var cx := 2 if wx >= cpos.x * S + S else (0 if wx < cpos.x * S else 1)
				var lx := wx - (cpos.x + cx - 1) * S
				var ri := ix + N * (iy + N * iz)
				var c: Variant = chunks[cx + 3 * (cy + 3 * cz)]
				if c != null:
					var b: int = c[lx + S * (ly + S * lz)]
					var v := lprops[b] if b < lp_n else 16
					kind[ri] = 2 if (v & 16) != 0 else (1 if (v & 32) != 0 else 0)
					emit[ri] = v & 15
				else:
					kind[ri] = 2 if wy <= skyh[ix + N * iz] else 0
	var sky := PackedByteArray()
	sky.resize(NNN)
	var blk := PackedByteArray()
	blk.resize(NNN)
	var q := PackedInt32Array()
	var lowest := PackedInt32Array()
	lowest.resize(NN)
	lowest.fill(N)
	for iz in N:
		for ix in N:
			var hy := skyh[ix + N * iz] - oy
			var iy := N - 1
			while iy > hy and iy >= 0:
				var ri := ix + N * (iy + N * iz)
				if kind[ri] != 0:
					break
				sky[ri] = 15
				lowest[ix + N * iz] = iy
				iy -= 1
	for iz in N:
		for ix in N:
			var lo := lowest[ix + N * iz]
			if lo >= N:
				continue
			var top := skyh[ix + N * iz] - oy
			if ix > 0: top = maxi(top, skyh[ix - 1 + N * iz] - oy)
			if ix < N - 1: top = maxi(top, skyh[ix + 1 + N * iz] - oy)
			if iz > 0: top = maxi(top, skyh[ix + N * (iz - 1)] - oy)
			if iz < N - 1: top = maxi(top, skyh[ix + N * (iz + 1)] - oy)
			for iy in range(lo, mini(N - 1, top + 1) + 1):
				var ri := ix + N * (iy + N * iz)
				if sky[ri] == 15:
					q.append(ri)
	_bfs(sky, q, kind, N)
	q = PackedInt32Array()
	for i in NNN:
		if emit[i] > 0:
			blk[i] = emit[i]
			q.append(i)
	_bfs(blk, q, kind, N)
	var pl := PackedByteArray()
	pl.resize(P * P * P)
	var il := PackedByteArray()
	il.resize(S * S * S)
	for z in P:
		for y in P:
			var rbase := N * ((y - 1 + M) + N * (z - 1 + M)) + (M - 1)
			var pbase := P * (y + P * z)
			for x in P:
				var ri := rbase + x
				var v := (sky[ri] << 4) | blk[ri]
				pl[pbase + x] = v
				if x >= 1 and x <= S and y >= 1 and y <= S and z >= 1 and z <= S:
					il[(x - 1) + S * ((y - 1) + S * (z - 1))] = v
	var tops := PackedInt32Array()
	tops.resize(S * S)
	var own: Variant = chunks[13]
	for z in S:
		for x in S:
			var t := -100000
			if own != null:
				for y in range(S - 1, -1, -1):
					var b: int = own[x + S * (y + S * z)]
					if b < lp_n and (lprops[b] & 16) != 0:
						t = cpos.y * S + y
						break
			tops[x + S * z] = t
	return [pl, il, tops]


static func _bfs(L: PackedByteArray, q: PackedInt32Array, kind: PackedByteArray, N: int) -> void:
	var NN := N * N
	var head := 0
	while head < q.size():
		var i := q[head]
		head += 1
		var v := L[i]
		var ix := i % N
		var iy := (i / N) % N
		var iz := i / NN
		for k in 6:
			var j := -1
			match k:
				0: j = i - 1 if ix > 0 else -1
				1: j = i + 1 if ix < N - 1 else -1
				2: j = i - N if iy > 0 else -1
				3: j = i + N if iy < N - 1 else -1
				4: j = i - NN if iz > 0 else -1
				5: j = i + NN if iz < N - 1 else -1
			if j < 0 or kind[j] == 2:
				continue
			var nv := v - (2 if kind[j] == 1 else 1)
			if nv > L[j]:
				L[j] = nv
				q.append(j)
