local STONE = "#7c7c7c"
engine.blocks.register("furnace", {
	name = "Piec",
	textures = {
		front = { pattern = "furnace", color = STONE, color2 = "#1c1816" },
		side = { pattern = "speckle", color = STONE, color2 = "#6a6a6a", spots = "#5a5a5a" },
		top = { pattern = "speckle", color = "#848484", color2 = "#707070", spots = "#5e5e5e" },
	},
	-- stan lit: rozpalony piec świeci i ma żarzące się palenisko
	states = { facing = { "north", "east", "south", "west" }, lit = { false, true } },
	variant = function(s)
		if s.lit then
			return { light = 13, textures = { front = { pattern = "furnace", color = STONE, color2 = "#f08a20" } } }
		end
	end,
	hardness = 3.0,
	tool = "pickaxe",
	sound = "stone",
})

engine.items.register("iron_ingot", { name = "Sztabka żelaza", icon = { pattern = "ingot", color = "#dcdcdc", color2 = "#a8a8a8" } })
if engine.items.def("beef") then
	engine.items.register("cooked_beef", { model = "steak", name = "Pieczona wołowina", food = 8, icon = { pattern = "food", color = "#8a4a2a", color2 = "#5a2e18" } })
	engine.items.register("cooked_mutton", { model = "steak", name = "Pieczona baranina", food = 6, icon = { pattern = "food", color = "#9a5a3a", color2 = "#6a3a22" } })
	engine.items.register("cooked_chicken", { model = "drumstick", name = "Pieczony kurczak", food = 6, icon = { pattern = "food", color = "#d8a060", color2 = "#a87038" } })
end
engine.sounds.register("furnace.fire", { files = { "base:sounds/sand_step1.ogg", "base:sounds/sand_step2.ogg" }, volume = 0.25, pitch = 0.6, range = 10 })
