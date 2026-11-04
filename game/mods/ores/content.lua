-- Rudy i ruiny: nowe bloki, przedmioty, rudy w ziemi i struktury.
local amount = engine.settings.get("ore_amount")

-- Tekstury ze wzorów: nie trzeba rysować plików PNG.
local stone_base = { pattern = "ore", color = "#7f7f84", color2 = "#96969b" }
local function ore_texture(spots)
	local t = {}
	for k, v in pairs(stone_base) do t[k] = v end
	t.spots = spots
	return t
end

engine.blocks.register("cobblestone", {
	name = "Bruk",
	texture = { pattern = "bricks", color = "#808085", color2 = "#9a9a9f", seed = 3 },
})
engine.blocks.register("coal_ore", { name = "Ruda węgla", texture = ore_texture("#202022"), drops = "coal" })
engine.blocks.register("iron_ore", { name = "Ruda żelaza", texture = ore_texture("#c89a72"), drops = "raw_iron" })
engine.blocks.register("ruby_ore", { name = "Ruda rubinu", texture = ore_texture("#d0203a"), drops = { item = "ruby", count = 1 } })

engine.items.register("coal", { name = "Węgiel", icon = { pattern = "gem", color = "#2a2a2e", color2 = "#151517" } })
engine.items.register("raw_iron", { name = "Surowe żelazo", icon = { pattern = "ingot", color = "#c89a72", color2 = "#9a7254" } })
engine.items.register("ruby", { name = "Rubin", icon = { pattern = "gem", color = "#e0304a", color2 = "#a01828" }, max_stack = 16 })

-- Zmiana bloku z innego moda: kamień (mod base) po wykopaniu daje bruk.
if engine.settings.get("cobblestone") then
	engine.blocks.get("stone").drops = "cobblestone"
end

-- Żyły rud: chance to szansa na żyłę w każdej komórce 16x16x16, size to największy promień.
engine.worldgen.ore("coal", { block = "coal_ore", replace = "stone", min_y = -64, max_y = 40, chance = 0.7 * amount, size = 2 })
engine.worldgen.ore("iron", { block = "iron_ore", replace = "stone", min_y = -64, max_y = 20, chance = 0.45 * amount, size = 2 })
engine.worldgen.ore("ruby", { block = "ruby_ore", replace = "stone", min_y = -64, max_y = 0, chance = 0.15 * amount, size = 1 })

if engine.settings.get("ruins") then
	-- Struktura z warstw: każda warstwa to wiersze (oś z) znaków (oś x), od dołu do góry.
	-- Spacja = nic nie zmieniaj, "." = powietrze. origin przesuwa środek struktury.
	engine.worldgen.structure("ruin", {
		origin = { 2, 1, 2 },
		key = { c = "cobblestone", p = "planks", ["."] = "air" },
		layers = {
			{ "ccccc", "ccccc", "ccccc", "ccccc", "ccccc" },   -- podłoga (zagłębiona o 1 blok)
			{ "cc.cc", "c...c", "....c", "c...c", "cc.cc" },
			{ "c . c", "     ", "    c", "     ", "c   c" },
			{ "p   p", "     ", "     ", "     ", "     " },
		},
	})
	engine.worldgen.structure("well", {
		origin = { 1, 2, 1 },
		key = { c = "cobblestone", ["."] = "air", w = "glass" },
		layers = {
			{ "ccc", "c.c", "ccc" },
			{ "ccc", "c.c", "ccc" },
			{ "ccc", "c.c", "ccc" },
			{ "c c", "   ", "c c" },
			{ "ccc", "ccc", "ccc" },
		},
	})
	engine.worldgen.add_feature("meadow", { structure = "ruin", chance = 0.0004 })
	engine.worldgen.add_feature("desert", { structure = "well", chance = 0.0004 })
end
