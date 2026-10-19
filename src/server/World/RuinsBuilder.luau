--[[
	RuinsBuilder — the Forgotten Ruins (improved)

	Layout (local coordinates, arrival at the south, temple to the north):
	  • South: arrival & return portal, the Watchers' tablet path.
	  • Main avenue (cobbled, lined with columns) running north to the
	    OBELISK crossroads — the hub of the zone.
	  • West path › the fallen COLOSSUS (landmark). A slab leaning on its
	    plinth hides a crawl-gap alcove with a chest.
	  • East path › a narrow CANYON leading to the CAVE.
	  • North › the SUNKEN TEMPLE: glyph plates, secret door, hidden chamber.
	  • North-west rock shelf › the Star Watcher, reached by jumping up
	    stepping stones (a difficult-to-reach spot).

	Discovery: three Watcher statues hold the glyph-order riddle; visible dig
	sites use the excavation challenge; HIDDEN caches have no marker at all —
	only a clue (odd soil, a pottery shard, a stone ring, a broken statue,
	glinting rocks) and the scanner lead you to them.
]]

local CollectionService = game:GetService("CollectionService")

local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local SiteTags = require(script.Parent.SiteTags)
local Secrets = require(script.Parent.Secrets)

local RuinsBuilder = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local UP = CFrame.Angles(0, 0, rad(90))
local M = Enum.Material
local C = Color3.fromRGB
local P = Props.P

local ZONE = "ForgottenRuins"
local PAL = Props.Sand
local RUIN = C(196, 180, 150)
local RUIN_DARK = C(150, 135, 110)
local GOLD = C(214, 172, 60)

local function terrain(origin: CFrame)
	local t = workspace.Terrain
	local base = origin.Position
	t:FillBlock(CF(base + V(0, -6, 0)), V(372, 12, 372), M.Sand)
	-- Dunes around the edge
	local rng = Random.new(77)
	for i = 0, 27 do
		local a = i / 28 * math.pi * 2
		local r = rng:NextNumber(150, 168)
		local y, size = rng:NextNumber(-10, -4), rng:NextNumber(16, 26)
		-- No dune over the arrival point / return portal (south, a ≈ 270°):
		-- one used to bury players who travelled here.
		if math.abs(a - math.pi * 1.5) > 0.45 then
			t:FillBall(base + V(math.cos(a) * r, y, math.sin(a) * r), size, M.Sand)
		end
	end
	-- Rock outcrops & the canyon walls to the east
	for _, p in { V(150, -4, -150), V(-155, -2, -120), V(160, 0, 70), V(-160, 0, 20) } do
		t:FillBall(base + p, 22, M.Sandstone)
	end
	for z = -32, 32, 6 do
		t:FillBlock(CF(base + V(48, 7, z)), V(10, 18, 7), M.Sandstone)
		t:FillBlock(CF(base + V(72, 7, z)), V(10, 18, 7), M.Sandstone)
	end
	-- Paths
	t:FillBlock(CF(base + V(0, -1, -50)), V(12, 2, 220), M.Cobblestone) -- main avenue
	t:FillBlock(CF(base + V(-55, -1, -40)), V(90, 2, 8), M.Ground) -- west path
	t:FillBlock(CF(base + V(40, -1, -40)), V(40, 2, 8), M.Ground) -- east path start
	t:FillBlock(CF(base + V(60, -1, 0)), V(8, 2, 80), M.Ground) -- canyon floor (runs north)
	t:FillBlock(CF(base + V(72, -1, 40)), V(30, 2, 8), M.Ground) -- canyon exit
	t:FillBlock(CF(base + V(85, -1, 70)), V(8, 2, 64), M.Ground) -- path to the cave
	-- Raised plateau under the temple
	t:FillBlock(CF(base + V(0, -2, 115)), V(90, 6, 70), M.Sandstone)
	-- Star Watcher's rock shelf (north-west) with stepping stones
	t:FillBlock(CF(base + V(-140, 6, 120)), V(26, 24, 26), M.Sandstone)
	-- Keep the arrival area and return portal clear of terrain (the base sand below y 0 stays).
	t:FillBlock(CF(base + V(0, 25, -152)), V(60, 50, 70), M.Air)
end

-- One Watcher statue + its inscription stele.
local function watcher(f: Instance, o: CFrame, x: number, z: number, yaw: number, name: string, emblem: Color3, clueId: string, text: string, baseY: number?)
	local origin = o * CF(0, baseY or 0, 0)
	Props.Statue(f, origin, x, z, yaw, PAL, emblem)
	local face = Props.Stele(f, origin * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0), 0, -5, 0, PAL, name .. " WATCHER")
	SiteTags.Inscription(face, clueId, name .. " Watcher", text)
end

function RuinsBuilder.Build(world: Instance, o: CFrame)
	local zone = Build.Folder(world, ZONE)
	local rng = Random.new(1234)
	terrain(o)

	-- ── Arrival & return portal ────────────────────────────────────────────
	local rf = CF(0, 0, -160)
	Build.Part(zone, o * rf, V(3, 14, 3), CF(-6, 7, 0), P(RUIN, M.Sandstone))
	Build.Part(zone, o * rf, V(3, 14, 3), CF(6, 7, 0), P(RUIN, M.Sandstone))
	Build.Part(zone, o * rf, V(16, 3, 3.4), CF(0, 15, 0), P(RUIN_DARK, M.Sandstone))
	local back = Build.Part(zone, o * rf, V(9, 12, 0.6), CF(0, 7, 0), P(C(255, 200, 90), M.Neon, { Transparency = 0.35, CanCollide = false, Name = "ReturnPortal" }))
	Build.Light(back, C(255, 200, 90), 22, 2)
	local backSign = Build.Part(zone, o * rf, V(12, 2.2, 0.4), CF(0, 18.5, 0.3), P(C(32, 78, 60)))
	Build.Label(backSign, Enum.NormalId.Back, "RETURN TO YOUR MUSEUM", GOLD)
	local arrival = Instance.new("Part")
	arrival.Name = "ArrivalPoint"
	arrival.Anchored = true
	arrival.CanCollide = false
	arrival.Transparency = 1
	arrival.Size = V(1, 1, 1)
	arrival.CFrame = o * CF(0, 4, -146)
	arrival.Parent = zone

	-- Welcome stele pointing explorers at the Watchers
	local welcome = Props.Stele(zone, o, -9, -138, 0, PAL, "THREE WATCHERS GUARD THESE SANDS")
	SiteTags.Inscription(welcome, "ruins_welcome", "Expedition notes", "Three Watcher statues guard the ruins: SUN by the fallen Colossus, MOON at the canyon mouth, STAR on the high rocks to the north-west. Read them, then step on the temple glyphs in their order.")

	-- ── Main avenue with columns ───────────────────────────────────────────
	local avenue = Build.Folder(zone, "Avenue")
	for z = -125, 30, 22 do
		for _, x in { -11, 11 } do
			local roll = rng:NextNumber()
			if roll < 0.25 then
				Props.FallenColumn(avenue, o, x + rng:NextNumber(-4, 4) * (if x < 0 then 1 else -1) * -1, z + 3, rng:NextNumber(9, 13), rng:NextNumber(20, 160), PAL)
			else
				Props.Column(avenue, o, x, z, if roll < 0.55 then rng:NextNumber(5, 9) else rng:NextNumber(13, 17), PAL, roll < 0.55, rng:NextNumber(-4, 4))
			end
		end
	end

	-- ── Obelisk crossroads (central landmark) ──────────────────────────────
	local ob = Build.Folder(zone, "Obelisk")
	Build.Part(ob, o, V(9, 1.5, 9), CF(0, 0.75, -40), P(RUIN_DARK, M.Slate))
	for i = 0, 4 do
		local s = 5 - i * 0.7
		Build.Part(ob, o, V(s, 5, s), CF(0, 4 + i * 5, -40), P(RUIN, M.Sandstone))
	end
	local cap = Build.Part(ob, o, V(1.8, 2.4, 1.8), CF(0, 28.5, -40) * CFrame.Angles(0, rad(45), 0), P(GOLD, M.Metal))
	Build.Light(cap, C(255, 220, 150), 30, 1)
	local obFace = Build.Part(ob, o, V(3.6, 4, 0.2), CF(0, 6, -42.6), P(RUIN, M.Sandstone, { CanCollide = false }))
	Build.Label(obFace, Enum.NormalId.Front, "← COLOSSUS     TEMPLE ↑     CANYON ›", C(90, 60, 30), Enum.Font.Fondamento)

	-- ── West: the fallen Colossus ──────────────────────────────────────────
	local col = Build.Folder(zone, "Colossus")
	local cx, cz = -112, -30
	Build.Part(col, o, V(16, 5, 14), CF(cx, 2.5, cz), P(RUIN_DARK, M.Slate)) -- plinth
	Build.Part(col, o, V(5, 9, 6), CF(cx - 3.5, 9.5, cz), P(RUIN, M.Sandstone)) -- standing legs
	Build.Part(col, o, V(5, 7, 6), CF(cx + 3.5, 8.5, cz), P(RUIN, M.Sandstone))
	Build.Part(col, o, V(5.4, 2, 8), CF(cx - 3.5, 5.6, cz - 1.2), P(RUIN, M.Sandstone)) -- feet
	Build.Part(col, o, V(5.4, 2, 8), CF(cx + 3.5, 5.6, cz - 1.2), P(RUIN, M.Sandstone))
	-- The giant head, half buried in the sand, tilted
	local headCF = CF(cx + 26, 3, cz - 12) * CFrame.Angles(rad(-20), rad(35), rad(28))
	Build.Part(col, o, V(16, 16, 16), headCF, P(RUIN, M.Sandstone, { Shape = Enum.PartType.Ball }))
	Build.Part(col, o, V(3, 5, 3.5), headCF * CF(0, -0.5, -7.8), P(RUIN, M.Sandstone)) -- nose
	Build.Part(col, o, V(3.4, 1.4, 1), headCF * CF(-3.2, 2.2, -7.4), P(RUIN_DARK, M.Sandstone)) -- brows
	Build.Part(col, o, V(3.4, 1.4, 1), headCF * CF(3.2, 2.2, -7.4), P(RUIN_DARK, M.Sandstone))
	Build.Part(col, o, V(5, 1, 1), headCF * CF(0, -4, -7), P(RUIN_DARK, M.Sandstone)) -- lips
	-- A slab leaning on the plinth leaves a crawl gap to a hidden alcove
	Build.Part(col, o, V(14, 1.4, 12), CF(cx - 1, 4.2, cz + 12) * CFrame.Angles(rad(-35), 0, 0), P(RUIN, M.Slate))
	Build.Box(col, o, V(cx - 8, 0, cz + 7), V(cx - 7, 4, cz + 14), P(RUIN_DARK, M.Slate))
	Build.Box(col, o, V(cx + 5, 0, cz + 7), V(cx + 6, 4, cz + 14), P(RUIN_DARK, M.Slate))
	local alcoveChest = Props.Chest(col, o, CF(cx - 1, 0, cz + 10), C(95, 60, 35))
	SiteTags.Register(alcoveChest, "Chest", ZONE, { DisplayName = "Colossus Alcove Chest" })
	Props.Debris(col, o, cx, cz - 10, 10, 14, rng, RUIN)
	watcher(col, o, cx + 18, cz + 18, 200, "SUN", C(255, 170, 60), "watcher_sun", "\"When I rise, the day begins. I am FIRST.\" — the Sun Watcher")

	-- ── East: canyon to the cave ───────────────────────────────────────────
	local canyon = Build.Folder(zone, "Canyon")
	watcher(canyon, o, 58, -52, 20, "MOON", C(170, 190, 255), "watcher_moon", "\"I follow the light into the night. I am SECOND.\" — the Moon Watcher")
	for z = -26, 26, 13 do
		Props.Rock(canyon, o, 60 + rng:NextNumber(-2, 2), z, rng:NextNumber(2, 4), rng, C(170, 145, 110))
	end
	-- Ledge urn in the canyon wall (reach it by climbing the boulders)
	-- Boulder steps up the east wall to a ledge on top (difficult to reach)
	for i, h in { 2, 5, 8, 11, 14 } do
		Build.Part(canyon, o, V(4, 1.2, 4), CF(64.5, h, -12 + i * 3.2), P(C(175, 150, 115), M.Sandstone))
	end
	Build.Part(canyon, o, V(7, 1.2, 7), CF(70, 16.6, 8), P(C(175, 150, 115), M.Sandstone))
	local ledgeUrn = Props.Urn(canyon, o * CF(0, 17.2, 0), 70, 8, C(160, 90, 55), rng)
	SiteTags.Register(ledgeUrn, "Urn", ZONE, { DisplayName = "Canyon Ledge Urn" })
	local dust = Build.Part(canyon, o, V(10, 1, 50), CF(60, 10, 0), P(C(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CanCollide = false }))
	local blow = Instance.new("ParticleEmitter")
	blow.Color = ColorSequence.new(C(220, 195, 150))
	blow.Size = NumberSequence.new(1.5)
	blow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.8), NumberSequenceKeypoint.new(1, 1) })
	blow.Lifetime = NumberRange.new(3, 5)
	blow.Rate = 6
	blow.Speed = NumberRange.new(4, 7)
	blow.EmissionDirection = Enum.NormalId.Front
	blow.Parent = dust

	-- ── Partially buried structures & storytelling debris ─────────────────
	local buried = Build.Folder(zone, "Buried")
	Props.BuriedArch(buried, o, -45, -95, 25, PAL)
	Props.BuriedArch(buried, o, 25, 60, -60, PAL)
	Props.BuriedArch(buried, o, -80, 70, 80, PAL)
	for _, p in { V(-60, 0, 0), V(30, 0, -15), V(-30, 0, 55), V(120, 0, -20) } do
		Props.FallenColumn(buried, o, p.X, p.Z, rng:NextNumber(10, 15), rng:NextNumber(0, 180), PAL)
		Props.Debris(buried, o, p.X, p.Z, 5, 6, rng, RUIN_DARK)
	end
	-- Long buried wall, only its top showing
	Build.Part(buried, o, V(30, 2.5, 2), CF(-95, 1, 110) * CFrame.Angles(0, rad(15), 0), P(RUIN_DARK, M.Sandstone))
	-- Bones of an old expedition camp
	Build.Part(buried, o, V(6, 0.2, 4), CF(25, 0.1, -120), P(C(170, 150, 110), M.Fabric, { CanCollide = false }))
	Build.Part(buried, o, V(0.3, 5, 0.3), CF(23, 2.5, -121), P(C(110, 80, 50), M.Wood))
	Build.Part(buried, o, V(0.3, 5, 0.3), CF(27, 2.5, -121), P(C(110, 80, 50), M.Wood))
	Build.Part(buried, o, V(5, 0.2, 3.5), CF(25, 4.6, -120) * CFrame.Angles(rad(15), 0, 0), P(C(200, 180, 140), M.Fabric, { CanCollide = false }))
	local camp = Props.Stele(buried, o, 29, -116, -30, PAL, nil)
	SiteTags.Inscription(camp, "ruins_journal", "Abandoned journal", "\"Day 12. The detector whines near the dark patches of sand west of the arch. Something metal is buried there, I'm sure of it.\"")

	-- Vegetation
	for _ = 1, 26 do
		local x, z = rng:NextNumber(-160, 160), rng:NextNumber(-150, 160)
		if math.abs(x) > 18 and not (x > 38 and x < 82 and math.abs(z) < 42) and not (math.abs(x) < 40 and z > 75) then
			if rng:NextNumber() < 0.45 then
				Props.Palm(zone, o, x, z, rng)
			else
				Props.Shrub(zone, o, x, z, rng)
			end
		end
	end

	-- ── Quick search sites ─────────────────────────────────────────────────
	for _, p in { V(-26, 0, -55), V(30, 0, -62), V(-110, 0, 60), V(95, 0, -120) } do
		local main = Build.Part(zone, o, V(5, 3, 4), CF(p.X, 1.5, p.Z) * CFrame.Angles(0, rng:NextNumber(0, 3), rad(10)), P(RUIN_DARK, M.Slate))
		Props.Debris(zone, o, p.X, p.Z, 3.5, 6, rng, RUIN)
		SiteTags.Register(main, "Rubble", ZONE)
	end
	for _, p in { V(-22, 0, 8), V(24, 0, 14), V(110, 0, -60), V(-125, 0, -85) } do
		local urn = Props.Urn(zone, o, p.X, p.Z, C(175, 100, 60), rng)
		SiteTags.Register(urn, "Urn", ZONE)
	end

	-- ── Visible excavation sites (skill-based) ─────────────────────────────
	local digs = Build.Folder(zone, "DigSites")
	for i, p in { V(-55, 0, -110), V(52, 0, -130), V(-40, 0, 32), V(100, 0, 10) } do
		local mound = Props.DigSite(digs, o, p.X, p.Z, C(125, 90, 58))
		SiteTags.Register(mound, "DigSite", ZONE, { DisplayName = "Excavation Site " .. string.char(64 + i), Fragile = i % 2 == 0 })
	end

	-- ── Hidden caches: clue in the world, position only on the server ─────
	local clues = Build.Folder(zone, "Clues")
	local function cache(id: string, pos: Vector3, depth: number, boost: number, decoy: boolean?, decoyKind: string?)
		Secrets.AddCache({
			Id = id,
			Zone = ZONE,
			Position = (o * CF(pos)).Position,
			Depth = depth,
			Decoy = decoy == true,
			DecoyKind = decoyKind,
			RareBoost = boost,
			Name = if decoy then "Strange signal" else "Buried cache",
		})
	end
	Props.SoilPattern(clues, o, -95, -100, C(150, 120, 85))
	cache("ruins_soil", V(-92, 0, -97), 1, 1.6)
	Props.PotteryShard(clues, o, 112, -82, C(170, 95, 60))
	cache("ruins_shard", V(115, 0, -78), 2, 1.9)
	Props.StoneRing(clues, o, -122, 82, C(140, 125, 100))
	cache("ruins_ring", V(-122, 0, 82), 2, 2.1)
	Props.Statue(clues, o, 42, 128, 160, PAL, nil, true) -- headless, broken statue
	cache("ruins_statue", V(42, 0, 136), 3, 2.6)
	cache("ruins_cave_deep", V(148, 0, 150), 3, 2.8) -- no clue: pure scanner work
	Props.GlintingRocks(clues, o, -30, -128)
	cache("ruins_mineral", V(-30, 0, -128), 1, 1, true, "Mineral")
	cache("ruins_empty", V(132, 0, 22), 2, 1, true, "Empty")

	-- ── The Sunken Temple (puzzle + hidden chamber) ────────────────────────
	local temple = Build.Folder(zone, "Temple")
	local tempo = o * CF(0, 3, 0) -- plateau top
	Build.Box(temple, o, V(-35, 0, 85), V(35, 3, 135), P(RUIN, M.Sandstone))
	for i = 0, 2 do
		Build.Box(temple, o, V(-12, 0, 79 + i * 2), V(12, 1 + i, 81 + i * 2), P(RUIN_DARK, M.Sandstone))
	end
	for _, z in { 90, 102, 114, 126 } do
		Props.Column(temple, tempo, -31, z, 14, PAL, false)
		Props.Column(temple, tempo, 31, z, if z == 114 then 6 else 14, PAL, z == 114)
	end
	Build.Wall(temple, tempo, -35, 134, 35, 134, 0, 16, 2, P(RUIN, M.Sandstone), { Center = 0, Width = 8, Height = 10 })
	Build.Wall(temple, tempo, -34, 92, -34, 133, 0, 12, 2, P(RUIN, M.Sandstone))
	Build.Wall(temple, tempo, 34, 92, 34, 120, 0, 9, 2, P(RUIN, M.Sandstone))
	Build.Box(temple, tempo, V(-35, 16, 112), V(10, 18, 135), P(RUIN_DARK, M.Sandstone))
	-- Carved frieze above the secret door
	local frieze = Build.Box(temple, tempo, V(-10, 10.5, 132.6), V(10, 13, 133), P(RUIN_DARK, M.Sandstone, { CanCollide = false }))
	Build.Label(frieze, Enum.NormalId.Front, "SUN  •  MOON  •  STAR", C(120, 90, 50), Enum.Font.Fondamento)
	Props.Torch(temple, tempo, -8, 0, 131)
	Props.Torch(temple, tempo, 8, 0, 131)
	Props.Torch(temple, o, -14, 0, 76)
	Props.Torch(temple, o, 14, 0, 76)
	local secretDoor = Build.Box(temple, tempo, V(-4, 0, 133.2), V(4, 10, 134.8), P(C(165, 150, 120), M.Sandstone, { Name = "SecretDoor" }))
	CollectionService:AddTag(secretDoor, "SecretDoor")
	for _, x in { -20, 20 } do
		local chest = Props.Chest(temple, tempo, CF(x, 0, 122))
		SiteTags.Register(chest, "Chest", ZONE)
	end
	-- Temple courtyard excavation (heavy stone slab: needs a pick)
	local slab = Build.Part(temple, tempo, V(6, 0.8, 6), CF(0, 0.4, 104), P(RUIN_DARK, M.Slate))
	SiteTags.Register(slab, "DigSite", ZONE, { DisplayName = "Cracked Floor Slab", Heavy = true, MinTool = 2 })

	-- Hidden chamber
	local cham = Build.Folder(zone, "HiddenChamber")
	Build.Box(cham, tempo, V(-13, -3, 135), V(13, 0, 157), P(RUIN_DARK, M.Sandstone))
	Build.Wall(cham, tempo, -13, 135, -13, 157, 0, 12, 2, P(RUIN_DARK, M.Sandstone))
	Build.Wall(cham, tempo, 13, 135, 13, 157, 0, 12, 2, P(RUIN_DARK, M.Sandstone))
	Build.Wall(cham, tempo, -13, 156, 13, 156, 0, 12, 2, P(RUIN_DARK, M.Sandstone))
	Build.Box(cham, tempo, V(-14, 12, 134), V(14, 14, 157), P(RUIN_DARK, M.Sandstone))
	for _, x in { -7, 7 } do
		local alcove = Build.Part(cham, tempo, V(3.4, 3.4, 3.4), CF(x, 1.7, 150), P(C(70, 160, 140), M.Glass, { Shape = Enum.PartType.Ball }))
		Build.Light(alcove, C(90, 230, 190), 16, 2)
		Build.Box(cham, tempo, V(x - 2.5, 0, 147.5), V(x + 2.5, 0.6, 152.5), P(GOLD, M.Metal))
		SiteTags.Register(alcove, "Hidden", ZONE)
	end
	Props.Torch(cham, tempo, 0, 0, 154)
	local exitPad = Build.Part(cham, tempo, V(4, 0.4, 4), CF(-9, 0.2, 139), P(C(255, 200, 90), M.Neon, { Name = "ChamberExit" }))
	Build.Billboard(exitPad, "EXIT", 3, 30, 4, 1.5)
	CollectionService:AddTag(exitPad, "ChamberExit")
	exitPad:SetAttribute("ExitTo", o * CF(0, 5, 76) * CFrame.Angles(0, math.pi, 0))

	-- Glyph plates and the riddle tablet
	local glyphs = { { "MOON", -14, C(170, 190, 255) }, { "STAR", 0, C(255, 240, 150) }, { "SUN", 14, C(255, 170, 80) } }
	for _, g in glyphs do
		local plate = Build.Box(temple, o, V(g[2] - 3, 0, 67), V(g[2] + 3, 0.5, 73), P(RUIN_DARK, M.Slate, { Name = "GlyphPlate" }))
		local name = string.sub(g[1], 1, 1) .. string.lower(string.sub(g[1], 2))
		plate:SetAttribute("Glyph", name)
		plate:SetAttribute("PuzzleId", "ruins_glyphs")
		Build.Label(plate, Enum.NormalId.Top, g[1], g[3])
		CollectionService:AddTag(plate, "GlyphPlate")
	end
	local tablet = Props.Stele(temple, o, 0, 59, 0, PAL, "STEP AS THE WATCHERS ROSE")
	SiteTags.Inscription(tablet, "ruins_tablet", "Temple tablet", "\"Three Watchers rose: Sun, Moon and Star. Each Watcher's stone tells WHEN it rose. Step on the glyphs in that order and the temple opens. Wrong steps never undo your progress.\"")

	-- ── The cave (north-east) ──────────────────────────────────────────────
	local cave = Build.Folder(zone, "Cave")
	local kx, kz = 120, 115
	for i = 0, 13 do
		local a = i / 14 * math.pi * 2
		if not (a > math.pi * 1.35 and a < math.pi * 1.65) then
			Build.Part(cave, o, V(9, 16, 9), CF(kx + math.cos(a) * 16, 8, kz + math.sin(a) * 16) * CFrame.Angles(0, -a, 0), P(C(120, 105, 90), M.Rock))
		end
	end
	Build.Part(cave, o, V(3, 40, 40), CF(kx, 16, kz) * UP, P(C(110, 95, 80), M.Rock, { Shape = Enum.PartType.Cylinder }))
	local crystal = Build.Part(cave, o, V(2, 5, 2), CF(kx - 8, 2.5, kz + 6) * CFrame.Angles(0, 0, rad(15)), P(C(150, 90, 220), M.Glass))
	Build.Light(crystal, C(170, 110, 255), 20, 1.6)
	local caveChest = Props.Chest(cave, o, CF(kx + 2, 0, kz + 6), C(90, 60, 35))
	SiteTags.Register(caveChest, "Chest", ZONE)
	Props.Torch(cave, o, kx + 9, 0, kz - 2)
	for i = 0, 4 do
		Props.Root(cave, o, kx - 14 + i * 7, kz - 18, rng:NextNumber(-30, 30), 9)
	end

	-- ── Star Watcher on the high rock shelf ────────────────────────────────
	local shelf = Build.Folder(zone, "HighShelf")
	-- Easy stone stair up to the shelf: 7 wide steps, each a short hop.
	for i = 0, 6 do
		local y = 1.2 + i * 2.5
		Build.Part(shelf, o, V(6, y + 0.6, 7), CF(-108 - i * 3, (y + 0.6) / 2 - 0.3, 120), P(C(185, 160, 120):Lerp(C(150, 130, 100), i / 10), M.Sandstone))
	end
	watcher(shelf, o, -142, 124, 140, "STAR", C(255, 240, 150), "watcher_star", "\"I wake last, when the sky is darkest. I am THIRD.\" — the Star Watcher", 18)
	local shelfUrn = Props.Urn(shelf, o * CF(0, 18, 0), -146, 114, C(150, 85, 55), rng)
	SiteTags.Register(shelfUrn, "Urn", ZONE, { DisplayName = "Watcher's Offering" })

	-- Boundary
	local props = P(C(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CastShadow = false })
	Build.Box(zone, o, V(-182, 0, -182), V(182, 80, -180), props)
	Build.Box(zone, o, V(-182, 0, 180), V(182, 80, 182), props)
	Build.Box(zone, o, V(-182, 0, -180), V(-180, 80, 180), props)
	Build.Box(zone, o, V(180, 0, -180), V(182, 80, 180), props)
end

return RuinsBuilder
