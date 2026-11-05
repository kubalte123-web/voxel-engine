-- Przedmioty i jedzenie: surowa ryba, pieczona ryba, wędka
engine.items.register("raw_fish", {
	model = "fish",
	name = "Surowa ryba",
	icon = { pattern = "food", color = "#3a78d8", color2 = "#2a5c9e" },
	max_stack = 64,
	food = 2,
})

engine.items.register("cooked_fish", {
	model = "fish",
	name = "Pieczona ryba",
	icon = { pattern = "food", color = "#c8642a", color2 = "#a04a1a" },
	max_stack = 64,
	food = 6,
})

engine.items.register("fishing_rod", {
	model = "fishing_rod",
	name = "Wędka",
	icon = { pattern = "stick", color = "#8a5a2e", color2 = "#d0d0d0" },
	max_stack = 1,
})

-- Rejestracja dźwięku zarzucenia i wyciągania wędki (używamy wbudowanego pop/click)
engine.sounds.register("fishing.splash", {
	files = { "base:sounds/water_splash1.ogg", "base:sounds/water_splash2.ogg" },
	volume = 0.8,
	pitch = 1.0,
	range = 15,
})
