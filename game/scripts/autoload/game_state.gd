extends Node
## Lista światów na dysku, tworzenie, usuwanie i bieżący świat.

const ROOT := "user://worlds"

var current := {}   # zawartość world.json bieżącego świata
var current_dir := ""
var autotest_dir := ""  # ustawiane przez test automatyczny z menu


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ROOT)


func list_worlds() -> Array:
	var out := []
	var dir := DirAccess.open(ROOT)
	if dir == null:
		return out
	for sub in dir.get_directories():
		var info := read_info(ROOT.path_join(sub))
		if not info.is_empty():
			info["dir"] = ROOT.path_join(sub)
			out.append(info)
	out.sort_custom(func(a, b): return a.get("played", 0) > b.get("played", 0))
	return out


func read_info(dir: String) -> Dictionary:
	var p := dir.path_join("world.json")
	if not FileAccess.file_exists(p):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


func write_info(dir: String, info: Dictionary) -> void:
	var f := FileAccess.open(dir.path_join("world.json"), FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(info, "\t"))


static func seed_from_text(text: String) -> int:
	text = text.strip_edges()
	if text.is_empty():
		return randi() % 2147483647
	if text.is_valid_int():
		return int(text) % 2147483647
	return text.hash() & 0x7fffffff


func create_world(name: String, seed_text: String) -> String:
	name = name.strip_edges()
	if name.is_empty():
		name = "Nowy świat"
	var slug := name.to_lower().validate_filename().replace(" ", "_")
	var dir := ROOT.path_join(slug)
	var n := 2
	while DirAccess.dir_exists_absolute(dir):
		dir = ROOT.path_join("%s_%d" % [slug, n])
		n += 1
	DirAccess.make_dir_recursive_absolute(dir.path_join("chunks"))
	var now := int(Time.get_unix_time_from_system())
	var mods := {}
	for id in ModManager.effective_order():
		if ModManager.is_enabled(id):
			mods[id] = ModManager.snapshot(id)
	var info := {
		"name": name, "seed": seed_from_text(seed_text), "created": now, "played": now,
		"version": 3, "mods": mods, "time_of_day": -1.0, "player": {},
	}
	write_info(dir, info)
	return dir


func delete_world(dir: String) -> void:
	_rm(dir)


func _rm(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)
	for s in d.get_directories():
		_rm(path.path_join(s))
	DirAccess.remove_absolute(path)


func start(dir: String) -> void:
	current_dir = dir
	current = read_info(dir)
	get_tree().change_scene_to_file("res://main.tscn")


func back_to_menu() -> void:
	current = {}
	current_dir = ""
	get_tree().paused = false
	get_tree().change_scene_to_file("res://menu.tscn")


## Ustawienie moda zapisane w świecie (generowanie terenu zależy od świata, a nie od bieżących opcji).
func world_mod_value(id: String, key: String) -> Variant:
	var m: Dictionary = current.get("mods", {}).get(id, {})
	if m.has(key):
		return m[key]
	return ModManager.get_value(id, key)


func world_has_mod(id: String) -> bool:
	return current.get("mods", {}).has(id)
