-- Świat podstawowy: bloki, biomy, drzewa i rośliny.
-- Ten plik jest zwykłym modem: każdy inny mod może zmienić te definicje
-- (np. engine.blocks.get("stone").texture = "...") albo dodać własne biomy.

local hill = engine.settings.get("hill_height")
local density = engine.settings.get("tree_density")
local trees = engine.settings.get("trees")
local plants = engine.settings.get("plants")

---------------------------------------------------------------------------
-- Bloki. Tekstury 16x16 w folderze textures/ moda.
---------------------------------------------------------------------------
engine.blocks.register("grass", {
	name = "Trawa",
	textures = { top = "textures/grass_top.png", side = "textures/grass_side.png", bottom = "textures/dirt.png" },
	drops = "dirt",
})
engine.blocks.register("dirt", { name = "Ziemia", texture = "textures/dirt.png" })
engine.blocks.register("stone", { name = "Kamień", texture = "textures/stone.png" })
engine.blocks.register("planks", { name = "Deski", texture = "textures/planks.png" })
engine.blocks.register("sand", { name = "Piasek", texture = "textures/sand.png" })
engine.blocks.register("log", {
	name = "Pień",
	textures = { side = "textures/log_side.png", top = "textures/log_top.png", bottom = "textures/log_top.png" },
})
engine.blocks.register("leaves", { name = "Liście", texture = "textures/leaves.png" })
engine.blocks.register("snow", { name = "Śnieg", texture = "textures/snow.png" })
engine.blocks.register("cactus", {
	name = "Kaktus",
	textures = { side = "textures/cactus_side.png", top = "textures/cactus_top.png", bottom = "textures/cactus_top.png" },
})
-- rośliny: dwie skrzyżowane ściany, bez kolizji
engine.blocks.register("tall_grass", { name = "Wysoka trawa", shape = "cross", texture = "textures/tall_grass.png", drops = false, item = false })
engine.blocks.register("flower_red", { name = "Mak", shape = "cross", texture = "textures/flower_red.png" })
engine.blocks.register("flower_yellow", { name = "Mlecz", shape = "cross", texture = "textures/flower_yellow.png" })
-- szkło: blok przezroczysty (bez ścian między sąsiednimi blokami szkła), tekstura ze wzoru
engine.blocks.register("glass", {
	name = "Szkło",
	transparent = true,
	texture = { pattern = "glass", color = "#d8eef5", color2 = "#ffffff" },
})
engine.blocks.register("bricks", {
	name = "Cegły",
	texture = { pattern = "bricks", color = "#9c4a3a", color2 = "#b0705a" },
})

---------------------------------------------------------------------------
-- Świat
---------------------------------------------------------------------------
engine.worldgen.config({ biome_scale = engine.settings.get("biome_size"), beach_height = 7 })

local function scaled(list)
	local out = {}
	for _, f in ipairs(list) do
		local c = {}
		for k, v in pairs(f) do c[k] = v end
		c.chance = (f.chance or 0) * density
		out[#out + 1] = c
	end
	return out
end

local oak = { shape = "oak", trunk = "log", leaves = "leaves", height = { 4, 6 }, radius = 2 }
local function with(t, extra) local c = {} for k, v in pairs(t) do c[k] = v end for k, v in pairs(extra) do c[k] = v end return c end

-- temperatura i wilgotność to punkt na mapie klimatu (szum od około -0.7 do 0.7);
-- każdy punkt świata dostaje biom o najbliższym klimacie
engine.worldgen.biome("meadow", {
	name = "Łąki", temperature = 0.0, humidity = -0.25,
	height = 12, hills = 9 * hill, roughness = 1.5,
	top = "grass", filler = "dirt", stone = "stone", depth = 3,
	beach = { top = "sand", filler = "sand" },
	features = trees and scaled({ with(oak, { chance = 0.004 }) }) or {},
	plants = plants and {
		{ block = "tall_grass", chance = 0.10 },
		{ block = "flower_red", chance = 0.025 },
		{ block = "flower_yellow", chance = 0.025 },
	} or {},
})

engine.worldgen.biome("forest", {
	name = "Las", temperature = 0.0, humidity = 0.4,
	height = 12, hills = 9 * hill, roughness = 1.5,
	top = "grass", filler = "dirt", stone = "stone", depth = 3,
	beach = { top = "sand", filler = "sand" },
	features = trees and scaled({ with(oak, { chance = 0.03 }) }) or {},
	plants = plants and {
		{ block = "tall_grass", chance = 0.18 },
		{ block = "flower_red", chance = 0.01 },
	} or {},
})

engine.worldgen.biome("desert", {
	name = "Pustynia", temperature = 0.55, humidity = 0.0,
	height = 12, hills = 3.6 * hill, roughness = 1.5,
	top = "sand", filler = "sand", stone = "stone", depth = 3,
	features = trees and scaled({
		{ shape = "column", trunk = "cactus", height = { 2, 3 }, chance = 0.006 },
	}) or {},
})

engine.worldgen.biome("snowy", {
	name = "Ośnieżone góry", temperature = -0.55, humidity = 0.0,
	height = 12, hills = 9 * hill, roughness = 1.5, mountains = 30 * hill,
	top = "snow", filler = "dirt", stone = "stone", depth = 3,
	peak = { height = 34, top = "snow", filler = "stone" },
	features = trees and scaled({
		{ shape = "spruce", trunk = "log", leaves = "leaves", height = { 6, 8 }, radius = 2, chance = 0.012, max_height = 33 },
	}) or {},
})
