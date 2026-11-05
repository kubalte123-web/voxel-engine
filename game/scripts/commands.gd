class_name Commands
## Polecenia czatu i konsoli (/help, /tp, /give, ...). Wbudowane są tutaj, mody dodają własne przez
## engine.commands.register. Działają na serwerze w imieniu gracza. Uprawnienie polecenia to najniższa
## potrzebna rola: "player" < "moderator" < "admin". Gospodarz gry jest administratorem; role kont nadaje
## /op i /role (zapis w świecie), na serwerze dedykowanym także --admin=konto1,konto2.

const ROLES := ["player", "moderator", "admin"]

const BUILTIN := {
	"help": ["player", "/help [polecenie] – lista poleceń albo opis jednego"],
	"list": ["player", "/list – gracze w grze"],
	"me": ["player", "/me <tekst> – wiadomość w trzeciej osobie"],
	"mods": ["player", "/mods – włączone mody"],
	"tp": ["moderator", "/tp <x> <y> <z> | /tp <gracz> | /tp <gracz> <gracz>"],
	"give": ["admin", "/give <przedmiot> [ilość] [gracz]"],
	"time": ["moderator", "/time <godzina> | /time day | /time night"],
	"weather": ["moderator", "/weather clear|rain|snow|storm [siła 0-1]"],
	"kick": ["moderator", "/kick <gracz> [powód]"],
	"op": ["admin", "/op <konto> – nadaje rolę administratora"],
	"deop": ["admin", "/deop <konto> – odbiera rolę"],
	"role": ["admin", "/role <konto> [player|moderator|admin] – pokazuje albo zmienia rolę"],
	"reload": ["admin", "/reload – przeładowanie modów (bez innych graczy na serwerze)"],
}


static func level(role: String) -> int:
	return maxi(0, ROLES.find(role))


static func allowed(role: String, need: String) -> bool:
	return level(role) >= level(need)


static func run(main: Node, p: int, text: String) -> String:
	var t := text.strip_edges()
	if t.begins_with("/"):
		t = t.substr(1)
	var parts := t.split(" ", false)
	if parts.is_empty():
		return ""
	var name := parts[0].to_lower()
	var args: Array = Array(parts.slice(1))
	var role: String = main.role_of(p)
	var need := ""
	if BUILTIN.has(name):
		need = BUILTIN[name][0]
	elif Mods.mod_commands.has(name):
		need = str(Mods.mod_commands[name].get("permission", "player"))
	else:
		return "Nie ma polecenia /%s. Wpisz /help." % name
	if not allowed(role, need):
		return "Brak uprawnień: /%s wymaga roli „%s” (masz „%s”)." % [name, need, role]
	var ctx: Dictionary = Mods.as_player(p, func(): return Mods.before("command", {"player": p, "name": name, "args": args, "text": text}))
	if ctx.get("cancel", false):
		return str(ctx.get("reply", ""))
	if Mods.mod_commands.has(name) and not BUILTIN.has(name):
		var r: Variant = Mods.as_player(p, func(): return Mods.run_command(name, {"player": p, "name": Mods.sessions[p].account if Mods.sessions.has(p) else "", "args": args, "text": text, "role": role}))
		return str(r) if r != null else ""
	return _builtin(main, p, name, args, role)


static func _builtin(main: Node, p: int, name: String, args: Array, role: String) -> String:
	match name:
		"help":
			if not args.is_empty():
				var n := str(args[0]).trim_prefix("/").to_lower()
				if BUILTIN.has(n):
					return BUILTIN[n][1]
				if Mods.mod_commands.has(n):
					var d: Dictionary = Mods.mod_commands[n]
					return "%s – %s (mod %s)" % [str(d.get("usage", "/" + n)), str(d.get("description", "")), str(d.get("mod", ""))]
				return "Nie ma polecenia /%s." % n
			var lines := ["Polecenia (twoja rola: %s):" % role]
			for k in BUILTIN:
				if allowed(role, BUILTIN[k][0]):
					lines.append("  " + BUILTIN[k][1])
			var names := Mods.mod_commands.keys()
			names.sort()
			for k in names:
				var d: Dictionary = Mods.mod_commands[k]
				if allowed(role, str(d.get("permission", "player"))):
					lines.append("  %s – %s" % [str(d.get("usage", "/" + str(k))), str(d.get("description", ""))])
			return "\n".join(lines)
		"list":
			var names := []
			for q in Mods.sessions:
				var s: Session = Mods.sessions[q]
				if s.logged_in:
					names.append("%s (%s)" % [s.account, main.role_of(q)])
			return "Graczy: %d – %s" % [names.size(), ", ".join(names)]
		"me":
			var s: Session = Mods.sessions.get(p)
			main.broadcast_chat("", "* %s %s" % [s.account if s else "?", " ".join(args)], "#e0b0ff")
			return ""
		"mods":
			return "Mody: " + ", ".join(Mods.loaded)
		"tp":
			return _tp(main, p, args)
		"give":
			if args.is_empty():
				return BUILTIN.give[1]
			var item := str(args[0])
			if not Mods.registry.items.has(item):
				return "Nie ma przedmiotu „%s”." % item
			var count := int(args[1]) if args.size() > 1 and str(args[1]).is_valid_int() else 1
			var who := p
			if args.size() > 2:
				who = find_player(str(args[2]))
				if who < 0:
					return "Nie ma gracza „%s”." % str(args[2])
			count = clampi(count, 1, 9999)
			var left := give(main, who, item, count)
			return "Dano %d × %s%s." % [count, Mods.registry.item_name(item), " (część na ziemi)" if left > 0 else ""]
		"time":
			if args.is_empty():
				return "Godzina: %.1f" % float(main.time_of_day)
			var a := str(args[0]).to_lower()
			var h := 8.0 if a == "day" or a == "dzien" or a == "dzień" else 21.0 if a == "night" or a == "noc" else float(a)
			main.time_of_day = fposmod(h, 24.0)
			return "Ustawiono godzinę %.1f." % main.time_of_day
		"weather":
			if args.is_empty():
				return "Pogoda: %s (%.1f)" % [main.weather.kind, main.weather.target]
			var k := str(args[0]).to_lower()
			if not ["clear", "rain", "snow", "storm"].has(k):
				return BUILTIN.weather[1]
			main.set_weather({"kind": k, "intensity": float(args[1]) if args.size() > 1 else 1.0})
			return "Pogoda: " + k
		"kick":
			if args.is_empty():
				return BUILTIN.kick[1]
			var q := find_player(str(args[0]))
			if q < 0:
				return "Nie ma gracza „%s”." % str(args[0])
			if Mods.sessions[q].local:
				return "Nie można wyrzucić gospodarza gry."
			var reason := " ".join(args.slice(1)) if args.size() > 1 else "wyrzucony przez moderatora"
			Net.kick(q, reason)
			return "Wyrzucono %s." % str(args[0])
		"op", "deop":
			if args.is_empty():
				return BUILTIN[name][1]
			main.set_role(str(args[0]), "admin" if name == "op" else "player")
			return "%s ma teraz rolę %s." % [str(args[0]), "admin" if name == "op" else "player"]
		"role":
			if args.is_empty():
				return BUILTIN.role[1]
			if args.size() == 1:
				return "%s: %s" % [str(args[0]), main.role_of_account(str(args[0]))]
			var r := str(args[1]).to_lower()
			if not ROLES.has(r):
				return "Role: " + ", ".join(ROLES)
			main.set_role(str(args[0]), r)
			return "%s ma teraz rolę %s." % [str(args[0]), r]
		"reload":
			var err: String = main.reload_mods()
			return err if err != "" else "Mody przeładowane."
	return ""


## Id gracza po nazwie konta (bez wielkości liter) albo -1.
static func find_player(name: String) -> int:
	for q in Mods.sessions:
		var s: Session = Mods.sessions[q]
		if s.logged_in and s.account.to_lower() == name.to_lower():
			return q
	return -1


## Przedmioty dla gracza przez hak "item.pickup" (jak podniesienie z ziemi); reszta ląduje u jego stóp.
static func give(main: Node, p: int, item: String, count: int) -> int:
	var left := count
	var tries := 0
	while left > 0 and tries < 64:
		tries += 1
		var n := mini(left, Mods.registry.max_stack(item))
		var ctx: Dictionary = Mods.as_player(p, func(): return Mods.before("item.pickup", {"item": item, "count": n}))
		var taken := int(ctx.get("taken", 0))
		left -= taken
		if taken < n:
			break
	var node: Node3D = main.players.get(p)
	if left > 0 and node:
		main.entities.drop_item(item, left, node.global_position + Vector3(0, 1, 0))
	return left


static func _tp(main: Node, p: int, args: Array) -> String:
	var node: Node3D = main.players.get(p)
	if args.size() >= 3 and node:
		var cur: Vector3 = node.global_position if node else Vector3.ZERO
		var v := Vector3.ZERO
		for i in 3:
			var a := str(args[i])
			v[i] = cur[i] + float(a.substr(1)) if a.begins_with("~") else float(a)
		node.teleport(v)
		return "Przeniesiono na %d %d %d." % [int(v.x), int(v.y), int(v.z)]
	if args.size() == 1:
		var q := find_player(str(args[0]))
		if q < 0:
			return "Nie ma gracza „%s”." % str(args[0])
		node.teleport((main.players[q] as Node3D).global_position)
		return "Przeniesiono do %s." % str(args[0])
	if args.size() == 2:
		var a := find_player(str(args[0]))
		var b := find_player(str(args[1]))
		if a < 0 or b < 0:
			return "Nie ma takiego gracza."
		(main.players[a] as Node3D).teleport((main.players[b] as Node3D).global_position)
		return "Przeniesiono %s do %s." % [str(args[0]), str(args[1])]
	return BUILTIN.tp[1]
