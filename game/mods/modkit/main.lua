-- Zestaw modera: wspólne funkcje dla innych modów.
-- Użycie w innym modzie:  local kit = engine.require("modkit")

local kit = { version = "0.1.0" }

---------------------------------------------------------------------------
-- Łatki: kilka haków naraz, jak w Harmony (prefix = before, postfix = after)
---------------------------------------------------------------------------
-- kit.patch("block.break", { before = function(ctx) ... end, after = function(ctx) ... end, priority = 10 })
function kit.patch(name, spec)
	if spec.before then engine.hooks.before(name, spec.before, spec.priority) end
	if spec.after then engine.hooks.after(name, spec.after, spec.priority) end
end

---------------------------------------------------------------------------
-- Ekwipunek
---------------------------------------------------------------------------
kit.inventory = {}

local function max_stack() return engine.items.max_stack() end

-- Dodaje przedmioty do kontenera: najpierw dokłada do istniejących stosów, potem w puste miejsca.
-- Zwraca liczbę sztuk, które się nie zmieściły.
function kit.inventory.add(container, block, count)
	local size = engine.items.size(container)
	local left = count
	for i = 1, size do
		if left <= 0 then break end
		local s = engine.items.get(container, i)
		if s.block == block and s.count < max_stack() then
			local n = math.min(left, max_stack() - s.count)
			engine.items.set(container, i, { block = block, count = s.count + n })
			left = left - n
		end
	end
	for i = 1, size do
		if left <= 0 then break end
		local s = engine.items.get(container, i)
		if s.block == nil then
			local n = math.min(left, max_stack())
			engine.items.set(container, i, { block = block, count = n })
			left = left - n
		end
	end
	return left
end

-- To samo dla kilku kontenerów po kolei, np. {"hotbar", "backpack"}.
function kit.inventory.add_many(containers, block, count)
	local left = count
	for _, c in ipairs(containers) do
		if left <= 0 then break end
		left = kit.inventory.add(c, block, left)
	end
	return left
end

-- Zabiera n sztuk z konkretnego miejsca. Zwraca, ile udało się zabrać.
function kit.inventory.take(container, index, n)
	local s = engine.items.get(container, index)
	if s.block == nil then return 0 end
	local taken = math.min(n, s.count)
	if s.count - taken <= 0 then
		engine.items.set(container, index, {})
	else
		engine.items.set(container, index, { block = s.block, count = s.count - taken })
	end
	return taken
end

function kit.inventory.count(container, block)
	local total = 0
	for i = 1, engine.items.size(container) do
		local s = engine.items.get(container, i)
		if s.block == block then total = total + s.count end
	end
	return total
end

---------------------------------------------------------------------------
-- Czas: zdarzenie "tick" przychodzi 10 razy na sekundę
---------------------------------------------------------------------------
local timers = {}
engine.on("tick", function(e)
	for i = #timers, 1, -1 do
		local t = timers[i]
		t.left = t.left - e.dt
		if t.left <= 0 then
			local ok, err = pcall(t.fn)
			if not ok then engine.log("licznik: " .. tostring(err)) end
			if t.every then t.left = t.left + t.every else table.remove(timers, i) end
		end
	end
end)

function kit.after(seconds, fn) timers[#timers + 1] = { left = seconds, fn = fn } end
function kit.every(seconds, fn) timers[#timers + 1] = { left = seconds, every = seconds, fn = fn } end

---------------------------------------------------------------------------
-- Tabele
---------------------------------------------------------------------------
function kit.copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = kit.copy(v) end
	return out
end

function kit.merge(base, extra)
	local out = kit.copy(base)
	for k, v in pairs(extra or {}) do out[k] = v end
	return out
end

function kit.clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

engine.export(kit)
