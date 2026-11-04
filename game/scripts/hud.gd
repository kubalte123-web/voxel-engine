class_name Hud
extends Control
## Celownik, pasek bloków, informacje o wydajności i podpowiedzi sterowania.

var player: Player
var world: World
var info: Label
var slots: Array[Panel] = []
var touch_mode := false
var _timer := 0.0
var help: Label
var bar: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	info = Label.new()
	info.position = Vector2(14, 10)
	info.add_theme_font_size_override("font_size", 15)
	info.add_theme_color_override("font_color", Color(1, 1, 1))
	info.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	info.add_theme_constant_override("outline_size", 4)
	add_child(info)

	if not touch_mode:
		help = Label.new()
		help.text = "WASD ruch · Spacja skok · LPM kop · PPM postaw · 1-5 / kółko blok · V widok · Esc kursor"
		help.add_theme_font_size_override("font_size", 14)
		help.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
		help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		help.add_theme_constant_override("outline_size", 4)
		help.size = Vector2(660, 24)
		help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_child(help)

	bar = HBoxContainer.new()
	bar.add_theme_constant_override("separation", 6)
	var n := Blocks.PLACEABLE.size()
	bar.size = Vector2(n * 58 - 6, 52)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	for i in n:
		var p := Panel.new()
		p.custom_minimum_size = Vector2(52, 52)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var tr := TextureRect.new()
		tr.texture = Blocks.icon(world.atlas, Blocks.PLACEABLE[i])
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.position = Vector2(8, 8)
		tr.size = Vector2(36, 36)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(tr)
		bar.add_child(p)
		slots.append(p)
	player.selection_changed.connect(_on_select)
	_on_select(player.selected)


func _on_select(index: int) -> void:
	for i in slots.size():
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(3 if i == index else 1)
		sb.border_color = Color(1, 0.92, 0.6) if i == index else Color(1, 1, 1, 0.35)
		slots[i].add_theme_stylebox_override("panel", sb)


func _process(delta: float) -> void:
	size = get_viewport_rect().size
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		var p := player.global_position
		info.text = "%d FPS\n%s\nx %.0f  y %.0f  z %.0f\nblok: %s" % [
			Engine.get_frames_per_second(), world.stats(), p.x, p.y, p.z,
			Blocks.NAMES[Blocks.PLACEABLE[player.selected]]]
	bar.position = Vector2((size.x - bar.size.x) / 2.0, size.y - bar.size.y - (150.0 if touch_mode else 18.0))
	if help:
		help.position = Vector2((size.x - help.size.x) / 2.0, 10)
	queue_redraw()


func _draw() -> void:
	var c := size / 2.0
	var col := Color(1, 1, 1, 0.85)
	draw_rect(Rect2(c + Vector2(-9, -1), Vector2(18, 2)), col)
	draw_rect(Rect2(c + Vector2(-1, -9), Vector2(2, 18)), col)
