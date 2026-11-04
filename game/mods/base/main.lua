-- Wiadra: puste nabiera pełny blok wody, pełne wylewa 8 poziomów wody (wiadro = jeden blok objętości).
local function take_one(slot)
	local s = engine.items.get("hotbar", slot)
	if s.item == nil then return end
	if s.count <= 1 then engine.items.set("hotbar", slot, {})
	else engine.items.set("hotbar", slot, { item = s.item, count = s.count - 1 }) end
end

local function give(item)
	local ok, bp = pcall(engine.require, "backpack")
	if ok then bp.give(item, 1) end
end

engine.hooks.before("item.use", function(ctx)
	local def = engine.items.def(ctx.item)
	if not def or not def.bucket then return end
	local t = engine.player.target(true)   -- true: celujemy też w ciecze
	if not t.pos then return end
	if def.bucket == "empty" then
		local key = engine.blocks.key(t.block)
		-- tylko pełny blok: zbiornik albo płynąca woda na poziomie 8
		if key == "water" or key == "water~8" then
			engine.world.set_block(t.pos, 0)
			take_one(ctx.slot)
			give("water_bucket")
		end
	elseif def.bucket == "water" then
		local pos = t.pos
		if engine.blocks.key(t.block):sub(1, 5) ~= "water" then pos = t.pos + t.normal end
		if engine.world.get_block(pos) == 0 or engine.blocks.key(engine.world.get_block(pos)):sub(1, 5) == "water" then
			engine.world.set_block(pos, "water~8")
			take_one(ctx.slot)
			give("bucket")
		end
	end
	ctx.cancel = true
end)
