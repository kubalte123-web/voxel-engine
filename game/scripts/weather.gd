class_name Weather
extends Node3D
## Pogoda i niebo z modów. Serwer ustawia stan (engine.weather.set, engine.sky.set) i wysyła go graczom;
## każdy gracz rysuje opady wokół siebie: deszcz, a w zimnych biomach śnieg (na pustyni nic). Pod dachem
## opadów nie widać. Pogoda przyciemnia niebo, słońce i zagęszcza mgłę; mod może też nadpisać kolory nieba.

var main: Node
var kind := "clear"        # clear | rain | snow | storm
var target := 0.0          # docelowa siła 0..1
var intensity := 0.0       # bieżąca (płynne przejście)
var sky := {}              # nadpisania nieba: top, horizon, fog, sun, ambient (z engine.sky.set)
var rain: CPUParticles3D
var snow: CPUParticles3D
var _cover := 1.0          # 0 pod dachem .. 1 pod gołym niebem
var _t := 0.0

const SNOW_BIOMES := ["snowy", "tundra", "mountains", "taiga"]
const DRY_BIOMES := ["desert", "badlands", "savanna"]


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	rain = _make(true)
	snow = _make(false)


func _make(is_rain: bool) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.amount = 900 if is_rain else 600
	p.lifetime = 1.1 if is_rain else 4.5
	p.preprocess = p.lifetime
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(16, 1, 16)
	p.direction = Vector3(0.08, -1, 0.04)
	p.spread = 2.0 if is_rain else 18.0
	p.gravity = Vector3(0, -6 if is_rain else -0.6, 0)
	p.initial_velocity_min = 16.0 if is_rain else 1.0
	p.initial_velocity_max = 20.0 if is_rain else 2.0
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var q := QuadMesh.new()
	q.size = Vector2(0.03, 0.7) if is_rain else Vector2(0.09, 0.09)
	p.mesh = q
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.78, 0.9, 0.45) if is_rain else Color(1, 1, 1, 0.9)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y if is_rain else BaseMaterial3D.BILLBOARD_ENABLED
	m.billboard_keep_scale = true
	p.material_override = m
	p.emitting = false
	add_child(p)
	return p


## Serwer albo stan od serwera: rodzaj, siła, nadpisania nieba.
func set_state(st: Dictionary) -> void:
	kind = str(st.get("kind", kind))
	target = clampf(float(st.get("intensity", 1.0 if kind != "clear" else 0.0)), 0.0, 1.0)
	if kind == "clear":
		target = 0.0
	if st.has("sky"):
		sky = st.sky if st.sky is Dictionary else {}
	if st.has("instant"):
		intensity = target


func state() -> Dictionary:
	return {"kind": kind, "intensity": target, "sky": sky}


func _process(delta: float) -> void:
	intensity = move_toward(intensity, target, delta / 6.0)
	if rain == null or main == null or main.player == null:
		return
	var pp: Vector3 = main.player.global_position
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		var head := pp + Vector3(0, 2.0, 0)
		_cover = clampf((main.world.light_at(head).x - 0.75) * 4.0, 0.0, 1.0)
	var biome := ""
	var t: Terrain = main.world.terrain
	var i: int = t.column(floori(pp.x), floori(pp.z)).y
	if i < t.biome_keys.size():
		biome = t.biome_keys[i]
	var snowy := kind == "snow" or SNOW_BIOMES.has(biome)
	var dry := DRY_BIOMES.has(biome) and kind != "snow"
	var show := intensity * _cover * (0.0 if dry else 1.0)
	var on: CPUParticles3D = snow if snowy else rain
	var off: CPUParticles3D = rain if snowy else snow
	off.emitting = false
	on.emitting = show > 0.03
	# ilość kropli w czterech poziomach (zmiana ilości uruchamia emiter od nowa, więc nie co klatkę)
	var level := clampi(ceili(clampf(show * (1.4 if kind == "storm" else 1.0), 0.0, 1.0) * 4.0), 1, 4)
	if int(on.get_meta("level", 0)) != level:
		on.set_meta("level", level)
		on.amount = int(on.get_meta("base", on.amount)) * level / 4
	if not on.has_meta("base"):
		on.set_meta("base", 900 if on == rain else 600)
	on.global_position = pp + Vector3(0, 14 if on == rain else 10, 0)


## Kolory nieba po pogodzie i nadpisaniach modów (wołane z main._update_sky).
func apply_sky(top: Color, hor: Color, sun_energy: float, ambient: float) -> Array:
	var gray := intensity * (0.75 if kind == "storm" else 0.55)
	top = top.lerp(Color(0.42, 0.45, 0.5) * (top.v + 0.1), gray)
	hor = hor.lerp(Color(0.55, 0.57, 0.6) * (hor.v + 0.1), gray)
	sun_energy *= 1.0 - gray
	if sky.has("top"):
		top = TexGen._col(sky.top, top)
	if sky.has("horizon"):
		hor = TexGen._col(sky.horizon, hor)
	if sky.has("sun"):
		sun_energy *= float(sky.sun)
	if sky.has("ambient"):
		ambient *= float(sky.ambient)
	return [top, hor, sun_energy, ambient]


func fog_mul() -> float:
	return (1.0 + intensity * (3.0 if kind == "storm" else 1.8)) * float(sky.get("fog", 1.0))
