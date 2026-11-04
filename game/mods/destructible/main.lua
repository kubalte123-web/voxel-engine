-- Zniszczalność bloków: anuluje kopanie bloków wyłączonych w ustawieniach.
-- Wysoki priorytet (100), żeby zadziałał przed innymi modami reagującymi na kopanie.
engine.hooks.before("block.break", function(ctx)
	local allowed = engine.settings.get("breakable") or {}
	local key = engine.blocks.key(ctx.block)
	if allowed[key] == false then
		ctx.cancel = true
		if engine.settings.get("message") then
			engine.ui.notify("Tego bloku nie można wykopać: " .. engine.blocks.name(ctx.block))
		end
	end
end, 100)
