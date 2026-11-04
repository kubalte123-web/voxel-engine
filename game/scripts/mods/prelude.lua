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

	E.blocks = {
		id = function(key) return host.block_id(key) end,
		key = function(id) return host.block_key(id) end,
		name = function(id) return host.block_name(id) end,
		list = function() return to_lua(host.block_list()) end,
		AIR = 0,
	}

	E.world = {
		get_block = function(pos) return host.get_block(pos) end,
		set_block = function(pos, id) return host.set_block(pos, id) end,
		biome = function(pos) return host.biome(pos) end,
		time = function() return host.time_of_day() end,
	}

	E.player = {
		position = function() return host.player_position() end,
		set = function(stat, value) host.player_set(stat, value) end,
		get = function(stat) return host.player_get(stat) end,
	}

	E.camera = {
		set = function(key, value) host.camera_set(key, value) end,
		get = function(key) return host.camera_get(key) end,
	}

	E.items = {
		container = function(id, size, persist) host.container_create(mod_id, id, size, persist ~= false) end,
		size = function(id) return host.container_size(id) end,
		get = function(id, index) return to_lua(host.slot_get(id, index - 1)) end,
		set = function(id, index, slot) host.slot_set(id, index - 1, to_godot(slot or {})) end,
		max_stack = function() return host.max_stack() end,
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

local function make_env(mod_id)
	local env = {}
	for _, k in ipairs(SAFE) do env[k] = _G[k] end
	env.engine = make_api(mod_id)
	env.print = env.engine.log
	env._G = env
	return env
end

return { dispatch = dispatch, make_env = make_env, input = input, window_action = window_action }
