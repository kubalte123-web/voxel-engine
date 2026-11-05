-- Uprawy: motyka, siew, wzrost (losowe aktualizacje), wilgotność pola, uprawa znika bez pola (aktualizacja od sąsiada).
local kit = engine.require("modkit")
local backpack = engine.require("backpack")

local function at(p, dy) return { x = p.x, y = p.y + dy, z = p.z } end
local function base_at(p) return engine.blocks.base(engine.world.get_block(p)) end
local function center(p) return { x = p.x + 0.5, y = p.y + 0.5, z = p.z + 0.5 } end
local growth = engine.settings.get("growth") or 1

local function water_near(p)
	for dx = -4, 4 do
		for dz = -4, 4 do
			for dy = 0, 1 do
				local k = engine.blocks.key(engine.world.get_block({ x = p.x + dx, y = p.y + dy, z = p.z + dz }))
				if k:sub(1, 5) == "water" then return true end
			end
		end
	end
	return false
end

engine.hooks.before("item.use", function(ctx)
	if not ctx.pos then return end
	local def = engine.items.def(ctx.item)
	local above = at(ctx.pos, 1)
	local free = engine.world.get_block(above) == 0
	-- motyka: trawa albo ziemia z wolnym miejscem nad nią
	if def and def.hoe then
		local k = base_at(ctx.pos)
		local plant = engine.blocks.base(engine.world.get_block(above))
		if (k == "grass" or k == "dirt") and (free or plant == "tall_grass") then
			if not free then engine.world.set_block(above, 0) end
			engine.world.set_block(ctx.pos, "farmland")
			engine.sound.play("dirt.place", { pos = ctx.pos })
			if water_near(ctx.pos) then engine.blocks.set_state(ctx.pos, { moist = true }) end
		end
		ctx.cancel = true
	-- nasiona: tylko na polu uprawnym
	elseif ctx.item == "seeds" then
		if base_at(ctx.pos) == "farmland" and free then
			engine.world.set_block(above, "wheat_crop")
			engine.sound.play("leaves.place", { pos = above })
			kit.inventory.take(backpack.HOTBAR, ctx.slot, 1)
		end
		ctx.cancel = true
	end
end)

engine.blocks.on_update("wheat_crop", function(ctx)
	local soil = at(ctx.pos, -1)
	if ctx.reason == "neighbor" then
		-- uprawa bez pola pod spodem znika i zostawia nasiona
		if base_at(soil) ~= "farmland" then
			engine.world.set_block(ctx.pos, 0)
			engine.entities.drop("seeds", 1, center(ctx.pos))
		end
	elseif ctx.reason == "random" and ctx.state.age < 3 then
		local moist = engine.blocks.state(soil).moist
		local chance = (moist and 1.0 or 0.35) * growth
		if engine.random() < chance then
			engine.blocks.set_state(ctx.pos, { age = math.min(3, ctx.state.age + (chance > 1 and engine.random() < chance - 1 and 2 or 1)) })
		end
	end
end)

engine.blocks.on_update("farmland", function(ctx)
	if ctx.reason == "random" then
		local wet = water_near(ctx.pos)
		if wet ~= ctx.state.moist then
			engine.blocks.set_state(ctx.pos, { moist = wet })
		elseif not wet and engine.world.get_block(at(ctx.pos, 1)) == 0 and engine.random() < 0.3 then
			engine.world.set_block(ctx.pos, "dirt")   -- suche, puste pole zarasta
		end
	elseif ctx.reason == "neighbor" and ctx.from.y == ctx.pos.y + 1 then
		-- blok postawiony na polu ugniata je z powrotem w ziemię
		local b = engine.world.get_block(ctx.from)
		if b ~= 0 and engine.blocks.base(b) ~= "wheat_crop" and not engine.blocks.key(b):find("water") then
			engine.world.set_block(ctx.pos, "dirt")
		end
	end
end)

-- przepisy, gdy są mody rzemiosła
local classic = engine.optional("crafting_classic")
if classic then
	classic.shaped({ "MM", " S", " S" }, { M = "planks", S = "stick" }, "wooden_hoe")
	classic.shaped({ "MM", " S", " S" }, { M = { "cobblestone", "stone" }, S = "stick" }, "stone_hoe")
	classic.shapeless({ wheat = 1 }, "seeds", 1)
end
local discovery = engine.optional("crafting_discovery")
if discovery then
	discovery.add("motyka_drewniana", { planks = 2, stick = 2, log = 1 }, "wooden_hoe", 1, 3)
	discovery.add("motyka_kamienna", { cobblestone = 2, stick = 2, log = 1 }, "stone_hoe", 1, 4)
end

-- zestaw na start (raz na konto; wyłączany w ustawieniach moda)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("started", false) then return end
	local bp = engine.require("backpack")
	if engine.items.def("wooden_hoe") then bp.give("wooden_hoe", 1) end
	if engine.items.def("seeds") then bp.give("seeds", 8) end
	engine.player.storage.set("started", true)
end)
