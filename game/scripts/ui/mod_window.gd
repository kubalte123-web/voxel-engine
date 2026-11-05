class_name ModWindow
extends Control
## Okno opisane przez mod danymi (engine.ui.window). Rodzaje sekcji:
##   {type = "character", lines = {...}}       podgląd postaci i tekst obok
##   {type = "slots", container = "id", columns = 9, title = "..."}  siatka miejsc na przedmioty
##   {type = "text", text = "..."}
##   {type = "button", id = "...", text = "...", on_press = function(fields)}
##   {type = "input", id = "login", label = "Login", secret = true, text = ""}  pole tekstowe
##   {type = "progress", value = 0.5, label = "..."}  pasek postępu
##   {type = "image", image = "textures/x.png" | {pattern...}, item = "klucz", size = {w, h}, caption = "..."}
##   {type = "row", sections = {...}}            sekcje obok siebie (na wąskim ekranie jedna pod drugą)
##   {type = "column", sections = {...}}         sekcje jedna pod drugą (np. kolumna w wierszu)
##   {type = "tabs", id = "...", tabs = {{title = "...", sections = {...}}, ...}, selected = 1}
##   {type = "list", id = "...", items = {{text, item, color}}, selected = n, height = 160}
##   {type = "slider", id = "...", label, min, max, step, value}
##   {type = "toggle", id = "...", text, value}
##   {type = "dropdown", id = "...", label, options = {...}, selected = n}
##   {type = "item_button", item = "klucz", count, text, on_press}
##   {type = "separator"} i {type = "space", size = 12}
## Wartości pól (input, slider, toggle, list, dropdown, tabs) trafiają do on_press(fields) i on_change(fields);
## listy, zakładki i lista rozwijana liczą od 1, jak w Lua.
## Przenoszenie przedmiotów: kliknięcie bierze cały stos, prawy przycisk połowę lub jedną sztukę.
## Logika kliknięć działa na serwerze (Mods.window_click), więc tak samo w grze wieloosobowej.

signal closed(id: String)

var spec: Dictionary
var inputs := {}           # id pola -> LineEdit
var values := {}           # id pola -> wartość (suwak, przełącznik, lista, zakładki)
var _kept := {}
var _building := false
var _tab_init: Array = []   # [TabContainer, indeks] – ustawiane po wejściu do drzewa
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
	_kept = values.duplicate()
	values.clear()
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
	_building = true
	_sections(spec.get("sections", []), content, narrow, keep)
	_end_build.call_deferred()
	info_label = UI.wrap("", 15, UI.MUTED)
	info_label.visible = false
	content.add_child(info_label)
	_update_slots()


func _end_build() -> void:
	for t in _tab_init:
		if is_instance_valid(t[0]):
			(t[0] as TabContainer).current_tab = int(t[1])
	_tab_init.clear()
	_building = false


func _sections(list: Variant, parent: Container, narrow: bool, keep: Dictionary) -> void:
	for s in Registry.arr(list):
		if s is Dictionary:
			var c := _section(s, narrow, keep)
			if c:
				parent.add_child(c)


func _labeled(s: Dictionary, c: Control) -> Control:
	if not s.has("label"):
		return c
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.add_child(UI.label(str(s.label), 16, UI.MUTED))
	box.add_child(c)
	return box


func _section(s: Dictionary, narrow: bool, keep: Dictionary) -> Control:
	var fid := str(s.get("id", ""))
	var action := str(s.get("action", ""))
	match str(s.get("type", "")):
		"character":
			return _character(s, narrow)
		"slots":
			return _slots(s, narrow)
		"text":
			var l := UI.wrap(str(s.get("text", "")), int(s.get("size", 17)), Color.from_string(str(s.get("color", "")), UI.TEXT))
			match str(s.get("align", "")):
				"center": l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				"right": l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			return l
		"button":
			var b := UI.button(str(s.get("text", "")), func(): _press(action), bool(s.get("primary", false)))
			b.disabled = bool(s.get("disabled", false))
			return b
		"item_button":
			var item := str(s.get("item", ""))
			var label := str(s.get("text", Mods.registry.item_name(item) if Mods.registry and item != "" else ""))
			if int(s.get("count", 0)) > 1:
				label = "%s ×%d" % [label, int(s.count)]
			var b := UI.button(label, func(): _press(action), bool(s.get("primary", false)))
			if item != "" and Mods.registry:
				b.icon = Mods.registry.icon(item)
				b.expand_icon = false
				b.add_theme_constant_override("icon_max_width", 32)
				b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.disabled = bool(s.get("disabled", false))
			b.tooltip_text = str(s.get("tooltip", ""))
			return b
		"input":
			var le := LineEdit.new()
			le.custom_minimum_size = Vector2(0, 46)
			le.secret = bool(s.get("secret", false))
			le.placeholder_text = str(s.get("placeholder", ""))
			var iid := fid if fid != "" else "pole"
			le.text = str(keep.get(iid, s.get("text", "")))
			inputs[iid] = le
			return _labeled(s, le)
		"progress":
			var pb := ProgressBar.new()
			pb.custom_minimum_size = Vector2(0, 22)
			pb.max_value = 1.0
			pb.value = float(s.get("value", 0.0))
			pb.show_percentage = false
			return _labeled(s, pb)
		"image":
			var tr := TextureRect.new()
			tr.texture = _image(s)
			tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if bool(s.get("pixel", true)) else CanvasItem.TEXTURE_FILTER_LINEAR
			tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var sz := Registry.arr(s.get("size"))
			tr.custom_minimum_size = Vector2(float(sz[0]) if sz.size() > 0 else 64.0, float(sz[1]) if sz.size() > 1 else (float(sz[0]) if sz.size() > 0 else 64.0))
			if not s.has("caption"):
				return tr
			var box := VBoxContainer.new()
			box.add_child(tr)
			var cap := UI.label(str(s.caption), 14, UI.MUTED)
			cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(cap)
			return box
		"column":
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", int(s.get("gap", 8)))
			_sections(s.get("sections"), col, narrow, keep)
			return col
		"row", "columns":
			var row: BoxContainer = VBoxContainer.new() if narrow and bool(s.get("wrap", true)) else HBoxContainer.new()
			row.add_theme_constant_override("separation", int(s.get("gap", 12)))
			for sub in Registry.arr(s.get("sections")):
				if sub is Dictionary:
					var c := _section(sub, narrow, keep)
					if c:
						c.size_flags_horizontal = Control.SIZE_EXPAND_FILL if bool(sub.get("expand", true)) else Control.SIZE_FILL
						row.add_child(c)
			return row
		"tabs":
			var tabs := TabContainer.new()
			var pages := Registry.arr(s.get("tabs"))
			for t in pages:
				if not t is Dictionary:
					continue
				var page := VBoxContainer.new()
				page.name = str(t.get("title", "?"))
				page.add_theme_constant_override("separation", 10)
				_sections(t.get("sections"), page, narrow, keep)
				tabs.add_child(page)
			var sel := int(s.get("selected", _kept.get(fid, 1))) - 1
			sel = clampi(sel, 0, maxi(0, tabs.get_tab_count() - 1))
			_tab_init.append([tabs, sel])
			values[fid] = sel + 1
			tabs.tab_changed.connect(func(i: int):
				if _building:
					return
				values[fid] = i + 1
				if action != "":
					_press(action))
			return tabs
		"list":
			var il := ItemList.new()
			il.custom_minimum_size = Vector2(0, float(s.get("height", 160)))
			il.add_theme_font_size_override("font_size", 16)
			il.fixed_icon_size = Vector2i(28, 28)
			for it in Registry.arr(s.get("items")):
				var d: Dictionary = it if it is Dictionary else {"text": str(it)}
				var icon: Texture2D = Mods.registry.icon(str(d.item)) if d.has("item") and Mods.registry else null
				var idx := il.add_item(str(d.get("text", Mods.registry.item_name(str(d.get("item", ""))) if Mods.registry else "")), icon)
				if d.has("color"):
					il.set_item_custom_fg_color(idx, Color.from_string(str(d.color), Color.WHITE))
				if bool(d.get("disabled", false)):
					il.set_item_disabled(idx, true)
			var sel := int(s.get("selected", _kept.get(fid, 0)))
			if sel >= 1 and sel <= il.item_count:
				il.select(sel - 1)
			values[fid] = sel
			il.item_selected.connect(func(i: int):
				values[fid] = i + 1
				if action != "":
					_press(action))
			return _labeled(s, il)
		"slider":
			var row := HBoxContainer.new()
			var sl := HSlider.new()
			sl.min_value = float(s.get("min", 0.0))
			sl.max_value = float(s.get("max", 1.0))
			sl.step = float(s.get("step", 0.01))
			sl.value = float(s.get("value", _kept.get(fid, sl.min_value)))
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sl.custom_minimum_size = Vector2(160, 32)
			var vl := UI.label("", 16)
			vl.custom_minimum_size = Vector2(56, 0)
			var fmt := func(v: float) -> String: return str(int(v)) if sl.step >= 1.0 else "%.2f" % v
			vl.text = fmt.call(sl.value)
			values[fid] = sl.value
			sl.value_changed.connect(func(v: float):
				values[fid] = v
				vl.text = fmt.call(v))
			if action != "":
				sl.drag_ended.connect(func(_c: bool): _press(action))
			row.add_child(sl)
			row.add_child(vl)
			return _labeled(s, row)
		"toggle":
			var cb := CheckButton.new()
			cb.text = str(s.get("text", ""))
			cb.button_pressed = bool(s.get("value", _kept.get(fid, false)))
			cb.add_theme_font_size_override("font_size", 17)
			values[fid] = cb.button_pressed
			cb.toggled.connect(func(on: bool):
				values[fid] = on
				if action != "":
					_press(action))
			return cb
		"dropdown":
			var ob := OptionButton.new()
			ob.custom_minimum_size = Vector2(0, 44)
			for o in Registry.arr(s.get("options")):
				ob.add_item(str(o))
			var sel := int(s.get("selected", _kept.get(fid, 1)))
			if ob.item_count > 0:
				ob.select(clampi(sel - 1, 0, ob.item_count - 1))
			values[fid] = ob.selected + 1
			ob.item_selected.connect(func(i: int):
				values[fid] = i + 1
				if action != "":
					_press(action))
			return _labeled(s, ob)
		"separator":
			return HSeparator.new()
		"space":
			var sp := Control.new()
			sp.custom_minimum_size = Vector2(0, float(s.get("size", 12)))
			return sp
	return null


## Obrazek sekcji: ikona przedmiotu, plik moda (pełna rozdzielczość) albo wzór.
func _image(s: Dictionary) -> Texture2D:
	return load_image(s, str(spec.get("mod", "")))


static func load_image(s: Dictionary, mod: String) -> Texture2D:
	if s.has("item") and Mods.registry:
		return Mods.registry.icon(str(s.item))
	var im: Variant = s.get("image")
	if im is Dictionary:
		return ImageTexture.create_from_image(TexGen.pattern(im))
	if im is String and Mods.registry:
		var rel: String = im
		if rel.find(":") > 0 and not rel.begins_with("res:") and not rel.begins_with("user:"):
			mod = rel.substr(0, rel.find(":"))
			rel = rel.substr(rel.find(":") + 1)
		var path: String = rel if rel.begins_with("user://") or rel.begins_with("res://") else Mods.registry._mod_path(mod).path_join(rel)
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) == OK or img.load_jpg_from_buffer(FileAccess.get_file_as_bytes(path)) == OK:
				return ImageTexture.create_from_image(img)
		elif ResourceLoader.exists(path):
			return load(path) as Texture2D
	return null


## Wszystkie sekcje okna (także w wierszach i zakładkach) – fn(sekcja).
static func each_section(list: Variant, fn: Callable) -> void:
	for s in Registry.arr(list):
		if not s is Dictionary:
			continue
		fn.call(s)
		each_section(s.get("sections"), fn)
		for t in Registry.arr(s.get("tabs")):
			if t is Dictionary:
				each_section(t.get("sections"), fn)


## Kontenery przedmiotów pokazane w oknie.
static func slot_containers(spec: Dictionary) -> Array:
	var out := []
	each_section(spec.get("sections"), func(s: Dictionary):
		if s.get("type") == "slots":
			out.append(str(s.get("container", ""))))
	return out


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
	for k in values:
		if str(k) != "":
			f[k] = values[k]
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
