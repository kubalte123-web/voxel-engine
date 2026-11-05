class_name RemotePlayer
extends Node3D
## Inny gracz. U klienta: kukła (model z animacją i podpisem), przesuwana płynnie do pozycji z serwera.
## Na serwerze: także stan gry tego gracza (zdrowie, wybrane miejsce paska, cel, w wodzie), z tym samym
## zestawem funkcji co Player, więc mody i Actions obsługują go tak samo jak gracza lokalnego.

signal health_changed(value: float, max_value: float)

var peer := 0
var account := ""
var world: World
var session: Session
var model: CharacterModel
var label: Label3D
var is_server_side := false

var velocity := Vector3.ZERO
var yaw := 0.0
var pitch := 0.0
var target := {}
var target_liq := {}
var in_liquid := false
var eyes_in_liquid := false
var cam_mode := "third"
var selected := 0
var on_floor := true
var speed := 0.0
var health := 20.0
var mount_id := -1
var mount_seat := 0.0
var pose := "stand"
var sprinting := false
var act_n := 0
var act_name := ""
var _seen_act := -1
var net_pos := Vector3.ZERO
var label_timer := 0.0
var _step := 0.0
var light_timer := 0.0

const SPEED := 4.6
const JUMP := 7.6
const GRAVITY := 24.0
const REACH := 6.0
const MAX_HEALTH := 20.0


func _ready() -> void:
	model = CharacterModel.new()
	add_child(model)
	label = Label3D.new()
	label.text = account
	label.position.y = 2.25
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 40
	label.pixel_size = 0.006
	label.outline_size = 10
	label.no_depth_test = false
	label.modulate = Color(1, 1, 1, 0.0)
	add_child(label)
	net_pos = global_position


func set_account(a: String) -> void:
	account = a
	if label:
		label.text = a


## Nazwa nad głową pojawia się, gdy gracz lokalny na niego patrzy (albo stoi bardzo blisko).
func show_name(visible_now: bool, delta: float) -> void:
	var want := 1.0 if visible_now else 0.0
	label.modulate.a = move_toward(label.modulate.a, want, delta * 4.0)


func apply_state(st: Dictionary) -> void:
	net_pos = st.get("pos", net_pos)
	yaw = float(st.get("yaw", yaw))
	pitch = float(st.get("pitch", pitch))
	velocity = st.get("vel", velocity)
	on_floor = bool(st.get("floor", on_floor))
	pose = str(st.get("pose", pose))
	sprinting = bool(st.get("sprint", false))
	model.digging = bool(st.get("dig", false))
	if st.has("liquid"):
		in_liquid = bool(st.liquid)
	var act: Variant = st.get("act")
	if act is Array and act.size() >= 2:
		var n := int(act[0])
		if _seen_act >= 0 and n > _seen_act and str(act[1]) != "":
			model.play_action(str(act[1]))
		_seen_act = n
		act_n = n
		act_name = str(act[1])
	if not is_server_side:
		mount_id = int(st.get("mount", -1))
		mount_seat = float(st.get("seat", 0.0))
		model.set_held(str(st.get("held", "")))
	if is_server_side:
		target = _target(st.get("target", {}))
		target_liq = _target(st.get("target_liq", {}))
		in_liquid = bool(st.get("liquid", false))
		eyes_in_liquid = bool(st.get("eyes", false))
		cam_mode = str(st.get("cam", "third"))
		global_position = net_pos


static func _target(t: Variant) -> Dictionary:
	if t is Dictionary and t.has("pos"):
		return {"pos": Vector3i(t.pos), "normal": Vector3i(t.normal)}
	return {}


func _process(delta: float) -> void:
	if not is_server_side:
		global_position = global_position.lerp(net_pos, minf(1.0, delta * 12.0))
	speed = Vector2(velocity.x, velocity.z).length()
	if speed > 0.3:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-velocity.x, -velocity.z), minf(1.0, delta * 10.0))
	model.position.y = mount_seat
	model.sitting = mount_id >= 0
	model.pose = pose
	model.sprinting = sprinting
	model.swimming = in_liquid and not on_floor
	model.vertical = velocity.y
	label.position.y = 2.25 + mount_seat
	model.animate(delta, speed, on_floor or in_liquid, pitch)
	# kroki innego gracza słyszymy u siebie (bez wysyłania przez sieć)
	if on_floor and not in_liquid and world:
		_step += speed * delta
		if _step > 1.9:
			_step = 0.0
			Sfx.block_local(world.get_block(Vector3i((global_position - Vector3(0, 0.2, 0)).floor())), "step", global_position)
	light_timer -= delta
	if light_timer <= 0.0 and world:
		light_timer = 0.25
		model.set_light(world.light_at(global_position + Vector3(0, 1.2, 0)))


# ---------- ten sam interfejs co Player (dla modów i Actions na serwerze) ----------

## Celowanie gracza zdalnego: oczy i kierunek z obrotu i pochylenia przysłanych przez klienta.
func aim() -> Array:
	var d := Vector3(-sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))
	return [global_position + Vector3(0, 1.55, 0), d.normalized()]


func stat(name: String) -> Variant:
	return session.player_stats.get(name, Player.default_stat(name)) if session else Player.default_stat(name)


func current_item() -> Dictionary:
	if session == null or session.hotbar.container == "":
		return {}
	return Mods.slot(session.hotbar.container, int(session.hotbar.first) + selected)


func current_block() -> int:
	var it := current_item()
	if it.is_empty():
		return 0
	return maxi(0, Blocks.reg.item_block(str(it.item)))


func target_with_liquids() -> Dictionary:
	return target_liq


func camera_mode() -> String:
	return cam_mode


func reset_fall() -> void:
	pass


func teleport(p: Vector3) -> void:
	global_position = p
	net_pos = p
	Net.s_teleport.rpc_id(peer, p)


func push(v: Vector3) -> void:
	Net.s_session.rpc_id(peer, "push", v)


func set_health(v: float) -> void:
	var mx := float(stat("max_health"))
	health = clampf(v, 0.0, mx)
	health_changed.emit(health, mx)
	Net.s_health.rpc_id(peer, health)


func damage(amount: float, cause: String) -> void:
	if health <= 0.0:
		return
	var ctx := Mods.before("player.damage", {"amount": amount, "cause": cause})
	if ctx.get("cancel", false):
		return
	set_health(health - float(ctx.get("amount", amount)))
	Sfx.emit("player.hurt", global_position)
	Mods.after("player.damage", ctx)
	if health <= 0.0:
		die(cause)


func die(cause: String) -> void:
	Mods.emit_event("player.death", {"cause": cause, "pos": global_position})
	Net.s_died.rpc_id(peer, cause)
	respawn()


func spawn_point() -> Vector3:
	var sp: Variant = stat("spawn")
	if sp is Vector3:
		return sp
	return Vector3(0.5, world.terrain.height(0, 0) + 2.0, 0.5)


func respawn() -> void:
	var ctx := Mods.before("player.respawn", {"pos": spawn_point()})
	teleport(Vector3(ctx.get("pos", spawn_point())))
	set_health(float(stat("max_health")))
	Mods.after("player.respawn", ctx)
