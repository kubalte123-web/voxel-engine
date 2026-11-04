-- Narzędzia: przedmioty i rodzaj narzędzia dla bloków (pole tool w definicji bloku).
local materials = {
	{ key = "wooden", name = "drewniany", color = "#a87a44", color2 = "#7a5630", speed = 2.0, damage = 3 },
	{ key = "stone", name = "kamienny", color = "#8a8a8e", color2 = "#66666a", speed = 4.0, damage = 4 },
	{ key = "iron", name = "żelazny", color = "#d8d8dc", color2 = "#a8a8ae", speed = 6.0, damage = 6 },
}
local kinds = {
	{ key = "pickaxe", name = "Kilof", tool = "pickaxe" },
	{ key = "axe", name = "Siekiera", tool = "axe" },
	{ key = "shovel", name = "Łopata", tool = "shovel" },
	{ key = "sword", name = "Miecz", tool = "sword" },
}
engine.items.register("stick", { name = "Patyk", icon = { pattern = "stick" } })
for _, m in ipairs(materials) do
	for _, k in ipairs(kinds) do
		local adj = m.name
		if k.key == "axe" or k.key == "shovel" then adj = adj:gsub("y$", "a") end  -- rodzaj żeński
		engine.items.register(m.key .. "_" .. k.key, {
			name = k.name .. " " .. adj,
			icon = { pattern = k.key, color = m.color, color2 = m.color2 },
			max_stack = 1,
			tool = k.tool,
			tool_speed = m.speed,
			damage = k.key == "sword" and m.damage or math.max(2, m.damage - 2),
		})
	end
end

-- który blok czym się kopie (bloki z innych modów można dopisać tak samo)
local by_tool = {
	pickaxe = { "stone", "cobblestone", "coal_ore", "iron_ore", "ruby_ore", "bricks", "ice", "lamp" },
	axe = { "log", "planks", "cactus", "crate", "barrel", "crafting_table", "workbench" },
	shovel = { "dirt", "grass", "sand", "gravel", "snow" },
}
for tool, list in pairs(by_tool) do
	for _, key in ipairs(list) do
		local b = engine.blocks.get(key)
		if b then b.tool = tool end
	end
end
