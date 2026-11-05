class_name ModConsole
extends Control
## Konsola modera (F2 albo `): dziennik modów z błędami i linia poleceń.
## - kod Lua, np. `engine.player.position()` albo `engine.effects.add("alchemy.speed", 30)` – wykonany na serwerze
##   w imieniu tego gracza (w grze sieciowej tylko administrator),
## - polecenia zaczynające się od `/`, np. `/reload` (przeładowanie modów), `/help`.

signal closed

var log_view: RichTextLabel
var input: LineEdit
var history: Array[String] = []
var hist_i := 0
var main: Node


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size = Vector2(0, get_viewport_rect().size.y * 0.55)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.07, 0.92)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var box := VBoxContainer.new()
	panel.add_child(box)
	var head := HBoxContainer.new()
	var title := Label.new()
	title.text = "Konsola modera – kod Lua albo /polecenie (/help). Esc zamyka."
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(UI.button("Zamknij", func(): close()))
	box.add_child(head)
	log_view = RichTextLabel.new()
	log_view.bbcode_enabled = true
	log_view.scroll_following = true
	log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_view.selection_enabled = true
	log_view.add_theme_font_size_override("normal_font_size", 14)
	box.add_child(log_view)
	input = LineEdit.new()
	input.placeholder_text = "np. engine.player.position()  ·  /reload  ·  /help"
	input.custom_minimum_size = Vector2(0, 42)
	input.text_submitted.connect(_submit)
	input.gui_input.connect(_history_keys)
	box.add_child(input)
	for l in Mods.logs.slice(maxi(0, Mods.logs.size() - 200)):
		_add_log(str(l))
	Mods.log_added.connect(_add_log)
	input.grab_focus.call_deferred()


func _add_log(line: String) -> void:
	var t := line.replace("[", "[lb]")
	if "BŁĄD" in line:
		log_view.append_text("[color=#ff8a7a]" + t + "[/color]\n")
	else:
		log_view.append_text("[color=#9aa4b4]" + t + "[/color]\n")


func print_line(text: String, color := "#e8eef8") -> void:
	log_view.append_text("[color=%s]%s[/color]\n" % [color, text.replace("[", "[lb]")])


func _submit(text: String) -> void:
	var t := text.strip_edges()
	input.clear()
	if t == "":
		return
	history.append(t)
	hist_i = history.size()
	print_line("> " + t, "#ffd36a")
	if t.begins_with("/"):
		main.run_command_local(t, self)
	elif Net.is_client():
		Net.c_console.rpc_id(1, t)
	else:
		print_line(Mods.console_exec(Mods.local_peer, t))


func _history_keys(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not history.is_empty():
		if e.keycode == KEY_UP:
			hist_i = maxi(0, hist_i - 1)
			input.text = history[hist_i]
			input.caret_column = input.text.length()
			accept_event()
		elif e.keycode == KEY_DOWN:
			hist_i = mini(history.size(), hist_i + 1)
			input.text = history[hist_i] if hist_i < history.size() else ""
			input.caret_column = input.text.length()
			accept_event()


func _unhandled_input(e: InputEvent) -> void:
	if e.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func close() -> void:
	closed.emit()
	queue_free()
