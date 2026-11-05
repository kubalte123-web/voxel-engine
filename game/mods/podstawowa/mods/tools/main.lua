-- Narzędzia: pasujące narzędzie skraca czas kopania (hak block.dig).
engine.hooks.before("block.dig", function(ctx)
	local item = engine.items.def(ctx.item or "")
	local block = engine.blocks.get(engine.blocks.key(ctx.block))
	if item and item.tool and block and block.tool == item.tool then
		ctx.time = ctx.time / (item.tool_speed or 1)
	end
end)
