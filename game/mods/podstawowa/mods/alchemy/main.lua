-- Alchemia: logika kotła i mikstur. Wygląd kotła zmienia się przez stany bloku (content) i
-- engine.blocks.look (kolor cieczy), animacje przez engine.blocks.animate, efekty przez engine.particles.spawn.
local kit = engine.require("modkit")
local backpack = engine.require("backpack")

local BREW = engine.settings.get("brew_time") or 10
local MAX_ING = 3
local DOSES = 3

-- składniki: kolor, który dodają do mikstury
local INGREDIENTS = {
	feather = "#f4f4f4", flower_yellow = "#f0d030", flower_red = "#e02a2a", apple = "#d83a3a",
	egg = "#f2e2c0", leaves = "#3aa040", ruby = "#e0304a", wheat = "#e0c050", seeds = "#b8a050",
	coal = "#202020", sand = "#e0d090", cactus = "#3a8a3a",
}
-- przepisy: posortowane klucze składników (bez rubinu) -> mikstura; rubin = wersja mocna
local RECIPES = {
	["feather+flower_yellow"] = "speed",
	["egg+feather"] = "jump",
	["feather+leaves"] = "feather",
	["apple+flower_red"] = "heal",
}
local COLORS = { speed = "#40c8f0", jump = "#70e060", feather = "#e8e8ff", heal = "#f04060" }
local WATER = "#3a78d8"

local loops = {}   -- klucz pozycji -> id zapętlonego dźwięku bulgotania

local function pkey(p) return p.x .. "," .. p.y .. "," .. p.z end
local function top(p) return { x = p.x + 0.5, y = p.y + 0.8, z = p.z + 0.5 } end

local function hex(c)
	return tonumber(c:sub(2, 3), 16), tonumber(c:sub(4, 5), 16), tonumber(c:sub(6, 7), 16)
end
local function mix(a, b, t)
	local r1, g1, b1 = hex(a)
	local r2, g2, b2 = hex(b)
	return string.format("#%02x%02x%02x", math.floor(r1 + (r2 - r1) * t), math.floor(g1 + (g2 - g1) * t), math.floor(b1 + (b2 - b1) * t))
end

local function liquid_color(list)
	local c = WATER
	for i, it in ipairs(list) do c = mix(c, INGREDIENTS[it] or "#808080", 0.55 / i + 0.2) end
	return c
end

local function recipe_of(list)
	local keys, strong = {}, false
	for _, it in ipairs(list) do
		if it == "ruby" then strong = true else keys[#keys + 1] = it end
	end
	table.sort(keys)
	return RECIPES[table.concat(keys, "+")], strong
end

local function take_hand(slot) kit.inventory.take(backpack.HOTBAR, slot, 1) end

local function stop_bubbling(pos)
	local k = pkey(pos)
	if loops[k] then engine.sound.stop(loops[k]); loops[k] = nil end
end

-- prawy przycisk na kotle
engine.hooks.before("block.use", function(ctx)
	if engine.blocks.base(ctx.block) ~= "cauldron" then return end
	ctx.cancel = true
	local pos = ctx.pos
	local st = engine.blocks.state(pos).content
	local d = engine.blocks.data(pos)
	local item = ctx.item

	if st == "empty" then
		if item == "water_bucket" then
			engine.items.set(backpack.HOTBAR, ctx.slot, { item = "bucket", count = 1 })
			engine.blocks.set_state(pos, { content = "water" })
			engine.blocks.set_data(pos, "ingredients", {})
			engine.blocks.look(pos, { colors = { liquid = WATER } })
			engine.particles.spawn("alchemy.splash", top(pos), { color = { WATER } })
			engine.sound.play("water.splash", { pos = pos })
		else
			engine.ui.notify("Kocioł jest pusty – nalej wody wiadrem.")
		end
	elseif st == "water" then
		local list = d.ingredients or {}
		if INGREDIENTS[item] then
			if #list >= MAX_ING then
				engine.ui.notify("Kocioł mieści najwyżej " .. MAX_ING .. " składniki. Zamieszaj patykiem.")
				return
			end
			take_hand(ctx.slot)
			list[#list + 1] = item
			engine.blocks.set_data(pos, "ingredients", list)
			local c = liquid_color(list)
			engine.blocks.look(pos, { colors = { liquid = c } })
			engine.blocks.animate(pos, "plop")
			engine.particles.spawn("alchemy.splash", top(pos), { color = { c, INGREDIENTS[item] } })
			engine.sound.play("alchemy.plop", { pos = pos })
			engine.ui.notify("Wrzucono: " .. engine.items.name(item) .. " (" .. #list .. "/" .. MAX_ING .. ")")
		elseif item == "stick" then
			if #list == 0 then
				engine.ui.notify("Najpierw wrzuć składniki.")
				return
			end
			engine.blocks.set_state(pos, { content = "brewing" })
			engine.blocks.schedule(pos, BREW, "brew")
			loops[pkey(pos)] = engine.sound.play("alchemy.bubbling", { pos = pos, loop = true })
			engine.ui.notify("Warzenie… (" .. BREW .. " s)")
		else
			engine.ui.notify("Wrzuć składnik albo zamieszaj patykiem.")
		end
	elseif st == "brewing" then
		engine.ui.notify("Mikstura jeszcze się warzy…")
	elseif st == "ready" then
		if item == "glass_bottle" then
			take_hand(ctx.slot)
			local name = "potion_" .. d.potion .. (d.strong and "_strong" or "")
			backpack.give(name, 1)
			local left = (d.doses or 1) - 1
			engine.sound.play("alchemy.fill", { pos = pos })
			engine.particles.spawn("alchemy.sparkle", top(pos), { color = { COLORS[d.potion], "#ffffff" }, amount = 0.4 })
			engine.ui.notify(engine.items.name(name) .. " (zostało: " .. left .. ")")
			if left <= 0 then
				engine.blocks.set_state(pos, { content = "empty" })
				engine.blocks.clear_data(pos)
			else
				engine.blocks.set_data(pos, "doses", left)
			end
		else
			engine.ui.notify("Mikstura gotowa – zbierz ją pustą butelką.")
		end
	end
end)

-- koniec warzenia (zaplanowana aktualizacja – działa też po wczytaniu gry)
engine.blocks.on_update("cauldron", function(ctx)
	if ctx.reason ~= "scheduled" or ctx.tag ~= "brew" then return end
	local pos = ctx.pos
	stop_bubbling(pos)
	local potion, strong = recipe_of(ctx.data.ingredients or {})
	if potion then
		engine.blocks.set_state(pos, { content = "ready" })
		engine.blocks.set_data(pos, "potion", potion)
		engine.blocks.set_data(pos, "strong", strong)
		engine.blocks.set_data(pos, "doses", DOSES)
		engine.blocks.look(pos, { colors = { liquid = COLORS[potion] } })
		engine.blocks.animate(pos, "done")
		engine.particles.spawn("alchemy.sparkle", top(pos), { color = { COLORS[potion], "#ffffff" } })
		engine.sound.play("alchemy.done", { pos = pos })
	else
		engine.blocks.set_state(pos, { content = "empty" })
		engine.blocks.clear_data(pos)
		engine.particles.spawn("alchemy.smoke", top(pos))
		engine.sound.play("alchemy.fail", { pos = pos })
	end
end)

-- kocioł zniszczony w trakcie warzenia: cisza
engine.on("block.removed", function(e)
	if e.key == "cauldron" then stop_bubbling(e.pos) end
end)

---------------------------------------------------------------------------
-- Mikstury: picie i działanie (statystyki gracza na czas)
---------------------------------------------------------------------------
local EFFECT_TIME = 45   -- sekundy; mocna mikstura działa dwa razy dłużej i silniej

engine.hooks.before("item.use", function(ctx)
	local def = engine.items.def(ctx.item)
	if not def or not def.potion then return end
	ctx.cancel = true
	take_hand(ctx.slot)
	backpack.give("glass_bottle", 1)
	local ppos = engine.player.position()
	engine.sound.play("alchemy.drink", { pos = ppos })
	engine.particles.spawn("alchemy.drink", { x = ppos.x, y = ppos.y + 1.0, z = ppos.z }, { color = { COLORS[def.potion], "#ffffff" } })
	engine.player.animate("wave")
	if def.potion == "heal" then
		engine.player.heal(def.strong and 16 or 8)
		return
	end
	-- efekt silnika: modyfikator statystyki (nie gryzie się z innymi modami), ikona i czas na ekranie
	local strength = def.strong and ({ speed = 1.67, jump = 1.5, feather = 1.25 })[def.potion] or 1
	engine.effects.add("alchemy." .. def.potion, EFFECT_TIME * (def.strong and 2 or 1), strength)
end)

---------------------------------------------------------------------------
-- Przepisy rzemiosła
---------------------------------------------------------------------------
local iron = engine.items.def("iron_ingot") and "iron_ingot" or "raw_iron"
local classic = engine.optional("crafting_classic")
if classic then
	classic.shaped({ "I I", "I I", "III" }, { I = iron }, "cauldron")
	classic.shaped({ "G G", " G " }, { G = "glass" }, "glass_bottle", 3)
end
local discovery = engine.optional("crafting_discovery")
if discovery then
	discovery.add("kociol", { [iron] = 7 }, "cauldron", 1, 6)
	discovery.add("butelki", { glass = 3 }, "glass_bottle", 3, 3)
end

engine.export({ recipes = RECIPES, ingredients = INGREDIENTS, colors = COLORS })

-- zestaw na start (raz na konto; wyłączany w ustawieniach moda)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("started", false) then return end
	local bp = engine.require("backpack")
	if engine.items.def("cauldron") then bp.give("cauldron", 1) end
	if engine.items.def("water_bucket") then bp.give("water_bucket", 2) end
	if engine.items.def("stick") then bp.give("stick", 4) end
	if engine.items.def("glass_bottle") then bp.give("glass_bottle", 6) end
	if engine.items.def("feather") then bp.give("feather", 4) end
	if engine.items.def("flower_yellow") then bp.give("flower_yellow", 2) end
	if engine.items.def("flower_red") then bp.give("flower_red", 2) end
	if engine.items.def("apple") then bp.give("apple", 2) end
	if engine.items.def("egg") then bp.give("egg", 2) end
	if engine.items.def("leaves") then bp.give("leaves", 2) end
	if engine.items.def("ruby") then bp.give("ruby", 2) end
	engine.player.storage.set("started", true)
end)
