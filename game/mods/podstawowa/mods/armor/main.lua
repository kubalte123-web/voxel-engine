-- Zbroja: zakładanie (okno ekwipunku albo prawy przycisk), wygląd na postaci, ochrona przed obrażeniami.
local kit = engine.require("modkit")
local backpack = engine.require("backpack")
local crafting = engine.optional("crafting_classic")

local EQ = backpack.EQUIPMENT
-- miejsca w oknie ekwipunku (mod backpack): 1 głowa, 2 tułów, 3 nogi, 4 buty, 5 lewa ręka
local SLOT_INDEX = { head = 1, chest = 2, legs = 3, feet = 4, offhand = 5 }
local SLOT_NAMES = { "na głowę", "na tułów", "na nogi", "na stopy", "do lewej ręki" }
local REDUCTION = (engine.settings.get("reduction") or 4) / 100

local function armor_of(item)
	local d = item and engine.items.def(item)
	return d and d.armor or nil
end

---------------------------------------------------------------------------
-- Wygląd na postaci: klocki na częściach postaci (engine.player.wear), widzą je wszyscy gracze
---------------------------------------------------------------------------
local function look_boxes(slot, look)
	local c, t, tex = look.color, look.trim, look.tex
	local function bx(size, pos, color, rot) return { size = size, pos = pos, color = color, rot = rot, tex = tex } end
	if slot == "head" then
		return { { part = "head", boxes = {
			bx({ 0.48, 0.14, 0.48 }, { 0, 0.44, 0 }, c),
			bx({ 0.05, 0.26, 0.46 }, { -0.235, 0.27, 0.01 }, c),
			bx({ 0.05, 0.26, 0.46 }, { 0.235, 0.27, 0.01 }, c),
			bx({ 0.46, 0.26, 0.05 }, { 0, 0.27, 0.225 }, c),
			bx({ 0.5, 0.04, 0.5 }, { 0, 0.38, 0 }, t),
		} } }
	elseif slot == "chest" then
		return {
			{ part = "body", boxes = {
				bx({ 0.56, 0.5, 0.34 }, { 0, 0.4, 0 }, c),
				bx({ 0.58, 0.06, 0.36 }, { 0, 0.16, 0 }, t),
				bx({ 0.2, 0.06, 0.35 }, { 0, 0.63, 0 }, t),
			} },
			{ part = "arm_left", boxes = { bx({ 0.22, 0.22, 0.25 }, { 0, -0.06, 0 }, c) } },
			{ part = "arm_right", boxes = { bx({ 0.22, 0.22, 0.25 }, { 0, -0.06, 0 }, c) } },
		}
	elseif slot == "legs" then
		return {
			{ part = "body", boxes = { bx({ 0.55, 0.14, 0.33 }, { 0, 0.04, 0 }, t) } },
			{ part = "leg_left", boxes = { bx({ 0.26, 0.4, 0.28 }, { 0, -0.2, 0 }, c) } },
			{ part = "leg_right", boxes = { bx({ 0.26, 0.4, 0.28 }, { 0, -0.2, 0 }, c) } },
		}
	elseif slot == "feet" then
		return {
			{ part = "leg_left", boxes = { bx({ 0.27, 0.22, 0.34 }, { 0, -0.66, -0.03 }, c), bx({ 0.28, 0.04, 0.35 }, { 0, -0.56, -0.03 }, t) } },
			{ part = "leg_right", boxes = { bx({ 0.27, 0.22, 0.34 }, { 0, -0.66, -0.03 }, c), bx({ 0.28, 0.04, 0.35 }, { 0, -0.56, -0.03 }, t) } },
		}
	elseif slot == "offhand" then
		return { { part = "arm_left", boxes = {
			bx({ 0.05, 0.5, 0.4 }, { -0.13, -0.42, -0.02 }, c),
			bx({ 0.06, 0.04, 0.42 }, { -0.13, -0.17, -0.02 }, t),
			bx({ 0.06, 0.04, 0.42 }, { -0.13, -0.67, -0.02 }, t),
			bx({ 0.06, 0.1, 0.1 }, { -0.16, -0.42, -0.02 }, t),
		} } }
	end
	return {}
end

-- punkty zbroi bieżącego gracza i wygląd: liczone od nowa z miejsc wyposażenia
local function points()
	local n = 0
	for i = 1, engine.items.size(EQ) do
		local a = armor_of(engine.items.get(EQ, i).item)
		if a and SLOT_INDEX[a.slot] == i then n = n + (a.points or 0) end
	end
	return n
end

local function refresh()
	for slot, i in pairs(SLOT_INDEX) do
		local a = armor_of(engine.items.get(EQ, i).item)
		local parts = (a and a.look and a.slot == slot) and look_boxes(slot, a.look) or {}
		for k = 1, 3 do
			local p = parts[k]
			engine.player.wear("armor_" .. slot .. "_" .. k, p and { part = p.part, boxes = p.boxes } or nil)
		end
	end
	if engine.settings.get("bar") then
		local n = points()
		if n > 0 then
			engine.ui.bar({ id = "armor", label = "Zbroja", value = n, max = 20, color = "#a8b0c0" })
		else
			engine.ui.remove("armor")
		end
	end
end

engine.on("player.join", function() refresh() end, 50)

---------------------------------------------------------------------------
-- Zakładanie: w oknie tylko pasująca część na swoje miejsce; prawy przycisk z częścią w ręce
---------------------------------------------------------------------------
engine.hooks.before("slot.click", function(ctx)
	if ctx.container ~= EQ then return end
	local held = engine.ui.held()
	if not held.item then return end
	local a = armor_of(held.item)
	local want = SLOT_INDEX[a and a.slot or ""]
	-- lewa ręka przyjmuje każdy przedmiot (jak w MC), inne miejsca tylko swoją część zbroi
	if ctx.index == SLOT_INDEX.offhand and (not a or a.slot == "offhand") then return end
	if want ~= ctx.index then
		ctx.cancel = true
		engine.ui.notify(a and ("To się zakłada " .. SLOT_NAMES[want]) or "Tu można założyć tylko zbroję")
	end
end)

engine.hooks.after("slot.click", function() refresh() end)

engine.hooks.before("item.use", function(ctx)
	local a = armor_of(ctx.item)
	if not a or not SLOT_INDEX[a.slot] then return end
	ctx.cancel = true
	local i = SLOT_INDEX[a.slot]
	local worn = engine.items.get(EQ, i)
	local hand = engine.items.get(backpack.HOTBAR, ctx.slot)
	-- zamiana: część z paska na postać, poprzednia część do paska
	engine.items.set(EQ, i, { item = hand.item, count = 1, data = hand.data })
	engine.items.set(backpack.HOTBAR, ctx.slot, worn.item and worn or {})
	refresh()
end)

---------------------------------------------------------------------------
-- Ochrona: obrażenia mniejsze o REDUCTION za punkt (najwyżej 80%); głód, topienie i pustka bez ochrony
---------------------------------------------------------------------------
local UNPROTECTED = { hunger = true, drown = true, void = true }
engine.hooks.before("player.damage", function(ctx)
	if UNPROTECTED[ctx.cause] then return end
	local n = points()
	if n <= 0 then return end
	ctx.amount = ctx.amount * (1 - math.min(0.8, n * REDUCTION))
end, 20)

---------------------------------------------------------------------------
-- Przepisy (gdy jest rzemiosło klasyczne): kształty jak w MC, przy stole 3×3
---------------------------------------------------------------------------
if crafting then
	local mats = {}
	if engine.items.def("leather") then mats[#mats + 1] = { "leather", "leather" } end
	if engine.items.def("iron_ingot") then mats[#mats + 1] = { "iron_ingot", "iron" } end
	for _, m in ipairs(mats) do
		local key = { M = m[1] }
		crafting.shaped({ "MMM", "M M" }, key, m[2] .. "_helmet")
		crafting.shaped({ "M M", "MMM", "MMM" }, key, m[2] .. "_chestplate")
		crafting.shaped({ "MMM", "M M", "M M" }, key, m[2] .. "_leggings")
		crafting.shaped({ "M M", "M M" }, key, m[2] .. "_boots")
	end
	if engine.items.def("iron_ingot") then
		crafting.shaped({ "PIP", "PPP", " P " }, { P = "planks", I = "iron_ingot" }, "wooden_shield")
	else
		crafting.shaped({ "PPP", "PPP", " P " }, { P = "planks" }, "wooden_shield")
	end
end

engine.export({ points = points, refresh = refresh, SLOT_INDEX = SLOT_INDEX })
