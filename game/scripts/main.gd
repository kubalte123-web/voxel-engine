extends Node3D
## Rozgrywka: niebo i dzień/noc, świat, gracz, interfejs, pauza, autozapis i test automatyczny.

var world: World
var far: FarTerrain
var entities: EntityManager
var player: Player
var hud: Hud
var touch: TouchControls
var pause_menu: PauseMenu
var ui: CanvasLayer
var sun: DirectionalLight3D
var env: Environment
var sky_mat: ProceduralSkyMaterial

var info := {}
var time_of_day := 8.0       # godzina 0..24
var daynight := false
var day_minutes := 20.0
var dark_nights := false
var autosave_timer := 60.0
var tick_timer := 0.0
var windows := {}  # id okna moda -> ModWindow
var fog_base := 0.01
var was_underwater := false

# gra wieloosobowa
var players := {}        # peer -> Player (lokalny) albo RemotePlayer
var projectiles: Projectiles   # pociski z modów (engine.projectiles)
var pending_names := {}  # serwer: peer -> nazwa podana przy dołączaniu
var my_account := ""

func _ready() -> void:
	_setup_input()
	var touch_mode := DisplayServer.is_touchscreen_available()
	info = GameState.current
	if info.is_empty():
		# uruchomienie sceny bez menu: świat tymczasowy
		info = {"name": "Tymczasowy", "seed": 1337, "mods": {"base": ModManager.snapshot("base")}}

	env = Environment.new()
	sky_mat = ProceduralSkyMaterial.new()
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.fog_enabled = true
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	weather = Weather.new()
	weather.main = self
	add_child(weather)
	if info.get("weather") is Dictionary:
		var w0: Dictionary = info.weather.duplicate()
		w0["instant"] = true
		weather.set_state(w0)

	sun = DirectionalLight3D.new()
	sun.directional_shadow_max_distance = 60.0
	sun.shadow_normal_bias = 2.0
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	add_child(sun)

	# faza 1 modów: rejestr bloków, przedmiotów i opisu świata
	var reg := Mods.start_content(GameState.current_dir)
	var seed_value := int(info.get("seed", 1337))
	var spec := WorldgenSpec.compile(reg.worldgen, reg, seed_value)
	world = World.new()
	world.setup(Terrain.new(seed_value, spec), GameState.current_dir, reg)
	# id bloków mogą się zmienić, gdy gracz włączy lub wyłączy mody: przeliczamy zapisane chunki
	var old_palette: Array = info.get("palette", [])
	if old_palette.is_empty() and int(info.get("version", 3)) < 3:
		old_palette = Blocks.LEGACY_KEYS
	if not old_palette.is_empty():
		var moved := world.migrate_palette(reg.remap_from(old_palette))
		if moved > 0:
			print("PALETA przeliczone chunki: ", moved)
	info["palette"] = reg.keys.duplicate()
	info["version"] = 3
	if not GameState.current_dir.is_empty():
		GameState.write_info(GameState.current_dir, info)
	add_child(world)
	far = FarTerrain.new()
	far.setup(world)
	add_child(far)

	player = Player.new()
	player.world = world
	add_child(player)
	player.respawn()
	world.update_center(player.global_position)
	entities = EntityManager.new()
	entities.name = "Entities"
	entities.setup(world, player)
	player.entities = entities
	add_child(entities)

	daynight = ModManager.is_enabled("daynight")
	day_minutes = float(ModManager.get_value("daynight", "day_minutes"))
	dark_nights = bool(ModManager.get_value("daynight", "dark_nights"))
	var tod := float(info.get("time_of_day", -1.0))
	time_of_day = tod if tod >= 0.0 else float(ModManager.get_value("daynight", "start_hour"))
	if not daynight:
		time_of_day = 10.0
	_update_sky()

	ui = CanvasLayer.new()
	add_child(ui)
	hud = Hud.new()
	hud.player = player
	hud.world = world
	hud.main = self
	hud.touch_mode = touch_mode
	ui.add_child(hud)
	chat = Chat.new()
	chat.main = self
	ui.add_child(chat)
	if touch_mode:
		touch = TouchControls.new()
		touch.player = player
		touch.main = self
		ui.add_child(touch)

	Settings.changed.connect(_apply_settings)
	_apply_settings()

	# faza 2 modów: skrypty, po zbudowaniu świata i gracza (tylko na serwerze i w grze jednoosobowej)
	Mods.ui_window_requested.connect(_open_mod_window)
	Mods.ui_close_requested.connect(_close_mod_window)
	Net.main = self
	projectiles = Projectiles.new()
	projectiles.name = "Projectiles"
	projectiles.main = self
	projectiles.world = world
	add_child(projectiles)
	var me := Net.my_id()
	players[me] = player
	var sess := Mods.add_session(me, Settings.player_name, player, true)
	if Net.mode == "dedicated":
		# serwer bez okna: niewidoczny „gracz” trzyma tylko okolicę punktu startu
		sess.account = "#serwer"
		player.visible = false
		player.set_physics_process(false)
		player.set_process_unhandled_input(false)
	if Net.is_client():
		player.frozen = true
		player.waiting_login = true
		var lk: Variant = Net.welcome.get("looks", {})
		if lk is Dictionary:
			world.models.looks = lk.duplicate(true)
		if not Net.client_ready(reg.content_hash()):
			Mods.stop()
			GameState.back_to_menu()
			return
	else:
		world.logic = BlockLogic.new(world, self)
		world.logic.load_from(GameState.current_dir)
		Mods.start_scripts(self)
		entities.load_from(GameState.current_dir)
		if Net.mode != "dedicated":
			accept_player(me, Settings.player_name)
	for e in spec.errors:
		hud.notify("Generator świata: " + str(e))
	for id in Mods.load_errors:
		hud.notify("Mod „%s” nie wczytał się: %s" % [ModManager.manifests.get(id, {}).get("name", id), str(Mods.load_errors[id]).left(120)])
	if touch:
		touch.refresh_binds()

	# test sieci: serwer stawia warzący kocioł z kolorem cieczy obok punktu startu
	if Net.mode == "dedicated" and OS.get_cmdline_user_args().has("--test-projectiles") and Mods.registry.projectiles.has("apitest.block"):
		_test_projectiles_server.call_deferred()
	if Net.mode == "dedicated" and OS.get_cmdline_user_args().has("--test-cauldron") and Mods.registry.id_of("cauldron") > 0:
		_test_cauldron_server.call_deferred()
	if not GameState.autotest_dir.is_empty():
		if Net.is_client():
			_autotest_client(GameState.autotest_dir)
		else:
			_autotest(GameState.autotest_dir)
	else:
		for a in OS.get_cmdline_user_args():
			if a.begins_with("--shots="):
				_autotest(a.trim_prefix("--shots="))


# ---------- gracze: dołączanie, logowanie, zapis ----------

func remote_count() -> int:
	return players.size() - 1


func is_logged(p: int) -> bool:
	var s: Session = Mods.sessions.get(p)
	return s != null and s.logged_in


## Zapisany stan gracza (pozycja, zdrowie) według nazwy konta.
func _saved_player(account: String) -> Dictionary:
	var all: Dictionary = info.get("players", {}) if info.get("players") is Dictionary else {}
	if all.has(account):
		return all[account]
	if info.get("player") is Dictionary and not (info.player as Dictionary).is_empty() and all.is_empty():
		return info.player  # świat sprzed etapu 6: jeden gracz
	return {}


func _store_player(account: String, node: Node3D) -> void:
	if account.begins_with("#"):
		return
	if not info.get("players") is Dictionary:
		info["players"] = {}
	var p := node.global_position
	info.players[account] = {"pos": [p.x, p.y, p.z], "yaw": node.yaw, "pitch": node.pitch,
		"selected": node.selected, "health": node.health}


## Przyjęcie gracza na konto: od teraz działa w świecie jako `account` (pozycja, ekwipunek, dane modów
## tego konta). Zwraca "" albo opis błędu. Wywołują to silnik (bez moda logowania) albo mod logowania.
func accept_player(p: int, account: String) -> String:
	var s: Session = Mods.sessions.get(p)
	if s == null:
		return "nie ma takiego gracza"
	account = account.strip_edges().left(24)
	if account.is_empty() or account.begins_with("#"):
		return "niepoprawna nazwa konta"
	for q in Mods.sessions:
		if q != p and Mods.sessions[q].logged_in and Mods.sessions[q].account == account:
			return "to konto jest już w grze"
	s.account = account
	s.logged_in = true
	var node: Node3D = s.node
	var saved := _saved_player(account)
	var pos: Vector3 = node.spawn_point()
	if saved.has("pos"):
		pos = Vector3(saved.pos[0], saved.pos[1], saved.pos[2])
	node.selected = int(saved.get("selected", 0))
	if s.local:
		my_account = account
		player.global_position = pos
		player.yaw = float(saved.get("yaw", player.yaw))
		player.pitch = float(saved.get("pitch", player.pitch))
		player.reset_fall()
	else:
		node.set_account(account)
		node.global_position = pos
		node.net_pos = pos
	Mods.restore_effects(p)
	Mods.as_player(p, func(): Mods.emit_event("player.join", {"id": p, "name": account}))
	var hp := float(saved.get("health", node.stat("max_health")))
	if s.local:
		player.set_health(hp)
	else:
		node.health = hp
		Net.s_accepted.rpc_id(p, account, pos, hp)
		Mods.dirty_containers[s.hotbar.container] = true
		s.dirty["stats"] = true
		s.dirty["camera"] = true
		s.dirty["hud"] = true
		s.dirty["hotbar"] = true
		_announce("%s dołącza do gry" % account)
	return ""


func _announce(text: String) -> void:
	broadcast_chat("", text, "#ffe08a")


# ---------- pogoda ----------

var weather: Weather


## Serwer: nowa pogoda albo niebo; trafia do wszystkich graczy. st: kind, intensity, sky.
func set_weather(st: Dictionary) -> void:
	var before := weather.state()
	weather.set_state(st)
	if Net.online() and Net.is_server():
		Net.s_weather.rpc(weather.state())
	if str(before.kind) != weather.kind:
		Mods.emit_event("weather.changed", {"kind": weather.kind, "intensity": weather.target, "from": before.kind})


# ---------- czat ----------

var chat: Chat


## U siebie: wpisany tekst z czatu (polecenie albo wiadomość).
func send_chat(text: String) -> void:
	if text.begins_with("/"):
		run_command_local(text, chat)
	elif Net.is_client():
		Net.c_chat.rpc_id(1, text)
	else:
		chat_from(Mods.local_peer, text)


## Serwer: wiadomość gracza p. Hak "chat.message" może ją zmienić (ctx.text, ctx.name, ctx.color) albo zatrzymać.
func chat_from(p: int, text: String) -> void:
	var s: Session = Mods.sessions.get(p)
	if s == null or not s.logged_in:
		return
	text = text.strip_edges().left(256)
	if text == "":
		return
	if text.begins_with("/"):
		var r := run_command(p, text)
		if r != "":
			send_system(p, r)
		return
	var ctx: Dictionary = Mods.as_player(p, func(): return Mods.before("chat.message", {"player": p, "name": s.account, "text": text, "color": ""}))
	if ctx.get("cancel", false):
		return
	broadcast_chat(str(ctx.get("name", s.account)), str(ctx.get("text", text)), str(ctx.get("color", "")))
	Mods.as_player(p, func(): Mods.after("chat.message", ctx))


## Serwer: linijka czatu do wszystkich (who = "" to wiadomość serwera) albo tylko do gracza `to`.
func broadcast_chat(who: String, text: String, color := "", to := -1) -> void:
	if Net.mode == "dedicated" or OS.get_cmdline_user_args().has("--chat-log"):
		print("CZAT ", ("<%s> " % who) if who != "" else "", text)
	for q in Mods.sessions:
		var s: Session = Mods.sessions[q]
		if not s.logged_in or (to >= 0 and q != to):
			continue
		if s.local:
			if Net.mode != "dedicated":
				show_chat(who, text, color)
		else:
			Net.s_chat.rpc_id(q, who, text, color)


func send_system(p: int, text: String) -> void:
	broadcast_chat("", text, "#cfe0f0", p)


func show_chat(who: String, text: String, color: String) -> void:
	if chat:
		chat.add_line(text, Color.from_string(color, Color(1, 1, 1)) if color != "" else Color(1, 1, 1), who)


## Serwer: klient wczytał świat. Tworzymy jego postać, wysyłamy stan i uruchamiamy logowanie.
func add_remote_player(p: int, name: String) -> void:
	var node := RemotePlayer.new()
	node.peer = p
	node.world = world
	node.is_server_side = true
	node.account = name
	add_child(node)
	node.global_position = player.spawn_point()
	players[p] = node
	var s := Mods.add_session(p, name, node, false)
	node.session = s
	s.lang = str(Net.peer_langs.get(p, "pl"))
	var ws := weather.state()
	ws["instant"] = true
	Net.s_weather.rpc_id(p, ws)
	Net.s_binds.rpc_id(p, Mods.binds)
	for e in entities.entities.values():
		Net.s_entity_spawn.rpc_id(p, entities.describe(e))
	for q in Mods.sessions:
		var o: Session = Mods.sessions[q]
		if o.logged_in and q != p:
			Net.s_look.rpc_id(p, q, o.model_colors, o.anim_overrides)
			if not o.wear.is_empty():
				Net.s_wear.rpc_id(p, q, o.wear)
	# logowanie: mod może zatrzymać gracza (ctx.wait = true) i przyjąć go później (engine.players.accept)
	var ctx: Dictionary = Mods.as_player(p, func(): return Mods.before("player.login", {"id": p, "name": name}))
	if ctx.get("cancel", false):
		Net.kick(p, str(ctx.get("reason", "")))
	elif not ctx.get("wait", false):
		var err := accept_player(p, name)
		if err != "":
			Net.kick(p, err)


func remove_remote_player(p: int) -> void:
	var s: Session = Mods.sessions.get(p)
	var node: Node3D = players.get(p)
	if s and s.logged_in and node:
		_store_player(s.account, node)
		Mods.window_closed(p, "")
		Mods.as_player(p, func(): Mods.emit_event("player.leave", {"id": p, "name": s.account}))
	Mods.remove_session(p)
	if s and s.logged_in:
		_announce("%s opuszcza grę" % s.account)
	pending_names.erase(p)
	if node:
		node.queue_free()
	players.erase(p)


func world_info_for_client() -> Dictionary:
	world.save_all()
	var chunks := {}
	if not GameState.current_dir.is_empty():
		var dir := DirAccess.open(GameState.current_dir.path_join("chunks"))
		if dir:
			for f in dir.get_files():
				var parts := f.get_basename().split("_")
				if parts.size() == 3:
					var c := Vector3i(int(parts[0]), int(parts[1]), int(parts[2]))
					chunks[c] = FileAccess.get_file_as_bytes(GameState.current_dir.path_join("chunks").path_join(f))
					Net.sent_chunks[c] = true
	var settings := {}
	var enabled := {}
	for id in ModManager.manifests:
		settings[id] = ModManager.snapshot(id)
		enabled[id] = ModManager.is_enabled(id)
	# ustawienia zapisane w świecie mają pierwszeństwo
	for id in info.get("mods", {}):
		for k in info.mods[id]:
			if settings.has(id):
				settings[id][k] = info.mods[id][k]
	return {"name": info.get("name", "Serwer"), "seed": int(info.get("seed", 1337)), "mods": info.get("mods", {}),
		"palette": Mods.registry.keys, "time": time_of_day, "content_hash": Mods.registry.content_hash(),
		"looks": world.logic.looks if world.logic else {},
		"versions": Net.mods_signature(), "chunks": chunks,
		"profile": {"order": ModManager.effective_order(), "enabled": enabled, "settings": settings}}


## Klient: serwer przyjął nas na konto.
func on_accepted(account: String, pos: Vector3, health: float) -> void:
	my_account = account
	player.waiting_login = false
	player.global_position = pos
	player.velocity = Vector3.ZERO
	player.reset_fall()
	player.set_health(health)


func remote_move(p: int, st: Dictionary) -> void:
	var node: Node3D = players.get(p)
	if node is RemotePlayer and is_logged(p):
		node.apply_state(st)


func remote_action(p: int, kind: String, args: Dictionary) -> void:
	var node: Node3D = players.get(p)
	if not node is RemotePlayer or not is_logged(p):
		return
	Mods.as_player(p, _remote_action.bind(p, node, kind, args))


func _remote_action(p: int, node: RemotePlayer, kind: String, args: Dictionary) -> void:
	var reach := float(node.stat("reach")) + 3.0
	if true:
		match kind:
			"select":
				node.selected = clampi(int(args.get("i", 0)), 0, 8)
			"dismount":
				entities.dismount(p)
			"dig_start":
				var pos := Vector3i(args.pos)
				Net.s_dig_time.rpc_id(p, pos, Actions.dig_time(node, world, pos))
			"dig":
				var pos := Vector3i(args.pos)
				if Vector3(pos).distance_to(node.global_position) <= reach + 1.0:
					Actions.break_at(node, world, pos)
			"use":
				var t := RemotePlayer._target(args.get("target", {}))
				if t.is_empty() or Vector3(t.pos).distance_to(node.global_position) <= reach + 1.0:
					node.target = t
					Actions.use(node, world, entities, t)
			"attack", "kick", "interact":
				var e: Node3D = entities.get_entity(int(args.get("id", -1)))
				if e and e.global_position.distance_to(node.global_position) <= reach + 1.0:
					if kind == "attack":
						Actions.attack(node, e, int(args.get("stage", 1)))
					elif kind == "kick":
						Actions.kick(node, e, Vector3(args.get("dir", Vector3.FORWARD)))
					else:
						Actions.interact(node, entities, e)
			"land":
				Mods.emit_event("player.land", {"fall": float(args.get("fall", 0.0)), "speed": float(args.get("speed", 0.0))})
			"void":
				node.die("void")


## Klient: stan od serwera (statystyki, kamera, paski, pasek przedmiotów, przedmiot pod kursorem).
func session_update(part: String, value: Variant) -> void:
	match part:
		"stats":
			Mods.player_stats.clear()
			Mods.player_stats.merge(value)
		"camera":
			Mods.camera_stats.clear()
			Mods.camera_stats.merge(value)
		"effects":
			Mods.client_effects = value if value is Dictionary else {}
			Mods.effects_changed.emit()
		"hud":
			Mods.hud.clear()
			Mods.hud.merge(value)
			Mods.hud_changed.emit()
		"hotbar":
			Mods.hotbar.merge(value, true)
			Mods.hotbar_changed.emit()
		"held":
			Mods.local_held.clear()
			Mods.local_held.merge(value)
		"push":
			player.velocity += Vector3(value)
		"mount":
			player.mount_id = int(value[0])
			player.mount_seat = float(value[1])


## Serwer: zmiany sesji graczy zdalnych i kontenerów, które oglądają, do ich klientów.
func flush_sessions() -> void:
	for p in Mods.sessions:
		var s: Session = Mods.sessions[p]
		if s.local:
			continue
		for part in s.dirty:
			match part:
				"stats": Net.s_session.rpc_id(p, "stats", s.player_stats)
				"camera": Net.s_session.rpc_id(p, "camera", s.camera_stats)
				"hud": Net.s_session.rpc_id(p, "hud", s.hud)
				"hotbar": Net.s_session.rpc_id(p, "hotbar", s.hotbar)
				"held": Net.s_session.rpc_id(p, "held", s.held)
				"effects": Net.s_session.rpc_id(p, "effects", s.effects)
		s.dirty.clear()
		if Mods.dirty_containers.is_empty():
			continue
		var watched := [s.hotbar.container]
		for w in s.windows.values():
			watched.append_array(ModWindow.slot_containers(w))
		for real in watched:
			if Mods.dirty_containers.has(real) and Mods.containers.has(real):
				Net.s_container.rpc_id(p, real, Mods.container_slots(real))
	Mods.dirty_containers.clear()


func may_access(p: int, real: String) -> bool:
	var s: Session = Mods.sessions.get(p)
	if s == null or not s.logged_in:
		return false
	if s.hotbar.container == real:
		return true
	for w in s.windows.values():
		if ModWindow.slot_containers(w).has(real):
			return true
	return false


func players_snapshot() -> Array:
	var out := []
	for p in players:
		var s: Session = Mods.sessions.get(p)
		if s == null or not s.logged_in:
			continue
		var n: Node3D = players[p]
		# czas stanu: dla gracza zdalnego jego własny (z klienta), dla gracza na serwerze czas serwera
		var t: float = n.net_t if n is RemotePlayer else NetInterp.now()
		out.append({"peer": p, "name": s.account, "t": t, "pos": n.global_position, "vel": n.velocity,
			"yaw": n.yaw, "pitch": n.pitch, "floor": n.is_on_floor() if n is Player else n.on_floor,
			"mount": s.mount, "seat": s.mount_seat, "held": str(n.current_item().get("item", "")),
			"pose": n.pose, "sprint": n.sprinting, "dig": n.model.digging, "liquid": n.in_liquid, "act": [n.act_n, n.act_name]})
	return out


## Klient: pozycje innych graczy od serwera.
func players_state(list: Array, time: float) -> void:
	time_of_day = time
	var seen := {}
	var me := Net.my_id()
	for st in list:
		var p := int(st.peer)
		if p == me:
			continue
		seen[p] = true
		var node: RemotePlayer = players.get(p)
		if node == null:
			node = RemotePlayer.new()
			node.peer = p
			node.world = world
			node.account = str(st.name)
			add_child(node)
			node.global_position = st.pos
			players[p] = node
		node.set_account(str(st.name))
		node.apply_state(st)
	for p in players.keys():
		if p != me and not seen.has(p):
			players[p].queue_free()
			players.erase(p)


func send_my_state() -> void:
	if player.waiting_login:
		return
	Net.c_move.rpc_id(1, {"t": NetInterp.now(), "pos": player.global_position, "vel": player.velocity, "yaw": player.yaw,
		"pitch": player.pitch, "floor": player.is_on_floor(), "target": Player._net_target(player.target),
		"target_liq": Player._net_target(player.target_with_liquids()), "liquid": player.in_liquid,
		"eyes": player.eyes_in_liquid, "cam": player.camera_mode(), "pose": player.pose, "sprint": player.sprinting,
		"dig": player.model.digging, "act": [player.act_n, player.act_name]})


func player_anim(p: int, name: String) -> void:
	var node: Node3D = players.get(p)
	if node and node.model:
		node.model.play(name)


func player_wear(p: int, wear: Dictionary) -> void:
	var node: Node3D = players.get(p)
	if node == null and p == Net.my_id():
		node = player
	if node and node.model:
		node.model.set_wear(wear)


func player_look(p: int, colors: Dictionary, overrides: Dictionary) -> void:
	var node: Node3D = players.get(p)
	if node == null:
		return
	if node == player:
		Mods.model_colors.merge(colors, true)
		Mods.anim_overrides.clear()
		Mods.anim_overrides.merge(overrides)
		player.model.apply_colors(colors)
	else:
		node.model.apply_colors(colors)
		node.model.overrides = overrides


## Podpisy nad głowami: widoczne, gdy patrzymy na gracza albo stoi bardzo blisko.
func _update_name_labels(delta: float) -> void:
	var cam := player.camera
	var fwd := -cam.global_basis.z
	for p in players:
		var node: Node3D = players[p]
		if not node is RemotePlayer:
			continue
		var head: Vector3 = node.global_position + Vector3(0, 1.4, 0)
		var to := head - cam.global_position
		var d := to.length()
		var look := d < 32.0 and fwd.dot(to.normalized()) > cos(deg_to_rad(7.0 + 30.0 / maxf(d, 1.0)))
		node.show_name(look or d < 3.0, delta)


func _apply_settings() -> void:
	world.set_radius(Settings.render_distance)
	far.set_radius(Settings.render_distance, Settings.far_view)
	world.water_material.set_shader_parameter("wave", 1.0 if Settings.water_waves else 0.0)
	world.material.set_shader_parameter("min_light", EntityLight.min_light())
	world.water_material.set_shader_parameter("min_light", EntityLight.min_light())
	player.camera.fov = Settings.fov
	player.mouse_sensitivity = 0.0028 * Settings.mouse_sensitivity
	sun.shadow_enabled = Settings.shadows and not OS.has_feature("web")
	var dist := maxf(Settings.render_distance * 32.0, far.radius_blocks)
	fog_base = 2.2 / dist
	env.fog_density = fog_base
	player.camera.far = dist + 64.0


var prof_main_ms := 0.0

func _process(delta: float) -> void:
	var tp0 := Time.get_ticks_usec()
	_process_inner(delta)
	prof_main_ms = (Time.get_ticks_usec() - tp0) / 1000.0


func _process_inner(delta: float) -> void:
	world.update_center(player.global_position)
	# przy wczytywaniu (gracz jeszcze czeka) wstawiamy chunki szybciej, w grze najwyżej 4 ms na klatkę
	world.apply_budget_ms = 40.0 if player.frozen else 4.0
	if Net.online() and Net.is_server():
		var extra: Array[Vector3] = []
		for p in players:
			if players[p] is RemotePlayer and is_logged(p):
				extra.append(players[p].global_position)
		world.extra_centers = extra
	if Net.online():
		_update_name_labels(delta)
	far.update_center(player.global_position)
	if daynight:
		time_of_day = fmod(time_of_day + delta * 24.0 / (day_minutes * 60.0), 24.0)
		_update_sky()
	elif Net.is_client() or (weather and (weather.intensity > 0.0 or not weather.sky.is_empty())):
		_update_sky()
	_update_underwater()
	_update_hand_light()
	tick_timer -= delta
	if tick_timer <= 0.0 and not Net.is_client():
		tick_timer = 0.1
		Mods.emit_event("tick", {"dt": 0.1, "time": time_of_day})
		if world.logic:
			world.logic.tick(0.1)
		Mods.tick_effects(0.1)
	autosave_timer -= delta
	if autosave_timer <= 0.0 and not GameState.current_dir.is_empty() and not Net.is_client():
		autosave_timer = 60.0
		save_game(false)   # chunki zapisuje wątek w tle


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_F2 or event.keycode == KEY_QUOTELEFT) and console == null:
		get_viewport().set_input_as_handled()
		open_console()
		return
	if event is InputEventKey and event.pressed and not event.echo and (event.keycode == KEY_T or event.keycode == KEY_ENTER or event.keycode == KEY_SLASH) \
			and console == null and windows.is_empty() and pause_menu == null and chat and not chat.open:
		get_viewport().set_input_as_handled()
		chat.open_input("/" if event.keycode == KEY_SLASH else "")
		return
	if event.is_action_pressed("ui_cancel") and pause_menu == null and windows.is_empty():
		get_viewport().set_input_as_handled()
		open_pause()
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := OS.get_keycode_string(event.physical_keycode).to_upper()
		for b in Mods.binds:
			if b.key == key:
				get_viewport().set_input_as_handled()
				Mods.press_bind(b.id)
				return


# ---------- konsola modera i przeładowanie modów ----------

var console: ModConsole


func open_console() -> void:
	if console:
		return
	close_pause()
	console = ModConsole.new()
	console.main = self
	console.closed.connect(func():
		console = null
		player.ui_blocked = not windows.is_empty()
		if windows.is_empty() and not touch:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)
	ui.add_child(console)
	player.ui_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


## Polecenie wpisane w konsoli albo czacie (u siebie): /reload działa lokalnie, reszta idzie do serwera.
func run_command_local(text: String, out: Node) -> void:
	var cmd := text.substr(1).get_slice(" ", 0).to_lower()
	if cmd == "reload":
		var err := reload_mods()
		if err != "" and out:
			out.print_line(err, "#ff8a7a")
		return
	if Net.is_client():
		Net.c_command.rpc_id(1, text)
	else:
		var r := run_command(Mods.local_peer, text)
		if out and r != "":
			out.print_line(r)


## Przeładowanie modów bez wychodzenia z gry: zapis, ponowne wczytanie plików modów i świata.
func reload_mods() -> String:
	if Net.is_client():
		return "Mody przeładowuje serwer (polecenie /reload na serwerze)."
	if Net.online() and remote_count() > 0:
		return "Nie można przeładować modów, gdy na serwerze są inni gracze."
	save_game()
	ModPack.clear_cache()
	ModManager.scan()
	ModManager.load_user()
	Mods.stop()
	print("PRZEŁADOWANIE modów")
	GameState.start(GameState.current_dir)
	return ""


## Polecenie na serwerze w imieniu gracza `p`. Zwraca odpowiedź dla gracza.
func run_command(p: int, text: String) -> String:
	return Commands.run(self, p, text)


## Rola gracza: administrator może używać konsoli Lua i poleceń administracyjnych.
func role_of(p: int) -> String:
	var s: Session = Mods.sessions.get(p)
	if s == null:
		return "player"
	if s.local and Net.mode != "dedicated":
		return "admin"
	return role_of_account(s.account)


func role_of_account(account: String) -> String:
	var roles: Dictionary = GameState.current.get("roles", {}) if GameState.current.get("roles") is Dictionary else {}
	for a in Net.admins:
		if str(a).to_lower() == account.to_lower():
			return "admin"
	return str(roles.get(account, "player"))


## Rola konta zapisywana w świecie (world.json); działa od razu, także dla grających.
func set_role(account: String, role: String) -> void:
	if not GameState.current.get("roles") is Dictionary:
		GameState.current["roles"] = {}
	if role == "player":
		GameState.current.roles.erase(account)
	else:
		GameState.current.roles[account] = role
	if not GameState.current_dir.is_empty():
		GameState.write_info(GameState.current_dir, GameState.current)
	var q := Commands.find_player(account)
	if q >= 0:
		send_system(q, "Twoja rola: %s" % role)


# ---------- okna modów ----------

func _open_mod_window(spec: Dictionary) -> void:
	var id := str(spec.get("id", ""))
	if windows.has(id):
		windows[id].build(spec)
		return
	var w := ModWindow.new()
	w.spec = spec
	w.closed.connect(_on_window_closed)
	ui.add_child(w)
	windows[id] = w
	player.ui_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _close_mod_window(id: String) -> void:
	if windows.has(id):
		windows[id].close()


func _on_window_closed(id: String) -> void:
	windows.erase(id)
	Mods.open_windows.erase(id)
	player.ui_blocked = not windows.is_empty()


## Słońce, kolory nieba, światło otoczenia i mgła w zależności od godziny.
func _update_sky() -> void:
	var angle := (time_of_day - 6.0) / 24.0 * TAU   # 6:00 wschód, 12:00 zenit, 18:00 zachód
	var elev := sin(angle)
	sun.rotation = Vector3(-asin(clampf(elev, -1.0, 1.0)) if elev > 0.0 else -0.15, -0.6 + angle * 0.15, 0)
	var day := Terrain.sm(-0.12, 0.25, elev)
	var dusk := clampf(1.0 - absf(elev) * 4.0, 0.0, 1.0) * (1.0 if elev > -0.25 else 0.0)
	var night_top := Color(0.03, 0.05, 0.12) if dark_nights else Color(0.08, 0.12, 0.25)
	var night_hor := Color(0.06, 0.08, 0.16) if dark_nights else Color(0.14, 0.20, 0.34)
	var top := night_top.lerp(Color(0.36, 0.58, 0.88), day)
	var hor := night_hor.lerp(Color(0.70, 0.82, 0.94), day).lerp(Color(0.95, 0.62, 0.40), dusk * 0.6)
	sky_mat.sky_top_color = top
	sky_mat.sky_horizon_color = hor
	sky_mat.ground_horizon_color = hor
	sky_mat.ground_bottom_color = hor.darkened(0.4)
	var amb := lerpf(0.025 if dark_nights else 0.07, 0.3, day)   # noc jest ciemna, żeby pochodnie miały znaczenie
	var sun_e := 0.75 * day
	if weather:
		var w := weather.apply_sky(top, hor, sun_e, amb)
		top = w[0]
		hor = w[1]
		sun_e = w[2]
		amb = w[3]
		sky_mat.sky_top_color = top
		sky_mat.sky_horizon_color = hor
		sky_mat.ground_horizon_color = hor
		sky_mat.ground_bottom_color = hor.darkened(0.4)
		if not was_underwater:
			env.fog_density = fog_base * weather.fog_mul()
	sun.light_energy = sun_e
	sun.light_color = Color(1, 1, 1).lerp(Color(1.0, 0.72, 0.5), dusk)
	sun.visible = day > 0.01
	env.ambient_light_energy = amb
	env.fog_light_color = hor


## Przedmiot świecący w ręce (pochodnia) oświetla okolicę gracza.
func _update_hand_light() -> void:
	var b := player.current_block()
	var l := 0
	if b > 0:
		l = Blocks.reg.lprops[b] & 15
	world.material.set_shader_parameter("hand_light", float(l) / 15.0)
	world.material.set_shader_parameter("hand_pos", player.global_position + Vector3(0, 1.3, 0))


## Widok pod wodą: gęsta mgła w kolorze cieczy i lekkie zabarwienie ekranu.
func _update_underwater() -> void:
	var under := player.eyes_in_liquid
	if under:
		var b := world.get_block(Vector3i(player.camera.global_position.floor()))
		var k := Blocks.reg.liquid_kind(b)
		var deep: Color = Blocks.reg.liquid_kinds[k].deep if k >= 0 else Color(0.05, 0.2, 0.4)
		env.fog_density = 0.09
		env.fog_light_color = deep.lightened(0.15)
		hud.tint = Color(deep.r, deep.g, deep.b, 0.28)
	elif was_underwater:
		env.fog_density = fog_base
		hud.tint = Color(0, 0, 0, 0)
		_update_sky()
	if under != was_underwater:
		Mods.emit_event("player.underwater", {"underwater": under})
	was_underwater = under


func time_text() -> String:
	return "%02d:%02d" % [int(time_of_day), int(fmod(time_of_day, 1.0) * 60.0)]


# ---------- pauza i zapis ----------

func open_pause() -> void:
	if pause_menu != null:
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	pause_menu = PauseMenu.new()
	pause_menu.resume.connect(close_pause)
	pause_menu.save_and_exit.connect(func():
		save_game()
		Net.leave()
		Mods.stop()
		GameState.back_to_menu())
	ui.add_child(pause_menu)
	# w grze wieloosobowej świat toczy się dalej (inni gracze, serwer)
	get_tree().paused = not Net.online()


func close_pause() -> void:
	if pause_menu:
		pause_menu.queue_free()
		pause_menu = null
	get_tree().paused = false


var last_save := {}   # czasy części ostatniego zapisu (pomiar)

## blocking = false (autozapis): pliki chunków zapisuje wątek w tle; przy wyjściu zawsze czekamy na zapis.
func save_game(blocking := true) -> void:
	if GameState.current_dir.is_empty() or Net.is_client():
		return
	var ts := Time.get_ticks_usec()
	var nch := world.save_all(blocking)
	var t1 := Time.get_ticks_usec()
	Mods.save_data(GameState.current_dir)
	var t2 := Time.get_ticks_usec()
	entities.save(GameState.current_dir)
	var t3 := Time.get_ticks_usec()
	last_save = {"chunks": nch, "world_ms": (t1 - ts) / 1000.0, "mods_ms": (t2 - t1) / 1000.0, "entities_ms": (t3 - t2) / 1000.0}
	for q in Mods.sessions:
		var s: Session = Mods.sessions[q]
		if s.logged_in and players.has(q):
			_store_player(s.account, players[q])
	info.erase("player")
	info["palette"] = Mods.registry.keys.duplicate()
	info["time_of_day"] = time_of_day
	info["weather"] = weather.state()
	info["played"] = int(Time.get_unix_time_from_system())
	GameState.current = info
	GameState.write_info(GameState.current_dir, info)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save_game()


func _setup_input() -> void:
	var keys := {
		"move_forward": [KEY_W, KEY_UP], "move_back": [KEY_S, KEY_DOWN],
		"move_left": [KEY_A, KEY_LEFT], "move_right": [KEY_D, KEY_RIGHT],
		"jump": [KEY_SPACE], "toggle_view": [KEY_V, KEY_F5], "dismount": [KEY_SHIFT],
		"crawl": [KEY_X], "sit": [KEY_Z], "sprint": [KEY_CTRL],
	}
	for i in 9:
		keys["slot_%d" % (i + 1)] = [KEY_1 + i]
	for action in keys:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)


# ---------- test automatyczny: zrzuty ekranu i pomiary ----------

func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _shot(dir: String, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(dir.path_join(name + ".png"))
	print("SHOT ", name)


func _wait_loaded() -> void:
	var t0 := Time.get_ticks_msec()
	while player.frozen or world.queued.size() > 0 or world.nodes.size() < 12:
		await _wait(0.2)
		if Time.get_ticks_msec() - t0 > 120000:
			break
	print("LOADED ms=", Time.get_ticks_msec() - t0, " ", world.stats())


func _inv_total() -> int:
	var n := 0
	for c in ["hotbar", "backpack"]:
		for sl in Mods.container_slots(Mods.cid(c)):
			n += int(sl.get("count", 0))
	return n


func _find_biome(biome: int) -> Vector2i:
	var t := world.terrain
	for r in range(0, 4000, 48):
		for k in 16:
			var a := k * TAU / 16.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			var c := t.column(x, z)
			if c.y == biome and c.x > 8 and t.column(x + 24, z).y == biome and t.column(x, z + 24).y == biome:
				return Vector2i(x, z)
	return Vector2i(999999, 0)


## Szuka kolumny ze strukturą (element rodzaju 3) w pobliżu startu.
func _find_structure() -> Vector3i:
	var t := world.terrain
	for r in range(0, 1500, 4):
		for k in 32:
			var a := k * TAU / 32.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			if Terrain.hash01(x, z, t.seed_value, 1) >= t.max_sum:
				continue
			var c := t.column(x, z)
			var f := t.feature_at(x, z, c.x, c.y)
			if f >= 0 and int(t.F[f * Terrain.FS + 1]) == 3:
				return Vector3i(x, c.x, z)
	return Vector3i(999999, 0, 0)


func _find_lake() -> Vector3i:
	var t := world.terrain
	for r in range(0, 900, 6):
		for k in 24:
			var a := k * TAU / 24.0
			var x := int(cos(a) * r)
			var z := int(sin(a) * r)
			if t.height(x, z) < t.sea - 2 and t.height(x + 3, z) < t.sea - 1 and t.height(x, z + 3) < t.sea - 1:
				return Vector3i(x, t.height(x, z), z)
	return Vector3i(999999, 0, 0)


func _water_volume(center: Vector3i, r: int) -> Array:
	var vol := 0
	var cells := 0
	for x in range(center.x - r, center.x + r + 1):
		for z in range(center.z - r, center.z + r + 1):
			for y in range(center.y - 4, center.y + 6):
				var b := world.get_block(Vector3i(x, y, z))
				if Blocks.reg.is_liquid(b):
					vol += Blocks.reg.liquid_level(b)
					cells += 1
	return [vol, cells]


func _look_at_point(p: Vector3) -> void:
	var to := p - (player.global_position + Vector3(0, 1.55, 0))
	player.yaw = atan2(-to.x, -to.z)
	player.pitch = clampf(atan2(to.y, Vector2(to.x, to.z).length()), -1.4, 1.1)


## Szybki test samego światła: noc z pochodniami i lampą, pochodnia w ręce.
func _test_light(dir: String) -> void:
	Settings.render_distance = 3
	_apply_settings()
	await _wait_loaded()
	var hz0 := world.terrain.height(0, 0)
	time_of_day = 23.0
	_update_sky()
	var tbase := Vector3i(player.global_position.floor())
	var placed: Array[Vector3i] = []
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		var x := tbase.x + roundi(cos(a) * 4.0)
		var z := tbase.z + roundi(sin(a) * 4.0)
		var ty := entities._surface(x, z, tbase.y + 6)
		if ty != -99999:
			world.set_block(Vector3i(x, ty + 1, z), Blocks.id("torch"))
			placed.append(Vector3i(x, ty + 1, z))
	world.set_block(Vector3i(tbase.x - 5, entities._surface(tbase.x - 5, tbase.z, tbase.y + 4) + 1, tbase.z), Blocks.id("lamp"))
	await _wait(2.0)
	var tq: Vector3i = placed[0] if not placed.is_empty() else tbase
	var cc := World.chunk_of(tq)
	var mb := 0.0
	if world.nodes.has(cc):
		var cols: PackedColorArray = (world.nodes[cc].mesh as ArrayMesh).surface_get_arrays(0)[Mesh.ARRAY_COLOR]
		for col in cols:
			mb = maxf(mb, col.b)
	print("ŚWIATŁO pochodnia ", Blocks.key(world.get_block(tq)), " w ", tq, " obok=", world.light_at(Vector3(tq) + Vector3(1.5, 0.5, 0.5)), " max b w siatce chunka=", mb)
	player.pitch = -0.45
	Mods.camera_stats["distance"] = 6.0
	await _wait(0.8)
	await _shot(dir, "l1_night_torches")
	Mods.set_slot("hotbar", 0, {"item": "torch", "count": 5})
	player.select(0)
	world.set_block(Vector3i(tbase.x, tbase.y, tbase.z) + Vector3i(0, -1, 0), Blocks.id("dirt"))
	time_of_day = 12.0
	_update_sky()
	await _wait(0.6)
	await _shot(dir, "l2_day")
	get_tree().quit()


func _test_stage5(dir: String) -> void:
	var reg := Blocks.reg
	# twardość: czas kopania
	print("KOPANIE czas [s]: ziemia=", reg.hardness[Blocks.id("dirt")], " kamień=", reg.hardness[Blocks.id("stone")], " woda=", reg.hardness[Blocks.id("water")])
	# woda wylana na płaskim terenie: objętość się zachowuje (8 poziomów = 1 blok)
	var p0 := Vector3i(player.global_position.floor())
	var spot := p0 + Vector3i(4, 0, 0)
	var gy := entities._surface(spot.x, spot.z, p0.y + 6)
	var pour := Vector3i(spot.x, gy + 3, spot.z)
	world.set_block(pour, Blocks.id("water~8"))
	world.set_block(pour + Vector3i(0, 0, 1), Blocks.id("water~8"))
	await _wait(0.4)
	var v1 := _water_volume(Vector3i(spot.x, gy, spot.z), 6)
	await _wait(3.0)
	var v2 := _water_volume(Vector3i(spot.x, gy, spot.z), 6)
	print("WODA wylane=16 po 0.4 s=", v1, " po 3.4 s=", v2, " zmian symulacji=", world.liquids.moved_total)
	_look_at_point(Vector3(spot.x, gy, spot.z))
	await _wait(0.3)
	await _shot(dir, "g10_water_poured")
	# grawitacja: piasek w powietrzu spada
	var sand_at := Vector3i(spot.x - 2, gy + 4, spot.z - 2)
	world.set_block(sand_at, Blocks.id("sand"))
	await _wait(2.0)
	var landed := -1
	for y in range(gy - 2, gy + 6):
		if world.get_block(Vector3i(sand_at.x, y, sand_at.z)) == Blocks.id("sand"):
			landed = y
	print("GRAWITACJA piasek z y=", sand_at.y, " wylądował na y=", landed, " (teren ", gy, ")")

	# jezioro: obiekty luźne pływają albo toną, gracz pływa
	var lake := _find_lake()
	if lake.x != 999999:
		var sea := world.terrain.sea
		await _goto(lake.x + 0.5, sea + 1.5, lake.z + 6.5)
		await _wait(0.5)
		var ids := {}
		for k in ["crate", "barrel", "ball", "boulder"]:
			ids[k] = entities.spawn_prop(Blocks.id(k), Vector3(lake.x + 0.5 + ids.size() * 1.3 - 2.0, sea + 2.5, lake.z + 0.5), Vector3.ZERO)
		await _wait(5.0)
		var ys := {}
		for k in ids:
			var e := entities.get_entity(ids[k])
			ys[k] = snappedf(e.global_position.y, 0.01) if e else "brak"
		print("PŁYWANIE poziom wody=", sea + 1, " wysokości obiektów: ", ys)
		_look_at_point(Vector3(lake.x + 0.5, sea + 1, lake.z + 0.5))
		player.global_position.y = sea + 3.0
		await _wait(0.5)
		await _shot(dir, "g11_lake_props")
		# pod wodą
		player.global_position = Vector3(lake.x + 0.5, sea - 1.2, lake.z + 3.5)
		player.velocity = Vector3.ZERO
		player.first_person = true
		await _wait(0.6)
		print("PŁYWA gracz w cieczy=", player.in_liquid, " oczy pod wodą=", player.eyes_in_liquid)
		await _shot(dir, "g12_underwater")
		player.first_person = false
		await _wait(1.5)
	else:
		print("JEZIORO nie znaleziono")

	# zwierzęta: czekamy, aż się pojawią, i patrzymy na najbliższe
	await _goto(0.5, world.terrain.height(0, 0) + 2.0, 0.5)
	var t0 := Time.get_ticks_msec()
	while entities.list().size() < 4 and Time.get_ticks_msec() - t0 < 30000:
		await _wait(0.5)
	var by_type := {}
	for id in entities.list():
		var c: Creature = entities.get_entity(id)
		by_type[c.type] = by_type.get(c.type, 0) + 1
	print("ZWIERZĘTA ", by_type)
	for type in ["sheep", "cow", "chicken"]:
		var lst := entities.list(type)
		if lst.is_empty():
			continue
		var c: Creature = entities.get_entity(lst[0])
		for id in lst:
			var cc: Creature = entities.get_entity(id)
			if cc.scale_factor >= 1.0:
				c = cc
				break
		var cp := c.global_position
		var hh := world.terrain.height(floori(cp.x) + 2, floori(cp.z) + 2)
		await _goto(cp.x + 2.2, maxf(cp.y, hh + 1.0) + 0.5, cp.z + 2.2)
		Mods.camera_stats["mode"] = "first"
		for i in 6:
			await _wait(0.25)
			cp = c.global_position
			_look_at_point(cp + Vector3(0, 0.3, 0))
		await _shot(dir, "g13_animal_" + type)
		Mods.camera_stats.erase("mode")
		if type == "sheep":
			var before := _inv_total()
			Mods.set_slot("backpack", 20, {"item": "shears", "count": 1})
			player.select(7)
			var ctx := Mods.before("entity.interact", {"id": c.id, "type": "sheep", "item": "shears", "slot": 8})
			await _wait(2.0)
			print("STRZYŻENIE ostrzyżona=", c.data.get("sheared", false), " wełna na ziemi/plecaku: przed=", before, " po=", _inv_total())
			var hp := c.health
			c.hit(2.0, player.global_position, "test")
			print("UDERZENIE zdrowie owcy ", hp, " -> ", c.health, " stan=", c.state)

	# jaskinia: kolumna z pustką pod powierzchnią
	var cave := Vector3i(999999, 0, 0)
	for x in range(-60, 60, 3):
		for z in range(-60, 60, 3):
			var h := world.terrain.height(x, z)
			for y in range(h - 30, h - 6):
				if world.is_loaded(Vector3i(x, y, z)) and world.get_block(Vector3i(x, y, z)) == Blocks.AIR \
						and world.get_block(Vector3i(x, y + 1, z)) == Blocks.AIR and world.get_block(Vector3i(x, y - 1, z)) != Blocks.AIR:
					cave = Vector3i(x, y, z)
					break
			if cave.x != 999999:
				break
		if cave.x != 999999:
			break
	if cave.x != 999999:
		player.global_position = Vector3(cave.x + 0.5, cave.y + 0.05, cave.z + 0.5)
		player.velocity = Vector3.ZERO
		Mods.camera_stats["distance"] = 2.0
		player.pitch = -0.1
		await _wait(1.0)
		await _shot(dir, "g14_cave")
		var dark := world.light_at(Vector3(cave) + Vector3(0.5, 0.5, 0.5))
		# pochodnia obok gracza rozjaśnia jaskinię
		var tp := cave + Vector3i(2, 0, 0)
		if world.get_block(tp) != Blocks.AIR:
			tp = cave + Vector3i(0, 0, 2)
		world.set_block(tp, Blocks.id("torch"))
		await _wait(1.5)
		var lit := world.light_at(Vector3(cave) + Vector3(0.5, 0.5, 0.5))
		await _shot(dir, "g14b_cave_torch")
		Mods.camera_stats.erase("distance")
		print("JASKINIA w ", cave, " światło (niebo, bloki) bez pochodni=", dark, " z pochodnią=", lit)

	# noc z pochodniami
	var hz0 := world.terrain.height(0, 0)
	await _goto(0.5, hz0 + 2.0, 0.5)
	var tod := time_of_day
	time_of_day = 23.0
	_update_sky()
	var tbase := Vector3i(player.global_position.floor())
	for i in 4:
		var a := i * TAU / 4.0 + 0.4
		var x := tbase.x + roundi(cos(a) * 3.0)
		var z := tbase.z + roundi(sin(a) * 3.0)
		var ty := entities._surface(x, z, tbase.y + 4)
		if ty != -99999:
			world.set_block(Vector3i(x, ty + 1, z), Blocks.id("torch"))
	world.set_block(Vector3i(tbase.x + 4, entities._surface(tbase.x + 4, tbase.z, tbase.y + 4) + 1, tbase.z), Blocks.id("lamp"))
	await _wait(1.5)
	player.pitch = -0.35
	Mods.camera_stats["distance"] = 5.0
	await _wait(0.5)
	await _shot(dir, "g16_night_torches")
	Mods.camera_stats.erase("distance")
	time_of_day = tod
	_update_sky()

	# daleki widok z wysoka
	var hz := world.terrain.height(0, 0)
	Mods.player_stats["gravity"] = 0.0
	await _goto(0.5, hz + 30.0, 0.5)
	player.velocity = Vector3.ZERO
	player.pitch = -0.12
	player.yaw = 0.9
	await _wait(3.0)
	await _shot(dir, "g15_far_view")
	print("DALEKI WIDOK kafle=", far.tiles.size())
	Mods.player_stats.erase("gravity")
	player.respawn()


func _goto(x: float, y: float, z: float) -> void:
	player.global_position = Vector3(x, y, z)
	player.velocity = Vector3.ZERO
	player.frozen = true
	player.reset_fall()
	world.update_center(player.global_position)
	await _wait_loaded()


## Test klienta gry wieloosobowej: --login=konto --password=hasło [--register] [--stay=s] [--place]
func _autotest_client(dir: String) -> void:
	var opt := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--") and "=" in a:
			opt[a.substr(2, a.find("=") - 2)] = a.substr(a.find("=") + 1)
		elif a.begins_with("--"):
			opt[a.substr(2)] = true
	Settings.render_distance = 3
	_apply_settings()
	var t0 := Time.get_ticks_msec()
	while my_account == "" and not windows.has("login") and Time.get_ticks_msec() - t0 < 60000:
		await _wait(0.2)
	print("KLIENT ", Settings.player_name, " okno logowania=", windows.has("login"), " konto=", my_account)
	if windows.has("login"):
		await _wait(0.5)
		await _shot(dir, "mp_login_" + Settings.player_name)
		var w: ModWindow = windows["login"]
		w.inputs["login"].text = str(opt.get("login", Settings.player_name))
		w.inputs["password"].text = str(opt.get("password", "haslo"))
		w._press("accounts:" + ("register" if opt.has("register") else "enter"))
		t0 = Time.get_ticks_msec()
		while my_account == "" and Time.get_ticks_msec() - t0 < 20000:
			await _wait(0.2)
	print("KLIENT ", Settings.player_name, " zalogowany jako=", my_account)
	print("KLIENT mody=", Mods.loaded, " z serwera=", ModManager.server_mods.keys(), " blok crystal=", Blocks.id("crystal"))
	await _wait_loaded()
	await _wait(2.0)
	if opt.has("expect-projectiles"):
		var seen := {}
		for i in 30:
			await _wait(0.1)
			for id in projectiles.list:
				seen[id] = projectiles.list[id].pos
		print("KLIENT widziane pociski: ", seen.size(), " przykład lotu: ", seen.values().slice(0, 2))
	if opt.has("expect-cauldron"):
		await _wait(1.0)
		for ch in world.models.by_chunk.values():
			for p in ch:
				var m: BlockModel = ch[p]
				var lq: Array = m.tagged.get("liquid", [])
				var col := ""
				if not lq.is_empty():
					var mat: Variant = (lq[0] as MeshInstance3D).get_surface_override_material(0)
					if mat is StandardMaterial3D and mat.has_meta("base"):
						col = (mat.get_meta("base") as Color).to_html(false)
				print("KLIENT model kotła w ", p, " stan=", world.reg.state_of(m.block), " animacja=", m.loop_anim, " ciecz=", col)
	print("KLIENT pozycja=", player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " zdrowie=", player.health,
		" pasek[0]=", Mods.hotbar_item(0), " gracze=", players.keys().size())
	if opt.has("place"):
		player.pitch = -0.75
		player.select(0)
		await _wait(0.5)
		var t: Dictionary = player.target.duplicate()
		if not t.is_empty():
			var at: Vector3i = t.pos + t.normal
			player.use_item()
			await _wait(1.5)
			print("KLIENT postawił at=", at, " blok=", Blocks.key(world.get_block(at)), " pasek[0]=", Mods.hotbar_item(0))
			player.break_block()
			await _wait(1.5)
			print("KLIENT zniszczył at=", at, " blok=", Blocks.key(world.get_block(at)))
	if opt.has("say"):
		for t in str(opt.say).split("|"):
			send_chat(t)
			await _wait(1.0)
		print("KLIENT czat: ", chat.text_lines())
		print("KLIENT pogoda: ", weather.state(), " gracze z kapeluszem/przedmiotem: ", players.values().map(func(n): return [n.model.held_key, n.model.wear_nodes.size()] if n is RemotePlayer else []))
	if opt.has("walk"):
		player.global_position += Vector3(float(opt.walk), 1.0, 0.0)
		await _wait(1.0)
	if opt.has("walk-circle"):
		await _test_walk_circle(float(opt["walk-circle"]))
	if opt.has("measure-remote"):
		await _test_measure_remote(float(opt["measure-remote"]))
	var stay := float(opt.get("stay", "3"))
	var until := Time.get_ticks_msec() + int(stay * 1000)
	var shot_done := false
	while Time.get_ticks_msec() < until:
		await _wait(0.5)
		# patrzymy na najbliższego innego gracza, żeby nad głową pojawiła się nazwa
		for p in players:
			var other: Node3D = players[p]
			if other != player and other is RemotePlayer and other.visible:
				var d: Vector3 = other.global_position - player.global_position
				player.yaw = atan2(-d.x, -d.z)
				player.pitch = -0.1
				if not shot_done and d.length() < 30.0:
					Mods.camera_stats.erase("mode")
					player.first_person = true
					await _wait(3.0)
					await _shot(dir, "mp_view_" + Settings.player_name)
					print("KLIENT widzi gracza ", other.account, " odległość=", snappedf(d.length(), 0.1), " nazwa=", other.label.text, " widoczność=", snappedf(other.label.modulate.a, 0.01))
					shot_done = true
	print("KLIENT koniec ", Settings.player_name, " konto=", my_account, " pozycja=", player.global_position.snapped(Vector3(0.1, 0.1, 0.1)), " pasek[0]=", Mods.hotbar_item(0))
	Net.leave()
	await _wait(0.5)
	get_tree().quit()


## Test sieci: gracz chodzi w kółko (promień 6 bloków, 5 bloków/s) przez podany czas.
func _test_walk_circle(sec: float) -> void:
	var c := player.global_position + Vector3(-6.0, 0.0, 0.0)
	var a := 0.0
	var until := Time.get_ticks_msec() + int(sec * 1000)
	print("KLIENT ", Settings.player_name, " chodzi w kółko ", sec, " s")
	while Time.get_ticks_msec() < until:
		await get_tree().physics_frame
		a += 5.0 / 6.0 / Engine.physics_ticks_per_second
		player.global_position = c + Vector3(cos(a) * 6.0, 0.0, sin(a) * 6.0)
		player.velocity = Vector3(-sin(a), 0.0, cos(a)) * 5.0
		player.yaw = atan2(sin(a), -cos(a))


## Test sieci: jak równo porusza się u nas inny gracz (co klatkę ekranu). Przy ruchu w kółko
## ze stałą prędkością 5 bloków/s idealnie każda klatka przesuwa go o 5 * czas klatki.
func _test_measure_remote(sec: float) -> void:
	var other: RemotePlayer = null
	var t0 := Time.get_ticks_msec()
	while other == null and Time.get_ticks_msec() - t0 < 20000:
		for p in players:
			if players[p] is RemotePlayer:
				other = players[p]
		await _wait(0.1)
	if other == null:
		print("KLIENT płynność: brak innego gracza")
		return
	await _wait(1.0)
	var speeds := []
	var stalls := 0
	var max_step := 0.0
	var last := other.global_position
	var lt := Time.get_ticks_usec()
	var until := Time.get_ticks_msec() + int(sec * 1000)
	while Time.get_ticks_msec() < until:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := (now - lt) / 1000000.0
		lt = now
		var pos := other.global_position
		var step := Vector2(pos.x - last.x, pos.z - last.z).length()
		last = pos
		if dt <= 0.0:
			continue
		speeds.append(step / dt)
		max_step = maxf(max_step, step)
		if step < 0.0005:
			stalls += 1
	var n := speeds.size()
	var mean := 0.0
	for s in speeds:
		mean += s
	mean /= maxf(1, n)
	var var_sum := 0.0
	var off := 0
	for s in speeds:
		var_sum += (s - mean) * (s - mean)
		if absf(s - mean) > 0.5 * mean:
			off += 1
	var sd := sqrt(var_sum / maxf(1, n))
	print("KLIENT płynność: interpolacja=%s klatki=%d prędkość średnio %.2f bloków/s, odchylenie %.2f (%.0f%%), klatki odbiegające o >50%%: %.1f%%, klatki bez ruchu: %.1f%%, największy skok %.3f bloku" %
		["wyłączona" if NetInterp.disabled else "bufor %.2f s" % other.interp.delay, n, mean, sd, 100.0 * sd / maxf(0.001, mean), 100.0 * off / maxf(1, n), 100.0 * stalls / maxf(1, n), max_step])


## Test alchemii: blok z modelem GLB, stany, wygląd, animacje, cząsteczki, mikstury, wydajność wielu modeli.
func _test_alchemy(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Net.my_id()
	var hb := Mods.cid("hotbar")
	var reg := Mods.registry
	Mods.camera_stats.erase("mode")
	player.first_person = true
	var look := func(from: Vector3, at: Vector3) -> void:
		player.global_position = from
		player.velocity = Vector3.ZERO
		var d := at - (from + Vector3(0, 1.6, 0))
		player.yaw = atan2(-d.x, -d.z)
		player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	var use_on := func(p: Vector3i, item: String) -> void:
		Mods.set_slot(hb, 0, {"item": item, "count": 1} if item != "" else {})
		player.select(0)
		Mods.as_player(me, func(): return Mods.before("block.use", {"pos": p, "normal": Vector3i.UP, "block": world.get_block(p), "item": item, "slot": 1}))
	var state := func(p: Vector3i) -> String: return str(reg.state_of(world.get_block(p)).get("content", "?"))
	print("ALCH zestaw startowy: kocioł=", _count_item("cauldron"), " wiadra wody=", _count_item("water_bucket"), " butelki=", _count_item("glass_bottle"), " piec=", _count_item("furnace"), " skrzynie=", _count_item("chest"), " motyka=", _count_item("wooden_hoe"))
	# kocioł na płaskim miejscu obok gracza
	var c := Vector3i(player.global_position.floor()) + Vector3i(0, 0, -3)
	for y in range(c.y + 4, c.y - 6, -1):
		if (reg.props[world.get_block(Vector3i(c.x, y, c.z))] & Registry.SOLID) != 0:
			c.y = y + 1
			break
	world.set_block(c, reg.id_of("cauldron"))
	world.set_block(c + Vector3i(0, 1, 0), Blocks.AIR)
	await _wait(0.5)
	var m: BlockModel = world.models.model_at(c)
	var tris := 0
	if m:
		for n in m.find_children("*", "MeshInstance3D", true, false):
			var mi := n as MeshInstance3D
			for sidx in mi.mesh.get_surface_count():
				var ia: int = mi.mesh.surface_get_array_index_len(sidx)
				tris += (ia if ia > 0 else mi.mesh.surface_get_array_len(sidx)) / 3
	print("ALCH model=", m != null, " części=", m.parts.keys() if m else [], " trójkątów=", tris, " emitery=", m.emitters.keys() if m else [])
	use_on.call(c, "water_bucket")
	print("ALCH woda: ", state.call(c), " w ręce=", Mods.slot(hb, 0), " ciecz widoczna=", m.tagged["liquid"][0].visible)
	for it in ["feather", "flower_yellow", "ruby"]:
		use_on.call(c, it)
		await _wait(0.3)
	print("ALCH składniki=", world.logic.get_data(c).get("ingredients"), " kolor=", world.logic.looks.get(c, {}).get("colors"))
	use_on.call(c, "stick")
	await _wait(1.5)
	print("ALCH warzenie: ", state.call(c), " światło=", world.light_at(Vector3(c) + Vector3(0.5, 1.2, 0.5)), " emitery aktywne=", m.emitters.keys().filter(func(k): return m.emitters[k].emitting), " animacja=", m.loop_anim)
	look.call(Vector3(c) + Vector3(0.5, 0.0, 2.3), Vector3(c) + Vector3(0.5, 0.55, 0.5))
	await _wait(1.0)
	await _shot(dir, "a1_brewing_day")
	time_of_day = 22.5
	await _wait(1.0)
	await _shot(dir, "a2_brewing_night")
	time_of_day = 10.0
	await _wait(float(Mods.registry.defs[reg.id_of("cauldron")].get("brew", 10.0)) + 0.5)
	print("ALCH po warzeniu: ", state.call(c), " dane=", world.logic.get_data(c))
	await _shot(dir, "a3_ready")
	use_on.call(c, "glass_bottle")
	use_on.call(c, "glass_bottle")
	print("ALCH butelki: ", state.call(c), " plecak mikstur=", _count_item("potion_speed_strong"))
	var speed_before := float(player.stat("speed"))
	Mods.set_slot(hb, 1, {"item": "potion_speed_strong", "count": 1})
	Mods.as_player(me, func(): return Mods.before("item.use", {"item": "potion_speed_strong", "slot": 2}))
	await _wait(0.6)
	print("ALCH wypita: szybkość ", speed_before, " -> ", player.stat("speed"), " efekty=", Mods.shown_effects())
	# drugi mod spowalnia gracza (np. ciężka zbroja): modyfikatory się mnożą, a po końcu efektu wraca tylko spowolnienie
	Mods.as_player(me, func(): Mods._h_player_modify("speed", "test:zbroja", 0.0, 0.5))
	print("ALCH mikstura + zbroja: ", snappedf(float(player.stat("speed")), 0.01))
	Mods.as_player(me, func(): Mods._h_effect_remove("alchemy.speed"))
	print("ALCH koniec mikstury, zostaje zbroja: ", snappedf(float(player.stat("speed")), 0.01))
	Mods.as_player(me, func(): Mods._h_player_unmodify("speed", "test:zbroja"))
	print("ALCH bez niczego: ", snappedf(float(player.stat("speed")), 0.01), " efekty=", Mods.shown_effects())
	Mods.as_player(me, func(): Mods._h_effect_add("alchemy.jump", 3.0, 1.0))
	await _wait(3.5)
	print("ALCH efekt skoku po 3,5 s (trwał 3 s): ", Mods.shown_effects(), " skok=", player.stat("jump"))
	# nieudana mikstura: węgiel i piasek
	var c2 := c + Vector3i(2, 0, 0)
	world.set_block(c2, reg.id_of("cauldron"))
	world.set_block(c2 + Vector3i(0, 1, 0), Blocks.AIR)
	await _wait(0.3)
	use_on.call(c2, "water_bucket")
	use_on.call(c2, "coal")
	use_on.call(c2, "sand")
	use_on.call(c2, "stick")
	world.logic.scheduled[world.logic.scheduled.size() - 1][0] = world.logic.clock + 0.5
	await _wait(1.0)
	print("ALCH nieudana: ", state.call(c2))
	await _shot(dir, "a4_fail_smoke")

	# wydajność: 40 warzących kotłów naraz
	await _wait(1.0)
	var frame_ms := func(n: int) -> Array:
		var a := []
		for i in n:
			await get_tree().process_frame
			a.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		a.sort()
		return [a[n / 2], Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)]
	look.call(Vector3(c) + Vector3(0.5, 3.0, 9.0), Vector3(c) + Vector3(0.5, 0.0, -4.0))
	await _wait(1.0)
	BlockModel.force_fx = true
	var before: Array = await frame_ms.call(60)
	var brewing := reg.with_state(reg.id_of("cauldron"), {"content": "brewing"})
	var t0 := Time.get_ticks_usec()
	for i in 40:
		var q := c + Vector3i(-6 + (i % 8) * 2, 2 + (i / 8) % 2 * 0, -2 - (i / 8) * 2)
		world.set_block(q, brewing)
		world.logic.set_look(q, {"colors": {"liquid": ["#40c8f0", "#70e060", "#f04060", "#e8e8ff"][i % 4]}})
	var build_ms := (Time.get_ticks_usec() - t0) / 1000.0
	await _wait(2.0)
	var after: Array = await frame_ms.call(60)
	print("ALCH wydajność: 40 kotłów postawione w %.1f ms; klatka (logika) %.1f -> %.1f ms; wywołania rysowania %d -> %d; trójkąty %d -> %d" % [build_ms, before[0], after[0], before[1], after[1], before[2], after[2]])
	await _shot(dir, "a5_many")
	get_tree().quit()


func _test_projectiles_server() -> void:
	while true:
		await _wait(0.7)
		if remote_count() > 0:
			projectiles.spawn("apitest.block", {"position": Vector3(4, 30, 0), "direction": Vector3(0.3, 0.2, -1), "speed": 12.0, "data": {"block": "planks"}})


func _test_cauldron_server() -> void:
	while not (world.is_loaded(Vector3i(3, 0, 0)) and world.is_loaded(Vector3i(3, 31, 0)) and world.is_loaded(Vector3i(3, 40, 0))):
		await _wait(0.2)
	var c := Vector3i(3, 0, 0)
	for y in range(40, -20, -1):
		if (Mods.registry.props[world.get_block(Vector3i(3, y, 0))] & Registry.SOLID) != 0:
			c.y = y + 1
			break
	world.set_block(c, Mods.registry.with_state(Mods.registry.id_of("cauldron"), {"content": "brewing"}))
	world.logic.set_look(c, {"colors": {"liquid": "#70e060"}})
	print("SERWER kocioł w ", c)


## Test moda wędkarskiego (napisanego przez inne AI na podstawie docs/AI_MOD_SPEC.md).
func _test_fishing(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Net.my_id()
	var hb := Mods.cid("hotbar")
	var reg := Mods.registry
	print("RYBY wczytany=", Mods.loaded.has("fishing"), " błędy wczytania=", Mods.load_errors.get("fishing", "brak"))
	print("RYBY przedmioty: ", ["raw_fish", "cooked_fish", "fishing_rod"].map(func(k): return k + "=" + str(reg.items.has(k))))
	print("RYBY zestaw: wędka=", _count_item("fishing_rod"), " ryba=", _count_item("raw_fish"))
	# brzeg: blok stały obok wody
	var shore := Vector3i(0, -999, 0)
	var origin := Vector3i(player.global_position.floor())
	for r in range(1, 60):
		for dx in range(-r, r + 1):
			for dz in [-r, r]:
				for p in [origin + Vector3i(dx, 0, dz), origin + Vector3i(dz, 0, dx)]:
					for y in range(4, 16):
						var q := Vector3i(p.x, y, p.z)
						if reg.block_key(world.get_block(q)).begins_with("water") and (reg.props[world.get_block(q + Vector3i(1, 0, 0))] & Registry.SOLID) != 0:
							shore = q + Vector3i(1, 0, 0)
							break
					if shore.y != -999: break
				if shore.y != -999: break
			if shore.y != -999: break
		if shore.y != -999: break
	print("RYBY brzeg=", shore)
	var fish := func(pos: Variant) -> void:
		Mods.set_slot(hb, 0, {"item": "fishing_rod", "count": 1})
		var c := {"item": "fishing_rod", "slot": 1}
		if pos != null:
			c["pos"] = pos
			c["normal"] = Vector3i.UP
			c["block"] = world.get_block(pos)
		Mods.as_player(me, func(): return Mods.before("item.use", c))
	var before := _count_item("raw_fish")
	for i in 40:
		fish.call(shore)
		await _wait(0.06)
	print("RYBY 40 rzutów przy wodzie (bez czekania): złowiono ", _count_item("raw_fish") - before)
	before = _count_item("raw_fish")
	fish.call(Vector3i(origin.x + 200, 30, origin.z + 200))
	fish.call(null)
	print("RYBY z dala od wody i bez celu: ryb +", _count_item("raw_fish") - before)
	# piec
	var f := shore + Vector3i(0, 1, 2)
	world.set_block(f, reg.id_of("furnace"))
	Mods.as_player(me, func(): return Mods.before("block.use", {"pos": f, "normal": Vector3i.UP, "block": world.get_block(f), "item": "", "slot": 1}))
	var fc := "@%d,%d,%d" % [f.x, f.y, f.z]
	Mods.set_slot(fc, 0, {"item": "raw_fish", "count": 3})
	Mods.set_slot(fc, 1, {"item": "coal", "count": 1})
	Mods.as_player(me, func(): Mods.after("slot.click", {"container": fc, "index": 1, "right": false, "held": {}}))
	await _wait(17.0)
	print("RYBY piec po 17 s: wynik=", Mods.slot(fc, 2), " surowiec=", Mods.slot(fc, 0))
	_close_mod_window("furnace")
	# rzemiosło
	var g3 := Mods.cid("craft3")
	var out3 := Mods.cid("craft3_out")
	for i in 9:
		Mods.set_slot(g3, i, {})
	for i in [2, 4, 6]:
		Mods.set_slot(g3, i, {"item": "stick", "count": 1})
	for i in [5, 8]:
		Mods.set_slot(g3, i, {"item": "wool", "count": 1})
	Mods.as_player(me, func(): Mods.after("slot.click", {"container": "craft3", "index": 1}))
	print("RYBY stół: patyki + wełna -> ", Mods.slot(out3, 0), " (przepis wymaga przedmiotu 'string': istnieje=", reg.items.has("string"), ")")
	print("RYBY błędy modów: ", Mods.logs.filter(func(l): return str(l).contains("fishing")))
	get_tree().quit()


## Test moda „Blokomiot” (napisanego przez inne AI).
func _test_gun(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Net.my_id()
	var hb := Mods.cid("hotbar")
	var reg := Mods.registry
	print("GUN wczytany=", Mods.loaded.has("block_gun"), " błąd=", Mods.load_errors.get("block_gun", "brak"), " blok ammo_brick=", reg.id_of("ammo_brick"))
	print("GUN dźwięk 'base:sounds/pop.ogg' zarejestrowany=", Sfx.has("base:sounds/pop.ogg"))
	player.pitch = -0.8
	player.yaw = 0.0
	await _wait(0.5)
	var scen := func(label: String, slots: Array) -> void:
		for i in 8:
			Mods.set_slot(hb, i, slots[i] if i < slots.size() else {})
		await _wait(0.3)
		var t: Dictionary = player.target.duplicate()
		var at: Vector3i = t.pos + t.normal if not t.is_empty() else Vector3i.ZERO
		var gun_slot := 0
		for i in slots.size():
			if str(slots[i].get("item", "")) == "block_gun":
				gun_slot = i
		Mods.as_player(me, func(): return Mods.before("item.use", {"item": "block_gun", "slot": gun_slot + 1, "pos": t.get("pos"), "normal": t.get("normal")}))
		await _wait(0.3)
		var now := []
		for i in 8:
			var sl := Mods.slot(hb, i)
			now.append(("%s×%d" % [sl.item, sl.count]) if not sl.is_empty() else "-")
		print("GUN ", label, ": pasek po strzale=", now.slice(0, slots.size()), " blok w celu=", reg.block_key(world.get_block(at)))
		world.set_block(at, Blocks.AIR)
	await scen.call("A (blokomiot w 1. miejscu, cegły w 2.)", [{"item": "block_gun", "count": 1}, {"item": "ammo_brick", "count": 5}])
	await scen.call("B (patyk w 1., blokomiot w 2., ziemia w 3.)", [{"item": "stick", "count": 3}, {"item": "block_gun", "count": 1}, {"item": "dirt", "count": 5}])
	await scen.call("C (ziemia w 1., blokomiot w 2.)", [{"item": "dirt", "count": 5}, {"item": "block_gun", "count": 1}])
	print("GUN tekstura cegły: ", "brak pliku (fioletowa szachownica)" if not FileAccess.file_exists("res://mods/podstawowa/mods/base/textures/bricks.png") else "jest")
	get_tree().quit()


## Test API pocisków, celowania, opisów i danych przedmiotów (mod testowy apitest w user://mods).
func _test_api(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Net.my_id()
	var hb := Mods.cid("hotbar")
	print("API mod=", Mods.loaded.has("apitest"), " błąd=", Mods.load_errors.get("apitest", "brak"), " pociski=", Mods.registry.projectiles.keys())
	Mods.set_slot(hb, 0, {"item": "test_launcher", "count": 1, "data": {"ammo": 7}})
	print("API opis: ", Mods.registry.tooltip(Mods.slot(hb, 0)).replace("\n", " | "), "  dane=", Mods.slot(hb, 0).get("data"))
	# stosy z różnymi danymi się nie łączą
	Mods.set_slot(hb, 1, {"item": "planks", "count": 5, "data": {"kolor": "czerwony"}})
	Mods.local_held.clear()
	Mods.local_held.merge({"item": "planks", "count": 3, "data": {"kolor": "zielony"}})
	Mods.window_click(me, hb, 1, false)
	print("API łączenie różnych danych: miejsce=", Mods.slot(hb, 1), " w ręce=", Mods.local_held)
	Mods.local_held.clear()
	Mods.local_held.merge({"item": "planks", "count": 3, "data": {"kolor": "zielony"}})
	Mods.window_click(me, hb, 1, false)
	print("API łączenie tych samych danych: miejsce=", Mods.slot(hb, 1), " w ręce=", Mods.local_held)
	Mods.local_held.clear()
	# strzał prawie poziomo
	Mods.camera_stats.erase("mode")
	player.first_person = true
	player.select(0)
	player.yaw = 0.0
	player.pitch = 0.05
	await _wait(0.5)
	Mods.as_player(me, func(): return Mods.before("item.use", {"item": "test_launcher", "slot": 1}))
	await _wait(0.15)
	print("API celowanie: ", Mods._h_storage_get("apitest", "aim"), " pocisków w locie=", projectiles.list.size())
	await _wait(0.25)
	await _shot(dir, "p1_flight")
	await _wait(4.0)
	var hit: Dictionary = Mods._h_storage_get("apitest", "last_hit")
	print("API trafienie: ", hit, " pocisków w locie=", projectiles.list.size())
	if hit.has("place"):
		var pp := Vector3i(int(hit.place[0]), int(hit.place[1]), int(hit.place[2]))
		print("API blok w miejscu trafienia: ", Mods.registry.block_key(world.get_block(pp)), " odległość od gracza=", snappedf(Vector3(pp).distance_to(player.global_position), 0.1))
	# trafienie w owcę
	var front := player.global_position + Vector3(0, 0, -6)
	var sid: int = entities.spawn_creature("sheep", front, {}, 1.0)
	await _wait(0.4)
	var sheep: Creature = entities.get_entity(sid)
	sheep.set_physics_process(false)
	sheep.global_position = front
	var hp := sheep.health
	player.pitch = atan2((front.y + 0.6) - (player.global_position.y + 1.55), 6.0)
	await _wait(0.2)
	Mods.as_player(me, func(): return Mods.before("item.use", {"item": "test_launcher", "slot": 1}))
	await _wait(1.0)
	print("API strzał w owcę: ", Mods._h_storage_get("apitest", "last_hit"), " zdrowie owcy ", hp, " -> ", sheep.health if is_instance_valid(sheep) else "zginęła")
	var lh: Variant = Mods._h_storage_get("apitest", "last_hit")
	if lh is Dictionary and lh.has("entity"):
		var he := entities.get_entity(int(lh.entity))
		print("API trafione stworzenie: id=", lh.entity, " owca=", sid, " rodzaj=", he.type if he is Creature else "?")
	get_tree().quit()


func _test_console(dir: String) -> void:
	await _wait_loaded()
	if GameState.has_meta("reloaded"):
		print("KONSOLA po przeładowaniu: mody=", Mods.loaded.size(), " świat wczytany, gracz w ", player.global_position.snapped(Vector3.ONE))
		get_tree().quit()
		return
	var me := Mods.local_peer
	print("KONSOLA wynik: ", Mods.console_exec(me, "engine.player.position()"))
	print("KONSOLA tabela: ", Mods.console_exec(me, "engine.items.def('apple')"))
	print("KONSOLA instrukcja: ", Mods.console_exec(me, "x = 5"), " | potem: ", Mods.console_exec(me, "x * 2"))
	print("KONSOLA błąd: ", Mods.console_exec(me, "local t = nil; return t.pole"))
	print("KONSOLA /help: ", run_command(me, "/help").replace("\n", " | "))
	print("KONSOLA /cos: ", run_command(me, "/cos"))
	open_console()
	await _wait(0.3)
	await _shot(dir, "c1_console")
	console.close()
	GameState.set_meta("reloaded", true)
	print("KONSOLA /reload: ", run_command(me, "/reload"))


func _count_item(item: String) -> int:
	var n := 0
	for cn in ["hotbar", "backpack"]:
		for sl in Mods.container_slots(Mods.cid(cn)):
			if sl is Dictionary and str(sl.get("item", "")) == item:
				n += int(sl.count)
	return n


## Pomiar: ile kosztuje postawienie bloku (czas wywołania, najdłuższa klatka, czas do nowej siatki).
func _test_perf() -> void:
	await _wait_loaded()
	await _wait(2.0)
	var stone := Mods.registry.id_of("stone")
	var idle := []
	for i in 120:
		await get_tree().process_frame
		idle.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
	idle.sort()
	print("PERF bez zmian: klatka (logika) mediana %.1f ms, max %.1f ms" % [idle[60], idle[119]])
	var base := Vector3i(player.global_position.floor()) + Vector3i(2, 1, 0)
	world.apply_stats = {"full": 0, "light": 0, "us": 0}
	var calls := []
	var rebuild := []
	var worst := []
	for i in 30:
		var p := base + Vector3i(i % 6, i / 6, (i % 2) * 3)
		var t0 := Time.get_ticks_usec()
		var tl := Time.get_ticks_usec()
		world.set_block(p, stone if i % 3 != 2 else Blocks.AIR)
		calls.append((Time.get_ticks_usec() - t0) / 1000.0)
		var c := World.chunk_of(p)
		var max_frame := 0.0
		var t1 := Time.get_ticks_usec()
		while world.queued.has(c) or world.dirty.has(c):
			var f0 := Time.get_ticks_usec()
			await get_tree().process_frame
			max_frame = maxf(max_frame, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
			if Time.get_ticks_usec() - t1 > 2000000:
				break
		rebuild.append((Time.get_ticks_usec() - t1) / 1000.0)
		worst.append(max_frame)
		await _wait(0.1)
	var avg := func(a: Array) -> float:
		var sum := 0.0
		for x in a: sum += x
		return sum / maxf(1, a.size())
	print("PERF siatka: ", world.mesher_name, " wątki=", world.threaded)
	var st := world.apply_stats
	print("PERF przebudowy chunków na 30 zmian: z kolizją=%d, tylko światło=%d, wątek główny razem %.1f ms (%.2f ms na zmianę)" % [st.full, st.light, st.us / 1000.0, st.us / 30000.0])
	print("PERF set_block: średnio %.2f ms, max %.2f ms" % [avg.call(calls), calls.max()])
	print("PERF nowa siatka po: średnio %.1f ms, max %.1f ms" % [avg.call(rebuild), rebuild.max()])
	print("PERF najdłuższa klatka (logika) w tym czasie: średnio %.1f ms, max %.1f ms" % [avg.call(worst), worst.max()])
	get_tree().quit()


## Pomiar renderowania: zasięgi z --bench-radii (domyślnie 8,16), z cieniami i bez, obrót kamery o 360°.
## Wyniki: wiersze BENCH w konsoli i plik render_bench.json w folderze zrzutów. Opcje gracza nie są zapisywane.
func _test_render_bench(dir: String) -> void:
	var radii := [8, 16]
	var far_list := [Settings.far_view]
	var walk_speeds := []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--bench-walk="):
			walk_speeds = Array(a.trim_prefix("--bench-walk=").split(",")).map(func(s): return float(s))
		if a.begins_with("--bench-radii="):
			radii = Array(a.trim_prefix("--bench-radii=").split(",")).map(func(s): return int(s))
		if a.begins_with("--bench-far="):
			far_list = Array(a.trim_prefix("--bench-far=").split(",")).map(func(s): return int(s))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	if not "--bench-window" in OS.get_cmdline_user_args():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)
	var vp_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	time_of_day = 12.0
	await _wait_loaded()
	print("BENCH okno=", DisplayServer.window_get_size(), " renderer=", RenderingServer.get_current_rendering_method(), " karta=", RenderingServer.get_video_adapter_name(), " sterownik=", RenderingServer.get_video_adapter_api_version(), " siatka=", world.mesher_name, " wątki=", world.threaded)
	var pct := func(a: Array, p: float) -> float:
		var b := a.duplicate()
		b.sort()
		return b[clampi(int(p * (b.size() - 1)), 0, b.size() - 1)]
	var results := []
	for r in radii:
		for fv in far_list:
			for sh in [true, false]:
				Settings.render_distance = r
				Settings.far_view = fv
				Settings.shadows = sh
				_apply_settings()
				var t0 := Time.get_ticks_msec()
				var calm := 0
				# świat gotowy: nic w budowie ani w kolejce do wstawienia, wszystko w zasięgu zbudowane,
				# daleki widok policzony – i tak przez 2 s (szukanie brakujących chunków idzie co 1 s)
				while calm < 20 and Time.get_ticks_msec() - t0 < 240000:
					await _wait(0.1)
					var idle := world.queued.is_empty() and world.dirty.is_empty() and world.results.is_empty() \
							and not world._scan_missing and far.pending.is_empty()
					calm = calm + 1 if idle else 0
				var load_ms := Time.get_ticks_msec() - t0
				player.pitch = -0.12
				for i in 30:
					await get_tree().process_frame
				var n := 360
				var frame := []
				var logic := []
				var phys := []
				var cpu_r := []
				var gpu_r := []
				var draws := []
				var objs := []
				var prims := []
				var last := Time.get_ticks_usec()
				for i in n:
					player.yaw += TAU / n
					await get_tree().process_frame
					var now := Time.get_ticks_usec()
					frame.append((now - last) / 1000.0)
					last = now
					logic.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
					phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
					cpu_r.append(RenderingServer.viewport_get_measured_render_time_cpu(vp_rid) + RenderingServer.get_frame_setup_time_cpu())
					gpu_r.append(RenderingServer.viewport_get_measured_render_time_gpu(vp_rid))
					draws.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
					objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
					prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
				var bodies := 0
				for c in world.nodes:
					if is_instance_valid(world.nodes[c]) and world.nodes[c].get_node_or_null("Body") != null:
						bodies += 1
				var med: float = pct.call(frame, 0.5)
				var row := {
					"radius": r, "far_view": fv, "shadows": sh, "load_ms": load_ms,
					"fps_median": snappedf(1000.0 / maxf(med, 0.001), 0.1),
					"frame_ms_median": snappedf(med, 0.01), "frame_ms_p95": snappedf(pct.call(frame, 0.95), 0.01), "frame_ms_max": snappedf(pct.call(frame, 1.0), 0.01),
					"logic_ms": snappedf(pct.call(logic, 0.5), 0.01), "physics_ms": snappedf(pct.call(phys, 0.5), 0.01),
					"render_cpu_ms": snappedf(pct.call(cpu_r, 0.5), 0.01), "render_gpu_ms": snappedf(pct.call(gpu_r, 0.5), 0.01),
					"draw_calls": int(pct.call(draws, 0.5)), "draw_calls_max": int(pct.call(draws, 1.0)),
					"objects": int(pct.call(objs, 0.5)), "primitives": int(pct.call(prims, 0.5)),
					"chunk_meshes": world.nodes.size(), "water_meshes": world.water_nodes.size(), "collision_bodies": bodies,
					"far_tiles": far.tiles.size() if "tiles" in far else -1,
					"static_mem_mb": snappedf(Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
					"video_mem_mb": snappedf(Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, 0.1),
				}
				row["parts_ms"] = await _bench_parts(120)
				results.append(row)
				print("BENCH ", JSON.stringify(row))
				await _shot(dir, "bench_r%d_f%d_%s" % [r, fv, "cienie" if sh else "bez_cieni"])
				if sh:
					for v in walk_speeds:
						var w := await _bench_walk(r, fv, v, pct)
						results.append(w)
						print("BENCH ", JSON.stringify(w))
	_bench_write(dir, results)
	get_tree().quit()


func _bench_write(dir: String, results: Array) -> void:
	var f := FileAccess.open(dir.path_join("render_bench.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(results, "  "))


## Test szczelin między blokami: niebo jednolicie purpurowe (bez mgły), kamera nad terenem patrzy w dół
## w 8 kierunkach i z 2 wysokości; każdy purpurowy piksel w dolnych 55% obrazu to dziura w terenie.
## Porównanie ustawień: domyślne, bez cieni, bez MSAA, bez obu. Wiersze SEAMS w konsoli.
func _test_seams(dir: String) -> void:
	time_of_day = 12.0
	daynight = false
	await _wait_loaded()
	await _wait(1.0)
	Mods.camera_stats.erase("mode")
	player.first_person = true
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 0, 1)
	env.fog_enabled = false
	var vp := get_viewport()
	var base_msaa := vp.msaa_3d
	var start := player.global_position
	var views := []
	for h in [24.0, 4.0]:
		for i in 8:
			views.append([h, TAU * i / 8.0, -0.75 if h > 10.0 else -0.4])
	var configs := [["domyślne", true, base_msaa], ["bez_cieni", false, base_msaa], ["bez_msaa", true, Viewport.MSAA_DISABLED], ["bez_obu", false, Viewport.MSAA_DISABLED]]
	for cfg in configs:
		Settings.shadows = cfg[1]
		_apply_settings()
		env.fog_enabled = false
		vp.msaa_3d = cfg[2]
		var total := 0
		var worst := 0
		var per := []
		for vi in views.size():
			var v: Array = views[vi]
			for k in 4:
				player.global_position = start + Vector3(0, v[0], 0)
				player.velocity = Vector3.ZERO
				player.yaw = v[1]
				player.pitch = v[2]
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			var n := _count_magenta(img, 0.45)
			per.append(n)
			total += n
			if n > worst:
				worst = n
				img.save_png(dir.path_join("seams_%s_najgorszy.png" % cfg[0]))
			if vi == 2 or vi == 10:
				img.save_png(dir.path_join("seams_%s_widok%d.png" % [cfg[0], vi]))
		print("SEAMS %s: dziury razem %d pikseli, najgorszy widok %d, widoki %s" % [cfg[0], total, worst, str(per)])
	get_tree().quit()


## Test dalekiego widoku: z wysokości 40 bloków nad terenem, 4 kierunki, zasięg 8 i 16 (daleki widok 4).
## Zrzuty zwykłe i z purpurowym niebem; purpurowe piksele w pasie tuż pod horyzontem to prześwity.
func _test_farview(dir: String) -> void:
	time_of_day = 12.0
	daynight = false
	await _wait_loaded()
	Mods.camera_stats.erase("mode")
	player.first_person = true
	var start := Vector3(0.5, world.terrain.height(0, 0) + 40.0, 0.5)
	for r in [8, 16]:
		Settings.render_distance = r
		Settings.far_view = 4
		_apply_settings()
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < 90000:
			player.global_position = start
			player.velocity = Vector3.ZERO
			await _wait(0.5)
			if world.queued.is_empty() and far.pending.is_empty() and Time.get_ticks_msec() - t0 > 4000:
				break
		var holes := []
		for i in 4:
			for magenta in [false, true]:
				env.background_mode = Environment.BG_COLOR if magenta else Environment.BG_SKY
				env.background_color = Color(1, 0, 1)
				env.fog_enabled = not magenta
				for k in 4:
					player.global_position = start
					player.velocity = Vector3.ZERO
					player.yaw = TAU * i / 4.0 + 0.4
					player.pitch = -0.12
					await get_tree().process_frame
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				if magenta:
					# pas od ok. 3/4 drogi środek–horyzont do środka ekranu: tylko teren (daleki widok)
					var h := img.get_height()
					var band := img.get_region(Rect2i(0, int(h * 0.45), img.get_width(), int(h * 0.05)))
					holes.append(_count_magenta(band, 0.0))
				img.save_png(dir.path_join("far_r%d_%d%s.png" % [r, i, "_m" if magenta else ""]))
		print("FARVIEW zasięg=%d kafle=%d wywołania=%d prześwity=%s" % [r, far.tiles.size(), Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME), str(holes)])
	env.background_mode = Environment.BG_SKY
	get_tree().quit()


## Liczba czysto purpurowych pikseli w dolnej części obrazu (od from_y * wysokość w dół).
static func _count_magenta(img: Image, from_y: float) -> int:
	img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var data := img.get_data()
	var n := 0
	for y in range(int(h * from_y), h):
		var row := y * w * 4
		for x in w:
			var i := row + x * 4
			if data[i] > 200 and data[i + 1] < 60 and data[i + 2] > 200:
				n += 1
	return n


## Mediana czasów części klatki (ms): skrypty main/world/far, fizyka.
func _bench_parts(n: int) -> Dictionary:
	var acc := {}
	for i in n:
		await get_tree().process_frame
		var d := world.prof.duplicate()
		d["main_process"] = prof_main_ms
		d["physics"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		d["process_total"] = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		for k in d:
			if not acc.has(k):
				acc[k] = []
			acc[k].append(float(d[k]))
	var out := {}
	for k in acc:
		var a: Array = acc[k]
		a.sort()
		out[k] = snappedf(a[a.size() / 2], 0.01)
	return out


## Gracz przesuwany w linii prostej (+x) z prędkością v bloków/s przez 15 s, 30 bloków nad startem.
func _bench_walk(r: int, fv: int, v: float, pct: Callable) -> Dictionary:
	var start := player.global_position
	var y := start.y + 30.0
	var frame := []
	var collect := []
	var applied := []
	var apply_ms := []
	var worst_parts := {}
	var worst := 0.0
	var dist := 0.0
	var last := Time.get_ticks_usec()
	var t_end := Time.get_ticks_msec() + 15000
	var s0: Dictionary = world.apply_stats.duplicate()
	player.pitch = -0.12
	player.yaw = -PI / 2.0   # patrzy w +x
	while Time.get_ticks_msec() < t_end:
		var st0: int = world.apply_stats.full + world.apply_stats.light
		var us0: int = world.apply_stats.us
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var ms := (now - last) / 1000.0
		last = now
		dist += v * ms / 1000.0
		player.global_position = Vector3(start.x + dist, y, start.z)
		player.velocity = Vector3.ZERO
		frame.append(ms)
		collect.append(float(world.prof.get("collect", 0.0)))
		applied.append(world.apply_stats.full + world.apply_stats.light - st0)
		apply_ms.append((world.apply_stats.us - us0) / 1000.0)
		if ms > worst:
			worst = ms
			worst_parts = world.prof.duplicate()
			worst_parts["main_process"] = prof_main_ms
			worst_parts["physics"] = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
			worst_parts["applied_chunks"] = applied[-1]
	var slow := frame.filter(func(x): return x > 33.3).size()
	var tsv := Time.get_ticks_usec()
	save_game(false)   # zapis po przejściu (jak autozapis): ile trwa w wątku głównym
	last_save["total_ms"] = (Time.get_ticks_usec() - tsv) / 1000.0
	# średni koszt jednego wstawionego chunka w wątku głównym, w częściach (ms)
	var s1: Dictionary = world.apply_stats
	var nch := maxi(1, int(s1.full) + int(s1.light) - int(s0.full) - int(s0.light))
	var split := {"chunks": nch}
	for k in ["pre_us", "mesh_us", "coll_us", "gen_us", "light_us", "us"]:
		split[k.trim_suffix("_us")] = snappedf((int(s1.get(k, 0)) - int(s0.get(k, 0))) / 1000.0 / nch, 0.01)
	var med: float = pct.call(frame, 0.5)
	return {
		"walk_speed": v, "radius": r, "far_view": fv, "shadows": true, "frames": frame.size(),
		"fps_median": snappedf(1000.0 / maxf(med, 0.001), 0.1), "fps_avg": snappedf(frame.size() / 15.0, 0.1),
		"frame_ms_median": snappedf(med, 0.01), "frame_ms_p95": snappedf(pct.call(frame, 0.95), 0.01), "frame_ms_p99": snappedf(pct.call(frame, 0.99), 0.01), "frame_ms_max": snappedf(worst, 0.01),
		"frames_over_33ms_pct": snappedf(100.0 * slow / maxf(1, frame.size()), 0.1),
		"collect_ms_median": snappedf(pct.call(collect, 0.5), 0.01), "collect_ms_p95": snappedf(pct.call(collect, 0.95), 0.01),
		"chunks_applied_per_frame_p95": pct.call(applied, 0.95), "chunks_applied_max": pct.call(applied, 1.0),
		"apply_ms_p95": snappedf(pct.call(apply_ms, 0.95), 0.01),
		"queued_end": world.queued.size(), "worst_frame_parts": worst_parts, "apply_ms_per_chunk": split, "last_save": last_save,
	}



## Test logiki bloków: skrzynia (kierunek, kontener), piec (dane, plan, świecenie), uprawy (losowe, sąsiad), dźwięki.
## Postawy i animacje gracza: kucanie przy krawędzi, pełzanie pod niskim stropem, siedzenie, bieg, seria ataków.
func _test_anim(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	time_of_day = 11.0
	var reg := Mods.registry
	var o := Vector3i(player.global_position.floor())
	o.y -= 1
	# platforma 5 x 5 nad przepaścią i tunel o wysokości 1 bloku
	for x in range(-8, 9):
		for z in range(-8, 9):
			for y in range(-4, 5):
				world.set_block(o + Vector3i(x, y, z), Blocks.AIR)
	for x in range(-2, 3):
		for z in range(-2, 3):
			world.set_block(o + Vector3i(x, 0, z), reg.id_of("stone"))
	for z in range(-2, 3):
		world.set_block(o + Vector3i(2, 2, z), reg.id_of("planks"))   # strop nad x = 2 (szczelina 1 blok)
	player.teleport(Vector3(o) + Vector3(0.5, 1.05, 0.5))
	await _wait(0.6)
	# kucanie: idziemy w stronę krawędzi (na zachód) i nie spadamy
	player.yaw = PI / 2
	Input.action_press("dismount")
	Input.action_press("move_forward")
	await _wait(2.0)
	Input.action_release("move_forward")
	print("POSTAWA kucanie: ", player.pose, " wysokość=", player.body_shape.size.y, " nad platformą=", snappedf(player.global_position.y - o.y, 0.01), " x=", snappedf(player.global_position.x - o.x, 0.01))
	Mods.camera_stats["side"] = 2.2
	await _wait(0.3)
	await _shot(dir, "a1_crouch_edge")
	Input.action_release("dismount")
	# pełzanie pod strop
	var ev := InputEventAction.new()
	ev.action = "crawl"
	ev.pressed = true
	player._unhandled_input(ev)
	await _wait(0.4)
	player.teleport(Vector3(o) + Vector3(1.5, 1.05, 0.5))
	player.yaw = -PI / 2   # na wschód, pod strop
	Input.action_press("move_forward")
	await _wait(1.0)
	Input.action_release("move_forward")
	print("POSTAWA pełzanie: ", player.pose, " wysokość=", player.body_shape.size.y, " x=", snappedf(player.global_position.x - o.x, 0.01))
	player._unhandled_input(ev)   # próba wstania pod stropem
	await _wait(0.3)
	print("POSTAWA pod stropem po X: ", player.pose, " (powinno zostać pełzanie)")
	await _shot(dir, "a2_crawl")
	player.teleport(Vector3(o) + Vector3(-0.5, 1.05, 0.5))
	await _wait(0.4)
	print("POSTAWA po wyjściu spod stropu: ", player.pose)
	# siedzenie
	var es := InputEventAction.new()
	es.action = "sit"
	es.pressed = true
	player._unhandled_input(es)
	await _wait(0.8)
	print("POSTAWA siad: ", player.pose)
	await _shot(dir, "a3_sit")
	player._unhandled_input(es)
	# bieg
	await _wait(0.3)
	player.teleport(Vector3(o) + Vector3(-1.5, 1.05, 0.5))
	for z in range(-8, 9):
		for x in range(-8, 9):
			world.set_block(o + Vector3i(x, 0, z), reg.id_of("stone"))
	await _wait(0.3)
	player.yaw = 0.0
	Input.action_press("sprint")
	Input.action_press("move_forward")
	await _wait(0.6)
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	print("POSTAWA bieg: sprint=", player.sprinting, " prędkość=", snappedf(v, 0.1))
	await _shot(dir, "a4_run")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	# seria ataków na owcę
	await _wait(0.4)
	var sid := entities.spawn_creature("sheep", player.global_position + Vector3(0, 0.2, -2.0))
	var sh: Creature = entities.get_entity(sid)
	sh.set_physics_process(false)
	Mods.camera_stats.erase("side")
	Mods.camera_stats["mode"] = "first"
	player.pitch = -0.25
	await _wait(0.3)
	var stages := []
	var hp := [sh.health]
	print("ATAKI cel: ", player.entity_target(), " blok=", player.target.get("pos"), " owca w ", sh.global_position, " gracz ", player.global_position)
	for i in 3:
		player.start_digging()
		player.stop_digging()
		stages.append(player.combo)
		await _wait(0.16)
		if i == 2:
			Mods.camera_stats.erase("mode")
			await _wait(0.05)
			await _shot(dir, "a5_attack3")
		await _wait(0.2)
		hp.append(sh.health if is_instance_valid(sh) else -1.0)
	print("ATAKI etapy=", stages, " zdrowie owcy=", hp, " akcje wysłane=", player.act_n)
	Mods.camera_stats.erase("side")
	Mods.camera_stats.erase("mode")
	get_tree().quit()


## Rozdzielczość tekstur: ściana z marmuru (blok 128 px) obok kamienia i desek.
func _test_hires(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var reg := Mods.registry
	print("HIRES domyślna=", reg.texture_res, " atlas=", reg.atlas_size, " mipmapy=", reg.max_lod)
	time_of_day = 11.0
	var o := Vector3i(player.global_position.floor()) + Vector3i(0, 0, -4)
	for x in range(-4, 5):
		for y in range(0, 4):
			var b := "marble_tiles" if absi(x) <= 1 else ("stone" if x < 0 else "planks")
			world.set_block(o + Vector3i(x, y, 0), reg.id_of(b))
	for x in range(-4, 5):
		for z in range(-3, 0):
			world.set_block(o + Vector3i(x, -1, z + 1), reg.id_of("marble_tiles"))
	Mods.camera_stats["mode"] = "first"
	player.yaw = 0.0
	player.pitch = 0.0
	await _wait(1.5)
	await _shot(dir, "h1_near_%d" % reg.texture_res)
	var far_z := o.z + 20
	var gy := world.terrain.height(o.x, far_z)
	player.teleport(Vector3(o.x + 0.5, maxi(gy + 1, o.y) + 0.1, far_z + 0.5))
	player.pitch = -0.05
	await _wait(1.5)
	await _shot(dir, "h2_far_%d" % reg.texture_res)
	get_tree().quit()


## Dodatki: tłumaczenia, dane przedmiotu na ziemi, wersje zależności, pogoda i niebo, przedmiot w ręce, kapelusz.
func _test_extras(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Mods.local_peer
	# tłumaczenia
	print("I18N koń=", Mods.registry.entities.get("horse", {}).get("name", "?"), " pl=", Mods.translate("horses", "tamed", "pl"),
		" en=", Mods.translate("horses", "tamed", "en"), " brak=", Mods.translate("horses", "nie_ma", "en"))
	print("I18N engine.t: ", Mods.console_exec(me, "return engine.t('x')"))
	# dane przedmiotu po wyrzuceniu i podniesieniu
	Mods.set_slot(Mods.cid("backpack"), 26, {})   # wolne miejsce (zestawy startowe wielu modów zapełniają plecak)
	var id := entities.drop_item("stone", 1, player.global_position + Vector3(0.5, 1.0, 0), {"ammo": 5, "owner": "test"})
	await _wait(1.5)
	var found := {}
	for c in ["hotbar", "backpack"]:
		for sl in Mods.container_slots(Mods.cid(c)):
			if sl is Dictionary and sl.get("data") is Dictionary and sl.data.has("ammo"):
				found = sl
	print("DANE przedmiot na ziemi=", entities.get_entity(id) != null, " w plecaku=", found)
	# wersje zależności
	print("WERSJE ", ModManager.version_ok("1.2.3", ">=", "1.2"), ModManager.version_ok("1.2.3", "^", "2.0"), ModManager.version_ok("0.3.9", "~", "0.3.1"),
		ModManager.version_ok("0.4.0", "~", "0.3.1"), " ", ModManager.dep_parse("modkit >= 0.2"))
	var keep: Array = ModManager.manifests["horses"].get("requires", [])
	ModManager.manifests["horses"]["requires"] = ["modkit>=9.0"]
	Mods.load_errors.erase("horses")
	Mods.resolve_load_order()
	print("WERSJE błąd: ", Mods.load_errors.get("horses", ""))
	ModManager.manifests["horses"]["requires"] = keep
	Mods.load_errors.erase("horses")
	# przedmiot w ręce i kapelusz
	Mods.set_slot(Mods.cid("hotbar"), 0, {"item": "iron_sword" if Mods.registry.items.has("iron_sword") else "torch", "count": 1})
	player.select(0)
	Mods.as_player(me, func(): Mods.press_bind("emotes:hat"))
	await _wait(0.4)
	print("RĘKA ", player.model.held_key, " kapelusz części=", player.model.wear_nodes.size())
	# pogoda
	time_of_day = 12.0
	Mods.console_exec(me, "engine.weather.set('rain', 1)")
	await _wait(7.0)
	print("POGODA ", weather.state(), " siła=", snappedf(weather.intensity, 0.01), " deszcz=", weather.rain.emitting if weather.rain else "brak okna", " mgła=", snappedf(env.fog_density / fog_base, 0.01))
	await _shot(dir, "e1_rain_hat")
	set_weather({"kind": "storm", "intensity": 1.0, "instant": true})
	Mods.console_exec(me, "engine.sky.set({ top = '#4a2a5a', horizon = '#c0603a', sun = 0.6 })")
	await _wait(1.0)
	await _shot(dir, "e2_storm_sky")
	Mods.console_exec(me, "engine.weather.set('clear') engine.sky.reset()")
	await _wait(1.0)
	print("POGODA po: ", weather.state())
	get_tree().quit()


## Generator świata w Lua (mod ruins): ruiny, głazy, kryształy; zapisy przez granice chunków.
func _test_worldgen(dir: String) -> void:
	await _wait_loaded()
	await _wait(1.0)
	var reg := Mods.registry
	var bricks := reg.id_of("bricks")
	var ruby := reg.id_of("ruby_ore")
	var counts := {"bricks": 0, "ruby_ore": 0}
	var ruin_at := Vector3i(0, -999, 0)
	for c in world.data:
		var d: PackedByteArray = world.data[c]
		counts.bricks += d.count(bricks)
		counts.ruby_ore += d.count(ruby)
		var i := d.find(bricks)
		if i >= 0 and ruin_at.y == -999:
			ruin_at = c * World.S + Vector3i(i % World.S, (i / World.S) % World.S, i / (World.S * World.S))
	for q in world.queued:
		print("GEN w kolejce ", q, " built=", world.built.has(q), " data=", world.data.has(q), " pending=", world.gen_pending.has(q), " dirty=", world.dirty.has(q))
	print("GEN generatory=", Mods.worldgen_mods.keys(), " chunki=", world.data.size(), " zmienione=", world.edited.size(), " zaległe=", world.gen_pending.size(), " bloki=", counts)
	# los i szum zależą tylko od ziarna
	print("GEN los: ", Mods.console_exec(Mods.local_peer, "local r = engine.worldgen.random('test') return r:int(1, 1000000) .. ' ' .. r:int(1, 1000000)"),
		" / ", Mods.console_exec(Mods.local_peer, "local r = engine.worldgen.random('test') return r:int(1, 1000000) .. ' ' .. r:int(1, 1000000)"),
		" szum: ", Mods.console_exec(Mods.local_peer, "return engine.worldgen.noise(10, 20, 16, 'a')"))
	if ruin_at.y != -999:
		player.teleport(Vector3(ruin_at) + Vector3(-6, 4, -6))
		var to := Vector3(ruin_at) - player.global_position
		player.yaw = atan2(-to.x, -to.z)
		player.pitch = -0.35
		await _wait(2.0)
		await _shot(dir, "w1_ruin")
	get_tree().quit()


## Bogatsze okna (mod handbook): zakładki, lista z ikonami, obrazek, suwak, przełącznik, lista rozwijana;
## element ekranu w wybranym miejscu (kompas u góry).
func _test_ui(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.8)
	var me := Mods.local_peer
	print("UI kompas na ekranie: ", Mods.hud.has("handbook.compass"), " ", Mods.hud.get("handbook.compass", {}).get("text", ""))
	Mods.press_bind("handbook:open")
	await _wait(0.5)
	print("UI okno=", windows.has("handbook"))
	Mods.as_player(me, func(): Mods.window_action("handbook:items", {"tab": 1, "items": 5}))
	await _wait(0.5)
	var w: ModWindow = windows.get("handbook")
	print("UI pola okna: ", w._fields() if w else {})
	await _shot(dir, "u1_items")
	Mods.as_player(me, func(): Mods.window_action("handbook:tab", {"tab": 3, "compass": true, "alpha": 0.6, "place": 3}))
	await _wait(0.5)
	w = windows.get("handbook")
	print("UI zakładka 3 pola: ", w._fields() if w else {}, " kompas: ", Mods.hud.get("handbook.compass", {}).get("anchor", ""))
	await _shot(dir, "u2_settings")
	_close_mod_window("handbook")
	await _wait(0.4)
	await _shot(dir, "u3_hud")
	get_tree().quit()


## Czat i polecenia: wiadomość, /help, /give, /time, /tp, polecenie moda, hak chat.message.
func _test_chat(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	Mods.console_exec(Mods.local_peer, "engine.hooks.before('chat.message', function(c) c.text = c.text:gsub('brzydkie', '***') end)")
	send_chat("Cześć wszystkim! brzydkie słowo")
	send_chat("/help")
	var before := _inv_total()
	send_chat("/give stone 5")
	print("CZAT /give: przedmiotów ", before, " -> ", _inv_total())
	send_chat("/time night")
	print("CZAT /time: ", time_of_day)
	var y0 := player.global_position.y
	send_chat("/tp ~ ~3 ~")
	print("CZAT /tp: wysokość +", snappedf(player.global_position.y - y0, 0.01))
	send_chat("/zombie")
	send_chat("/kon")
	send_chat("/nieznane")
	send_chat("/me macha ręką")
	await _wait(0.5)
	print("CZAT linie: ", chat.text_lines())
	print("CZAT polecenia modów: ", Mods.mod_commands.keys(), " rola=", role_of(Mods.local_peer))
	time_of_day = 12.0
	chat.open_input("/gi")
	await _wait(0.5)
	await _shot(dir, "ch1_chat")
	chat.close_input()
	get_tree().quit()


## Stworzenia: jazda na koniu, wrogie zombie z modelem GLB, mózg w Lua (płonięcie w słońcu).
func _test_creatures(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Mods.local_peer
	print("STWORZENIA rodzaje=", Mods.registry.entities.keys(), " mózgi=", Mods.entity_brains.keys())
	time_of_day = 10.0
	# płaski teren wokół gracza
	var reg := Mods.registry
	var o := Vector3i(player.global_position.floor())
	o.y -= 1
	for x in range(-10, 11):
		for z in range(-10, 11):
			world.set_block(o + Vector3i(x, 0, z), reg.id_of("grass"))
			for y in range(1, 5):
				world.set_block(o + Vector3i(x, y, z), Blocks.AIR)
	player.teleport(Vector3(o) + Vector3(0.5, 1.05, 0.5))
	for id in entities.entities.keys():
		if entities.entities[id] is Creature:
			entities.remove(id)
	await _wait(0.6)
	# koń: oswojony (dane), wsiadanie przez kliknięcie, szybsza jazda, zsiadanie
	var h := entities.spawn_creature("horse", Vector3(o) + Vector3(2.5, 1.1, 0.5))
	entities.get_entity(h).data["tame"] = true
	var speed0 := float(player.stat("speed"))
	Actions.interact(player, entities, entities.get_entity(h))
	await _wait(0.3)
	print("JAZDA wsiadł=", player.mount_id == h, " jeździec=", (entities.get_entity(h) as Creature).rider, " prędkość ", speed0, " -> ", player.stat("speed"), " siodło=", player.mount_seat)
	var start := player.global_position
	player.yaw = PI / 2   # na zachód
	Input.action_press("move_forward")
	await _wait(1.5)
	Input.action_release("move_forward")
	var horse_node := entities.get_entity(h)
	print("JAZDA przejechał=", snappedf(start.distance_to(player.global_position), 0.1), " m w 1.5 s, koń przy graczu=", snappedf(horse_node.global_position.distance_to(player.global_position), 0.01))
	Mods.camera_stats["side"] = 2.6
	Mods.camera_stats["distance"] = 4.5
	player.pitch = -0.3
	await _wait(0.8)
	await _shot(dir, "c1_horse_ride")
	Mods.camera_stats.erase("side")
	Mods.camera_stats.erase("distance")
	player.request_dismount()
	await _wait(0.3)
	print("JAZDA zsiadł=", player.mount_id == -1, " prędkość=", player.stat("speed"), " koń wolny=", (horse_node as Creature).rider == -1)
	# zombie: noc, gonienie i atak, animacje z pliku GLB
	time_of_day = 23.0
	player.teleport(Vector3(o) + Vector3(4.5, 1.05, 0.5))
	await _wait(0.3)
	var z := entities.spawn_creature("zombie", Vector3(o) + Vector3(-3.5, 1.2, 0.5))
	var zn := entities.get_entity(z) as Creature
	print("ZOMBIE model GLB: animacje=", zn.anim_player.get_animation_list() if zn.anim_player else "brak", " części=", zn.parts.size())
	var hp0 := float(player.health)
	player.yaw = PI / 2
	player.pitch = -0.1
	await _wait(1.5)
	print("ZOMBIE stan=", zn.state, " cel=", zn.target_peer, " animacja=", zn.anim_player.current_animation if zn.anim_player else "")
	await _shot(dir, "c2_zombie_chase")
	await _wait(3.5)
	print("ZOMBIE zdrowie gracza ", hp0, " -> ", player.health, " animacja=", zn.anim_player.current_animation if zn.anim_player else "")
	print("ZOMBIE odległość=", snappedf(zn.global_position.distance_to(player.global_position), 0.01), " pozycje ", zn.global_position, player.global_position, " cd=", zn.attack_cd, " stan=", zn.state, " has_target=", zn.has_target)
	Mods.camera_stats["side"] = 2.5
	await _wait(0.5)
	await _shot(dir, "c3_zombie_attack")
	Mods.camera_stats.erase("side")
	# mózg w Lua: w dzień zombie płonie
	player.set_health(20.0)
	player.teleport(player.global_position + Vector3(30, 0, 0))
	time_of_day = 12.0
	var hz0 := zn.health
	await _wait(3.0)
	print("ZOMBIE w słońcu: zdrowie ", hz0, " -> ", zn.health if is_instance_valid(zn) else -1.0)
	get_tree().quit()


## Kształty z prostopadłościanów (mod building): stawianie schodów i półbloków, celowanie, chodzenie po nich.
func _test_shapes(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var reg := Mods.registry
	var hb := Mods.cid("hotbar")
	print("KSZTAŁTY bloki=", reg.count(), " schody=", reg.id_of("planks_stairs"), " półblok=", reg.id_of("stone_slab"))
	# płaska scena: podłoga z kamienia, powietrze nad nią
	var o := Vector3i(floori(player.global_position.x) + 4, 0, floori(player.global_position.z))
	o.y = floori(player.global_position.y) - 1
	for x in range(-6, 7):
		for z in range(-6, 7):
			world.set_block(o + Vector3i(x, 0, z), reg.id_of("stone"))
			for y in range(1, 6):
				world.set_block(o + Vector3i(x, y, z), Blocks.AIR)
	await _wait(0.5)
	# stawianie przez gracza: schody patrzą tam, gdzie gracz (północ), półblok pod sufitem jest górny
	player.global_position = Vector3(o) + Vector3(0.5, 1.0, 3.5)
	player.velocity = Vector3.ZERO
	Mods.set_slot(hb, 0, {"item": "planks_stairs", "count": 5})
	player.select(0)
	player.yaw = 0.0
	player.pitch = -0.6
	await _wait(0.4)
	var at: Vector3i = player.target.pos + player.target.normal if not player.target.is_empty() else Vector3i(0, -999, 0)
	player.use_item()
	await _wait(0.3)
	print("KSZTAŁTY schody: ", reg.block_key(world.get_block(at)), " stan=", reg.state_of(world.get_block(at)))
	# celowanie w półblok: trafienie w górną ściankę na wysokości 0.5
	var s1 := o + Vector3i(3, 1, 0)
	world.set_block(s1, reg.id_of("stone_slab"))
	var r := world.raycast(Vector3(s1) + Vector3(0.5, 3.0, 0.5), Vector3.DOWN, 6.0)
	print("KSZTAŁTY trafienie w półblok: pos=", r.get("pos"), " normal=", r.get("normal"), " y=", snappedf((r.point as Vector3).y - s1.y, 0.01) if r.has("point") else -1)
	print("KSZTAŁTY górny półblok: ", reg.block_key(Actions.oriented(reg.id_of("stone_slab"), 0.0, Vector3i.DOWN)),
		" boczna ściana wysoko: ", reg.block_key(Actions.oriented(reg.id_of("stone_slab"), 0.0, Vector3i(1, 0, 0), Vector3(0, 5.8, 0))))
	# chodzenie po półbloku: gracz spada na niego i stoi pół bloku wyżej niż na podłodze
	player.global_position = Vector3(s1) + Vector3(0.5, 2.0, 0.5)
	player.velocity = Vector3.ZERO
	await _wait(1.2)
	print("KSZTAŁTY gracz na półbloku: y nad podłogą=", snappedf(player.global_position.y - s1.y, 0.01))
	# scena: płot, murek, szyby (łączą się), schody z czterech stron, stolik
	var fence := reg.id_of("planks_fence")
	for x in range(-5, 0):
		world.set_block(o + Vector3i(x, 1, -4), fence)
	world.set_block(o + Vector3i(-5, 1, -3), fence)
	world.set_block(o + Vector3i(-5, 1, -2), fence)
	for x in range(1, 5):
		world.set_block(o + Vector3i(x, 1, -4), reg.id_of("cobblestone_wall"))
	for x in range(-2, 1):
		world.set_block(o + Vector3i(x, 1, -2), reg.id_of("glass_pane"))
		world.set_block(o + Vector3i(x, 2, -2), reg.id_of("glass_pane"))
	var st := reg.id_of("stone_stairs")
	for k in 4:
		world.set_block(o + Vector3i(-4 + k, 1, 1), reg.with_state(st, {"facing": ["north", "east", "south", "west"][k]}))
		world.set_block(o + Vector3i(-4 + k, 2, 2), reg.with_state(st, {"facing": ["north", "east", "south", "west"][k], "half": "top"}))
	for k in 4:
		world.set_block(o + Vector3i(1 + k, 1, 1), reg.with_state(reg.id_of("bricks_slab"), {"half": "bottom" if k % 2 == 0 else "top"}))
	world.set_block(o + Vector3i(2, 1, -1), reg.id_of("planks_table"))
	await _wait(1.0)
	player.global_position = Vector3(o) + Vector3(0.5, 1.0, 6.5)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.pitch = -0.35
	await _wait(0.8)
	await _shot(dir, "s1_shapes")
	player.global_position = Vector3(o) + Vector3(-6.0, 1.0, 4.5)
	player.yaw = -0.9
	player.pitch = -0.3
	await _wait(0.8)
	await _shot(dir, "s2_shapes_side")
	# ikony w pasku
	for i in 6:
		Mods.set_slot(hb, i, {"item": ["planks_stairs", "stone_slab", "planks_fence", "glass_pane", "cobblestone_wall", "planks_table"][i], "count": 8})
	await _wait(0.4)
	await _shot(dir, "s3_icons")
	get_tree().quit()


func _test_blocks(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Net.my_id()
	var hb := Mods.cid("hotbar")
	var reg := Mods.registry
	print("BLOKI mody=", Mods.loaded, " bloki=", reg.count())
	var place := func(item: String, yaw: float) -> Vector3i:
		Mods.set_slot(hb, 0, {"item": item, "count": 5})
		player.select(0)
		player.yaw = yaw
		player.pitch = -0.9
		await _wait(0.4)
		if player.target.is_empty():
			return Vector3i(0, -999, 0)
		var at: Vector3i = player.target.pos + player.target.normal
		player.use_item()
		await _wait(0.4)
		return at
	var key_at := func(p: Vector3i) -> String: return reg.block_key(world.get_block(p))

	# skrzynia: przodem do gracza
	var c1: Vector3i = await place.call("chest", 0.0)
	var dir_name := str(reg.state_of(world.get_block(c1)).get("facing", "?"))
	print("SKRZYNIA ", key_at.call(c1), " facing=", dir_name, " (gracz patrzy na północ, więc przód na południe)")
	Mods.as_player(me, func(): return Mods.before("block.use", {"pos": c1, "normal": Vector3i.UP, "block": world.get_block(c1), "item": "", "slot": 1}))
	var cid := "@%d,%d,%d" % [c1.x, c1.y, c1.z]
	print("SKRZYNIA okno=", windows.has("chest"), " kontener=", Mods.containers.has(cid), " miejsc=", Mods.container_slots(cid).size())
	Mods.set_slot(cid, 3, {"item": "ruby", "count": 7})
	await _wait(0.3)
	await _shot(dir, "b1_chest_window")
	_close_mod_window("chest")
	var drops_before := entities.entities.size()
	Actions.break_at(player, world, c1)
	await _wait(0.3)
	print("SKRZYNIA zniszczona: kontener=", Mods.containers.has(cid), " nowe przedmioty na ziemi=", entities.entities.size() - drops_before)

	# piec: dane bloku, zaplanowane aktualizacje, wariant „lit” świeci
	var f1: Vector3i = await place.call("furnace", PI / 2)
	print("PIEC ", key_at.call(f1), " stan=", reg.state_of(world.get_block(f1)))
	Mods.as_player(me, func(): return Mods.before("block.use", {"pos": f1, "normal": Vector3i.UP, "block": world.get_block(f1), "item": "", "slot": 1}))
	var fc := "@%d,%d,%d" % [f1.x, f1.y, f1.z]
	Mods.set_slot(fc, 0, {"item": "raw_iron", "count": 2})
	Mods.set_slot(fc, 1, {"item": "coal", "count": 1})
	Mods.as_player(me, func(): Mods.after("slot.click", {"container": fc, "index": 1, "right": false, "held": {}}))
	await _wait(3.0)
	var lit_key: String = key_at.call(f1)
	var front := f1 + Vector3i(1, 0, 0)
	print("PIEC po 3 s: ", lit_key, " dane=", world.logic.get_data(f1), " światło obok=", world.light_at(Vector3(front) + Vector3(0.5, 0.5, 0.5)))
	await _shot(dir, "b2_furnace_window")
	_close_mod_window("furnace")
	Mods.camera_stats.erase("mode")
	player.first_person = true
	var look := func(from: Vector3, at: Vector3) -> void:
		player.global_position = from
		player.velocity = Vector3.ZERO
		var d := at - (from + Vector3(0, 1.6, 0))
		player.yaw = atan2(-d.x, -d.z)
		player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	time_of_day = 22.5
	look.call(Vector3(f1) + Vector3(3.5, 0.0, 0.5), Vector3(f1) + Vector3(0.5, 0.5, 0.5))
	await _wait(1.5)
	await _shot(dir, "b3_furnace_lit_night")
	time_of_day = 10.0
	await _wait(9.0)
	print("PIEC po 12 s: wynik=", Mods.slot(fc, 2), " surowiec=", Mods.slot(fc, 0), " ", key_at.call(f1))

	# uprawy: motyka, nasiona, wzrost (przyspieszamy losowe aktualizacje), sąsiad
	var soil := Vector3i(f1.x - 3, 0, f1.z + 3)
	soil.y = f1.y - 1
	# szukamy powierzchni trawy w pobliżu
	for y in range(f1.y + 3, f1.y - 6, -1):
		var b: String = key_at.call(Vector3i(soil.x, y, soil.z))
		if b == "grass" or b == "dirt":
			soil.y = y
			break
	world.set_block(soil + Vector3i(0, 1, 0), Blocks.AIR)
	world.set_block(soil, reg.id_of("grass"))
	Mods.set_slot(hb, 0, {"item": "wooden_hoe", "count": 1})
	player.select(0)
	Mods.as_player(me, func(): return Mods.before("item.use", {"item": "wooden_hoe", "slot": 1, "pos": soil, "normal": Vector3i.UP, "block": world.get_block(soil)}))
	print("UPRAWY po motyce: ", key_at.call(soil))
	Mods.set_slot(hb, 0, {"item": "seeds", "count": 3})
	Mods.as_player(me, func(): return Mods.before("item.use", {"item": "seeds", "slot": 1, "pos": soil, "normal": Vector3i.UP, "block": world.get_block(soil)}))
	var crop := soil + Vector3i(0, 1, 0)
	print("UPRAWY zasiane: ", key_at.call(crop), " nasion=", Mods.slot(hb, 0))
	for id in reg.count():
		if reg.block_key(reg.base_of(id)) == "wheat_crop":
			world.logic.random_rate[id] = 0.4
	await _wait(6.0)
	print("UPRAWY po wzroście: ", key_at.call(crop))
	# rząd upraw w każdym wieku na wilgotnym polu (normalna szybkość wzrostu)
	for id in reg.count():
		if reg.block_key(reg.base_of(id)) == "wheat_crop":
			world.logic.random_rate[id] = 30.0
	var moist := reg.with_state(reg.id_of("farmland"), {"moist": true})
	for i in 4:
		var q := soil + Vector3i(i + 1, 0, 0)
		world.set_block(q + Vector3i(0, 1, 0), Blocks.AIR)
		world.set_block(q, moist)
		world.set_block(q + Vector3i(0, 1, 0), reg.with_state(reg.id_of("wheat_crop"), {"age": i}))
	look.call(Vector3(soil) + Vector3(3.0, 1.0, 3.2), Vector3(soil) + Vector3(3.0, 1.2, 0.5))
	await _wait(1.5)
	await _shot(dir, "b4_crop")
	var before_e := entities.entities.size()
	world.set_block(soil, reg.id_of("stone"))
	await _wait(0.5)
	print("UPRAWY pole zamienione w kamień: uprawa=", key_at.call(crop), " łup=", entities.entities.size() - before_e)

	# zapis danych bloków i odczyt
	world.logic.set_data(f1, "test", 42)
	world.logic.save(GameState.current_dir)
	var copy := BlockLogic.new(world, self)
	copy.load_from(GameState.current_dir)
	print("ZAPIS dane=", copy.get_data(f1).get("test"), " kontenery=", copy.containers.size(), " plan=", copy.scheduled.size())
	print("DŹWIĘKI zarejestrowane=", reg.sounds.size(), " stone.break plików=", Sfx._load("stone.break").size(), " sheep.say=", Sfx._load("sheep.say").size(), " chest.open=", Sfx._load("chest.open").size())
	get_tree().quit()


## Test rzemiosła: siatka 3x3 (kilof), lustrzana siekiera, bezkształtne deski, warsztat odkrywczy.
func _test_craft(dir: String) -> void:
	await _wait_loaded()
	await _wait(0.5)
	var me := Net.my_id()
	var g3 := Mods.cid("craft3")
	var out3 := Mods.cid("craft3_out")
	print("CRAFT mody=", Mods.loaded)
	if Mods.containers.has(g3):
		var put := func(cells: Dictionary) -> void:
			for i in 9:
				Mods.set_slot(g3, i, cells.get(i, {}))
			Mods.as_player(me, func(): Mods.after("slot.click", {"container": "craft3", "index": 1}))
		put.call({0: {"item": "cobblestone", "count": 3}, 1: {"item": "cobblestone", "count": 1}, 2: {"item": "cobblestone", "count": 1},
			4: {"item": "stick", "count": 2}, 7: {"item": "stick", "count": 1}})
		print("CRAFT kilof wynik=", Mods.slot(out3, 0))
		Mods.as_player(me, func(): return Mods.before("block.use", {"pos": Vector3i(0, 10, 0), "normal": Vector3i.UP, "block": Blocks.id("crafting_table"), "item": "", "slot": 1}))
		await _wait(0.5)
		await _shot(dir, "craft_table")
		_close_mod_window("crafting_table")
		Mods.window_click(me, out3, 0, false)
		print("CRAFT po kliknięciu trzymany=", Mods.local_held, " pole0=", Mods.slot(g3, 0), " pole4=", Mods.slot(g3, 4), " pole7=", Mods.slot(g3, 7), " wynik=", Mods.slot(out3, 0))
		Mods.local_held.clear()
		# siekiera w lustrzanym odbiciu (MM / SM / S_) i deski z pnia w dowolnym polu
		put.call({0: {"item": "planks", "count": 1}, 1: {"item": "planks", "count": 1}, 3: {"item": "stick", "count": 1}, 4: {"item": "planks", "count": 1}, 6: {"item": "stick", "count": 1}})
		print("CRAFT siekiera lustrzana wynik=", Mods.slot(out3, 0))
		put.call({8: {"item": "log", "count": 5}})
		print("CRAFT deski wynik=", Mods.slot(out3, 0))
		put.call({0: {"item": "dirt", "count": 1}, 4: {"item": "sand", "count": 1}})
		print("CRAFT brak przepisu wynik=", Mods.slot(out3, 0))
		# zamknięcie okna stołu: przedmioty z siatki wracają do plecaka
		put.call({8: {"item": "log", "count": 5}})
		var before_inv := _inv_total()
		Mods.window_closed(me, "crafting_table")
		print("CRAFT zamknięcie siatka=", Mods.slot(g3, 8), " plecak +", _inv_total() - before_inv)
	var forge := Mods.cid("forge")
	if Mods.containers.has(forge):
		var bench := Blocks.id("workbench")
		Mods.as_player(me, func(): return Mods.before("block.use", {"pos": Vector3i(0, 10, 0), "normal": Vector3i.UP, "block": bench, "item": "", "slot": 1}))
		print("ODKRYCIE okno warsztatu=", windows.has("workbench"))
		Mods.set_slot(forge, 0, {"item": "log", "count": 2})
		var inv := _inv_total()
		Mods.window_action("crafting_discovery:forge")
		print("ODKRYCIE wykuwanie, pola=", Mods.slot(forge, 0))
		await _wait(2.5)
		print("ODKRYCIE deski: plecak +", _inv_total() - inv, " (2 pnie → 8 desek + premia 4)")
		Mods.set_slot(forge, 0, {"item": "cobblestone", "count": 1})
		Mods.set_slot(forge, 1, {"item": "stick", "count": 1})
		Mods.window_action("crafting_discovery:forge")
		await _wait(0.3)
		var w: ModWindow = windows.get("workbench")
		var msg := ""
		if w:
			for c in w.content.get_children():
				if c is Label or c is RichTextLabel:
					msg += c.text.left(60) + " | "
		print("ODKRYCIE złe ilości, okno: ", msg)
		await _shot(dir, "craft_workbench")
	get_tree().quit()


func _autotest(dir: String) -> void:
	if OS.get_cmdline_user_args().has("--light-only"):
		await _test_light(dir)
		return
	if OS.get_cmdline_user_args().has("--craft-only"):
		await _test_craft(dir)
		return
	if OS.get_cmdline_user_args().has("--console-only"):
		await _test_console(dir)
		return
	if OS.get_cmdline_user_args().has("--api-only"):
		await _test_api(dir)
		return
	if OS.get_cmdline_user_args().has("--gun-only"):
		await _test_gun(dir)
		return
	if OS.get_cmdline_user_args().has("--fishing-only"):
		await _test_fishing(dir)
		return
	if OS.get_cmdline_user_args().has("--alchemy-only"):
		await _test_alchemy(dir)
		return
	if OS.get_cmdline_user_args().has("--perf-only"):
		await _test_perf()
		return
	if OS.get_cmdline_user_args().has("--render-bench"):
		await _test_render_bench(dir)
		return
	if OS.get_cmdline_user_args().has("--seams-only"):
		await _test_seams(dir)
		return
	if OS.get_cmdline_user_args().has("--farview-only"):
		await _test_farview(dir)
		return
	if OS.get_cmdline_user_args().has("--blocks-only"):
		await _test_blocks(dir)
		return
	if OS.get_cmdline_user_args().has("--creatures-only"):
		await _test_creatures(dir)
		return
	if OS.get_cmdline_user_args().has("--anim-only"):
		await _test_anim(dir)
		return
	if OS.get_cmdline_user_args().has("--hires-only"):
		await _test_hires(dir)
		return
	if OS.get_cmdline_user_args().has("--extras-only"):
		await _test_extras(dir)
		return
	if OS.get_cmdline_user_args().has("--worldgen-only"):
		await _test_worldgen(dir)
		return
	if OS.get_cmdline_user_args().has("--ui-only"):
		await _test_ui(dir)
		return
	if OS.get_cmdline_user_args().has("--chat-only"):
		await _test_chat(dir)
		return
	if OS.get_cmdline_user_args().has("--shapes-only"):
		await _test_shapes(dir)
		return
	Settings.render_distance = 4
	_apply_settings()
	await _wait_loaded()
	await _wait(1.0)
	await _shot(dir, "g1_start")

	print("MODS loaded=", Mods.loaded, " errors=", Mods.load_errors, " binds=", Mods.binds.size())
	print("REJESTR bloki=", Mods.registry.count(), " przedmioty=", Mods.registry.items.size(), " biomy=", world.terrain.biome_names)
	# kopanie i stawianie przez haki modów (plecak dostaje łup bloku, stawianie zużywa przedmiot)
	player.pitch = -0.75
	await _wait(0.3)
	var target: Dictionary = player.target.duplicate()
	var before_inv := _inv_total()
	player.break_block()
	await _wait(0.4)
	var dug: Vector3i = target.get("pos", Vector3i.ZERO)
	print("BREAK pos=", dug, " now=", world.get_block(dug), " plecak przed=", before_inv, " po=", _inv_total())
	player.select(0)
	var planks_before := int(Mods.hotbar_item(0).get("count", 0))
	var place_at: Vector3i = player.target.pos + player.target.normal if not player.target.is_empty() else Vector3i.ZERO
	player.use_item()
	await _wait(0.4)
	print("PLACE at=", place_at, " block=", Blocks.key(world.get_block(place_at)), " deski przed=", planks_before, " po=", int(Mods.hotbar_item(0).get("count", 0)))
	var stone_try := Mods.before("block.break", {"pos": dug, "block": Blocks.id("stone"), "drops": []})
	print("DESTRUCTIBLE kamień anulowany=", stone_try.get("cancel", false))
	# przetrwanie: upadek zadaje obrażenia, jedzenie przy pełnym żołądku jest anulowane
	var hp := player.health
	Mods.emit_event("player.land", {"fall": 6.0, "speed": 12.0})
	print("FALL zdrowie przed=", hp, " po=", player.health)
	Mods.set_slot("hotbar", 2, {"item": "apple", "count": 3})
	var eat := Mods.before("item.use", {"item": "apple", "slot": 3})
	print("ITEM.USE jabłko anulowane (pełny żołądek)=", eat.get("cancel", false))
	Mods.press_bind("backpack:toggle")
	await _wait(0.8)
	await _shot(dir, "g5_backpack")
	if windows.has("character"):
		windows["character"]._click("hotbar", 0, false)
		windows["character"]._click("backpack", 4, false)
		await _wait(0.4)
		await _shot(dir, "g6_backpack_moved")
		windows["character"].close()
	await _wait(0.3)
	var n := world.save_all()
	var check := World.new()
	check.save_dir = GameState.current_dir
	check._load_chunk(World.chunk_of(dug))
	var d: Variant = check.data.get(World.chunk_of(dug))
	var l := dug - World.chunk_of(dug) * World.S
	print("SAVE chunks=", n, " reloaded_block=", Blocks.key(d[l.x + 32 * (l.y + 32 * l.z)]) if d != null else "brak")
	check.free()

	# wystawa nowych bloków przed graczem, gest i tryby kamery
	var p0 := Vector3i(player.global_position.floor())
	var show := ["glass", "bricks", "cobblestone", "coal_ore", "iron_ore", "ruby_ore"]
	var fwd := Vector3i(roundi(-sin(player.yaw) * 3), 0, roundi(-cos(player.yaw) * 3))
	var side := Vector3i(roundi(cos(player.yaw)), 0, roundi(-sin(player.yaw)))
	for i in show.size():
		var id := Blocks.id(show[i])
		if id > 0:
			world.set_block(p0 + fwd + side * (i - 2) + Vector3i(0, 1, 0), id)
			world.set_block(p0 + fwd + side * (i - 2) + Vector3i(0, 2, 0), id)
	var cc := World.chunk_of(p0 + fwd + Vector3i(0, 1, 0))
	var vc_before: int = (world.nodes[cc].mesh as ArrayMesh).surface_get_array_len(0) if world.nodes.has(cc) else -1
	await _wait(1.0)
	var vc_after: int = (world.nodes[cc].mesh as ArrayMesh).surface_get_array_len(0) if world.nodes.has(cc) else -1
	print("REMESH chunk ", cc, " wierzchołki przed=", vc_before, " po=", vc_after, " blok=", Blocks.key(world.get_block(p0 + fwd + Vector3i(0, 1, 0))))
	player.pitch = -0.2
	Mods.press_bind("emotes:wave")
	await _wait(0.5)
	await _shot(dir, "g7_blocks_wave")
	for m in ["shoulder", "top"]:
		Mods.press_bind("emotes:camera")
		await _wait(0.8)
		await _shot(dir, "g8_camera_" + m)
	Mods.camera_stats.erase("mode")

	# rudy w załadowanych chunkach
	var ore_counts := {}
	for k in ["coal_ore", "iron_ore", "ruby_ore"]:
		var id := Blocks.id(k)
		for c in world.data:
			ore_counts[k] = ore_counts.get(k, 0) + (world.data[c] as PackedByteArray).count(id)
	print("ORES ", ore_counts)

	await _test_stage5(dir)

	# struktura (ruiny albo studnia)
	var st := _find_structure()
	if st.x != 999999:
		await _goto(st.x + 6.5, st.y + 4.0, st.z + 6.5)
		await _wait(0.8)
		Mods.camera_stats["distance"] = 8.0
		player.yaw = 0.8
		player.pitch = -0.6
		await _wait(0.6)
		await _shot(dir, "g9_structure")
		Mods.camera_stats.erase("distance")
		print("STRUCTURE at ", st, " biom ", world.terrain.biome_name(world.terrain.column(st.x, st.z).y))
	else:
		print("STRUCTURE nie znaleziono")

	# wycieczka po biomach
	for b in world.terrain.nb:
		var at := _find_biome(b)
		if at.x == 999999:
			print("BIOME ", world.terrain.biome_name(b), " nie znaleziono")
			continue
		var h := world.terrain.height(at.x, at.y)
		await _goto(at.x + 0.5, h + 2.0, at.y + 0.5)
		await _wait(0.8)
		Mods.camera_stats["distance"] = 9.0
		player.pitch = -0.3
		player.yaw = 0.8
		await _wait(0.6)
		await _shot(dir, "g2_biome_%d" % b)
		Mods.camera_stats.erase("distance")
		print("BIOME ", world.terrain.biome_name(b), " at ", at)

	# zmierzch (dzień i noc)
	if daynight:
		time_of_day = 18.6
		_update_sky()
		await _wait(0.5)
		await _shot(dir, "g3_dusk")
		time_of_day = 10.0
		_update_sky()

	open_pause()
	await _wait(0.5)
	await _shot(dir, "g4_pause")
	close_pause()
	print("FPS ", Engine.get_frames_per_second(), " ", world.stats())
	get_tree().quit()
