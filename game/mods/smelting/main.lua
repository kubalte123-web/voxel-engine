-- Piec: kontener bloku (1 surowiec, 2 paliwo, 3 wynik), dane bloku (paliwo, postęp) i zaplanowana
-- aktualizacja co sekundę, dopóki piec pracuje. Silnik zapisuje dane i plan ze światem, więc piec
-- pracuje dalej po wczytaniu gry, a po zniszczeniu bloku przedmioty wypadają.
local kit = engine.require("modkit")
local backpack = engine.require("backpack")

local COOK = 5          -- sekundy na jeden przedmiot
local recipes = {}      -- surowiec -> {item, count}
local fuel = {}         -- paliwo -> sekundy palenia
local viewers = {}      -- id gracza -> klucz pozycji otwartego pieca

local function recipe(input, output, count)
	if engine.items.def(input) and engine.items.def(output) then recipes[input] = { item = output, count = count or 1 } end
end
local function add_fuel(item, seconds)
	if engine.items.def(item) then fuel[item] = seconds end
end

recipe("raw_iron", "iron_ingot")
recipe("sand", "glass")
recipe("cobblestone", "stone")
recipe("log", "coal")
recipe("beef", "cooked_beef")
recipe("mutton", "cooked_mutton")
recipe("chicken_meat", "cooked_chicken")
add_fuel("coal", 40)
add_fuel("log", 15)
add_fuel("planks", 8)
add_fuel("stick", 3)
add_fuel("crafting_table", 12)
add_fuel("chest", 12)

local function pkey(p) return p.x .. "," .. p.y .. "," .. p.z end
local function container(pos) return engine.blocks.container(pos, 3) end

local function smeltable(c)
	local inp = engine.items.get(c, 1)
	local r = inp.item and recipes[inp.item]
	if not r then return nil end
	local out = engine.items.get(c, 3)
	if out.item and (out.item ~= r.item or out.count + r.count > engine.items.max_stack(r.item)) then return nil end
	return r
end

local open_window

-- okno odświeżamy wszystkim graczom, którzy patrzą na ten piec
local function refresh(pos)
	local k = pkey(pos)
	engine.players.each(function()
		if viewers[engine.player.id()] == k and engine.ui.is_open("furnace") then open_window(pos) end
	end)
end

local function start(pos)
	local d = engine.blocks.data(pos)
	if d.active then return end
	engine.blocks.set_data(pos, "active", true)
	engine.blocks.schedule(pos, 0.2, "smelt")
end

-- jeden krok pracy pieca (co sekundę)
local function step(pos)
	local c = container(pos)
	local d = engine.blocks.data(pos)
	local burn, progress = d.burn or 0, d.progress or 0
	local r = smeltable(c)
	if burn <= 0 and r then
		local f = engine.items.get(c, 2)
		if f.item and fuel[f.item] then
			kit.inventory.take(c, 2, 1)
			burn = fuel[f.item]
			engine.blocks.set_data(pos, "burn_max", burn)
		end
	end
	if burn > 0 then
		burn = burn - 1
		if r then
			progress = progress + 1
			if progress >= COOK then
				progress = 0
				kit.inventory.take(c, 1, 1)
				local out = engine.items.get(c, 3)
				engine.items.set(c, 3, { item = r.item, count = (out.count or 0) + r.count })
			end
		else
			progress = 0
		end
		if engine.random() < 0.3 then engine.sound.play("furnace.fire", { pos = pos }) end
	else
		progress = 0
	end
	engine.blocks.set_data(pos, "burn", burn)
	engine.blocks.set_data(pos, "progress", progress)
	local lit = burn > 0
	if engine.blocks.state(pos).lit ~= lit then engine.blocks.set_state(pos, { lit = lit }) end
	local f = engine.items.get(c, 2)
	if lit or (smeltable(c) and f.item and fuel[f.item]) then
		engine.blocks.schedule(pos, 1, "smelt")
	else
		engine.blocks.set_data(pos, "active", nil)
	end
	refresh(pos)
end

engine.blocks.on_update("furnace", function(ctx)
	if ctx.reason == "scheduled" then step(ctx.pos) end
end)

open_window = function(pos)
	local d = engine.blocks.data(pos)
	viewers[engine.player.id()] = pkey(pos)
	engine.ui.window({
		id = "furnace",
		title = "Piec",
		sections = {
			{ type = "text", text = "Surowiec, paliwo, wynik. Paliwo: węgiel, drewno, deski, patyki." },
			{ type = "slots", container = container(pos), columns = 3 },
			{ type = "progress", label = "Przetapianie", value = (d.progress or 0) / COOK },
			{ type = "progress", label = "Ogień", value = (d.burn or 0) / math.max(1, d.burn_max or 1) },
			{ type = "slots", container = backpack.BACKPACK, columns = 9, title = "Plecak" },
			{ type = "slots", container = backpack.HOTBAR, columns = 8, title = "Pasek" },
		},
	})
end

engine.hooks.before("block.use", function(ctx)
	if engine.blocks.base(ctx.block) ~= "furnace" then return end
	ctx.cancel = true
	open_window(ctx.pos)
end)

-- coś włożono do pieca: może zacząć pracę
engine.hooks.after("slot.click", function(ctx)
	local x, y, z = ctx.container:match("^@(-?%d+),(-?%d+),(-?%d+)$")
	if not x then return end
	local pos = { x = tonumber(x), y = tonumber(y), z = tonumber(z) }
	if engine.blocks.base(engine.world.get_block(pos)) == "furnace" then start(pos) end
end)

engine.on("ui.closed", function(e)
	if e.id == "furnace" then viewers[engine.player.id()] = nil end
end)

local classic = engine.optional("crafting_classic")
if classic then classic.shaped({ "CCC", "C C", "CCC" }, { C = "cobblestone" }, "furnace") end
local discovery = engine.optional("crafting_discovery")
if discovery then discovery.add("piec", { cobblestone = 8 }, "furnace", 1, 5) end

engine.export({ recipe = recipe, fuel = add_fuel, recipes = recipes })
