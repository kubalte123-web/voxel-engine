class_name ModWindow
extends Control
## Okno opisane przez mod danymi (engine.ui.window). Rodzaje sekcji:
##   {type = "character", lines = {...}}       podgląd postaci i tekst obok
##   {type = "slots", container = "id", columns = 9, title = "..."}  siatka miejsc na przedmioty
##   {type = "text", text = "..."}
##   {type = "button", id = "...", text = "...", on_press = function}
## Przenoszenie przedmiotów: kliknięcie bierze cały stos, prawy przycisk połowę lub jedną sztukę.

signal closed(id: String)

var spec: Dictionary
var atlas: Texture2D
var held := {}             # przedmiot trzymany pod kursorem
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
	UI.clear(content)
	slot_views.clear()
	var head := HBoxContainer.new()
	var title := UI.label(str(spec.get("title", "")), 26)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
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
				content.add_child(UI.button(str(s.get("text", "")), func(): Mods.window_action(action)))
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
			if e is InputEventMouseButton and e.pressed:
				_click(cid, idx, e.button_index == MOUSE_BUTTON_RIGHT))
		grid.add_child(b)
		slot_views.append([cid, i, b])
	box.add_child(grid)
	return box


func _click(cid: String, i: int, right: bool) -> void:
	var cur := Mods.slot(cid, i)
	var max_stack := Mods.MAX_STACK
	if held.is_empty():
		if cur.is_empty():
			return
		if right and int(cur.count) > 1:
			var half := int(cur.count) / 2
			held = {"block": cur.block, "count": half}
			Mods.set_slot(cid, i, {"block": cur.block, "count": int(cur.count) - half})
		else:
			held = cur.duplicate()
			Mods.set_slot(cid, i, {})
	else:
		if cur.is_empty():
			var n := 1 if right else int(held.count)
			Mods.set_slot(cid, i, {"block": held.block, "count": n})
			held.count = int(held.count) - n
		elif int(cur.block) == int(held.block):
			var room := max_stack - int(cur.count)
			var n := mini(room, 1 if right else int(held.count))
			Mods.set_slot(cid, i, {"block": cur.block, "count": int(cur.count) + n})
			held.count = int(held.count) - n
		elif not right:
			Mods.set_slot(cid, i, held.duplicate())
			held = cur.duplicate()
		if int(held.get("count", 0)) <= 0:
			held = {}
	_update_slots()


func _update_slots() -> void:
	for v in slot_views:
		var sl := Mods.slot(v[0], v[1])
		var b: Button = v[2]
		if sl.is_empty():
			b.icon = null
			b.text = ""
		else:
			b.icon = Blocks.icon(atlas, int(sl.block))
			b.text = str(sl.count) if int(sl.count) > 1 else ""
			b.tooltip_text = Blocks.NAMES[int(sl.block)]
	held_icon.visible = not held.is_empty()
	if not held.is_empty():
		held_icon.texture = Blocks.icon(atlas, int(held.block))


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
	_return_held()
	closed.emit(str(spec.get("id", "")))
	queue_free()


## Przedmiot trzymany pod kursorem wraca do pierwszego wolnego miejsca w otwartych kontenerach.
func _return_held() -> void:
	if held.is_empty():
		return
	for v in slot_views:
		var sl := Mods.slot(v[0], v[1])
		if sl.is_empty():
			Mods.set_slot(v[0], v[1], held)
			held = {}
			return
		if int(sl.block) == int(held.block) and int(sl.count) + int(held.count) <= Mods.MAX_STACK:
			Mods.set_slot(v[0], v[1], {"block": sl.block, "count": int(sl.count) + int(held.count)})
			held = {}
			return


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()
