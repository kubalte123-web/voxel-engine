-- Świat podstawowy: bloki, biomy, drzewa i rośliny.
-- Ten plik jest zwykłym modem: każdy inny mod może zmienić te definicje
-- (np. engine.blocks.get("stone").texture = "...") albo dodać własne biomy.

local hill = engine.settings.get("hill_height")
local density = engine.settings.get("tree_density")
local trees = engine.settings.get("trees")
local plants = engine.settings.get("plants")

---------------------------------------------------------------------------
-- Bloki. Tekstury 16x16 w folderze textures/ moda.
-- Właściwości: hardness = sekundy kopania gołą ręką, breakable = false (nie do wykopania),
-- gravity = spada bez podparcia, solid = kolizja, transparent = nie zasłania sąsiadów,
-- liquid = ciecz (opis niżej), loose = obiekt luźny (mod „Luźne przedmioty”).
---------------------------------------------------------------------------
engine.blocks.register("grass", {
	name = "Trawa",
	textures = { top = "textures/grass_top.png", side = "textures/grass_side.png", bottom = "textures/dirt.png" },
	drops = "dirt",
	hardness = 0.6,
})
engine.blocks.register("dirt", { name = "Ziemia", texture = "textures/dirt.png", hardness = 0.5 })
engine.blocks.register("stone", { name = "Kamień", texture = "textures/stone.png", hardness = 1.5 })
engine.blocks.register("planks", { name = "Deski", texture = "textures/planks.png", hardness = 1.2 })
engine.blocks.register("sand", { name = "Piasek", texture = "textures/sand.png", hardness = 0.5, gravity = true })
engine.blocks.register("log", {
	name = "Pień",
	textures = { side = "textures/log_side.png", top = "textures/log_top.png", bottom = "textures/log_top.png" },
	hardness = 1.6,
})
engine.blocks.register("leaves", { name = "Liście", texture = "textures/leaves.png", hardness = 0.2 })
engine.blocks.register("snow", { name = "Śnieg", texture = "textures/snow.png", hardness = 0.3 })
engine.blocks.register("cactus", {
	name = "Kaktus",
	textures = { side = "textures/cactus_side.png", top = "textures/cactus_top.png", bottom = "textures/cactus_top.png" },
	hardness = 0.4,
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
	hardness = 0.3,
	drops = false,
})
engine.blocks.register("bricks", {
	name = "Cegły",
	texture = { pattern = "bricks", color = "#9c4a3a", color2 = "#b0705a" },
	hardness = 2.0,
})
engine.blocks.register("gravel", {
	name = "Żwir",
	texture = { pattern = "speckle", color = "#8a8580", color2 = "#a09a94", spots = "#5e5a56" },
	hardness = 0.6,
	gravity = true,
})
engine.blocks.register("ice", {
	name = "Lód",
	transparent = true,
	texture = { pattern = "noise", color = "#a8d0f0e6", color2 = "#c4e0f8e6" },
	hardness = 0.5,
	drops = false,
})
engine.blocks.register("bedrock", {
	name = "Skała macierzysta",
	texture = { pattern = "speckle", color = "#3a3a3e", color2 = "#505056", spots = "#1e1e22" },
	breakable = false,
})

-- Woda: ciecz z 8 poziomami, która zachowuje objętość (wylana rozlewa się w kałużę i powoli wysycha).
-- Blok "water" to zbiornik (morza, jeziora): oddaje wodę bez końca. Płynące poziomy to "water~1".."water~8".
engine.blocks.register("water", {
	name = "Woda",
	item = false,
	liquid = {
		color = "#2a78c8",   -- płytka woda
		deep = "#0a2a5c",    -- głęboka woda
		foam = "#e8f4ff",
		viscosity = 1,       -- co ile kroków symulacji płynie (lawa: 4)
		push = 1.0,          -- siła prądu
	},
})

---------------------------------------------------------------------------
-- Wiadra (używane w scripts/main.lua przez hak item.use)
---------------------------------------------------------------------------
engine.items.register("bucket", { name = "Wiadro", icon = { pattern = "ingot", color = "#a8a8b0", color2 = "#78787f" }, max_stack = 16, bucket = "empty" })
engine.items.register("water_bucket", { name = "Wiadro z wodą", icon = { pattern = "ingot", color = "#3a80d0", color2 = "#78787f" }, max_stack = 1, bucket = "water" })

---------------------------------------------------------------------------
-- Świat
---------------------------------------------------------------------------
engine.worldgen.config({
	biome_scale = engine.settings.get("biome_size"),
	beach_height = 9,
	sea_level = engine.settings.get("water") and 8 or nil,   -- poniżej tej wysokości teren zalewa woda
	lakes = engine.settings.get("water") and { depth = 11, amount = 1.0 } or nil,  -- niecki jezior
	water = "water",
	caves = engine.settings.get("caves") and { tunnels = 1.0, caverns = 1.0, min_y = -56 } or nil,
})

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
	beach = { top = "gravel", filler = "gravel" },
	water_surface = "ice",
	features = trees and scaled({
		{ shape = "spruce", trunk = "log", leaves = "leaves", height = { 6, 8 }, radius = 2, chance = 0.012, max_height = 33 },
	}) or {},
})
