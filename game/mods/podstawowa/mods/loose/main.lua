-- Luźne przedmioty: zestaw na start.
local backpack = engine.require("backpack")
engine.on("player.join", function()
	if engine.settings.get("starter") and not engine.player.storage.get("started", false) then
		backpack.give("crate", 3)
		backpack.give("barrel", 2)
		backpack.give("ball", 1)
		backpack.give("boulder", 1)
		engine.player.storage.set("started", true)
	end
end)
