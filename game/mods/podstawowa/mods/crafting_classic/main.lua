-- Rzemiosło klasyczne: siatka 2x2 (okno postaci) i 3x3 (stół rzemieślniczy), przepisy kształtowe i bezkształtne.
local kit = engine.require("modkit")
local backpack = engine.require("backpack")

local recipes = {}

-- przepis kształtowy: wzór (wiersze znaków), klucz znak -> przedmiot albo lista przedmiotów, wynik
local function shaped(pattern, key, item, count)
	local cells, w = {}, 0
	for _, row in ipairs(pattern) do w = math.max(w, #row) end
	for y, row in ipairs(pattern) do
		for x = 1, w do
			local ch = row:sub(x, x)
			local k = key[ch]
			if type(k) == "string" then k = { k } end
			cells[(y - 1) * w + x] = (ch ~= " " and ch ~= "") and k or false
		end
	end
	recipes[#recipes + 1] = { kind = "shaped", w = w, h = #pattern, cells = cells, item = item, count = count or 1 }
end

-- przepis bezkształtny: przedmioty w dowolnych miejscach siatki
local function shapeless(items, item, count)
	recipes[#recipes + 1] = { kind = "shapeless", items = items, item = item, count = count or 1 }
end

local function has(item) return engine.items.def(item) ~= nil end
local function contains(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

-- siatka -> wynik; grid to lista n*n kluczy przedmiotów albo false
local function match(grid, n)
	local minx, miny, maxx, maxy = n + 1, n + 1, 0, 0
	local counts, total = {}, 0
	for y = 1, n do
		for x = 1, n do
			local it = grid[(y - 1) * n + x]
			if it then
				minx, miny = math.min(minx, x), math.min(miny, y)
				maxx, maxy = math.max(maxx, x), math.max(maxy, y)
				counts[it] = (counts[it] or 0) + 1
				total = total + 1
			end
		end
	end
	if total == 0 then return nil end
	local w, h = maxx - minx + 1, maxy - miny + 1
	for _, r in ipairs(recipes) do
		if r.kind == "shaped" and r.w == w and r.h == h then
			for _, mirror in ipairs({ false, true }) do
				local ok = true
				for y = 1, h do
					for x = 1, w do
						local rx = mirror and (w - x + 1) or x
						local want = r.cells[(y - 1) * w + rx]
						local got = grid[(miny + y - 2) * n + (minx + x - 1)]
						if want then
							if not got or not contains(want, got) then ok = false end
						elseif got then
							ok = false
						end
					end
				end
				if ok then return r end
			end
		elseif r.kind == "shapeless" then
			local need, ok = 0, true
			for it, c in pairs(r.items) do
				need = need + c
				if counts[it] ~= c then ok = false end
			end
			if ok and need == total then return r end
		end
	end
	return nil
end

-- Przepisy podstawowe (te, których przedmioty istnieją przy włączonych modach)
shapeless({ log = 1 }, "planks", 4)
shaped({ "P", "P" }, { P = "planks" }, "stick", 4)
shaped({ "PP", "PP" }, { P = "planks" }, "crafting_table", 1)
if has("coal") then shaped({ "C", "S" }, { C = "coal", S = "stick" }, "torch", 4) end
local mats = { { "planks", "wooden" }, { { "cobblestone", "stone" }, "stone" } }
if has("raw_iron") then mats[#mats + 1] = { "raw_iron", "iron" } end
for _, m in ipairs(mats) do
	local key = { M = m[1], S = "stick" }
	shaped({ "MMM", " S ", " S " }, key, m[2] .. "_pickaxe")
	shaped({ "MM", "MS", " S" }, key, m[2] .. "_axe")
	shaped({ "M", "S", "S" }, key, m[2] .. "_shovel")
	shaped({ "M", "M", "S" }, key, m[2] .. "_sword")
end
if has("raw_iron") then shaped({ "I I", " I " }, { I = "raw_iron" }, "bucket", 1) end
if has("coal") then shapeless({ sand = 2, coal = 1 }, "glass", 2) end
shaped({ "GGG", "GTG", "GGG" }, { G = "glass", T = "torch" }, "lamp", 2)
if has("bread") and has("wheat") then shaped({ "WWW" }, { W = "wheat" }, "bread", 1) end
if has("crate") then shaped({ "SPS", "P P", "SPS" }, { P = "planks", S = "stick" }, "crate", 2) end
if has("barrel") then shaped({ "PSP", "P P", "PSP" }, { P = "planks", S = "stick" }, "barrel", 2) end
if has("ball") and has("leather") then shaped({ " L ", "LWL", " L " }, { L = "leather", W = "wool" }, "ball", 1) end
shaped({ "SS", "SS" }, { S = "stone" }, "bricks", 4)

-- siatki każdego gracza: 2x2 w oknie postaci, 3x3 przy stole
local GRIDS = { craft2 = { n = 2, out = "craft2_out" }, craft3 = { n = 3, out = "craft3_out" } }

engine.on("player.join", function()
	engine.items.container("craft2", 4, true, true)
	engine.items.container("craft2_out", 1, false, true)
	engine.items.container("craft3", 9, true, true)
	engine.items.container("craft3_out", 1, false, true)
end)

local function grid_items(name)
	local n = GRIDS[name].n
	local g = {}
	for i = 1, n * n do
		local s = engine.items.get(name, i)
		g[i] = s.item or false
	end
	return g, n
end

local function update(name)
	local r = match(grid_items(name))
	engine.items.set(GRIDS[name].out, 1, r and { item = r.item, count = r.count } or {})
end

-- po każdej zmianie w siatce liczymy wynik
engine.hooks.after("slot.click", function(ctx)
	if GRIDS[ctx.container] then update(ctx.container) end
end)

-- kliknięcie w wynik: bierzemy go do kursora i zużywamy po jednej sztuce z każdego pola siatki
engine.hooks.before("slot.click", function(ctx)
	local grid
	for name, g in pairs(GRIDS) do if g.out == ctx.container then grid = name end end
	if not grid then return end
	ctx.cancel = true
	local out = engine.items.get(ctx.container, 1)
	if not out.item then return end
	local held = engine.ui.held()
	if held.item and (held.item ~= out.item or held.count + out.count > engine.items.max_stack(out.item)) then return end
	engine.ui.set_held({ item = out.item, count = (held.count or 0) + out.count })
	local n = GRIDS[grid].n
	for i = 1, n * n do kit.inventory.take(grid, i, 1) end
	update(grid)
end)

-- zamknięcie okna: przedmioty z siatki wracają do plecaka
engine.on("ui.closed", function(e)
	local grid = (e.id == "character" and "craft2") or (e.id == "crafting_table" and "craft3") or nil
	if not grid then return end
	local n = GRIDS[grid].n
	for i = 1, n * n do
		local s = engine.items.get(grid, i)
		if s.item then
			backpack.give(s.item, s.count)
			engine.items.set(grid, i, {})
		end
	end
	update(grid)
end)

if engine.settings.get("grid_in_inventory") then
	backpack.add_section(function()
		return {
			{ type = "slots", container = "craft2", columns = 2, title = "Rzemiosło" },
			{ type = "slots", container = "craft2_out", columns = 1, title = "Wynik" },
		}
	end)
end

-- stół rzemieślniczy: prawy przycisk otwiera siatkę 3x3
engine.hooks.before("block.use", function(ctx)
	if engine.blocks.key(ctx.block) ~= "crafting_table" then return end
	ctx.cancel = true
	engine.ui.window({
		id = "crafting_table",
		title = "Stół rzemieślniczy",
		sections = {
			{ type = "slots", container = "craft3", columns = 3, title = "Ułóż przedmioty według przepisu" },
			{ type = "slots", container = "craft3_out", columns = 1, title = "Wynik" },
			{ type = "slots", container = backpack.BACKPACK, columns = 9, title = "Plecak" },
			{ type = "slots", container = backpack.HOTBAR, columns = 8, title = "Pasek" },
		},
	})
end)

engine.export({ shaped = shaped, shapeless = shapeless, recipes = recipes, match = match })
