-- Prelude systemu modów: buduje API `engine` dla każdego moda.
-- Wykonywane raz, we wspólnym stanie Lua. Funkcje gospodarza (GDScript) są w tabeli `host`,
-- do której mody nie mają bezpośredniego dostępu: każdy mod dostaje własne, odizolowane
-- środowisko (_ENV) z bezpiecznymi funkcjami i swoim obiektem `engine`.

local host = host

---------------------------------------------------------------------------
-- Zamiana wartości między Godotem a Lua (tablice Lua liczone od 1)
---------------------------------------------------------------------------
local function to_lua(v)
	if type(v) == "userdata" then
		if Variant.is(v, Dictionary) then
			local t = {}
			for k, x in pairs(v) do t[k] = to_lua(x) end
			return t
		elseif Variant.is(v, Array) then
			local t = {}
			for i, x in pairs(v) do t[i + 1] = to_lua(x) end
			return t
		end
	end
	return v
end

local function is_list(t)
	if next(t) == nil then return false end
	local n = 0
	for k in pairs(t) do
		if type(k) ~= "number" then return false end
		n = n + 1
	end
	return n == #t
end

local function to_godot(v)
	if type(v) == "table" then
		if is_list(v) then
			local a = Array()
			for _, x in ipairs(v) do a:append(to_godot(x)) end
			return a
		end
		local d = Dictionary()
		for k, x in pairs(v) do
			if type(x) ~= "function" then d:set(k, to_godot(x)) end
		end
		return d
	end
	return v
end

---------------------------------------------------------------------------
-- Strażnik: limit czasu (liczba instrukcji) i pamięci dla kodu modów.
-- Każde wejście silnika do Lua dostaje budżet; mod, który go przekroczy (np. pętla bez końca),
-- zostaje wyłączony do końca gry, a gra działa dalej.
---------------------------------------------------------------------------
local sethook = debug.sethook
local traceback = debug.traceback
local collectgarbage = collectgarbage
local co_create, co_resume = coroutine.create, coroutine.resume
local STEP = 1000                 -- co ile instrukcji sprawdzamy limity
local LIMIT_CALL = 30000000       -- instrukcji na jedno wywołanie (około 0,1–0,3 s)
local LIMIT_LOAD = 300000000      -- instrukcji na wczytanie pliku moda
local MEMORY_KB = 256 * 1024      -- pamięć całego stanu Lua
local guard = { used = 0, limit = LIMIT_LOAD, owner = "?", tripped = false, depth = 0, checks = 0 }
local disabled = {}

local function hook()
	if guard.depth == 0 then
		guard.used = 0  -- kod silnika (prelude) nie ma limitu czasu
	end
	guard.used = guard.used + STEP
	if guard.depth > 0 and (guard.tripped or guard.used > guard.limit) then
		guard.tripped = true
		error("przekroczony limit czasu wykonania (pętla bez końca?)", 2)
	end
	guard.checks = guard.checks + 1
	if guard.checks % 16 == 0 and collectgarbage("count") > MEMORY_KB then
		collectgarbage("collect")
		if collectgarbage("count") > MEMORY_KB then
			guard.tripped = true
			error("przekroczony limit pamięci", 2)
		end
	end
end
sethook(hook, "", STEP)

-- Wywołanie kodu moda pod limitem. Zwraca ok, błąd.
local function guarded(owner, limit, fn, ...)
	if disabled[owner] then return false, nil end
	local saved_used, saved_limit, saved_owner = guard.used, guard.limit, guard.owner
	if guard.depth == 0 then guard.tripped = false end
	guard.depth = guard.depth + 1
	guard.used, guard.limit, guard.owner = 0, limit, owner
	local ok, err = xpcall(fn, function(e)
		if guard.tripped or type(e) ~= "string" then return e end
		local tb = traceback("", 2)
		tb = tb:gsub("\n%s*%[C%]: in %?", ""):gsub("\n[^\n]*prelude%.lua[^\n]*", ""):gsub("\n[^\n]*xpcall[^\n]*", "")
		if not tb:find("\n%s*%S+:%d+:") then tb = "" end   -- sam nagłówek bez miejsc w kodzie moda
		return e .. tb:sub(1, 700)
	end, ...)
	local tripped = guard.tripped
	guard.depth = guard.depth - 1
	guard.used, guard.limit, guard.owner = saved_used + guard.used, saved_limit, saved_owner
	if guard.depth == 0 then guard.tripped = false end
	if tripped and not disabled[owner] then
		disabled[owner] = true
		host.mod_disabled(owner, tostring(err))
	end
	return ok, err
end

-- Korutyny modów też podlegają limitom.
local function safe_coroutine()
	local c = {}
	for k, v in pairs(coroutine) do c[k] = v end
	c.create = function(f)
		local co = co_create(f)
		sethook(co, hook, "", STEP)
		return co
	end
	c.wrap = function(f)
		local co = c.create(f)
		return function(...)
			local r = table.pack(co_resume(co, ...))
			if not r[1] then error(r[2], 2) end
			return table.unpack(r, 2, r.n)
		end
	end
	return c
end

-- string.rep potrafi zająć gigabajty jednym wywołaniem, zanim strażnik zdąży zareagować
local function safe_string()
	local s = {}
	for k, v in pairs(string) do s[k] = v end
	local rep = string.rep
	s.rep = function(str, n, sep)
		if #tostring(str) * (tonumber(n) or 0) > 16 * 1024 * 1024 then error("string.rep: wynik za duży", 2) end
		return rep(str, n, sep)
	end
	return s
end

-- pcall i xpcall modów nie mogą połknąć błędu strażnika (np. pętla wokół pcall)
local raw_pcall, raw_xpcall = pcall, xpcall
local function safe_pcall(f, ...)
	local r = table.pack(raw_pcall(f, ...))
	if guard.tripped then error(r[2], 0) end
	return table.unpack(r, 1, r.n)
end
local function safe_xpcall(f, h, ...)
	local r = table.pack(raw_xpcall(f, h, ...))
	if guard.tripped then error(r[2], 0) end
	return table.unpack(r, 1, r.n)
end

-- mody nie mogą podmienić wspólnej metatabeli tekstów
getmetatable("").__metatable = false

---------------------------------------------------------------------------
-- Haki (przed / po, jak prefix i postfix w Harmony) oraz zdarzenia
---------------------------------------------------------------------------
local handlers = { before = {}, after = {}, event = {} }
local exports = {}
local binds = {}
local window_actions = {}

local function add_handler(kind, name, fn, priority, owner)
	assert(type(name) == "string", "nazwa haka musi być tekstem")
	assert(type(fn) == "function", "drugi argument musi być funkcją")
	local list = handlers[kind][name]
	if not list then
		list = {}
		handlers[kind][name] = list
	end
	list[#list + 1] = { fn = fn, priority = priority or 0, owner = owner, order = #list }
	host.hook_added(kind, name)
	table.sort(list, function(a, b)
		if a.priority ~= b.priority then return a.priority > b.priority end
		return a.order < b.order
	end)
end

local function run(kind, name, ctx)
	local list = handlers[kind][name]
	if not list then return ctx end
	if guard.depth == 0 then guard.tripped = false end
	for _, h in ipairs(list) do
		local ok, err = guarded(h.owner, LIMIT_CALL, h.fn, ctx)
		if not ok and err ~= nil then host.report_error(h.owner, name .. ": " .. tostring(err)) end
		if kind == "before" and ctx.cancel then break end
	end
	return ctx
end

-- wywoływane przez silnik
local function dispatch(kind, name, ctx)
	local list = handlers[kind][name]
	if not list then return ctx end
	return to_godot(run(kind, name, to_lua(ctx)))
end

local function input(id)
	local b = binds[id]
	if b then
		local ok, err = guarded(b.owner, LIMIT_CALL, b.fn)
		if not ok and err ~= nil then host.report_error(b.owner, "klawisz " .. id .. ": " .. tostring(err)) end
	end
end

local make_env_ref  -- ustawiane niżej (make_env jest zdefiniowane na końcu pliku)

-- aktualizacje bloków: base klucz -> lista {fn, owner}
local block_handlers = {}

local function block_update(key, ctx)
	local list = block_handlers[key]
	if not list then return end
	if guard.depth == 0 then guard.tripped = false end
	local c = to_lua(ctx)
	for _, h in ipairs(list) do
		local ok, err = guarded(h.owner, LIMIT_CALL, h.fn, c)
		if not ok and err ~= nil then host.report_error(h.owner, "blok " .. key .. ": " .. tostring(err)) end
	end
end

-- generatory świata: lista {fn, owner}; deterministyczny los (xorshift) zależny tylko od ziarna
local worldgen_fns = {}

local function make_rng(seed)
	local s = (math.tointeger(seed) or 1) ~ 0x2545F4914F6CDD1D
	if s == 0 then s = 1 end
	local r = {}
	function r:next()
		s = s ~ (s << 13)
		s = s ~ (s >> 7)
		s = s ~ (s << 17)
		return ((s >> 11) & 0x1FFFFFFFFFFFFF) / 9007199254740992.0
	end
	function r:int(a, b) return a + math.floor(self:next() * (b - a + 1)) end
	function r:chance(p) return self:next() < p end
	function r:pick(list) return list[self:int(1, #list)] end
	return r
end

local function str_hash(t)
	local h = 5381
	for i = 1, #t do h = ((h * 33) ~ t:byte(i)) & 0x7FFFFFFF end
	return h
end

local function worldgen(cx, cy, cz, world_seed)
	if #worldgen_fns == 0 then return end
	if guard.depth == 0 then guard.tripped = false end
	local S = 32
	local seed = (world_seed * 73856093) ~ (cx * 19349663) ~ (cy * 83492791) ~ (cz * 2654435761)
	local function P(x, y, z)
		if type(x) ~= "number" then return VI(x), y end
		return Vector3i(math.floor(x), math.floor(y), math.floor(z)), nil
	end
	local ch = { x = cx, y = cy, z = cz, size = S, seed = seed,
		min = Vector3i(cx * S, cy * S, cz * S), max = Vector3i(cx * S + S - 1, cy * S + S - 1, cz * S + S - 1) }
	function ch.get(x, y, z) local p = P(x, y, z) return host.gen_get(p) end
	-- set(x, y, z, blok) albo set(pozycja, blok); blok: klucz albo id
	function ch.set(x, y, z, b)
		local p, b2 = P(x, y, z)
		if b2 ~= nil then b = b2 end
		if type(b) == "string" then b = host.block_id(b) end
		if b and b >= 0 then host.gen_set(p, b) end
	end
	function ch.height(x, z) return host.gen_height(math.floor(x), math.floor(z)) end
	function ch.biome(x, z) return host.gen_biome(math.floor(x), math.floor(z)) end
	function ch.random(salt) return make_rng(seed ~ str_hash(tostring(salt or ""))) end
	function ch.contains(x, y, z)
		local p = P(x, y, z)
		return p.x >= ch.min.x and p.x <= ch.max.x and p.y >= ch.min.y and p.y <= ch.max.y and p.z >= ch.min.z and p.z <= ch.max.z
	end
	for _, h in ipairs(worldgen_fns) do
		local ok, err = guarded(h.owner, LIMIT_CALL, h.fn, ch)
		if not ok and err ~= nil then host.report_error(h.owner, "generator świata: " .. tostring(err)) end
	end
end

-- polecenia modów: nazwa -> {fn, owner}
local command_fns = {}

local function command(name, ctx)
	local c = command_fns[name]
	if not c then return nil end
	if guard.depth == 0 then guard.tripped = false end
	local args = to_lua(ctx)
	local ok, res = guarded(c.owner, LIMIT_CALL, c.fn, args)
	if not ok then
		if res ~= nil then host.report_error(c.owner, "polecenie /" .. name .. ": " .. tostring(res)) end
		return "Błąd w poleceniu /" .. name
	end
	if res == nil then return nil end
	return tostring(res)
end

-- mózgi stworzeń: rodzaj -> lista {fn, owner}
local entity_handlers = {}

local function entity_think(type, ctx)
	local list = entity_handlers[type]
	if not list then return end
	if guard.depth == 0 then guard.tripped = false end
	local c = to_lua(ctx)
	if c.target == -1 then c.target = nil end
	if c.rider == -1 then c.rider = nil end
	for _, h in ipairs(list) do
		local ok, err = guarded(h.owner, LIMIT_CALL, h.fn, c)
		if not ok and err ~= nil then host.report_error(h.owner, "stworzenie " .. type .. ": " .. tostring(err)) end
	end
end

-- pociski: rodzaj -> lista {fn, owner}; opisy przedmiotów: klucz -> {fn, owner}
local projectile_handlers = {}
local tooltip_fns = {}

local function projectile_hit(type, ctx)
	local list = projectile_handlers[type]
	if not list then return end
	if guard.depth == 0 then guard.tripped = false end
	local c = to_lua(ctx)
	for _, h in ipairs(list) do
		local ok, err = guarded(h.owner, LIMIT_CALL, h.fn, c)
		if not ok and err ~= nil then host.report_error(h.owner, "pocisk " .. type .. ": " .. tostring(err)) end
	end
end

local function item_tooltip(key, slot)
	local t = tooltip_fns[key]
	if not t then return nil end
	if guard.depth == 0 then guard.tripped = false end
	local ok, lines = guarded(t.owner, LIMIT_CALL, t.fn, to_lua(slot))
	if not ok then
		if lines ~= nil then host.report_error(t.owner, "opis " .. key .. ": " .. tostring(lines)) end
		return nil
	end
	if type(lines) == "string" then lines = { lines } end
	if type(lines) ~= "table" then return nil end
	local out = {}
	for _, l in ipairs(lines) do out[#out + 1] = tostring(l) end
	return to_godot(out)
end

-- konsola modera: kod Lua w środowisku moda "console" (z pełnym engine), wynik jako tekst
local console_env = nil

local function console(code)
	if console_env == nil then console_env = make_env_ref("console") end
	local f = load("return " .. code, "=konsola", "t", console_env)
	if not f then
		local err
		f, err = load(code, "=konsola", "t", console_env)
		if not f then return "błąd: " .. tostring(err) end
	end
	local out = {}
	local ok, r = guarded("console", LIMIT_CALL, function()
		local res = table.pack(f())
		for i = 1, res.n do
			local v = res[i]
			if type(v) == "table" then
				local parts = {}
				for k, x in pairs(v) do
					parts[#parts + 1] = tostring(k) .. " = " .. tostring(x)
					if #parts >= 30 then parts[#parts + 1] = "…" break end
				end
				out[#out + 1] = "{ " .. table.concat(parts, ", ") .. " }"
			else
				out[#out + 1] = tostring(v)
			end
		end
	end)
	if not ok then return "błąd: " .. tostring(r) end
	return table.concat(out, "\t")
end

local function window_action(id, fields)
	local a = window_actions[id]
	if a then
		local ok, err = guarded(a.owner, LIMIT_CALL, a.fn, to_lua(fields) or {})
		if not ok and err ~= nil then host.report_error(a.owner, "przycisk " .. id .. ": " .. tostring(err)) end
	end
end

-- Wczytanie pliku moda: tylko kod tekstowy (bez binarnego bajtkodu), pod limitem czasu.
local function run_chunk(mod_id, code, chunkname, env)
	local f, err = load(code, chunkname, "t", env)
	if not f then return tostring(err) end
	local ok, e = guarded(mod_id, LIMIT_LOAD, f)
	if not ok then return tostring(e or "mod wyłączony") end
	return nil
end

---------------------------------------------------------------------------
-- Rejestr treści (faza content.lua): bloki, przedmioty, świat, animacje.
-- Definicje są zwykłymi tabelami Lua, więc mod wczytany później może je zmienić
-- (np. podmienić teksturę kamienia albo dodać drzewo do cudzego biomu).
---------------------------------------------------------------------------
-- Pozycje z Lua: tabela {x =, y =, z =} albo wektor. Bloki: liczby całkowite (w dół), obiekty: ułamki.
local function VI(p)
	if type(p) == "table" then
		return Vector3i(math.floor(p.x or p[1] or 0), math.floor(p.y or p[2] or 0), math.floor(p.z or p[3] or 0))
	end
	return p
end
local function VF(p)
	if type(p) == "table" then return Vector3(p.x or p[1] or 0, p.y or p[2] or 0, p.z or p[3] or 0) end
	return p
end

local R = {
	frozen = false,
	blocks = {}, block_list = {},
	items = {}, item_list = {},
	biomes = {}, biome_list = {},
	ores = {}, ore_list = {},
	structures = {},
	config = { biome_scale = 1.0, beach_height = 7 },
	animations = {},
	entities = {},
	sounds = {},
	particles = {},
	projectiles = {},
	effects = {},
}

local function open_registry(what)
	if R.frozen then
		error(what .. ": rejestracja działa tylko w plikach \"content\" (np. content.lua)", 3)
	end
end

local function copy(t)
	if type(t) ~= "table" then return t end
	local out = {}
	for k, v in pairs(t) do out[k] = copy(v) end
	return out
end

local function put(map, list, key, def)
	if map[key] == nil then list[#list + 1] = key end
	map[key] = def
	return def
end

local function norm_drops(key, d, has_item)
	if d == false then return {} end
	if d == nil then return has_item and { { item = key, count = 1 } } or {} end
	if type(d) == "string" then return { { item = d, count = 1 } } end
	if d.item then return { { item = d.item, count = d.count or 1, chance = d.chance } } end
	local out = {}
	for _, x in ipairs(d) do
		if type(x) == "string" then out[#out + 1] = { item = x, count = 1 }
		else out[#out + 1] = { item = x.item, count = x.count or 1, chance = x.chance } end
	end
	return out
end

-- Struktura z warstw tekstowych: layers[y][z] to wiersz znaków (x), key mapuje znak na blok.
local function norm_structure(def)
	local s = copy(def)
	local out = {}
	if s.layers then
		local key = s.key or {}
		local ox, oy, oz = 0, 0, 0
		if s.origin then ox, oy, oz = s.origin[1] or 0, s.origin[2] or 0, s.origin[3] or 0 end
		for y, layer in ipairs(s.layers) do
			for z, row in ipairs(layer) do
				for x = 1, #row do
					local ch = row:sub(x, x)
					local b = key[ch]
					if b then out[#out + 1] = { x - 1 - ox, y - 1 - oy, z - 1 - oz, b } end
				end
			end
		end
	end
	for _, b in ipairs(s.blocks or {}) do out[#out + 1] = { b[1], b[2], b[3], b[4] } end
	s.blocks = out
	s.layers = nil
	s.key = nil
	return s
end

-- Stany bloku: states = { facing = {"north", "east", "south", "west"}, lit = {false, true} } daje osobny
-- wariant (osobne id) dla każdej kombinacji. Pierwsza kombinacja nosi klucz bloku, pozostałe
-- "klucz[facing=east,lit=true]". variant(state) zwraca zmiany definicji dla wariantu (np. światło, tekstury),
-- a stan facing obraca tekstury: front (przód), back (tył), side (boki).
local OPPOSITE = { north = "south", south = "north", east = "west", west = "east" }

local function orient(tex, facing)
	if type(tex) ~= "table" or tex.front == nil or OPPOSITE[facing] == nil then return tex end
	local t = copy(tex)
	local side = tex.side or tex.all
	for f in pairs(OPPOSITE) do t[f] = side end
	t[facing] = tex.front
	t[OPPOSITE[facing]] = tex.back or side
	t.front, t.back, t.side = nil, nil, nil
	return t
end

-- Kształty z prostopadłościanów (w szesnastkach bloku: x1, y1, z1, x2, y2, z2). Przód kształtu to północ;
-- stan facing obraca prostopadłościany, stan half = "top" odwraca półbloki i schody do góry nogami.
local function rot_box(b, turns)
	for _ = 1, turns do b = { 16 - b[6], b[2], b[1], 16 - b[3], b[5], b[4] } end
	return b
end
local TURNS = { north = 0, east = 1, south = 2, west = 3 }
local SHAPE_PRESETS = {
	slab = { boxes = { { 0, 0, 0, 16, 8, 16 } }, top = { { 0, 8, 0, 16, 16, 16 } } },
	stairs = { boxes = { { 0, 0, 0, 16, 8, 16 }, { 0, 8, 0, 16, 16, 8 } }, top = { { 0, 8, 0, 16, 16, 16 }, { 0, 0, 0, 16, 8, 8 } } },
	fence = { boxes = { { 6, 0, 6, 10, 16, 10 } }, group = "fence", north = { { 7, 12, 0, 9, 15, 6 }, { 7, 6, 0, 9, 9, 6 } } },
	pane = { boxes = { { 7, 0, 7, 9, 16, 9 } }, group = "pane", north = { { 7, 0, 0, 9, 16, 7 } } },
	wall = { boxes = { { 4, 0, 4, 12, 16, 12 } }, group = "wall", north = { { 5, 0, 0, 11, 13, 4 } } },
}

local function shape_of(b)
	local preset = SHAPE_PRESETS[b.shape]
	if not preset and not b.boxes then return nil end
	local st = b.state or {}
	local boxes = preset and ((st.half == "top" and preset.top) or preset.boxes) or b.boxes
	local turns = TURNS[st.facing] or 0
	local out = {}
	for i, bx in ipairs(boxes) do out[i] = rot_box({ bx[1], bx[2], bx[3], bx[4], bx[5], bx[6] }, turns) end
	local con = b.connect
	if preset and preset.group then
		con = { group = preset.group, north = preset.north }
	end
	local connect = nil
	if con then
		connect = { group = con.group }
		local north = con.north or {}
		local dirs = { "north", "east", "south", "west" }
		for k, d in ipairs(dirs) do
			local src = con[d]
			if src == nil then
				src = {}
				for i, bx in ipairs(north) do src[i] = rot_box({ bx[1], bx[2], bx[3], bx[4], bx[5], bx[6] }, k - 1) end
			end
			connect[d] = src
		end
	end
	return out, connect
end

-- Paczki zasobów gracza: pliki podmieniane po kluczu (blocks/stone.png, blocks/furnace.front.png,
-- items/apple.png, entities/horse.glb, sounds/cow.say.ogg). Działa też dla tekstur ze wzorów i modeli z klocków.
local function res_file(names) return host.res_file(to_godot(names)) end
local RES_FACES = { "top", "bottom", "side", "front", "back", "north", "south", "east", "west" }

local function res_block(v, keys)
	local function find(suffix)
		local names = {}
		for _, k in ipairs(keys) do names[#names + 1] = "blocks/" .. k .. suffix end
		return res_file(names)
	end
	local all = find(".png")
	local tex = nil
	if all ~= "" then tex = { all = all } end
	for _, f in ipairs(RES_FACES) do
		local p = find("." .. f .. ".png")
		if p ~= "" then
			if not tex then
				tex = {}
				if type(v.textures) == "table" then for k2, t in pairs(v.textures) do tex[k2] = t end
				elseif v.texture then tex.all = v.texture end
			end
			tex[f] = p
		end
	end
	if tex then v.textures = tex v.texture = nil end
	local glb = find(".glb")
	if glb ~= "" and type(v.model) == "table" then
		local m = copy(v.model)
		m.file = glb
		v.model = m
	end
end

local function state_names(states)
	local names = {}
	for n in pairs(states) do names[#names + 1] = n end
	table.sort(names)
	return names
end

local function expand_states(key, b)
	local names = state_names(b.states)
	local combos = { {} }
	for _, n in ipairs(names) do
		local next_c = {}
		for _, c in ipairs(combos) do
			for _, v in ipairs(b.states[n]) do
				local x = copy(c)
				x[n] = v
				next_c[#next_c + 1] = x
			end
		end
		combos = next_c
	end
	local out = {}
	for i, st in ipairs(combos) do
		local v = copy(b)
		v.variant = nil
		if type(b.variant) == "function" then
			local ok, ch = pcall(b.variant, copy(st))
			if ok and type(ch) == "table" then
				for k, val in pairs(ch) do
					if k == "textures" and type(val) == "table" and type(v.textures) == "table" then
						local t = copy(v.textures)
						for f, spec in pairs(val) do t[f] = spec end
						v.textures = t
					else
						v[k] = val
					end
				end
			elseif not ok then
				host.report_error(b.mod or "?", "variant " .. key .. ": " .. tostring(ch))
			end
		end
		if v.texture and not v.textures then v.textures = { all = v.texture } v.texture = nil end
		do
			local parts = {}
			for _, n in ipairs(names) do parts[#parts + 1] = n .. "=" .. tostring(st[n]) end
			res_block(v, { key .. "[" .. table.concat(parts, ",") .. "]", key })
		end
		if st.facing ~= nil then v.textures = orient(v.textures, st.facing) end
		v.base = key
		v.state = st
		if i == 1 then
			v.key = key
			v.state_names = names
		else
			local parts = {}
			for _, n in ipairs(names) do parts[#parts + 1] = n .. "=" .. tostring(st[n]) end
			v.key = key .. "[" .. table.concat(parts, ",") .. "]"
			v.item = false
			v.variant_of = key
		end
		out[#out + 1] = v
	end
	return out
end

-- nazwy "@klucz" tłumaczone z plików lang/<język>.json moda
local function tr_name(d)
	if type(d) == "table" and type(d.name) == "string" and d.name:sub(1, 1) == "@" then
		d.name = host.t(d.mod or "", d.name:sub(2))
	end
end

local function finalize()
	R.frozen = true
	for _, k in ipairs(R.block_list) do tr_name(R.blocks[k]) end
	for _, k in ipairs(R.item_list) do tr_name(R.items[k]) end
	for _, d in pairs(R.entities) do tr_name(d) end
	for _, d in pairs(R.effects) do tr_name(d) end
	local blocks = {}
	local list = {}
	for _, key in ipairs(R.block_list) do
		local b = R.blocks[key]
		-- kształty gotowe dostają swoje stany (półblok: half; schody: facing i half)
		if b.shape == "slab" and b.states == nil then b.states = { half = { "bottom", "top" } } end
		if b.shape == "stairs" and b.states == nil then
			b.states = { facing = { "north", "east", "south", "west" }, half = { "bottom", "top" } }
			if b.place_facing == nil then b.place_facing = "away" end
		end
		if type(b.states) == "table" and next(b.states) ~= nil and not b.liquid then
			for _, v in ipairs(expand_states(key, b)) do list[#list + 1] = v end
		else
			res_block(b, { key })
			list[#list + 1] = b
		end
	end
	for _, b in ipairs(list) do
		local key = b.key
		local base = b.variant_of and R.blocks[b.variant_of] or b
		local has_item = b.item ~= false
		if has_item and R.items[key] == nil then
			put(R.items, R.item_list, key, {
				key = key, name = b.name, block = key, mod = b.mod, max_stack = b.max_stack or 64,
			})
		end
		local out = copy(b)
		out.variant = nil
		local boxes, connect = shape_of(b)
		if boxes then
			out.boxes = boxes
			out.connect = connect
			if b.transparent == nil then out.transparent = true end
		end
		out.drops = norm_drops(b.variant_of or key, b.drops, base.item ~= false)
		local ricon = res_file({ "items/" .. (b.variant_of or key) .. ".png" })
		if ricon ~= "" then out.icon = ricon end
		if out.texture then
			out.textures = out.textures or { all = out.texture }
			out.texture = nil
		end
		blocks[#blocks + 1] = out
	end
	local items = {}
	for _, key in ipairs(R.item_list) do
		local it = copy(R.items[key])
		local ricon = res_file({ "items/" .. key .. ".png" })
		if ricon ~= "" then it.icon = ricon end
		items[#items + 1] = it
	end
	-- stworzenia: model z pliku zamiast klocków (+ entities/<rodzaj>.json z ustawieniami modelu)
	for t, d in pairs(R.entities) do
		local glb = res_file({ "entities/" .. t .. ".glb" })
		if glb ~= "" then
			local m = { file = glb, animations = { idle = "Idle", walk = "Walk", run = "Run", attack = "Attack", hurt = "Hurt" } }
			local extra = to_lua(host.res_json("entities/" .. t .. ".json"))
			if type(extra) == "table" then for k, v in pairs(extra) do m[k] = v end end
			d.model = m
		end
	end
	-- dźwięki: sounds/<nazwa>.ogg albo kilka wersji sounds/<nazwa>.1.ogg, .2.ogg ...
	for name, d in pairs(R.sounds) do
		local files = {}
		for _, ext in ipairs({ "ogg", "wav", "mp3" }) do
			local one = res_file({ "sounds/" .. name .. "." .. ext })
			if one ~= "" then files[#files + 1] = one end
			for i = 1, 8 do
				local f = res_file({ "sounds/" .. name .. "." .. i .. "." .. ext })
				if f ~= "" then files[#files + 1] = f end
			end
		end
		if #files > 0 then d.files = files d.file = nil end
	end
	local biomes = {}
	for _, key in ipairs(R.biome_list) do biomes[#biomes + 1] = copy(R.biomes[key]) end
	local ores = {}
	for _, key in ipairs(R.ore_list) do ores[#ores + 1] = copy(R.ores[key]) end
	local structures = {}
	for key, s in pairs(R.structures) do structures[key] = norm_structure(s) end
	return to_godot({
		blocks = blocks, items = items, animations = copy(R.animations), entities = copy(R.entities),
		sounds = copy(R.sounds), particles = copy(R.particles), projectiles = copy(R.projectiles), effects = copy(R.effects),
		worldgen = { config = copy(R.config), biomes = biomes, ores = ores, structures = structures },
		texture_resolution = R.texture_res or 16,
	})
end

---------------------------------------------------------------------------
-- API dla moda
---------------------------------------------------------------------------
local function make_api(mod_id)
	local E = {}
	E.mod = { id = mod_id }

	-- tłumaczenie: engine.t("klucz", {nazwa = "Ola"}) -> tekst z lang/<język gracza>.json, "{nazwa}" podmienione
	function E.t(key, args)
		key = tostring(key):gsub("^@", "")
		local text = host.t(mod_id, key)
		if type(args) == "table" then
			text = text:gsub("{([%w_]+)}", function(k)
				local v = args[tonumber(k) or k]
				if v == nil then return "{" .. k .. "}" end
				return tostring(v)
			end)
		end
		return text
	end

	function E.log(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[#parts + 1] = tostring(select(i, ...)) end
		host.log(mod_id, table.concat(parts, " "))
	end

	-- zdarzenia
	function E.on(name, fn, priority) add_handler("event", name, fn, priority, mod_id) end
	function E.emit(name, data) return run("event", name, data or {}) end

	-- haki: before może ustawić ctx.cancel = true albo zmienić pola ctx; after widzi wynik
	E.hooks = {
		before = function(name, fn, priority) add_handler("before", name, fn, priority, mod_id) end,
		after = function(name, fn, priority) add_handler("after", name, fn, priority, mod_id) end,
	}

	-- biblioteki: mod udostępnia tabelę, inne mody ją pobierają (wymagają go w mod.json)
	function E.export(t) exports[mod_id] = t end
	-- biblioteka innego moda albo nil, gdy mod jest wyłączony (w mod.json: "after": [id])
	-- moduł zastąpiony przez inny mod ("replaces" w mod.json): biblioteka zastępcy
	local function lib(id)
		local t = exports[id]
		if t == nil then
			local r = host.mod_replacement(id)
			if r ~= "" then t = exports[r] end
		end
		return t
	end
	function E.optional(id) return lib(id) end

	function E.require(id)
		local t = lib(id)
		if t == nil then
			error("mod '" .. id .. "' nie jest wczytany; dodaj go do \"requires\" w mod.json", 2)
		end
		return t
	end

	E.settings = {
		get = function(key) return to_lua(host.setting(mod_id, key)) end,
	}

	E.storage = {
		get = function(key, default)
			local v = host.storage_get(mod_id, key)
			if v == nil then return default end
			return to_lua(v)
		end,
		set = function(key, value) host.storage_set(mod_id, key, to_godot(value)) end,
	}

	-- bloki: rejestracja w content.lua, zapytania w każdej chwili
	E.blocks = {
		AIR = 0,
		register = function(key, def)
			open_registry("blocks.register")
			assert(type(key) == "string", "blocks.register: pierwszy argument to klucz bloku")
			local d = copy(def or {})
			d.key = key
			d.mod = mod_id
			d.name = d.name or key
			return put(R.blocks, R.block_list, key, d)
		end,
		-- definicja bloku (tabela); w content.lua można ją zmieniać
		get = function(key) return R.blocks[key] end,
		id = function(key) return host.block_id(key) end,
		key = function(id) return host.block_key(id) end,
		name = function(id) return host.block_name(id) end,
		list = function() return to_lua(host.block_list()) end,
		-- stany: tabela stanu bloku w świecie, zmiana stanu (inny wariant tego samego bloku)
		state = function(pos) return to_lua(host.block_state(VI(pos))) or {} end,
		set_state = function(pos, changes) return host.block_set_state(VI(pos), to_godot(changes or {})) end,
		with_state = function(block, changes) return host.block_with_state(block, to_godot(changes or {})) end,
		base = function(block) return host.block_base(block) end,
		-- dane bloku: znikają razem z blokiem (zdarzenie block.removed)
		data = function(pos) return to_lua(host.block_data(VI(pos))) or {} end,
		set_data = function(pos, key, value) host.block_set_data(VI(pos), tostring(key), to_godot(value)) end,
		clear_data = function(pos) host.block_clear_data(VI(pos)) end,
		-- kontener przypisany do bloku (skrzynia): po zniszczeniu bloku przedmioty wypadają
		container = function(pos, size) return host.block_container(mod_id, VI(pos), size or 9) end,
		-- aktualizacje: fn(ctx) z ctx.reason = "random" | "scheduled" | "neighbor"
		on_update = function(keys, fn)
			if type(keys) == "string" then keys = { keys } end
			assert(type(fn) == "function", "blocks.on_update: drugi argument musi być funkcją")
			for _, k in ipairs(keys) do
				block_handlers[k] = block_handlers[k] or {}
				local l = block_handlers[k]
				l[#l + 1] = { fn = fn, owner = mod_id }
				host.block_listen(k)
			end
		end,
		-- model bloku: wygląd (anim, emitters, colors, hide) i jednorazowa animacja; widzą wszyscy gracze
		look = function(pos, look) host.block_look(VI(pos), to_godot(look or {})) end,
		get_look = function(pos) return to_lua(host.block_get_look(VI(pos))) or {} end,
		animate = function(pos, name) host.block_animate(VI(pos), tostring(name)) end,
		schedule = function(pos, seconds, tag) host.block_schedule(VI(pos), tonumber(seconds) or 1, tostring(tag or "")) end,
	}

	E.items = {
		register = function(key, def)
			open_registry("items.register")
			local d = copy(def or {})
			d.key = key
			d.mod = mod_id
			d.name = d.name or key
			return put(R.items, R.item_list, key, d)
		end,
		def = function(key) return R.items[key] end,
		-- klucze wszystkich przedmiotów w kolejności rejestracji
		list = function() local t = {} for i, k in ipairs(R.item_list) do t[i] = k end return t end,
		name = function(key) return host.item_name(key) end,
		block_of = function(key) local b = host.item_block(key); if b <= 0 then return nil end; return b end,
		-- per_player = true: każdy gracz ma własną kopię (ekwipunek); funkcje działają na kopii bieżącego gracza
		container = function(id, size, persist, per_player) host.container_create(mod_id, id, size, persist ~= false, per_player == true) end,
		size = function(id) return host.container_size(id) end,
		get = function(id, index) return to_lua(host.slot_get(id, index - 1)) end,
		set = function(id, index, slot) host.slot_set(id, index - 1, to_godot(slot or {})) end,
		max_stack = function(key) return host.max_stack(key or "") end,
		-- dane egzemplarza w miejscu kontenera (np. amunicja broni); stosy z różnymi danymi się nie łączą
		data = function(id, index) return (to_lua(host.slot_get(id, index - 1)) or {}).data or {} end,
		set_data = function(id, index, key, value)
			local s = to_lua(host.slot_get(id, index - 1)) or {}
			if s.item == nil then return false end
			s.data = s.data or {}
			s.data[key] = value
			host.slot_set(id, index - 1, to_godot(s))
			return true
		end,
		-- opis dynamiczny: fn(slot) zwraca listę linii; liczony na serwerze przy każdej zmianie miejsca
		tooltip = function(key, fn)
			assert(type(fn) == "function", "items.tooltip: drugi argument musi być funkcją")
			tooltip_fns[key] = { fn = fn, owner = mod_id }
			host.item_tooltip_register(key)
		end,
	}

	-- rozdzielczość tekstur bloków całej gry (content.lua): engine.textures.resolution(64);
	-- gra bierze największą z modów i paczek zasobów, gracz może ją zmienić w opcjach.
	-- Pojedynczy blok: pole resolution = 128 w jego definicji.
	E.textures = {
		resolution = function(n)
			open_registry("textures.resolution")
			R.texture_res = math.max(R.texture_res or 16, math.floor(tonumber(n) or 16))
		end,
	}

	E.worldgen = {
		-- generator w Lua (skrypty, serwer): fn(ch) dla każdego nowego chunka (nie wczytanego z dysku);
		-- ch.x/y/z (chunk), ch.min/max (narożniki w świecie), ch.get/set/height/biome/contains, ch.random(salt)
		on_generate = function(fn)
			assert(type(fn) == "function", "worldgen.on_generate potrzebuje funkcji")
			worldgen_fns[#worldgen_fns + 1] = { fn = fn, owner = mod_id }
			host.worldgen_on(mod_id)
		end,
		-- szum zależny od ziarna świata, -1..1; 2D: noise(x, z, skala, salt), 3D: noise3(x, y, z, skala, salt)
		noise = function(x, z, scale, salt, octaves) return host.gen_noise(x, nil, z, scale or 32, tostring(salt or ""), octaves or 1) end,
		noise3 = function(x, y, z, scale, salt, octaves) return host.gen_noise(x, y, z, scale or 32, tostring(salt or ""), octaves or 1) end,
		-- los deterministyczny: rng:next() 0..1, rng:int(a, b), rng:chance(p), rng:pick(lista)
		random = function(seed) return make_rng(type(seed) == "string" and str_hash(seed) or seed) end,
		config = function(t)
			open_registry("worldgen.config")
			for k, v in pairs(t) do R.config[k] = v end
		end,
		biome = function(key, def)
			open_registry("worldgen.biome")
			local d = copy(def or {})
			d.key = key
			d.mod = mod_id
			d.name = d.name or key
			d.features = d.features or {}
			d.plants = d.plants or {}
			return put(R.biomes, R.biome_list, key, d)
		end,
		get_biome = function(key) return R.biomes[key] end,
		remove_biome = function(key)
			open_registry("worldgen.remove_biome")
			R.biomes[key] = nil
			for i, k in ipairs(R.biome_list) do if k == key then table.remove(R.biome_list, i) break end end
		end,
		biomes = function() local out = {} for i, k in ipairs(R.biome_list) do out[i] = k end return out end,
		add_feature = function(biome, feature)
			open_registry("worldgen.add_feature")
			local b = assert(R.biomes[biome], "nie ma biomu " .. tostring(biome))
			b.features[#b.features + 1] = copy(feature)
		end,
		add_plant = function(biome, plant)
			open_registry("worldgen.add_plant")
			local b = assert(R.biomes[biome], "nie ma biomu " .. tostring(biome))
			b.plants[#b.plants + 1] = copy(plant)
		end,
		structure = function(key, def)
			open_registry("worldgen.structure")
			R.structures[key] = copy(def)
		end,
		ore = function(key, def)
			open_registry("worldgen.ore")
			local d = copy(def)
			d.key = key
			return put(R.ores, R.ore_list, key, d)
		end,
	}

	-- dźwięki: rejestracja w content.lua ({file = "sounds/x.ogg"} albo {files = {...}}, volume, pitch,
	-- pitch_random, range), odtwarzanie w skryptach
	E.sounds = {
		register = function(name, def)
			open_registry("sounds.register")
			local d = copy(def or {})
			d.mod = mod_id
			R.sounds[name] = d
		end,
		get = function(name) return R.sounds[name] end,
	}
	-- opts: pos (dźwięk w miejscu, słyszą gracze w pobliżu; bez pos słyszy tylko ten gracz), volume, pitch,
	-- loop (zwraca id do engine.sound.stop), player (id gracza: tylko on słyszy)
	E.sound = {
		play = function(name, opts) return host.sound_play(tostring(name), to_godot(opts or {})) end,
		stop = function(id) host.sound_stop(tonumber(id) or 0) end,
	}

	-- cząsteczki: opis efektu w content.lua, wybuch w skryptach (słyszą... widzą gracze w pobliżu)
	E.particles = {
		register = function(name, def)
			open_registry("particles.register")
			R.particles[name] = copy(def or {})
		end,
		get = function(name) return R.particles[name] end,
		spawn = function(name, pos, opts) host.particles_spawn(tostring(name), VF(pos), to_godot(opts or {})) end,
	}

	-- pociski: rodzaj w content.lua, wystrzał i obsługa trafienia w skryptach (fizyka i kolizje liczy serwer)
	E.projectiles = {
		register = function(type, def)
			open_registry("projectiles.register")
			R.projectiles[type] = copy(def or {})
		end,
		get = function(type) return R.projectiles[type] end,
		-- opts: position, direction (albo velocity), speed, owner (domyślnie bieżący gracz), data
		spawn = function(type, opts)
			opts = copy(opts or {})
			if opts.position then opts.position = VF(opts.position) end
			if opts.direction then opts.direction = VF(opts.direction) end
			if opts.velocity then opts.velocity = VF(opts.velocity) end
			if opts.owner == nil then opts.owner = host.player_id() end
			return host.projectile_spawn(tostring(type), to_godot(opts))
		end,
		remove = function(id) host.projectile_remove(tonumber(id) or -1) end,
		on_hit = function(type, fn)
			assert(type ~= nil and fn ~= nil, "projectiles.on_hit: podaj rodzaj i funkcję")
			projectile_handlers[type] = projectile_handlers[type] or {}
			local l = projectile_handlers[type]
			l[#l + 1] = { fn = fn, owner = mod_id }
		end,
	}

	-- efekty: opis w content.lua ({name, icon, color, stats = {speed = {mul = 1.5}}, negative}),
	-- nakładanie w skryptach (czas liczy silnik, ikona i czas na ekranie, zapis z kontem gracza)
	E.effects = {
		register = function(name, def)
			open_registry("effects.register")
			local d = copy(def or {})
			d.mod = mod_id
			R.effects[name] = d
		end,
		def = function(name) return R.effects[name] end,
		add = function(name, seconds, strength) return host.effect_add(tostring(name), tonumber(seconds) or 10, tonumber(strength) or 1) end,
		remove = function(name) host.effect_remove(tostring(name)) end,
		get = function(name) return to_lua(host.effect_get(tostring(name))) end,
		list = function() return to_lua(host.effect_list()) or {} end,
	}

	E.animation = {
		-- {length = 1.0, loop = false, tracks = {arm_right = {{0, {0,0,0}}, {0.5, {-90,0,0}}}, ...}}
		register = function(name, def)
			open_registry("animation.register")
			R.animations[name] = copy(def)
		end,
		-- zamiana wbudowanego stanu ("idle", "walk", "jump") na własną animację; nil przywraca
		override = function(state, name) host.anim_override(state, name or "") end,
	}

	E.entities = {
		-- rodzaj stworzenia: części modelu, AI, łup, pojawianie się (opis w docs/MODDING.md)
		register = function(type, def)
			open_registry("entities.register")
			local d = copy(def or {})
			d.mod = mod_id
			d.name = d.name or type
			R.entities[type] = d
			return d
		end,
		def = function(type) return R.entities[type] end,
		spawn = function(type, pos, data, scale) return host.entity_spawn(type, VF(pos), to_godot(data or {}), scale or 1.0) end,
		remove = function(id) host.entity_remove(id) end,
		exists = function(id) return host.entity_exists(id) end,
		type = function(id) return host.entity_get(id, "type") end,
		position = function(id) return host.entity_get(id, "pos") end,
		health = function(id) return host.entity_get(id, "health") end,
		state = function(id) return host.entity_get(id, "state") end,
		scale = function(id) return host.entity_get(id, "scale") end,
		list = function(type, radius) return to_lua(host.entity_list(type or "", radius or 0)) end,
		teleport = function(id, pos) host.entity_set(id, "pos", VF(pos)) end,
		move_to = function(id, pos) host.entity_set(id, "target", VF(pos)) end,
		set_scale = function(id, s) host.entity_set(id, "scale", s) end,
		damage = function(id, amount, cause) host.entity_damage(id, amount, cause or "mod") end,
		animate = function(id, name) host.entity_set(id, "animate", name) end,
		show = function(id, tag, on) host.entity_tag(id, tag, on ~= false, nil) end,
		color = function(id, tag, color) host.entity_tag(id, tag, true, color) end,
		data = function(id) return to_lua(host.entity_get(id, "data")) or {} end,
		set_data = function(id, key, value) host.entity_data(id, key, to_godot(value)) end,
		-- mózg: fn(ctx) co ai.think sekund (domyślnie 1) dla każdego stworzenia tego rodzaju na serwerze;
		-- ctx: id, type, state, pos, health, max_health, data, target, rider, player, player_distance, on_floor
		on_think = function(types, fn)
			if type(types) == "string" then types = { types } end
			assert(type(fn) == "function", "entities.on_think: drugi argument musi być funkcją")
			for _, k in ipairs(types) do
				entity_handlers[k] = entity_handlers[k] or {}
				local l = entity_handlers[k]
				l[#l + 1] = { fn = fn, owner = mod_id }
				host.entity_brain(k)
			end
		end,
		-- stan: "idle", "wander", "flee", "follow", "chase" albo własna nazwa (stoi przez `seconds`)
		set_state = function(id, state, seconds) host.entity_set(id, "state", { state, seconds or 5 }) end,
		attack = function(id, player) host.entity_set(id, "attack", player) end,
		target = function(id) return host.entity_get(id, "target") end,
		look_at = function(id, pos) host.entity_set(id, "look_at", VF(pos)) end,
		push = function(id, v) host.entity_set(id, "push", VF(v)) end,
		velocity = function(id) return host.entity_get(id, "velocity") end,
		-- jazda (pole ride w definicji): gracz domyślnie bieżący
		mount = function(id, player) return host.entity_mount(id, player or -1) end,
		dismount = function(player) host.entity_dismount(player or -1) end,
		rider = function(id) return host.entity_get(id, "rider") end,
		-- najbliższy gracz w promieniu: {id, distance, position} albo nil
		nearest_player = function(pos, radius) return to_lua(host.entity_nearest_player(VF(pos), radius or 16)) end,
		-- przedmiot leżący na ziemi; gracz podnosi go, podchodząc (hak item.pickup)
		-- data: dane egzemplarza (zostają po podniesieniu, hak item.pickup dostaje ctx.data)
		drop = function(item, count, pos, data) return host.item_drop(item, count or 1, VF(pos), to_godot(data or {})) end,
	}

	-- pogoda (serwer, widzą wszyscy): kind = "clear" | "rain" | "snow" | "storm", intensity 0..1
	-- deszcz w zimnych biomach pada jako śnieg, na pustyni nie pada; pod dachem opadów nie widać
	E.weather = {
		set = function(kind, intensity) host.weather_set(tostring(kind or "clear"), intensity or 1) end,
		get = function() return to_lua(host.weather_get()) end,
	}
	-- niebo: {top = kolor, horizon = kolor, fog = mnożnik mgły, sun = mnożnik słońca, ambient = mnożnik}
	E.sky = {
		set = function(t) host.sky_set(to_godot(t or {})) end,
		reset = function() host.sky_set({}) end,
	}

	-- polecenia czatu: /nazwa argumenty; fn(ctx) z ctx.player, ctx.name, ctx.args (lista słów), ctx.text, ctx.role
	-- zwraca tekst odpowiedzi dla gracza; permission: "player" | "moderator" | "admin"
	E.commands = {
		register = function(name, def)
			assert(type(name) == "string" and type(def) == "table" and type(def.fn) == "function",
				"commands.register: podaj nazwę i tabelę z polem fn")
			name = name:lower():gsub("^/", "")
			command_fns[name] = { fn = def.fn, owner = mod_id }
			host.command_register(mod_id, name, to_godot({ description = def.description, usage = def.usage, permission = def.permission }))
		end,
	}

	-- czat: send(tekst, {player = id (tylko on), color = "#rrggbb", from = "nadawca"})
	E.chat = {
		send = function(text, opts)
			opts = opts or {}
			host.chat_send(tostring(text), opts.color, opts.player or -1, opts.from)
		end,
	}

	E.world = {
		get_block = function(pos) return host.get_block(VI(pos)) end,
		-- promień od punktu w kierunku: {position, normal, place_pos, point, distance, block, key} albo nil
		raycast = function(from, dir, dist, opts)
			opts = opts or {}
			return to_lua(host.world_raycast(VF(from), VF(dir), tonumber(dist) or 32, opts.liquids == true, opts.solid ~= false))
		end,
		set_block = function(pos, id)
			if type(id) == "string" then id = host.block_id(id) end
			return host.set_block(VI(pos), id)
		end,
		biome = function(pos) return host.biome(VI(pos)) end,
		biome_key = function(pos) return host.biome_key(VI(pos)) end,
		height = function(x, z) return host.height(x, z) end,
		time = function() return host.time_of_day() end,
		-- światło: {sky, block} w skali 0..15 i day (0 noc .. 1 dzień)
		light = function(pos) return to_lua(host.world_light(VF(pos))) end,
		set_time = function(h) host.set_time(h) end,
	}

	-- gracze: w grze wieloosobowej kod moda działa zawsze w imieniu jednego gracza (ten, kto kopie,
	-- klika, naciska klawisz); engine.player.* dotyczy właśnie jego
	E.players = {
		list = function() return to_lua(host.players_list()) end,
		-- rola gracza: "player" | "moderator" | "admin" (gospodarz gry jest administratorem)
		role = function(id) return host.role_get(id or -1) end,
		set_role = function(id_or_account, role) host.role_set(id_or_account, role) end,
		-- wywołuje fn(gracz) w imieniu każdego zalogowanego gracza (np. głód co sekundę)
		each = function(fn)
			local prev = host.get_ctx()
			for _, p in ipairs(to_lua(host.players_list())) do
				host.set_ctx(p.id)
				local ok, err = pcall(fn, p)
				if not ok then
					if guard.tripped then host.set_ctx(prev); error(err, 0) end
					host.report_error(mod_id, "players.each: " .. tostring(err))
				end
			end
			host.set_ctx(prev)
		end,
		-- logowanie: przyjęcie gracza na konto (zwraca nil albo opis błędu) i wyrzucenie z serwera
		accept = function(id, account) local r = host.players_accept(id, account); if r == "" then return nil end; return r end,
		kick = function(id, reason) host.players_kick(id, reason or "") end,
	}

	function E.as_player(id, fn)
		local prev = host.get_ctx()
		host.set_ctx(id)
		local ok, err = pcall(fn)
		host.set_ctx(prev)
		if not ok then error(err, 2) end
	end

	E.is_multiplayer = function() return host.is_multiplayer() end
	E.hash = function(text) return host.hash(tostring(text)) end

	E.player = {
		id = function() return host.player_id() end,
		name = function() return host.player_name() end,
		is_host = function() return host.player_is_host() end,
		-- dane moda zapisywane osobno dla każdego konta gracza
		storage = {
			get = function(key, default)
				local v = host.pstorage_get(mod_id, key)
				if v == nil then return default end
				return to_lua(v)
			end,
			set = function(key, value) host.pstorage_set(mod_id, key, to_godot(value)) end,
		},
		position = function() return host.player_position() end,
		teleport = function(pos) host.player_teleport(VF(pos)) end,
		velocity = function() return host.player_velocity() end,
		push = function(v) host.player_push(VF(v)) end,
		set = function(stat, value) host.player_set(stat, value) end,
		get = function(stat) return host.player_get(stat) end,
		health = function() return host.player_health() end,
		max_health = function() return host.player_get("max_health") end,
		set_health = function(v) host.player_set_health(v) end,
		damage = function(amount, cause) host.player_damage(amount, cause or "mod") end,
		heal = function(amount) host.player_set_health(host.player_health() + amount) end,
		animate = function(name) host.player_animate(name) end,
		stop_animation = function() host.player_animate("") end,
		-- kolory części postaci: {tunic = "#aa3333", scarf = Color(...)} (klucze w docs/MODDING.md)
		colors = function(t) host.player_colors(to_godot(t)) end,
		-- postawa: "stand" | "crouch" | "crawl" | "sit" (zdarzenie player.pose przy zmianie)
		pose = function() return host.player_get_pose() end,
		-- rzecz założona na postać (widzą wszyscy): wear(id, {part = "head", boxes = {{size, pos, color, rot}}}),
		-- wear(id, nil) zdejmuje; części: body, head, arm_left, arm_right, leg_left, leg_right
		wear = function(id, spec) host.player_wear(tostring(id), spec and to_godot(spec) or nil) end,
		-- blok, w który celuje gracz: {pos, normal, block}; with_liquids = true uwzględnia ciecze
		target = function(with_liquids) return to_lua(host.player_target(with_liquids == true)) end,
		-- statystyki: base = wartość bez modyfikatorów; modify dokłada modyfikator od źródła (add, mul)
		base = function(stat) return host.player_base(stat) end,
		modify = function(stat, source, m)
			m = m or {}
			host.player_modify(stat, tostring(source), tonumber(m.add) or 0, tonumber(m.mul) or 1)
		end,
		unmodify = function(stat, source) host.player_unmodify(stat, tostring(source)) end,
		eye_position = function() return host.player_eye() end,
		look_direction = function() return host.player_look() end,
		raycast = function(dist, opts)
			opts = opts or {}
			return to_lua(host.world_raycast(host.player_eye(), host.player_look(), tonumber(dist) or 32, opts.liquids == true, opts.solid ~= false))
		end,
		in_liquid = function() return host.player_in_liquid() end,
		eyes_in_liquid = function() return host.player_eyes_in_liquid() end,
		selected_item = function() return to_lua(host.selected_item()) end,
	}

	E.camera = {
		set = function(key, value) host.camera_set(key, value) end,
		get = function(key) return host.camera_get(key) end,
		mode = function(m) if m then host.camera_set("mode", m) end return host.camera_get("mode") end,
	}

	E.hotbar = {
		bind = function(container, first, count) host.hotbar_bind(container, first - 1, count) end,
		unbind = function() host.hotbar_bind("", 0, 0) end,
		selected = function() return host.hotbar_selected() + 1 end,
	}

	E.ui = {
		-- okno opisane danymi: {id, title, sections = {{type="character"|"slots"|"text"|"button"|"input"|"progress", ...}}}
		-- przycisk dostaje tabelę wartości pól "input": on_press(fields), np. fields.login
		-- więcej rodzajów sekcji: image, row, tabs, list, slider, toggle, dropdown, item_button, separator, space
		-- (opis w docs/MODDING.md); on_change(fields) przy suwaku, przełączniku, liście, zakładkach
		window = function(spec)
			local n = 0
			local function walk(list)
				for _, s in ipairs(list or {}) do
					n = n + 1
					local fn = s.on_press or s.on_change
					if type(fn) == "function" then
						s.action = mod_id .. ":" .. tostring(s.id or s.text or s.item or n)
						window_actions[s.action] = { fn = fn, owner = mod_id }
						s.on_press, s.on_change = nil, nil
					end
					walk(s.sections)
					for _, t in ipairs(s.tabs or {}) do walk(t.sections) end
				end
			end
			walk(spec.sections)
			host.ui_window(mod_id, to_godot(spec))
		end,
		close = function(id) host.ui_close(id) end,
		is_open = function(id) return host.ui_is_open(id) end,
		notify = function(text) host.notify(tostring(text)) end,
		-- pasek na ekranie gry: {id, label, value, max, color}
		bar = function(spec) host.hud_bar(mod_id, to_godot(spec)) end,
		-- napis na ekranie gry: {id, text, color, font_size}
		text = function(spec) host.hud_text(mod_id, to_godot(spec)) end,
		-- obrazek na ekranie gry: {id, item | image, size = {w, h}, text, alpha}
		-- każdy element może mieć anchor ("top_left" .. "bottom_right", "center") i offset = {x, y}
		image = function(spec) host.hud_image(mod_id, to_godot(spec)) end,
		remove = function(id) host.hud_remove(id) end,
		-- przedmiot trzymany kursorem w oknie: {item, count} albo {}
		held = function() return to_lua(host.ui_held()) end,
		set_held = function(v) host.ui_set_held(to_godot(v or {})) end,
	}

	E.input = {
		-- {id, key = "E", label = "Plecak", on_press = function() ... end}
		bind = function(spec)
			assert(type(spec.on_press) == "function", "input.bind potrzebuje on_press")
			local id = mod_id .. ":" .. spec.id
			binds[id] = { fn = spec.on_press, owner = mod_id }
			host.input_bind(mod_id, id, spec.key or "", spec.label or spec.id)
		end,
	}

	E.random = function(a, b)
		if a == nil then return host.randf() end
		if b == nil then return host.randi(1, a) end
		return host.randi(a, b)
	end

	return E
end

---------------------------------------------------------------------------
-- Bezpieczne środowisko moda
---------------------------------------------------------------------------
local SAFE = {
	"assert", "error", "ipairs", "next", "pairs", "pcall", "select", "tonumber", "tostring",
	"type", "xpcall", "setmetatable", "getmetatable", "rawequal", "rawget", "rawset", "rawlen",
	"string", "table", "math", "utf8", "coroutine",
	"Vector2", "Vector2i", "Vector3", "Vector3i", "Vector4", "Color", "Rect2", "Array", "Dictionary",
	"Variant", "StringName",
}

local LIB_TABLES = { string = true, table = true, math = true, utf8 = true, coroutine = true }

local function make_env(mod_id)
	local env = {}
	for _, k in ipairs(SAFE) do
		-- biblioteki kopiujemy, żeby jeden mod nie mógł podmienić funkcji innym
		env[k] = LIB_TABLES[k] and copy(_G[k]) or _G[k]
	end
	env.coroutine = safe_coroutine()
	env.string = safe_string()
	env.pcall = safe_pcall
	env.xpcall = safe_xpcall
	env.engine = make_api(mod_id)
	env.print = env.engine.log
	env._G = env
	return env
end
make_env_ref = make_env

return { dispatch = dispatch, make_env = make_env, input = input, window_action = window_action, finalize = finalize, run_chunk = run_chunk, block_update = block_update, entity_think = entity_think, command = command, worldgen = worldgen, projectile_hit = projectile_hit, item_tooltip = item_tooltip, console = console }
