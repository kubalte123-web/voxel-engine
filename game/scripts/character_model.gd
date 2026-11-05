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


## speed: prędkość pozioma, on_floor: czy stoi, look_pitch: kąt kamery (głowa lekko podąża).
func animate(delta: float, speed: float, on_floor: bool, look_pitch: float) -> void:
	t += delta
	var state := "jump" if not on_floor else ("walk" if speed > 0.3 else "idle")
	var moving := clampf(speed / 4.5, 0.0, 1.0)
	walk_phase += delta * (4.0 + speed * 1.8) * (1.0 if moving > 0.05 else 0.0)
	var s := sin(walk_phase)
	var leg_amp := 0.75 * moving
	var arm_amp := 0.6 * moving
	if sitting:
		state = "sit"
		moving = 0.0
		legs[0].rotation.x = lerpf(legs[0].rotation.x, -1.35, delta * 10.0)
		legs[1].rotation.x = lerpf(legs[1].rotation.x, -1.35, delta * 10.0)
		legs[0].rotation.z = lerpf(legs[0].rotation.z, 0.25, delta * 10.0)
		legs[1].rotation.z = lerpf(legs[1].rotation.z, -0.25, delta * 10.0)
		arms[0].rotation.x = lerpf(arms[0].rotation.x, -0.6, delta * 8.0)
		arms[1].rotation.x = lerpf(arms[1].rotation.x, -0.6, delta * 8.0)
	elif not on_floor:
		legs[0].rotation.x = lerpf(legs[0].rotation.x, -0.5, delta * 8.0)
		legs[1].rotation.x = lerpf(legs[1].rotation.x, 0.35, delta * 8.0)
		arms[0].rotation.x = lerpf(arms[0].rotation.x, -1.0, delta * 8.0)
		arms[1].rotation.x = lerpf(arms[1].rotation.x, -1.0, delta * 8.0)
		arms[0].rotation.z = lerpf(arms[0].rotation.z, -0.35, delta * 8.0)
		arms[1].rotation.z = lerpf(arms[1].rotation.z, 0.35, delta * 8.0)
	else:
		legs[0].rotation.z = lerpf(legs[0].rotation.z, 0.0, delta * 10.0)
		legs[1].rotation.z = lerpf(legs[1].rotation.z, 0.0, delta * 10.0)
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
	_mod_animation(delta, state)


func do_swing() -> void:
	swing = 1.0


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
