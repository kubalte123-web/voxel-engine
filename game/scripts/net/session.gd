class_name Session
extends RefCounted
## Stan jednego gracza po stronie modów: konto, postać (Player albo RemotePlayer), nadpisania statystyk
## i kamery, pasek szybkiego dostępu, otwarte okna, paski na ekranie i przedmiot trzymany kursorem.
## Dla gracza lokalnego słowniki są tymi samymi obiektami co Mods.player_stats itd. (interfejs czyta je wprost).
## Dla graczy zdalnych zmiany trafiają do `dirty` i Net wysyła je do ich klientów.

var peer := 1
var name := "Gracz"
var account := "Gracz"
var node: Node3D = null
var local := false
var logged_in := false

var player_stats := {}
var camera_stats := {}
var anim_overrides := {}
var model_colors := {}
var hud := {}
var hotbar := {"container": "", "first": 0, "count": 0}
var windows := {}
var held := {}
var dirty := {}   # "stats", "camera", "hud", "hotbar", "held", "look" -> true


func mark(what: String) -> void:
	if not local:
		dirty[what] = true
