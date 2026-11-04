-- Plecak i postać: ekwipunek, pasek z kontenera i okno postaci.
local kit = engine.require("modkit")

local HOTBAR = "hotbar"
local BACKPACK = "backpack"
local EQUIPMENT = "equipment"

local creative = engine.settings.get("creative")
local rows = engine.settings.get("rows")

engine.items.container(HOTBAR, 8)
engine.items.container(BACKPACK, rows * 9)
engine.items.container(EQUIPMENT, 4)

if not creative then
	engine.hotbar.bind(HOTBAR, 1, 8)
end

local stats = engine.storage.get("stats", { mined = 0, placed = 0 })

if engine.settings.get("starter") and not engine.storage.get("started", false) then
	kit.inventory.add(HOTBAR, engine.blocks.id("planks"), 32)
	kit.inventory.add(HOTBAR, engine.blocks.id("stone"), 16)
	engine.storage.set("started", true)
end

-- co wypada z bloku
local function drop_of(block)
	local key = engine.blocks.key(block)
	if key == "tall_grass" then return nil end
	if key == "grass" and engine.settings.get("grass_drops_dirt") then return engine.blocks.id("dirt") end
	return block
end

engine.hooks.after("block.break", function(ctx)
	stats.mined = stats.mined + 1
	engine.storage.set("stats", stats)
	if creative then return end
	local drop = drop_of(ctx.block)
	if drop then
		local left = kit.inventory.add_many({ HOTBAR, BACKPACK }, drop, 1)
		if left > 0 then engine.ui.notify("Plecak jest pełny") end
	end
	if engine.ui.is_open("character") then open_window() end
end)

-- przed postawieniem: czy na wybranym miejscu paska jest blok
engine.hooks.before("block.place", function(ctx)
	if creative then return end
	local slot = engine.items.get(HOTBAR, ctx.slot)
	if slot.block == nil or slot.count <= 0 then
		ctx.cancel = true
	end
end)

engine.hooks.after("block.place", function(ctx)
	stats.placed = stats.placed + 1
	engine.storage.set("stats", stats)
	if not creative then kit.inventory.take(HOTBAR, ctx.slot, 1) end
end)

function open_window()
	local pos = engine.player.position()
	engine.ui.window({
		id = "character",
		title = "Postać i plecak",
		sections = {
			{ type = "character", lines = {
				"Wędrowiec",
				"Biom: " .. engine.world.biome(Vector3i(math.floor(pos.x), 0, math.floor(pos.z))),
				"Wykopane bloki: " .. string.format("%d", stats.mined),
				"Postawione bloki: " .. string.format("%d", stats.placed),
				creative and "Tryb kreatywny" or ("Bloki w plecaku: " .. string.format("%d", (function()
					local n = 0
					for i = 1, engine.items.size(BACKPACK) do n = n + (engine.items.get(BACKPACK, i).count or 0) end
					return n
				end)())),
			} },
			{ type = "slots", container = EQUIPMENT, columns = 4, title = "Wyposażenie (głowa, tułów, nogi, buty)" },
			{ type = "slots", container = BACKPACK, columns = 9, title = "Plecak" },
			{ type = "slots", container = HOTBAR, columns = 8, title = "Pasek szybkiego dostępu" },
			{ type = "text", text = "Kliknij, żeby wziąć stos, i kliknij inne miejsce, żeby go odłożyć. Prawy przycisk bierze połowę albo odkłada jedną sztukę." },
		},
	})
end

engine.input.bind({
	id = "toggle",
	key = "E",
	label = "Plecak",
	on_press = function()
		if engine.ui.is_open("character") then engine.ui.close("character") else open_window() end
	end,
})
