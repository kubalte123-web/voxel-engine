-- Zbroja: przedmioty. Pole armor = { slot, points, look }:
--   slot: "head" | "chest" | "legs" | "feet" | "offhand" (miejsce w oknie ekwipunku),
--   points: punkty ochrony (każdy punkt zmniejsza obrażenia, ustawienie moda),
--   look: wygląd na postaci – kolor materiału, kolor wykończenia i faktura klocków.
-- Model przedmiotu (slot, ręka, ziemia): wbudowane modele helmet, chestplate, leggings, boots, shield.
local MATERIALS = {
	{ key = "leather", name = "skórzan", color = "#8a5a32", trim = "#5a3a1e", tex = "leather", points = { 1, 3, 2, 1 } },
	{ key = "iron", name = "żelazn", color = "#d2d2d8", trim = "#8a8a92", tex = "metal", points = { 2, 6, 5, 2 } },
}
local PIECES = {
	{ key = "helmet", slot = "head", name = "Hełm", gender = "y" },
	{ key = "chestplate", slot = "chest", name = "Napierśnik", gender = "y" },
	{ key = "leggings", slot = "legs", name = "Nogawice", gender = "e" },
	{ key = "boots", slot = "feet", name = "Buty", gender = "e" },
}

for _, m in ipairs(MATERIALS) do
	for i, p in ipairs(PIECES) do
		local key = m.key .. "_" .. p.key
		engine.items.register(key, {
			name = p.name .. " " .. m.name .. p.gender,
			model = p.key,
			model_colors = { m.color, m.trim },
			icon = { pattern = "ingot", color = m.color, color2 = m.trim },
			max_stack = 1,
			armor = { slot = p.slot, points = m.points[i], look = { color = m.color, trim = m.trim, tex = m.tex } },
			tooltip = { category = "Zbroja", lines = { "Ochrona: +" .. m.points[i] } },
		})
	end
end

engine.items.register("wooden_shield", {
	name = "Tarcza drewniana",
	model = "shield",
	model_colors = { "#9a6a38", "#6a6a72" },
	icon = { pattern = "planks", color = "#9a6a38", color2 = "#6a6a72" },
	max_stack = 1,
	armor = { slot = "offhand", points = 1, look = { color = "#9a6a38", trim = "#6a6a72", tex = "twill" } },
	tooltip = { category = "Zbroja", lines = { "Ochrona: +1", "Na lewą rękę" } },
})
