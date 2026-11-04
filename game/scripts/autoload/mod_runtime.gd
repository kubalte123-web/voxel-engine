extends Node
## Środowisko uruchomieniowe modów w Lua.
## Jeden stan Lua, w nim każdy mod ma własne, odizolowane środowisko (_ENV) z obiektem `engine`.
## Mody ładują się w kolejności z menedżera modów; mody z "requires" czekają na swoje zależności.
## Silnik wywołuje haki (before/after) i zdarzenia, a mody odpowiadają przez API z prelude.lua.

signal ui_window_requested(spec: Dictionary)
signal ui_close_requested(id: String)
signal notified(text: String)
signal binds_changed
signal hotbar_changed

const MAX_STACK := 64
const LIBS := 1 | 4 | 8 | 32 | 64 | 4096 | 8192  # base, coroutine, string, math, table, utf8, typy Godota
const MAX_ERRORS_SHOWN := 5

var lua: Object = null
var _dispatch: Object = null
var _make_env: Object = null
var _input: Object = null
var _window_action: Object = null

var main: Node = null
var loaded: Array[String] = []
var load_errors := {}   # id moda -> tekst błędu przy wczytywaniu
var logs: Array[String] = []
var _errors_shown := 0

var containers := {}    # id -> {"owner": String, "persist": bool, "slots": Array[Dictionary]}
var storage := {}       # id moda -> Dictionary
var binds: Array = []   # [{"id", "mod", "key", "label"}]
var hotbar := {"container": "", "first": 0, "count": 0}
var open_windows := {}  # id -> spec
var player_stats := {}  # nadpisania statystyk gracza przez mody
var camera_stats := {}  # nadpisania kamery przez mody


func available() -> bool:
	return ClassDB.class_exists("LuaState")


func is_running() -> bool:
	return lua != null


# ---------- uruchamianie i zatrzymywanie ----------

func start(main_node: Node, world_dir: String) -> void:
	stop()
	main = main_node
	_load_data(world_dir)
	if not available():
		load_errors["_"] = "Brak środowiska Lua w tej wersji gry."
		return
	lua = ClassDB.instantiate("LuaState")
	lua.open_libraries(LIBS)
	lua.globals["host"] = lua.create_table(_host_table())
	var code := FileAccess.get_file_as_string("res://scripts/mods/prelude.lua")
	var res: Variant = lua.do_string(code, "@prelude.lua")
	if not _is_table(res):
		load_errors["_"] = "Błąd prelude: %s" % str(res)
		push_error(load_errors["_"])
		lua = null
		return
	_dispatch = res.get("dispatch")
	_make_env = res.get("make_env")
	_input = res.get("input")
	_window_action = res.get("window_action")
	for id in resolve_load_order():
		_load_mod(id)
	emit_event("world_ready", {})


func stop() -> void:
	_dispatch = null
	_make_env = null
	_input = null
	_window_action = null
	lua = null
	main = null
	loaded.clear()
	load_errors.clear()
	logs.clear()
	containers.clear()
	storage.clear()
	binds.clear()
	open_windows.clear()
	player_stats.clear()
	camera_stats.clear()
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


func _load_mod(id: String) -> void:
	var m: Dictionary = ModManager.manifests[id]
	var scripts: Array = m.get("scripts", [])
	if scripts.is_empty():
		loaded.append(id)  # mod tylko z danymi i ustawieniami
		return
	var env: Variant = _make_env.invoke(id)
	for s in scripts:
		var path: String = String(m.path).path_join(s)
		if not FileAccess.file_exists(path):
			_fail(id, "brak pliku " + s)
			return
		var r: Variant = lua.do_string(FileAccess.get_file_as_string(path), "@%s/%s" % [id, s], env)
		if _is_error(r):
			_fail(id, str(r))
			return
	loaded.append(id)
	_log(id, "wczytany")


func _fail(id: String, msg: String) -> void:
	load_errors[id] = msg
	report_error(id, msg)


static func _is_error(v: Variant) -> bool:
	return v is Object and v != null and v.get_class() == "LuaError"


static func _is_table(v: Variant) -> bool:
	return v is Object and v != null and v.get_class() == "LuaTable"


# ---------- wywołania z silnika ----------

## Hak „przed”: mody mogą zmienić pola ctx albo ustawić ctx.cancel = true.
func before(name: String, ctx: Dictionary) -> Dictionary:
	return _call("before", name, ctx)


## Hak „po”: wywoływany po domyślnym działaniu silnika.
func after(name: String, ctx: Dictionary) -> Dictionary:
	return _call("after", name, ctx)


func emit_event(name: String, data: Dictionary) -> void:
	_call("event", name, data)


func _call(kind: String, name: String, ctx: Dictionary) -> Dictionary:
	if _dispatch == null:
		return ctx
	var r: Variant = _dispatch.invoke(kind, name, ctx)
	if _is_error(r):
		report_error("silnik", "%s %s: %s" % [kind, name, str(r)])
		return ctx
	return r if r is Dictionary else ctx


func press_bind(id: String) -> void:
	if _input:
		_input.invoke(id)


func window_action(action: String) -> void:
	if _window_action:
		_window_action.invoke(action)


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
	if int(v.get("count", 0)) <= 0 or int(v.get("block", 0)) == 0:
		v = {}
	s[i] = {"block": int(v.block), "count": int(v.count)} if not v.is_empty() else {}
	if id == hotbar.container:
		hotbar_changed.emit()


## Blok w wybranym miejscu paska: -1 gdy pasek nie jest podpięty do kontenera.
func hotbar_block(index: int) -> int:
	if hotbar.container == "":
		return -1
	return int(slot(hotbar.container, hotbar.first + index).get("block", 0))


func hotbar_count(index: int) -> int:
	if hotbar.container == "":
		return -1
	return int(slot(hotbar.container, hotbar.first + index).get("count", 0))


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
			slots.append({"block": int(sl.block), "count": int(sl.count)} if sl is Dictionary and sl.has("block") else {})
		containers[id] = {"owner": "", "persist": true, "slots": slots}


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
	var names := ["log", "report_error", "setting", "storage_get", "storage_set", "block_id", "block_key",
		"block_name", "block_list", "get_block", "set_block", "biome", "time_of_day", "player_position",
		"player_set", "player_get", "camera_set", "camera_get", "container_create", "container_size",
		"slot_get", "slot_set", "max_stack", "hotbar_bind", "hotbar_selected", "ui_window", "ui_close",
		"ui_is_open", "notify", "input_bind"]
	var t := {}
	for n in names:
		t[n] = Callable(self, "_h_" + n)
	return t


func _h_log(mod_id, msg) -> void: _log(str(mod_id), str(msg))
func _h_report_error(mod_id, msg) -> void: report_error(str(mod_id), str(msg))
func _h_setting(mod_id, key) -> Variant: return ModManager.get_value(str(mod_id), str(key))
func _h_storage_get(mod_id, key) -> Variant: return storage.get(str(mod_id), {}).get(str(key))


func _h_storage_set(mod_id, key, v) -> void:
	if not storage.has(str(mod_id)):
		storage[str(mod_id)] = {}
	storage[str(mod_id)][str(key)] = v


func _h_block_id(key) -> int: return Blocks.KEYS.find(str(key))
func _h_block_key(id) -> String: return Blocks.KEYS[int(id)] if int(id) >= 0 and int(id) < Blocks.COUNT else ""
func _h_block_name(id) -> String: return Blocks.NAMES[int(id)] if int(id) >= 0 and int(id) < Blocks.COUNT else ""


func _h_block_list() -> Array:
	var out := []
	for i in range(1, Blocks.COUNT):
		out.append({"id": i, "key": Blocks.KEYS[i], "name": Blocks.NAMES[i]})
	return out


func _h_get_block(pos) -> int: return main.world.get_block(Vector3i(pos)) if main else 0
func _h_set_block(pos, id) -> bool: return main.world.set_block(Vector3i(pos), int(id)) if main else false


func _h_biome(pos) -> String:
	if main == null:
		return ""
	var p := Vector3i(pos)
	return Terrain.BIOME_NAMES[main.world.terrain.column(p.x, p.z).y]


func _h_time_of_day() -> float: return main.time_of_day if main else 12.0
func _h_player_position() -> Vector3: return main.player.global_position if main else Vector3.ZERO
func _h_player_set(stat, v) -> void: player_stats[str(stat)] = v
func _h_player_get(stat) -> Variant: return main.player.stat(str(stat)) if main else null
func _h_camera_set(key, v) -> void: camera_stats[str(key)] = v
func _h_camera_get(key) -> Variant: return camera_stats.get(str(key))


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
func _h_max_stack() -> int: return MAX_STACK


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


func _h_input_bind(mod_id, id, key, label) -> void:
	for b in binds:
		if b.id == str(id):
			return
	binds.append({"id": str(id), "mod": str(mod_id), "key": str(key).to_upper(), "label": str(label)})
	binds_changed.emit()
