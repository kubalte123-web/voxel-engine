-- Oswajanie: jabłko albo pszenica w ręce, każda próba ma szansę. Dziki koń nie daje na siebie wsiąść.
local kit = engine.require("modkit")
local FOOD = { apple = 0.35, wheat = 0.2 }

local function horse(t) return t == "horse" or t == "horse_white" end

local function tame(id)
	engine.entities.set_data(id, "tame", true)
	engine.entities.show(id, "saddle", true)
	engine.entities.set_state(id, "idle", 3)
end

engine.on("entity.spawn", function(e)
	-- siodło widać tylko u oswojonych
	if horse(e.type) and not engine.entities.data(e.id).tame then engine.entities.show(e.id, "saddle", false) end
end)

engine.hooks.before("entity.interact", function(ctx)
	if not horse(ctx.type) then return end
	local d = engine.entities.data(ctx.id)
	if d.tame then return end   -- oswojony: silnik sam posadzi gracza (pole ride)
	ctx.cancel = true
	local chance = FOOD[ctx.item]
	if chance then
		kit.inventory.take("hotbar", ctx.slot, 1)
		engine.particles.spawn("horses.heart", engine.entities.position(ctx.id) + Vector3(0, 1.8, 0))
		if engine.random() < chance then
			tame(ctx.id)
			engine.ui.notify(engine.t("tamed"))
		else
			engine.entities.look_at(ctx.id, engine.player.position())
		end
	else
		engine.ui.notify(engine.t("wild"))
		engine.entities.set_state(ctx.id, "flee", 2)
	end
end)

engine.on("entity.mount", function(e)
	if horse(e.type) then engine.ui.notify(engine.t("dismount")) end
end)

-- oswojony koń na start (raz na konto)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("horse_given", false) then return end
	engine.player.storage.set("horse_given", true)
	local p = engine.player.position()
	local id = engine.entities.spawn("horse", p + Vector3(2.5, 0.5, 0))
	if id and id > 0 then tame(id) end
end)

-- polecenie: oswojony koń obok gracza (moderator i administrator)
engine.commands.register("kon", {
	description = engine.t("cmd"), usage = "/kon [siwy]", permission = "moderator",
	fn = function(ctx)
		local kind = ctx.args[1] == "siwy" and "horse_white" or "horse"
		local id = engine.entities.spawn(kind, engine.player.position() + Vector3(2, 0.5, 0))
		if not id or id < 0 then return "Nie udało się" end
		tame(id)
		engine.chat.send(engine.t("summoned", { name = ctx.name }), { color = "#c8a070" })
		return engine.t("waiting")
	end,
})
