extends Node
## Środowisko uruchomieniowe modów w Lua.
## Jeden stan Lua, w nim każdy mod ma własne, odizolowane środowisko (_ENV) z obiektem `engine`.
## Dwie fazy:
##   1. content – pliki "content" z mod.json rejestrują bloki, przedmioty, biomy, struktury i animacje.
##      Ta faza działa też w menu (np. lista bloków w ustawieniach). Na jej końcu powstaje Registry.
##   2. scripts – pliki "scripts" uruchamiane po zbudowaniu świata i gracza (haki, zdarzenia, okna).
## Mody ładują się w kolejności z menedżera modów; mody z "requires" czekają na swoje zależności.

signal ui_window_requested(spec: Dictionary)
signal ui_close_requested(id: String)
signal notified(text: String)
signal binds_changed
signal hotbar_changed
signal hud_changed

const LIBS := 1 | 4 | 8 | 32 | 64 | 128 | 4096 | 8192  # base, coroutine, string, math, table, debug (tylko dla strażnika w prelude), utf8, typy Godota
const MAX_ERRORS_SHOWN := 5

var lua: Object = null
var _api: Dictionary = {}   # funkcje z prelude.lua: dispatch, make_env, input, window_action, finalize
var _envs := {}             # id moda -> środowisko Lua

var main: Node = null
var registry: Registry = null
var order: Array[String] = []
var loaded: Array[String] = []
var load_errors := {}   # id moda -> tekst błędu przy wczytywaniu
var logs: Array[String] = []
var _errors_shown := 0
var _hooks := {}        # "before:block.break" -> true, gdy jakiś mod podpiął hak

var containers := {}    # id -> {"owner": String, "persist": bool, "slots": Array[Dictionary]}
var storage := {}       # id moda -> Dictionary
var binds: Array = []   # [{"id", "mod", "key", "label"}]
var hotbar := {"container": "", "first": 0, "count": 0}
var open_windows := {}  # id -> spec
var player_stats := {}  # statystyki gracza lokalnego po modyfikatorach (interfejs i ruch czytają wprost)
signal effects_changed
var client_effects := {}  # klient: efekty od serwera (do wyświetlenia)


## Efekty do pokazania na ekranie tego gracza.
func shown_effects() -> Dictionary:
	if Net.is_client():
		return client_effects
	var s: Session = sessions.get(local_peer)
	return s.effects if s else {}
var camera_stats := {}  # nadpisania kamery przez mody
var anim_overrides := {}  # stan postaci ("idle", "walk", "jump") -> nazwa animacji
var model_colors := {}    # część postaci -> Color
var hud := {}             # id -> {"type": "bar"|"text", ...}

var _rng := RandomNumberGenerator.new()
var _menu_registry: Registry = null


func _ready() -> void:
	ModManager.changed.connect(func(): _menu_registry = null)


func available() -> bool:
	return ClassDB.class_exists("LuaState")


func is_running() -> bool:
	return lua != null


# ---------- uruchamianie i zatrzymywanie ----------

## Faza 1: tworzy stan Lua, wykonuje pliki content wszystkich modów i buduje rejestr treści.
func start_content(world_dir: String) -> Registry:
	stop()
	_load_data(world_dir)
	order = resolve_load_order()
	var content := {}
	if not available():
		load_errors["_"] = "Brak środowiska Lua w tej wersji gry."
	elif _open_lua():
		for id in order:
			_run_files(id, "content")
		var res: Variant = _api.finalize.invoke()
		if _is_error(res):
			report_error("silnik", "rejestr treści: " + str(res))
		elif res is Dictionary:
			content = res
	registry = Registry.new()
	var paths := {}
	for id in ModManager.manifests:
		paths[id] = ModManager.manifests[id].path
	var tr := texture_resolution(int(content.get("texture_resolution", 16)))
	registry.build(content, paths, tr.x, tr.y)
	Sfx.reset()
	for e in registry.errors:
		report_error("silnik", e)
	Blocks.reg = registry
	_migrate_slots()
	return registry


## Faza 2: skrypty modów; wywoływane, gdy świat i gracz już istnieją.
func start_scripts(main_node: Node) -> void:
	main = main_node
	if lua == null:
		return
	for id in order:
		if not load_errors.has(id):
			_run_files(id, "scripts")
	for id in order:
		if not load_errors.has(id):
			loaded.append(id)
			_log(id, "wczytany")
	emit_event("world_ready", {})


## Rejestr dla menu (lista bloków w ustawieniach): faza content w osobnym, tymczasowym stanie Lua.
func menu_registry() -> Registry:
	if _menu_registry == null:
		var keep_main := main
		_menu_registry = start_content("")
		stop()
		main = keep_main
		Blocks.reg = _menu_registry
	return _menu_registry


func _open_lua() -> bool:
	lua = ClassDB.instantiate("LuaState")
	lua.open_libraries(LIBS)
	lua.globals["host"] = lua.create_table(_host_table())
	var code := FileAccess.get_file_as_string("res://scripts/mods/prelude.lua")
	var res: Variant = lua.do_string(code, "@prelude.lua")
	if not _is_table(res):
		load_errors["_"] = "Błąd prelude: %s" % str(res)
		push_error(load_errors["_"])
		lua = null
		return false
	for k in ["dispatch", "make_env", "input", "window_action", "finalize", "run_chunk", "block_update", "projectile_hit", "item_tooltip", "console", "entity_think", "command", "worldgen"]:
		_api[k] = res.get(k)
	return true


## Rozdzielczość kafelków: (domyślna, największa dozwolona). Opcja gracza ustawia ją na sztywno (także jako
## górną granicę dla bloków z własną rozdzielczością); „automatycznie” bierze największą z modów
## (engine.textures.resolution) i włączonych paczek zasobów. Przeglądarka: najwyżej 32.
func texture_resolution(requested: int) -> Vector2i:
	var cap := 32 if OS.has_feature("web") else 512
	var forced := int(Settings.texture_resolution)
	if forced > 0:
		var f := mini(Registry.pow2(forced), cap)
		return Vector2i(f, f)
	var r := requested
	for id in ModManager.resource_order:
		r = maxi(r, ModManager.resource_resolution(id))
	return Vector2i(mini(Registry.pow2(maxi(r, 16)), cap), cap)


func stop() -> void:
	_api = {}
	_envs.clear()
	lua = null
	main = null
	order.clear()
	loaded.clear()
	load_errors.clear()
	logs.clear()
	containers.clear()
	storage.clear()
	binds.clear()
	open_windows.clear()
	player_stats.clear()
	camera_stats.clear()
	anim_overrides.clear()
	model_colors.clear()
	hud.clear()
	_hooks.clear()
	entity_brains.clear()
	mod_commands.clear()
	worldgen_mods.clear()
	lang_tables.clear()
	_gen_noises.clear()
	hotbar.container = ""
	hotbar.first = 0
	hotbar.count = 0
	local_held.clear()
	sessions.clear()
	per_player.clear()
	pstorage.clear()
	dirty_containers.clear()
	ctx = 1
	_errors_shown = 0


## Kolejność wczytywania: kolejność gracza (lub serwera), ale moda z zależnościami
## wczytujemy dopiero po nich. Brakujące albo wyłączone zależności zgłaszamy jako błąd.
func resolve_load_order() -> Array[String]:
	var wanted: Array[String] = []
	for id in ModManager.effective_order():
		if ModManager.is_enabled(id):
			wanted.append(id)
	var out: Array[String] = []
	var pending := wanted.duplicate()
	var progress := true
	while progress and not pending.is_empty():
		progress = false
		for id in pending.duplicate():
			var reqs: Array = ModManager.manifests[id].get("requires", [])
			var missing := []
			var waiting := false
			var bad_ver := []
			for req in reqs:
				var r: String = ModManager.dep_parse(str(req))[0]
				var rr := ModManager.replacement_of(r)
				if rr != "" and wanted.has(rr):
					r = rr   # zależność od modułu zastąpionego innym modem
				if not wanted.has(r):
					missing.append(r)
				elif not out.has(r):
					waiting = true
				var vp: String = ModManager.dep_version_problem(str(req))
				if vp != "":
					bad_ver.append(vp)
			if not bad_ver.is_empty():
				load_errors[id] = "wymaga innej wersji: " + ", ".join(bad_ver)
				pending.erase(id)
				progress = true
				continue
			# "after": mody opcjonalne – jeśli są włączone, wczytujemy je wcześniej
			for r0 in ModManager.manifests[id].get("after", []) + ModManager.manifests[id].get("replaces", []):
				var r: String = str(r0)
				if ModManager.replacement_of(r) != "" and ModManager.replacement_of(r) != id:
					r = ModManager.replacement_of(r)
				if wanted.has(r) and not out.has(r) and r != id:
					waiting = true
			var clash := []
			for c in ModManager.manifests[id].get("conflicts", []):
				if wanted.has(str(c)) and (out.has(str(c)) or pending.has(str(c))):
					clash.append(str(c))
			if not clash.is_empty() and not out.has(id):
				# z pary wykluczających się wczytuje się ten wcześniej na liście
				if out.has(clash[0]) or wanted.find(clash[0]) < wanted.find(id):
					load_errors[id] = "nie działa razem z: " + ", ".join(clash)
					pending.erase(id)
					progress = true
					continue
			if not missing.is_empty():
				load_errors[id] = "wymaga wyłączonych lub brakujących modów: " + ", ".join(missing)
				pending.erase(id)
				progress = true
			elif not waiting:
				out.append(id)
				pending.erase(id)
				progress = true
	for id in pending:
		load_errors[id] = "zależności tworzą pętlę"
	return out


func _run_files(id: String, field: String) -> void:
	if load_errors.has(id):
		return
	var m: Dictionary = ModManager.manifests[id]
	var files: Array = m.get(field, [])
	if files.is_empty():
		return
	if not _envs.has(id):
		_envs[id] = _api.make_env.invoke(id)
	for s in files:
		var path: String = String(m.path).path_join(s)
		if not FileAccess.file_exists(path):
			_fail(id, "brak pliku " + s)
			return
		var r: Variant = _api.run_chunk.invoke(id, FileAccess.get_file_as_string(path), "@%s/%s" % [id, s], _envs[id])
		if _is_error(r):
			_fail(id, str(r))
			return
		if r != null:
			_fail(id, str(r))
			return


func _fail(id: String, msg: String) -> void:
	load_errors[id] = msg
	report_error(id, msg)


static func _is_error(v: Variant) -> bool:
	return v is Object and v != null and v.get_class() == "LuaError"


static func _is_table(v: Variant) -> bool:
	return v is Object and v != null and v.get_class() == "LuaTable"


# ---------- wywołania z silnika ----------

## Czy jakiś mod podpiął hak (pozwala pominąć koszt wywołania, np. co klatkę dla kamery).
func has_hook(kind: String, name: String) -> bool:
	return _hooks.has(kind + ":" + name)


## Hak „przed”: mody mogą zmienić pola ctx albo ustawić ctx.cancel = true.
func before(name: String, ctx: Dictionary) -> Dictionary:
	return _call("before", name, ctx)


## Hak „po”: wywoływany po domyślnym działaniu silnika.
func after(name: String, ctx: Dictionary) -> Dictionary:
	return _call("after", name, ctx)


func emit_event(name: String, data: Dictionary) -> void:
	_call("event", name, data)


func _call(kind: String, name: String, ctx: Dictionary) -> Dictionary:
	if _api.is_empty() or not has_hook(kind, name):
		return ctx
	var r: Variant = _api.dispatch.invoke(kind, name, ctx)
	if _is_error(r):
		report_error("silnik", "%s %s: %s" % [kind, name, str(r)])
		return ctx
	return r if r is Dictionary else ctx


func press_bind(id: String) -> void:
	if Net.is_client():
		Net.c_bind.rpc_id(1, id)
		return
	if _api.has("input"):
		_api.input.invoke(id)


func projectile_hit(type: String, ctx: Dictionary) -> void:
	if _api.has("projectile_hit"):
		_api.projectile_hit.invoke(type, ctx)


## Tekst moda w języku (lang/<język>.json); po kolei: język, polski, angielski, inne mody, sam klucz.
func translate(mod_id: String, key: String, lang: String) -> String:
	for l in [lang, "pl", "en"]:
		var rf := ModManager.resource_file("lang/%s.json" % l)
		if rf != "":
			var rk := "@res|" + rf
			if not lang_tables.has(rk):
				var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(rf))
				lang_tables[rk] = d if d is Dictionary else {}
			var rt: Dictionary = lang_tables[rk]
			if rt.has(mod_id + ":" + key):
				return str(rt[mod_id + ":" + key])
			if rt.has(key):
				return str(rt[key])
	for l in [lang, "pl", "en"]:
		var t := _lang(mod_id, l)
		if t.has(key):
			return str(t[key])
	for m in order:
		if m != mod_id:
			var t := _lang(m, lang)
			if t.has(key):
				return str(t[key])
	return key


func _lang(mod_id: String, lang: String) -> Dictionary:
	var k := mod_id + "|" + lang
	if not lang_tables.has(k):
		var path := str(ModManager.manifests[mod_id].path).path_join("lang/%s.json" % lang) if ModManager.manifests.has(mod_id) else ""
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(path)) if path != "" and FileAccess.file_exists(path) else null
		lang_tables[k] = d if d is Dictionary else {}
	return lang_tables[k]


## Paczki zasobów: plik dla klucza (pierwsza pasująca nazwa z listy) albo "".
func _h_res_file(names) -> String:
	for n in (names if names is Array else [names]):
		var f := ModManager.resource_file(str(n))
		if f != "":
			return f
	return ""


func _h_res_json(rel) -> Variant:
	var f := ModManager.resource_file(str(rel))
	return JSON.parse_string(FileAccess.get_file_as_string(f)) if f != "" else null


func _h_mod_replacement(id) -> String:
	var r := ModManager.replacement_of(str(id))
	return r if loaded.has(r) else ""


func _h_weather_set(kind, intensity) -> void:
	if main and not Net.is_client():
		main.set_weather({"kind": str(kind), "intensity": float(intensity)})


func _h_weather_get() -> Dictionary:
	return main.weather.state() if main else {"kind": "clear", "intensity": 0.0}


func _h_sky_set(sky) -> void:
	if main and not Net.is_client():
		main.set_weather({"sky": sky if sky is Dictionary else {}})


func _h_t(mod_id, key) -> String:
	var s := S()
	return translate(str(mod_id), str(key), s.lang if s and not s.local else Settings.language)


func worldgen_active() -> bool:
	return not worldgen_mods.is_empty() and _api.has("worldgen") and not Net.is_client()


## Generatory modów dla nowego chunka (współrzędne chunka).
func worldgen_generate(c: Vector3i) -> void:
	if _api.has("worldgen"):
		_api.worldgen.invoke(c.x, c.y, c.z, main.world.terrain.seed_value if main else 0)


func _h_worldgen_on(mod_id) -> void:
	worldgen_mods[str(mod_id)] = true


func _h_gen_get(pos) -> int:
	return main.world.gen_get(Vector3i(pos)) if main else 0


func _h_gen_set(pos, id) -> void:
	if main and int(id) >= 0 and int(id) < registry.count():
		main.world.gen_set(Vector3i(pos), int(id))


func _h_gen_height(x, z) -> int:
	return main.world.terrain.height(int(x), int(z)) if main else 0


func _h_gen_biome(x, z) -> String:
	if main == null:
		return ""
	var t: Terrain = main.world.terrain
	var i: int = t.column(int(x), int(z)).y
	return t.biome_keys[i] if i < t.biome_keys.size() else ""


## Szum zależny od ziarna świata: -1..1. salt rozróżnia niezależne szumy (np. "rudy", "jeziora").
func _h_gen_noise(x, y, z, scale, salt, octaves) -> float:
	var key := str(salt) + "|" + str(octaves)
	var n: FastNoiseLite = _gen_noises.get(key)
	if n == null:
		n = FastNoiseLite.new()
		n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		n.seed = (main.world.terrain.seed_value if main else 0) + hash(str(salt))
		n.frequency = 1.0
		n.fractal_type = FastNoiseLite.FRACTAL_FBM if int(octaves) > 1 else FastNoiseLite.FRACTAL_NONE
		n.fractal_octaves = maxi(1, int(octaves))
		_gen_noises[key] = n
	var sc := maxf(0.0001, float(scale))
	if y == null:
		return n.get_noise_2d(float(x) / sc, float(z) / sc)
	return n.get_noise_3d(float(x) / sc, float(y) / sc, float(z) / sc)


## Polecenie moda: zwraca tekst odpowiedzi (albo null).
func run_command(name: String, ctx: Dictionary) -> Variant:
	if _api.has("command"):
		return _api.command.invoke(name, ctx)
	return null


func entity_think(type: String, ctx: Dictionary) -> void:
	if _api.has("entity_think"):
		_api.entity_think.invoke(type, ctx)


func block_update(key: String, ctx: Dictionary) -> void:
	if _api.has("block_update"):
		_api.block_update.invoke(key, ctx)


func window_action(action: String, fields: Dictionary = {}) -> void:
	if _api.has("window_action"):
		_api.window_action.invoke(action, fields)


func report_error(mod_id: String, msg: String) -> void:
	var line := "[%s] BŁĄD: %s" % [mod_id, msg]
	push_warning(line)
	logs.append(line)
	if _errors_shown < MAX_ERRORS_SHOWN:
		_errors_shown += 1
		notified.emit("Błąd w modzie „%s”: %s (szczegóły: konsola F2)" % [_mod_name(mod_id), msg.get_slice("\n", 0).left(140)])
	log_added.emit(line)


func _log(mod_id: String, msg: String) -> void:
	var line := "[%s] %s" % [mod_id, msg]
	print(line)
	logs.append(line)
	log_added.emit(line)


signal log_added(line: String)


## Konsola: kod Lua wykonany w imieniu gracza `peer` (serwer). Zwraca wynik jako tekst.
func console_exec(peer: int, code: String) -> String:
	if not _api.has("console"):
		return "Skrypty modów nie działają (klient bez serwera?)."
	var prev := ctx
	ctx = peer
	var r: Variant = _api.console.invoke(code)
	ctx = prev
	return str(r) if r != null else ""


func _mod_name(id: String) -> String:
	return ModManager.manifests.get(id, {}).get("name", id)


# ---------- przedmioty ----------
# Miejsce w kontenerze: {} (puste) albo {"item": klucz, "count": n, "data": {...}, "info": [...]}.
# data – dane egzemplarza (np. amunicja w broni); stosy z różnymi danymi się nie łączą.
# info – linie opisu policzone przez mod (engine.items.tooltip), wysyłane do graczy razem z miejscem.

var lang_tables := {}     # "mod|język" -> {klucz: tekst} (pliki lang/<język>.json modów)
var worldgen_mods := {}   # mod -> true (ma engine.worldgen.on_generate)
var _gen_noises := {}
var mod_commands := {}    # polecenie -> {description, permission, usage, mod} (engine.commands.register)
var entity_brains := {}   # rodzaj stworzenia -> true (mod ma mózg engine.entities.on_think)
var tooltip_items := {}   # klucz przedmiotu -> true (mod liczy opis dynamiczny)

func container_slots(id: String) -> Array:
	return containers.get(id, {}).get("slots", [])


func slot(id: String, i: int) -> Dictionary:
	var s: Array = container_slots(id)
	if i < 0 or i >= s.size():
		return {}
	return s[i]


func set_slot(id: String, i: int, v: Dictionary) -> void:
	var s: Array = container_slots(id)
	if i < 0 or i >= s.size():
		return
	var item := str(v.get("item", ""))
	if int(v.get("count", 0)) <= 0 or item == "" or (registry and not registry.items.has(item)):
		s[i] = {}
	else:
		var ns := {"item": item, "count": int(v.count)}
		if v.get("data") is Dictionary and not (v.data as Dictionary).is_empty():
			ns["data"] = (v.data as Dictionary).duplicate(true)
		if tooltip_items.has(item) and _api.has("item_tooltip"):
			var lines: Variant = _api.item_tooltip.invoke(item, ns.duplicate(true))
			if lines is Array and not lines.is_empty():
				ns["info"] = lines
		s[i] = ns
	dirty_containers[id] = true
	if id == hotbar.container:
		hotbar_changed.emit()


func max_stack(item: String) -> int:
	return registry.max_stack(item) if registry else 64


## Przedmiot w wybranym miejscu paska: null gdy pasek nie jest podpięty do kontenera.
func hotbar_item(index: int) -> Variant:
	if hotbar.container == "":
		return null
	return slot(hotbar.container, hotbar.first + index)


# ---------- zapis danych modów w świecie ----------

func _load_data(world_dir: String) -> void:
	if world_dir.is_empty():
		return
	var p := world_dir.path_join("mods_data.json")
	if not FileAccess.file_exists(p):
		return
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(d) != TYPE_DICTIONARY:
		return
	storage = d.get("storage", {})
	pstorage = d.get("players", {}) if d.get("players") is Dictionary else {}
	for id in d.get("containers", {}):
		var slots: Array = []
		for sl in d.containers[id]:
			slots.append(sl if sl is Dictionary else {})
		containers[id] = {"owner": "", "persist": true, "slots": slots}


## Zapisy z etapu 3 trzymały w miejscach numer bloku ("block"); zamieniamy go na klucz przedmiotu.
func _migrate_slots() -> void:
	for id in containers:
		var slots: Array = containers[id].slots
		for i in slots.size():
			var sl: Dictionary = slots[i]
			if sl.has("block") and not sl.has("item"):
				var b := int(sl.block)
				slots[i] = {"item": Blocks.LEGACY_KEYS[b], "count": int(sl.count)} if b > 0 and b < Blocks.LEGACY_KEYS.size() else {}
			elif sl.has("item"):
				if not registry.items.has(str(sl.item)):
					slots[i] = {}  # przedmiot z wyłączonego moda
				else:
					slots[i] = {"item": str(sl.item), "count": int(sl.count)}


func save_data(world_dir: String) -> void:
	if world_dir.is_empty():
		return
	var cont := {}
	for id in containers:
		if containers[id].persist:
			cont[id] = containers[id].slots
	var f := FileAccess.open(world_dir.path_join("mods_data.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"storage": storage, "containers": cont, "players": pstorage}))


# ---------- gracze (sesje) ----------
# ctx = gracz, w którego imieniu działa kod moda (kopanie, kliknięcie, klawisz, zdarzenie gracza).
# Funkcje engine.player.*, kontenery „na gracza”, okna i paski dotyczą zawsze gracza z ctx.

var sessions := {}        # peer -> Session
var ctx := 1
var local_peer := 1
var per_player := {}      # logiczne id kontenerów prowadzonych osobno dla każdego gracza
var pstorage := {}        # konto -> {mod -> {klucz -> wartość}}
var dirty_containers := {}


func S() -> Session:
	var s: Session = sessions.get(ctx)
	if s == null:
		s = sessions.get(local_peer)
	return s


func add_session(peer: int, name: String, node: Node3D, local: bool) -> Session:
	var s := Session.new()
	s.peer = peer
	s.name = name
	s.account = name
	s.node = node
	s.local = local
	if local:
		# gracz lokalny: te same słowniki, które czyta interfejs
		s.player_stats = player_stats
		s.camera_stats = camera_stats
		s.anim_overrides = anim_overrides
		s.model_colors = model_colors
		s.hud = hud
		s.hotbar = hotbar
		s.windows = open_windows
		s.held = local_held
		local_peer = peer
	sessions[peer] = s
	return s


func remove_session(peer: int) -> void:
	sessions.erase(peer)


## Wykonuje fn w imieniu gracza peer (np. akcja gracza zdalnego na serwerze).
func as_player(peer: int, fn: Callable) -> Variant:
	var prev := ctx
	ctx = peer
	var r: Variant = fn.call()
	ctx = prev
	return r


func _pl() -> Node3D:
	var s := S()
	return s.node if s else null


## Rzeczywisty klucz kontenera: kontenery „na gracza” mają osobną kopię dla każdego konta.
func cid(id: String) -> String:
	if per_player.has(id):
		return id + "#" + S().account
	return id


static func logical_cid(real: String) -> String:
	var i := real.find("#")
	return real if i < 0 else real.substr(0, i)


func session_of_account(account: String) -> Session:
	for p in sessions:
		if sessions[p].account == account and sessions[p].logged_in:
			return sessions[p]
	return null


# ---------- okna: kliknięcia w miejsca na przedmioty (logika po stronie serwera) ----------

var local_held := {}


func held_of(peer: int) -> Dictionary:
	var s: Session = sessions.get(peer)
	return s.held if s else local_held


## Kliknięcie w miejsce kontenera: bierze stos (prawy: połowę), odkłada, łączy, zamienia.
## Hak „slot.click” (before) może przejąć kliknięcie, np. pole wyniku rzemiosła.
func window_click(peer: int, real: String, i: int, right: bool) -> void:
	var s: Session = sessions.get(peer)
	if s == null or not containers.has(real):
		return
	var prev := ctx
	ctx = peer
	var held: Dictionary = s.held
	var ctxd := before("slot.click", {"container": logical_cid(real), "index": i + 1, "right": right,
		"held": held.duplicate()})
	if not ctxd.get("cancel", false):
		var cur := slot(real, i)
		if held.is_empty():
			if not cur.is_empty():
				if right and int(cur.count) > 1:
					var half := int(cur.count) / 2
					_set_held(s, with_count(cur, half))
					set_slot(real, i, with_count(cur, int(cur.count) - half))
				else:
					_set_held(s, cur.duplicate(true))
					set_slot(real, i, {})
		else:
			var ms := max_stack(str(held.item))
			if cur.is_empty():
				var n := mini(ms, 1 if right else int(held.count))
				set_slot(real, i, with_count(held, n))
				_set_held(s, with_count(held, int(held.count) - n))
			elif stackable(cur, held):
				var n := mini(ms - int(cur.count), 1 if right else int(held.count))
				set_slot(real, i, with_count(cur, int(cur.count) + n))
				_set_held(s, with_count(held, int(held.count) - n))
			elif not right:
				set_slot(real, i, held.duplicate())
				_set_held(s, cur.duplicate())
		after("slot.click", ctxd)
	ctx = prev


## Ten sam przedmiot z tymi samymi danymi: można łączyć w jeden stos.
static func stackable(a: Dictionary, b: Dictionary) -> bool:
	return str(a.get("item", "")) == str(b.get("item", "")) and a.get("data", {}) == b.get("data", {})


static func with_count(v: Dictionary, n: int) -> Dictionary:
	var c := v.duplicate(true)
	c["count"] = n
	return c


func _set_held(s: Session, v: Dictionary) -> void:
	s.held.clear()
	if not v.is_empty() and int(v.get("count", 0)) > 0:
		s.held.merge(v)
	s.mark("held")


## Okno zamknięte: trzymany przedmiot wraca do kontenerów okna, a gdy brak miejsca, upada na ziemię.
func window_closed(peer: int, id: String) -> void:
	var s: Session = sessions.get(peer)
	if s == null:
		return
	var spec: Dictionary = s.windows.get(id, {})
	s.windows.erase(id)
	var prev := ctx
	ctx = peer
	if id != "":
		emit_event("ui.closed", {"id": id})
	if s.held.is_empty():
		ctx = prev
		return
	var conts := ModWindow.slot_containers(spec)
	if s.hotbar.container != "":
		conts.append(s.hotbar.container)
	var left := int(s.held.count)
	for c in conts:
		for i in container_slots(c).size():
			if left <= 0:
				break
			var sl := slot(c, i)
			var ms := max_stack(str(s.held.item))
			if sl.is_empty():
				var n := mini(ms, left)
				set_slot(c, i, with_count(s.held, n))
				left -= n
			elif stackable(sl, s.held) and int(sl.count) < ms:
				var n := mini(ms - int(sl.count), left)
				set_slot(c, i, with_count(sl, int(sl.count) + n))
				left -= n
	if left > 0 and main and s.node:
		main.entities.drop_item(str(s.held.item), left, s.node.global_position + Vector3(0, 1, 0), s.held.get("data", {}) if s.held.get("data") is Dictionary else {})
	_set_held(s, {})
	ctx = prev


# ---------- funkcje gospodarza dostępne dla prelude.lua ----------

func _host_table() -> Dictionary:
	var names := ["log", "report_error", "mod_disabled", "hook_added", "setting", "storage_get", "storage_set",
		"block_id", "block_key", "block_name", "block_list", "item_name", "item_block", "max_stack",
		"get_block", "set_block", "biome", "biome_key", "height", "time_of_day", "set_time",
		"player_position", "player_teleport", "player_velocity", "player_push", "player_set", "player_get",
		"player_health", "player_set_health", "player_damage", "player_animate", "player_colors",
		"player_target", "player_in_liquid", "player_eyes_in_liquid", "selected_item", "anim_override",
		"camera_set", "camera_get", "container_create", "container_size", "slot_get", "slot_set",
		"hotbar_bind", "hotbar_selected", "ui_window", "ui_close", "ui_is_open", "notify", "hud_bar",
		"hud_text", "hud_remove", "ui_held", "ui_set_held", "input_bind", "randf", "randi",
		"entity_spawn", "entity_remove", "entity_exists", "entity_get", "entity_list", "entity_set",
		"entity_damage", "entity_tag", "entity_data", "item_drop", "entity_brain", "entity_mount", "entity_dismount",
		"entity_nearest_player", "world_light", "command_register", "chat_send", "role_get", "role_set", "hud_image",
		"worldgen_on", "gen_get", "gen_set", "gen_height", "gen_biome", "gen_noise", "t",
		"weather_set", "weather_get", "sky_set", "player_wear", "mod_replacement", "res_file", "res_json",
		"player_id", "player_name", "player_is_host", "players_list", "set_ctx", "get_ctx",
		"pstorage_get", "pstorage_set", "players_accept", "players_kick", "is_multiplayer", "hash",
		"block_state", "block_set_state", "block_with_state", "block_base", "block_data", "block_set_data",
		"block_clear_data", "block_container", "block_listen", "block_schedule", "sound_play", "sound_stop",
		"particles_spawn", "block_look", "block_get_look", "block_animate",
		"projectile_spawn", "projectile_remove", "player_eye", "player_look", "world_raycast", "item_tooltip_register",
		"player_base", "player_modify", "player_unmodify", "effect_add", "effect_remove", "effect_get", "effect_list"]
	var t := {}
	for n in names:
		t[n] = Callable(self, "_h_" + n)
	return t


func _h_log(mod_id, msg) -> void: _log(str(mod_id), str(msg))
func _h_report_error(mod_id, msg) -> void: report_error(str(mod_id), str(msg))


func _h_mod_disabled(mod_id, msg) -> void:
	load_errors[str(mod_id)] = "wyłączony: " + str(msg)
	_errors_shown = 0
	report_error(str(mod_id), "mod został wyłączony, bo zawieszał grę (%s)" % str(msg))


func _h_hook_added(kind, name) -> void: _hooks[str(kind) + ":" + str(name)] = true


## Ustawienie z "world": true czyta wartość zapisaną w świecie, pozostałe bieżącą.
func _h_setting(mod_id, key) -> Variant:
	var id := str(mod_id)
	var k := str(key)
	for d in ModManager.setting_defs(id):
		if d.key == k and d.get("world", false) and not GameState.current.is_empty():
			return GameState.world_mod_value(id, k)
	return ModManager.get_value(id, k)


func _h_storage_get(mod_id, key) -> Variant: return storage.get(str(mod_id), {}).get(str(key))


func _h_storage_set(mod_id, key, v) -> void:
	if not storage.has(str(mod_id)):
		storage[str(mod_id)] = {}
	storage[str(mod_id)][str(key)] = v


func _h_pstorage_get(mod_id, key) -> Variant:
	return pstorage.get(S().account, {}).get(str(mod_id), {}).get(str(key))


func _h_pstorage_set(mod_id, key, v) -> void:
	var acc := S().account
	if not pstorage.has(acc):
		pstorage[acc] = {}
	if not pstorage[acc].has(str(mod_id)):
		pstorage[acc][str(mod_id)] = {}
	pstorage[acc][str(mod_id)][str(key)] = v


func _h_block_id(key) -> int: return registry.id_of(str(key)) if registry else -1
func _h_block_key(id) -> String: return registry.block_key(int(id)) if registry else ""
func _h_block_name(id) -> String: return registry.block_name(int(id)) if registry else ""


func _h_block_list() -> Array:
	var out := []
	if registry:
		for i in range(1, registry.count()):
			out.append({"id": i, "key": registry.keys[i], "name": registry.names[i]})
	return out


func _h_item_name(key) -> String: return registry.item_name(str(key)) if registry else str(key)
func _h_item_block(key) -> int: return registry.item_block(str(key)) if registry else -1
func _h_max_stack(key) -> int: return max_stack(str(key)) if str(key) != "" else 64


## Pozycja z Lua: Vector3/Vector3i albo tabela {x=, y=, z=}.
static func _v3i(pos: Variant) -> Vector3i:
	if pos is Dictionary:
		return Vector3i(floori(float(pos.get("x", 0))), floori(float(pos.get("y", 0))), floori(float(pos.get("z", 0))))
	if pos is Vector3:
		return Vector3i(pos.floor())
	if pos is Vector3i:
		return pos
	return Vector3i.ZERO


# ---------- stany, dane i aktualizacje bloków ----------

func _logic() -> BlockLogic:
	return main.world.logic if main and main.world else null


func _block_arg(block: Variant) -> int:
	if block is String:
		return registry.id_of(block) if registry else -1
	return int(block)


func _h_block_state(pos) -> Dictionary:
	return registry.state_of(_h_get_block(pos)) if registry else {}


func _h_block_set_state(pos, changes) -> bool:
	var p := _v3i(pos)
	var id := _h_get_block(p)
	var nid := registry.with_state(id, changes if changes is Dictionary else {})
	if nid == id:
		return false
	return main.world.set_block(p, nid)


func _h_block_with_state(block, changes) -> int:
	return registry.with_state(_block_arg(block), changes if changes is Dictionary else {}) if registry else -1


func _h_block_base(block) -> String:
	return registry.block_key(registry.base_of(_block_arg(block))) if registry else ""


func _h_block_data(pos) -> Dictionary:
	var l := _logic()
	return l.get_data(_v3i(pos)).duplicate(true) if l else {}


func _h_block_set_data(pos, key, value) -> void:
	var l := _logic()
	if l:
		l.set_data(_v3i(pos), str(key), value)


func _h_block_clear_data(pos) -> void:
	var l := _logic()
	if l:
		l.data.erase(_v3i(pos))


func _h_block_container(mod_id, pos, size) -> String:
	var l := _logic()
	return l.container(str(mod_id), _v3i(pos), clampi(int(size), 1, 108)) if l else ""


func _h_block_listen(key) -> void:
	var l := _logic()
	if l:
		l.add_listener(str(key))


func _h_block_schedule(pos, seconds, tag) -> void:
	var l := _logic()
	if l:
		l.schedule(_v3i(pos), float(seconds), str(tag))


func _h_sound_play(name, opts) -> int:
	var o: Dictionary = opts if opts is Dictionary else {}
	var pos: Variant = null
	if o.has("pos"):
		pos = Vector3(_v3i(o.pos)) + Vector3(0.5, 0.5, 0.5) if o.pos is Dictionary or o.pos is Vector3i else Vector3(o.pos)
	var peer := int(o.get("player", -1))
	return Sfx.emit(str(name), pos, float(o.get("volume", 1.0)), float(o.get("pitch", 1.0)), bool(o.get("loop", false)), peer)


func _h_particles_spawn(name, pos, opts) -> void:
	Fx.emit(str(name), Vector3(pos) if pos is Vector3 else Vector3(_v3i(pos)), opts if opts is Dictionary else {})


func _h_block_look(pos, look) -> void:
	var l := _logic()
	if l:
		l.set_look(_v3i(pos), look if look is Dictionary else {})


func _h_block_get_look(pos) -> Dictionary:
	var l := _logic()
	return l.looks.get(_v3i(pos), {}).duplicate(true) if l else {}


func _h_block_animate(pos, name) -> void:
	var l := _logic()
	if l:
		l.animate(_v3i(pos), str(name))


func _h_projectile_spawn(type, opts) -> int:
	if main == null or main.get("projectiles") == null:
		return -1
	return main.projectiles.spawn(str(type), opts if opts is Dictionary else {})


func _h_projectile_remove(id) -> void:
	if main and main.get("projectiles"):
		main.projectiles.remove(int(id))


func _h_player_eye() -> Vector3:
	var p := _pl()
	return p.call("aim")[0] if p and p.has_method("aim") else Vector3.ZERO


func _h_player_look() -> Vector3:
	var p := _pl()
	return p.call("aim")[1] if p and p.has_method("aim") else Vector3.FORWARD


func _h_world_raycast(from, dir, dist, liquids, solid) -> Variant:
	if main == null:
		return null
	var o := Vector3(from) if (from is Vector3 or from is Vector3i) else Vector3.ZERO
	var d := Vector3(dir) if (dir is Vector3 or dir is Vector3i) else Vector3.FORWARD
	if d.length() < 0.0001:
		return null
	var r: Dictionary = main.world.raycast(o, d.normalized(), clampf(float(dist), 0.0, 256.0), bool(liquids), bool(solid))
	if not r.get("hit", false):
		return null
	var b: int = main.world.get_block(r.pos)
	return {"position": r.pos, "normal": r.normal, "place_pos": (r.pos as Vector3i) + (r.normal as Vector3i),
		"point": o + d.normalized() * float(r.dist), "distance": float(r.dist), "block": b,
		"key": registry.block_key(b)}


func _h_item_tooltip_register(key) -> void:
	tooltip_items[str(key)] = true


func _h_sound_stop(id) -> void:
	Sfx.stop(int(id))


func _h_get_block(pos) -> int: return main.world.get_block(_v3i(pos)) if main else 0
func _h_set_block(pos, id) -> bool: return main.world.set_block(_v3i(pos), int(id)) if main and int(id) >= 0 else false


func _h_biome(pos) -> String:
	if main == null:
		return ""
	var p := Vector3i(pos)
	return main.world.terrain.biome_name(main.world.terrain.column(p.x, p.z).y)


func _h_biome_key(pos) -> String:
	if main == null:
		return ""
	var p := Vector3i(pos)
	var i: int = main.world.terrain.column(p.x, p.z).y
	var keys: Array[String] = main.world.terrain.biome_keys
	return keys[i] if i < keys.size() else ""


func _h_height(x, z) -> int: return main.world.terrain.height(int(x), int(z)) if main else 0
func _h_time_of_day() -> float: return main.time_of_day if main else 12.0


## Światło w punkcie: {sky = 0..15 (niebo, bez pory dnia), block = 0..15 (pochodnie), day = 0..1 (jasność dnia)}.
func _h_world_light(pos) -> Dictionary:
	if main == null:
		return {"sky": 15, "block": 0, "day": 1.0}
	var l: Vector2 = main.world.light_at(Vector3(pos))
	var t := float(main.time_of_day)
	var day := clampf(minf((t - 5.0) / 2.0, (20.0 - t) / 2.0), 0.0, 1.0)
	return {"sky": int(round(l.x * 15.0)), "block": int(round(l.y * 15.0)), "day": day}


func _h_set_time(h) -> void:
	if main:
		main.time_of_day = fposmod(float(h), 24.0)


func _h_player_id() -> int: return S().peer
func _h_player_name() -> String: return S().account
func _h_player_is_host() -> bool: return S().local
func _h_is_multiplayer() -> bool: return Net.mode != "single"
func _h_set_ctx(peer) -> void: ctx = int(peer)
func _h_get_ctx() -> int: return ctx
func _h_hash(text) -> String: return str(text).sha256_text()


func _h_players_list() -> Array:
	var out := []
	for p in sessions:
		var s: Session = sessions[p]
		if s.logged_in:
			out.append({"id": p, "name": s.account})
	return out


func _h_players_accept(peer, account) -> String:
	if main == null:
		return "brak świata"
	return main.accept_player(int(peer), str(account))


func _h_players_kick(peer, reason) -> void:
	Net.kick(int(peer), str(reason))


func _h_player_position() -> Vector3:
	var p := _pl()
	return p.global_position if p else Vector3.ZERO


func _h_player_teleport(pos) -> void:
	var p := _pl()
	if p:
		p.teleport(Vector3(pos))


func _h_player_velocity() -> Vector3:
	var p := _pl()
	return p.velocity if p else Vector3.ZERO


func _h_player_push(v) -> void:
	var p := _pl()
	if p:
		p.push(Vector3(v))


func _h_player_set(stat, v) -> void:
	var s := S()
	if v == null:
		s.stat_base.erase(str(stat))
	else:
		s.stat_base[str(stat)] = v
	recompute_stats(s)


func _h_player_base(stat) -> Variant:
	return S().stat_base.get(str(stat), Player.default_stat(str(stat)))


## Modyfikator statystyki od źródła (np. "alchemy:speed"): wartość = (baza + suma add) * iloczyn mul.
func _h_player_modify(stat, source, add, mul) -> void:
	var s := S()
	var st := str(stat)
	if not s.stat_mods.has(st):
		s.stat_mods[st] = {}
	s.stat_mods[st][str(source)] = [float(add), float(mul)]
	recompute_stats(s)


func _h_player_unmodify(stat, source) -> void:
	var s := S()
	var st := str(stat)
	if s.stat_mods.has(st):
		s.stat_mods[st].erase(str(source))
		if s.stat_mods[st].is_empty():
			s.stat_mods.erase(st)
	recompute_stats(s)


## Statystyki widziane przez grę = baza od modów z nałożonymi modyfikatorami.
func recompute_stats(s: Session) -> void:
	var keys := {}
	for k in s.stat_base:
		keys[k] = true
	for k in s.stat_mods:
		keys[k] = true
	s.player_stats.clear()
	for k in keys:
		var v: Variant = s.stat_base.get(k, Player.default_stat(k))
		if s.stat_mods.has(k) and (v is float or v is int):
			var add := 0.0
			var mul := 1.0
			for src in s.stat_mods[k]:
				add += float(s.stat_mods[k][src][0])
				mul *= float(s.stat_mods[k][src][1])
			v = (float(v) + add) * mul
		s.player_stats[k] = v
	s.mark("stats")


# ---------- efekty (mikstury, trucizny, premie): czas, modyfikatory, ikona na ekranie ----------

func _effect_mods(s: Session, name: String, on: bool) -> void:
	var d: Dictionary = registry.effects.get(name, {}) if registry else {}
	var stats: Variant = d.get("stats", {})
	if not stats is Dictionary:
		return
	var strength := float(s.effects.get(name, {}).get("strength", 1.0))
	var prev := ctx
	ctx = s.peer
	for st in stats:
		var m: Dictionary = stats[st] if stats[st] is Dictionary else {}
		if on:
			var mul := 1.0 + (float(m.get("mul", 1.0)) - 1.0) * strength
			_h_player_modify(st, "effect:" + name, float(m.get("add", 0.0)) * strength, mul)
		else:
			_h_player_unmodify(st, "effect:" + name)
	ctx = prev


func _h_effect_add(name, seconds, strength) -> bool:
	var n := str(name)
	if registry == null or not registry.effects.has(n):
		return false
	var s := S()
	var had := s.effects.has(n)
	if had:
		_effect_mods(s, n, false)
	s.effects[n] = {"left": float(seconds), "strength": float(strength)}
	_effect_mods(s, n, true)
	s.mark("effects")
	if s.local:
		effects_changed.emit()
	if not had:
		emit_event("effect.start", {"name": n, "strength": float(strength)})
	return true


func _h_effect_remove(name) -> void:
	var s := S()
	var n := str(name)
	if not s.effects.has(n):
		return
	_effect_mods(s, n, false)
	s.effects.erase(n)
	s.mark("effects")
	if s.local:
		effects_changed.emit()
	emit_event("effect.end", {"name": n})


func _h_effect_get(name) -> Variant:
	var e: Variant = S().effects.get(str(name))
	return (e as Dictionary).duplicate() if e is Dictionary else null


func _h_effect_list() -> Dictionary:
	return S().effects.duplicate(true)


## Co 0,1 s na serwerze: odliczanie efektów, koniec – zdjęcie modyfikatorów i zdarzenie effect.end.
func tick_effects(dt: float) -> void:
	for p in sessions:
		var s: Session = sessions[p]
		if s.effects.is_empty() or not s.logged_in:
			continue
		var prev := ctx
		ctx = p
		for n in s.effects.keys():
			s.effects[n].left = float(s.effects[n].left) - dt
			if float(s.effects[n].left) <= 0.0:
				_h_effect_remove(n)
		# czas na ekranie odświeżamy co sekundę
		if int(Time.get_ticks_msec() / 1000) != int(s.get_meta("eff_sec", -1)):
			s.set_meta("eff_sec", int(Time.get_ticks_msec() / 1000))
			s.mark("effects")
			if s.local:
				effects_changed.emit()
		ctx = prev


## Gracz wszedł na konto: efekty z zapisu konta wracają razem z modyfikatorami.
func restore_effects(p: int) -> void:
	var s: Session = sessions.get(p)
	if s == null:
		return
	var acc := s.account
	if not pstorage.has(acc):
		pstorage[acc] = {}
	if not pstorage[acc].has("_engine"):
		pstorage[acc]["_engine"] = {}
	var eng: Dictionary = pstorage[acc]["_engine"]
	if not eng.get("effects") is Dictionary:
		eng["effects"] = {}
	s.effects = eng.effects
	for n in s.effects.keys():
		if registry and registry.effects.has(n):
			_effect_mods(s, n, true)
		else:
			s.effects.erase(n)
	s.mark("effects")


func _h_player_get(stat) -> Variant:
	var p := _pl()
	return p.stat(str(stat)) if p else null


func _h_player_health() -> float:
	var p := _pl()
	return p.health if p else 0.0


func _h_player_set_health(v) -> void:
	var p := _pl()
	if p:
		p.set_health(float(v))


func _h_player_damage(amount, cause) -> void:
	var p := _pl()
	if p:
		p.damage(float(amount), str(cause))


func _h_player_animate(name) -> void:
	var p := _pl()
	if p:
		p.model.play(str(name))
		Net.broadcast_anim(S().peer, str(name))


func _h_player_colors(t) -> void:
	if t is Dictionary:
		var s := S()
		for k in t:
			var c: Variant = t[k]
			s.model_colors[str(k)] = c if c is Color else Color.from_string(str(c), Color.WHITE)
		if s.node:
			s.node.model.apply_colors(s.model_colors)
		Net.broadcast_look(s)


func _h_player_wear(id, spec) -> void:
	var s := S()
	if spec is Dictionary:
		s.wear[str(id)] = spec
	else:
		s.wear.erase(str(id))
	if s.node and s.node.model:
		s.node.model.set_wear(s.wear)
	if Net.online() and Net.is_server():
		Net.s_wear.rpc(s.peer, s.wear)


func _h_player_in_liquid() -> bool:
	var p := _pl()
	return p.in_liquid if p else false


func _h_player_eyes_in_liquid() -> bool:
	var p := _pl()
	return p.eyes_in_liquid if p else false


func _h_player_target(with_liquids) -> Dictionary:
	var p := _pl()
	if p == null:
		return {}
	var t: Dictionary = p.target_with_liquids() if bool(with_liquids) else p.target
	if t.is_empty():
		return {}
	return {"pos": t.pos, "normal": t.normal, "block": main.world.get_block(t.pos)}


func _h_selected_item() -> Dictionary:
	var p := _pl()
	return p.current_item() if p else {}


func _h_anim_override(state, name) -> void:
	var s := S()
	if str(name) == "":
		s.anim_overrides.erase(str(state))
	else:
		s.anim_overrides[str(state)] = str(name)
	Net.broadcast_look(s)


func _h_camera_set(key, v) -> void:
	S().camera_stats[str(key)] = v
	S().mark("camera")


func _h_camera_get(key) -> Variant:
	var s := S()
	if s.camera_stats.has(str(key)):
		return s.camera_stats[str(key)]
	if s.node and str(key) == "mode":
		return s.node.camera_mode()
	return null


func _h_container_create(mod_id, id, size, persist, for_player) -> void:
	var logical := str(id)
	if bool(for_player):
		per_player[logical] = true
	var key := cid(logical)
	var n := int(size)
	if bool(for_player) and not containers.has(key) and containers.has(logical) and S().local:
		# świat sprzed gry wieloosobowej: wspólny kontener staje się kontenerem gracza-gospodarza
		containers[key] = containers[logical]
		containers.erase(logical)
	if not containers.has(key):
		containers[key] = {"owner": str(mod_id), "persist": bool(persist), "slots": []}
	var c: Dictionary = containers[key]
	c.owner = str(mod_id)
	c.persist = bool(persist)
	var slots: Array = c.slots
	while slots.size() < n:
		slots.append({})
	if slots.size() > n:
		slots.resize(n)
	dirty_containers[key] = true


func _h_container_size(id) -> int: return container_slots(cid(str(id))).size()
func _h_slot_get(id, i) -> Dictionary: return slot(cid(str(id)), int(i))
func _h_slot_set(id, i, v) -> void: set_slot(cid(str(id)), int(i), v if v is Dictionary else {})


func _h_hotbar_bind(container, first, count) -> void:
	var s := S()
	s.hotbar.container = cid(str(container)) if str(container) != "" else ""
	s.hotbar.first = int(first)
	s.hotbar.count = int(count)
	s.mark("hotbar")
	if s.local:
		hotbar_changed.emit()


func _h_hotbar_selected() -> int:
	var p := _pl()
	return p.selected if p else 0


func _h_ui_window(mod_id, spec) -> void:
	var d: Dictionary = spec if spec is Dictionary else {}
	d["mod"] = str(mod_id)
	ModWindow.each_section(d.get("sections"), func(sec: Dictionary):
		if sec.get("type") == "slots":
			sec["container"] = cid(str(sec.get("container", ""))))
	var s := S()
	s.windows[str(d.get("id", mod_id))] = d
	if s.local:
		ui_window_requested.emit(d)
	else:
		Net.send_window(s.peer, d)


func _h_ui_close(id) -> void:
	var s := S()
	if s.local:
		ui_close_requested.emit(str(id))
	else:
		window_closed(s.peer, str(id))
		Net.send_close(s.peer, str(id))


func _h_ui_is_open(id) -> bool: return S().windows.has(str(id))


func _h_notify(text) -> void:
	var s := S()
	if s.local:
		notified.emit(str(text))
	else:
		Net.send_notify(s.peer, str(text))


func _h_ui_held() -> Dictionary: return S().held


func _h_ui_set_held(v) -> void:
	_set_held(S(), v if v is Dictionary else {})


func _h_hud_bar(mod_id, spec) -> void:
	var d: Dictionary = spec if spec is Dictionary else {}
	d["type"] = "bar"
	d["mod"] = str(mod_id)
	var s := S()
	s.hud[str(d.get("id", mod_id))] = d
	s.mark("hud")
	if s.local:
		hud_changed.emit()


func _h_hud_text(mod_id, spec) -> void:
	var d: Dictionary = spec if spec is Dictionary else {}
	d["type"] = "text"
	d["mod"] = str(mod_id)
	var s := S()
	s.hud[str(d.get("id", mod_id))] = d
	s.mark("hud")
	if s.local:
		hud_changed.emit()


func _h_hud_image(mod_id, spec) -> void:
	var d: Dictionary = spec if spec is Dictionary else {}
	d["type"] = "image"
	d["mod"] = str(mod_id)
	var s := S()
	s.hud[str(d.get("id", mod_id))] = d
	s.mark("hud")
	if s.local:
		hud_changed.emit()


func _h_hud_remove(id) -> void:
	var s := S()
	if s.hud.has(str(id)):
		s.hud.erase(str(id))
		s.mark("hud")
		if s.local:
			hud_changed.emit()


func _h_input_bind(mod_id, id, key, label) -> void:
	for b in binds:
		if b.id == str(id):
			return
	binds.append({"id": str(id), "mod": str(mod_id), "key": str(key).to_upper(), "label": str(label)})
	binds_changed.emit()


func _h_randf() -> float: return _rng.randf()
func _h_randi(a, b) -> int: return _rng.randi_range(int(a), int(b))


# ---------- stworzenia i obiekty ----------

func _ent(id) -> Node3D:
	if main == null or main.entities == null:
		return null
	return main.entities.get_entity(int(id))


func _h_entity_spawn(type, pos, data, scale) -> int:
	if main == null:
		return -1
	return main.entities.spawn_creature(str(type), Vector3(pos), data if data is Dictionary else {}, float(scale))


func _h_entity_remove(id) -> void:
	if main:
		main.entities.remove(int(id))


func _h_entity_exists(id) -> bool: return _ent(id) != null


func _h_entity_get(id, key) -> Variant:
	var e := _ent(id)
	if e == null:
		return null
	match str(key):
		"type": return e.type if e is Creature else ("prop" if e is Prop else "item")
		"pos": return e.global_position
		"health": return e.health if e is Creature else 0.0
		"state": return e.state if e is Creature else ""
		"scale": return e.scale_factor if e is Creature else 1.0
		"data": return e.data if e is Creature else {}
		"target": return e.target_peer if e is Creature and e.target_peer >= 0 else null
		"rider": return e.rider if e is Creature and e.rider >= 0 else null
		"velocity": return e.velocity if e is Creature else Vector3.ZERO
		"yaw": return e.rotation.y
		"hostile": return e.is_hostile() if e is Creature else false
	return null


func _h_entity_list(type, radius) -> Array:
	if main == null:
		return []
	var p := _pl()
	return main.entities.list(str(type), p.global_position if p else Vector3.ZERO, float(radius))


func _h_entity_set(id, key, v) -> void:
	var e := _ent(id)
	if e == null:
		return
	match str(key):
		"pos":
			e.global_position = Vector3(v)
		"target":
			if e is Creature:
				e.move_to(Vector3(v))
		"scale":
			if e is Creature:
				e.set_scale_factor(float(v))
				Net.entity_look(e)
		"animate":
			if e is Creature:
				e.play(str(v))
				Net.entity_anim(e.id, str(v))
		"state":
			if e is Creature and v is Array and v.size() >= 1:
				e.set_state(str(v[0]), float(v[1]) if v.size() > 1 else 5.0)
				if str(v[0]) != "chase":
					e.target_peer = -1
		"attack":
			if e is Creature:
				e.chase(int(v), 30.0)
		"look_at":
			if e is Creature:
				e.look_point = Vector3(v)
				e.look_time = 2.0
				var to := Vector3(v) - e.global_position
				e.rotation.y = atan2(-to.x, -to.z)
		"push":
			if e is Creature:
				e.velocity += Vector3(v)
			elif e is RigidBody3D:
				(e as RigidBody3D).apply_central_impulse(Vector3(v) * (e as RigidBody3D).mass)


func _h_command_register(mod_id, name, def) -> void:
	var d: Dictionary = def if def is Dictionary else {}
	mod_commands[str(name).to_lower()] = {"description": str(d.get("description", "")), "usage": str(d.get("usage", "/" + str(name))),
		"permission": str(d.get("permission", "player")), "mod": str(mod_id)}


## Wiadomość czatu od serwera: do wszystkich albo do jednego gracza (to >= 0); who = nadawca (puste: serwer).
func _h_chat_send(text, color, to, who) -> void:
	if main:
		main.broadcast_chat(str(who) if who != null else "", str(text), str(color) if color != null else "#cfe0f0", int(to) if to != null else -1)


func _h_role_get(peer) -> String:
	if main == null:
		return "player"
	return main.role_of(int(peer) if peer != null and int(peer) >= 0 else ctx)


func _h_role_set(peer_or_account, role) -> void:
	if main == null or not Commands.ROLES.has(str(role)):
		return
	var account := str(peer_or_account)
	if (peer_or_account is int or peer_or_account is float) and sessions.has(int(peer_or_account)):
		account = (sessions[int(peer_or_account)] as Session).account
	main.set_role(account, str(role))


func _h_entity_brain(type) -> void:
	entity_brains[str(type)] = true


## Gracz (domyślnie bieżący) wsiada na stworzenie.
func _h_entity_mount(id, peer) -> bool:
	if main == null:
		return false
	var p := int(peer) if peer != null and int(peer) >= 0 else ctx
	return main.entities.mount(p, int(id))


func _h_entity_dismount(peer) -> void:
	if main:
		main.entities.dismount(int(peer) if peer != null and int(peer) >= 0 else ctx)


func _h_entity_nearest_player(pos, radius) -> Variant:
	if main == null:
		return null
	var pl: Node3D = main.entities.nearest_player(Vector3(pos))
	if pl == null or pl.global_position.distance_to(Vector3(pos)) > float(radius):
		return null
	return {"id": EntityManager.peer_of(pl), "distance": pl.global_position.distance_to(Vector3(pos)), "position": pl.global_position}


func _h_entity_damage(id, amount, cause) -> void:
	var e := _ent(id)
	if e is Creature:
		e.hit(float(amount), e.global_position, str(cause))


func _h_entity_tag(id, tag, on, color) -> void:
	var e := _ent(id)
	if e is Creature:
		e.show_tag(str(tag), bool(on))
		if color != null:
			e.color_tag(str(tag), color if color is Color else Color.from_string(str(color), Color.WHITE))
		Net.entity_look(e)


func _h_entity_data(id, key, v) -> void:
	var e := _ent(id)
	if e is Creature:
		if v == null:
			e.data.erase(str(key))
		else:
			e.data[str(key)] = v


func _h_item_drop(item, count, pos, data) -> int:
	if main == null:
		return -1
	return main.entities.drop_item(str(item), int(count), Vector3(pos), data if data is Dictionary else {})
