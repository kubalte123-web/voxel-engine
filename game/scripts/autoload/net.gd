extends Node
## Gra wieloosobowa (do 8 graczy) na ENet. Serwer (gracz-host albo serwer bez okna) jest autorytatywny:
## uruchamia skrypty modów, symulację wody, stworzenia i zapis świata. Klienci generują teren sami
## z tego samego ziarna i modów (więc przesyłane są tylko zmienione chunki), wczytują z modów tylko treść
## (bloki, przedmioty, modele), a stan gry dostają od serwera: zmiany bloków, graczy, stworzenia,
## ekwipunek, okna, paski i powiadomienia. Akcje gracza (kopanie, stawianie, użycie, klawisze, kliknięcia
## w oknach) klient wysyła do serwera, który wykonuje je w imieniu tego gracza (Mods.ctx).
## Dołączyć można tylko z tymi samymi modami: serwer porównuje listę modów i wersje, a klient sprawdza
## skrót rejestru treści (te same bloki, przedmioty i świat).

signal status(text: String)
signal mods_offer(mods: Array)    # klient: serwer ma mody, których brakuje (menu pyta gracza)
signal mods_progress(done: int, total: int)

const PROTOCOL := 2
const CHUNK := 48 * 1024           # kawałek paczki modu w jednym pakiecie
const CHUNKS_PER_FRAME := 3
const DEFAULT_PORT := 7777
const MAX_PLAYERS := 8
const STATE_DT := 1.0 / 15.0
const ENTITY_DT := 0.1

var mode := "single"     # single | host | client | dedicated
var peer: ENetMultiplayerPeer = null
var main: Node = null
var welcome := {}        # klient: dane świata od serwera
var last_error := ""
var remote_chunks := {}  # klient: zmienione chunki od serwera (Vector3i -> PackedByteArray)
var block_queue := PackedInt32Array()  # serwer: zmiany bloków do rozesłania (x, y, z, id)
var full_chunks := {}    # serwer: chunki zmienione po raz pierwszy (wysyłamy całe)
var sent_chunks := {}    # serwer: chunki, które klienci już mają
var _state_t := 0.0
var _ent_t := 0.0
var dig_times := {}      # klient: czas kopania od serwera (pozycja -> sekundy)
# pobieranie modów z serwera
var auto_accept_mods := false      # testy: zgoda bez pytania (--accept-mods)
var offer := []                    # klient: mody do pobrania [{id, name, version, author, fp, size}]
var _offered_all := []             # klient: wszystkie mody z oferty (także te już w pamięci podręcznej)
var _offer_round := 0
var _dl := {}                      # klient: id -> PackedByteArray (odbierane)
var _dl_done := 0
var _dl_total := 0
var _packs := {}                   # serwer: id -> paczka (liczona raz)
var _offers := {}                  # serwer: peer -> {id: fp} zaproponowane mody
var _uploads := {}                 # serwer: peer -> [[id, paczka, przesunięcie]]


func is_server() -> bool:
	return mode != "client"


func is_client() -> bool:
	return mode == "client"


func online() -> bool:
	return mode != "single"


func my_id() -> int:
	return multiplayer.get_unique_id() if peer != null else 1


# ---------- łączenie ----------

func host(port: int, dedicated: bool = false) -> String:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_server(port, MAX_PLAYERS)
	if err != OK:
		peer = null
		return "Nie udało się otworzyć portu %d (błąd %d)." % [port, err]
	multiplayer.multiplayer_peer = peer
	mode = "dedicated" if dedicated else "host"
	if not multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.connect(_on_peer_connected)
		multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return ""


func join(address: String, port: int) -> String:
	leave()
	peer = ENetMultiplayerPeer.new()
	var err := peer.create_client(address, port)
	if err != OK:
		peer = null
		return "Nie udało się połączyć (błąd %d)." % err
	multiplayer.multiplayer_peer = peer
	mode = "client"
	if not multiplayer.connected_to_server.is_connected(_on_connected):
		multiplayer.connected_to_server.connect(_on_connected)
		multiplayer.connection_failed.connect(_on_failed)
		multiplayer.server_disconnected.connect(_on_server_gone)
	status.emit("Łączenie z %s:%d..." % [address, port])
	return ""


func leave() -> void:
	if peer != null:
		peer.close()
	multiplayer.multiplayer_peer = null
	peer = null
	mode = "single"
	welcome = {}
	remote_chunks.clear()
	block_queue = PackedInt32Array()
	full_chunks.clear()
	sent_chunks.clear()
	dig_times.clear()
	offer = []
	_offered_all = []
	_offer_round = 0
	_dl.clear()
	_offers.clear()
	_uploads.clear()
	ModManager.clear_server_mods()


func kick(p: int, reason: String) -> void:
	if not is_server() or p == 1:
		return
	s_kicked.rpc_id(p, reason)
	await get_tree().create_timer(0.3).timeout
	if peer:
		peer.disconnect_peer(p)


## Lista modów i wersji (do porównania przy dołączaniu).
static func mods_signature() -> Dictionary:
	var out := {}
	for id in ModManager.effective_order():
		if ModManager.is_enabled(id):
			out[id] = str(ModManager.manifests[id].get("version", ""))
	return out


func _on_connected() -> void:
	status.emit("Połączono, sprawdzanie modów...")
	_hello()


func _hello() -> void:
	c_hello.rpc_id(1, Settings.player_name, PROTOCOL, ModManager.fingerprints())


func _on_failed() -> void:
	last_error = "Nie udało się połączyć z serwerem."
	status.emit(last_error)
	leave()


func _on_server_gone() -> void:
	if last_error.is_empty():
		last_error = "Serwer zakończył połączenie."
	leave()
	Mods.stop()
	GameState.back_to_menu()


func _on_peer_connected(_p: int) -> void:
	pass


func _on_peer_disconnected(p: int) -> void:
	_uploads.erase(p)
	_offers.erase(p)
	if main:
		main.remove_remote_player(p)


# ---------- uzgadnianie (klient -> serwer -> klient) ----------

@rpc("any_peer", "reliable")
func c_hello(name: String, proto: int, available: Variant) -> void:
	var p := multiplayer.get_remote_sender_id()
	if main == null:
		s_reject.rpc_id(p, "Serwer jeszcze nie wczytał świata.")
		return
	if proto != PROTOCOL or not available is Dictionary:
		s_reject.rpc_id(p, "Inna wersja gry (protokół %d, serwer %d). Zaktualizuj grę." % [proto, PROTOCOL])
		return
	# mody, których klient nie ma albo ma w innej wersji (inny odcisk): proponujemy pobranie
	var need := []
	var fps := {}
	for id in mods_signature():
		var m: Dictionary = ModManager.manifests[id]
		var fp := ModPack.fingerprint(m.path)
		if str(available.get(id, "")) == fp:
			continue
		if not _packs.has(id):
			_packs[id] = ModPack.pack(m.path)
		fps[id] = fp
		need.append({"id": id, "name": str(m.get("name", id)), "version": str(m.get("version", "")),
			"author": str(m.get("author", "")), "fp": fp, "size": (_packs[id] as PackedByteArray).size(),
			"update": available.has(id)})
	if not need.is_empty():
		print("MODY oferta dla %d: %s" % [p, fps.keys()])
		_offers[p] = fps
		s_offer_mods.rpc_id(p, need)
		return
	main.pending_names[p] = name.strip_edges().left(24) if not name.strip_edges().is_empty() else "Gracz"
	s_welcome.rpc_id(p, main.world_info_for_client())


# ---------- pobieranie modów z serwera ----------

## Klient: serwer proponuje mody. Te, które już kiedyś pobraliśmy (ten sam odcisk), bierzemy z pamięci
## podręcznej; o resztę pytamy gracza (menu), a po zgodzie pobieramy je od serwera.
@rpc("authority", "reliable")
func s_offer_mods(mods: Array) -> void:
	_offer_round += 1
	if _offer_round > 2:
		last_error = "Nie udało się dopasować modów do serwera (pobrane mody różnią się od serwerowych)."
		status.emit(last_error)
		leave()
		return
	_offered_all = mods
	offer = []
	for m in mods:
		if not ModPack.is_cached(str(m.id), str(m.fp)):
			offer.append(m)
	if offer.is_empty():
		_use_offered()
		return
	if auto_accept_mods:
		accept_mods()
	else:
		mods_offer.emit(offer)


func accept_mods() -> void:
	if offer.is_empty() or not is_client():
		return
	_dl.clear()
	_dl_done = 0
	_dl_total = 0
	var ids := []
	for m in offer:
		ids.append(m.id)
		_dl_total += int(m.size)
	status.emit("Pobieranie modów...")
	print("MODY pobieranie: ", ids, " ", _kb(_dl_total))
	c_get_mods.rpc_id(1, ids)


func decline_mods() -> void:
	last_error = "Nie dołączono: bez modów serwera nie można grać na tym serwerze."
	leave()
	status.emit(last_error)


func _use_offered() -> void:
	var dirs := {}
	for m in _offered_all:
		dirs[str(m.id)] = ModPack.cache_dir(str(m.id), str(m.fp))
	ModManager.use_server_mods(dirs)
	print("MODY z serwera gotowe: ", dirs.keys(), " (pobrane teraz: ", offer.size(), ")")
	status.emit("Mody gotowe, dołączanie...")
	_hello()


@rpc("any_peer", "reliable")
func c_get_mods(ids: Array) -> void:
	var p := multiplayer.get_remote_sender_id()
	var allowed: Dictionary = _offers.get(p, {})
	var queue := []
	for id in ids:
		if allowed.has(str(id)) and _packs.has(str(id)):
			queue.append([str(id), _packs[str(id)], 0])
	_uploads[p] = queue
	print("MODY wysyłanie do %d: %s" % [p, ids])


## Serwer: wysyłanie paczek kawałkami (kilka na klatkę, żeby gra działała płynnie).
func _send_uploads() -> void:
	for p in _uploads.keys():
		var queue: Array = _uploads[p]
		var n := CHUNKS_PER_FRAME
		while n > 0 and not queue.is_empty():
			var job: Array = queue[0]
			var data: PackedByteArray = job[1]
			var off: int = job[2]
			var end := mini(off + CHUNK, data.size())
			s_mod_chunk.rpc_id(p, job[0], off, data.size(), data.slice(off, end))
			job[2] = end
			if end >= data.size():
				queue.pop_front()
			n -= 1
		if queue.is_empty():
			_uploads.erase(p)


@rpc("authority", "reliable")
func s_mod_chunk(id: String, offset: int, total: int, bytes: PackedByteArray) -> void:
	var m: Dictionary = {}
	for o in offer:
		if str(o.id) == id:
			m = o
	if m.is_empty() or total != int(m.size) or total > ModPack.MAX_TOTAL:
		return
	var buf: PackedByteArray = _dl.get(id, PackedByteArray())
	if offset != buf.size():
		return
	buf.append_array(bytes)
	_dl[id] = buf
	_dl_done += bytes.size()
	mods_progress.emit(_dl_done, _dl_total)
	status.emit("Pobieranie modów: %d%% (%s z %s)" % [100 * _dl_done / maxi(1, _dl_total), _kb(_dl_done), _kb(_dl_total)])
	if buf.size() < total:
		return
	var err := ModPack.unpack(id, str(m.fp), buf)
	_dl.erase(id)
	if err != "":
		last_error = "Nie udało się zapisać modu „%s”: %s" % [m.name, err]
		status.emit(last_error)
		leave()
		return
	for o in offer:
		if not ModPack.is_cached(str(o.id), str(o.fp)):
			return
	_use_offered()


static func _kb(n: int) -> String:
	return "%.1f MB" % (n / 1048576.0) if n >= 1048576 else "%d KB" % maxi(1, n / 1024)


# ---------- modele bloków i cząsteczki ----------

@rpc("authority", "reliable")
func s_block_look(p: Vector3i, look: Dictionary) -> void:
	if main:
		main.world.models.set_look(p, look)


@rpc("authority", "reliable")
func s_block_anim(p: Vector3i, name: String) -> void:
	if main:
		main.world.models.play(p, name)


@rpc("authority", "unreliable")
func s_particles(name: String, pos: Vector3, opts: Dictionary) -> void:
	Fx.burst_local(name, pos, opts)


# ---------- dźwięki ----------

@rpc("authority", "unreliable")
func s_sound(name: String, pos: Vector3, has_pos: bool, volume: float, pitch: float, loop_id: int) -> void:
	Sfx.play_local(name, pos if has_pos else null, volume, pitch, loop_id)


@rpc("authority", "reliable")
func s_sound_stop(id: int) -> void:
	Sfx.stop_local(id)


@rpc("authority", "reliable")
func s_reject(reason: String) -> void:
	last_error = reason
	status.emit(reason)
	leave()


@rpc("authority", "reliable")
func s_kicked(reason: String) -> void:
	last_error = "Wyrzucono z serwera: " + reason if not reason.is_empty() else "Wyrzucono z serwera."


@rpc("authority", "reliable")
func s_welcome(info: Dictionary) -> void:
	welcome = info
	# wymuszona kolejność, włączenie i ustawienia modów z serwera
	ModManager.apply_server_profile(info.get("profile", {}))
	var mine := mods_signature()
	var diff := []
	var theirs: Dictionary = info.get("versions", {})
	for id in theirs:
		if str(mine.get(id, "")) != str(theirs[id]):
			diff.append("%s (serwer %s, ty %s)" % [ModManager.manifests.get(id, {}).get("name", id), theirs[id], mine.get(id, "brak")])
	if not diff.is_empty():
		last_error = "Inne wersje modów: " + ", ".join(diff)
		status.emit(last_error)
		leave()
		ModManager.apply_server_profile({})
		return
	GameState.current = {"name": info.get("name", "Serwer"), "seed": info.seed, "mods": info.get("mods", {}),
		"palette": info.get("palette", []), "version": 3, "time_of_day": info.get("time", 10.0)}
	GameState.current_dir = ""
	for k in info.get("chunks", {}):
		remote_chunks[k] = (info.chunks[k] as PackedByteArray).decompress(32768, FileAccess.COMPRESSION_ZSTD)
	status.emit("Wczytywanie świata...")
	get_tree().change_scene_to_file("res://main.tscn")


## Klient: świat zbudowany; sprawdza zgodność treści i zgłasza gotowość.
func client_ready(content_hash: String) -> bool:
	if content_hash != str(welcome.get("content_hash", "")):
		last_error = "Mody różnią się od serwera (inne bloki, przedmioty albo świat). Zaktualizuj mody."
		leave()
		return false
	c_ready.rpc_id(1)
	return true


@rpc("any_peer", "reliable")
func c_ready() -> void:
	var p := multiplayer.get_remote_sender_id()
	if main:
		main.add_remote_player(p, str(main.pending_names.get(p, "Gracz")))


@rpc("authority", "reliable")
func s_accepted(account: String, pos: Vector3, health: float) -> void:
	if main:
		main.on_accepted(account, pos, health)


# ---------- świat ----------

## Serwer: zmiana bloku (wywoływane przez World przy każdej zmianie na serwerze).
func block_changed(p: Vector3i, id: int, chunk: Vector3i, first_edit: bool) -> void:
	if not online() or not is_server() or main == null or main.remote_count() == 0:
		return
	if first_edit and not sent_chunks.has(chunk):
		full_chunks[chunk] = true
		return
	if full_chunks.has(chunk):
		return
	block_queue.append_array([p.x, p.y, p.z, id])


@rpc("authority", "reliable")
func s_blocks(changes: PackedInt32Array) -> void:
	if main:
		for i in range(0, changes.size(), 4):
			main.world.apply_remote(Vector3i(changes[i], changes[i + 1], changes[i + 2]), changes[i + 3])
		main.world.flush_pending()


@rpc("authority", "reliable")
func s_chunk(c: Vector3i, raw: PackedByteArray) -> void:
	var d := raw.decompress(32768, FileAccess.COMPRESSION_ZSTD)
	remote_chunks[c] = d
	if main:
		main.world.apply_remote_chunk(c, d)


# ---------- gracze ----------

## Klient: własny stan (pozycja, kamera, cel) do serwera, 15 razy na sekundę.
@rpc("any_peer", "unreliable_ordered")
func c_move(st: Dictionary) -> void:
	if main:
		main.remote_move(multiplayer.get_remote_sender_id(), st)


@rpc("authority", "unreliable_ordered")
func s_players(list: Array, time: float) -> void:
	if main:
		main.players_state(list, time)


@rpc("any_peer", "reliable")
func c_action(kind: String, args: Dictionary) -> void:
	if main:
		main.remote_action(multiplayer.get_remote_sender_id(), kind, args)


@rpc("authority", "reliable")
func s_session(part: String, value: Variant) -> void:
	if main:
		main.session_update(part, value)


@rpc("authority", "reliable")
func s_teleport(pos: Vector3) -> void:
	if main and main.player:
		main.player.global_position = pos
		main.player.velocity = Vector3.ZERO
		main.player.reset_fall()


@rpc("authority", "reliable")
func s_health(v: float) -> void:
	if main and main.player:
		main.player.set_health(v)


@rpc("authority", "reliable")
func s_died(cause: String) -> void:
	if main and main.player:
		main.player.died.emit(cause)


@rpc("authority", "reliable")
func s_dig_time(pos: Vector3i, t: float) -> void:
	dig_times[pos] = t


func broadcast_anim(p: int, name: String) -> void:
	if online() and is_server():
		s_anim.rpc(p, name)


@rpc("authority", "reliable")
func s_anim(p: int, name: String) -> void:
	if main:
		main.player_anim(p, name)


## Wygląd gracza (kolory, zamienniki animacji) dla wszystkich.
func broadcast_look(s: Session) -> void:
	if online() and is_server():
		s_look.rpc(s.peer, s.model_colors, s.anim_overrides)


@rpc("authority", "reliable")
func s_look(p: int, colors: Dictionary, overrides: Dictionary) -> void:
	if main:
		main.player_look(p, colors, overrides)


# ---------- interfejs modów u klienta ----------

func send_window(p: int, spec: Dictionary) -> void:
	s_window.rpc_id(p, spec)


func send_close(p: int, id: String) -> void:
	s_close.rpc_id(p, id)


func send_notify(p: int, text: String) -> void:
	s_notify.rpc_id(p, text)


@rpc("authority", "reliable")
func s_window(spec: Dictionary) -> void:
	Mods.open_windows[str(spec.get("id", ""))] = spec
	Mods.ui_window_requested.emit(spec)


@rpc("authority", "reliable")
func s_close(id: String) -> void:
	Mods.open_windows.erase(id)
	Mods.ui_close_requested.emit(id)


@rpc("authority", "reliable")
func s_notify(text: String) -> void:
	Mods.notified.emit(text)


@rpc("authority", "reliable")
func s_container(real: String, slots: Array) -> void:
	Mods.containers[real] = {"owner": "", "persist": false, "slots": slots}
	if real == Mods.hotbar.container:
		Mods.hotbar_changed.emit()


@rpc("authority", "reliable")
func s_binds(list: Array) -> void:
	Mods.binds.clear()
	Mods.binds.append_array(list)
	Mods.binds_changed.emit()


@rpc("any_peer", "reliable")
func c_bind(id: String) -> void:
	var p := multiplayer.get_remote_sender_id()
	if main and main.is_logged(p):
		Mods.as_player(p, func(): Mods.press_bind(id))


@rpc("any_peer", "reliable")
func c_click(real: String, i: int, right: bool) -> void:
	var p := multiplayer.get_remote_sender_id()
	if main and main.may_access(p, real):
		Mods.window_click(p, real, i, right)


@rpc("any_peer", "reliable")
func c_button(action: String, fields: Dictionary) -> void:
	var p := multiplayer.get_remote_sender_id()
	Mods.as_player(p, func(): Mods.window_action(action, fields))


@rpc("any_peer", "reliable")
func c_closed(id: String) -> void:
	Mods.window_closed(multiplayer.get_remote_sender_id(), id)


# ---------- stworzenia i obiekty ----------

func entity_spawned(e: Node3D) -> void:
	if online() and is_server() and main and main.remote_count() > 0:
		s_entity_spawn.rpc(main.entities.describe(e))


func entity_removed(id: int) -> void:
	if online() and is_server() and main and main.remote_count() > 0:
		s_entity_remove.rpc(id)


func entity_look(e: Node3D) -> void:
	if online() and is_server() and main and main.remote_count() > 0:
		s_entity_spawn.rpc(main.entities.describe(e))


func entity_anim(id: int, name: String) -> void:
	if online() and is_server() and main and main.remote_count() > 0:
		s_entity_anim.rpc(id, name)


@rpc("authority", "reliable")
func s_entity_spawn(d: Dictionary) -> void:
	if main:
		main.entities.puppet_spawn(d)


@rpc("authority", "reliable")
func s_entity_remove(id: int) -> void:
	if main:
		main.entities.remove(id)


@rpc("authority", "reliable")
func s_entity_anim(id: int, name: String) -> void:
	if main:
		var e: Node = main.entities.get_entity(id)
		if e is Creature:
			e.play(name)


@rpc("authority", "unreliable_ordered")
func s_entities(states: PackedFloat32Array) -> void:
	if main:
		main.entities.puppet_states(states)


# ---------- pętla serwera: rozsyłanie zmian ----------

func _physics_process(delta: float) -> void:
	if not online() or main == null:
		return
	if is_client():
		_state_t -= delta
		if _state_t <= 0.0:
			_state_t = STATE_DT
			main.send_my_state()
		return
	if not _uploads.is_empty():
		_send_uploads()
	if main.remote_count() == 0:
		return
	# bloki: całe chunki zmienione po raz pierwszy, potem pojedyncze zmiany
	for c in full_chunks.keys():
		var d: Variant = main.world.chunk_data(c)
		if d != null:
			s_chunk.rpc(c, (d as PackedByteArray).compress(FileAccess.COMPRESSION_ZSTD))
			sent_chunks[c] = true
	full_chunks.clear()
	if not block_queue.is_empty():
		s_blocks.rpc(block_queue)
		block_queue = PackedInt32Array()
	main.flush_sessions()
	_state_t -= delta
	if _state_t <= 0.0:
		_state_t = STATE_DT
		s_players.rpc(main.players_snapshot(), main.time_of_day)
	_ent_t -= delta
	if _ent_t <= 0.0:
		_ent_t = ENTITY_DT
		var st: PackedFloat32Array = main.entities.snapshot()
		if not st.is_empty():
			s_entities.rpc(st)
