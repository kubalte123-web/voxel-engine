class_name CharacterModel
extends Node3D
## Klockowa postać „Wędrowiec": tunika, szalik, plecak z kocem, skórzana czapka.
## Przód postaci to -Z. Animacje wbudowane są proceduralne (chód, oddech, skok, machnięcie ręką);
## mody mogą odtwarzać własne animacje klatkowe i zastępować nimi stany "idle", "walk", "jump".
## Części do animacji: body, head, arm_left, arm_right, leg_left, leg_right.
## Kolory (engine.player.colors): skin, tunic, tunic_dark, trousers, boots, leather, scarf, hair, bedroll, gold, eye.

var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var torso: Node3D
var head: Node3D
var scarf_tail: Node3D

var walk_phase := 0.0
var sitting := false  # jazda na stworzeniu: nogi do przodu
var swing := 0.0  # 1.0 = początek machnięcia ręką (kopanie / stawianie)
var t := 0.0
var parts := {}       # nazwa części -> Node3D
var mats := {}        # nazwa koloru -> materiał
var overrides: Variant = null  # zamienniki stanów dla innych graczy (null = Mods.anim_overrides)
var anim := {}        # odtwarzana animacja moda: {"name", "def", "time", "weight", "loop", "explicit"}

const DEFAULT_COLORS := {
	"skin": Color(0.88, 0.68, 0.52), "tunic": Color(0.24, 0.50, 0.46), "tunic_dark": Color(0.18, 0.40, 0.37),
	"trousers": Color(0.55, 0.45, 0.32), "boots": Color(0.30, 0.20, 0.13), "leather": Color(0.48, 0.31, 0.18),
	"scarf": Color(0.72, 0.22, 0.20), "hair": Color(0.25, 0.16, 0.10), "bedroll": Color(0.78, 0.70, 0.52),
	"gold": Color(0.86, 0.68, 0.26), "eye": Color(0.12, 0.12, 0.14), "mouth": Color(0.55, 0.32, 0.28),
	"nose": Color(0.81, 0.63, 0.48), "strap": Color(0.36, 0.23, 0.13),
}


func _mat(slot: String) -> StandardMaterial3D:
	if not mats.has(slot):
		var m := StandardMaterial3D.new()
		m.albedo_color = DEFAULT_COLORS.get(slot, Color.WHITE)
		m.roughness = 0.9
		mats[slot] = m
	return mats[slot]


## Zmienia kolory części postaci, np. {"tunic": Color(0.6, 0.2, 0.2)}.
func apply_colors(colors: Dictionary) -> void:
	for k in colors:
		if mats.has(k):
			mats[k].set_meta("base", colors[k])
			mats[k].albedo_color = colors[k]
	if light_value.x >= 0.0:
		set_light(light_value)


var light_value := Vector2(-1, 0)


## Oświetlenie postaci światłem z mapy światła (Vector2(niebo, bloki), 0..1).
func set_light(l: Vector2) -> void:
	light_value = l
	EntityLight.apply(mats.values(), l)
	if held_sprite:
		var f := EntityLight.factors(l)
		var v := clampf(f.x + f.y, 0.0, 1.0)
		held_sprite.modulate = Color(v, v, v)


# ---------- przedmiot w ręce i rzeczy założone przez mody ----------

var held_sprite: Sprite3D
var held_key := ""
var wear_nodes: Array = []


## Przedmiot trzymany w prawej ręce (ikona). Pusty klucz chowa.
func set_held(key: String) -> void:
	if key == held_key or arms.size() < 2:
		return
	held_key = key
	if held_sprite:
		held_sprite.queue_free()
		held_sprite = null
	if key == "" or Mods.registry == null or not Mods.registry.items.has(key):
		return
	held_sprite = Sprite3D.new()
	held_sprite.texture = Mods.registry.icon(key)
	held_sprite.pixel_size = 0.36 / maxf(1.0, float(held_sprite.texture.get_width()))
	held_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	held_sprite.shaded = false
	held_sprite.position = Vector3(0, -0.62, -0.14)
	held_sprite.rotation_degrees = Vector3(-60, 90, 0)
	arms[1].add_child(held_sprite)
	set_light(light_value if light_value.x >= 0.0 else Vector2(1, 0))


## Rzeczy założone przez mody (hełm, plecak, peleryna): id -> {part, boxes = {{size, pos, color, rot}}}.
## part: body, head, arm_left, arm_right, leg_left, leg_right.
func set_wear(wear: Dictionary) -> void:
	for n in wear_nodes:
		if is_instance_valid(n):
			n.queue_free()
	wear_nodes.clear()
	for id in wear:
		var w: Variant = wear[id]
		if not w is Dictionary:
			continue
		var parent: Node3D = parts.get(str(w.get("part", "head")))
		if parent == null:
			continue
		for b in Registry.arr(w.get("boxes")):
			if not b is Dictionary:
				continue
			var col := TexGen._col(b.get("color", "#888888"), Color.GRAY)
			var key := "wear|" + col.to_html()
			if not mats.has(key):
				var m := StandardMaterial3D.new()
				m.albedo_color = col
				m.roughness = 0.85
				mats[key] = m
			var mi := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Creature.vec(b.get("size"), Vector3(0.2, 0.2, 0.2))
			mi.mesh = bm
			mi.material_override = mats[key]
			mi.position = Creature.vec(b.get("pos"))
			mi.rotation_degrees = Creature.vec(b.get("rot"))
			parent.add_child(mi)
			wear_nodes.append(mi)
	if light_value.x >= 0.0:
		set_light(light_value)


func _box(parent: Node3D, size: Vector3, pos: Vector3, slot: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(slot)
	mi.position = pos
	parent.add_child(mi)
	return mi


func _pivot(parent: Node3D, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.position = pos
	parent.add_child(n)
	return n


func _ready() -> void:
	# nogi (punkt obrotu w biodrze)
	for side in [-1.0, 1.0]:
		var hip := _pivot(self, Vector3(0.12 * side, 0.76, 0))
		_box(hip, Vector3(0.22, 0.6, 0.24), Vector3(0, -0.3, 0), "trousers")
		_box(hip, Vector3(0.24, 0.18, 0.3), Vector3(0, -0.67, -0.03), "boots")
		_box(hip, Vector3(0.25, 0.05, 0.31), Vector3(0, -0.57, -0.03), "leather")
		legs.append(hip)

	# tułów
	torso = _pivot(self, Vector3(0, 0.76, 0))
	_box(torso, Vector3(0.5, 0.66, 0.28), Vector3(0, 0.33, 0), "tunic")
	_box(torso, Vector3(0.52, 0.16, 0.3), Vector3(0, 0.04, 0), "tunic_dark")  # dół tuniki
	_box(torso, Vector3(0.53, 0.07, 0.31), Vector3(0, 0.15, 0), "leather")    # pas
	_box(torso, Vector3(0.09, 0.08, 0.03), Vector3(0, 0.15, -0.165), "gold")  # klamra
	_box(torso, Vector3(0.12, 0.1, 0.06), Vector3(0.16, 0.08, -0.17), "leather")  # sakiewka
	_box(torso, Vector3(0.05, 0.4, 0.02), Vector3(-0.1, 0.42, -0.145), "tunic_dark")  # rozcięcie tuniki
	# plecak z kocem
	_box(torso, Vector3(0.38, 0.42, 0.16), Vector3(0, 0.36, 0.22), "leather")
	_box(torso, Vector3(0.3, 0.12, 0.03), Vector3(0, 0.44, 0.31), "strap")
	_box(torso, Vector3(0.46, 0.13, 0.13), Vector3(0, 0.62, 0.22), "bedroll")
	_box(torso, Vector3(0.04, 0.14, 0.14), Vector3(-0.12, 0.62, 0.22), "leather")
	_box(torso, Vector3(0.04, 0.14, 0.14), Vector3(0.12, 0.62, 0.22), "leather")
	# szalik i jego koniec na plecach
	_box(torso, Vector3(0.46, 0.09, 0.32), Vector3(0, 0.66, 0), "scarf")
	scarf_tail = _pivot(torso, Vector3(0.12, 0.64, 0.15))
	_box(scarf_tail, Vector3(0.1, 0.3, 0.04), Vector3(0, -0.15, 0.02), "scarf")

	# ręce (punkt obrotu w barku)
	for side in [-1.0, 1.0]:
		var sh := _pivot(torso, Vector3(0.34 * side, 0.6, 0))
		_box(sh, Vector3(0.17, 0.5, 0.2), Vector3(0, -0.22, 0), "tunic")
		_box(sh, Vector3(0.18, 0.06, 0.21), Vector3(0, -0.45, 0), "tunic_dark")
		_box(sh, Vector3(0.15, 0.13, 0.17), Vector3(0, -0.54, 0), "skin")
		arms.append(sh)

	# głowa
	head = _pivot(torso, Vector3(0, 0.68, 0))
	_box(head, Vector3(0.4, 0.4, 0.4), Vector3(0, 0.2, 0), "skin")
	_box(head, Vector3(0.42, 0.1, 0.42), Vector3(0, 0.38, 0), "hair")        # włosy
	_box(head, Vector3(0.42, 0.24, 0.07), Vector3(0, 0.27, 0.18), "hair")    # włosy z tyłu
	_box(head, Vector3(0.44, 0.1, 0.44), Vector3(0, 0.44, 0.0), "leather")    # czapka
	_box(head, Vector3(0.3, 0.05, 0.12), Vector3(0, 0.4, -0.25), "leather")  # daszek
	_box(head, Vector3(0.06, 0.06, 0.02), Vector3(-0.08, 0.2, -0.205), "eye")
	_box(head, Vector3(0.06, 0.06, 0.02), Vector3(0.08, 0.2, -0.205), "eye")
	_box(head, Vector3(0.09, 0.025, 0.02), Vector3(-0.08, 0.26, -0.205), "hair")
	_box(head, Vector3(0.09, 0.025, 0.02), Vector3(0.08, 0.26, -0.205), "hair")
	_box(head, Vector3(0.06, 0.06, 0.04), Vector3(0, 0.14, -0.215), "nose")  # nos
	_box(head, Vector3(0.12, 0.025, 0.02), Vector3(0, 0.07, -0.205), "mouth")  # usta
	parts = {"body": torso, "head": head, "arm_left": arms[0], "arm_right": arms[1], "leg_left": legs[0], "leg_right": legs[1]}
	apply_colors(Mods.model_colors)


## Animacja proceduralna: każda postawa (stanie i chód, bieg, kucanie, pełzanie, siedzenie, jazda, pływanie,
## skok i spadanie) liczy docelowe kąty stawów, postawy przenikają się płynnie (wagi), a stawy dochodzą do
## celu wykładniczo (bez szarpnięć przy zmianie stanu). Na to nakładają się akcje: machnięcie, kopanie,
## ataki w serii (attack1, attack2, attack3), zranienie i lądowanie.
## Kąty: dodatnie x unosi zwisającą kończynę do przodu i odchyla tułów do tyłu; dodatnie y obraca w lewo.

var pose := "stand"        # stand | crouch | crawl | sit (ustawia gracz)
var swimming := false
var digging := false       # kopanie bloku (pętla machnięć)
var sprinting := false
var vertical := 0.0        # prędkość pionowa (skok w górę, spadanie)
var action := {}           # {name, time, length}
var _w := {"crouch": 0.0, "crawl": 0.0, "sit": 0.0, "ride": 0.0, "air": 0.0, "swim": 0.0}
var _was_floor := true
var _land := 0.0
var _land_power := 0.0
var _dig_t := 0.0
var _dig_hold := 0.0         # kopanie trwa jeszcze chwilę po przerwie (bez restartu ruchu)
const DIG_CYCLE := 0.42      # jeden zamach przy kopaniu (s)
const DIG_HOLD := 0.3

const ACTIONS := {"swing": 0.28, "attack1": 0.34, "attack2": 0.34, "attack3": 0.55, "hurt": 0.3, "dig": 0.3}


static func _k(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


static func _ease(x: float) -> float:
	x = clampf(x, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


## Jednorazowa akcja: swing, attack1, attack2, attack3, hurt (wbudowane) albo animacja klatkowa moda.
signal acted(name: String)


func play_action(name: String) -> void:
	if not action.is_empty() and action.name == name and float(action.time) < 0.08:
		return   # ta sama akcja przed chwilą (np. z serwera i od gracza)
	acted.emit(name)
	if ACTIONS.has(name):
		action = {"name": name, "time": 0.0, "length": float(ACTIONS[name])}
	else:
		play(name)


func reset_pose() -> void:
	for n in [legs[0], legs[1], arms[0], arms[1], head]:
		n.rotation = Vector3.ZERO
	torso.rotation = Vector3.ZERO
	torso.position = Vector3(0, 0.76, 0)
	for k in _w:
		_w[k] = 0.0
	action = {}
	walk_phase = 0.0
	t = 0.0


## Podgląd (tools/anim_preview.gd): postawa albo akcja po czasie `time` od początku.
func preview(what: String, speed: float, time: float) -> void:
	reset_pose()
	pose = "stand"
	swimming = false
	digging = false
	sprinting = false
	sitting = false
	var floor := true
	match what:
		"crouch", "crawl", "sit": pose = what
		"swim": swimming = true; floor = false
		"ride": sitting = true
		"run": sprinting = true
		"jump": floor = false; vertical = 5.0
		"fall": floor = false; vertical = -12.0
		"dig": digging = true
		"stand", "walk": pass
		_: play_action(what)
	var step := 1.0 / 60.0
	var n := int(time / step) + 30
	if ACTIONS.has(what):
		n = int(time / step)
		for i in 30:   # ustalona postawa przed akcją
			var keep := action
			action = {}
			animate(step, speed, floor, 0.0)
			action = keep
	for i in n:
		animate(step, speed, floor, 0.0)


## speed: prędkość pozioma, on_floor: czy stoi, look_pitch: kąt kamery (ujemny: patrzy w dół).
func animate(delta: float, speed: float, on_floor: bool, look_pitch: float) -> void:
	t += delta
	var crawl := pose == "crawl"
	# wagi postaw – płynne przejścia
	var want := {"crouch": pose == "crouch", "crawl": crawl, "sit": pose == "sit" and not sitting, "ride": sitting,
		"swim": swimming and not on_floor and not sitting, "air": not on_floor and not swimming and not sitting}
	for k in _w:
		_w[k] = lerpf(_w[k], 1.0 if want[k] else 0.0, _k(9.0, delta))
	# lądowanie po upadku: przysiad
	if on_floor and not _was_floor and vertical < -5.0:
		_land = 1.0
		_land_power = clampf(-vertical / 18.0, 0.3, 1.0)
	_was_floor = on_floor
	_land = maxf(0.0, _land - delta / 0.3)

	var moving := clampf(speed / 4.5, 0.0, 1.0)
	var run := clampf((speed - 4.6) / 2.5, 0.0, 1.0) if sprinting else 0.0
	var cadence := 3.4 + speed * 1.7
	if crawl:
		cadence = 2.0 + speed * 2.2
	walk_phase += delta * cadence * (1.0 if speed > 0.25 else 0.0)
	var s := sin(walk_phase)
	var c := cos(walk_phase)
	var breath := sin(t * 1.8)
	var state := "walk" if speed > 0.3 else "idle"

	# ---------- stanie, chód i bieg ----------
	var stride := 0.7 * moving + 0.35 * run
	var L := [Vector3(s * stride, 0, 0), Vector3(-s * stride, 0, 0)]
	var A := [Vector3(-s * (0.55 * moving + 0.45 * run) - breath * 0.03 * (1.0 - moving), 0, -0.07 - 0.02 * (1.0 - moving)),
		Vector3(s * (0.55 * moving + 0.45 * run) - breath * 0.03 * (1.0 - moving), 0, 0.07 + 0.02 * (1.0 - moving))]
	if run > 0.0:   # w biegu łokcie wyżej
		A[0].x += 0.25 * run
		A[1].x += 0.25 * run
	var T_rot := Vector3(-0.05 * moving - 0.22 * run, s * 0.1 * moving, c * 0.03 * moving)
	var T_y := 0.76 + absf(c) * (0.045 * moving + 0.05 * run) + breath * 0.006 * (1.0 - moving)
	var H := Vector3(clampf(look_pitch * 0.45, -0.5, 0.4) + 0.05 * moving, -s * 0.08 * moving, 0)
	if speed > 0.3:
		state = "run" if run > 0.3 else "walk"

	# ---------- postawy (mieszane wagami) ----------
	var wc: float = _w.crouch
	if wc > 0.001:
		L = _mixv(L, [Vector3(s * stride * 0.5 + 0.35, 0, -0.08), Vector3(-s * stride * 0.5 + 0.35, 0, 0.08)], wc)
		A = _mixv(A, [Vector3(-s * 0.3 * moving + 0.35, 0, -0.18), Vector3(s * 0.3 * moving + 0.35, 0, 0.18)], wc)
		T_rot = T_rot.lerp(Vector3(-0.5, s * 0.06 * moving, 0), wc)
		T_y = lerpf(T_y, 0.6 + absf(c) * 0.02 * moving, wc)
		H = H.lerp(Vector3(0.38 + look_pitch * 0.3, 0, 0), wc)
		if pose == "crouch":
			state = "crouch"
	var wr: float = _w.crawl
	if wr > 0.001:
		L = _mixv(L, [Vector3(-1.5 + s * 0.35 * moving, 0, -0.1), Vector3(-1.5 - s * 0.35 * moving, 0, 0.1)], wr)
		A = _mixv(A, [Vector3(2.7 + s * 0.45 * moving, 0, -0.25), Vector3(2.7 - s * 0.45 * moving, 0, 0.25)], wr)
		T_rot = T_rot.lerp(Vector3(-1.5, s * 0.12 * moving, s * 0.08 * moving), wr)
		T_y = lerpf(T_y, 0.2 + absf(c) * 0.03 * moving, wr)
		H = H.lerp(Vector3(1.25 + look_pitch * 0.3, -s * 0.1 * moving, 0), wr)
		if crawl:
			state = "crawl"
	var ws: float = _w.sit
	if ws > 0.001:
		L = _mixv(L, [Vector3(1.45, 0.12, -0.12), Vector3(1.45, -0.12, 0.12)], ws)
		A = _mixv(A, [Vector3(0.55 + breath * 0.02, 0, -0.12), Vector3(0.55 + breath * 0.02, 0, 0.12)], ws)
		T_rot = T_rot.lerp(Vector3(0.08 + breath * 0.01, 0, 0), ws)
		T_y = lerpf(T_y, 0.34, ws)
		if pose == "sit":
			state = "sit"
	var wd: float = _w.ride
	if wd > 0.001:
		L = _mixv(L, [Vector3(1.3, 0, -0.3), Vector3(1.3, 0, 0.3)], wd)
		A = _mixv(A, [Vector3(0.6, 0, -0.1), Vector3(0.6, 0, 0.1)], wd)
		T_rot = T_rot.lerp(Vector3(-0.08 + absf(c) * 0.04 * moving, 0, 0), wd)
		T_y = lerpf(T_y, 0.76 + absf(s) * 0.03 * moving, wd)
		state = "sit"
	var wsw: float = _w.swim
	if wsw > 0.001:
		var sw := t * 4.0
		L = _mixv(L, [Vector3(-1.3 + sin(t * 9.0) * 0.3, 0, -0.08), Vector3(-1.3 - sin(t * 9.0) * 0.3, 0, 0.08)], wsw)
		A = _mixv(A, [Vector3(2.4 + sin(sw) * 0.6, cos(sw) * 0.5, -0.4 - cos(sw) * 0.4), Vector3(2.4 + sin(sw) * 0.6, -cos(sw) * 0.5, 0.4 + cos(sw) * 0.4)], wsw)
		T_rot = T_rot.lerp(Vector3(-1.2 * moving - 0.2, 0, sin(t * 2.0) * 0.06), wsw)
		T_y = lerpf(T_y, 0.76, wsw)
		H = H.lerp(Vector3(1.0 * moving + look_pitch * 0.3, 0, 0), wsw)
		state = "swim"
	var wa: float = _w.air
	if wa > 0.001:
		var up := clampf(vertical / 6.0, -1.0, 1.0)
		var flail := sin(t * 14.0) * 0.25 * clampf(-vertical / 10.0, 0.0, 1.0)
		L = _mixv(L, [Vector3(0.55 - up * 0.1, 0, -0.06), Vector3(-0.35 + up * 0.1, 0, 0.06)], wa)
		A = _mixv(A, [Vector3(0.5 + up * 0.9 + flail, 0, -0.45 - flail), Vector3(0.5 + up * 0.9 - flail, 0, 0.45 + flail)], wa)
		T_rot = T_rot.lerp(Vector3(-0.08 * up, 0, 0), wa)
		state = "jump"
	# lądowanie: krótki przysiad
	if _land > 0.0:
		var k := sin(_land * PI) * _land_power
		T_y -= 0.12 * k
		T_rot.x -= 0.25 * k
		A[0].z -= 0.35 * k
		A[1].z += 0.35 * k
		L[0].x += 0.25 * k
		L[1].x += 0.25 * k

	# ---------- akcje: kopanie, machnięcie, ataki w serii, zranienie ----------
	# kopanie: ręka uderza przed sobą (od poziomu w skos w dół), tułów i głowa stoją spokojnie;
	# krótka przerwa (np. między wykopanymi blokami) nie zaczyna ruchu od nowa
	if digging and pose != "crawl":
		_dig_hold = DIG_HOLD
	else:
		_dig_hold = maxf(0.0, _dig_hold - delta)
	if _dig_hold > 0.0:
		_dig_t += delta
		var cyc := fmod(_dig_t / DIG_CYCLE, 1.0)
		# zamach w górę (60% cyklu), szybkie uderzenie w dół (25%), chwila w dole
		var raise := _ease(cyc / 0.6) if cyc < 0.6 else 1.0 - _ease((cyc - 0.6) / 0.25)
		var fade := clampf(_dig_hold / DIG_HOLD, 0.0, 1.0) if not digging else 1.0
		A[1] = A[1].lerp(Vector3(lerpf(0.85, 1.75, raise), 0.3, 0.05), fade)
		A[0].x = lerpf(A[0].x, 0.3, 0.5 * fade)
		T_rot.y += -0.1 * fade
		T_rot.x += -0.04 * fade
	else:
		_dig_t = 0.0
	if swing > 0.0:   # stary wywołujący: do_swing() = machnięcie
		action = {"name": "swing", "time": 0.0, "length": float(ACTIONS.swing)}
		swing = 0.0
	if not action.is_empty():
		action.time += delta
		var p: float = action.time / float(action.length)
		if p >= 1.0:
			action = {}
		else:
			var env := minf(1.0, minf(p / 0.12, (1.0 - p) / 0.2))   # wejście i wyjście z akcji
			var a := _action_pose(str(action.name), p)
			if a.has("A1"):
				A[1] = A[1].lerp(a.A1, env)
			if a.has("A0"):
				A[0] = A[0].lerp(a.A0, env)
			if a.has("T"):
				T_rot += a.T * env
			if a.has("Ty"):
				T_y += float(a.Ty) * env
			if a.has("H"):
				H += a.H * env
			if a.has("L"):
				L[0].x += float(a.L) * env
				L[1].x -= float(a.L) * env * 0.5

	# ---------- stawy dochodzą do celu ----------
	var r := _k(16.0, delta)
	var rf := _k(26.0, delta)   # akcje szybciej
	var ra := rf if not action.is_empty() or _dig_hold > 0.0 else r
	legs[0].rotation = legs[0].rotation.lerp(L[0], r)
	legs[1].rotation = legs[1].rotation.lerp(L[1], r)
	arms[0].rotation = arms[0].rotation.lerp(A[0], ra)
	arms[1].rotation = arms[1].rotation.lerp(A[1], ra)
	torso.rotation = torso.rotation.lerp(T_rot, ra)
	torso.position.y = lerpf(torso.position.y, T_y, r)
	# nogi idą za biodrem (przy kucaniu, pełzaniu i siedzeniu biodro jest niżej)
	legs[0].position.y = minf(torso.position.y, 0.76)
	legs[1].position.y = minf(torso.position.y, 0.76)
	head.rotation = head.rotation.lerp(H, _k(10.0, delta))
	scarf_tail.rotation.x = lerpf(scarf_tail.rotation.x, 0.25 + 0.5 * moving + 0.4 * wa + sin(t * 3.0 + walk_phase) * 0.12, _k(6.0, delta))
	_mod_animation(delta, state)


static func _mixv(a: Array, b: Array, w: float) -> Array:
	return [(a[0] as Vector3).lerp(b[0], w), (a[1] as Vector3).lerp(b[1], w)]


## Kąty akcji w chwili p (0..1): A1 prawa ręka, A0 lewa, T tułów (dodawany), Ty wysokość, H głowa, L wykrok.
func _action_pose(name: String, p: float) -> Dictionary:
	match name:
		"swing":   # użycie, stawianie: szybki ruch prawej ręki w przód
			var k := sin(p * PI)
			return {"A1": Vector3(0.4 + 1.25 * k, 0.15 * k, 0.1), "T": Vector3(-0.08 * k, -0.12 * k, 0)}
		"attack1":   # cięcie poziome z prawej do lewej
			var sweep := _ease((p - 0.2) / 0.5)
			var wind := _ease(p / 0.2)
			return {"A1": Vector3(1.55, lerpf(-1.1 * wind, 1.0, sweep), 0.15), "A0": Vector3(0.6, 0, -0.3),
				"T": Vector3(-0.1, lerpf(-0.45 * wind, 0.55, sweep), 0), "L": 0.25 * sweep}
		"attack2":   # cięcie odwrotne (z lewej do prawej)
			var sweep := _ease((p - 0.2) / 0.5)
			var wind := _ease(p / 0.2)
			return {"A1": Vector3(1.35, lerpf(1.1 * wind, -1.2, sweep), -0.1), "A0": Vector3(0.4, 0, -0.5),
				"T": Vector3(-0.08, lerpf(0.5 * wind, -0.6, sweep), 0), "L": 0.2 * sweep}
		"attack3":   # uderzenie z góry: zamach nad głową, mocne cięcie w dół, wykrok
			var wind := _ease(p / 0.35)
			var hit := _ease((p - 0.35) / 0.2)
			var arm := lerpf(lerpf(0.6, 3.0, wind), 0.55, hit)
			return {"A1": Vector3(arm, 0.1, 0.05), "A0": Vector3(lerpf(lerpf(0.5, 2.6, wind), 0.7, hit), -0.2, -0.1),
				"T": Vector3(lerpf(0.18 * wind, -0.5, hit), 0, 0), "Ty": -0.08 * hit, "H": Vector3(-0.2 * hit, 0, 0), "L": 0.45 * hit}
		"hurt":   # odrzut po trafieniu
			var k := sin(p * PI)
			return {"A0": Vector3(0.7, 0, -0.7), "A1": Vector3(0.7, 0, 0.7), "T": Vector3(0.3 * k, 0, 0.05 * k), "H": Vector3(0.35 * k, 0, 0)}
	return {}


func do_swing() -> void:
	play_action("swing")


# ---------- animacje klatkowe z modów ----------

## Odtwarza animację zarejestrowaną przez mod (engine.animation.register). Pusta nazwa zatrzymuje.
func play(name: String) -> void:
	if name == "":
		if not anim.is_empty():
			anim.explicit = false
			anim.stopping = true
		return
	var def: Variant = Mods.registry.animations.get(name) if Mods.registry else null
	if not def is Dictionary:
		return
	anim = {"name": name, "def": def, "time": 0.0, "weight": 0.0, "loop": bool(def.get("loop", false)),
		"explicit": true, "stopping": false}


func _mod_animation(delta: float, state: String) -> void:
	# animacja jawnie włączona ma pierwszeństwo; inaczej zamiennik stanu ("idle", "walk", "jump")
	if anim.is_empty() or not anim.explicit:
		var ov: Dictionary = overrides if overrides is Dictionary else Mods.anim_overrides
		var want: String = ov.get(state, "")
		if want != "" and (anim.is_empty() or anim.name != want or anim.get("stopping", false)):
			play(want)
			anim.explicit = false
			anim.loop = true
		elif want == "" and not anim.is_empty() and not anim.explicit:
			anim.stopping = true
	if anim.is_empty():
		return
	var def: Dictionary = anim.def
	var length := maxf(0.05, float(def.get("length", 1.0)))
	anim.time += delta * float(def.get("speed", 1.0))
	if anim.time >= length:
		if anim.loop and not anim.stopping:
			anim.time = fmod(anim.time, length)
		else:
			anim.stopping = true
	anim.weight = move_toward(anim.weight, 0.0 if anim.stopping else 1.0, delta / 0.15)
	if anim.stopping and anim.weight <= 0.0:
		anim = {}
		return
	var tracks: Dictionary = def.get("tracks", {}) if def.get("tracks") is Dictionary else {}
	for part_name in tracks:
		var node: Node3D = parts.get(part_name)
		if node == null:
			continue
		var sample := _sample(Registry.arr(tracks[part_name]), minf(anim.time, length))
		if sample.is_empty():
			continue
		var rot: Vector3 = sample.rot * (PI / 180.0)
		node.rotation = node.rotation.lerp(rot, anim.weight)


## Klatki: {czas, {x, y, z}} albo {t = czas, rot = {x, y, z}}; kąty w stopniach, interpolacja liniowa.
static func _key(k: Variant) -> Array:
	if k is Array and k.size() >= 2:
		return [float(k[0]), _vec(k[1])]
	if k is Dictionary:
		return [float(k.get("t", 0.0)), _vec(k.get("rot", [0, 0, 0]))]
	return []


static func _vec(v: Variant) -> Vector3:
	if v is Vector3:
		return v
	if v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	return Vector3.ZERO


static func _sample(keys: Array, time: float) -> Dictionary:
	var prev: Array = []
	for k in keys:
		var e := _key(k)
		if e.is_empty():
			continue
		if e[0] >= time:
			if prev.is_empty():
				return {"rot": e[1]}
			var span: float = maxf(0.0001, e[0] - prev[0])
			return {"rot": (prev[1] as Vector3).lerp(e[1], (time - prev[0]) / span)}
		prev = e
	return {} if prev.is_empty() else {"rot": prev[1]}
