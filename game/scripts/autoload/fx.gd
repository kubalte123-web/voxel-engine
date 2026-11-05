extends Node
## Cząsteczki z modów. Mod opisuje efekt danymi w content.lua (engine.particles.register), a gra
## odtwarza go jako jednorazowy wybuch (engine.particles.spawn) albo ciągły emiter przypięty do modelu bloku.
## Serwer wysyła wybuchy graczom w pobliżu; emitery modeli działają u każdego gracza samodzielnie.
##
## Opis efektu: amount (sztuk w wybuchu albo na sekundę w emiterze), life (sekundy), speed (liczba albo
## {min, max}), direction ({x, y, z}), spread (stopnie), gravity (w dół; ujemna unosi), size (liczba albo
## {start, koniec}), color (kolor albo lista kolorów od początku do końca życia), box ({x, y, z} – pół-wymiary
## obszaru narodzin), shape ("round", "square", "spark"), glow (świeci, dodaje się do tła), damping.

const RANGE := 48.0

var _tex := {}       # kształt -> tekstura
var _mats := {}      # klucz -> materiał


func _reg() -> Registry:
	return Mods.registry


func has(name: String) -> bool:
	var r := _reg()
	return r != null and r.particles.has(name)


static func _v(v: Variant, fb: Vector3) -> Vector3:
	if v is Vector3:
		return v
	if v is Dictionary:
		return Vector3(float(v.get("x", fb.x)), float(v.get("y", fb.y)), float(v.get("z", fb.z)))
	var a := Registry.arr(v)
	if a.size() >= 3:
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return fb


static func _range(v: Variant, fb: float) -> Vector2:
	var a := Registry.arr(v)
	if a.size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	if v is float or v is int:
		return Vector2(float(v), float(v))
	return Vector2(fb, fb)


func _texture(shape: String) -> Texture2D:
	if _tex.has(shape):
		return _tex[shape]
	var n := 16
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var dx := (x + 0.5 - n / 2.0) / (n / 2.0)
			var dy := (y + 0.5 - n / 2.0) / (n / 2.0)
			var a := 1.0
			match shape:
				"round":
					a = clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
					a = a * a * (3.0 - 2.0 * a)
				"spark":
					a = clampf(1.0 - (absf(dx) * 4.0 + absf(dy)) * 0.7, 0.0, 1.0) + clampf(1.0 - (absf(dy) * 4.0 + absf(dx)) * 0.7, 0.0, 1.0)
					a = clampf(a, 0.0, 1.0)
				_:
					a = 1.0 if absf(dx) < 0.8 and absf(dy) < 0.8 else 0.0
			img.set_pixel(x, y, Color(1, 1, 1, a))
	var t := ImageTexture.create_from_image(img)
	_tex[shape] = t
	return t


func _material(shape: String, glow: bool) -> StandardMaterial3D:
	var key := shape + ("|glow" if glow else "")
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true   # bez tego cząsteczki tracą rozmiar (zawsze 1 m)
	m.albedo_texture = _texture(shape)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	if glow:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.no_depth_test = false
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


## Węzeł cząsteczek z opisu. opts: color (zastępuje kolory), amount (mnożnik).
func build(name: String, opts: Dictionary = {}, burst := true) -> CPUParticles3D:
	var r := _reg()
	var d: Dictionary = r.particles.get(name, {}) if r else {}
	if d.is_empty():
		return null
	var p := CPUParticles3D.new()
	var life := maxf(0.05, float(d.get("life", 1.0)))
	var amount := float(d.get("amount", 12)) * float(opts.get("amount", 1.0))
	p.lifetime = life
	p.amount = maxi(1, int(round(amount if burst else amount * life)))
	p.one_shot = burst
	p.explosiveness = clampf(float(d.get("explosiveness", 0.95 if burst else 0.0)), 0.0, 1.0)
	p.randomness = 0.5
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	p.mesh = quad
	p.material_override = _material(str(d.get("shape", "round")), bool(d.get("glow", false)))
	p.direction = _v(d.get("direction"), Vector3.UP)
	p.spread = float(d.get("spread", 20.0))
	var sp := _range(d.get("speed"), 1.0)
	p.initial_velocity_min = sp.x
	p.initial_velocity_max = sp.y
	p.gravity = Vector3(0, -float(d.get("gravity", 9.8)), 0)
	p.damping_min = float(d.get("damping", 0.0))
	p.damping_max = float(d.get("damping", 0.0))
	var box := _v(d.get("box"), Vector3.ZERO)
	if box != Vector3.ZERO:
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = box
	var size := _range(d.get("size"), 0.1)
	p.scale_amount_min = size.x
	p.scale_amount_max = size.x
	if not is_equal_approx(size.x, size.y) and size.x > 0.0:
		var curve := Curve.new()
		curve.max_value = maxf(1.0, size.y / size.x)
		curve.add_point(Vector2(0, 1))
		curve.add_point(Vector2(1, size.y / size.x))
		p.scale_amount_curve = curve
	var cols: Array = []
	var src: Variant = opts.get("color", d.get("color", "#ffffff"))
	for c in (src if src is Array else [src]):
		cols.append(TexGen._col(c, Color.WHITE))
	if bool(d.get("fade", true)) and cols.size() >= 1:
		var last: Color = cols[cols.size() - 1]
		if last.a > 0.0:
			cols.append(Color(last.r, last.g, last.b, 0.0))
	if cols.size() == 1:
		cols.append(cols[0])
	var offs := PackedFloat32Array()
	for i in cols.size():
		offs.append(float(i) / float(cols.size() - 1))
	var g := Gradient.new()
	g.offsets = offs
	g.colors = PackedColorArray(cols)
	p.color_ramp = g
	return p


## Jednorazowy wybuch u siebie.
func burst_local(name: String, pos: Vector3, opts: Dictionary = {}) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var parent: Node = Net.main.world if Net.main and Net.main.get("world") else get_tree().current_scene
	if parent == null:
		return
	var p := build(name, opts, true)
	if p == null:
		return
	parent.add_child(p)
	p.global_position = pos
	p.emitting = true
	get_tree().create_timer(p.lifetime + 0.6).timeout.connect(p.queue_free)


## Serwer: wybuch widziany przez graczy w pobliżu (i u siebie, jeśli gra ma okno).
func emit(name: String, pos: Vector3, opts: Dictionary = {}) -> void:
	if not has(name):
		return
	if not Net.online():
		burst_local(name, pos, opts)
		return
	for p in Mods.sessions:
		var s: Session = Mods.sessions[p]
		if not s.logged_in or (s.node and s.node.global_position.distance_to(pos) > RANGE):
			continue
		if s.local:
			if Net.mode != "dedicated":
				burst_local(name, pos, opts)
		else:
			Net.s_particles.rpc_id(p, name, pos, opts)
