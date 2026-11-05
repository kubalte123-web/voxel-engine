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
	local ok, err = pcall(fn, ...)
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

local function finalize()
	R.frozen = true
	local blocks = {}
	local list = {}
	for _, key in ipairs(R.block_list) do
		local b = R.blocks[key]
		if type(b.states) == "table" and next(b.states) ~= nil and not b.liquid then
			for _, v in ipairs(expand_states(key, b)) do list[#list + 1] = v end
		else
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
		out.drops = norm_drops(b.variant_of or key, b.drops, base.item ~= false)
		if out.texture then
			out.textures = out.textures or { all = out.texture }
			out.texture = nil
		end
		blocks[#blocks + 1] = out
	end
	local items = {}
	for _, key in ipairs(R.item_list) do items[#items + 1] = copy(R.items[key]) end
	local biomes = {}
	for _, key in ipairs(R.biome_list) do biomes[#biomes + 1] = copy(R.biomes[key]) end
	local ores = {}
	for _, key in ipairs(R.ore_list) do ores[#ores + 1] = copy(R.ores[key]) end
	local structures = {}
	for key, s in pairs(R.structures) do structures[key] = norm_structure(s) end
	return to_godot({
		blocks = blocks, items = items, animations = copy(R.animations), entities = copy(R.entities),
		sounds = copy(R.sounds), particles = copy(R.particles),
		worldgen = { config = copy(R.config), biomes = biomes, ores = ores, structures = structures },
	})
end

---------------------------------------------------------------------------
-- API dla moda
---------------------------------------------------------------------------
local function make_api(mod_id)
	local E = {}
	E.mod = { id = mod_id }

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
	function E.optional(id) return exports[id] end

	function E.require(id)
		local t = exports[id]
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
		name = function(key) return host.item_name(key) end,
		block_of = function(key) local b = host.item_block(key); if b <= 0 then return nil end; return b end,
		-- per_player = true: każdy gracz ma własną kopię (ekwipunek); funkcje działają na kopii bieżącego gracza
		container = function(id, size, persist, per_player) host.container_create(mod_id, id, size, persist ~= false, per_player == true) end,
		size = function(id) return host.container_size(id) end,
		get = function(id, index) return to_lua(host.slot_get(id, index - 1)) end,
		set = function(id, index, slot) host.slot_set(id, index - 1, to_godot(slot or {})) end,
		max_stack = function(key) return host.max_stack(key or "") end,
	}

	E.worldgen = {
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
		-- przedmiot leżący na ziemi; gracz podnosi go, podchodząc (hak item.pickup)
		drop = function(item, count, pos) return host.item_drop(item, count or 1, VF(pos)) end,
	}

	E.world = {
		get_block = function(pos) return host.get_block(VI(pos)) end,
		set_block = function(pos, id)
			if type(id) == "string" then id = host.block_id(id) end
			return host.set_block(VI(pos), id)
		end,
		biome = function(pos) return host.biome(VI(pos)) end,
		biome_key = function(pos) return host.biome_key(VI(pos)) end,
		height = function(x, z) return host.height(x, z) end,
		time = function() return host.time_of_day() end,
		set_time = function(h) host.set_time(h) end,
	}

	-- gracze: w grze wieloosobowej kod moda działa zawsze w imieniu jednego gracza (ten, kto kopie,
	-- klika, naciska klawisz); engine.player.* dotyczy właśnie jego
	E.players = {
		list = function() return to_lua(host.players_list()) end,
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
		-- blok, w który celuje gracz: {pos, normal, block}; with_liquids = true uwzględnia ciecze
		target = function(with_liquids) return to_lua(host.player_target(with_liquids == true)) end,
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
		window = function(spec)
			for _, s in ipairs(spec.sections or {}) do
				if s.type == "button" and type(s.on_press) == "function" then
					s.action = mod_id .. ":" .. (s.id or s.text)
					window_actions[s.action] = { fn = s.on_press, owner = mod_id }
				end
			end
			host.ui_window(mod_id, to_godot(spec))
		end,
		close = function(id) host.ui_close(id) end,
		is_open = function(id) return host.ui_is_open(id) end,
		notify = function(text) host.notify(tostring(text)) end,
		-- pasek na ekranie gry: {id, label, value, max, color}
		bar = function(spec) host.hud_bar(mod_id, to_godot(spec)) end,
		-- napis na ekranie gry: {id, text, color}
		text = function(spec) host.hud_text(mod_id, to_godot(spec)) end,
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

return { dispatch = dispatch, make_env = make_env, input = input, window_action = window_action, finalize = finalize, run_chunk = run_chunk, block_update = block_update }
