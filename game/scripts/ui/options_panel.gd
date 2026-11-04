class_name OptionsPanel
extends VBoxContainer
## Opcje gracza. Używane w menu głównym i w menu pauzy. Każda zmiana zapisuje się od razu.

var on_back: Callable


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	add_child(UI.label("Opcje", 30))
	var s := Settings
	var web := OS.has_feature("web")
	add_child(UI.slider_row("Zasięg widzenia", 2, s.max_render_distance(), 1, s.render_distance,
		func(v): return "%d chunków" % int(v), func(v): s.render_distance = int(v); s.save_settings()))
	add_child(UI.slider_row("Daleki widok", 0, 4, 1, s.far_view,
		func(v): return "wyłączony" if int(v) == 0 else "%d× dalej" % (int(v) + 1), func(v): s.far_view = int(v); s.save_settings()))
	add_child(UI.check_row("Fale na wodzie", s.water_waves, func(on): s.water_waves = on; s.save_settings()))
	add_child(UI.slider_row("Pole widzenia", 55, 100, 1, s.fov,
		func(v): return "%d°" % int(v), func(v): s.fov = v; s.save_settings()))
	add_child(UI.slider_row("Czułość myszy", 0.2, 3.0, 0.1, s.mouse_sensitivity,
		func(v): return "%.1f×" % v, func(v): s.mouse_sensitivity = v; s.save_settings()))
	add_child(UI.slider_row("Czułość dotyku", 0.2, 3.0, 0.1, s.touch_sensitivity,
		func(v): return "%.1f×" % v, func(v): s.touch_sensitivity = v; s.save_settings()))
	add_child(UI.check_row("Pokaż informacje techniczne (FPS, chunki)", s.show_debug,
		func(on): s.show_debug = on; s.save_settings()))
	if not web:
		add_child(UI.check_row("Cienie", s.shadows, func(on): s.shadows = on; s.save_settings()))
		add_child(UI.check_row("Pełny ekran", s.fullscreen, func(on): s.fullscreen = on; s.save_settings()))
	else:
		add_child(UI.wrap("W przeglądarce zasięg widzenia jest ograniczony do 6 chunków, a cienie są wyłączone."))
	var back := UI.button("Wróć", func(): if on_back.is_valid(): on_back.call())
	add_child(back)
