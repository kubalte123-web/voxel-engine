-- Koń z klocków; pole ride: gdzie siedzi jeździec i o ile szybciej jedzie.
local function leg(x, z, swing, color)
	return {
		pivot = { x, 0.72, z }, swing = swing,
		boxes = {
			{ size = { 0.16, 0.66, 0.16 }, pos = { 0, -0.33, 0 }, color = color },
			{ size = { 0.18, 0.1, 0.18 }, pos = { 0, -0.67, 0 }, color = "#2a2420" },
		},
	}
end

for _, v in ipairs({ { "horse", "Koń", "#8a5a34", "#4a2e1a" }, { "horse_white", "Siwy koń", "#d8d2c8", "#8a8478" } }) do
	local COAT, MANE = v[3], v[4]
	engine.entities.register(v[1], {
		name = v[2],
		health = 16, speed = 1.3, panic_speed = 4.0,
		size = { 1.0, 1.6 },
		parts = {
			body = { pivot = { 0, 0.98, 0 }, boxes = {
				{ size = { 0.62, 0.6, 1.3 }, pos = { 0, 0.04, 0 }, color = COAT },
				{ size = { 0.12, 0.5, 0.12 }, pos = { 0, -0.04, 0.7 }, color = MANE, rot = { 25, 0, 0 } },
				{ size = { 0.66, 0.08, 0.5 }, pos = { 0, 0.36, 0.0 }, color = "#6a3a20", tag = "saddle" },
				{ size = { 0.04, 0.3, 0.06 }, pos = { -0.34, 0.16, 0.0 }, color = "#3a2416", tag = "saddle" },
				{ size = { 0.04, 0.3, 0.06 }, pos = { 0.34, 0.16, 0.0 }, color = "#3a2416", tag = "saddle" },
			} },
			neck = { parent = "body", pivot = { 0, 0.2, -0.58 }, look = true, boxes = {
				{ size = { 0.3, 0.7, 0.36 }, pos = { 0, 0.26, -0.12 }, color = COAT, rot = { -30, 0, 0 } },
				{ size = { 0.1, 0.62, 0.12 }, pos = { 0, 0.34, 0.06 }, color = MANE, rot = { -30, 0, 0 } },
				{ size = { 0.28, 0.28, 0.6 }, pos = { 0, 0.6, -0.38 }, color = COAT },
				{ size = { 0.26, 0.2, 0.2 }, pos = { 0, 0.54, -0.66 }, color = "#3a2a22" },
				{ size = { 0.06, 0.16, 0.06 }, pos = { -0.09, 0.82, -0.18 }, color = COAT },
				{ size = { 0.06, 0.16, 0.06 }, pos = { 0.09, 0.82, -0.18 }, color = COAT },
				{ size = { 0.05, 0.05, 0.02 }, pos = { -0.145, 0.66, -0.5 }, color = "#141414" },
				{ size = { 0.05, 0.05, 0.02 }, pos = { 0.145, 0.66, -0.5 }, color = "#141414" },
			} },
			leg_fl = leg(-0.2, -0.5, 1, COAT),
			leg_fr = leg(0.2, -0.5, -1, COAT),
			leg_bl = leg(-0.2, 0.5, -1, COAT),
			leg_br = leg(0.2, 0.5, 1, COAT),
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
