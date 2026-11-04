-- Zwierzęta: strzyżenie, dojenie, jajka, rozmnażanie i dorastanie młodych.
local kit = engine.require("modkit")
local backpack = engine.require("backpack")

if engine.settings.get("starter") and not engine.storage.get("started", false) then
	backpack.give("shears", 1)
	backpack.give("wheat", 8)
	engine.storage.set("started", true)
end

local function adult(id) return not engine.entities.data(id).baby end

-- po wczytaniu świata ostrzyżone owce nie mają wełny
engine.on("entity.spawn", function(e)
	if e.type == "sheep" and engine.entities.data(e.id).sheared then
		engine.entities.show(e.id, "wool", false)
	end
end)

-- prawy przycisk na zwierzęciu
engine.hooks.before("entity.interact", function(ctx)
	local id, item = ctx.id, ctx.item
	if ctx.type == "sheep" and item == "shears" and adult(id) and not engine.entities.data(id).sheared then
		engine.entities.show(id, "wool", false)
		engine.entities.set_data(id, "sheared", true)
		engine.entities.drop("wool", engine.random(1, 3), engine.entities.position(id) + Vector3(0, 0.8, 0))
		return
	end
	if ctx.type == "cow" and item == "bucket" and adult(id) then
		kit.inventory.take("hotbar", ctx.slot, 1)
		backpack.give("milk_bucket", 1)
		engine.ui.notify("Wiadro mleka")
		return
	end
	if item == "wheat" and engine.settings.get("breeding") and adult(id) then
		local d = engine.entities.data(id)
		if (d.love or 0) <= 0 then
			kit.inventory.take("hotbar", ctx.slot, 1)
			engine.entities.set_data(id, "love", 15)
			engine.entities.animate(id, "animals_happy")
		end
	end
end)

-- owca skubiąca trawę odzyskuje wełnę
engine.on("entity.graze", function(e)
	if e.type == "sheep" and engine.entities.data(e.id).sheared then
		engine.entities.show(e.id, "wool", true)
		engine.entities.set_data(e.id, "sheared", nil)
	end
end)

-- co sekundę dla każdego zwierzęcia: miłość, dorastanie, jajka
local egg_chance = 1 / (engine.settings.get("eggs_minutes") * 60)
engine.on("entity.tick", function(e)
	local id, d = e.id, e.data
	if d.baby then
		local grow = (d.grow or 120) - 1
		if grow <= 0 then
			engine.entities.set_data(id, "baby", nil)
			engine.entities.set_data(id, "grow", nil)
			engine.entities.set_scale(id, 1.0)
		else
			engine.entities.set_data(id, "grow", grow)
		end
	end
	if e.type == "chicken" and not d.baby and engine.random() < egg_chance then
		engine.entities.drop("egg", 1, e.pos + Vector3(0, 0.3, 0))
	end
	if (d.love or 0) > 0 then
		engine.entities.set_data(id, "love", d.love - 1)
		-- szukamy partnera tego samego gatunku, też zakochanego
		for _, other in ipairs(engine.entities.list(e.type, 40)) do
			if other ~= id and (engine.entities.data(other).love or 0) > 0 then
				local op = engine.entities.position(other)
				if (op - e.pos):length() < 1.6 then
					engine.entities.set_data(id, "love", 0)
					engine.entities.set_data(other, "love", 0)
					engine.entities.spawn(e.type, (op + e.pos) / 2 + Vector3(0, 0.3, 0), { baby = true, grow = 120 }, 0.55)
					engine.ui.notify("Urodziło się młode!")
				else
					engine.entities.move_to(id, op)
				end
				break
			end
		end
	end
end)

-- przedmioty z ziemi trafiają do plecaka (hak silnika item.pickup), obsługuje to mod Plecak
