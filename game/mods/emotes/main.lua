-- Gesty, kamera i wygląd.
local outfits = {
	["Zielony"] = { tunic = "#3d8076", tunic_dark = "#2e665e", scarf = "#b83833" },
	["Czerwony"] = { tunic = "#a83a32", tunic_dark = "#862c26", scarf = "#e0b040" },
	["Niebieski"] = { tunic = "#3a5aa8", tunic_dark = "#2c4686", scarf = "#e8e8e8" },
	["Fioletowy"] = { tunic = "#6a3a8a", tunic_dark = "#542c6e", scarf = "#40b0a0" },
}
engine.player.colors(outfits[engine.settings.get("outfit")] or outfits["Zielony"])

if engine.settings.get("lively_idle") then
	engine.animation.override("idle", "idle_look")
end

local dancing = false
engine.input.bind({ id = "wave", key = "G", label = "Machnij", on_press = function()
	dancing = false
	engine.player.animate("wave")
end })
engine.input.bind({ id = "dance", key = "H", label = "Taniec", on_press = function()
	dancing = not dancing
	if dancing then engine.player.animate("dance") else engine.player.stop_animation() end
end })

-- Tryby kamery po kolei pod klawiszem C.
local modes = { "third", "shoulder", "top", "first" }
local names = { third = "zza pleców", shoulder = "zza ramienia", top = "z góry", first = "z oczu" }
local current = 1
engine.input.bind({ id = "camera", key = "C", label = "Kamera", on_press = function()
	current = current % #modes + 1
	engine.camera.set("mode", modes[current])
	engine.ui.notify("Kamera: " .. names[modes[current]])
end })

-- Hak kamery co klatkę: przy tańcu kamera powoli okrąża postać.
local angle = 0
engine.hooks.after("camera.update", function(cam)
	if dancing and cam.mode ~= "first" then
		angle = angle + 0.01
		cam.yaw = cam.yaw + math.sin(angle) * 0.6
	end
end)
