extends SceneTree
## Paczki zasobów: eksport szablonu i podmiana tekstury, ikony, modelu stworzenia i nazwy z paczki.
## Uruchomienie: godot --headless --path game -s tests/resources.gd

const RP := "user://resourcepacks/_test_rp"
const TPL := "user://resourcepacks/_test_szablon"


func _initialize() -> void:
	_run.call_deferred()


func _rm(dir: String) -> void:
	if not DirAccess.dir_exists_absolute(dir):
		return
	for sub in DirAccess.get_directories_at(dir):
		_rm(dir.path_join(sub))
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)


func _run() -> void:
	var mm: Node = root.get_node("/root/ModManager")
	var mods: Node = root.get_node("/root/Mods")
	_rm(RP)
	_rm(TPL)
	# eksport szablonu z gry bez paczek
	var reg0: Registry = mods.start_content("")
	var c: Dictionary = ResourceExport.export(reg0, TPL)
	var files := 0
	for sub in ["blocks", "items", "sounds", "entities", "lang"]:
		files += DirAccess.get_files_at(TPL.path_join(sub)).size()
	print("SZABLON ", c, " plików=", files, " kamień=", FileAccess.file_exists(TPL.path_join("blocks/stone.png")),
		" piec przód=", FileAccess.file_exists(TPL.path_join("blocks/furnace.north.png")), " koń=", FileAccess.file_exists(TPL.path_join("entities/horse.txt")))
	mods.stop()
	# własna paczka: czerwony kamień, ikona jabłka, koń z modelu GLB, inna nazwa
	for sub in ["blocks", "items", "entities", "lang"]:
		DirAccess.make_dir_recursive_absolute(RP.path_join(sub))
	var red := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	red.fill(Color(0.9, 0.1, 0.1))
	red.save_png(RP.path_join("blocks/stone.png"))
	red.save_png(RP.path_join("items/apple.png"))
	var glb := FileAccess.get_file_as_bytes("res://mods/podstawowa/mods/monsters/models/zombie.glb")
	FileAccess.open(RP.path_join("entities/horse.glb"), FileAccess.WRITE).store_buffer(glb)
	FileAccess.open(RP.path_join("lang/pl.json"), FileAccess.WRITE).store_string('{"horses:horse": "Rumak"}')
	mm.scan()
	mm.load_user()
	mm.set_resource_enabled("_test_rp", true)
	var reg: Registry = mods.start_content("")
	var stone := reg.id_of("stone")
	var px: Color = reg.tile_images[reg.tiles[stone * 6 + 2]].get_pixel(4, 4)
	print("PACZKA kamień kolor=", px, " jabłko ikona=", reg.items.get("apple", {}).get("icon", ""))
	print("PACZKA koń model=", reg.entities.get("horse", {}).get("model", {}).get("file", ""), " nazwa=", reg.entities.get("horse", {}).get("name", ""))
	mods.stop()
	mm.set_resource_enabled("_test_rp", false)
	_rm(RP)
	_rm(TPL)
	mm.scan()
	mm.load_user()
	quit()
