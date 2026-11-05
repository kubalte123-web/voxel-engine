class_name BlockModels
extends Node3D
## Modele bloków (pole `model` w definicji bloku) w wczytanych chunkach. Działa u każdego gracza:
## modele powstają z danych chunka, więc klient nie potrzebuje do tego nic od serwera poza blokami.
## Wygląd ustawiany przez mody (engine.blocks.look) przychodzi z serwera i jest tu trzymany per pozycja.

var world: World
var is_model := PackedByteArray()
var any := false
var by_chunk := {}   # chunk -> {pozycja: BlockModel}
var looks := {}      # pozycja -> Dictionary (wygląd od modów)


func setup(w: World) -> void:
	world = w
	is_model.resize(256)
	for id in w.reg.count():
		if (w.reg.props[id] & Registry.MODEL) != 0:
			is_model[id] = 1
			any = true


## Po zbudowaniu chunka: modele dla wszystkich bloków z modelem (nowe tworzymy, zbędne usuwamy).
func sync_chunk(c: Vector3i) -> void:
	if not any or not world.data.has(c):
		return
	var d: PackedByteArray = world.data[c]
	var want := {}
	for id in 256:
		if not is_model[id]:
			continue
		var i := d.find(id)
		while i >= 0:
			want[c * World.S + Vector3i(i % World.S, (i / World.S) % World.S, i / (World.S * World.S))] = id
			i = d.find(id, i + 1)
	var have: Dictionary = by_chunk.get(c, {})
	for p in have.keys():
		if not want.has(p):
			have[p].queue_free()
			have.erase(p)
	for p in want:
		if have.has(p):
			if have[p].block != want[p]:
				have[p].set_block(want[p])
		else:
			have[p] = _create(p, want[p])
	if have.is_empty():
		by_chunk.erase(c)
	else:
		by_chunk[c] = have


func chunk_unloaded(c: Vector3i) -> void:
	for m in by_chunk.get(c, {}).values():
		m.queue_free()
	by_chunk.erase(c)


## Zmiana jednego bloku (od razu, bez czekania na przebudowę chunka).
func block_changed(p: Vector3i, old: int, id: int) -> void:
	if not any or (not is_model[old] and not is_model[id]):
		return
	var c := World.chunk_of(p)
	if not world.built.has(c):
		return
	var have: Dictionary = by_chunk.get(c, {})
	var m: BlockModel = have.get(p)
	if m and is_model[id] and world.reg.base_of(id) == world.reg.base_of(m.block):
		m.set_block(id)
		return
	if m:
		m.queue_free()
		have.erase(p)
	if is_model[id]:
		have[p] = _create(p, id)
	else:
		looks.erase(p)
	by_chunk[c] = have


func _create(p: Vector3i, id: int) -> BlockModel:
	var m := BlockModel.new()
	m.setup(world, p, id)
	if looks.has(p):
		m.dynamic_look = looks[p]
	add_child(m)
	return m


func model_at(p: Vector3i) -> BlockModel:
	return by_chunk.get(World.chunk_of(p), {}).get(p)


func set_look(p: Vector3i, look: Dictionary) -> void:
	if look.is_empty():
		looks.erase(p)
	else:
		looks[p] = look
	var m := model_at(p)
	if m:
		m.set_dynamic_look(look)


func play(p: Vector3i, name: String) -> void:
	var m := model_at(p)
	if m:
		m.play(name)
