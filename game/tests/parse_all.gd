extends SceneTree
## Wczytuje wszystkie skrypty GDScript, żeby wyłapać błędy składni i typów.

func _init() -> void:
	process_frame.connect(_check, CONNECT_ONE_SHOT)


func _check() -> void:
	var bad := 0
	for f in _walk("res://scripts") + _walk("res://tests"):
		var s := load(f) as GDScript
		if s == null or not s.can_instantiate() and not f.ends_with("parse_all.gd"):
			if s == null or s.reload() != OK:
				print("BŁĄD: ", f)
				bad += 1
	print("parse_all: ", bad, " błędów")
	quit(1 if bad > 0 else 0)


func _walk(dir: String) -> Array:
	var out := []
	for f in DirAccess.get_files_at(dir):
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for d in DirAccess.get_directories_at(dir):
		out += _walk(dir.path_join(d))
	return out
