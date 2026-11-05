extends Node
## Opcje gracza zapisywane w user://settings.cfg (niezależne od świata i modów).

signal changed

const PATH := "user://settings.cfg"

var render_distance := 8
var mouse_sensitivity := 1.0
var touch_sensitivity := 1.0
var fov := 72.0
var show_debug := true
var fullscreen := false
var shadows := true
var far_view := 3        # daleki widok: zasięg uproszczonego terenu jako wielokrotność zasięgu chunków (0 = wyłączony)
var water_waves := true
var player_name := "Gracz"  # nazwa gracza (konto w grze wieloosobowej, podpis nad głową)
var last_address := "127.0.0.1"
var last_port := 7777
var sound_volume := 0.8  # głośność dźwięków 0..1
var brightness := 0.3    # jasność w ciemności (jaskinie, noc): 0 = prawie czarno, 1 = jaśniej


func _ready() -> void:
	if OS.has_feature("web"):
		render_distance = 4
		shadows = false
		far_view = 0
	load_settings()
	apply_window()


func max_render_distance() -> int:
	return 6 if OS.has_feature("web") else 16


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	render_distance = clampi(cfg.get_value("video", "render_distance", render_distance), 2, max_render_distance())
	fov = cfg.get_value("video", "fov", fov)
	fullscreen = cfg.get_value("video", "fullscreen", fullscreen)
	shadows = cfg.get_value("video", "shadows", shadows)
	show_debug = cfg.get_value("video", "show_debug", show_debug)
	far_view = clampi(cfg.get_value("video", "far_view", far_view), 0, 4)
	water_waves = cfg.get_value("video", "water_waves", water_waves)
	brightness = cfg.get_value("video", "brightness", brightness)
	sound_volume = cfg.get_value("audio", "volume", sound_volume)
	player_name = cfg.get_value("player", "name", player_name)
	last_address = cfg.get_value("player", "address", last_address)
	last_port = cfg.get_value("player", "port", last_port)
	mouse_sensitivity = cfg.get_value("controls", "mouse_sensitivity", mouse_sensitivity)
	touch_sensitivity = cfg.get_value("controls", "touch_sensitivity", touch_sensitivity)


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("video", "render_distance", render_distance)
	cfg.set_value("video", "fov", fov)
	cfg.set_value("video", "fullscreen", fullscreen)
	cfg.set_value("video", "shadows", shadows)
	cfg.set_value("video", "show_debug", show_debug)
	cfg.set_value("video", "far_view", far_view)
	cfg.set_value("video", "water_waves", water_waves)
	cfg.set_value("video", "brightness", brightness)
	cfg.set_value("audio", "volume", sound_volume)
	cfg.set_value("player", "name", player_name)
	cfg.set_value("player", "address", last_address)
	cfg.set_value("player", "port", last_port)
	cfg.set_value("controls", "mouse_sensitivity", mouse_sensitivity)
	cfg.set_value("controls", "touch_sensitivity", touch_sensitivity)
	cfg.save(PATH)
	apply_window()
	changed.emit()


func apply_window() -> void:
	if OS.has_feature("web") or DisplayServer.get_name() == "headless":
		return
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
