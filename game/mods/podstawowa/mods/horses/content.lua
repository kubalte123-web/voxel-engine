-- Koń z klocków; pole ride: gdzie siedzi jeździec i o ile szybciej jedzie.
-- Klocki mają faktury: sierść (surface = "hide"), grzywa i ogon (tex = "hair"), siodło (tex = "leather").
local function leg(x, z, swing, color, mane)
	return {
		pivot = { x, 0.72, z }, swing = swing,
		boxes = {
			{ size = { 0.18, 0.3, 0.2 }, pos = { 0, -0.12, 0 }, color = color },          -- udo
			{ size = { 0.14, 0.42, 0.14 }, pos = { 0, -0.42, 0 }, color = color },        -- goleń
			{ size = { 0.17, 0.08, 0.17 }, pos = { 0, -0.6, 0.0 }, color = mane, tex = "hair" },   -- szczotki nad kopytem
			{ size = { 0.17, 0.1, 0.19 }, pos = { 0, -0.67, -0.01 }, color = "#2a2420", tex = "leather" },
		},
	}
end

-- nazwy z "@" tłumaczy silnik z plików lang/pl.json, lang/en.json (język z opcji gracza)
for _, v in ipairs({ { "horse", "@horse", "#8a5a34", "#4a2e1a" }, { "horse_white", "@horse_white", "#d8d2c8", "#8a8478" } }) do
	local COAT, MANE = v[3], v[4]
	engine.entities.register(v[1], {
		name = v[2],
		health = 16, speed = 1.3, panic_speed = 4.0,
		size = { 1.0, 1.6 },
		surface = "hide",
		parts = {
			body = { pivot = { 0, 0.98, 0 }, boxes = {
				{ size = { 0.62, 0.6, 1.3 }, pos = { 0, 0.04, 0 }, color = COAT },
				{ size = { 0.58, 0.5, 0.3 }, pos = { 0, 0.08, -0.6 }, color = COAT },           -- pierś
				{ size = { 0.6, 0.12, 0.5 }, pos = { 0, 0.32, 0.42 }, color = COAT },          -- zad
				-- ogon: nasada i długi warkocz
				{ size = { 0.12, 0.2, 0.12 }, pos = { 0, 0.26, 0.68 }, color = MANE, rot = { 40, 0, 0 }, tex = "hair" },
				{ size = { 0.15, 0.62, 0.12 }, pos = { 0, -0.06, 0.78 }, color = MANE, rot = { 18, 0, 0 }, tex = "hair" },
				{ size = { 0.66, 0.08, 0.5 }, pos = { 0, 0.36, 0.0 }, color = "#6a3a20", tag = "saddle", tex = "leather" },
				{ size = { 0.5, 0.06, 0.12 }, pos = { 0, 0.41, 0.2 }, color = "#5a3018", tag = "saddle", tex = "leather" },
				{ size = { 0.04, 0.3, 0.06 }, pos = { -0.34, 0.16, 0.0 }, color = "#3a2416", tag = "saddle", tex = "leather" },
				{ size = { 0.04, 0.3, 0.06 }, pos = { 0.34, 0.16, 0.0 }, color = "#3a2416", tag = "saddle", tex = "leather" },
				{ size = { 0.06, 0.06, 0.1 }, pos = { -0.34, -0.02, 0.0 }, color = "#a8a8b0", tag = "saddle", tex = "metal" },
				{ size = { 0.06, 0.06, 0.1 }, pos = { 0.34, -0.02, 0.0 }, color = "#a8a8b0", tag = "saddle", tex = "metal" },
			} },
			neck = { parent = "body", pivot = { 0, 0.2, -0.58 }, look = true, boxes = {
				{ size = { 0.3, 0.7, 0.36 }, pos = { 0, 0.26, -0.12 }, color = COAT, rot = { -30, 0, 0 } },
				-- grzywa wzdłuż szyi (trzy pasma) i grzywka
				{ size = { 0.12, 0.66, 0.14 }, pos = { 0, 0.36, 0.06 }, color = MANE, rot = { -30, 0, 0 }, tex = "hair" },
				{ size = { 0.14, 0.4, 0.08 }, pos = { 0.05, 0.18, 0.14 }, color = MANE, rot = { -30, 0, 8 }, tex = "hair" },
				{ size = { 0.14, 0.12, 0.1 }, pos = { 0, 0.78, -0.22 }, color = MANE, tex = "hair" },
				-- głowa: czaszka, pysk, chrapy
				{ size = { 0.28, 0.3, 0.42 }, pos = { 0, 0.62, -0.32 }, color = COAT },
				{ size = { 0.24, 0.22, 0.3 }, pos = { 0, 0.55, -0.6 }, color = COAT },
				{ size = { 0.25, 0.14, 0.12 }, pos = { 0, 0.49, -0.74 }, color = "#3a2a22", tex = "skin" },
				{ size = { 0.04, 0.04, 0.02 }, pos = { -0.07, 0.52, -0.805 }, color = "#141010" },
				{ size = { 0.04, 0.04, 0.02 }, pos = { 0.07, 0.52, -0.805 }, color = "#141010" },
				{ size = { 0.07, 0.16, 0.06 }, pos = { -0.09, 0.84, -0.2 }, color = COAT, rot = { 0, 0, -8 } },
				{ size = { 0.07, 0.16, 0.06 }, pos = { 0.09, 0.84, -0.2 }, color = COAT, rot = { 0, 0, 8 } },
				{ size = { 0.05, 0.05, 0.02 }, pos = { -0.145, 0.68, -0.44 }, color = "#141414" },
				{ size = { 0.05, 0.05, 0.02 }, pos = { 0.145, 0.68, -0.44 }, color = "#141414" },
				-- uzda
				{ size = { 0.27, 0.04, 0.04 }, pos = { 0, 0.58, -0.66 }, color = "#3a2416", tag = "saddle", tex = "leather" },
			} },
			leg_fl = leg(-0.2, -0.5, 1, COAT, MANE),
			leg_fr = leg(0.2, -0.5, -1, COAT, MANE),
			leg_bl = leg(-0.2, 0.5, -1, COAT, MANE),
			leg_br = leg(0.2, 0.5, 1, COAT, MANE),
		},
		ai = { wander = true, flee = true, swim = true, follow = "apple", graze = { from = "grass", chance = 0 } },
		-- jazda: wysokość siodła nad ziemią, mnożnik prędkości i skoku gracza
		ride = { seat = { 0, 0.95, 0 }, speed = 2.3, jump = 1.3 },
		drops = { { item = "leather", count = 0, max = 2 } },
		spawn = { biomes = { "meadow" }, on = { "grass" }, group = { 1, 3 }, max = 3 },
	})
end

engine.particles.register("horses.heart", {
	amount = 5, life = 0.9, speed = { 0.3, 0.6 }, direction = { 0, 1, 0 }, spread = 40, gravity = -0.6,
	size = 0.12, color = { "#ff6a8a", "#ff6a8a00" }, shape = "round", glow = true,
})
