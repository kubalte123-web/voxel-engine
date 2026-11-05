class_name Commands
## Polecenia czatu i konsoli (/help, /tp, /give, ...). Wbudowane są tutaj, mody dodają własne przez
## engine.commands.register. Działają na serwerze w imieniu gracza; polecenia z uprawnieniem "admin"
## wymagają roli administratora (gospodarz gry i konta nadane przez /op).

const BUILTIN := {
	"help": ["player", "/help – lista poleceń"],
	"reload": ["admin", "/reload – przeładowanie modów (bez innych graczy na serwerze)"],
}


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
	match name:
		"help":
			var lines := ["Polecenia:"]
			for k in BUILTIN:
				if BUILTIN[k][0] == "player" or role == "admin":
					lines.append("  " + BUILTIN[k][1])
			return "\n".join(lines)
		"reload":
			if role != "admin":
				return "Brak uprawnień (potrzebna rola administratora)."
			return main.reload_mods()
	return "Nie ma polecenia /%s. Wpisz /help." % name
