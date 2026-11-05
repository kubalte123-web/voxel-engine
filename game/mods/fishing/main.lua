local kit = engine.require("modkit")
local backpack = engine.require("backpack")

local function base_at(p)
	local b = engine.world.get_block(p)
	return engine.blocks.base(b)
end

-- Sprawdzenie, czy w pobliżu pozycji znajduje się woda
local function is_near_water(pos)
	for dx = -3, 3 do
		for dz = -3, 3 do
			for dy = -1, 1 do
				local p = { x = pos.x + dx, y = pos.y + dy, z = pos.z + dz }
				local k = base_at(p)
				if k:sub(1, 5) == "water" then
					return true
				end
			end
		end
	end
	return false
end

-- Użycie wędki (prawy przycisk myszy trzymając wędkę)
local last_cast = {}  -- id gracza -> czas ostatniego rzutu (bez tego klikanie łowi ryby bez końca)
local clock = 0
engine.on("tick", function(e) clock = clock + e.dt end)

engine.hooks.before("item.use", function(ctx)
	if ctx.item == "fishing_rod" then
		ctx.cancel = true
		if not ctx.pos then
			engine.ui.notify("Wyceluj wędką w wodę albo brzeg.")
			return
		end
		local pid = engine.player.id()
		if last_cast[pid] and clock - last_cast[pid] < 2 then return end
		last_cast[pid] = clock

		-- Gracz musi stać w pobliżu wody, aby móc łowić
		if is_near_water(ctx.pos) then
			engine.sound.play("fishing.splash", { pos = ctx.pos })
			engine.particles.spawn("alchemy.splash", { x = ctx.pos.x + 0.5, y = ctx.pos.y + 1, z = ctx.pos.z + 0.5 })
			
			-- Szansa na złowienie ryby (np. 60% szans)
			if engine.random() < 0.6 then
				kit.inventory.add_many({ backpack.HOTBAR, backpack.BACKPACK }, "raw_fish", 1)
				engine.ui.notify("Złowiono rybę!")
			else
				engine.ui.notify("Nic nie wzięło...")
			end
		else
			engine.ui.notify("Musisz łowić w pobliżu wody!")
		end
	end
end)

-- Integracja z piecem (smelting), jeśli mod pieca jest dostępny
local smelting = engine.optional("smelting")
if smelting then
	smelting.recipe("raw_fish", "cooked_fish", 1) -- surowa ryba -> pieczona ryba (3. argument = liczba sztuk)
end

-- Przepisy rzemieślnicze dla wędki
local classic = engine.optional("crafting_classic")
if classic then
	-- w grze nie ma nici ("string"): żyłka z wełny
	classic.shaped({ "  S", " ST", "S T" }, { S = "stick", T = "wool" }, "fishing_rod")
end

local discovery = engine.optional("crafting_discovery")
if discovery then
	discovery.add("wedka", { stick = 3 }, "fishing_rod", 1, 2)
end

-- Zestaw startowy (wędka i surowa ryba)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("started_fishing", false) then return end
	if engine.items.def("fishing_rod") then backpack.give("fishing_rod", 1) end
	if engine.items.def("raw_fish") then backpack.give("raw_fish", 2) end
	engine.player.storage.set("started_fishing", true)
end)
