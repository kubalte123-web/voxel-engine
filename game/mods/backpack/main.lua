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

-- Inne mody mogą dokładać sekcje do okna postaci (np. siatka rzemiosła): add_section(function() return {...} end)
local extra = {}

engine.export({
	give = give, HOTBAR = HOTBAR, BACKPACK = BACKPACK, EQUIPMENT = EQUIPMENT,
	add_section = function(fn) extra[#extra + 1] = fn end,
	open = function() open_window() end,
})

-- przy wejściu gracza do świata: jego kontenery, pasek i zestaw startowy (raz na konto)
engine.on("player.join", function()
	engine.items.container(HOTBAR, 8, true, true)
	engine.items.container(BACKPACK, rows * 9, true, true)
	engine.items.container(EQUIPMENT, 4, true, true)
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

function open_window()
	local pos = engine.player.position()
	local st = stats()
	local sections = {
		{ type = "character", lines = {
			engine.player.name(),
			string.format("Zdrowie: %d / %d", math.floor(engine.player.health() + 0.5), engine.player.max_health()),
			"Biom: " .. engine.world.biome(Vector3i(math.floor(pos.x), 0, math.floor(pos.z))),
			"Wykopane bloki: " .. string.format("%d", st.mined),
			"Postawione bloki: " .. string.format("%d", st.placed),
			creative and "Tryb kreatywny" or ("Przedmioty w plecaku: " .. string.format("%d", total(BACKPACK))),
		} },
		{ type = "slots", container = EQUIPMENT, columns = 4, title = "Wyposażenie (głowa, tułów, nogi, buty)" },
	}
	for _, fn in ipairs(extra) do
		for _, s in ipairs(fn() or {}) do sections[#sections + 1] = s end
	end
	sections[#sections + 1] = { type = "slots", container = BACKPACK, columns = 9, title = "Plecak" }
	sections[#sections + 1] = { type = "slots", container = HOTBAR, columns = 8, title = "Pasek szybkiego dostępu" }
	sections[#sections + 1] = { type = "text", text = "Kliknij, żeby wziąć stos, i kliknij inne miejsce, żeby go odłożyć. Prawy przycisk bierze połowę albo odkłada jedną sztukę." }
	engine.ui.window({ id = "character", title = "Postać i plecak", sections = sections })
end

engine.input.bind({
	id = "toggle",
	key = "E",
	label = "Plecak",
	on_press = function()
		if engine.ui.is_open("character") then engine.ui.close("character") else open_window() end
	end,
})
