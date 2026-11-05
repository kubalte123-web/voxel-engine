-- Generator działa na serwerze dla każdego nowego chunka (32 x 32 x 32). Bloki poza chunkiem też można
-- stawiać – silnik dopisze je, gdy sąsiedni chunk powstanie.
local function bid(key) local i = engine.blocks.id(key) if i and i > 0 then return i end end
local AIR = 0
local STONE = bid("stone")
local COBBLE = bid("cobblestone") or STONE
local BRICKS = bid("bricks") or STONE
local MOSS = bid("leaves")
local CRYSTAL = bid("ruby_ore") or bid("iron_ore")
local GRASS_LANDS = { meadow = true, forest = true }

local function boulder(ch, rng, x, z)
	local h = ch.height(x, z)
	if h < ch.min.y - 3 or h > ch.max.y + 3 then return end   -- powierzchnia nie w tym chunku
	local r = rng:int(1, 2) + (rng:chance(0.3) and 1 or 0)
	for dx = -r, r do
		for dy = -r, r do
			for dz = -r, r do
				local d = dx * dx + dy * dy * 1.6 + dz * dz
				if d <= r * r + 0.5 then
					local b = rng:chance(0.7) and STONE or COBBLE
					if dy == r - 1 and MOSS and rng:chance(0.25) then b = MOSS end
					ch.set(x + dx, h + dy, z + dz, b)
				end
			end
		end
	end
end

local function ruin(ch, rng, x, z)
	local h = ch.height(x, z)
	if h < ch.min.y or h > ch.max.y - 8 then return end
	local w, d = rng:int(4, 6), rng:int(4, 6)
	for i = 0, w do
		for k = 0, d do
			local edge = i == 0 or k == 0 or i == w or k == d
			local gy = ch.height(x + i, z + k)
			ch.set(x + i, gy, z + k, COBBLE)        -- posadzka
			if edge then
				-- mur o nierównej wysokości, wyższy w narożnikach, z dziurami
				local corner = (i == 0 or i == w) and (k == 0 or k == d)
				local top = corner and rng:int(3, 5) or rng:int(0, 3)
				for y = 1, top do
					if rng:chance(0.85) then ch.set(x + i, gy + y, z + k, rng:chance(0.8) and BRICKS or COBBLE) end
				end
			else
				for y = 1, 4 do ch.set(x + i, gy + y, z + k, AIR) end
			end
		end
	end
end

engine.worldgen.on_generate(function(ch)
	local rng = ch.random("ruins")
	local cx, cz = ch.min.x, ch.min.z
	-- głazy: kilka prób na chunk, tylko na trawiastych biomach
	local tries = rng:int(0, 2)
	for _ = 1, tries do
		if rng:chance(engine.settings.get("boulders")) then
			local x, z = cx + rng:int(3, 28), cz + rng:int(3, 28)
			if GRASS_LANDS[ch.biome(x, z)] then boulder(ch, rng, x, z) end
		end
	end
	-- ruiny: rzadko, tam gdzie teren jest płaski
	if rng:chance(engine.settings.get("ruins")) then
		local x, z = cx + rng:int(4, 22), cz + rng:int(4, 22)
		if math.abs(ch.height(x, z) - ch.height(x + 6, z + 6)) <= 1 and ch.biome(x, z) ~= "desert" then ruin(ch, rng, x, z) end
	end
	-- kryształowe żyły w skale: szum 3D, tylko w chunkach pod powierzchnią
	if CRYSTAL and ch.max.y < ch.height(cx + 16, cz + 16) - 4 then
		for i = 1, 60 do
			local x, y, z = cx + rng:int(0, 31), ch.min.y + rng:int(0, 31), cz + rng:int(0, 31)
			if engine.worldgen.noise3(x, y, z, 12, "krysztaly") > 0.55 and ch.get(x, y, z) == STONE then
				ch.set(x, y, z, CRYSTAL)
			end
		end
	end
end)
