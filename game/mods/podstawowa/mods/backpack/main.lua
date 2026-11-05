-- Plecak i postać: ekwipunek każdego gracza, pasek z kontenera i okno postaci.
-- W grze wieloosobowej każdy gracz (konto) ma własny pasek, plecak i wyposażenie.
local kit = engine.require("modkit")

local HOTBAR = "hotbar"
local BACKPACK = "backpack"
local EQUIPMENT = "equipment"

local creative = engine.settings.get("creative")
local rows = engine.settings.get("rows")

-- dodaje przedmioty do paska, a gdy się nie mieszczą, do plecaka (bieżącego gracza); zwraca resztę
local function give(item, count)
	local left = kit.inventory.add_many({ HOTBAR, BACKPACK }, item, count)
	if left > 0 then engine.ui.notify("Plecak jest pełny") end
	return left
end

-- Inne mody mogą dokładać sekcje do okna postaci: add_section(fn) – prawa kolumna obok postaci
-- (np. siatka rzemiosła 2×2), add_side(fn) – panel z lewej strony okna (np. księga przepisów, gdy otwarta).
-- fn() zwraca listę sekcji (albo nil).
local extra = {}
local side = {}

-- miejsca wyposażenia: głowa, tułów, nogi, buty, lewa ręka
local EQUIP_HINTS = { "Głowa", "Tułów", "Nogi", "Buty", "Lewa ręka" }

engine.export({
	give = give, HOTBAR = HOTBAR, BACKPACK = BACKPACK, EQUIPMENT = EQUIPMENT,
	add_section = function(fn) extra[#extra + 1] = fn end,
	add_side = function(fn) side[#side + 1] = fn end,
	open = function() open_window() end,
})

-- przy wejściu gracza do świata: jego kontenery, pasek i zestaw startowy (raz na konto)
engine.on("player.join", function()
	engine.items.container(HOTBAR, 8, true, true)
	engine.items.container(BACKPACK, rows * 9, true, true)
	engine.items.container(EQUIPMENT, #EQUIP_HINTS, true, true)
	if not creative then engine.hotbar.bind(HOTBAR, 1, 8) end
	if engine.settings.get("starter") and not engine.player.storage.get("started", false) then
		kit.inventory.add(HOTBAR, "planks", 32)
		kit.inventory.add(HOTBAR, "stone", 16)
		kit.inventory.add(BACKPACK, "torch", 32)
		engine.player.storage.set("started", true)
	end
end, 100)

-- przedmioty leżące na ziemi i podnoszone obiekty trafiają do plecaka gracza, który je podniósł
engine.hooks.before("item.pickup", function(ctx)
	local left = kit.inventory.add_many({ HOTBAR, BACKPACK }, ctx.item, ctx.count, ctx.data)
	ctx.taken = ctx.count - left
end)

-- trawa daje ziemię (tak opisuje ją mod base); ustawienie pozwala to wyłączyć
engine.hooks.before("block.break", function(ctx)
	if engine.blocks.key(ctx.block) == "grass" and not engine.settings.get("grass_drops_dirt") then
		ctx.drops = { { item = "grass", count = 1 } }
	end
end)

local function stats() return engine.player.storage.get("stats", { mined = 0, placed = 0 }) end

engine.hooks.after("block.break", function(ctx)
	local st = stats()
	st.mined = st.mined + 1
	engine.player.storage.set("stats", st)
	if creative then return end
	for _, d in ipairs(ctx.drops or {}) do give(d.item, d.count) end
	if engine.ui.is_open("character") then open_window() end
end)

-- przed postawieniem: czy na wybranym miejscu paska jest przedmiot
engine.hooks.before("block.place", function(ctx)
	if creative then return end
	local slot = engine.items.get(HOTBAR, ctx.slot)
	if slot.item == nil or slot.count <= 0 then
		ctx.cancel = true
	end
end)

engine.hooks.after("block.place", function(ctx)
	local st = stats()
	st.placed = st.placed + 1
	engine.player.storage.set("stats", st)
	if not creative then kit.inventory.take(HOTBAR, ctx.slot, 1) end
end)

local function total(container)
	local n = 0
	for i = 1, engine.items.size(container) do n = n + (engine.items.get(container, i).count or 0) end
	return n
end

-- Okno jak w MC, całe widoczne bez przewijania: u góry wyposażenie z lewej, postać, z prawej rzemiosło
-- (sekcje innych modów); niżej plecak, na dole pasek. Panel boczny (np. księga przepisów) z lewej.
local CELL = 46

function open_window()
	local pos = engine.player.position()
	local st = stats()
	local right = {}
	for _, fn in ipairs(extra) do
		for _, s in ipairs(fn() or {}) do right[#right + 1] = s end
	end
	local info = string.format("%s · zdrowie %d/%d · %s · wykopane %d · postawione %d", engine.player.name(),
		math.floor(engine.player.health() + 0.5), engine.player.max_health(),
		engine.world.biome(Vector3i(math.floor(pos.x), 0, math.floor(pos.z))), st.mined, st.placed)
	if creative then info = info .. " · tryb kreatywny" end
	local main = {
		{ type = "row", wrap = false, gap = 14, sections = {
			{ type = "slots", container = EQUIPMENT, columns = 1, cell = CELL - 6, hints = EQUIP_HINTS, expand = false },
			{ type = "character", width = 150, height = (CELL - 2) * #EQUIP_HINTS, expand = false },
			{ type = "column", gap = 6, sections = right },
		} },
		{ type = "slots", container = BACKPACK, columns = 9, cell = CELL },
		{ type = "slots", container = HOTBAR, columns = 8, cell = CELL },
		{ type = "text", size = 13, color = "#9aa4b2", text = info },
	}
	local left = {}
	for _, fn in ipairs(side) do
		for _, s in ipairs(fn() or {}) do left[#left + 1] = s end
	end
	local sections = main
	if #left > 0 then
		sections = { { type = "row", wrap = false, gap = 18, sections = {
			{ type = "column", gap = 6, sections = left, expand = false },
			{ type = "column", gap = 8, sections = main, expand = false },
		} } }
	end
	engine.ui.window({ id = "character", title = "Ekwipunek", fit = true, sections = sections })
end

engine.input.bind({
	id = "toggle",
	key = "E",
	label = "Plecak",
	on_press = function()
		if engine.ui.is_open("character") then engine.ui.close("character") else open_window() end
	end,
})
