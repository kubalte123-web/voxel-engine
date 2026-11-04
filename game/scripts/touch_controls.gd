class_name TouchControls
extends Control
## Sterowanie dotykowe: joystick po lewej, przeciąganie po prawej obraca kamerę, przyciski akcji.
## Każdy palec jest obsługiwany osobno, więc można iść, rozglądać się i skakać jednocześnie.

var player: Player
var main: Node

const JOY_R := 80.0
const SENS := 0.005

var joy_center := Vector2.ZERO
var joy_knob := Vector2.ZERO
var joy_finger := -1
var look_finger := -1
var buttons := {}        # nazwa -> [środek, promień, etykieta]
var button_fingers := {} # palec -> nazwa
var mod_buttons := {}    # nazwa przycisku -> id skrótu moda
var last_pos := {}       # palec -> ostatnia pozycja (liczymy ruch sami, bez skoków)
const MAX_STEP := 70.0   # większy skok między zdarzeniami to błąd przeglądarki, pomijamy go


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _layout() -> void:
	joy_center = Vector2(150, size.y - 150)
	var r := size.x - 110
	var b := size.y
	buttons = {
		"jump": [Vector2(r, b - 120), 58.0, "Skok"],
		"break": [Vector2(r - 140, b - 80), 48.0, "Kop"],
		"place": [Vector2(r - 20, b - 260), 48.0, "Postaw"],
		"next": [Vector2(r - 180, b - 200), 32.0, "Blok"],
		"view": [Vector2(size.x - 60, 60), 32.0, "Widok"],
		"menu": [Vector2(size.x - 140, 60), 32.0, "Menu"],
	}
	var i := 0
	for name in mod_buttons:
		buttons[name] = [Vector2(size.x - 220 - i * 80, 60), 32.0, mod_buttons[name][1]]
		i += 1


func _input(event: InputEvent) -> void:
	if get_tree().paused or (main and not main.windows.is_empty()):
		return
	if event is InputEventScreenTouch:
		_layout()
		if event.pressed:
			last_pos[event.index] = event.position
			for name in buttons:
				var bt: Array = buttons[name]
				if event.position.distance_to(bt[0]) <= bt[1] + 12.0:
					button_fingers[event.index] = name
					_press(name, true)
					get_viewport().set_input_as_handled()
					return
			if event.position.x < size.x * 0.4 and joy_finger == -1:
				joy_finger = event.index
				joy_knob = Vector2.ZERO
				_drag_joy(event.position)
			elif look_finger == -1:
				look_finger = event.index
		else:
			last_pos.erase(event.index)
			if button_fingers.has(event.index):
				_press(button_fingers[event.index], false)
				button_fingers.erase(event.index)
			if event.index == joy_finger:
				joy_finger = -1
				joy_knob = Vector2.ZERO
				player.touch_move = Vector2.ZERO
			if event.index == look_finger:
				look_finger = -1
			# drugi palec przejmuje rolę, jeśli pierwszy został puszczony
			if joy_finger == -1 and look_finger == -1:
				last_pos.clear()
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == joy_finger:
			_drag_joy(event.position)
		elif event.index == look_finger:
			var prev: Vector2 = last_pos.get(event.index, event.position)
			var step: Vector2 = event.position - prev
			# pozycja nagle przeskoczyła (np. przeglądarka zamieniła palce): ignorujemy ten ruch
			if step.length() <= MAX_STEP:
				player.look(step * SENS * Settings.touch_sensitivity)
		last_pos[event.index] = event.position
		get_viewport().set_input_as_handled()


func _drag_joy(pos: Vector2) -> void:
	var d := (pos - joy_center).limit_length(JOY_R)
	joy_knob = d
	player.touch_move = d / JOY_R


func _press(name: String, down: bool) -> void:
	match name:
		"jump":
			player.touch_jump = down
		"break":
			if down: player.start_digging()
			else: player.stop_digging()
		"place":
			if down: player.use_item()
		"next":
			if down: player.select((player.selected + 1) % player.hotbar_size())
		"view":
			if down: player.toggle_view()
		"menu":
			if down and main: main.open_pause()
		_:
			if down and mod_buttons.has(name):
				Mods.press_bind(mod_buttons[name][0])


func _process(_delta: float) -> void:
	size = get_viewport_rect().size
	queue_redraw()


func _draw() -> void:
	if main and not main.windows.is_empty():
		return
	_layout()
	var font := get_theme_default_font()
	draw_circle(joy_center, JOY_R, Color(1, 1, 1, 0.12))
	draw_arc(joy_center, JOY_R, 0, TAU, 48, Color(1, 1, 1, 0.4), 2.0)
	draw_circle(joy_center + joy_knob, 34.0, Color(1, 1, 1, 0.35))
	for name in buttons:
		var bt: Array = buttons[name]
		var held := button_fingers.values().has(name)
		draw_circle(bt[0], bt[1], Color(0, 0, 0, 0.45) if not held else Color(1, 1, 1, 0.35))
		draw_arc(bt[0], bt[1], 0, TAU, 40, Color(1, 1, 1, 0.55), 2.0)
		var fs := 18 if bt[1] > 40.0 else 15
		var w := font.get_string_size(bt[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		draw_string(font, bt[0] + Vector2(-w / 2.0, fs * 0.35), bt[2], HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1))


## Przyciski dotykowe dla skrótów dodanych przez mody (engine.input.bind).
func refresh_binds() -> void:
	mod_buttons.clear()
	for b in Mods.binds:
		mod_buttons["mod_" + b.id] = [b.id, b.label.left(8)]
