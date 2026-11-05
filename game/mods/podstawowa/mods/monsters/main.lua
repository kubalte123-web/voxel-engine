-- Mózg zombie (co pół sekundy na serwerze): płonie w słońcu, jęczy, gdy goni, i woła inne zombie.
engine.entities.on_think("zombie", function(z)
	local head = z.pos + Vector3(0, 1.7, 0)
	if engine.settings.get("burn") and not z.in_liquid then
		local l = engine.world.light(head)
		if l.day > 0.5 and l.sky >= 14 then
			engine.particles.spawn("monsters.flame", z.pos + Vector3(0, 0.9, 0))
			engine.particles.spawn("monsters.smoke", head)
			engine.entities.damage(z.id, 1, "sun")
			-- w słońcu ucieka w cień (byle dalej od gracza)
			if z.state ~= "flee" then engine.entities.set_state(z.id, "wander", 3) end
			return
		end
	end
	if z.target then
		if engine.random() < 0.12 then engine.sound.play("zombie.groan", { pos = z.pos, pitch = 0.4 + engine.random() * 0.15 }) end
		-- czasem woła pobliskie zombie do pościgu
		if engine.random() < 0.1 then
			for _, other in ipairs(engine.entities.list("zombie")) do
				if other ~= z.id and not engine.entities.target(other) then
					local p = engine.entities.position(other)
					if p and p:distance_to(z.pos) < 12 then engine.entities.attack(other, z.target) end
				end
			end
		end
	end
end)

-- zombie, które zabiło gracza, przestaje gonić i wraca do wędrówki
engine.on("player.death", function(e)
	for _, id in ipairs(engine.entities.list("zombie", 0)) do
		if engine.entities.target(id) == engine.player.id() then engine.entities.set_state(id, "wander", 5) end
	end
end)

-- polecenie dla administratora: zombie przed graczem (test walki)
engine.commands.register("zombie", {
	description = "przywołuje zombie przed tobą", usage = "/zombie [ile]", permission = "admin",
	fn = function(ctx)
		local n = math.min(tonumber(ctx.args[1]) or 1, 10)
		local p = engine.player.position()
		for i = 1, n do engine.entities.spawn("zombie", p + Vector3(math.cos(i) * 4, 0.5, math.sin(i) * 4)) end
		return "Przywołano zombie: " .. n
	end,
})
