class_name TouchControls
extends Control
## Sterowanie dotykowe: joystick po lewej, przeciąganie po prawej obraca kamerę, przyciski akcji.
## Każdy palec jest obsługiwany osobno, więc można iść, rozglądać się i skakać jednocześnie.

var player: Player

const JOY_R := 80.0
const SENS := 0.006

var joy_center := Vector2.ZERO
var joy_knob := Vector2.ZERO
var joy_finger := -1
var look_finger := -1
var buttons := {}        # nazwa -> [środek, promień, etykieta]
var button_fingers := {} # palec -> nazwa


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
		"next": [Vector2(size.x / 2.0 + 210, b - 44), 30.0, ">"],
		"view": [Vector2(size.x - 60, 60), 32.0, "Widok"],
	}


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_layout()
		if event.pressed:
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
			if button_fingers.has(event.index):
				_press(button_fingers[event.index], false)
				button_fingers.erase(event.index)
			if event.index == joy_finger:
				joy_finger = -1
				joy_knob = Vector2.ZERO
				player.touch_move = Vector2.ZERO
			if event.index == look_finger:
				look_finger = -1
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag:
		if event.index == joy_finger:
			_drag_joy(event.position)
		elif event.index == look_finger:
			player.look(event.relative * SENS)
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
			if down: player.break_block()
		"place":
			if down: player.place_block()
		"next":
			if down: player.select((player.selected + 1) % Blocks.PLACEABLE.size())
		"view":
			if down: player.toggle_view()


func _process(_delta: float) -> void:
	size = get_viewport_rect().size
	queue_redraw()


func _draw() -> void:
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
