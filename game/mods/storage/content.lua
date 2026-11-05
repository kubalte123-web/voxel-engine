-- Stan facing: silnik obraca teksturę "front" i stawia blok przodem do gracza.
engine.blocks.register("chest", {
	name = "Skrzynia",
	textures = {
		front = { pattern = "chest", color = "#a8743c", color2 = "#94622f", spots = "#d8c040" },
		side = { pattern = "planks", color = "#9a6a38", color2 = "#b07a40" },
		top = { pattern = "planks", color = "#8a5a2e", color2 = "#a06a36" },
	},
	states = { facing = { "north", "east", "south", "west" } },
	hardness = 2.0,
	tool = "axe",
	sound = "wood",
})
engine.sounds.register("chest.open", { files = { "base:sounds/wood_break1.ogg", "base:sounds/wood_break2.ogg" }, volume = 0.6, pitch = 0.6 })
