-- Przetrwanie: zdrowie, głód i powietrze każdego gracza, obrażenia od upadku i topienie, jedzenie.
local backpack = engine.require("backpack")
local kit = engine.require("modkit")

local MAX_FOOD = 20
local MAX_AIR = 10
local mult = ({ ["Łagodny"] = 0.5, ["Normalny"] = 1.0, ["Trudny"] = 1.6 })[engine.settings.get("difficulty")] or 1.0
local per_second = MAX_FOOD / (engine.settings.get("hunger_minutes") * 60)

-- stan bieżącego gracza (engine.player.storage zapisuje go osobno dla każdego konta)
local function food() return engine.player.storage.get("food", MAX_FOOD) end
local air = {}  -- id gracza -> powietrze (nie zapisujemy)

local function show()
	engine.ui.bar({ id = "health", label = "Zdrowie", value = engine.player.health(), max = engine.player.max_health(), color = "#d83a3a" })
	if engine.settings.get("hunger") then
		engine.ui.bar({ id = "hunger", label = "Głód", value = food(), max = MAX_FOOD, color = "#d89a3a" })
	end
end

local function set_food(v)
	engine.player.storage.set("food", math.max(0, math.min(MAX_FOOD, v)))
	show()
end

engine.on("player.join", show)
engine.hooks.after("player.damage", show)
engine.hooks.after("player.respawn", function() set_food(MAX_FOOD) end)

-- Upadek z wysokości ponad 3,5 bloku boli: 2 punkty za każdy blok powyżej 3.
engine.on("player.land", function(e)
	if engine.settings.get("fall_damage") and e.fall > 3.5 then
		engine.player.damage(math.floor((e.fall - 3) * 2 * mult), "fall")
	end
end)

engine.on("player.death", function(e)
	local why = ({ fall = "upadek", hunger = "głód", void = "upadek w pustkę", drown = "utonięcie" })[e.cause] or e.cause
	engine.ui.notify("Przyczyna: " .. why)
end)

-- Co sekundę dla każdego gracza: głód, leczenie najedzonego, powietrze pod wodą.
local acc = {}
kit.every(1.0, function()
	engine.players.each(function(p)
		if engine.settings.get("hunger") then
			acc[p.id] = (acc[p.id] or 0) + per_second * mult
			if acc[p.id] >= 0.5 then
				set_food(food() - acc[p.id])
				acc[p.id] = 0
			end
			if food() <= 0 then engine.player.damage(1, "hunger") end
		end
		if food() >= MAX_FOOD * 0.8 and engine.player.health() < engine.player.max_health() then
			engine.player.heal(0.5)
			show()
		end
		local a = air[p.id] or MAX_AIR
		if engine.player.eyes_in_liquid() then
			a = a - 1
			if a <= 0 then
				a = 0
				engine.player.damage(math.ceil(2 * mult), "drown")
			end
		else
			a = math.min(MAX_AIR, a + 3)
		end
		air[p.id] = a
		if a < MAX_AIR then
			engine.ui.bar({ id = "zair", label = "Powietrze", value = a, max = MAX_AIR, color = "#7ac8f0" })
		else
			engine.ui.remove("zair")
		end
	end)
end)

-- Jedzenie: prawy przycisk z jedzeniem w ręce (przedmiot z polem food).
engine.hooks.before("item.use", function(ctx)
	local def = engine.items.def(ctx.item)
	if not def or not def.food then return end
	if food() >= MAX_FOOD then
		engine.ui.notify("Nie jesteś głodny")
		ctx.cancel = true
		return
	end
	kit.inventory.take(backpack.HOTBAR, ctx.slot, 1)
	set_food(food() + def.food)
	engine.player.heal(def.food / 2)
	show()
end)
