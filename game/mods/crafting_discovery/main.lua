-- Rzemiosło odkrywcze: składniki bez kolejności, przepisy do odkrycia, wykuwanie trwa, ogień przyspiesza.
local kit = engine.require("modkit")
local backpack = engine.require("backpack")

local SLOTS = 4
local recipes = {}

-- items: { klucz = ile }, time w sekundach, hint: krótka podpowiedź po odkryciu podobnego
local function add(id, items, result, count, time, name)
	if engine.items.def(result) == nil and engine.blocks.id(result) == nil then return end
	for k in pairs(items) do
		if engine.items.def(k) == nil and engine.blocks.id(k) == nil then return end
	end
	recipes[#recipes + 1] = { id = id, items = items, item = result, count = count or 1, time = time or 2, name = name }
end

add("deski", { log = 1 }, "planks", 4, 1)
add("patyki", { planks = 1 }, "stick", 4, 1)
add("pochodnie", { coal = 1, stick = 1 }, "torch", 6, 1.5)
add("warsztat", { planks = 2, cobblestone = 2 }, "workbench", 1, 3)
add("kilof_drewniany", { planks = 3, stick = 2 }, "wooden_pickaxe", 1, 3)
add("siekiera_drewniana", { planks = 2, stick = 2 }, "wooden_axe", 1, 3)
add("lopata_drewniana", { planks = 1, stick = 2 }, "wooden_shovel", 1, 2)
add("miecz_drewniany", { planks = 2, stick = 1 }, "wooden_sword", 1, 2)
add("kilof_kamienny", { cobblestone = 3, stick = 2 }, "stone_pickaxe", 1, 4)
add("siekiera_kamienna", { cobblestone = 2, stick = 2 }, "stone_axe", 1, 4)
add("lopata_kamienna", { cobblestone = 1, stick = 2 }, "stone_shovel", 1, 3)
add("miecz_kamienny", { cobblestone = 2, stick = 1 }, "stone_sword", 1, 3)
add("kilof_zelazny", { raw_iron = 3, stick = 2, coal = 1 }, "iron_pickaxe", 1, 6)
add("siekiera_zelazna", { raw_iron = 2, stick = 2, coal = 1 }, "iron_axe", 1, 6)
add("lopata_zelazna", { raw_iron = 1, stick = 2, coal = 1 }, "iron_shovel", 1, 5)
add("miecz_zelazny", { raw_iron = 2, stick = 1, coal = 1 }, "iron_sword", 1, 5)
add("wiadro", { raw_iron = 3, coal = 1 }, "bucket", 1, 5)
add("szklo", { sand = 2, coal = 1 }, "glass", 3, 4)
add("lampa", { glass = 2, torch = 1, ruby = 1 }, "lamp", 2, 5)
add("cegly", { stone = 2, sand = 1 }, "bricks", 4, 3)
add("chleb", { wheat = 3 }, "bread", 2, 4)
add("skrzynka", { planks = 4 }, "crate", 2, 3)
add("beczka", { planks = 3, stick = 2, cobblestone = 1 }, "barrel", 1, 4)
add("pilka", { leather = 2, wool = 1 }, "ball", 1, 3)

local by_id = {}
for _, r in ipairs(recipes) do by_id[r.id] = r end

engine.on("player.join", function()
	engine.items.container("forge", SLOTS, true, true)
end)

local function contents()
	local c = {}
	for i = 1, SLOTS do
		local s = engine.items.get("forge", i)
		if s.item then c[s.item] = (c[s.item] or 0) + s.count end
	end
	return c
end

-- ile razy przepis mieści się w składnikach (dokładnie te same rodzaje, wielokrotność ilości)
local function fits(r, c)
	local times = nil
	for k, n in pairs(r.items) do
		local have = c[k] or 0
		if have < n or have % n ~= 0 then return 0 end
		local t = have // n
		if times and t ~= times then return 0 end
		times = t
	end
	for k in pairs(c) do if not r.items[k] then return 0 end end
	return times or 0
end

-- podpowiedź: te same rodzaje, złe ilości → „Prawie!”, brakuje jednego rodzaju → „Czegoś brakuje”
local function hint(c)
	for _, r in ipairs(recipes) do
		local same, missing, extra = 0, 0, 0
		for k in pairs(r.items) do if c[k] then same = same + 1 else missing = missing + 1 end end
		for k in pairs(c) do if not r.items[k] then extra = extra + 1 end end
		if extra == 0 and missing == 0 then return "Prawie! Składniki pasują, ale ilości nie." end
		if extra == 0 and missing == 1 and same >= 1 then return "Czegoś jeszcze brakuje…" end
	end
	return nil
end

local function book()
	return engine.player.storage.get("book", {})
end

local function known_count()
	local n = 0
	for id in pairs(book()) do if by_id[id] then n = n + 1 end end
	return n
end

local function describe(r)
	local parts = {}
	for k, n in pairs(r.items) do parts[#parts + 1] = n .. "× " .. engine.items.name(k) end
	table.sort(parts)
	return table.concat(parts, " + ") .. "  →  " .. r.count .. "× " .. engine.items.name(r.item)
end

-- ogień w promieniu 3 bloków (pochodnia, lampa) przyspiesza wykuwanie
local function fire_bonus(pos)
	if not pos then return 1 end
	local torch, lamp = engine.blocks.id("torch"), engine.blocks.id("lamp")
	for dx = -3, 3 do for dy = -1, 2 do for dz = -3, 3 do
		local b = engine.world.get_block({ x = pos.x + dx, y = pos.y + dy, z = pos.z + dz })
		if b == torch or b == lamp then return 2 end
	end end end
	return 1
end

local jobs = {} -- id gracza → { recipe, times, left, total, pos }
local messages = {} -- id gracza → ostatni komunikat warsztatu

local open_window

local function forge(fields)
	local pid = engine.player.id()
	if jobs[pid] then return end
	local c = contents()
	if next(c) == nil then
		messages[pid] = "Wrzuć składniki do pól warsztatu."
		return open_window()
	end
	for _, r in ipairs(recipes) do
		local times = fits(r, c)
		if times > 0 then
			for i = 1, SLOTS do engine.items.set("forge", i, {}) end
			local speed = engine.settings.get("speed") or 1
			local pos = engine.player.storage.get("bench_pos", nil)
			local total = r.time * math.sqrt(times) / speed / fire_bonus(pos)
			jobs[pid] = { recipe = r, times = times, left = total, total = total }
			messages[pid] = "Wykuwanie: " .. engine.items.name(r.item) .. (fire_bonus(pos) > 1 and "  (ogień przyspiesza)" or "")
			return open_window()
		end
	end
	messages[pid] = (engine.settings.get("hints") and hint(c)) or "Nic z tego nie wyszło."
	open_window()
end

local function finish(pid, job)
	local r = job.recipe
	local count = r.count * job.times
	local b = book()
	local first = not b[r.id]
	if first then
		b[r.id] = true
		engine.player.storage.set("book", b)
		count = count + r.count -- premia za pierwsze odkrycie
		engine.ui.notify("Odkryto przepis: " .. engine.items.name(r.item) .. "! (" .. known_count() .. "/" .. #recipes .. ")")
		engine.emit("crafting.discovered", { player = pid, recipe = r.id, item = r.item })
	end
	backpack.give(r.item, count)
	messages[pid] = "Gotowe: " .. count .. "× " .. engine.items.name(r.item) .. (first and "  (premia za odkrycie)" or "")
	engine.emit("crafting.crafted", { player = pid, item = r.item, count = count })
end

open_window = function()
	local pid = engine.player.id()
	local job = jobs[pid]
	local sections = {
		{ type = "text", text = messages[pid] or "Wrzuć do pól dowolne składniki i spróbuj szczęścia. Kolejność nie ma znaczenia." },
		{ type = "slots", container = "forge", columns = SLOTS, title = "Składniki" },
	}
	if job then
		sections[#sections + 1] = { type = "progress", label = "Wykuwanie…", value = 1 - job.left / job.total }
	else
		sections[#sections + 1] = { type = "button", id = "forge", text = "Wykuj", on_press = forge }
	end
	sections[#sections + 1] = { type = "slots", container = backpack.BACKPACK, columns = 9, title = "Plecak" }
	sections[#sections + 1] = { type = "slots", container = backpack.HOTBAR, columns = 8, title = "Pasek" }
	local lines = {}
	for _, r in ipairs(recipes) do if book()[r.id] then lines[#lines + 1] = describe(r) end end
	sections[#sections + 1] = { type = "text", text = "Księga przepisów (" .. #lines .. "/" .. #recipes .. "):\n" ..
		(#lines > 0 and table.concat(lines, "\n") or "jeszcze nic nie odkryto") }
	engine.ui.window({ id = "workbench", title = "Warsztat", sections = sections })
end

engine.hooks.before("block.use", function(ctx)
	if engine.blocks.key(ctx.block) ~= "workbench" then return end
	ctx.cancel = true
	engine.player.storage.set("bench_pos", ctx.pos)
	open_window()
end)

-- postęp wykuwania każdego gracza; okno odświeżamy, gdy jest otwarte
kit.every(0.25, function()
	for pid, job in pairs(jobs) do
		job.left = job.left - 0.25
		engine.as_player(pid, function()
			if job.left <= 0 then
				jobs[pid] = nil
				finish(pid, job)
			end
			if engine.ui.is_open("workbench") then open_window() end
		end)
	end
end)

-- gracz wyszedł: niedokończone wykuwanie i tak się kończy (przedmioty nie przepadają)
engine.on("player.leave", function(e)
	local job = jobs[e.id]
	if job then
		jobs[e.id] = nil
		engine.as_player(e.id, function() finish(e.id, job) end)
	end
end)

-- zamknięcie okna: składniki zostają w polach warsztatu (pojemnik jest trwały i osobny dla każdego gracza)
engine.export({ add = add, recipes = recipes, known = function() return book() end })
