-- Pole uprawne: stan moist (wilgotne przy wodzie). Losowe aktualizacje co ok. 20 s sprawdzają wodę.
engine.blocks.register("farmland", {
	name = "Pole uprawne",
	textures = { top = { pattern = "furrows", color = "#6e4c2e", color2 = "#5c3f24" }, side = "base:textures/dirt.png", bottom = "base:textures/dirt.png" },
	states = { moist = { false, true } },
	variant = function(s)
		if s.moist then return { textures = { top = { pattern = "furrows", color = "#4a311b", color2 = "#3a2614" } } } end
	end,
	random_tick = 20,
	drops = "dirt",
	item = false,
	hardness = 0.6,
	sound = "dirt",
	tool = "shovel",
})

-- Pszenica: stan age 0..3 (wygląd i łup zależą od wieku).
local GREEN, RIPE = "#5aa03a", "#e0c050"
engine.blocks.register("wheat_crop", {
	name = "Pszenica",
	shape = "cross",
	states = { age = { 0, 1, 2, 3 } },
	variant = function(s)
		local ripe = s.age == 3
		local v = {
			textures = { all = { pattern = "crop", stage = s.age + 1, color = ripe and "#9a9a40" or GREEN, color2 = ripe and RIPE or "#86c454" } },
		}
		if ripe then
			v.name = "Dojrzała pszenica"
			v.drops = { { item = "wheat", count = 1 }, { item = "wheat", count = 1, chance = 0.4 }, { item = "seeds", count = 1 }, { item = "seeds", count = 1, chance = 0.6 } }
		end
		return v
	end,
	drops = "seeds",
	item = false,
	random_tick = 30,
	hardness = 0,
	sound = "leaves",
})

engine.items.register("seeds", { name = "Nasiona pszenicy", icon = { pattern = "seeds", color = "#d8c070", color2 = "#9a8440" } })
if not engine.items.def("wheat") then
	engine.items.register("wheat", { name = "Pszenica", icon = { pattern = "plant", color = "#e0c050", color2 = "#b89a30" } })
end
engine.items.register("wooden_hoe", { name = "Drewniana motyka", hoe = true, max_stack = 1, icon = { pattern = "hoe", color = "#a8743c", color2 = "#7a5228" } })
engine.items.register("stone_hoe", { name = "Kamienna motyka", hoe = true, max_stack = 1, icon = { pattern = "hoe", color = "#8a8a8a", color2 = "#666666" } })

-- nasiona wypadają z wysokiej trawy (obok pszenicy z moda animals)
local tg = engine.blocks.get("tall_grass")
if tg then
	local drops = type(tg.drops) == "table" and tg.drops or {}
	if drops.item then drops = { drops } end
	drops[#drops + 1] = { item = "seeds", count = 1, chance = 0.15 }
	tg.drops = drops
end
