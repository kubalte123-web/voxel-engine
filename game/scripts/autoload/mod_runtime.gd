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

const LIBS := 1 | 4 | 8 | 32 | 64 | 4096 | 8192  # base, coroutine, string, math, table, utf8, typy Godota
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
var player_stats := {}  # nadpisania statystyk gracza przez mody
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
	registry.build(content, paths)
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
	for k in ["dispatch", "make_env", "input", "window_action", "finalize"]:
		_api[k] = res.get(k)
	return true


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
	hotbar = {"container": "", "first": 0, "count": 0}
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
			for r in reqs:
				if not wanted.has(r):
					missing.append(r)
				elif not out.has(r):
					waiting = true
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
		var r: Variant = lua.do_string(FileAccess.get_file_as_string(path), "@%s/%s" % [id, s], _envs[id])
		if _is_error(r):
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
	if _api.has("input"):
		_api.input.invoke(id)


func window_action(action: String) -> void:
	if _api.has("window_action"):
		_api.window_action.invoke(action)


func report_error(mod_id: String, msg: String) -> void:
	var line := "[%s] BŁĄD: %s" % [mod_id, msg]
	push_warning(line)
	logs.append(line)
	if _errors_shown < MAX_ERRORS_SHOWN:
		_errors_shown += 1
		notified.emit("Błąd w modzie „%s”: %s" % [_mod_name(mod_id), msg.left(140)])


func _log(mod_id: String, msg: String) -> void:
	var line := "[%s] %s" % [mod_id, msg]
	print(line)
	logs.append(line)


func _mod_name(id: String) -> String:
	return ModManager.manifests.get(id, {}).get("name", id)


# ---------- przedmioty ----------
# Miejsce w kontenerze: {} (puste) albo {"item": klucz, "count": n}.

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
		s[i] = {"item": item, "count": int(v.count)}
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
		f.store_string(JSON.stringify({"storage": storage, "containers": cont}))


# ---------- funkcje gospodarza dostępne dla prelude.lua ----------

func _host_table() -> Dictionary:
	var names := ["log", "report_error", "hook_added", "setting", "storage_get", "storage_set",
		"block_id", "block_key", "block_name", "block_list", "item_name", "item_block", "max_stack",
		"get_block", "set_block", "biome", "biome_key", "height", "time_of_day", "set_time",
		"player_position", "player_teleport", "player_velocity", "player_push", "player_set", "player_get",
		"player_health", "player_set_health", "player_damage", "player_animate", "player_colors",
		"player_target", "selected_item", "anim_override", "camera_set", "camera_get",
		"container_create", "container_size", "slot_get", "slot_set", "hotbar_bind", "hotbar_selected",
		"ui_window", "ui_close", "ui_is_open", "notify", "hud_bar", "hud_text", "hud_remove",
		"input_bind", "randf", "randi"]
	var t := {}
	for n in names:
		t[n] = Callable(self, "_h_" + n)
	return t


func _h_log(mod_id, msg) -> void: _log(str(mod_id), str(msg))
func _h_report_error(mod_id, msg) -> void: report_error(str(mod_id), str(msg))
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


func _h_get_block(pos) -> int: return main.world.get_block(Vector3i(pos)) if main else 0
func _h_set_block(pos, id) -> bool: return main.world.set_block(Vector3i(pos), int(id)) if main and int(id) >= 0 else false


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


func _h_set_time(h) -> void:
	if main:
		main.time_of_day = fposmod(float(h), 24.0)


func _h_player_position() -> Vector3: return main.player.global_position if main else Vector3.ZERO


func _h_player_teleport(pos) -> void:
	if main:
		main.player.global_position = Vector3(pos)
		main.player.velocity = Vector3.ZERO
		main.player.reset_fall()


func _h_player_velocity() -> Vector3: return main.player.velocity if main else Vector3.ZERO


func _h_player_push(v) -> void:
	if main:
		main.player.velocity += Vector3(v)


func _h_player_set(stat, v) -> void: player_stats[str(stat)] = v
func _h_player_get(stat) -> Variant: return main.player.stat(str(stat)) if main else null
func _h_player_health() -> float: return main.player.health if main else 0.0


func _h_player_set_health(v) -> void:
	if main:
		main.player.set_health(float(v))


func _h_player_damage(amount, cause) -> void:
	if main:
		main.player.damage(float(amount), str(cause))


func _h_player_animate(name) -> void:
	if main:
		main.player.model.play(str(name))


func _h_player_colors(t) -> void:
	if t is Dictionary:
		for k in t:
			var c: Variant = t[k]
			model_colors[str(k)] = c if c is Color else Color.from_string(str(c), Color.WHITE)
		if main:
			main.player.model.apply_colors(model_colors)


func _h_player_target() -> Dictionary:
	if main == null or main.player.target.is_empty():
		return {}
	var t: Dictionary = main.player.target
	return {"pos": t.pos, "normal": t.normal, "block": main.world.get_block(t.pos)}


func _h_selected_item() -> Dictionary:
	if main == null:
		return {}
	return main.player.current_item()


func _h_anim_override(state, name) -> void:
	if str(name) == "":
		anim_overrides.erase(str(state))
	else:
		anim_overrides[str(state)] = str(name)


func _h_camera_set(key, v) -> void: camera_stats[str(key)] = v


func _h_camera_get(key) -> Variant:
	if camera_stats.has(str(key)):
		return camera_stats[str(key)]
	if main and str(key) == "mode":
		return main.player.camera_mode()
	return null


func _h_container_create(mod_id, id, size, persist) -> void:
	var n := int(size)
	var key := str(id)
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


func _h_container_size(id) -> int: return container_slots(str(id)).size()
func _h_slot_get(id, i) -> Dictionary: return slot(str(id), int(i))
func _h_slot_set(id, i, v) -> void: set_slot(str(id), int(i), v if v is Dictionary else {})


func _h_hotbar_bind(container, first, count) -> void:
	hotbar = {"container": str(container), "first": int(first), "count": int(count)}
	hotbar_changed.emit()


func _h_hotbar_selected() -> int: return main.player.selected if main else 0


func _h_ui_window(mod_id, spec) -> void:
	var d: Dictionary = spec if spec is Dictionary else {}
	d["mod"] = str(mod_id)
	open_windows[str(d.get("id", mod_id))] = d
	ui_window_requested.emit(d)


func _h_ui_close(id) -> void: ui_close_requested.emit(str(id))
func _h_ui_is_open(id) -> bool: return open_windows.has(str(id))
func _h_notify(text) -> void: notified.emit(str(text))


func _h_hud_bar(mod_id, spec) -> void:
	var d: Dictionary = spec if spec is Dictionary else {}
	d["type"] = "bar"
	d["mod"] = str(mod_id)
	hud[str(d.get("id", mod_id))] = d
	hud_changed.emit()


func _h_hud_text(mod_id, spec) -> void:
	var d: Dictionary = spec if spec is Dictionary else {}
	d["type"] = "text"
	d["mod"] = str(mod_id)
	hud[str(d.get("id", mod_id))] = d
	hud_changed.emit()


func _h_hud_remove(id) -> void:
	hud.erase(str(id))
	hud_changed.emit()


func _h_input_bind(mod_id, id, key, label) -> void:
	for b in binds:
		if b.id == str(id):
			return
	binds.append({"id": str(id), "mod": str(mod_id), "key": str(key).to_upper(), "label": str(label)})
	binds_changed.emit()


func _h_randf() -> float: return _rng.randf()
func _h_randi(a, b) -> int: return _rng.randi_range(int(a), int(b))
