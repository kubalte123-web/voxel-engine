extends SceneTree
## Test zabezpieczeń Lua: pętla bez końca, pętla z pcall, korutyna, zjadanie pamięci, bajtkod,
## podmiana metatabeli tekstów. Gra ma przeżyć każdy przypadek, a winny mod ma zostać wyłączony.
## Uruchomienie: godot --headless --path game -s tests/lua_guard.gd


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mods: Node = root.get_node("/root/Mods")
	mods.start_content("")
	var cases := {
		"petla": "while true do end",
		"pcall": "while true do pcall(function() while true do end end) end",
		"korutyna": "local co = coroutine.wrap(function() while true do end end) co()",
		"pamiec": "local t = {} for i = 1, 1e9 do t[i] = string.rep('x', 1000) .. i end",
		"rep": "local s = string.rep('x', 1e10)",
		"bajtkod": "return load(string.dump(function() end))",
		"metatabela": "getmetatable('').__index = nil",
		"debug": "debug.sethook()",
		"ok": "x = 1 + 1",
	}
	for name in cases:
		var env: Variant = mods._api.make_env.invoke("test_" + name)
		var t0 := Time.get_ticks_msec()
		var r: Variant = mods._api.run_chunk.invoke("test_" + name, cases[name], "@" + name, env)
		print("GUARD %-10s %5d ms  -> %s" % [name, Time.get_ticks_msec() - t0, str(r).left(90).replace("\n", " ")])
	# po wyłączeniu mod nie wykonuje już kodu, a inne mody działają
	var env2: Variant = mods._api.make_env.invoke("test_ok")
	print("GUARD po testach: ", mods._api.run_chunk.invoke("test_ok", "y = 2", "@ok2", env2))
	print("GUARD wyłączone: ", mods.load_errors.keys())
	quit()
