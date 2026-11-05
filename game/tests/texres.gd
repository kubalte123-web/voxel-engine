extends SceneTree
## Rozdzielczość tekstur: domyślna 16, wymuszona w opcjach, z paczki zasobów i własna jednego bloku.
## Uruchomienie: godot --headless --path game -s tests/texres.gd

const RP := "user://resourcepacks/_test_hd"


func _initialize() -> void:
	_run.call_deferred()


func _info(tag: String, reg: Registry) -> void:
	var stone := reg.id_of("stone")
	var marble := reg.id_of("marble_tiles")
	var ts := reg.tiles[stone * 6 + 2]
	var tm := reg.tiles[marble * 6 + 2]
	print("ROZDZ %s: domyślna=%d atlas=%s kamień=%d marmur=%d mipmapy=%.1f ikona kamienia=%d" % [tag, reg.texture_res, str(reg.atlas_size),
		reg.tile_images[ts].get_width(), reg.tile_images[tm].get_width() if marble > 0 else -1, reg.max_lod, reg.icon("stone").get_width()])


func _run() -> void:
	var mods: Node = root.get_node("/root/Mods")
	var mm: Node = root.get_node("/root/ModManager")
	var st: Node = root.get_node("/root/Settings")
	var keep: int = st.texture_resolution
	st.texture_resolution = 0
	_info("auto", mods.start_content(""))
	mods.stop()
	st.texture_resolution = 64
	_info("opcja 64", mods.start_content(""))
	mods.stop()
	st.texture_resolution = 0
	DirAccess.make_dir_recursive_absolute(RP.path_join("blocks"))
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.6, 0.9))
	img.save_png(RP.path_join("blocks/stone.png"))
	mm.scan()
	mm.load_user()
	mm.set_resource_enabled("_test_hd", true)
	_info("paczka 32", mods.start_content(""))
	mods.stop()
	mm.set_resource_enabled("_test_hd", false)
	DirAccess.remove_absolute(RP.path_join("blocks/stone.png"))
	DirAccess.remove_absolute(RP.path_join("blocks"))
	DirAccess.remove_absolute(RP)
	mm.scan()
	mm.load_user()
	st.texture_resolution = keep
	quit()
