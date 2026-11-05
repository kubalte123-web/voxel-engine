class_name Actions
## Akcje gracza wykonywane na serwerze (albo w grze jednoosobowej): kopanie, stawianie, użycie przedmiotu,
## atak, interakcja ze stworzeniem, podnoszenie i kopanie obiektów luźnych. Ten sam kod obsługuje gracza
## lokalnego (Player) i zdalnego (RemotePlayer), a haki modów działają w imieniu gracza z Mods.ctx.
## Aktor musi mieć: global_position, yaw, selected, model, current_item(), current_block().

static var _rng := RandomNumberGenerator.new()


static func dig_time(actor: Node3D, world: World, pos: Vector3i) -> float:
	var block := world.get_block(pos)
	var hd := Blocks.reg.hardness[block] if block < Blocks.reg.hardness.size() else 1.0
	if hd < 0.0:
		return -1.0
	var t := hd / maxf(0.01, float(actor.stat("break_speed")))
	if Mods.has_hook("before", "block.dig"):
		var ctx := Mods.before("block.dig", {"pos": pos, "block": block, "time": t, "item": str(actor.current_item().get("item", ""))})
		if ctx.get("cancel", false):
			return -1.0
		t = float(ctx.get("time", t))
	return t


## Kopanie przechodzi przez haki modów: „block.break” przed (można anulować, zmienić łup) i po.
static func break_at(actor: Node3D, world: World, pos: Vector3i) -> void:
	var block := world.get_block(pos)
	if block == Blocks.AIR or Blocks.reg.hardness[block] < 0.0:
		return
	var drops := []
	for d in Blocks.reg.drops(block):
		if not d.has("chance") or _rng.randf() < float(d.chance):
			drops.append({"item": str(d.item), "count": int(d.get("count", 1))})
	var ctx := Mods.before("block.break", {"pos": pos, "block": block, "drops": drops,
		"item": str(actor.current_item().get("item", ""))})
	if ctx.get("cancel", false):
		return
	if world.set_block(pos, Blocks.AIR):
		actor.model.do_swing()
		Sfx.block(block, "break", pos)
		Mods.after("block.break", ctx)


## Prawy przycisk na bloku: hak „block.use” (np. stół rzemieślniczy otwiera okno), potem przedmiot:
## blok stawia, inny przedmiot wywołuje „item.use”.
static func use(actor: Node3D, world: World, entities: EntityManager, target: Dictionary) -> void:
	var it: Dictionary = actor.current_item()
	var key := str(it.get("item", ""))
	if not target.is_empty() and Mods.has_hook("before", "block.use"):
		var bctx := Mods.before("block.use", {"pos": target.pos, "normal": target.normal,
			"block": world.get_block(target.pos), "item": key, "slot": actor.selected + 1})
		if bctx.get("cancel", false):
			actor.model.do_swing()
			Mods.after("block.use", bctx)
			return
	if key != "" and Blocks.reg.item_block(key) <= 0:
		var ctx := {"item": key, "slot": actor.selected + 1}
		if not target.is_empty():
			ctx["pos"] = target.pos
			ctx["normal"] = target.normal
			ctx["block"] = world.get_block(target.pos)
		ctx = Mods.before("item.use", ctx)
		if ctx.get("cancel", false):
			return
		actor.model.do_swing()
		Mods.after("item.use", ctx)
		return
	place(actor, world, entities, target)


static func place(actor: Node3D, world: World, entities: EntityManager, target: Dictionary) -> void:
	if target.is_empty() or target.normal == Vector3i.ZERO:
		return
	var p: Vector3i = target.pos + target.normal
	# nie stawiamy bloku tam, gdzie stoi jakiś gracz
	for pl in entities.players():
		var gp: Vector3 = pl.global_position
		var a_min := gp - Vector3(0.3, 0, 0.3)
		var a_max := gp + Vector3(0.3, 1.8, 0.3)
		if a_max.x > p.x and a_min.x < p.x + 1 and a_max.y > p.y and a_min.y < p.y + 1 and a_max.z > p.z and a_min.z < p.z + 1:
			return
	var block: int = actor.current_block()
	if block <= 0:
		return
	block = oriented(block, actor.yaw, target.normal, target.get("point"))
	var ctx := Mods.before("block.place", {"pos": p, "block": block, "slot": actor.selected + 1,
		"item": str(actor.current_item().get("item", ""))})
	if ctx.get("cancel", false):
		return
	var placed := int(ctx.get("block", block))
	# blok luźny nie trafia do siatki świata, tylko staje się obiektem fizycznym
	if Blocks.reg.loose(placed) != null and entities:
		if entities.spawn_prop(placed, Vector3(p) + Vector3(0.5, 0.5, 0.5), Vector3(0, actor.yaw, 0)) >= 0:
			actor.model.do_swing()
			Sfx.block(placed, "place", p)
			Mods.after("block.place", ctx)
		return
	if world.set_block(p, placed):
		actor.model.do_swing()
		Sfx.block(placed, "place", p)
		Mods.after("block.place", ctx)


## Blok ze stanem „facing” stawiamy przodem do gracza (chyba że definicja ma place_facing = false).
## place_facing = "away" (schody): wysoka część z dala od gracza. Stan half: górna połowa, gdy gracz
## klika w spód bloku albo w górną połowę ściany bocznej.
static func oriented(block: int, yaw: float, normal: Vector3i = Vector3i.UP, point: Variant = null) -> int:
	var d := Blocks.reg.def_of(Blocks.reg.base_of(block))
	var states: Variant = d.get("states")
	if not states is Dictionary:
		return block
	var changes := {}
	var pf: Variant = d.get("place_facing", true)
	if states.has("facing") and not (pf is bool and pf == false):
		var v := Vector3(sin(yaw), 0, cos(yaw))   # od bloku w stronę gracza
		if str(pf) == "away":
			v = -v
		changes["facing"] = ("east" if v.x > 0 else "west") if absf(v.x) > absf(v.z) else ("south" if v.z > 0 else "north")
	if states.has("half"):
		var top := normal.y < 0
		if normal.y == 0 and point is Vector3:
			top = fposmod((point as Vector3).y, 1.0) > 0.5
		changes["half"] = "top" if top else "bottom"
	return Blocks.reg.with_state(block, changes) if not changes.is_empty() else block


## stage: etap serii ataków (1, 2, 3); trzecie uderzenie (z góry) jest o połowę mocniejsze.
static func attack(actor: Node3D, node: Node3D, stage := 1) -> void:
	stage = clampi(stage, 1, 3)
	actor.model.play_action("attack%d" % stage)
	if node is Creature:
		var it := str(actor.current_item().get("item", ""))
		var dmg := float(Blocks.reg.items.get(it, {}).get("data", {}).get("damage", 1.0)) if it != "" else 1.0
		node.hit(dmg * (1.5 if stage == 3 else 1.0), actor.global_position, "player")


static func kick(actor: Node3D, node: Node3D, dir: Vector3) -> void:
	actor.model.do_swing()
	if node is Prop:
		node.kick(dir, 6.0)


static func interact(actor: Node3D, entities: EntityManager, node: Node3D) -> void:
	if node is Creature:
		var peer := EntityManager.peer_of(actor)
		if node.rider == peer:   # użycie własnego wierzchowca: zsiadanie
			entities.dismount(peer)
			return
		var ctx := Mods.before("entity.interact", {"id": node.id, "type": node.type,
			"item": str(actor.current_item().get("item", "")), "slot": actor.selected + 1})
		if not ctx.get("cancel", false):
			Mods.after("entity.interact", ctx)
			# stworzenie z polem ride: wsiadanie (opcjonalnie z wymaganym przedmiotem w ręce, ride.item)
			var rd: Variant = node.def.get("ride")
			if rd is Dictionary and node.rider < 0 and not ctx.get("handled", false):
				var need := str(rd.get("item", ""))
				if need == "" or need == str(actor.current_item().get("item", "")) or bool(node.data.get("saddled", false)):
					entities.mount(peer, node.id)
		actor.model.do_swing()
	elif node is Prop:
		if entities.pickup_prop(node):
			actor.model.do_swing()
