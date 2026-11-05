class_name PauseMenu
extends Control
## Menu pauzy w grze: powrót, opcje, zapis i wyjście do menu.

signal resume
signal save_and_exit

var content: VBoxContainer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vs := get_viewport_rect().size
	var w := minf(vs.x - 32.0, 520.0)
	scroll.custom_minimum_size = Vector2(w - 48.0, minf(vs.y - 80.0, 260.0))
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", 14)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)
	show_main()


func show_main() -> void:
	var scroll: ScrollContainer = content.get_parent()
	scroll.custom_minimum_size.y = minf(get_viewport_rect().size.y - 80.0, 260.0)
	UI.clear(content)
	content.add_child(UI.label("Pauza", 30))
	content.add_child(UI.button("Wróć do gry", func(): resume.emit(), true))
	content.add_child(UI.button("Opcje", show_options))
	content.add_child(UI.button("Konsola modera (F2)", func():
		var m: Node = get_tree().current_scene
		if m and m.has_method("open_console"):
			m.open_console()))
	content.add_child(UI.button("Zapisz i wyjdź do menu", func(): save_and_exit.emit()))


func show_options() -> void:
	var scroll: ScrollContainer = content.get_parent()
	scroll.custom_minimum_size.y = minf(get_viewport_rect().size.y - 80.0, 520.0)
	UI.clear(content)
	var o := OptionsPanel.new()
	o.on_back = show_main
	content.add_child(o)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume.emit()
