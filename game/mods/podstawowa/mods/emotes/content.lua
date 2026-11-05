-- Animacje klatkowe: dla każdej części postaci lista klatek {czas w sekundach, {obrót x, y, z w stopniach}}.
-- Części: body, head, arm_left, arm_right, leg_left, leg_right.
engine.animation.register("wave", {
	length = 1.6,
	tracks = {
		arm_right = { { 0, { 0, 0, 0 } }, { 0.25, { 0, 0, 160 } }, { 0.5, { 0, 0, 130 } }, { 0.75, { 0, 0, 165 } },
			{ 1.0, { 0, 0, 130 } }, { 1.25, { 0, 0, 160 } }, { 1.6, { 0, 0, 0 } } },
		head = { { 0, { 0, 0, 0 } }, { 0.4, { 5, 0, -8 } }, { 1.2, { 5, 0, -8 } }, { 1.6, { 0, 0, 0 } } },
	},
})

engine.animation.register("dance", {
	length = 1.0,
	loop = true,
	tracks = {
		arm_left = { { 0, { 0, 0, -150 } }, { 0.5, { 0, 0, -100 } }, { 1.0, { 0, 0, -150 } } },
		arm_right = { { 0, { 0, 0, 100 } }, { 0.5, { 0, 0, 150 } }, { 1.0, { 0, 0, 100 } } },
		body = { { 0, { 0, 15, 0 } }, { 0.5, { 0, -15, 0 } }, { 1.0, { 0, 15, 0 } } },
		head = { { 0, { 0, -10, 8 } }, { 0.5, { 0, 10, -8 } }, { 1.0, { 0, -10, 8 } } },
		leg_left = { { 0, { 20, 0, 0 } }, { 0.5, { -10, 0, 0 } }, { 1.0, { 20, 0, 0 } } },
		leg_right = { { 0, { -10, 0, 0 } }, { 0.5, { 20, 0, 0 } }, { 1.0, { -10, 0, 0 } } },
	},
})

-- zamiennik wbudowanego stanu "idle": postać rozgląda się co kilka sekund
engine.animation.register("idle_look", {
	length = 6.0,
	loop = true,
	tracks = {
		head = { { 0, { 0, 0, 0 } }, { 2.0, { 0, 0, 0 } }, { 2.6, { -5, 35, 0 } }, { 3.4, { -5, 35, 0 } },
			{ 4.0, { 0, -30, 0 } }, { 4.8, { 0, -30, 0 } }, { 5.4, { 0, 0, 0 } }, { 6.0, { 0, 0, 0 } } },
		arm_left = { { 0, { 0, 0, -6 } }, { 3.0, { 4, 0, -8 } }, { 6.0, { 0, 0, -6 } } },
		arm_right = { { 0, { 0, 0, 6 } }, { 3.0, { -4, 0, 8 } }, { 6.0, { 0, 0, 6 } } },
	},
})
