-- Skrzynia: kontener przypisany do bloku (engine.blocks.container) – silnik zapisuje go ze światem,
-- a po zniszczeniu bloku przedmioty wypadają.
local backpack = engine.require("backpack")
local SIZE = 27

engine.hooks.before("block.use", function(ctx)
	if engine.blocks.base(ctx.block) ~= "chest" then return end
	ctx.cancel = true
	local c = engine.blocks.container(ctx.pos, SIZE)
	engine.sound.play("chest.open", { pos = ctx.pos })
	engine.ui.window({
		id = "chest",
		title = "Skrzynia",
		sections = {
			{ type = "slots", container = c, columns = 9, title = "Skrzynia" },
			{ type = "slots", container = backpack.BACKPACK, columns = 9, title = "Plecak" },
			{ type = "slots", container = backpack.HOTBAR, columns = 8, title = "Pasek" },
		},
	})
end)

local classic = engine.optional("crafting_classic")
if classic then classic.shaped({ "PPP", "P P", "PPP" }, { P = "planks" }, "chest") end
local discovery = engine.optional("crafting_discovery")
if discovery then discovery.add("skrzynia", { planks = 8 }, "chest", 1, 4) end

-- zestaw na start (raz na konto; wyłączany w ustawieniach moda)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("started", false) then return end
	local bp = engine.require("backpack")
	if engine.items.def("chest") then bp.give("chest", 2) end
	engine.player.storage.set("started", true)
end)
