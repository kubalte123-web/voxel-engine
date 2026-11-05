-- Zestaw modera: wspólne funkcje dla innych modów.
-- Użycie w innym modzie:  local kit = engine.require("modkit")

local kit = { version = "0.2.0" }

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

-- Przedmioty to klucze tekstowe ("stone", "apple"); miejsce w kontenerze to {item, count, data} albo {}.
-- Stosy z danymi egzemplarza (data) nie łączą się ze zwykłymi.

-- Dodaje przedmioty do kontenera: najpierw dokłada do istniejących stosów, potem w puste miejsca.
-- data (dane egzemplarza) – tylko w puste miejsca, bez łączenia ze stosami.
-- Zwraca liczbę sztuk, które się nie zmieściły.
function kit.inventory.add(container, item, count, data)
	local size = engine.items.size(container)
	local stack = engine.items.max_stack(item)
	local left = count
	if data ~= nil and next(data) ~= nil then
		for i = 1, size do
			if left <= 0 then break end
			if engine.items.get(container, i).item == nil then
				local n = math.min(left, stack)
				engine.items.set(container, i, { item = item, count = n, data = data })
				left = left - n
			end
		end
		return left
	end
	for i = 1, size do
		if left <= 0 then break end
		local s = engine.items.get(container, i)
		if s.item == item and s.data == nil and s.count < stack then
			local n = math.min(left, stack - s.count)
			engine.items.set(container, i, { item = item, count = s.count + n })
			left = left - n
		end
	end
	for i = 1, size do
		if left <= 0 then break end
		local s = engine.items.get(container, i)
		if s.item == nil then
			local n = math.min(left, stack)
			engine.items.set(container, i, { item = item, count = n })
			left = left - n
		end
	end
	return left
end

-- To samo dla kilku kontenerów po kolei, np. {"hotbar", "backpack"}.
function kit.inventory.add_many(containers, item, count, data)
	local left = count
	for _, c in ipairs(containers) do
		if left <= 0 then break end
		left = kit.inventory.add(c, item, left, data)
	end
	return left
end

-- Zabiera n sztuk z konkretnego miejsca. Zwraca, ile udało się zabrać.
function kit.inventory.take(container, index, n)
	local s = engine.items.get(container, index)
	if s.item == nil then return 0 end
	local taken = math.min(n, s.count)
	if s.count - taken <= 0 then
		engine.items.set(container, index, {})
	else
		engine.items.set(container, index, { item = s.item, count = s.count - taken, data = s.data })
	end
	return taken
end

-- Zabiera n sztuk przedmiotu z dowolnych miejsc kontenerów. Zwraca, ile zabrano.
function kit.inventory.remove(containers, item, n)
	if type(containers) == "string" then containers = { containers } end
	local taken = 0
	for _, c in ipairs(containers) do
		for i = 1, engine.items.size(c) do
			if taken >= n then return taken end
			if engine.items.get(c, i).item == item then taken = taken + kit.inventory.take(c, i, n - taken) end
		end
	end
	return taken
end

function kit.inventory.count(containers, item)
	if type(containers) == "string" then containers = { containers } end
	local total = 0
	for _, c in ipairs(containers) do
		for i = 1, engine.items.size(c) do
			local s = engine.items.get(c, i)
			if s.item == item then total = total + s.count end
		end
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
