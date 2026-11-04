-- Luźne przedmioty: blok z polem `loose` nie trafia do siatki świata, tylko staje się obiektem fizycznym.
-- loose = { shape = "box" | "ball" | "cylinder", size, mass, density (< 1 pływa), bounce, friction }
engine.blocks.register("crate", {
	name = "Skrzynia",
	texture = { pattern = "planks", color = "#a8783e", color2 = "#c08a4a" },
	loose = { shape = "box", size = 0.9, mass = 8, density = 0.55, friction = 0.9 },
})
engine.blocks.register("barrel", {
	name = "Beczka",
	texture = { pattern = "stripes", color = "#8a5a2e", color2 = "#6e4422" },
	loose = { shape = "cylinder", size = 0.9, mass = 12, density = 0.65, friction = 0.6 },
})
engine.blocks.register("ball", {
	name = "Piłka",
	texture = { pattern = "stripes", color = "#e04030", color2 = "#f4f0e8" },
	loose = { shape = "ball", size = 0.6, mass = 1.5, density = 0.25, bounce = 0.7, friction = 0.5 },
})
engine.blocks.register("boulder", {
	name = "Głaz",
	texture = { pattern = "speckle", color = "#8a8a8e", color2 = "#a0a0a4", spots = "#6a6a6e" },
	loose = { shape = "ball", size = 0.95, mass = 60, density = 2.6, bounce = 0.05, friction = 0.9 },
})

-- Flaga luźności dla zwykłych bloków wybranych w ustawieniach (drewno pływa, reszta tonie).
local floaty = { planks = 0.6, log = 0.7, leaves = 0.3, cactus = 0.8, snow = 0.9, ice = 0.9 }
local chosen = engine.settings.get("loose_blocks") or {}
for key, on in pairs(chosen) do
	local b = engine.blocks.get(key)
	if on and b and not b.liquid and b.shape ~= "cross" then
		b.loose = { shape = "box", size = 0.95, mass = 10, density = floaty[key] or 1.8 }
	end
end
