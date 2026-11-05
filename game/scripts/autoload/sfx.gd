extends Node
## Dźwięki z modów. Mod rejestruje dźwięk w content.lua (engine.sounds.register), a gra odtwarza go:
## w przestrzeni (w miejscu, ze ściszaniem z odległością) albo „w uszach” jednego gracza.
## Serwer decyduje, kto słyszy: dźwięk w miejscu trafia do graczy w zasięgu, pozostałe do jednego gracza.
## Silnik sam gra dźwięki bloków (kopanie, niszczenie, stawianie, kroki – pole `sound` bloku),
## wody (plusk, pływanie), podnoszenia przedmiotów i stworzeń (pole `sounds` stworzenia).

const POOL_3D := 24
const POOL_2D := 8

var _p3: Array[AudioStreamPlayer3D] = []
var _p2: Array[AudioStreamPlayer] = []
var _streams := {}     # nazwa -> Array[AudioStream]
var _loops := {}       # id -> odtwarzacz
var _next_id := 1
var _rng := RandomNumberGenerator.new()
var enabled := true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	enabled = DisplayServer.get_name() != "headless"
	_rng.randomize()
	for i in POOL_3D:
		var p := AudioStreamPlayer3D.new()
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		p.unit_size = 4.0
		p.finished.connect(_on_finished.bind(p))
		add_child(p)
		_p3.append(p)
	for i in POOL_2D:
		var p := AudioStreamPlayer.new()
		p.finished.connect(_on_finished.bind(p))
		add_child(p)
		_p2.append(p)


## Nowy rejestr (nowa gra): czyścimy wczytane pliki.
func reset() -> void:
	stop_all()
	_streams.clear()


func _reg() -> Registry:
	return Mods.registry


func has(name: String) -> bool:
	var r := _reg()
	return r != null and r.sounds.has(name)


func _load(name: String) -> Array:
	if _streams.has(name):
		return _streams[name]
	var out := []
	var r := _reg()
	var d: Dictionary = r.sounds.get(name, {}) if r else {}
	var files: Array = []
	if d.get("files") is Array:
		files = d.files
	elif d.has("file"):
		files = [d.file]
	for f in files:
		var mod := str(d.get("mod", ""))
		var file := str(f)
		if file.find(":") > 0 and not file.begins_with("res:") and not file.begins_with("user:"):
			mod = file.substr(0, file.find(":"))   # plik z innego moda: "base:sounds/pop.ogg"
			file = file.substr(file.find(":") + 1)
		var path := r._mod_path(mod).path_join(file)
		var s: AudioStream = null
		if FileAccess.file_exists(path):
			match path.get_extension().to_lower():
				"ogg": s = AudioStreamOggVorbis.load_from_file(path)
				"wav": s = AudioStreamWAV.load_from_file(path)
				"mp3": s = AudioStreamMP3.load_from_file(path)
		elif ResourceLoader.exists(path):
			s = load(path) as AudioStream   # mody wbudowane w wyeksportowaną grę
		if s:
			out.append(s)
		else:
			push_warning("Brak dźwięku: " + path)
	_streams[name] = out
	return out


## Odtworzenie u siebie (bez sieci). pos = null: dźwięk bez miejsca (interfejs, własne kroki).
func play_local(name: String, pos: Variant = null, volume := 1.0, pitch := 1.0, loop_id := 0) -> void:
	if not enabled or Settings.sound_volume <= 0.0:
		return
	var streams := _load(name)
	if streams.is_empty():
		return
	var d: Dictionary = _reg().sounds.get(name, {})
	var vol := volume * float(d.get("volume", 1.0)) * Settings.sound_volume
	var pr := float(d.get("pitch_random", 0.08))
	var pt := pitch * float(d.get("pitch", 1.0)) * (1.0 + _rng.randf_range(-pr, pr))
	var stream: AudioStream = streams[_rng.randi() % streams.size()]
	var player: Node = null
	if pos is Vector3:
		player = _free(_p3)
		var p3: AudioStreamPlayer3D = player
		p3.global_position = pos
		p3.max_distance = float(d.get("range", 24.0))
		p3.volume_db = linear_to_db(maxf(vol, 0.0001))
		p3.pitch_scale = clampf(pt, 0.2, 4.0)
		p3.stream = stream
		p3.play()
	else:
		player = _free(_p2)
		var p2: AudioStreamPlayer = player
		p2.volume_db = linear_to_db(maxf(vol, 0.0001))
		p2.pitch_scale = clampf(pt, 0.2, 4.0)
		p2.stream = stream
		p2.play()
	if loop_id > 0:
		player.set_meta("loop", loop_id)
		_loops[loop_id] = player
	elif player.has_meta("loop"):
		player.remove_meta("loop")


func _free(pool: Array) -> Node:
	for p in pool:
		if not p.playing and not p.has_meta("loop"):
			return p
	# wszystkie zajęte: zabieramy najstarszy niezapętlony
	for p in pool:
		if not p.has_meta("loop"):
			p.stop()
			return p
	return pool[0]


func _on_finished(p: Node) -> void:
	if p.has_meta("loop") and _loops.get(p.get_meta("loop")) == p:
		p.play()


func stop_local(id: int) -> void:
	var p: Node = _loops.get(id)
	_loops.erase(id)
	if p and is_instance_valid(p):
		p.remove_meta("loop")
		p.stop()


func stop_all() -> void:
	for id in _loops.keys():
		stop_local(id)


# ---------- serwer: kto słyszy ----------

## Dźwięk w grze: w miejscu (pos: Vector3) słyszą gracze w zasięgu; bez miejsca – tylko gracz `peer`
## (0 = gracz, w którego imieniu działa kod). Zwraca id zapętlonego dźwięku (do stop) albo 0.
func emit(name: String, pos: Variant = null, volume := 1.0, pitch := 1.0, loop := false, peer := -1) -> int:
	if not has(name):
		return 0
	var id := 0
	if loop:
		id = _next_id
		_next_id += 1
	var main: Node = Net.main
	if main == null or not Net.online():
		play_local(name, pos, volume, pitch, id)
		return id
	var target := peer
	if pos == null and target < 0:
		var s: Session = Mods.S()
		target = s.peer if s else Net.my_id()
	var reach := float(_reg().sounds[name].get("range", 24.0)) + 8.0
	for p in Mods.sessions:
		var sess: Session = Mods.sessions[p]
		if not sess.logged_in or (target >= 0 and p != target):
			continue
		if pos is Vector3 and sess.node and sess.node.global_position.distance_to(pos) > reach:
			continue
		if sess.local:
			if Net.mode != "dedicated":
				play_local(name, pos, volume, pitch, id)
		else:
			Net.s_sound.rpc_id(p, name, pos if pos is Vector3 else Vector3.ZERO, pos is Vector3, volume, pitch, id)
	return id


func stop(id: int) -> void:
	stop_local(id)
	if Net.online() and Net.is_server():
		Net.s_sound_stop.rpc(id)


# ---------- dźwięki bloków ----------

## Grupa dźwięków bloku: pole `sound` (np. "stone", "wood"); domyślnie rośliny "leaves", reszta "stone".
func block_group(block: int) -> String:
	var r := _reg()
	if r == null or block <= 0:
		return ""
	var d := r.def_of(r.base_of(block))
	if d.has("sound"):
		return str(d.sound)
	if r.is_liquid(block):
		return "water"
	return "leaves" if (r.props[block] & (Registry.CROSS)) != 0 else "stone"


func _block_name(block: int, event: String) -> String:
	var g := block_group(block)
	if g == "":
		return ""
	if has(g + "." + event):
		return g + "." + event
	if event != "step" and has(g + ".break"):
		return g + ".break"
	return ""


## Serwer: dźwięk bloku słyszany przez graczy w pobliżu (niszczenie, stawianie).
func block(block_id: int, event: String, pos: Vector3i) -> void:
	var n := _block_name(block_id, event)
	if n != "":
		emit(n, Vector3(pos) + Vector3(0.5, 0.5, 0.5), 0.8 if event == "place" else 1.0, 0.9 if event == "place" else 1.0)


## U siebie: kroki i uderzenia przy kopaniu (każdy klient gra je sam dla graczy, których widzi).
func block_local(block_id: int, event: String, pos: Vector3) -> void:
	var n := _block_name(block_id, event)
	if n != "":
		play_local(n, pos)
