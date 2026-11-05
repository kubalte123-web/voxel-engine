-- Przepisy na kształty (gdy włączony jest któryś z modów rzemiosła) i zestaw na start.
local classic = engine.optional("crafting_classic")
local discovery = engine.optional("crafting_discovery")

local function has(k) return engine.items.def(k) ~= nil end

for _, src in ipairs({ "planks", "stone", "cobblestone", "bricks" }) do
	local slab, stairs = src .. "_slab", src .. "_stairs"
	if has(slab) then
		if classic then
			classic.shaped({ "SSS" }, { S = src }, slab, 6)
			classic.shaped({ "S  ", "SS ", "SSS" }, { S = src }, stairs, 4)
		end
		if discovery then
			discovery.add(slab, { [src] = 3 }, slab, 6, 1)
			discovery.add(stairs, { [src] = 6 }, stairs, 4, 1.5)
		end
	end
end
if classic then
	if has("stick") then classic.shaped({ "PSP", "PSP" }, { P = "planks", S = "stick" }, "planks_fence", 3) end
	if has("cobblestone_wall") then classic.shaped({ "CCC", "CCC" }, { C = "cobblestone" }, "cobblestone_wall", 6) end
	classic.shaped({ "GGG", "GGG" }, { G = "glass" }, "glass_pane", 16)
	classic.shaped({ "PPP", " P ", " P " }, { P = "planks" }, "planks_table", 1)
end
if discovery then
	if has("stick") then discovery.add("plot", { planks = 2, stick = 1 }, "planks_fence", 3, 1) end
	discovery.add("murek", { cobblestone = 3 }, "cobblestone_wall", 3, 1)
	discovery.add("szyby", { glass = 3 }, "glass_pane", 8, 1)
	discovery.add("stolik", { planks = 4 }, "planks_table", 1, 2)
end

-- zestaw na start (raz na konto; wyłączany w ustawieniach moda)
engine.on("player.join", function()
	if not engine.settings.get("starter") or engine.player.storage.get("building_started", false) then return end
	local bp = engine.optional("backpack")
	if not bp then return end
	for _, k in ipairs({ "planks_slab", "planks_stairs", "stone_stairs", "planks_fence", "glass_pane", "cobblestone_wall" }) do
		if has(k) then bp.give(k, 16) end
	end
	if has("planks_table") then bp.give("planks_table", 2) end
	engine.player.storage.set("building_started", true)
end)
