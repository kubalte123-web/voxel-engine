class_name LiquidSim
extends Node
## Symulacja cieczy z zachowaniem objętości.
## Każdy blok płynącej cieczy ma poziom 1..8. Woda spada w dół, a potem wyrównuje poziom z sąsiadami
## (oddaje po jednej jednostce sąsiadom niższym co najmniej o 2), więc wylana woda rozlewa się w płaską
## kałużę o tej samej objętości, zamiast mnożyć się jak w Minecrafcie. Płytka kałuża (poziom 2) nie
## rozpływa się dalej po suchym terenie (napięcie powierzchniowe), a cienkie warstwy (poziom 1) powoli wysychają. Bloki źródłowe (morza i jeziora z generatora) są dużymi zbiornikami:
## oddają wodę, nie tracąc jej, więc wykopanie dołu przy jeziorze napełnia go, a jezioro nie znika.
## Symulowane są tylko komórki „aktywne” (zmienione niedawno lub obok zmiany), z limitem na krok.

const TICK := 0.15
const BUDGET := 900
const DIRS := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
const ALL := [Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 1, 0), Vector3i(0, -1, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]

var world: World
var active := {}
var timer := 0.0
var step := 0
var moved_total := 0
var rng := RandomNumberGenerator.new()


func activate(p: Vector3i) -> void:
	active[p] = true


func activate_around(p: Vector3i) -> void:
	if world.reg.is_liquid(world.get_block(p)):
		active[p] = true
	for d in ALL:
		var q: Vector3i = p + d
		if world.reg.is_liquid(world.get_block(q)):
			active[q] = true


func _process(delta: float) -> void:
	timer += delta
	if timer < TICK:
		return
	timer = minf(timer - TICK, TICK)
	tick()


func tick() -> void:
	step += 1
	if active.is_empty():
		return
	var cells: Array = active.keys()
	active.clear()
	# od dołu do góry: woda spada płynnie, zanim zacznie się rozlewać
	cells.sort_custom(func(a: Vector3i, b: Vector3i) -> bool: return a.y < b.y)
	var n := 0
	for p in cells:
		if n >= BUDGET:
			active[p] = true
			continue
		n += 1
		_update(p)
	world.flush_pending()


func _passable(id: int) -> bool:
	if id == Blocks.AIR:
		return true
	var pr := Blocks.props(id)
	return (pr & Blocks.CROSS) != 0 and (pr & Blocks.SOLID) == 0


func _put_level(q: Vector3i, kind: int, level: int) -> void:
	var id := Blocks.AIR if level <= 0 else int(world.reg.liquid_kinds[kind].levels[mini(level, Registry.LEVELS)])
	if world.get_block(q) == id:
		return
	if world.set_block_quiet(q, id):
		moved_total += 1
		active[q] = true
		for d in ALL:
			active[q + d] = true


func _update(p: Vector3i) -> void:
	var reg := world.reg
	var b := world.get_block(p)
	if not reg.is_liquid(b) or not world.is_loaded(p):
		return
	var kind := reg.liquid_kind(b)
	var info: Dictionary = reg.liquid_kinds[kind]
	var visc := int(info.viscosity)
	if visc > 1 and step % visc != 0:
		active[p] = true  # gęsta ciecz (np. lawa) płynie rzadziej
		return
	var src := reg.is_source(b)
	var lv := reg.liquid_level(b)
	# 1. w dół
	var dp := p + Vector3i(0, -1, 0)
	if world.is_loaded(dp):
		var db := world.get_block(dp)
		if _passable(db):
			_put_level(dp, kind, lv)
			if not src:
				_put_level(p, kind, 0)
			return
		if reg.liquid_kind(db) == kind and not reg.is_source(db):
			var dl := reg.liquid_level(db)
			if dl < Registry.LEVELS:
				var t := Registry.LEVELS - dl if src else mini(lv, Registry.LEVELS - dl)
				_put_level(dp, kind, dl + t)
				if not src:
					lv -= t
					_put_level(p, kind, lv)
					if lv <= 0:
						return
	# 2. na boki: źródło napełnia sąsiadów do poziomu 7, płynąca ciecz wyrównuje poziom
	var order := DIRS.duplicate()
	var k0 := step % 4
	var cands := []
	for i in 4:
		var q: Vector3i = p + order[(i + k0) % 4]
		if not world.is_loaded(q):
			continue
		var qb := world.get_block(q)
		var ql := -1
		if _passable(qb):
			ql = 0
		elif reg.liquid_kind(qb) == kind and not reg.is_source(qb):
			ql = reg.liquid_level(qb)
		if ql < 0:
			continue
		if src:
			if ql < Registry.LEVELS - 1:
				_put_level(q, kind, Registry.LEVELS - 1)
		elif lv - ql >= 2 and (lv >= 3 or ql > 0):
			# napięcie powierzchniowe: płytka kałuża (poziom 2) nie rozlewa się dalej na suchy teren
			cands.append([q, ql])
	if src:
		return
	if cands.is_empty():
		# cienka warstwa bez odpływu powoli wysycha
		if lv == 1 and reg.liquid_kind(world.get_block(p + Vector3i(0, 1, 0))) != kind:
			if rng.randf() < 0.03:
				_put_level(p, kind, 0)
			elif rng.randf() < 0.85:
				active[p] = true
		return
	cands.sort_custom(func(a: Array, c: Array) -> bool: return a[1] < c[1])
	for c in cands:
		if lv - int(c[1]) >= 2:
			_put_level(c[0], kind, int(c[1]) + 1)
			lv -= 1
	_put_level(p, kind, lv)


## Kierunek prądu w punkcie (do spychania gracza, stworzeń i przedmiotów): w stronę niższego poziomu.
func flow_at(p: Vector3i) -> Vector3:
	var reg := world.reg
	var b := world.get_block(p)
	if not reg.is_liquid(b):
		return Vector3.ZERO
	var kind := reg.liquid_kind(b)
	var lv := reg.liquid_level(b)
	var f := Vector3.ZERO
	for d in DIRS:
		var qb := world.get_block(p + d)
		var ql := -1
		if _passable(qb):
			ql = 0
		elif reg.liquid_kind(qb) == kind:
			ql = reg.liquid_level(qb)
		if ql >= 0 and ql < lv:
			f += Vector3(d) * float(lv - ql)
	if _passable(world.get_block(p + Vector3i(0, -1, 0))):
		f.y -= 2.0
	return f.normalized() * float(reg.liquid_kinds[kind].push) if f.length() > 0.0 else Vector3.ZERO
