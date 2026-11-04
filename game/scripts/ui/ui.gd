class_name UI
## Wspólny wygląd interfejsu i pomocnicze funkcje do budowania ekranów w kodzie.

const BG := Color(0.09, 0.12, 0.16, 0.94)
const PANEL_EDGE := Color(1, 1, 1, 0.08)
const TEXT := Color(0.93, 0.95, 0.96)
const MUTED := Color(0.66, 0.72, 0.76)
const ACCENT := Color(0.38, 0.64, 0.31)
const ACCENT_HOVER := Color(0.45, 0.73, 0.37)
const BUTTON := Color(0.19, 0.24, 0.30)
const BUTTON_HOVER := Color(0.25, 0.31, 0.38)
const DANGER := Color(0.72, 0.26, 0.22)
const LOCK := Color(0.95, 0.75, 0.30)


static func _box(c: Color, radius: int = 8, border: Color = Color(0, 0, 0, 0), pad: int = 12) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = c
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	if border.a > 0.0:
		s.set_border_width_all(1)
		s.border_color = border
	return s


static func make_theme() -> Theme:
	var t := Theme.new()
	t.default_font_size = 18
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("panel", "PanelContainer", _box(BG, 12, PANEL_EDGE, 24))
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var c := BUTTON
		if state == "hover":
			c = BUTTON_HOVER
		elif state == "pressed":
			c = ACCENT
		elif state == "disabled":
			c = Color(0.15, 0.18, 0.22)
		var sb := _box(c, 8, Color(0, 0, 0, 0), 10)
		if state == "focus":
			sb.bg_color = Color(0, 0, 0, 0)
			sb.set_border_width_all(2)
			sb.border_color = ACCENT_HOVER
		t.set_stylebox(state, "Button", sb)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.55, 0.6))
	t.set_font_size("font_size", "Button", 20)
	t.set_stylebox("normal", "LineEdit", _box(Color(0.06, 0.08, 0.11), 6, PANEL_EDGE, 10))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.06, 0.08, 0.11), 6, ACCENT, 10))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(0.5, 0.55, 0.6))
	t.set_color("font_color", "CheckBox", TEXT)
	t.set_color("font_hover_color", "CheckBox", Color(1, 1, 1))
	t.set_stylebox("slider", "HSlider", _box(Color(0.06, 0.08, 0.11), 4, Color(0, 0, 0, 0), 3))
	t.set_stylebox("grabber_area", "HSlider", _box(ACCENT, 4, Color(0, 0, 0, 0), 3))
	t.set_stylebox("grabber_area_highlight", "HSlider", _box(ACCENT_HOVER, 4, Color(0, 0, 0, 0), 3))
	for state in ["normal", "hover", "pressed", "disabled", "focus", "hover_pressed"]:
		var e := StyleBoxEmpty.new()
		e.set_content_margin_all(6)
		t.set_stylebox(state, "CheckBox", e)
	return t


static func button(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 52)
	b.pressed.connect(cb)
	if primary:
		b.add_theme_stylebox_override("normal", _box(ACCENT, 8, Color(0, 0, 0, 0), 10))
		b.add_theme_stylebox_override("hover", _box(ACCENT_HOVER, 8, Color(0, 0, 0, 0), 10))
	return b


static func danger(b: Button) -> Button:
	b.add_theme_stylebox_override("normal", _box(DANGER.darkened(0.25), 8, Color(0, 0, 0, 0), 10))
	b.add_theme_stylebox_override("hover", _box(DANGER, 8, Color(0, 0, 0, 0), 10))
	return b


static func label(text: String, size: int = 18, color: Color = TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


static func wrap(text: String, size: int = 16, color: Color = MUTED) -> Label:
	var l := label(text, size, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(200, 0)
	return l


## Wiersz z suwakiem: etykieta, suwak i wartość obok.
static func slider_row(text: String, lo: float, hi: float, step: float, value: float,
		fmt: Callable, on_change: Callable, locked: bool = false) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := label(text, 17)
	l.custom_minimum_size = Vector2(220, 0)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.custom_minimum_size = Vector2(160, 32)
	s.editable = not locked
	row.add_child(s)
	var v := label(fmt.call(value), 17, MUTED)
	v.custom_minimum_size = Vector2(90, 0)
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(v)
	s.value_changed.connect(func(x: float) -> void:
		v.text = fmt.call(x)
		on_change.call(x))
	return row


static func check_row(text: String, value: bool, on_change: Callable, locked: bool = false) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = value
	c.disabled = locked
	c.add_theme_font_size_override("font_size", 17)
	c.toggled.connect(on_change)
	return c


static func clear(node: Node) -> void:
	for ch in node.get_children():
		node.remove_child(ch)
		ch.queue_free()


static func narrow(viewport_size: Vector2) -> bool:
	return viewport_size.x < 900.0
