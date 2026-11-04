-- Konta graczy: logowanie po dołączeniu do serwera.
-- Hak „player.login” zatrzymuje gracza (ctx.wait = true) i otwiera okno z loginem i hasłem.
-- Po poprawnym haśle engine.players.accept(id, login) wpuszcza gracza na konto `login`:
-- od tej chwili jego pozycja, ekwipunek i dane modów należą do tego konta.
-- Hasła nie są zapisywane: w świecie leży tylko sól i skrót SHA-256 (sól .. hasło).

local attempts = {}

local function accounts() return engine.storage.get("accounts", {}) end

local function new_salt()
	return string.format("%08x%08x", engine.random(0, 0x7fffffff), engine.random(0, 0x7fffffff))
end

local function valid_login(s)
	return type(s) == "string" and #s >= 3 and #s <= 24 and s:match("^[%w_%-]+$") ~= nil
end

local function open_login(name, message)
	local reg = engine.settings.get("allow_register")
	local sections = {
		{ type = "text", text = message or ("Witaj, " .. name .. "! Zaloguj się na swoje konto" .. (reg and " albo załóż nowe." or ".")) },
		{ type = "input", id = "login", label = "Login", text = name },
		{ type = "input", id = "password", label = "Hasło", secret = true },
		{ type = "button", id = "enter", text = "Zaloguj", on_press = function(f) try_login(f) end },
	}
	if reg then
		sections[#sections + 1] = { type = "button", id = "register", text = "Załóż konto", on_press = function(f) try_register(f) end }
	end
	sections[#sections + 1] = { type = "text", text = "Na to samo konto możesz wejść z innego urządzenia: wpisz ten sam login i hasło." }
	engine.ui.window({ id = "login", title = "Logowanie na serwer", closable = false, sections = sections })
end

local function fail(message)
	local id = engine.player.id()
	attempts[id] = (attempts[id] or 0) + 1
	if attempts[id] >= engine.settings.get("max_attempts") then
		engine.players.kick(id, "za dużo błędnych prób logowania")
		return
	end
	open_login(engine.player.name(), message)
end

local function enter(login)
	local err = engine.players.accept(engine.player.id(), login)
	if err then
		fail("Nie można wejść: " .. err)
		return
	end
	attempts[engine.player.id()] = nil
	engine.ui.close("login")
	engine.ui.notify("Zalogowano jako " .. login)
end

function try_login(f)
	local acc = accounts()[f.login or ""]
	if not acc then
		fail("Nie ma konta „" .. tostring(f.login) .. "”." .. (engine.settings.get("allow_register") and " Możesz je założyć." or ""))
		return
	end
	if engine.hash(acc.salt .. ":" .. (f.password or "")) ~= acc.hash then
		fail("Złe hasło.")
		return
	end
	enter(f.login)
end

function try_register(f)
	if not engine.settings.get("allow_register") then return end
	local login, pass = f.login or "", f.password or ""
	if not valid_login(login) then
		open_login(engine.player.name(), "Login: 3–24 znaki, tylko litery, cyfry, _ i -.")
		return
	end
	if #pass < 4 then
		open_login(engine.player.name(), "Hasło musi mieć co najmniej 4 znaki.")
		return
	end
	local all = accounts()
	if all[login] then
		open_login(engine.player.name(), "Konto „" .. login .. "” już istnieje. Zaloguj się albo wybierz inny login.")
		return
	end
	local salt = new_salt()
	all[login] = { salt = salt, hash = engine.hash(salt .. ":" .. pass) }
	engine.storage.set("accounts", all)
	enter(login)
end

engine.hooks.before("player.login", function(ctx)
	if not engine.is_multiplayer() then return end
	if engine.player.is_host() and not engine.settings.get("host_login") then return end
	ctx.wait = true
	open_login(ctx.name)
end)
