extends SceneTree
## Paczki modów: wykrywanie paczki, wyłączanie paczki, zastępowanie modułu (replaces) i wykluczanie (conflicts).
## Uruchomienie: godot --headless --path game -s tests/packs.gd

const TMP := "user://mods/_test_konie"
const TMP2 := "user://mods/_test_konflikt"


func _initialize() -> void:
	_run.call_deferred()


func _write(dir: String, files: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	for f in files:
		var fa := FileAccess.open(dir.path_join(f), FileAccess.WRITE)
		fa.store_string(files[f])


func _run() -> void:
	var mm: Node = root.get_node("/root/ModManager")
	var mods: Node = root.get_node("/root/Mods")
	_write(TMP, {
		"mod.json": '{"id": "_test_konie", "name": "Inne konie", "version": "1.0.0", "replaces": ["horses"], "requires": ["modkit"], "content": ["content.lua"], "scripts": ["main.lua"]}',
		"content.lua": 'engine.entities.register("horse", { name = "Kucyk", health = 5, parts = {}, ride = { seat = {0, 0.6, 0} } })',
		"main.lua": 'engine.export({ kto = "zastepca" })',
	})
	_write(TMP2, {
		"mod.json": '{"id": "_test_konflikt", "name": "Konflikt", "version": "1.0.0", "conflicts": ["ruins"], "scripts": []}',
	})
	mm.scan()
	mm.load_user()
	print("PACZKI ", mm.packs.keys(), " modułów=", mm.packs.get("podstawowa", {}).get("modules", []).size(), " wymagana=", mm.pack_required("podstawowa"))
	print("PACZKI base w paczce=", mm.manifests.get("base", {}).get("pack", ""), " ścieżka=", mm.manifests.get("base", {}).get("path", ""))
	mm.enabled["_test_konie"] = true
	mm.enabled["horses"] = true
	print("ZASTĘPOWANIE horses włączony=", mm.is_enabled("horses"), " zastępca=", mm.replacement_of("horses"), " zaznaczony=", mm.is_checked("horses"))
	var reg: Registry = mods.start_content("")
	print("ZASTĘPOWANIE wczytane: konie=", mods.order.has("horses"), " zastępca=", mods.order.has("_test_konie"), " koń=", reg.entities.get("horse", {}).get("name", "?"), " błędy=", mods.load_errors)
	# konflikt: włączenie jednego wyłącza drugi
	mm.enabled["ruins"] = true
	mm.set_enabled("_test_konflikt", true)
	print("KONFLIKT ruins po włączeniu konfliktu=", mm.enabled.get("ruins"), " konflikt=", mm.enabled.get("_test_konflikt"))
	mm.set_enabled("ruins", true)
	print("KONFLIKT po ponownym włączeniu ruins: konflikt=", mm.enabled.get("_test_konflikt"))
	# sprzątanie
	for d in [TMP, TMP2]:
		for f in DirAccess.get_files_at(d):
			DirAccess.remove_absolute(d.path_join(f))
		DirAccess.remove_absolute(d)
	mm.enabled.erase("_test_konie")
	mm.enabled.erase("_test_konflikt")
	mm.scan()
	mm.load_user()
	mm.save_user(false)
	quit()
