class_name ModsScreen
extends VBoxContainer
## Ekran modów: ręczna kolejność ładowania, włączanie i pełne ustawienia każdego moda.
## Ustawienia wymuszone przez serwer są zablokowane i oznaczone.

var on_back: Callable
var selected := ""
var list_box: VBoxContainer
var details: VBoxContainer


func _ready() -> void:
	add_theme_constant_override("separation", 12)
	ModManager.changed.connect(_refresh)
	_build()


func _build() -> void:
	UI.clear(self)
	add_child(UI.label("Mody", 30))
	add_child(UI.wrap("Mody niżej na liście ładują się później i mogą nadpisywać wcześniejsze. Ustawienia generowania terenu zapisują się w świecie przy jego tworzeniu."))
	if not ModManager.server_profile.is_empty():
		add_child(UI.wrap("Połączono z serwerem: elementy oznaczone [serwer] są ustawione przez serwer i nie można ich zmienić.", 16, UI.LOCK))
	var narrow := UI.narrow(get_viewport_rect().size)
	var split: BoxContainer = VBoxContainer.new() if narrow else HBoxContainer.new()
	split.add_theme_constant_override("separation", 18)
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(split)

	var left := ScrollContainer.new()
	left.custom_minimum_size = Vector2(0 if narrow else 380, 180 if narrow else 360)
	left.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(left)
	list_box = VBoxContainer.new()
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_box.add_theme_constant_override("separation", 8)
	left.add_child(list_box)

	var right := ScrollContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.custom_minimum_size = Vector2(0, 260 if narrow else 360)
	right.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(right)
	details = VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	details.add_theme_constant_override("separation", 12)
	right.add_child(details)

	add_child(UI.button("Wróć", func(): if on_back.is_valid(): on_back.call()))
	if selected.is_empty() and not ModManager.effective_order().is_empty():
		selected = ModManager.effective_order()[0]
	_refresh()


func _refresh() -> void:
	if list_box == null:
		return
	UI.clear(list_box)
	var order := ModManager.effective_order()
	for i in order.size():
		var id: String = order[i]
		var m: Dictionary = ModManager.manifests[id]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		row.add_child(UI.label("%d." % (i + 1), 17, UI.MUTED))
		var cb := CheckBox.new()
		cb.button_pressed = ModManager.is_enabled(id)
		cb.disabled = ModManager.enabled_locked(id) or m.get("required", false)
		cb.tooltip_text = "Wymagany" if m.get("required", false) else "Włącz lub wyłącz mod"
		cb.toggled.connect(func(on): ModManager.set_enabled(id, on))
		row.add_child(cb)
		var name_btn := Button.new()
		name_btn.text = m.get("name", id)
		name_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		name_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_btn.custom_minimum_size = Vector2(0, 46)
		if id == selected:
			name_btn.add_theme_stylebox_override("normal", UI._box(UI.ACCENT.darkened(0.35), 8, UI.ACCENT, 10))
		name_btn.pressed.connect(func(): selected = id; _refresh())
		row.add_child(name_btn)
		var up := Button.new()
		up.text = "Wyżej"
		up.custom_minimum_size = Vector2(72, 46)
		up.disabled = ModManager.order_locked() or i == 0
		up.pressed.connect(func(): ModManager.move(id, -1))
		row.add_child(up)
		var down := Button.new()
		down.text = "Niżej"
		down.custom_minimum_size = Vector2(72, 46)
		down.disabled = ModManager.order_locked() or i == order.size() - 1
		down.pressed.connect(func(): ModManager.move(id, 1))
		row.add_child(down)
		list_box.add_child(row)
	if ModManager.order_locked():
		list_box.add_child(UI.wrap("[serwer] Kolejność ustawiona przez serwer.", 15, UI.LOCK))
	_details()


func _details() -> void:
	UI.clear(details)
	if not ModManager.manifests.has(selected):
		details.add_child(UI.wrap("Wybierz mod z listy."))
		return
	var m: Dictionary = ModManager.manifests[selected]
	details.add_child(UI.label("%s  %s" % [m.get("name", selected), m.get("version", "")], 24))
	details.add_child(UI.label("Autor: %s" % m.get("author", "nieznany"), 16, UI.MUTED))
	details.add_child(UI.wrap(m.get("description", ""), 17, UI.TEXT))
	var defs: Array = ModManager.setting_defs(selected)
	if defs.is_empty():
		details.add_child(UI.wrap("Ten mod nie ma ustawień."))
		return
	details.add_child(UI.label("Ustawienia", 20))
	for d in defs:
		details.add_child(_setting(selected, d))
	details.add_child(UI.button("Przywróć domyślne", func(): ModManager.reset(selected)))


func _setting(id: String, d: Dictionary) -> Control:
	var key: String = d.key
	var locked := ModManager.is_locked(id, key)
	var text: String = d.get("label", key)
	if d.get("world", false):
		text += " (nowe światy)"
	if locked:
		text = "[serwer] " + text
	var v: Variant = ModManager.get_value(id, key)
	match d.get("type", "float"):
		"bool":
			return UI.check_row(text, bool(v), func(on): ModManager.set_value(id, key, on), locked)
		"int":
			return UI.slider_row(text, d.get("min", 0), d.get("max", 100), d.get("step", 1), int(v),
				func(x): return str(int(x)), func(x): ModManager.set_value(id, key, int(x)), locked)
		_:
			return UI.slider_row(text, d.get("min", 0.0), d.get("max", 1.0), d.get("step", 0.1), float(v),
				func(x): return "%.1f" % x, func(x): ModManager.set_value(id, key, x), locked)
