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

-- ---------- księga przepisów ----------
-- Tryb (ustawienie moda): wszystkie przepisy, tylko odkryte (już wytworzone) albo z tego, co gracz zdobył
-- (przepis pojawia się, gdy gracz miał w ekwipunku choć jeden składnik, np. deskę – wtedy widać miecz).
local BOOK_MODE = engine.settings.get("recipe_book") or "Z tego, co gracz zdobył"
local PLAYER_CONTAINERS = { backpack.HOTBAR, backpack.BACKPACK }

local function seen() return engine.player.storage.get("seen_items", {}) end
local function crafted() return engine.player.storage.get("crafted_items", {}) end

-- zapamiętuje przedmioty, które gracz ma teraz w ekwipunku
local function mark_seen()
	local s, changed = seen(), false
	for _, c in ipairs(PLAYER_CONTAINERS) do
		for i = 1, engine.items.size(c) do
			local it = engine.items.get(c, i).item
			if it and not s[it] then s[it] = true; changed = true end
		end
	end
	if changed then engine.player.storage.set("seen_items", s) end
end

-- składniki przepisu: lista kluczy (dla wzoru wszystkie warianty)
local function ingredients(r)
	local out, set = {}, {}
	local function add(k) if not set[k] then set[k] = true; out[#out + 1] = k end end
	if r.kind == "shaped" then
		for i = 1, r.w * r.h do
			if r.cells[i] then for _, k in ipairs(r.cells[i]) do add(k) end end
		end
	else
		for k in pairs(r.items) do add(k) end
	end
	return out
end

local function visible(r)
	if BOOK_MODE == "Wszystkie przepisy" then return true end
	if BOOK_MODE == "Tylko odkryte (już wytworzone)" then return crafted()[r.item] == true end
	local s = seen()
	if s[r.item] then return true end
	for _, k in ipairs(ingredients(r)) do if s[k] then return true end end
	return false
end

local function fits2(r)
	if r.kind == "shaped" then return r.w <= 2 and r.h <= 2 end
	local n = 0
	for _, c in pairs(r.items) do n = n + c end
	return n <= 4
end

local function book_list()
	local out = {}
	for i, r in ipairs(recipes) do
		if engine.items.def(r.item) and visible(r) then out[#out + 1] = i end
	end
	table.sort(out, function(a, b) return engine.items.name(recipes[a].item) < engine.items.name(recipes[b].item) end)
	return out
end

-- stan księgi gracza: otwarta i wybrany przepis
local function book() return engine.player.storage.get("recipe_book", { open = false, sel = 0 }) end
local function set_book(b) engine.player.storage.set("recipe_book", b) end

-- przepis na siatce 3×3 jako sekcje: wiersze ikon składników
local function pattern_sections(r)
	local rows = {}
	if r.kind == "shaped" then
		for y = 1, r.h do
			local row = {}
			for x = 1, r.w do
				local k = r.cells[(y - 1) * r.w + x]
				row[#row + 1] = k and { type = "image", item = k[1], size = { 36, 36 }, expand = false }
					or { type = "space", size = 36, width = 36, expand = false }
			end
			rows[#rows + 1] = { type = "row", wrap = false, gap = 4, sections = row }
		end
	else
		local row = {}
		for k, c in pairs(r.items) do
			for _ = 1, c do row[#row + 1] = { type = "image", item = k, size = { 36, 36 }, expand = false } end
		end
		rows[#rows + 1] = { type = "row", wrap = false, gap = 4, sections = row }
	end
	return rows
end

local book_toggle, book_pick, book_fill

-- panel księgi z lewej strony okna ekwipunku
backpack.add_side(function()
	local b = book()
	if not b.open then return nil end
	mark_seen()
	local list = book_list()
	local items = {}
	local sel = 0
	for n, i in ipairs(list) do
		local r = recipes[i]
		items[#items + 1] = { item = r.item, text = engine.items.name(r.item) .. (r.count > 1 and (" ×" .. r.count) or "") }
		if i == b.sel then sel = n end
	end
	local out = {
		{ type = "text", text = "Księga przepisów", size = 18 },
		{ type = "list", id = "book_sel", items = items, selected = sel, height = 230, on_change = function(f) book_pick(f) end },
	}
	if #items == 0 then
		out[#out + 1] = { type = "text", size = 13, color = "#9aa4b2", text = "Zbieraj przedmioty, a pojawią się przepisy." }
	end
	local r = recipes[b.sel]
	if r and sel > 0 then
		for _, s in ipairs(pattern_sections(r)) do out[#out + 1] = s end
		if fits2(r) then
			out[#out + 1] = { type = "button", id = "book_fill", text = "Ułóż w siatce", primary = true, on_press = function() book_fill() end }
		else
			out[#out + 1] = { type = "text", size = 13, color = "#9aa4b2", text = "Wymaga stołu rzemieślniczego (siatka 3×3)." }
		end
	end
	return out
end)

book_toggle = function()
	local b = book()
	b.open = not b.open
	set_book(b)
	backpack.open()
end

book_pick = function(fields)
	local list = book_list()
	local b = book()
	b.sel = list[fields.book_sel or 0] or 0
	set_book(b)
	backpack.open()
end

-- układa składniki wybranego przepisu w siatce 2×2 z paska i plecaka
book_fill = function()
	local r = recipes[book().sel]
	if not r or not fits2(r) then return end
	-- najpierw siatka do plecaka
	for i = 1, 4 do
		local s = engine.items.get("craft2", i)
		if s.item then backpack.give(s.item, s.count); engine.items.set("craft2", i, {}) end
	end
	local want = {}   -- miejsce siatki -> lista dopuszczalnych przedmiotów
	if r.kind == "shaped" then
		for y = 1, r.h do
			for x = 1, r.w do want[(y - 1) * 2 + x] = r.cells[(y - 1) * r.w + x] end
		end
	else
		local i = 1
		for k, c in pairs(r.items) do for _ = 1, c do want[i] = { k }; i = i + 1 end end
	end
	local missing = {}
	for slot = 1, 4 do
		local opts = want[slot]
		if opts then
			local got = false
			for _, k in ipairs(opts) do
				if not got and kit.inventory.count(PLAYER_CONTAINERS, k) > 0 then
					kit.inventory.remove(PLAYER_CONTAINERS, k, 1)
					engine.items.set("craft2", slot, { item = k, count = 1 })
					got = true
				end
			end
			if not got then missing[#missing + 1] = engine.items.name(opts[1]) end
		end
	end
	update("craft2")
	if #missing > 0 then engine.ui.notify("Brakuje: " .. table.concat(missing, ", ")) end
	backpack.open()
end

engine.hooks.after("item.pickup", function() mark_seen() end)
engine.hooks.after("block.break", function() mark_seen() end)

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
	-- odkryte przepisy (tryb księgi „tylko odkryte”) i zebrane przedmioty
	local c = crafted()
	if not c[out.item] then c[out.item] = true; engine.player.storage.set("crafted_items", c) end
	local s = seen()
	if not s[out.item] then s[out.item] = true; engine.player.storage.set("seen_items", s) end
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

-- prawa kolumna okna ekwipunku: siatka 2×2, strzałka, wynik; pod spodem przycisk księgi przepisów
backpack.add_section(function()
	local out = {}
	if engine.settings.get("grid_in_inventory") then
		out[#out + 1] = { type = "text", text = "Rzemiosło", size = 15, color = "#9aa4b2" }
		out[#out + 1] = { type = "row", wrap = false, gap = 8, sections = {
			{ type = "slots", container = "craft2", columns = 2, cell = 44, expand = false },
			{ type = "text", text = "→", size = 26, wrap = false, expand = false },
			{ type = "slots", container = "craft2_out", columns = 1, cell = 44, expand = false },
		} }
	end
	out[#out + 1] = { type = "space", size = 6 }
	out[#out + 1] = { type = "button", id = "book_toggle", text = book().open and "Zamknij księgę" or "Księga przepisów", on_press = function() book_toggle() end }
	return out
end)

-- stół rzemieślniczy: prawy przycisk otwiera siatkę 3x3
engine.hooks.before("block.use", function(ctx)
	if engine.blocks.key(ctx.block) ~= "crafting_table" then return end
	ctx.cancel = true
	engine.ui.window({
		id = "crafting_table",
		title = "Stół rzemieślniczy",
		fit = true,
		sections = {
			{ type = "row", wrap = false, gap = 10, sections = {
				{ type = "slots", container = "craft3", columns = 3, cell = 46, expand = false },
				{ type = "text", text = "→", size = 30, wrap = false, expand = false },
				{ type = "slots", container = "craft3_out", columns = 1, cell = 46, expand = false },
			} },
			{ type = "slots", container = backpack.BACKPACK, columns = 9, cell = 46 },
			{ type = "slots", container = backpack.HOTBAR, columns = 8, cell = 46 },
		},
	})
end)

engine.export({ shaped = shaped, shapeless = shapeless, recipes = recipes, match = match })
