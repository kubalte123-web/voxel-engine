-- Zwierzęta: modele z klocków, AI, łup i pojawianie się.
-- Model to części z punktem obrotu (pivot) i klockami (boxes). Klocek: size, pos (względem punktu obrotu),
-- color, opcjonalnie tag (np. "wool" – mod może go ukryć albo przekolorować).
-- swing = 1 / -1: noga kołysze się przy chodzie; wing = 1 / -1: skrzydło trzepocze w locie;
-- look = true: głowa patrzy na gracza i schyla się przy skubaniu.
local amount = engine.settings.get("amount")

-- Klocek może mieć tex = faktura powierzchni (fur, wool, hide, feathers, leather, hair…), domyślnie
-- `surface` stworzenia; drobne klocki (oczy, nozdrza) są bez faktury.
local function leg(x, y, z, swing, color, hoof, w, h, sock)
	w = w or 0.16
	h = h or 0.42
	local boxes = {
		{ size = { w, h, w }, pos = { 0, -h / 2, 0 }, color = color },
		{ size = { w + 0.01, 0.08, w + 0.01 }, pos = { 0, -h + 0.04, 0 }, color = hoof, tex = "leather" },
	}
	if sock then   -- wełniana „nogawka” owcy
		boxes[#boxes + 1] = { size = { w + 0.06, h * 0.45, w + 0.06 }, pos = { 0, -h * 0.2, 0 }, color = sock, tag = "wool", tex = "wool" }
	end
	return { pivot = { x, y, z }, swing = swing, boxes = boxes }
end

local function eyes(z, y, dx)
	return
		{ size = { 0.06, 0.06, 0.02 }, pos = { -dx, y, z }, color = "#1a1a1e" },
		{ size = { 0.06, 0.06, 0.02 }, pos = { dx, y, z }, color = "#1a1a1e" }
end

---------------------------------------------------------------------------
-- Przedmioty
---------------------------------------------------------------------------
engine.items.register("wool", { model = "wool", name = "Wełna", icon = { pattern = "noise", color = "#efeee8", color2 = "#d8d6cc" } })
engine.items.register("mutton", { model = "steak", name = "Surowa baranina", icon = { pattern = "food", color = "#d06a5a", color2 = "#a04a3a" }, food = 3 })
engine.items.register("beef", { model = "steak", name = "Surowa wołowina", icon = { pattern = "food", color = "#c04a3a", color2 = "#8a2a20" }, food = 3 })
engine.items.register("chicken_meat", { model = "drumstick", name = "Surowy kurczak", icon = { pattern = "food", color = "#f0c0a8", color2 = "#d09a80" }, food = 2 })
engine.items.register("leather", { model = "leather", name = "Skóra", icon = { pattern = "ingot", color = "#8a5a32", color2 = "#6a4022" } })
engine.items.register("feather", { model = "feather", name = "Pióro", icon = { pattern = "plant", color = "#f4f4f0", color2 = "#d0d0c8" } })
engine.items.register("egg", { model = "egg", name = "Jajko", icon = { pattern = "food", color = "#efe2c8", color2 = "#d8c8a8" }, food = 2, max_stack = 16 })
engine.items.register("wheat", { name = "Pszenica", icon = { pattern = "plant", color = "#d8b450", color2 = "#b8943a" } })
engine.items.register("shears", { model = "shears", name = "Nożyce", icon = { pattern = "ingot", color = "#c8c8d0", color2 = "#8a8a94" }, max_stack = 1 })
engine.items.register("milk_bucket", { model = "bucket", name = "Wiadro mleka", icon = { pattern = "ingot", color = "#f4f4f4", color2 = "#78787f" }, max_stack = 1, food = 6 })

-- pszenica wypada czasem z wysokiej trawy (zmiana bloku moda base)
engine.blocks.get("tall_grass").drops = { { item = "wheat", count = 1, chance = 0.12 } }

---------------------------------------------------------------------------
-- Owca
---------------------------------------------------------------------------
local WOOL = "#eceae2"
local WOOL2 = "#f4f2ec"
local FACE = "#dccdbd"
engine.entities.register("sheep", {
	name = "Owca",
	health = 8, speed = 1.1, panic_speed = 2.8,
	size = { 0.85, 1.2 },
	surface = "hide",
	parts = {
		body = { pivot = { 0, 0.62, 0 }, boxes = {
			{ size = { 0.6, 0.46, 0.86 }, pos = { 0, 0.1, 0 }, color = "#d8c8b8" },
			-- runo: bryła i kłębki na wierzchu, bokach, z przodu i z tyłu (nieregularny obrys)
			{ size = { 0.74, 0.58, 1.02 }, pos = { 0, 0.12, 0 }, color = WOOL, tag = "wool", tex = "wool" },
			{ size = { 0.56, 0.1, 0.78 }, pos = { 0.02, 0.44, 0.02 }, color = WOOL2, tag = "wool", tex = "wool" },
			{ size = { 0.3, 0.08, 0.32 }, pos = { -0.12, 0.5, -0.2 }, color = WOOL, tag = "wool", tex = "wool" },
			{ size = { 0.28, 0.08, 0.3 }, pos = { 0.14, 0.5, 0.22 }, color = WOOL2, tag = "wool", tex = "wool" },
			{ size = { 0.08, 0.38, 0.62 }, pos = { -0.4, 0.1, 0.04 }, color = WOOL2, tag = "wool", tex = "wool" },
			{ size = { 0.08, 0.36, 0.58 }, pos = { 0.4, 0.12, -0.02 }, color = WOOL2, tag = "wool", tex = "wool" },
			{ size = { 0.56, 0.42, 0.08 }, pos = { 0, 0.12, 0.54 }, color = WOOL2, tag = "wool", tex = "wool" },
			{ size = { 0.5, 0.4, 0.08 }, pos = { 0, 0.1, -0.54 }, color = WOOL2, tag = "wool", tex = "wool" },
			{ size = { 0.16, 0.16, 0.1 }, pos = { 0, 0.26, 0.6 }, color = WOOL, tag = "wool", tex = "wool" },
		} },
		head = { parent = "body", pivot = { 0, 0.3, -0.5 }, look = true, boxes = {
			{ size = { 0.32, 0.34, 0.4 }, pos = { 0, 0.02, -0.18 }, color = FACE },
			{ size = { 0.24, 0.18, 0.08 }, pos = { 0, -0.07, -0.4 }, color = "#c8b6a4" },
			{ size = { 0.42, 0.18, 0.3 }, pos = { 0, 0.21, -0.08 }, color = WOOL, tag = "wool", tex = "wool" },
			{ size = { 0.2, 0.08, 0.12 }, pos = { 0, 0.2, -0.3 }, color = WOOL2, tag = "wool", tex = "wool" },
			{ size = { 0.16, 0.07, 0.1 }, pos = { -0.23, 0.08, -0.1 }, color = "#c8b8a8", rot = { 0, 0, 20 } },
			{ size = { 0.16, 0.07, 0.1 }, pos = { 0.23, 0.08, -0.1 }, color = "#c8b8a8", rot = { 0, 0, -20 } },
			{ size = { 0.04, 0.03, 0.02 }, pos = { -0.05, -0.04, -0.445 }, color = "#6a5446" },
			{ size = { 0.04, 0.03, 0.02 }, pos = { 0.05, -0.04, -0.445 }, color = "#6a5446" },
			eyes(-0.385, 0.06, 0.1),
		} },
		leg_fl = leg(-0.2, 0.42, -0.3, 1, "#cfc2b4", "#4a3a30", nil, nil, WOOL),
		leg_fr = leg(0.2, 0.42, -0.3, -1, "#cfc2b4", "#4a3a30", nil, nil, WOOL),
		leg_bl = leg(-0.2, 0.42, 0.3, -1, "#cfc2b4", "#4a3a30", nil, nil, WOOL),
		leg_br = leg(0.2, 0.42, 0.3, 1, "#cfc2b4", "#4a3a30", nil, nil, WOOL),
	},
	ai = { wander = true, flee = true, follow = "wheat", swim = true, graze = { from = "grass", to = "dirt", chance = 0.5 } },
	drops = { { item = "wool", count = 1, max = 2, adult_only = true }, { item = "mutton", count = 1, max = 2, adult_only = true } },
	spawn = { biomes = { "meadow", "forest", "snowy" }, on = { "grass", "snow" }, group = { 2, 4 }, max = math.floor(5 * amount + 0.5) },
})

---------------------------------------------------------------------------
-- Krowa
---------------------------------------------------------------------------
local HIDE = "#4a3226"
local SPOT = "#efe8dc"
engine.entities.register("cow", {
	name = "Krowa",
	health = 10, speed = 1.0, panic_speed = 2.5,
	size = { 0.95, 1.4 },
	surface = "hide",
	parts = {
		body = { pivot = { 0, 0.78, 0 }, boxes = {
			{ size = { 0.8, 0.68, 1.3 }, pos = { 0, 0.08, 0 }, color = HIDE },
			-- łaty: nieregularne białe plamy na bokach i grzbiecie
			{ size = { 0.82, 0.34, 0.4 }, pos = { 0, 0.2, 0.2 }, color = SPOT },
			{ size = { 0.82, 0.24, 0.26 }, pos = { 0, -0.02, -0.4 }, color = SPOT },
			{ size = { 0.82, 0.18, 0.2 }, pos = { 0, -0.12, 0.28 }, color = SPOT },
			{ size = { 0.82, 0.14, 0.14 }, pos = { 0, 0.3, -0.12 }, color = SPOT },
			{ size = { 0.5, 0.02, 0.3 }, pos = { 0.08, 0.43, 0.3 }, color = SPOT },
			{ size = { 0.82, 0.2, 0.12 }, pos = { 0, 0.02, 0.6 }, color = SPOT },
			{ size = { 0.32, 0.14, 0.34 }, pos = { 0, -0.32, 0.36 }, color = "#e8a0a8", tex = "skin" },
			{ size = { 0.05, 0.08, 0.05 }, pos = { -0.08, -0.42, 0.3 }, color = "#d88890" },
			{ size = { 0.05, 0.08, 0.05 }, pos = { 0.08, -0.42, 0.3 }, color = "#d88890" },
			-- ogon z kitką
			{ size = { 0.07, 0.42, 0.07 }, pos = { 0, -0.04, 0.68 }, color = HIDE, rot = { 8, 0, 0 } },
			{ size = { 0.12, 0.14, 0.12 }, pos = { 0, -0.28, 0.71 }, color = "#2a1c16", tex = "hair" },
		} },
		head = { parent = "body", pivot = { 0, 0.26, -0.66 }, look = true, boxes = {
			{ size = { 0.5, 0.46, 0.42 }, pos = { 0, 0.02, -0.2 }, color = HIDE },
			{ size = { 0.16, 0.34, 0.02 }, pos = { 0, 0.1, -0.415 }, color = SPOT },   -- biała strzałka na czole
			{ size = { 0.4, 0.22, 0.12 }, pos = { 0, -0.11, -0.45 }, color = "#d8b0a0", tex = "skin" },
			{ size = { 0.06, 0.06, 0.02 }, pos = { -0.09, -0.1, -0.515 }, color = "#3a2a24" },
			{ size = { 0.06, 0.06, 0.02 }, pos = { 0.09, -0.1, -0.515 }, color = "#3a2a24" },
			{ size = { 0.08, 0.16, 0.08 }, pos = { -0.22, 0.3, -0.14 }, color = "#e8e0d0", rot = { 0, 0, 15 }, tex = "metal" },
			{ size = { 0.08, 0.16, 0.08 }, pos = { 0.22, 0.3, -0.14 }, color = "#e8e0d0", rot = { 0, 0, -15 }, tex = "metal" },
			{ size = { 0.16, 0.08, 0.1 }, pos = { -0.31, 0.12, -0.12 }, color = HIDE, rot = { 0, 0, 15 } },
			{ size = { 0.16, 0.08, 0.1 }, pos = { 0.31, 0.12, -0.12 }, color = HIDE, rot = { 0, 0, -15 } },
			eyes(-0.415, 0.1, 0.13),
		} },
		leg_fl = leg(-0.26, 0.5, -0.45, 1, HIDE, "#2a1e18", 0.2, 0.5),
		leg_fr = leg(0.26, 0.5, -0.45, -1, HIDE, "#2a1e18", 0.2, 0.5),
		leg_bl = leg(-0.26, 0.5, 0.45, -1, HIDE, "#2a1e18", 0.2, 0.5),
		leg_br = leg(0.26, 0.5, 0.45, 1, HIDE, "#2a1e18", 0.2, 0.5),
	},
	ai = { wander = true, flee = true, follow = "wheat", swim = true, graze = { from = "grass", chance = 0 } },
	drops = { { item = "beef", count = 1, max = 3, adult_only = true }, { item = "leather", count = 0, max = 2, adult_only = true } },
	spawn = { biomes = { "meadow" }, on = { "grass" }, group = { 2, 3 }, max = math.floor(4 * amount + 0.5) },
})

---------------------------------------------------------------------------
-- Kurczak
---------------------------------------------------------------------------
engine.entities.register("chicken", {
	name = "Kurczak",
	health = 4, speed = 1.0, panic_speed = 2.6,
	size = { 0.45, 0.75 },
	surface = "feathers",
	parts = {
		body = { pivot = { 0, 0.36, 0 }, boxes = {
			{ size = { 0.34, 0.3, 0.44 }, pos = { 0, 0.04, 0 }, color = "#f4f2ec" },
			{ size = { 0.3, 0.12, 0.3 }, pos = { 0, -0.12, -0.02 }, color = "#ebe9e1" },   -- brzuch
			-- ogon: wachlarz piór w górę i do tyłu
			{ size = { 0.22, 0.22, 0.1 }, pos = { 0, 0.16, 0.25 }, color = "#e8e6de", rot = { -20, 0, 0 } },
			{ size = { 0.16, 0.18, 0.06 }, pos = { 0, 0.28, 0.29 }, color = "#dcdad2", rot = { -32, 0, 0 } },
		} },
		head = { parent = "body", pivot = { 0, 0.18, -0.18 }, look = true, boxes = {
			{ size = { 0.22, 0.26, 0.2 }, pos = { 0, 0.12, -0.04 }, color = "#f4f2ec" },
			{ size = { 0.1, 0.07, 0.1 }, pos = { 0, 0.11, -0.18 }, color = "#e8a830" },
			{ size = { 0.06, 0.08, 0.04 }, pos = { 0, 0.03, -0.15 }, color = "#d03a2a" },
			{ size = { 0.04, 0.08, 0.14 }, pos = { 0, 0.28, -0.04 }, color = "#d03a2a" },
			eyes(-0.145, 0.16, 0.07),
		} },
		wing_l = { parent = "body", pivot = { -0.18, 0.14, 0 }, wing = -1, boxes = {
			{ size = { 0.05, 0.22, 0.32 }, pos = { -0.02, -0.08, 0 }, color = "#e6e4dc" },
			{ size = { 0.055, 0.08, 0.14 }, pos = { -0.02, -0.16, 0.14 }, color = "#c8c6be" },   -- lotki
		} },
		wing_r = { parent = "body", pivot = { 0.18, 0.14, 0 }, wing = 1, boxes = {
			{ size = { 0.05, 0.22, 0.32 }, pos = { 0.02, -0.08, 0 }, color = "#e6e4dc" },
			{ size = { 0.055, 0.08, 0.14 }, pos = { 0.02, -0.16, 0.14 }, color = "#c8c6be" },
		} },
		leg_l = { pivot = { -0.08, 0.22, 0 }, swing = 1, boxes = {
			{ size = { 0.04, 0.22, 0.04 }, pos = { 0, -0.11, 0 }, color = "#e8a830" },
			{ size = { 0.1, 0.02, 0.12 }, pos = { 0, -0.21, -0.03 }, color = "#e8a830" },
		} },
		leg_r = { pivot = { 0.08, 0.22, 0 }, swing = -1, boxes = {
			{ size = { 0.04, 0.22, 0.04 }, pos = { 0, -0.11, 0 }, color = "#e8a830" },
			{ size = { 0.1, 0.02, 0.12 }, pos = { 0, -0.21, -0.03 }, color = "#e8a830" },
		} },
	},
	ai = { wander = true, flee = true, follow = "wheat", swim = true, slow_fall = true, graze = { from = "grass", chance = 0 } },
	drops = { { item = "chicken_meat", count = 1, adult_only = true }, { item = "feather", count = 0, max = 2 } },
	spawn = { biomes = { "meadow", "forest" }, on = { "grass" }, group = { 2, 5 }, max = math.floor(5 * amount + 0.5) },
})

-- serduszka przy rozmnażaniu: krótki podskok głowy
engine.animation.register("animals_happy", {
	length = 0.6,
	tracks = { head = { { 0, { 0, 0, 0 } }, { 0.15, { -25, 0, 0 } }, { 0.3, { 10, 0, 0 } }, { 0.6, { 0, 0, 0 } } } },
})

---------------------------------------------------------------------------
-- Odgłosy: silnik gra sounds.idle co jakiś czas (średnio co idle_every sekund) i sounds.hurt przy ranie;
-- młode mają wyższy głos.
---------------------------------------------------------------------------
engine.sounds.register("sheep.say", { files = { "sounds/sheep1.ogg", "sounds/sheep2.ogg" }, volume = 0.7, range = 20 })
engine.sounds.register("cow.say", { files = { "sounds/cow1.ogg", "sounds/cow2.ogg" }, volume = 0.8, range = 24 })
engine.sounds.register("chicken.say", { files = { "sounds/chicken1.ogg", "sounds/chicken2.ogg" }, volume = 0.6, range = 16 })
engine.entities.def("sheep").sounds = { idle = "sheep.say", idle_every = 18 }
engine.entities.def("cow").sounds = { idle = "cow.say", idle_every = 22 }
engine.entities.def("chicken").sounds = { idle = "chicken.say", idle_every = 12 }
