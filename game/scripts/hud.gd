class_name Hud
extends Control
## Celownik, pasek przedmiotów (z trybu kreatywnego albo z kontenera moda), informacje,
## podpowiedzi sterowania, paski i napisy modów (engine.ui.bar / engine.ui.text) oraz powiadomienia.

var player: Player
var world: World
var main: Node
var info: Label
var help: Label
var bar: HBoxContainer
var toasts: VBoxContainer
var slots: Array[Panel] = []
var mod_box: VBoxContainer
var mod_texts: VBoxContainer
var flash := 0.0
var tint := Color(0, 0, 0, 0)  # zabarwienie ekranu (np. pod wodą)
var touch_mode := false
var _timer := 0.0
var _last_health := -1.0


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

	mod_box = VBoxContainer.new()
	mod_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mod_box.add_theme_constant_override("separation", 4)
	add_child(mod_box)
	mod_texts = VBoxContainer.new()
	mod_texts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(mod_texts)

	item_label = _outlined(16)
	item_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	item_label.modulate.a = 0.0
	add_child(item_label)
	player.selection_changed.connect(func(_i):
		_rebuild_bar()
		_show_item())
	player.health_changed.connect(func(v, _m):
		if _last_health >= 0.0 and v < _last_health:
			flash = 0.45
		_last_health = v)
	player.died.connect(func(_c): notify("Zginąłeś. Odradzasz się w punkcie startu."))
	effect_box = VBoxContainer.new()
	effect_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(effect_box)
	Mods.effects_changed.connect(_rebuild_effects)
	Mods.hotbar_changed.connect(_rebuild_bar)
	Mods.hud_changed.connect(_rebuild_mod_hud)
	Mods.notified.connect(notify)
	_rebuild_bar()
	_rebuild_mod_hud()


func _outlined(size_px: int) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size_px)
	l.add_theme_color_override("font_color", Color(1, 1, 1))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("outline_size", 4)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _update_help() -> void:
	var t := "WASD ruch · Spacja skok · Ctrl bieg · Shift kucanie · X pełzanie · Z siad · LPM kop i atak (seria) · PPM postaw / użyj · 1-9 przedmiot · V widok · T czat · Esc pauza"
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
	var creative: bool = Mods.hotbar.container == ""
	var list := Blocks.reg.placeable
	for i in n:
		var it: Dictionary = {}
		if creative:
			if not list.is_empty():
				it = {"item": list[i % list.size()], "count": 1}
		else:
			it = Mods.hotbar_item(i)
		var count := int(it.get("count", 0))
		var p := Panel.new()
		p.custom_minimum_size = Vector2(52, 52)
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0, 0, 0, 0.45)
		sb.set_corner_radius_all(6)
		sb.set_border_width_all(3 if i == player.selected else 1)
		sb.border_color = Color(1, 0.92, 0.6) if i == player.selected else Color(1, 1, 1, 0.35)
		p.add_theme_stylebox_override("panel", sb)
		if not it.is_empty():
			var tr := TextureRect.new()
			tr.texture = Blocks.reg.icon(str(it.item))
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


## Paski i napisy z modów: pasek {label, value, max, color}, napis {text, color}.
## Z polem anchor ("top_left", "top", "top_right", "left", "center", "right", "bottom_left", "bottom",
## "bottom_right") i offset {x, y} element stoi w wybranym miejscu ekranu zamiast na liście.
var mod_free: Control
var free_items: Array = []   # [Control, anchor, offset]

const ANCHORS := {"top_left": Vector2(0, 0), "top": Vector2(0.5, 0), "top_right": Vector2(1, 0),
	"left": Vector2(0, 0.5), "center": Vector2(0.5, 0.5), "right": Vector2(1, 0.5),
	"bottom_left": Vector2(0, 1), "bottom": Vector2(0.5, 1), "bottom_right": Vector2(1, 1)}


func _place_free() -> void:
	var vs := get_viewport_rect().size
	for f in free_items:
		var c: Control = f[0]
		if not is_instance_valid(c):
			continue
		var a: Vector2 = f[1]
		var sz := c.get_combined_minimum_size()
		c.size = sz
		c.position = (vs - sz) * a + (f[2] as Vector2) + Vector2(12, 12) * (Vector2.ONE - a * 2.0)   # margines od krawędzi


func _rebuild_mod_hud() -> void:
	if mod_free == null:
		mod_free = Control.new()
		mod_free.mouse_filter = Control.MOUSE_FILTER_IGNORE
		mod_free.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(mod_free)
	free_items.clear()
	for box in [mod_box, mod_texts, mod_free]:
		for c in box.get_children():
			box.remove_child(c)
			c.queue_free()
	var ids := Mods.hud.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = Mods.hud[id]
		var col: Color = d.color if d.get("color") is Color else Color.from_string(str(d.get("color", "#e0e0e0")), Color(0.9, 0.9, 0.9))
		var w := _mod_hud_item(d, col)
		if d.has("anchor"):
			var off := Registry.arr(d.get("offset"))
			mod_free.add_child(w)
			free_items.append([w, ANCHORS.get(str(d.anchor), Vector2.ZERO), Vector2(float(off[0]) if off.size() > 0 else 0.0, float(off[1]) if off.size() > 1 else 0.0)])
		elif d.type == "bar" or d.type == "image":
			mod_box.add_child(w)
		else:
			mod_texts.add_child(w)
	_place_free.call_deferred()


func _mod_hud_item(d: Dictionary, col: Color) -> Control:
	if d.type == "image":
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 6)
		var tr := TextureRect.new()
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tr.texture = ModWindow.load_image(d, str(d.get("mod", "")))
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		var sz := Registry.arr(d.get("size"))
		var w := float(sz[0]) if sz.size() > 0 else 40.0
		tr.custom_minimum_size = Vector2(w, float(sz[1]) if sz.size() > 1 else w)
		tr.modulate = Color(1, 1, 1, float(d.get("alpha", 1.0)))
		row.add_child(tr)
		if str(d.get("text", "")) != "":
			var l := _outlined(int(d.get("font_size", 15)))
			l.text = str(d.text)
			l.add_theme_color_override("font_color", col)
			row.add_child(l)
		return row
	if d.type == "bar":
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_theme_constant_override("separation", 8)
		var l := _outlined(14)
		l.text = str(d.get("label", ""))
		l.custom_minimum_size = Vector2(70, 0)
		row.add_child(l)
		var bar_bg := Panel.new()
		bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bar_bg.custom_minimum_size = Vector2(180, 14)
		var bg := StyleBoxFlat.new()
		bg.bg_color = Color(0, 0, 0, 0.5)
		bg.set_corner_radius_all(4)
		bar_bg.add_theme_stylebox_override("panel", bg)
		var mx := maxf(0.0001, float(d.get("max", 1.0)))
		var fill := Panel.new()
		fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fs := StyleBoxFlat.new()
		fs.bg_color = col
		fs.set_corner_radius_all(4)
		fill.add_theme_stylebox_override("panel", fs)
		fill.position = Vector2(2, 2)
		fill.size = Vector2(176.0 * clampf(float(d.get("value", 0.0)) / mx, 0.0, 1.0), 10)
		bar_bg.add_child(fill)
		row.add_child(bar_bg)
		var v := _outlined(13)
		v.text = "%d/%d" % [roundi(float(d.get("value", 0.0))), roundi(mx)]
		row.add_child(v)
		return row
	var l := _outlined(int(d.get("font_size", 15)))
	l.text = str(d.get("text", ""))
	l.add_theme_color_override("font_color", col)
	return l


## Efekty gracza: ikona, nazwa i pozostały czas (prawy górny róg).
var effect_box: VBoxContainer


func _rebuild_effects() -> void:
	for c in effect_box.get_children():
		c.queue_free()
	var eff: Dictionary = Mods.shown_effects()
	for n in eff:
		var d: Dictionary = Mods.registry.effects.get(n, {})
		var row := HBoxContainer.new()
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ic := TextureRect.new()
		ic.texture = Mods.registry.effect_icon(n)
		ic.custom_minimum_size = Vector2(28, 28)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		row.add_child(ic)
		var l := _outlined(15)
		var left := int(ceil(float(eff[n].get("left", 0.0))))
		l.text = "%s  %d:%02d" % [str(d.get("name", n)), left / 60, left % 60]
		if bool(d.get("negative", false)):
			l.add_theme_color_override("font_color", Color(1.0, 0.6, 0.55))
		row.add_child(l)
		effect_box.add_child(row)


## Po zmianie przedmiotu w ręce: nazwa i pierwsze linie opisu nad paskiem przez 2 s.
var item_label: Label
var _item_tw: Tween


func _show_item() -> void:
	var it := player.current_item()
	if it.is_empty():
		item_label.modulate.a = 0.0
		return
	var lines := Mods.registry.tooltip(it).split("\n")
	item_label.text = "\n".join(lines.slice(0, 3))
	item_label.modulate.a = 1.0
	if _item_tw:
		_item_tw.kill()
	_item_tw = create_tween()
	_item_tw.tween_interval(2.0)
	_item_tw.tween_property(item_label, "modulate:a", 0.0, 0.5)


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
	if not free_items.is_empty():
		_place_free()
	_timer -= delta
	if _timer <= 0.0:
		_timer = 0.25
		var p := player.global_position
		var biome: String = world.terrain.biome_name(world.terrain.column(floori(p.x), floori(p.z)).y)
		var clock: String = main.time_text() if main else ""
		var it := player.current_item()
		var block_name: String = Blocks.reg.item_name(str(it.item)) if not it.is_empty() else "pusto"
		if Settings.show_debug:
			info.text = "%d FPS\n%s\nx %.0f  y %.0f  z %.0f · %s · %s\nprzedmiot: %s · mody: %d" % [
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
	mod_box.position = Vector2(bar.position.x, bar.position.y - mod_box.size.y - 10)
	effect_box.position = Vector2(size.x - effect_box.size.x - 14, 46)
	item_label.size = Vector2(size.x - 40, 0)
	item_label.position = Vector2(20, mod_box.position.y - item_label.size.y - 6)
	mod_texts.position = Vector2(14, info.position.y + info.size.y + 8)
	flash = maxf(0.0, flash - delta)
	toasts.size = Vector2(440, 0)
	toasts.position = Vector2((size.x - 440) / 2.0, size.y * 0.22)
	queue_redraw()


func _draw() -> void:
	if tint.a > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), tint)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.8, 0.05, 0.05, flash * 0.5))
	var c := size / 2.0
	var col := Color(1, 1, 1, 0.85)
	draw_rect(Rect2(c + Vector2(-9, -1), Vector2(18, 2)), col)
	draw_rect(Rect2(c + Vector2(-1, -9), Vector2(2, 18)), col)
