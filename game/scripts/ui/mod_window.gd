class_name ModWindow
extends Control
## Okno opisane przez mod danymi (engine.ui.window). Rodzaje sekcji:
##   {type = "character", lines = {...}}       podgląd postaci i tekst obok
##   {type = "slots", container = "id", columns = 9, title = "..."}  siatka miejsc na przedmioty
##   {type = "text", text = "..."}
##   {type = "button", id = "...", text = "...", on_press = function(fields)}
##   {type = "input", id = "login", label = "Login", secret = true, text = ""}  pole tekstowe
##   {type = "progress", value = 0.5, label = "..."}  pasek postępu
## Przenoszenie przedmiotów: kliknięcie bierze cały stos, prawy przycisk połowę lub jedną sztukę.
## Logika kliknięć działa na serwerze (Mods.window_click), więc tak samo w grze wieloosobowej.

signal closed(id: String)

var spec: Dictionary
var inputs := {}           # id pola -> LineEdit
var held_icon: Control
var slot_views := []       # [kontener, indeks, Button]
var content: VBoxContainer
var _refresh := 0.0


func _ready() -> void:
	theme = UI.make_theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	size = get_viewport_rect().size
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.35)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	center.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var vs := get_viewport_rect().size
	scroll.custom_minimum_size = Vector2(minf(vs.x - 40.0, 720.0), minf(vs.y - 60.0, 600.0))
	panel.add_child(scroll)
	content = VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	held_icon = TextureRect.new()
	held_icon.size = Vector2(40, 40)
	held_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	held_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	held_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	held_icon.visible = false
	add_child(held_icon)
	build(spec)


func build(new_spec: Dictionary) -> void:
	spec = new_spec
	var keep := {}
	for k in inputs:
		if is_instance_valid(inputs[k]):
			keep[k] = inputs[k].text
	UI.clear(content)
	slot_views.clear()
	inputs.clear()
	var head := HBoxContainer.new()
	var title := UI.label(str(spec.get("title", "")), 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	if bool(spec.get("closable", true)):
		head.add_child(UI.button("Zamknij", close))
	content.add_child(head)
	var narrow := UI.narrow(get_viewport_rect().size)
	for s in spec.get("sections", []):
		if not s is Dictionary:
			continue
		match str(s.get("type", "")):
			"character":
				content.add_child(_character(s, narrow))
			"slots":
				content.add_child(_slots(s, narrow))
			"text":
				content.add_child(UI.wrap(str(s.get("text", "")), 17, UI.TEXT))
			"button":
				var action := str(s.get("action", ""))
				content.add_child(UI.button(str(s.get("text", "")), func(): _press(action)))
			"input":
				if s.has("label"):
					content.add_child(UI.label(str(s.label), 16, UI.MUTED))
				var le := LineEdit.new()
				le.custom_minimum_size = Vector2(0, 46)
				le.secret = bool(s.get("secret", false))
				le.placeholder_text = str(s.get("placeholder", ""))
				var fid := str(s.get("id", "pole"))
				le.text = str(keep.get(fid, s.get("text", "")))
				content.add_child(le)
				inputs[fid] = le
			"progress":
				if s.has("label"):
					content.add_child(UI.label(str(s.label), 16, UI.MUTED))
				var pb := ProgressBar.new()
				pb.custom_minimum_size = Vector2(0, 22)
				pb.max_value = 1.0
				pb.value = float(s.get("value", 0.0))
				pb.show_percentage = false
				content.add_child(pb)
	info_label = UI.wrap("", 15, UI.MUTED)
	info_label.visible = false
	content.add_child(info_label)
	_update_slots()


func _character(s: Dictionary, narrow: bool) -> Control:
	var row: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var svc := SubViewportContainer.new()
	svc.custom_minimum_size = Vector2(200, 240)
	svc.stretch = true
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.transparent_bg = true
	vp.size = Vector2i(200, 240)
	svc.add_child(vp)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.05, 2.7)
	cam.fov = 40
	vp.add_child(cam)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, 25, 0)
	vp.add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.65, 0.7)
	env.environment.background_mode = Environment.BG_CLEAR_COLOR
	vp.add_child(env)
	var model := CharacterModel.new()
	model.rotation.y = PI
	model.name = "Preview"
	vp.add_child(model)
	row.add_child(svc)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	for line in s.get("lines", []):
		col.add_child(UI.label(str(line), 17))
	row.add_child(col)
	return row


func _slots(s: Dictionary, narrow: bool) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	if s.has("title"):
		box.add_child(UI.label(str(s.title), 18, UI.MUTED))
	var cid := str(s.get("container", ""))
	var grid := GridContainer.new()
	var n: int = Mods.container_slots(cid).size()
	var cols := clampi(int(s.get("columns", 9)), 1, 12)
	var cell := 52.0
	var avail := minf(get_viewport_rect().size.x - 100.0, 670.0)
	if cols * (cell + 6) > avail:
		cell = maxf(36.0, avail / cols - 6)
	grid.columns = cols
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 6)
	for i in n:
		var b := Button.new()
		b.custom_minimum_size = Vector2(cell, cell)
		b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		b.expand_icon = true
		b.add_theme_font_size_override("font_size", 13)
		b.add_theme_constant_override("icon_max_width", int(cell) - 16)
		var idx := i
		b.gui_input.connect(func(e: InputEvent) -> void:
			if not e is InputEventMouseButton:
				return
			# dotyk (zdarzenie emulowane z ekranu): krótkie dotknięcie = lewy przycisk,
			# przytrzymanie = prawy (połowa stosu / odłożenie jednej sztuki)
			if e.device == InputEvent.DEVICE_ID_EMULATION:
				if e.pressed:
					b.set_meta("down", Time.get_ticks_msec())
				elif b.has_meta("down"):
					var held: int = Time.get_ticks_msec() - int(b.get_meta("down"))
					b.remove_meta("down")
					_click(cid, idx, held >= LONG_PRESS_MS)
			elif e.pressed:
				_click(cid, idx, e.button_index == MOUSE_BUTTON_RIGHT))
		grid.add_child(b)
		slot_views.append([cid, i, b])
	box.add_child(grid)
	return box


const LONG_PRESS_MS := 400


func _fields() -> Dictionary:
	var f := {}
	for k in inputs:
		f[k] = inputs[k].text
	return f


func _press(action: String) -> void:
	if Net.is_client():
		Net.c_button.rpc_id(1, action, _fields())
	else:
		Mods.window_action(action, _fields())


## Pasek u dołu okna z opisem ostatnio klikniętego przedmiotu (na telefonie nie ma dymków po najechaniu).
var info_label: Label


func _show_info(cid: String, i: int) -> void:
	var sl := Mods.slot(cid, i)
	if sl.is_empty() or info_label == null:
		return
	info_label.text = Mods.registry.tooltip(sl).replace("\n", " · ")
	info_label.visible = true


func _click(cid: String, i: int, right: bool) -> void:
	_show_info(cid, i)
	if Net.is_client():
		Net.c_click.rpc_id(1, cid, i, right)
	else:
		Mods.window_click(Mods.local_peer, cid, i, right)
	_update_slots()


func _update_slots() -> void:
	for v in slot_views:
		var sl := Mods.slot(v[0], v[1])
		var b: Button = v[2]
		if sl.is_empty():
			b.icon = null
			b.text = ""
		else:
			b.icon = Mods.registry.icon(str(sl.item))
			b.text = str(sl.count) if int(sl.count) > 1 else ""
			b.tooltip_text = Mods.registry.tooltip(sl)
	var held: Dictionary = Mods.local_held
	held_icon.visible = not held.is_empty()
	if not held.is_empty():
		held_icon.texture = Mods.registry.icon(str(held.item))


func _process(delta: float) -> void:
	size = get_viewport_rect().size
	if held_icon.visible:
		held_icon.position = get_local_mouse_position() + Vector2(8, 8)
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.2
		_update_slots()
	var prev := find_child("Preview", true, false)
	if prev:
		prev.rotation.y += delta * 0.6
		prev.animate(delta, 0.0, true, 0.0)


func close() -> void:
	var id := str(spec.get("id", ""))
	if Net.is_client():
		Net.c_closed.rpc_id(1, id)
		Mods.open_windows.erase(id)
	else:
		Mods.window_closed(Mods.local_peer, id)
	closed.emit(id)
	queue_free()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and bool(spec.get("closable", true)):
		get_viewport().set_input_as_handled()
		close()
