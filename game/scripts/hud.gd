class_name Hud
extends Control
## Celownik, pasek bloków (z trybu kreatywnego albo z kontenera moda), informacje,
## podpowiedzi sterowania i powiadomienia od modów.

var player: Player
var world: World
var main: Node
var info: Label
var help: Label
var bar: HBoxContainer
var toasts: VBoxContainer
var slots: Array[Panel] = []
var touch_mode := false
var _timer := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	info = _outlined(15)
	info.position = Vector2(14, 10)
	add_child(info)

	if not touch_mode:
		help = _outlined(14)
		help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(help)
		Mods.binds_changed.connect(_update_help)
		_update_help()

	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if touch_mode:
		bar.scale = Vector2(0.8, 0.8)
	add_child(bar)

	toasts = VBoxContainer.new()
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.add_theme_constant_override("separation", 6)
	add_child(toasts)

	player.selection_changed.connect(func(_i): _rebuild_bar())
	Mods.hotbar_changed.connect(_rebuild_bar)
	Mods.notified.connect(notify)
	_rebuild_bar()


func _outlined(size_px: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_help() -> void:
	var t := "WASD ruch · Spacja skok · LPM kop · PPM postaw · 1-9 / kółko blok · V widok · Esc pauza"
	for b in Mods.binds:
		if b.key != "":
			t += " · %s %s" % [b.key, b.label]
	help.text = t


func _rebuild_bar() -> void:
	for c in bar.get_children():
		bar.remove_child(c)
		c.queue_free()
	slots.clear()
	var n := player.hotbar_size()
	for i in n:
		var b := Mods.hotbar_block(i)
		var count := Mods.hotbar_count(i)
		if b < 0:
			b = Blocks.PLACEABLE[i % Blocks.PLACEABLE.size()]
		var p := Panel.new()
		p.custom_minimum_size = Vector2(52, 52)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(3 if i == player.selected else 1)
		sb.border_color = Color(1, 0.92, 0.6) if i == player.selected else Color(1, 1, 1, 0.35)
		p.add_theme_stylebox_override("panel", sb)
		if b > 0:
			var tr := TextureRect.new()
			tr.texture = Blocks.icon(world.atlas, b)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.position = Vector2(8, 8)
			tr.size = Vector2(36, 36)
			tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
			p.add_child(tr)
		if count > 1:
			var l := _outlined(14)
			l.text = str(count)
			l.position = Vector2(30, 30)
			p.add_child(l)
		bar.add_child(p)
		slots.append(p)
	bar.size = Vector2(n * 58 - 6, 52)


func notify(text: String) -> void:
	var l := _outlined(16)
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(420, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toasts.add_child(l)
	var tw := create_tween()
	tw.tween_interval(3.0)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func _process(delta: float) -> void:
	size = get_viewport_rect().size
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		var p := player.global_position
		var biome: String = Terrain.BIOME_NAMES[world.terrain.column(floori(p.x), floori(p.z)).y]
		var clock: String = main.time_text() if main else ""
		var b := player.current_block()
		var block_name: String = Blocks.NAMES[b] if b > 0 else "pusto"
		if Settings.show_debug:
			info.text = "%d FPS\n%s\nx %.0f  y %.0f  z %.0f · %s · %s\nblok: %s · mody: %d" % [
				Engine.get_frames_per_second(), world.stats(), p.x, p.y, p.z, biome, clock,
				block_name, Mods.loaded.size()]
		else:
			info.text = "%s · %s" % [biome, clock]
		if Mods.hotbar.container != "":
			_rebuild_bar()  # liczby przedmiotów mogą się zmieniać bez sygnału
	bar.position = Vector2((size.x - bar.size.x * bar.scale.x) / 2.0, size.y - bar.size.y * bar.scale.y - (12.0 if touch_mode else 18.0))
	if help:
		help.size = Vector2(size.x - 40, 24)
		help.position = Vector2(20, 10)
	toasts.size = Vector2(440, 0)
	toasts.position = Vector2((size.x - 440) / 2.0, size.y * 0.22)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var col := Color(1, 1, 1, 0.85)
	draw_rect(Rect2(c + Vector2(-9, -1), Vector2(18, 2)), col)
	draw_rect(Rect2(c + Vector2(-1, -9), Vector2(2, 18)), col)
