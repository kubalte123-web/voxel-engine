-- Alchemia: kocioł z modelem (plik GLB z „Blendera” + części z klocków), animacje, cząsteczki, mikstury.

---------------------------------------------------------------------------
-- Cząsteczki (opis efektów; silnik odtwarza je u graczy w pobliżu)
---------------------------------------------------------------------------
engine.particles.register("alchemy.fire", {
	amount = 22, life = 0.55, speed = { 0.2, 0.6 }, direction = { 0, 1, 0 }, spread = 12, gravity = -1.6,
	size = { 0.16, 0.03 }, color = { "#fff2a0", "#ffb030", "#e04010" }, box = { 0.16, 0.02, 0.16 }, glow = true,
})
engine.particles.register("alchemy.ember", {
	amount = 4, life = 1.4, speed = { 0.4, 1.2 }, direction = { 0, 1, 0 }, spread = 35, gravity = -0.4,
	size = 0.035, color = { "#ffd060", "#ff6010" }, box = { 0.15, 0, 0.15 }, glow = true, shape = "square",
})
engine.particles.register("alchemy.bubble", {
	amount = 7, life = 0.9, speed = { 0.05, 0.25 }, direction = { 0, 1, 0 }, spread = 10, gravity = -0.15,
	size = { 0.05, 0.09 }, color = { "#ffffff" }, box = { 0.27, 0, 0.27 },
})
engine.particles.register("alchemy.steam", {
	amount = 3, life = 2.4, speed = { 0.15, 0.35 }, direction = { 0, 1, 0 }, spread = 18, gravity = -0.25,
	size = { 0.18, 0.6 }, color = { "#ffffff80", "#ffffff00" }, box = { 0.22, 0, 0.22 }, damping = 0.2,
})
engine.particles.register("alchemy.glint", {
	amount = 5, life = 1.2, speed = { 0.1, 0.4 }, direction = { 0, 1, 0 }, spread = 40, gravity = -0.3,
	size = { 0.07, 0.01 }, color = { "#ffffff" }, box = { 0.25, 0, 0.25 }, glow = true, shape = "spark",
})
engine.particles.register("alchemy.splash", {
	amount = 16, life = 0.6, speed = { 1.0, 2.2 }, direction = { 0, 1, 0 }, spread = 40, gravity = 7,
	size = 0.06, color = { "#4a8ae0" }, box = { 0.1, 0, 0.1 },
})
engine.particles.register("alchemy.sparkle", {
	amount = 40, life = 1.3, speed = { 0.6, 1.8 }, direction = { 0, 1, 0 }, spread = 70, gravity = -0.2,
	size = { 0.09, 0.01 }, color = { "#fff6c0", "#ffffff" }, box = { 0.2, 0, 0.2 }, glow = true, shape = "spark", damping = 1.0,
})
engine.particles.register("alchemy.smoke", {
	amount = 30, life = 1.8, speed = { 0.4, 1.2 }, direction = { 0, 1, 0 }, spread = 50, gravity = -0.6,
	size = { 0.25, 0.8 }, color = { "#3a3a3a", "#5a5a5acc", "#80808000" }, box = { 0.2, 0, 0.2 }, damping = 0.6,
})
engine.particles.register("alchemy.drink", {
	amount = 30, life = 1.1, speed = { 0.4, 1.0 }, direction = { 0, 1, 0 }, spread = 180, gravity = -0.8,
	size = { 0.08, 0.02 }, color = { "#ffffff" }, box = { 0.35, 0.6, 0.35 }, glow = true, shape = "spark",
})

---------------------------------------------------------------------------
-- Dźwięki
---------------------------------------------------------------------------
engine.sounds.register("alchemy.bubbling", { file = "sounds/bubbling.ogg", volume = 0.45, range = 14, pitch_random = 0 })
engine.sounds.register("alchemy.plop", { file = "sounds/plop.ogg", volume = 0.8 })
engine.sounds.register("alchemy.done", { file = "sounds/chime.ogg", volume = 0.7, range = 20, pitch_random = 0 })
engine.sounds.register("alchemy.fail", { file = "sounds/poof.ogg", volume = 0.9 })
engine.sounds.register("alchemy.drink", { file = "sounds/drink.ogg", volume = 0.8 })
engine.sounds.register("alchemy.fill", { file = "sounds/fill.ogg", volume = 0.7 })

---------------------------------------------------------------------------
-- Kocioł: model z pliku GLB (pot, band, handle_l/r, liquid) + części z klocków (nóżki, ognisko, chochla)
---------------------------------------------------------------------------
local IRON, DARK, STONE, WOOD = "#3a3a42", "#26262c", "#7a7670", "#6a4424"
local function stone(x, z, s) return { size = { s, 0.09, s * 0.9 }, pos = { x, 0.045, z }, color = STONE } end

engine.blocks.register("cauldron", {
	name = "Kocioł alchemiczny",
	shape = "model",
	icon = { pattern = "cauldron", color = "#3a3a42", color2 = "#5a9ae8" },
	hardness = 3.0,
	tool = "pickaxe",
	sound = "stone",
	transparent = true,
	states = { content = { "empty", "water", "brewing", "ready" } },
	variant = function(s)
		if s.content == "water" then
			return { look = { hide = { "embers", "flame" } } }
		elseif s.content == "brewing" then
			return { light = 11, look = { anim = "stir", hide = {}, emitters = { "fire", "sparks", "bubbles", "steam" } } }
		elseif s.content == "ready" then
			return { light = 7, look = { hide = { "flame" }, emitters = { "glint", "steam" } } }
		end
	end,
	model = {
		file = "models/cauldron.glb",
		parts = {
			-- trójnóg i obręcz pod kotłem
			legs = { boxes = {
				{ size = { 0.06, 0.3, 0.06 }, pos = { 0, 0.14, -0.36 }, rot = { -14, 0, 0 }, color = DARK },
				{ size = { 0.06, 0.3, 0.06 }, pos = { 0.31, 0.14, 0.18 }, rot = { 7, 0, -12 }, color = DARK },
				{ size = { 0.06, 0.3, 0.06 }, pos = { -0.31, 0.14, 0.18 }, rot = { 7, 0, 12 }, color = DARK },
				{ size = { 0.05, 0.04, 0.05 }, pos = { 0, 0.02, -0.4 }, color = IRON },
				{ size = { 0.05, 0.04, 0.05 }, pos = { 0.35, 0.02, 0.2 }, color = IRON },
				{ size = { 0.05, 0.04, 0.05 }, pos = { -0.35, 0.02, 0.2 }, color = IRON },
			} },
			-- ognisko: krąg kamieni, polana, żar (tag „embers” świeci) i płomień
			firepit = { boxes = {
				stone(0.27, 0, 0.11), stone(-0.27, 0, 0.12), stone(0, 0.27, 0.1), stone(0, -0.27, 0.12),
				stone(0.19, 0.19, 0.1), stone(-0.19, 0.19, 0.11), stone(0.19, -0.19, 0.09), stone(-0.19, -0.19, 0.1),
				{ size = { 0.4, 0.07, 0.08 }, pos = { 0, 0.05, 0 }, rot = { 0, 35, 0 }, color = WOOD },
				{ size = { 0.4, 0.07, 0.08 }, pos = { 0, 0.07, 0 }, rot = { 0, -40, 0 }, color = "#5a3a1c" },
				{ size = { 0.18, 0.03, 0.18 }, pos = { 0, 0.03, 0 }, color = "#ff7a20", tag = "embers", glow = true },
				{ size = { 0.06, 0.035, 0.06 }, pos = { 0.1, 0.1, 0.05 }, color = "#ffb040", tag = "embers", glow = true },
				{ size = { 0.05, 0.035, 0.05 }, pos = { -0.08, 0.11, -0.06 }, color = "#ffb040", tag = "embers", glow = true },
			} },
			flame = { pivot = { 0, 0.08, 0 }, boxes = {
				{ size = { 0.12, 0.14, 0.12 }, pos = { 0, 0.07, 0 }, rot = { 0, 45, 0 }, color = "#ffcf50", tag = "flame", glow = true },
				{ size = { 0.07, 0.1, 0.07 }, pos = { 0.05, 0.1, -0.03 }, color = "#fff2a0", tag = "flame", glow = true },
			} },
			-- chochla: obraca się wokół środka kotła
			ladle = { pivot = { 0, 0.72, 0 }, boxes = {
				{ size = { 0.035, 0.62, 0.035 }, pos = { 0.17, 0.2, 0 }, rot = { 0, 0, -22 }, color = WOOD },
				{ size = { 0.05, 0.05, 0.05 }, pos = { 0.29, 0.49, 0 }, color = "#4a2e18" },
				{ size = { 0.12, 0.04, 0.1 }, pos = { 0.07, -0.08, 0 }, color = "#7a5030" },
			} },
		},
		animations = {
			stir = { length = 2.4, loop = true, tracks = {
				ladle = { { 0, rot = { 0, 0, 0 } }, { 0.6, rot = { 4, 90, 0 } }, { 1.2, rot = { 0, 180, 0 } }, { 1.8, rot = { -4, 270, 0 } }, { 2.4, rot = { 0, 360, 0 } } },
				liquid = { { 0, pos = { 0, 0, 0 } }, { 0.6, pos = { 0, 0.008, 0 } }, { 1.2, pos = { 0, 0, 0 } }, { 1.8, pos = { 0, 0.008, 0 } }, { 2.4, pos = { 0, 0, 0 } } },
				flame = { { 0, scale = { 1, 1, 1 } }, { 0.3, scale = { 1.15, 1.4, 1.15 } }, { 0.7, scale = { 0.9, 0.85, 0.9 } }, { 1.1, scale = { 1.1, 1.3, 1.1 } }, { 1.6, scale = { 0.95, 0.9, 0.95 } }, { 2.4, scale = { 1, 1, 1 } } },
			} },
			plop = { length = 0.6, tracks = {
				liquid = { { 0, pos = { 0, 0, 0 } }, { 0.1, pos = { 0, -0.03, 0 } }, { 0.25, pos = { 0, 0.025, 0 } }, { 0.45, pos = { 0, -0.008, 0 } }, { 0.6, pos = { 0, 0, 0 } } },
				ladle = { { 0, rot = { 0, 0, 0 } }, { 0.15, rot = { 0, 0, 8 } }, { 0.35, rot = { 0, 0, -6 } }, { 0.6, rot = { 0, 0, 0 } } },
			} },
			done = { length = 1.0, tracks = {
				ladle = { { 0, pos = { 0, 0, 0 } }, { 0.3, pos = { 0, 0.12, 0 }, rot = { 0, 0, -10 } }, { 0.7, pos = { 0, 0.12, 0 }, rot = { 0, 30, -10 } }, { 1.0, pos = { 0, 0, 0 } } },
				pot = { { 0, scale = { 1, 1, 1 } }, { 0.15, scale = { 1.04, 0.97, 1.04 } }, { 0.35, scale = { 0.98, 1.02, 0.98 } }, { 0.6, scale = { 1, 1, 1 } } },
			} },
		},
		emitters = {
			fire = { particle = "alchemy.fire", pos = { 0, 0.08, 0 } },
			sparks = { particle = "alchemy.ember", pos = { 0, 0.12, 0 } },
			bubbles = { particle = "alchemy.bubble", pos = { 0, 0.73, 0 }, color_from = "liquid" },
			steam = { particle = "alchemy.steam", pos = { 0, 0.85, 0 } },
			glint = { particle = "alchemy.glint", pos = { 0, 0.76, 0 }, color_from = "liquid" },
		},
		collision = { { min = { 0.06, 0, 0.06 }, max = { 0.94, 0.87, 0.94 } } },
		look = { hide = { "liquid", "embers", "flame" }, colors = { liquid = "#3a78d8" } },
	},
})

---------------------------------------------------------------------------
-- Butelki i mikstury
---------------------------------------------------------------------------
engine.items.register("glass_bottle", { name = "Pusta butelka", icon = { pattern = "potion", color = "#00000000", color2 = "#c8e4f0" } })

local POTIONS = {
	{ "speed", "Mikstura szybkości", "#40c8f0" },
	{ "jump", "Mikstura skoku", "#70e060" },
	{ "feather", "Mikstura lekkości", "#e8e8ff" },
	{ "heal", "Mikstura leczenia", "#f04060" },
}
for _, p in ipairs(POTIONS) do
	engine.items.register("potion_" .. p[1], { name = p[2], potion = p[1], max_stack = 8,
		icon = { pattern = "potion", color = p[3], color2 = "#c8e4f0" } })
	engine.items.register("potion_" .. p[1] .. "_strong", { name = p[2] .. " (mocna)", potion = p[1], strong = true, max_stack = 8,
		icon = { pattern = "potion", color = p[3], color2 = "#f0d060" } })
end
