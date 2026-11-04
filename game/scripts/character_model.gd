class_name CharacterModel
extends Node3D
## Klockowa postać „Wędrowiec": tunika, szalik, plecak z kocem, skórzana czapka.
## Przód postaci to -Z. Animacje są proceduralne: chód, oddech, skok, machnięcie ręką.

var legs: Array[Node3D] = []
var arms: Array[Node3D] = []
var torso: Node3D
var head: Node3D
var scarf_tail: Node3D

var walk_phase := 0.0
var swing := 0.0  # 1.0 = początek machnięcia ręką (kopanie / stawianie)
var t := 0.0

const SKIN := Color(0.88, 0.68, 0.52)
const TUNIC := Color(0.24, 0.50, 0.46)
const TUNIC_DARK := Color(0.18, 0.40, 0.37)
const TROUSERS := Color(0.55, 0.45, 0.32)
const BOOTS := Color(0.30, 0.20, 0.13)
const LEATHER := Color(0.48, 0.31, 0.18)
const SCARF := Color(0.72, 0.22, 0.20)
const HAIR := Color(0.25, 0.16, 0.10)
const BEDROLL := Color(0.78, 0.70, 0.52)
const GOLD := Color(0.86, 0.68, 0.26)
const EYE := Color(0.12, 0.12, 0.14)


static func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(color)
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
		_box(hip, Vector3(0.22, 0.6, 0.24), Vector3(0, -0.3, 0), TROUSERS)
		_box(hip, Vector3(0.24, 0.18, 0.3), Vector3(0, -0.67, -0.03), BOOTS)
		_box(hip, Vector3(0.25, 0.05, 0.31), Vector3(0, -0.57, -0.03), LEATHER)
		legs.append(hip)

	# tułów
	torso = _pivot(self, Vector3(0, 0.76, 0))
	_box(torso, Vector3(0.5, 0.66, 0.28), Vector3(0, 0.33, 0), TUNIC)
	_box(torso, Vector3(0.52, 0.16, 0.3), Vector3(0, 0.04, 0), TUNIC_DARK)  # dół tuniki
	_box(torso, Vector3(0.53, 0.07, 0.31), Vector3(0, 0.15, 0), LEATHER)    # pas
	_box(torso, Vector3(0.09, 0.08, 0.03), Vector3(0, 0.15, -0.165), GOLD)  # klamra
	_box(torso, Vector3(0.12, 0.1, 0.06), Vector3(0.16, 0.08, -0.17), LEATHER)  # sakiewka
	_box(torso, Vector3(0.05, 0.4, 0.02), Vector3(-0.1, 0.42, -0.145), TUNIC_DARK)  # rozcięcie tuniki
	# plecak z kocem
	_box(torso, Vector3(0.38, 0.42, 0.16), Vector3(0, 0.36, 0.22), LEATHER)
	_box(torso, Vector3(0.3, 0.12, 0.03), Vector3(0, 0.44, 0.31), LEATHER.darkened(0.25))
	_box(torso, Vector3(0.46, 0.13, 0.13), Vector3(0, 0.62, 0.22), BEDROLL)
	_box(torso, Vector3(0.04, 0.14, 0.14), Vector3(-0.12, 0.62, 0.22), LEATHER)
	_box(torso, Vector3(0.04, 0.14, 0.14), Vector3(0.12, 0.62, 0.22), LEATHER)
	# szalik i jego koniec na plecach
	_box(torso, Vector3(0.46, 0.09, 0.32), Vector3(0, 0.66, 0), SCARF)
	scarf_tail = _pivot(torso, Vector3(0.12, 0.64, 0.15))
	_box(scarf_tail, Vector3(0.1, 0.3, 0.04), Vector3(0, -0.15, 0.02), SCARF)

	# ręce (punkt obrotu w barku)
	for side in [-1.0, 1.0]:
		var sh := _pivot(torso, Vector3(0.34 * side, 0.6, 0))
		_box(sh, Vector3(0.17, 0.5, 0.2), Vector3(0, -0.22, 0), TUNIC)
		_box(sh, Vector3(0.18, 0.06, 0.21), Vector3(0, -0.45, 0), TUNIC_DARK)
		_box(sh, Vector3(0.15, 0.13, 0.17), Vector3(0, -0.54, 0), SKIN)
		arms.append(sh)

	# głowa
	head = _pivot(torso, Vector3(0, 0.68, 0))
	_box(head, Vector3(0.4, 0.4, 0.4), Vector3(0, 0.2, 0), SKIN)
	_box(head, Vector3(0.42, 0.1, 0.42), Vector3(0, 0.38, 0), HAIR)        # włosy
	_box(head, Vector3(0.42, 0.24, 0.07), Vector3(0, 0.27, 0.18), HAIR)    # włosy z tyłu
	_box(head, Vector3(0.44, 0.1, 0.44), Vector3(0, 0.44, 0.0), LEATHER)    # czapka
	_box(head, Vector3(0.3, 0.05, 0.12), Vector3(0, 0.4, -0.25), LEATHER)  # daszek
	_box(head, Vector3(0.06, 0.06, 0.02), Vector3(-0.08, 0.2, -0.205), EYE)
	_box(head, Vector3(0.06, 0.06, 0.02), Vector3(0.08, 0.2, -0.205), EYE)
	_box(head, Vector3(0.09, 0.025, 0.02), Vector3(-0.08, 0.26, -0.205), HAIR)
	_box(head, Vector3(0.09, 0.025, 0.02), Vector3(0.08, 0.26, -0.205), HAIR)
	_box(head, Vector3(0.06, 0.06, 0.04), Vector3(0, 0.14, -0.215), SKIN.darkened(0.08))  # nos
	_box(head, Vector3(0.12, 0.025, 0.02), Vector3(0, 0.07, -0.205), Color(0.55, 0.32, 0.28))  # usta


## speed: prędkość pozioma, on_floor: czy stoi, look_pitch: kąt kamery (głowa lekko podąża).
func animate(delta: float, speed: float, on_floor: bool, look_pitch: float) -> void:
	t += delta
	var moving := clampf(speed / 4.5, 0.0, 1.0)
	walk_phase += delta * (4.0 + speed * 1.8) * (1.0 if moving > 0.05 else 0.0)
	var s := sin(walk_phase)
	var leg_amp := 0.75 * moving
	var arm_amp := 0.6 * moving
	if not on_floor:
		legs[0].rotation.x = lerpf(legs[0].rotation.x, -0.5, delta * 8.0)
		legs[1].rotation.x = lerpf(legs[1].rotation.x, 0.35, delta * 8.0)
		arms[0].rotation.x = lerpf(arms[0].rotation.x, -1.0, delta * 8.0)
		arms[1].rotation.x = lerpf(arms[1].rotation.x, -1.0, delta * 8.0)
		arms[0].rotation.z = lerpf(arms[0].rotation.z, -0.35, delta * 8.0)
		arms[1].rotation.z = lerpf(arms[1].rotation.z, 0.35, delta * 8.0)
	else:
		legs[0].rotation.x = lerpf(legs[0].rotation.x, s * leg_amp, delta * 14.0)
		legs[1].rotation.x = lerpf(legs[1].rotation.x, -s * leg_amp, delta * 14.0)
		var idle := sin(t * 1.8) * 0.04 * (1.0 - moving)
		arms[0].rotation.x = lerpf(arms[0].rotation.x, -s * arm_amp + idle, delta * 14.0)
		arms[1].rotation.x = lerpf(arms[1].rotation.x, s * arm_amp - idle, delta * 14.0)
		arms[0].rotation.z = lerpf(arms[0].rotation.z, -0.06, delta * 10.0)
		arms[1].rotation.z = lerpf(arms[1].rotation.z, 0.06, delta * 10.0)
	# machnięcie prawą ręką przy kopaniu i stawianiu
	if swing > 0.0:
		swing = maxf(0.0, swing - delta * 4.0)
		var k := sin(swing * PI)
		arms[1].rotation.x = -1.6 * k - 0.2
	# kołysanie tułowia przy chodzie i oddech w miejscu
	var bob := absf(s) * 0.05 * moving
	torso.position.y = 0.76 + bob + sin(t * 1.8) * 0.006 * (1.0 - moving)
	torso.rotation.y = s * 0.08 * moving
	torso.rotation.x = 0.06 * moving
	head.rotation.x = clampf(-look_pitch * 0.4, -0.35, 0.35)
	head.rotation.y = -s * 0.06 * moving
	scarf_tail.rotation.x = 0.25 + 0.4 * moving + sin(t * 3.0 + walk_phase) * 0.12


func do_swing() -> void:
	swing = 1.0
