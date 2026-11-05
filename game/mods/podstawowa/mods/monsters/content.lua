-- Zombie: model z pliku GLB (tools/make_zombie.gd), animacje z pliku według stanu stworzenia.
engine.items.register("rotten_flesh", {
	model = "steak",
	name = "Zgniłe mięso", food = 2,
	icon = { pattern = "food", color = "#7a8a4a", color2 = "#5a6a32" },
})

engine.sounds.register("zombie.groan", { files = { "animals:sounds/cow1.ogg", "animals:sounds/cow2.ogg" }, volume = 0.7, pitch = 0.45, range = 20 })
engine.sounds.register("zombie.hurt", { files = { "animals:sounds/sheep1.ogg" }, volume = 0.7, pitch = 0.5, range = 16 })

engine.particles.register("monsters.smoke", {
	amount = 10, life = 1.0, speed = { 0.3, 0.8 }, direction = { 0, 1, 0 }, spread = 25, gravity = -1.2,
	size = { 0.2, 0.5 }, color = { "#3a3a3acc", "#20202000" }, box = { 0.25, 0.5, 0.25 },
})
engine.particles.register("monsters.flame", {
	amount = 14, life = 0.5, speed = { 0.4, 1.0 }, direction = { 0, 1, 0 }, spread = 20, gravity = -2,
	size = { 0.14, 0.02 }, color = { "#fff0a0", "#ff9020", "#c03010" }, box = { 0.25, 0.6, 0.25 }, glow = true,
})

engine.entities.register("zombie", {
	name = "Zombie",
	health = 20, speed = 1.1,
	size = { 0.6, 1.9 },
	model = {
		file = "models/zombie.glb",
		-- nazwy animacji w pliku dla stanów stworzenia
		animations = { idle = "Idle", walk = "Walk", attack = "Attack", hurt = "Hurt" },
	},
	ai = {
		wander = true, swim = true, avoid_cliffs = false, think = 0.5,
		hostile = { damage = 3, range = 1.5, sight = 18, cooldown = 1.1, speed = 2.4, knockback = 4 },
	},
	drops = { { item = "rotten_flesh", count = 0, max = 2 } },
	spawn = {
		night = true, max_light = 7, group = { 1, 2 }, max = engine.settings.get("amount"),
		on = { "grass", "dirt", "sand", "snow", "stone", "gravel" },
	},
	sounds = { idle = "zombie.groan", idle_every = 10, hurt = "zombie.hurt" },
})
