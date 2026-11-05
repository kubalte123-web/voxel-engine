extends Node
## Menedżer modów: wykrywa mody (wbudowane w res://mods i gracza w user://mods), trzyma ręczną kolejność,
## włączenie i ustawienia każdego moda.
## Paczka modów to folder z pack.json i podfolderem mods/ z modułami (np. res://mods/podstawowa): w menu
## jedna pozycja, którą można włączyć albo otworzyć i ustawić każdy moduł osobno. Pola mod.json:
## "replaces": ["horses"] – mod zastępuje moduł (ten się nie wczytuje, a zależni dostają zastępcę),
## "conflicts": ["x"] – nie może działać razem z x (włączenie jednego wyłącza drugi). Profil serwera ma pierwszeństwo: wymusza kolejność, włączenie
## i wartości ustawień, a interfejs pokazuje je jako zablokowane.

signal changed

const USER_CFG := "user://mods.cfg"
const DIRS := ["res://mods", "user://mods"]
const RES_DIR := "user://resourcepacks"   # paczki zasobów gracza (tekstury, modele, dźwięki, teksty bez kodu)

var manifests := {}       # id -> Dictionary (zawartość mod.json + "path", "pack" dla modułów paczki)
var packs := {}           # id paczki -> pack.json + "path", "modules" (ids w kolejności alfabetycznej)
var pack_enabled := {}    # id paczki -> bool
var resource_packs := []  # [{id, name, description, path}] wszystkie znalezione
var resource_order: Array[String] = []   # włączone paczki zasobów, pierwsza ma pierwszeństwo
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
	packs.clear()
	for dir_path in DIRS:
		var dir := DirAccess.open(dir_path)
		if dir == null:
			continue
		for sub in dir.get_directories():
			var folder: String = dir_path.path_join(sub)
			if FileAccess.file_exists(folder.path_join("pack.json")):
				_scan_pack(folder)
			else:
				_scan_mod(folder, "")
	_scan_resources()
	for id in server_mods:
		var path: String = server_mods[id].path_join("mod.json")
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if typeof(parsed) == TYPE_DICTIONARY and str(parsed.get("id", "")) == id:
			parsed["path"] = server_mods[id]
			parsed["from_server"] = true
			manifests[id] = parsed


static func _arr(v: Variant) -> Array:
	return v if v is Array else ([] if v == null else [v])


func _scan_mod(folder: String, pack: String) -> void:
	var path := folder.path_join("mod.json")
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("id"):
		push_warning("Pominięto mod z błędnym manifestem: " + path)
		return
	parsed["path"] = folder
	if pack != "":
		parsed["pack"] = pack
		packs[pack].modules.append(parsed.id)
	manifests[parsed.id] = parsed


func _scan_pack(folder: String) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("pack.json")))
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Pominięto paczkę z błędnym pack.json: " + folder)
		return
	var id := str(parsed.get("id", folder.get_file()))
	parsed["id"] = id
	parsed["path"] = folder
	parsed["modules"] = []
	packs[id] = parsed
	var dir := DirAccess.open(folder.path_join("mods"))
	if dir:
		for sub in dir.get_directories():
			_scan_mod(folder.path_join("mods").path_join(sub), id)
	(parsed.modules as Array).sort()


# ---------- paczki zasobów ----------

func _scan_resources() -> void:
	resource_packs.clear()
	DirAccess.make_dir_recursive_absolute(RES_DIR)
	var dir := DirAccess.open(RES_DIR)
	if dir == null:
		return
	for sub in dir.get_directories():
		var folder := RES_DIR.path_join(sub)
		var info: Variant = JSON.parse_string(FileAccess.get_file_as_string(folder.path_join("pack.json"))) if FileAccess.file_exists(folder.path_join("pack.json")) else null
		var d: Dictionary = info if info is Dictionary else {}
		resource_packs.append({"id": sub, "name": str(d.get("name", sub)), "description": str(d.get("description", "")), "path": folder})


func resource_pack(id: String) -> Dictionary:
	for r in resource_packs:
		if r.id == id:
			return r
	return {}


func set_resource_enabled(id: String, on: bool) -> void:
	resource_order.erase(id)
	if on:
		resource_order.insert(0, id)
	_reset_menu_registry()
	save_user()


func _reset_menu_registry() -> void:
	var m := get_node_or_null("/root/Mods")
	if m and not m.is_running():
		m.set("_menu_registry", null)


func move_resource(id: String, delta: int) -> void:
	var i := resource_order.find(id)
	var j := clampi(i + delta, 0, resource_order.size() - 1)
	if i < 0 or i == j:
		return
	resource_order[i] = resource_order[j]
	resource_order[j] = id
	_reset_menu_registry()
	save_user()


## Plik z włączonej paczki zasobów (pierwsza na liście wygrywa) albo "". rel np. "blocks/stone.png".
func resource_file(rel: String) -> String:
	for id in resource_order:
		var r := resource_pack(id)
		if not r.is_empty() and FileAccess.file_exists(str(r.path).path_join(rel)):
			return str(r.path).path_join(rel)
	return ""


## Paczka zawiera moduł wymagany (np. świat podstawowy): nie da się jej wyłączyć.
func pack_required(pack: String) -> bool:
	for id in packs.get(pack, {}).get("modules", []):
		if manifests.get(id, {}).get("required", false):
			return true
	return false


func is_pack_enabled(pack: String) -> bool:
	if server_profile.has("order") or server_profile.has("enabled"):
		for id in packs.get(pack, {}).get("modules", []):
			if is_enabled(id):
				return true
		return false
	return pack_required(pack) or bool(pack_enabled.get(pack, true))


func set_pack_enabled(pack: String, on: bool) -> void:
	if order_locked() or pack_required(pack):
		return
	pack_enabled[pack] = on
	save_user()


## Moduły paczki z powrotem w ustawieniu domyślnym paczki (włączenie i ustawienia).
func reset_pack(pack: String) -> void:
	for id in packs.get(pack, {}).get("modules", []):
		enabled[id] = _default_enabled(id)
	save_user()


func _default_enabled(id: String) -> bool:
	var m: Dictionary = manifests[id]
	var pk: Dictionary = packs.get(str(m.get("pack", "")), {})
	var defs: Dictionary = pk.get("defaults", {}) if pk.get("defaults") is Dictionary else {}
	return bool(defs.get(id, m.get("enabled_by_default", true)))


## Mod, który zastępuje dany moduł ("replaces" w mod.json), jeśli jest włączony; inaczej "".
func replacement_of(id: String) -> String:
	for other in manifests:
		if other != id and _arr(manifests[other].get("replaces")).has(id) and _enabled_raw(other):
			return other
	return ""


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
		enabled[id] = cfg.get_value("enabled", id, _default_enabled(id))
		var v: Dictionary = cfg.get_value("settings", id, {})
		values[id] = v
	for pk in packs:
		pack_enabled[pk] = cfg.get_value("packs", pk, packs[pk].get("enabled_by_default", true))
	resource_order.clear()
	for id in cfg.get_value("resources", "order", []):
		if not resource_pack(str(id)).is_empty():
			resource_order.append(str(id))


func _rank(id: String) -> int:
	var m: Dictionary = manifests[id]
	if m.get("required", false):
		return 0
	if m.get("library", false):
		return 1
	return 2 if m.has("pack") else 3   # mody gracza po modułach paczek (mogą je nadpisywać)


func save_user(notify: bool = true) -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("mods", "order", order)
	for id in manifests:
		cfg.set_value("enabled", id, enabled.get(id, true))
		cfg.set_value("settings", id, values.get(id, {}))
	for pk in packs:
		cfg.set_value("packs", pk, pack_enabled.get(pk, true))
	cfg.set_value("resources", "order", resource_order)
	cfg.save(USER_CFG)
	if notify:
		changed.emit()


# ---------- kolejność i włączenie ----------

# ---------- zależności z wersjami ----------

## Wpis z "requires": "modkit", "modkit>=0.2", "backpack^1.0", "ores~0.3", "base=1.2.0" -> [id, op, wersja].
static func dep_parse(r: String) -> Array:
	var t := r.replace(" ", "")
	for op in [">=", "<=", "==", "=", ">", "<", "^", "~"]:
		var i := t.find(op)
		if i > 0:
			return [t.substr(0, i), "=" if op == "==" else op, t.substr(i + op.length())]
	return [t, "", ""]


static func _ver(v: String) -> Array:
	var out := [0, 0, 0]
	var parts := v.split(".")
	for i in mini(3, parts.size()):
		out[i] = int(parts[i])
	return out


static func _cmp(a: Array, b: Array) -> int:
	for i in 3:
		if a[i] != b[i]:
			return -1 if a[i] < b[i] else 1
	return 0


## Czy wersja `have` spełnia warunek: ^ – ta sama główna wersja i nie starsza, ~ – ta sama główna i poboczna.
static func version_ok(have: String, op: String, want: String) -> bool:
	if op == "":
		return true
	var h := _ver(have)
	var w := _ver(want)
	var c := _cmp(h, w)
	match op:
		">=": return c >= 0
		">": return c > 0
		"<=": return c <= 0
		"<": return c < 0
		"=": return c == 0
		"^": return c >= 0 and h[0] == w[0]
		"~": return c >= 0 and h[0] == w[0] and h[1] == w[1]
	return true


## Opis niespełnionej wersji zależności albo "" (brak moda sprawdza się osobno).
func dep_version_problem(r: String) -> String:
	var d := dep_parse(r)
	if not manifests.has(d[0]) or d[1] == "":
		return ""
	var have := str(manifests[d[0]].get("version", "0.0.0"))
	if version_ok(have, d[1], d[2]):
		return ""
	return "%s %s%s (jest %s)" % [d[0], d[1], d[2], have]


func effective_order() -> Array[String]:
	if server_profile.has("order"):
		var out: Array[String] = []
		for id in server_profile.order:
			if manifests.has(id):
				out.append(id)
		return out
	return order


## Przesunięcie wśród „rodzeństwa”: modułów tej samej paczki albo modów spoza paczek.
func move(id: String, delta: int) -> void:
	if order_locked():
		return
	var sib := siblings(id)
	var k := sib.find(id)
	var k2 := clampi(k + delta, 0, sib.size() - 1)
	if k < 0 or k == k2:
		return
	var i := order.find(id)
	var j := order.find(sib[k2])
	order[i] = sib[k2]
	order[j] = id
	save_user()


## Mody na tej samej liście w menu (moduły jednej paczki albo mody luzem), w kolejności wczytywania.
func siblings(id: String) -> Array[String]:
	var pack := str(manifests.get(id, {}).get("pack", ""))
	var out: Array[String] = []
	for m in effective_order():
		if str(manifests[m].get("pack", "")) == pack:
			out.append(m)
	return out


func order_locked() -> bool:
	return server_profile.has("order")


func is_enabled(id: String) -> bool:
	if server_profile.has("enabled") and server_profile.enabled.has(id):
		return server_profile.enabled[id]
	if server_profile.has("order"):
		return server_profile.order.has(id)
	return _enabled_raw(id) and replacement_of(id) == ""


## Włączony w ustawieniach (z paczką), bez sprawdzania zastępców.
func _enabled_raw(id: String) -> bool:
	if not manifests.has(id) or not enabled.get(id, false):
		return false
	var pk := str(manifests[id].get("pack", ""))
	return pk == "" or pack_required(pk) or bool(pack_enabled.get(pk, true))


## Włączony przez gracza (przełącznik), choć może nie działać, bo paczka jest wyłączona albo ktoś go zastępuje.
func is_checked(id: String) -> bool:
	if server_profile.has("enabled") or server_profile.has("order"):
		return is_enabled(id)
	return bool(enabled.get(id, false))


func enabled_locked(id: String) -> bool:
	return server_profile.has("order") or (server_profile.has("enabled") and server_profile.enabled.has(id))


func set_enabled(id: String, on: bool) -> void:
	if enabled_locked(id) or manifests.get(id, {}).get("required", false):
		return
	enabled[id] = on
	if on:   # mody, które się wykluczają, wyłączają się nawzajem
		for other in manifests:
			if other != id and (_arr(manifests[id].get("conflicts")).has(other) or _arr(manifests[other].get("conflicts")).has(id)):
				if not manifests[other].get("required", false):
					enabled[other] = false
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
