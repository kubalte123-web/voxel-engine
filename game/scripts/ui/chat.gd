class_name Chat
extends Control
## Czat: wiadomości graczy i serwera w lewym dolnym rogu (znikają po chwili), T albo Enter otwiera pole
## wpisywania. Tekst zaczynający się od „/” to polecenie (/help). Mody czytają i zmieniają wiadomości hakiem
## "chat.message" i piszą przez engine.chat.send.

const SHOW_TIME := 10.0
const MAX_LINES := 60

var main: Node
var box: VBoxContainer
var scroll: ScrollContainer
var input: LineEdit
var lines: Array = []      # [RichTextLabel, czas pojawienia]
var history: Array[String] = []
var hist_i := 0
var open := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scroll)
	box = VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 1)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	scroll.add_child(box)
	input = LineEdit.new()
	input.placeholder_text = "Wiadomość albo /polecenie (Enter wysyła, Esc zamyka)"
	input.max_length = 256
	input.visible = false
	input.text_submitted.connect(_submit)
	input.gui_input.connect(_keys)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0, 0, 0, 0.6)
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	input.add_theme_stylebox_override("normal", sb)
	input.add_theme_stylebox_override("focus", sb)
	add_child(input)
	_layout()
	get_viewport().size_changed.connect(_layout)


func _layout() -> void:
	var vs := get_viewport_rect().size
	var w := minf(560.0, vs.x - 24.0)
	input.position = Vector2(12, vs.y - 190)
	input.size = Vector2(w, 34)
	scroll.position = Vector2(12, vs.y - 190 - 236)
	scroll.size = Vector2(w, 230)


## Nowa linijka czatu. color: kolor tekstu (nazwa gracza jest pogrubiona, gdy podana).
func add_line(text: String, color := Color(1, 1, 1), who := "") -> void:
	var l := RichTextLabel.new()
	l.bbcode_enabled = true
	l.fit_content = true
	l.scroll_active = false
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("normal_font_size", 15)
	l.add_theme_font_size_override("bold_font_size", 15)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 4)
	var body := "[color=#%s]%s[/color]" % [color.to_html(false), text.replace("[", "[lb]")]
	l.text = ("[b]<%s>[/b] " % who.replace("[", "[lb]") if who != "" else "") + body
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.32)
	bg.content_margin_left = 6
	bg.content_margin_right = 6
	l.add_theme_stylebox_override("normal", bg)
	box.add_child(l)
	lines.append([l, Time.get_ticks_msec() / 1000.0])
	while lines.size() > MAX_LINES:
		(lines.pop_front()[0] as Node).queue_free()
	_scroll_down.call_deferred()


func _scroll_down() -> void:
	scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	for e in lines:
		var l: Control = e[0]
		var age: float = now - float(e[1])
		l.modulate.a = 1.0 if open else clampf((SHOW_TIME - age) / 1.5, 0.0, 1.0)


func open_input(prefix := "") -> void:
	if open:
		return
	open = true
	input.visible = true
	input.text = prefix
	input.caret_column = prefix.length()
	input.grab_focus.call_deferred()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.mouse_filter = Control.MOUSE_FILTER_PASS
	main.player.ui_blocked = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_input() -> void:
	if not open:
		return
	open = false
	input.visible = false
	input.release_focus()
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main.player.ui_blocked = not main.windows.is_empty() or main.console != null
	if main.windows.is_empty() and main.console == null and not main.touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _submit(text: String) -> void:
	var t := text.strip_edges()
	close_input()
	if t == "":
		return
	history.append(t)
	hist_i = history.size()
	main.send_chat(t)


func _keys(e: InputEvent) -> void:
	if not (e is InputEventKey and e.pressed):
		return
	if e.keycode == KEY_ESCAPE:
		accept_event()
		close_input()
	elif e.keycode == KEY_UP and not history.is_empty():
		hist_i = maxi(0, hist_i - 1)
		input.text = history[hist_i]
		input.caret_column = input.text.length()
		accept_event()
	elif e.keycode == KEY_DOWN and not history.is_empty():
		hist_i = mini(history.size(), hist_i + 1)
		input.text = history[hist_i] if hist_i < history.size() else ""
		input.caret_column = input.text.length()
		accept_event()


## Wynik polecenia albo wiadomość z serwera tylko dla tego gracza.
func print_line(text: String, color := "#e8eef8") -> void:
	for ln in text.split("\n"):
		add_line(ln, Color.from_string(color, Color(0.9, 0.93, 0.97)))


## Tekst wszystkich linijek (testy).
func text_lines() -> Array:
	var out := []
	for e in lines:
		out.append((e[0] as RichTextLabel).get_parsed_text())
	return out
