extends Node
## Menedżer modów: wykrywa mody (wbudowane w res://mods i gracza w user://mods), trzyma ręczną kolejność,
## włączenie i ustawienia każdego moda. Profil serwera ma pierwszeństwo: wymusza kolejność, włączenie
## i wartości ustawień, a interfejs pokazuje je jako zablokowane.

signal changed

const USER_CFG := "user://mods.cfg"
const DIRS := ["res://mods", "user://mods"]

var manifests := {}       # id -> Dictionary (zawartość mod.json + "path")
var order: Array[String] = []
var enabled := {}         # id -> bool
var values := {}          # id -> {klucz: wartość} (ustawienia gracza)
var server_profile := {}  # {"order": [...], "enabled": {...}, "settings": {id: {klucz: wartość}}}
var server_mods := {}     # id -> folder moda pobranego z serwera (zastępuje mod gracza tylko na czas gry na tym serwerze)


func _ready() -> void:
	scan()
	load_user()


func scan() -> void:
	manifests.clear()
	for dir_path in DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			var path: String = dir_path.path_join(sub).path_join("mod.json")
			if not FileAccess.file_exists(path):
				continue
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
				push_warning("Pominięto mod z błędnym manifestem: " + path)
				continue
			parsed["path"] = dir_path.path_join(sub)
			manifests[parsed.id] = parsed
	for id in server_mods:
		var path: String = server_mods[id].path_join("mod.json")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("id", "")) == id:
			parsed["path"] = server_mods[id]
			parsed["from_server"] = true
			manifests[id] = parsed


## Mody pobrane z serwera: używane zamiast własnych do końca połączenia.
func use_server_mods(mods: Dictionary) -> void:
	server_mods = mods.duplicate()
	scan()


func clear_server_mods() -> void:
	if server_mods.is_empty():
		return
	server_mods.clear()
	scan()


## Odciski wszystkich dostępnych modów (klient wysyła je serwerowi przy dołączaniu).
func fingerprints() -> Dictionary:
	var out := {}
	for id in manifests:
		out[id] = ModPack.fingerprint(manifests[id].path)
	return out


func load_user() -> void:
	var cfg := ConfigFile.new()
	cfg.load(USER_CFG)
	var saved_order: Array = cfg.get_value("mods", "order", [])
	order.clear()
	for id in saved_order:
		if manifests.has(id):
			order.append(id)
	var rest := manifests.keys()
	# nowe mody: najpierw wymagane i biblioteki, potem reszta alfabetycznie
	rest.sort_custom(func(a, b):
		var ra := _rank(a)
		var rb := _rank(b)
		return ra < rb if ra != rb else a < b)
	for id in rest:
		if not order.has(id):
			order.append(id)
	for id in manifests:
		enabled[id] = cfg.get_value("enabled", id, manifests[id].get("enabled_by_default", true))
		var v: Dictionary = cfg.get_value("settings", id, {})
		values[id] = v


func _rank(id: String) -> int:
	var m: Dictionary = manifests[id]
	if m.get("required", false):
		return 0
	if m.get("library", false):
		return 1
	return 2


func save_user(notify: bool = true) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("mods", "order", order)
	for id in manifests:
		cfg.set_value("enabled", id, enabled.get(id, true))
		cfg.set_value("settings", id, values.get(id, {}))
	cfg.save(USER_CFG)
	if notify:
		changed.emit()


# ---------- kolejność i włączenie ----------

func effective_order() -> Array[String]:
	if server_profile.has("order"):
		var out: Array[String] = []
		for id in server_profile.order:
			if manifests.has(id):
				out.append(id)
		return out
	return order


func move(id: String, delta: int) -> void:
	if order_locked():
		return
	var i := order.find(id)
	var j := clampi(i + delta, 0, order.size() - 1)
	if i < 0 or i == j:
		return
	order.remove_at(i)
	order.insert(j, id)
	save_user()


func order_locked() -> bool:
	return server_profile.has("order")


func is_enabled(id: String) -> bool:
	if server_profile.has("enabled") and server_profile.enabled.has(id):
		return server_profile.enabled[id]
	if server_profile.has("order"):
		return server_profile.order.has(id)
	return enabled.get(id, false) and manifests.has(id)


func enabled_locked(id: String) -> bool:
	return server_profile.has("order") or (server_profile.has("enabled") and server_profile.enabled.has(id))


func set_enabled(id: String, on: bool) -> void:
	if enabled_locked(id) or manifests.get(id, {}).get("required", false):
		return
	enabled[id] = on
	save_user()


# ---------- ustawienia ----------

func setting_defs(id: String) -> Array:
	return manifests.get(id, {}).get("settings", [])


func _def(id: String, key: String) -> Dictionary:
	for d in setting_defs(id):
		if d.key == key:
			return d
	return {}


func is_locked(id: String, key: String) -> bool:
	return server_profile.get("settings", {}).get(id, {}).has(key)


## Wartość efektywna: serwer > gracz > domyślna z manifestu.
func get_value(id: String, key: String) -> Variant:
	var srv: Dictionary = server_profile.get("settings", {}).get(id, {})
	if srv.has(key):
		return srv[key]
	var user: Dictionary = values.get(id, {})
	if user.has(key):
		return user[key]
	return _def(id, key).get("default")


func set_value(id: String, key: String, v: Variant) -> void:
	if is_locked(id, key):
		return
	if not values.has(id):
		values[id] = {}
	values[id][key] = v
	save_user(false)  # bez przebudowy ekranu, żeby nie przerywać przesuwania suwaka


func reset(id: String) -> void:
	values[id] = {}
	save_user()


func snapshot(id: String) -> Dictionary:
	var out := {}
	for d in setting_defs(id):
		out[d.key] = get_value(id, d.key)
	return out


## Wywoływane po połączeniu z serwerem (etap multiplayer). Pusty słownik zdejmuje blokady.
func apply_server_profile(profile: Dictionary) -> void:
	server_profile = profile
	changed.emit()
