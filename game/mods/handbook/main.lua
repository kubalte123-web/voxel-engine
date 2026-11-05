-- Poradnik: okno z zakładkami. Stan okna (zakładka, wybrany przedmiot, ustawienia kompasu) trzymamy
-- osobno dla każdego gracza w engine.player.storage.
local DIRS = { "N", "NE", "E", "SE", "S", "SW", "W", "NW" }
local PLACES = { "top", "top_left", "top_right" }

local function st(key, default) return engine.player.storage.get(key, default) end
local function set(key, value) engine.player.storage.set(key, value) end

local shown = {}   -- gracz -> ostatni pokazany napis (wysyłamy tylko zmiany)

local function compass(force)
	local me = engine.player.id()
	if not st("compass", true) then
		if shown[me] then engine.ui.remove("handbook.compass") shown[me] = nil end
		return
	end
	local d = engine.player.look_direction()
	local deg = math.deg(math.atan(d.x, -d.z)) % 360
	local name = DIRS[math.floor((deg + 22.5) / 45) % 8 + 1]
	local text = string.format("%s  %d°", name, math.floor(deg / 5) * 5)
	if shown[me] == text and force ~= true then return end
	shown[me] = text
	engine.ui.image({
		id = "handbook.compass", image = { pattern = "gem", color = "#e8c860", color2 = "#a07820" }, size = { 26, 26 },
		text = text, font_size = 18,
		anchor = PLACES[st("compass_place", 1)] or "top", offset = { 0, 12 }, alpha = st("compass_alpha", 1.0),
	})
end

local open

local function on_change(f)
	set("tab", f.tab or 1)
	if f.items and f.items > 0 then set("item", f.items) end
	if f.compass ~= nil then set("compass", f.compass) end
	if f.alpha then set("compass_alpha", f.alpha) end
	if f.place then set("compass_place", f.place) end
	compass(true)
	open()
end

open = function()
	local keys = engine.items.list()
	local list = {}
	for i, k in ipairs(keys) do list[i] = { item = k, text = engine.items.name(k) } end
	local sel = math.min(st("item", 1), #keys)
	local key = keys[sel]
	local def = engine.items.def(key) or {}
	local info = {
		{ type = "image", item = key, size = { 96, 96 } },
		{ type = "text", text = engine.items.name(key), size = 22 },
		{ type = "text", text = def.description or "Bez opisu.", color = "#b8c4d0" },
		{ type = "text", text = string.format("Klucz: %s · stos: %d%s", key, engine.items.max_stack(key), def.food and (" · jedzenie: " .. def.food) or ""), size = 14, color = "#8a96a4" },
	}
	if engine.players.role() == "admin" then
		info[#info + 1] = { type = "item_button", id = "take", item = key, text = "Weź 1 (administrator)", on_press = function()
			local bp = engine.optional("backpack")
			if bp then bp.give(key, 1) end
		end }
	end
	local creatures = {}
	for _, t in ipairs({ "sheep", "cow", "chicken", "horse", "zombie" }) do
		local d = engine.entities.def(t)
		if d then creatures[#creatures + 1] = { text = d.name .. (d.ai and d.ai.hostile and "  (wróg)" or ""), color = d.ai and d.ai.hostile and "#ff8a7a" or nil } end
	end
	engine.ui.window({
		id = "handbook", title = "Poradnik",
		sections = {
			{ type = "tabs", id = "tab", selected = st("tab", 1), on_change = on_change, tabs = {
				{ title = "Przedmioty", sections = {
					{ type = "row", sections = {
						{ type = "list", id = "items", items = list, selected = sel, height = 320, on_change = on_change },
						{ type = "column", sections = info },
					} },
				} },
				{ title = "Stworzenia", sections = {
					{ type = "text", text = "Stworzenia w tym świecie:" },
					{ type = "list", id = "mobs", items = creatures, height = 200 },
				} },
				{ title = "Ekran", sections = {
					{ type = "toggle", id = "compass", text = "Kompas na ekranie", value = st("compass", true), on_change = on_change },
					{ type = "slider", id = "alpha", label = "Przezroczystość kompasu", min = 0.2, max = 1, step = 0.05, value = st("compass_alpha", 1.0), on_change = on_change },
					{ type = "dropdown", id = "place", label = "Miejsce kompasu", options = { "Góra", "Lewy górny róg", "Prawy górny róg" }, selected = st("compass_place", 1), on_change = on_change },
				} },
			} },
		},
	})
end

engine.input.bind({ id = "open", key = "J", label = "Poradnik", on_press = open })

engine.on("player.join", function() compass(true) end)
engine.on("player.leave", function(e) shown[e.id] = nil end)
local t = 0
engine.on("tick", function(e)
	t = t + e.dt
	if t < 0.3 then return end
	t = 0
	engine.players.each(function() compass() end)
end)
