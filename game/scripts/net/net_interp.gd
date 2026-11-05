class_name NetInterp
extends RefCounted
## Bufor interpolacji stanów z sieci (inni gracze, stworzenia, przedmioty, rzeczy).
## Każdy stan ma znacznik czasu nadawcy. Pokazujemy obiekt DELAY sekund „w przeszłości”,
## płynnie między dwoma stanami; gdy kolejny stan się spóźnia, krótko przewidujemy ruch z prędkości.

const DELAY := 0.1          # o ile pokazujemy obiekt w przeszłości (1,5 odstępu między stanami przy 15/s)
const MAX_EXTRAP := 0.25    # najdłuższe przewidywanie ruchu, gdy stany nie przychodzą
const SNAP_DIST := 8.0      # większy skok między stanami = teleport, bez przesuwania przez świat
const MAX_STATES := 32

static var disabled := OS.get_cmdline_user_args().has("--no-interp")   # do porównań: stary sposób (dochodzenie do ostatniej pozycji)
var delay := DELAY         # obiekty wysyłane rzadziej (stworzenia co 0,1 s) dostają większe opóźnienie
var buf: Array = []         # [czas nadawcy, pozycja, obrót (Vector3), prędkość albo null]
var offset := 0.0           # czas lokalny - czas nadawcy (z opóźnieniem sieci)
var _has_offset := false


func _init(p_delay := DELAY) -> void:
	delay = p_delay


static func now() -> float:
	return Time.get_ticks_usec() / 1000000.0


func push(t: float, pos: Vector3, rot: Vector3, vel: Variant = null) -> void:
	var o := now() - t
	if not _has_offset:
		offset = o
		_has_offset = true
	elif o < offset:
		offset = o                          # stan doszedł szybciej: przesuwamy od razu
	else:
		offset = lerpf(offset, o, 0.02)     # opóźnienie urosło: dochodzimy powoli (bez szarpnięć)
	if not buf.is_empty():
		var last: Array = buf[-1]
		if t <= float(last[0]):
			return                          # stary albo zdublowany stan
		if (last[1] as Vector3).distance_to(pos) > SNAP_DIST:
			buf.clear()
	buf.append([t, pos, rot, vel])
	while buf.size() > MAX_STATES:
		buf.pop_front()


## Od razu w nowym miejscu (np. teleport ustawiony lokalnie).
func reset() -> void:
	buf.clear()


func is_empty() -> bool:
	return buf.is_empty()


## [pozycja, obrót, prędkość] na teraz, albo [] gdy nie ma jeszcze żadnego stanu.
func sample() -> Array:
	if buf.is_empty() or disabled:
		return []
	var rt := now() - offset - delay
	while buf.size() > 2 and float(buf[1][0]) <= rt:
		buf.pop_front()
	var a: Array = buf[0]
	if buf.size() == 1 or rt <= float(a[0]):
		return [a[1], a[2], a[3] if a[3] != null else Vector3.ZERO]
	var b: Array = buf[1]
	var span := maxf(0.0001, float(b[0]) - float(a[0]))
	var seg_vel := ((b[1] as Vector3) - (a[1] as Vector3)) / span
	var k := (rt - float(a[0])) / span
	if k <= 1.0:
		var vel: Vector3 = (a[3] as Vector3).lerp(b[3], k) if a[3] != null and b[3] != null else seg_vel
		return [(a[1] as Vector3).lerp(b[1], k), _lerp_rot(a[2], b[2], k), vel]
	# stany się spóźniają: krótko dalej z ostatnią prędkością
	var v: Vector3 = b[3] if b[3] != null else seg_vel
	var dt := minf(rt - float(b[0]), MAX_EXTRAP)
	return [(b[1] as Vector3) + v * dt, b[2], v if rt - float(b[0]) < MAX_EXTRAP else Vector3.ZERO]


static func _lerp_rot(a: Vector3, b: Vector3, k: float) -> Vector3:
	return Vector3(lerp_angle(a.x, b.x, k), lerp_angle(a.y, b.y, k), lerp_angle(a.z, b.z, k))
