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
			if type(x) ~= "function" then d[k] = to_godot(x) end
		end
		return d
	end
	return v
end

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
	for _, h in ipairs(list) do
		local ok, err = pcall(h.fn, ctx)
		if not ok then host.report_error(h.owner, name .. ": " .. tostring(err)) end
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
		local ok, err = pcall(b.fn)
		if not ok then host.report_error(b.owner, "klawisz " .. id .. ": " .. tostring(err)) end
	end
end

local function window_action(id)
	local a = window_actions[id]
	if a then
		local ok, err = pcall(a.fn)
		if not ok then host.report_error(a.owner, "przycisk " .. id .. ": " .. tostring(err)) end
	end
end

---------------------------------------------------------------------------
-- Rejestr treści (faza content.lua): bloki, przedmioty, świat, animacje.
-- Definicje są zwykłymi tabelami Lua, więc mod wczytany później może je zmienić
-- (np. podmienić teksturę kamienia albo dodać drzewo do cudzego biomu).
---------------------------------------------------------------------------
local R = {
	frozen = false,
	blocks = {}, block_list = {},
	items = {}, item_list = {},
	biomes = {}, biome_list = {},
	ores = {}, ore_list = {},
	structures = {},
	config = { biome_scale = 1.0, beach_height = 7 },
	animations = {},
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

local function finalize()
	R.frozen = true
	local blocks = {}
	for _, key in ipairs(R.block_list) do
		local b = R.blocks[key]
		local has_item = b.item ~= false
		if has_item and R.items[key] == nil then
			put(R.items, R.item_list, key, {
				key = key, name = b.name, block = key, mod = b.mod, max_stack = b.max_stack or 64,
			})
		end
		local out = copy(b)
		out.drops = norm_drops(key, b.drops, has_item)
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
		blocks = blocks, items = items, animations = copy(R.animations),
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
		container = function(id, size, persist) host.container_create(mod_id, id, size, persist ~= false) end,
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

	E.animation = {
		-- {length = 1.0, loop = false, tracks = {arm_right = {{0, {0,0,0}}, {0.5, {-90,0,0}}}, ...}}
		register = function(name, def)
			open_registry("animation.register")
			R.animations[name] = copy(def)
		end,
		-- zamiana wbudowanego stanu ("idle", "walk", "jump") na własną animację; nil przywraca
		override = function(state, name) host.anim_override(state, name or "") end,
	}

	E.world = {
		get_block = function(pos) return host.get_block(pos) end,
		set_block = function(pos, id)
			if type(id) == "string" then id = host.block_id(id) end
			return host.set_block(pos, id)
		end,
		biome = function(pos) return host.biome(pos) end,
		biome_key = function(pos) return host.biome_key(pos) end,
		height = function(x, z) return host.height(x, z) end,
		time = function() return host.time_of_day() end,
		set_time = function(h) host.set_time(h) end,
	}

	E.player = {
		position = function() return host.player_position() end,
		teleport = function(pos) host.player_teleport(pos) end,
		velocity = function() return host.player_velocity() end,
		push = function(v) host.player_push(v) end,
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
		target = function() return to_lua(host.player_target()) end,
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
		-- okno opisane danymi: {id, title, sections = {{type="character"|"slots"|"text"|"button", ...}}}
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
	env.engine = make_api(mod_id)
	env.print = env.engine.log
	env._G = env
	return env
end

return { dispatch = dispatch, make_env = make_env, input = input, window_action = window_action, finalize = finalize }
