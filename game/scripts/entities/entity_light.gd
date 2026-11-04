class_name EntityLight
## Oświetlenie obiektów poza siatką świata (postać, stworzenia, przedmioty) światłem z mapy światła:
## te same krzywe co shader terenu, więc w ciemnej jaskini stworzenie też jest ciemne, a przy pochodni
## ciepło oświetlone.

const TORCH := Color(1.0, 0.78, 0.5)


static func min_light() -> float:
	return 0.01 + 0.1 * Settings.brightness


## Mnożnik koloru (światło nieba) i siła świecenia (światło bloków) dla wartości Vector2(niebo, bloki).
static func factors(l: Vector2) -> Vector2:
	var blk := pow(0.86, (1.0 - l.y) * 15.0) * 2.0 if l.y > 0.01 else 0.0
	return Vector2(maxf(World.light_curve(l.x) if l.x > 0.01 else 0.0, min_light()), blk)


## Ustawia materiały: kolor bazowy (meta "base") razy światło nieba, świecenie od pochodni.
static func apply(mats: Array, l: Vector2, extra: Color = Color(0, 0, 0)) -> void:
	var f := factors(l)
	for m in mats:
		var sm := m as StandardMaterial3D
		if sm == null:
			continue
		if not sm.has_meta("base"):
			sm.set_meta("base", sm.albedo_color)
		var base: Color = sm.get_meta("base")
		sm.albedo_color = Color(base.r * f.x, base.g * f.x, base.b * f.x, base.a)
		var e := Color(base.r * TORCH.r * f.y, base.g * TORCH.g * f.y, base.b * TORCH.b * f.y) + extra
		sm.emission_enabled = e.r + e.g + e.b > 0.003
		sm.emission = e
		sm.emission_energy_multiplier = 1.0
