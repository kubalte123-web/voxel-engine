-- Kształty z prostopadłościanów: półbloki, schody, ogrodzenia, murki i szyby z istniejących bloków.
-- Tekstury bierzemy z bloku źródłowego (ścieżki plików dostają nazwę moda, np. "base:textures/planks.png").

local function textures_of(src_key)
	local src = engine.blocks.get(src_key)
	if not src then return nil end
	local function fix(t)
		if type(t) == "string" and not t:find(":") then return src.mod .. ":" .. t end
		return t
	end
	if src.textures then
		local out = {}
		for face, t in pairs(src.textures) do out[face] = fix(t) end
		return out
	end
	return { all = fix(src.texture) }
end

-- source = blok, z którego powstaje kształt; shape = rodzaj; name = nazwa w grze
local function shape(key, source, kind, name, extra)
	local tex = textures_of(source)
	if not tex then return end
	local src = engine.blocks.get(source)
	local def = {
		name = name,
		shape = kind,
		textures = tex,
		hardness = src.hardness,
		tool = src.tool,
		sound = src.sound,
	}
	for k, v in pairs(extra or {}) do def[k] = v end
	engine.blocks.register(key, def)
end

for _, s in ipairs({
	{ "planks", "Deski" }, { "stone", "Kamień" }, { "cobblestone", "Bruk" }, { "bricks", "Cegły" },
}) do
	shape(s[1] .. "_slab", s[1], "slab", s[2] .. " – półblok")
	shape(s[1] .. "_stairs", s[1], "stairs", s[2] .. " – schody")
end
shape("planks_fence", "planks", "fence", "Płot z desek")
shape("cobblestone_wall", "cobblestone", "wall", "Murek z bruku")
shape("glass_pane", "glass", "pane", "Szyba", { drops = false })

-- własny kształt: stolik (blat i noga) z prostopadłościanów w szesnastkach bloku
shape("planks_table", "planks", "boxes", "Stolik", {
	boxes = { { 0, 14, 0, 16, 16, 16 }, { 7, 0, 7, 9, 14, 9 } },
})

-- blok w wyższej rozdzielczości: tekstura 128 × 128 zostaje ostra, choć reszta świata ma 16 × 16
engine.blocks.register("marble_tiles", {
	name = "Płyty marmurowe",
	texture = "textures/marble_tiles.png",
	resolution = 128,
	hardness = 2.0, tool = "pickaxe", sound = "stone",
})
