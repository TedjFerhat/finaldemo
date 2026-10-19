--[[
	JungleBuilder — Jungle Temple Ruins (the one new location)

	One cohesive map, six connected sections (south › north):
	  1. ENTRANCE        — vine-covered gate between giant trees.
	  2. OVERGROWN PATH  — winding mud trail, early finds, the Dawn stele.
	  3. COURTYARD       — four Guardian Pillars (symbol puzzle), central altar,
	                       a pool fed by a WATERFALL; a grotto hides behind it.
	  4. COLLAPSED RUINS — west: fallen halls, buried finds and a cracked,
	                       root-covered wall. Scanning it reveals a hollow; a
	                       pick opens the hidden ROOT CHAMBER.
	  5. HIDDEN ENTRANCE — the Root Chamber (clues + fragile burial goods).
	  6. INNER TEMPLE    — a stepped pyramid. Solving the pillars opens the
	                       sanctum below it: four animal statues, four sealed
	                       floor stones, one hides the Sun Disk.

	Palette: deep greens, earthy browns, weathered mossy stone, restrained
	gold and jade accents.
]]

local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Build = require(script.Parent.Build)
local Props = require(script.Parent.Props)
local SiteTags = require(script.Parent.SiteTags)
local Secrets = require(script.Parent.Secrets)

local JungleBuilder = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local UP = CFrame.Angles(0, 0, rad(90))
local M = Enum.Material
local C = Color3.fromRGB
local P = Props.P

local ZONE = "JungleTemple"
local PAL = Props.Jungle
local STONE = PAL.Stone
local STONE_DARK = PAL.StoneDark
local MOSS = PAL.Moss :: Color3
local GOLD = C(196, 160, 70)
local SOIL = C(96, 72, 48)

local function terrain(o: CFrame)
	local t = workspace.Terrain
	local b = o.Position
	t:FillBlock(CF(b + V(0, -6, 0)), V(372, 12, 372), M.LeafyGrass)
	-- Cliff ring
	local rng = Random.new(31)
	for i = 0, 31 do
		local a = i / 32 * math.pi * 2
		local r = rng:NextNumber(165, 178)
		local y, size = rng:NextNumber(4, 14), rng:NextNumber(18, 28)
		-- Leave the entrance (south, a ≈ 270°) open: a boulder here used to
		-- bury players arriving at the jungle.
		if math.abs(a - math.pi * 1.5) > 0.4 then
			t:FillBall(b + V(math.cos(a) * r, y, math.sin(a) * r), size, M.Rock)
		end
	end
	-- Keep the arrival clearing free of terrain (the ground below y 0 stays).
	t:FillBlock(CF(b + V(0, 25, -156)), V(50, 50, 60), M.Air)
	-- Winding mud path (entrance › courtyard)
	local pts = { V(0, 0, -150), V(0, 0, -130), V(-22, 0, -108), V(-8, 0, -84), V(18, 0, -62), V(4, 0, -38) }
	for i = 1, #pts - 1 do
		local a, c = pts[i], pts[i + 1]
		local mid = (a + c) / 2
		local len = (c - a).Magnitude
		t:FillBlock(CFrame.lookAt(b + mid + V(0, -1, 0), b + c + V(0, -1, 0)), V(9, 2, len + 6), M.Mud)
	end
	-- Trail to the collapsed ruins and to the waterfall
	t:FillBlock(CF(b + V(-60, -1, -10)), V(60, 2, 7), M.Mud)
	t:FillBlock(CFrame.lookAt(b + V(45, -1, -52), b + V(80, -1, -45)), V(7, 2, 44), M.Mud)
	-- Pool + stream (carve, then water)
	t:FillBlock(CF(b + V(70, -3, 10)), V(30, 6, 40), M.Air)
	t:FillBlock(CF(b + V(70, -4, 10)), V(30, 4, 40), M.Water)
	t:FillBlock(CF(b + V(70, -3, -40)), V(8, 6, 60), M.Air)
	t:FillBlock(CF(b + V(70, -4, -40)), V(8, 4, 60), M.Water)
	-- Waterfall cliff and the grotto behind it
	t:FillBlock(CF(b + V(95, 18, 10)), V(14, 40, 50), M.Rock)
	t:FillBlock(CF(b + V(93, 5, 10)), V(9, 10, 14), M.Air)
	-- Sanctum under the pyramid: ramp + room
	t:FillBlock(CF(b + V(16, -6, 79)), V(10, 12, 28), M.Air)
	t:FillBlock(CF(b + V(0, -6, 112)), V(54, 12, 42), M.Air)
end

local function zoneProps(): Build.PartProps
	return P(C(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CastShadow = false })
end

-- A rotatable Guardian Pillar for the courtyard puzzle.
local function guardianPillar(f: Instance, o: CFrame, x: number, z: number, pillarId: string)
	local base = o * CF(x, 0, z)
	Build.Part(f, base, V(6, 1.4, 6), CF(0, 0.7, 0), P(STONE_DARK, M.Slate))
	Build.Part(f, base, V(3.6, 9, 3.6), CF(0, 5.9, 0), P(STONE, M.Slate))
	Build.Part(f, base, V(4.2, 0.6, 4.2), CF(0, 10.7, 0), P(MOSS, M.Grass, { CanCollide = false }))
	local plate = Build.Part(f, base, V(4, 1.6, 0.3), CF(0, 2.4, -3.1), P(STONE_DARK, M.Slate, { CanCollide = false }))
	Build.Label(plate, Enum.NormalId.Front, pillarId:upper(), GOLD, Enum.Font.Fondamento)
	-- The carved head that turns
	local head = Build.Part(f, base, V(4.4, 4.4, 4.4), CF(0, 13.4, 0), P(C(110, 118, 100), M.Slate, { Name = "GuardianHead" }))
	head:SetAttribute("PillarId", pillarId)
	for _, face in { Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right } do
		local label = Build.Label(head, face, "?", C(230, 200, 120), Enum.Font.Fondamento)
		label.Name = "Symbol"
	end
	CollectionService:AddTag(head, "GuardianPillar")
	Props.Vines(f, base, CF(0, 11, -1.85), 3, 6, Random.new(#pillarId))
end

-- Animal statue for the sanctum (stylised silhouettes: readable at a glance).
local function animalStatue(f: Instance, o: CFrame, animal: string)
	Build.Part(f, o, V(6, 2, 5), CF(0, 1, 0), P(STONE_DARK, M.Slate))
	local stone = P(STONE, M.Slate)
	if animal == "Jaguar" then
		Build.Part(f, o, V(2.6, 2.6, 6), CF(0, 3.6, 0.5), stone) -- body
		Build.Part(f, o, V(2.8, 2.6, 2.6), CF(0, 4.6, -3), stone) -- head
		Build.Part(f, o, V(0.8, 0.8, 0.6), CF(-0.9, 6.2, -3), stone) -- ears
		Build.Part(f, o, V(0.8, 0.8, 0.6), CF(0.9, 6.2, -3), stone)
		Build.Part(f, o, V(0.6, 0.6, 4), CF(0, 3.4, 4.6) * CFrame.Angles(rad(-35), 0, 0), stone) -- tail
	elseif animal == "Serpent" then
		for i = 0, 5 do
			Build.Part(f, o, V(1.8, 1.8, 1.8), CF(math.sin(i) * 1.6, 2.8 + i * 0.9, 1.5 - i * 0.6), P(STONE, M.Slate, { Shape = Enum.PartType.Ball }))
		end
		Build.Part(f, o, V(2.2, 1.6, 3), CF(0.4, 8.3, -2.6), stone)
	elseif animal == "Eagle" then
		Build.Part(f, o, V(2.4, 4, 2.2), CF(0, 4, 0), stone) -- body
		Build.Part(f, o, V(1.8, 1.8, 1.8), CF(0, 6.9, -0.3), stone) -- head
		Build.Part(f, o, V(0.8, 0.6, 1.2), CF(0, 6.7, -1.6), P(GOLD, M.Metal)) -- beak
		Build.Part(f, o, V(0.6, 4, 3), CF(-2, 5, 0.4) * CFrame.Angles(0, 0, rad(-35)), stone) -- wings
		Build.Part(f, o, V(0.6, 4, 3), CF(2, 5, 0.4) * CFrame.Angles(0, 0, rad(35)), stone)
	else -- Monkey
		Build.Part(f, o, V(2.4, 3, 2), CF(0, 3.6, 0), stone)
		Build.Part(f, o, V(2.2, 2.2, 2.2), CF(0, 6.1, 0), P(STONE, M.Slate, { Shape = Enum.PartType.Ball }))
		Build.Part(f, o, V(1, 1, 0.4), CF(-1.3, 6.3, 0), stone)
		Build.Part(f, o, V(1, 1, 0.4), CF(1.3, 6.3, 0), stone)
		Build.Part(f, o, V(0.6, 3.4, 0.6), CF(-1.6, 6, -0.4) * CFrame.Angles(0, 0, rad(-20)), stone) -- raised arm
		Build.Part(f, o, V(0.5, 0.5, 4), CF(0, 2.6, 2.4) * CFrame.Angles(rad(40), 0, 0), stone)
	end
	local plaque = Build.Part(f, o, V(4, 1, 0.3), CF(0, 1, -2.7), P(STONE_DARK, M.Slate, { CanCollide = false }))
	Build.Label(plaque, Enum.NormalId.Front, animal:upper(), GOLD, Enum.Font.Fondamento)
end

function JungleBuilder.Build(world: Instance, o: CFrame)
	local zone = Build.Folder(world, ZONE)
	local rng = Random.new(2024)
	terrain(o)

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

	-- ── 1. ENTRANCE ────────────────────────────────────────────────────────
	local ent = Build.Folder(zone, "Entrance")
	local rf = o * CF(0, 0, -164)
	Build.Part(ent, rf, V(3, 14, 3), CF(-6, 7, 0), P(STONE, M.Slate))
	Build.Part(ent, rf, V(3, 14, 3), CF(6, 7, 0), P(STONE, M.Slate))
	Build.Part(ent, rf, V(16, 3, 3.4), CF(0, 15, 0), P(STONE_DARK, M.Slate))
	local back = Build.Part(ent, rf, V(9, 12, 0.6), CF(0, 7, 0), P(C(255, 200, 90), M.Neon, { Transparency = 0.35, CanCollide = false, Name = "ReturnPortal" }))
	Build.Light(back, C(255, 200, 90), 22, 2)
	local backSign = Build.Part(ent, rf, V(12, 2.2, 0.4), CF(0, 18.5, 0.3), P(C(32, 78, 60)))
	Build.Label(backSign, Enum.NormalId.Back, "RETURN TO YOUR MUSEUM", GOLD)
	local arrival = Instance.new("Part")
	arrival.Name = "ArrivalPoint"
	arrival.Anchored = true
	arrival.CanCollide = false
	arrival.Transparency = 1
	arrival.Size = V(1, 1, 1)
	arrival.CFrame = o * CF(0, 4, -150)
	arrival.Parent = ent
	-- Vine-covered gate
	local gate = o * CF(0, 0, -132)
	for _, x in { -11, 11 } do
		Build.Part(ent, gate, V(6, 22, 6), CF(x, 11, 0), P(STONE, M.Slate))
		Build.Part(ent, gate, V(6.6, 0.6, 6.6), CF(x, 22.3, 0), P(MOSS, M.Grass, { CanCollide = false }))
	end
	Build.Part(ent, gate, V(30, 4, 7), CF(0, 24, 0), P(STONE_DARK, M.Slate))
	local lintel = Build.Part(ent, gate, V(10, 2.6, 0.3), CF(0, 24, -3.6), P(STONE, M.Slate, { CanCollide = false }))
	Build.Label(lintel, Enum.NormalId.Front, "TEMPLE OF THE JAGUAR SUN", GOLD, Enum.Font.Fondamento)
	Props.Vines(ent, gate, CF(0, 22, -3.6), 28, 9, rng)
	for _, p in { V(-30, 0, -150), V(30, 0, -146), V(-42, 0, -125), V(40, 0, -122) } do
		Props.JungleTree(ent, o, p.X, p.Z, rng, 1.15)
	end

	-- ── 2. OVERGROWN PATH ──────────────────────────────────────────────────
	local path = Build.Folder(zone, "Path")
	for _ = 1, 22 do
		local z = rng:NextNumber(-125, -45)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		Props.Fern(path, o, side * rng:NextNumber(14, 40), z, rng)
	end
	for _, p in { V(-12, 0, -118), V(8, 0, -72), V(-2, 0, -95) } do
		Props.Root(path, o, p.X, p.Z, rng:NextNumber(0, 180), 10)
	end
	local dawn = Props.Stele(path, o, -34, -100, -60, PAL, nil)
	SiteTags.Inscription(dawn, "jungle_dawn", "Mossy stele (path)", Secrets.JunglePillars[1].Clue)
	SiteTags.Register(Props.Urn(path, o, -30, -122, C(165, 100, 60), rng), "Urn", ZONE)
	SiteTags.Register(Props.Urn(path, o, 32, -96, C(150, 90, 55), rng), "Urn", ZONE)
	local rubble = Build.Part(path, o, V(5, 3, 4), CF(27, 1.5, -48) * CFrame.Angles(0, 1, rad(8)), P(STONE_DARK, M.Slate))
	Props.Debris(path, o, 27, -48, 3.5, 6, rng, STONE)
	SiteTags.Register(rubble, "Rubble", ZONE)
	SiteTags.Register(Props.DigSite(path, o, 30, -78, SOIL), "DigSite", ZONE, { DisplayName = "Trailside Dig", Fragile = true })
	Props.PotteryShard(path, o, 42, -113, C(170, 100, 60))
	cache("jungle_shard", V(44, 0, -110), 1, 1.6)
	for _ = 1, 10 do
		local z = rng:NextNumber(-125, -40)
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		Props.JungleTree(path, o, side * rng:NextNumber(42, 75), z, rng)
	end

	-- ── 3. COURTYARD ───────────────────────────────────────────────────────
	local yard = Build.Folder(zone, "Courtyard")
	for x = -42, 42, 7 do
		for z = -32, 42, 7 do
			if rng:NextNumber() > 0.12 then
				local col = if rng:NextNumber() < 0.3 then MOSS:Lerp(STONE, 0.4) else STONE:Lerp(STONE_DARK, rng:NextNumber(0, 0.5))
				Build.Part(yard, o, V(6.6, 0.6, 6.6), CF(x, 0.3, z) * CFrame.Angles(0, rng:NextNumber(-0.05, 0.05), 0), P(col, M.Slate))
			end
		end
	end
	-- Central altar with a carved sun disc
	Build.Part(yard, o, V(10, 2, 10), CF(0, 1, 5), P(STONE_DARK, M.Slate))
	Build.Part(yard, o, V(6, 5, 6), CF(0, 4.5, 5), P(STONE, M.Slate))
	local disc = Build.Part(yard, o, V(0.6, 5, 5), CF(0, 9.6, 5) * CFrame.Angles(0, rad(90), 0), P(GOLD, M.Metal, { Shape = Enum.PartType.Cylinder }))
	Build.Light(disc, C(255, 210, 120), 26, 1)
	local altarText = Build.Part(yard, o, V(5, 2.6, 0.2), CF(0, 4.5, 1.9), P(STONE, M.Slate, { CanCollide = false }))
	Build.Label(altarText, Enum.NormalId.Front, "SET EACH GUARDIAN\nTO ITS BEAST", GOLD, Enum.Font.Fondamento)
	SiteTags.Inscription(altarText, "jungle_altar", "Courtyard altar", "\"Turn each Guardian to the beast it serves, and the Sun's house will open. Four stones tell the four truths.\"")
	guardianPillar(yard, o, 30, 5, "Dawn")
	guardianPillar(yard, o, -30, 5, "Dusk")
	guardianPillar(yard, o, 0, 34, "Rain")
	guardianPillar(yard, o, 0, -24, "Root")
	for _, p in { V(-40, 0, -30), V(40, 0, -30), V(-40, 0, 40), V(40, 0, 40) } do
		Props.Column(yard, o, p.X, p.Z, rng:NextNumber(6, 14), PAL, rng:NextNumber() < 0.5, rng:NextNumber(-6, 6))
	end
	-- Fireflies
	local glow = Build.Part(yard, o, V(80, 1, 80), CF(0, 6, 5), P(C(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CanCollide = false }))
	local flies = Instance.new("ParticleEmitter")
	flies.Color = ColorSequence.new(C(220, 255, 150))
	flies.LightEmission = 1
	flies.Size = NumberSequence.new(0.18)
	flies.Lifetime = NumberRange.new(3, 6)
	flies.Rate = 8
	flies.Speed = NumberRange.new(0.3, 1)
	flies.SpreadAngle = Vector2.new(180, 180)
	flies.Parent = glow

	-- Pool, waterfall and the grotto
	local water = Build.Folder(zone, "Waterfall")
	local sheet = Build.Part(water, o, V(1, 34, 16), CF(87.6, 19, 10), P(C(150, 205, 235), M.Glass, { Transparency = 0.35, CanCollide = false, CastShadow = false }))
	local foam = Instance.new("ParticleEmitter")
	foam.Color = ColorSequence.new(C(230, 245, 255))
	foam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 3) })
	foam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	foam.Lifetime = NumberRange.new(1, 1.6)
	foam.Rate = 40
	foam.Speed = NumberRange.new(10, 14)
	foam.EmissionDirection = Enum.NormalId.Bottom
	foam.Parent = sheet
	if Config.Sounds.Water ~= "" then
		local sound = Instance.new("Sound")
		sound.SoundId = Config.Sounds.Water
		sound.Looped = true
		sound.Volume = 0.35
		sound.RollOffMaxDistance = 80
		sound.Parent = sheet
		sound:Play()
	end
	local rain = Props.Stele(water, o, 95, 10, 90, PAL, nil)
	SiteTags.Inscription(rain, "jungle_rain", "Grotto stele (behind the waterfall)", Secrets.JunglePillars[3].Clue)
	Build.Light(Build.Part(water, o, V(1, 1, 1), CF(92, 6, 10), P(C(120, 200, 255), M.Neon, { Transparency = 1, CanCollide = false })), C(120, 200, 255), 14, 1)
	-- Stone bridge over the stream on the waterfall trail
	local bridge = o * CF(70, 0, -45)
	Build.Part(water, bridge, V(14, 1.2, 6), CF(0, 1.4, 0), P(STONE, M.Slate))
	Build.Part(water, bridge, V(14, 1.4, 0.8), CF(0, 2.6, -2.6), P(STONE_DARK, M.Slate))
	Build.Part(water, bridge, V(14, 1.4, 0.8), CF(0, 2.6, 2.6), P(STONE_DARK, M.Slate))
	Build.Part(water, bridge, V(2, 1.2, 6), CF(-7.5, 0.6, 0), P(STONE_DARK, M.Slate))
	Build.Part(water, bridge, V(2, 1.2, 6), CF(7.5, 0.6, 0), P(STONE_DARK, M.Slate))
	-- Rim path stones along the south of the pool to the cliff
	for x = 58, 86, 4 do
		Build.Part(water, o, V(4, 0.8, 4), CF(x, 0.2, -12), P(STONE:Lerp(MOSS, 0.3), M.Slate))
	end
	for z = -12, 4, 4 do
		Build.Part(water, o, V(4, 0.8, 4), CF(87, 0.2, z), P(STONE:Lerp(MOSS, 0.3), M.Slate))
	end

	-- ── 4. COLLAPSED RUINS (west) ──────────────────────────────────────────
	local ruins = Build.Folder(zone, "CollapsedRuins")
	Props.Statue(ruins, o, -58, -34, 200, PAL, nil, true)
	local duskStele = Props.Stele(ruins, o, -54, -27, 200, PAL, nil)
	SiteTags.Inscription(duskStele, "jungle_dusk", "Weathered statue base", Secrets.JunglePillars[2].Clue)
	for _, w in { { -70, 20, 18, 0 }, { -85, -5, 14, 70 }, { -62, 60, 20, 110 }, { -115, 70, 16, 30 } } do
		local wall = Build.Part(ruins, o, V(w[3], rng:NextNumber(4, 9), 2.4), CF(w[1], 3, w[2]) * CFrame.Angles(0, rad(w[4]), rad(rng:NextNumber(-6, 6))), P(STONE, M.Slate))
		Build.Part(ruins, o * CF(w[1], 0, w[2]) * CFrame.Angles(0, rad(w[4]), 0), V(w[3], 0.4, 2.8), CF(0, wall.Size.Y / 2 + 3.1, 0), P(MOSS, M.Grass, { CanCollide = false }))
		Props.Debris(ruins, o, w[1], w[2] + 3, 5, 6, rng, STONE_DARK)
	end
	for _, p in { V(-78, 0, 40), V(-95, 0, -20), V(-68, 0, -10) } do
		Props.Column(ruins, o, p.X, p.Z, rng:NextNumber(4, 9), PAL, true, rng:NextNumber(-12, 12))
	end
	Props.FallenColumn(ruins, o, -88, 12, 12, 40, PAL)
	SiteTags.Register(Props.DigSite(ruins, o, -72, 32, SOIL), "DigSite", ZONE, { DisplayName = "Collapsed Hall Dig", Fragile = false })
	Props.StoneRing(ruins, o, -75, 8, STONE_DARK)
	cache("jungle_ring", V(-75, 0, 8), 2, 2.0)
	Props.SoilPattern(ruins, o, -100, 74, C(70, 55, 40))
	cache("jungle_soil", V(-97, 0, 72), 2, 1.8)
	Props.GlintingRocks(ruins, o, -62, 52)
	cache("jungle_mineral", V(-62, 0, 52), 1, 1, true, "Mineral")
	SiteTags.Register(Props.Chest(ruins, o, CF(-92, 0, -24) * CFrame.Angles(0, rad(20), 0)), "Chest", ZONE)

	-- ── 5. ROOT CHAMBER (hidden entrance) ──────────────────────────────────
	local cham = Build.Folder(zone, "RootChamber")
	local co = o * CF(-114, 0, 40)
	local wallProps = P(STONE_DARK, M.Slate)
	Build.Box(cham, co, V(-13, -0.5, -13), V(13, 0.2, 13), P(SOIL, M.Ground))
	Build.Wall(cham, co, -13, -13, 13, -13, 0, 12, 2, wallProps)
	Build.Wall(cham, co, -13, 13, 13, 13, 0, 12, 2, wallProps)
	Build.Wall(cham, co, -13, -12, -13, 12, 0, 12, 2, wallProps)
	Build.Wall(cham, co, 13, -12, 13, 12, 0, 12, 2, wallProps, { Center = 0, Width = 6, Height = 7 })
	Build.Box(cham, co, V(-14, 12, -14), V(14, 14, 14), P(STONE, M.Slate))
	Build.Box(cham, co, V(-14.4, 14, -14.4), V(14.4, 14.6, 14.4), P(MOSS, M.Grass))
	-- The cracked, root-covered wall that seals the doorway (scanner + pick)
	local hollow = Build.Part(cham, co, V(1.6, 7, 6), CF(13.6, 3.5, 0), P(C(105, 98, 84), M.Slate, { Name = "HollowWall" }))
	CollectionService:AddTag(hollow, "HollowWall")
	hollow:SetAttribute("HollowId", "jungle_root_wall")
	for i = 0, 4 do
		Build.Part(cham, co, V(0.6, 7.5, 0.6), CF(14.5, 3.7, -2.4 + i * 1.2) * CFrame.Angles(rad(rng:NextNumber(-12, 12)), 0, 0), P(C(88, 66, 46), M.Wood, { CanCollide = false }))
	end
	Props.Vines(cham, co, CF(14.6, 12, 0), 10, 8, rng)
	Secrets.AddHollow({ Id = "jungle_root_wall", Zone = ZONE, Position = hollow.Position, Part = hollow })
	-- Inside
	for _ = 1, 10 do
		local len = rng:NextNumber(4, 9)
		Build.Part(cham, co, V(0.5, len, 0.5), CF(rng:NextNumber(-11, 11), 12 - len / 2, rng:NextNumber(-11, 11)), P(C(88, 66, 46), M.Wood, { CanCollide = false }))
	end
	for _ = 1, 8 do
		local s = rng:NextNumber(0.5, 1.1)
		local shroom = Build.Part(cham, co, V(s, s * 0.6, s), CF(rng:NextNumber(-11, 11), 0.4, rng:NextNumber(-11, 11)), P(C(120, 230, 200), M.Neon, { Shape = Enum.PartType.Ball, CanCollide = false }))
		if rng:NextNumber() < 0.4 then
			Build.Light(shroom, C(120, 230, 200), 10, 0.8)
		end
	end
	local rootStele = Props.Stele(cham, co, -9, 6, -90, PAL, nil)
	SiteTags.Inscription(rootStele, "jungle_root", "Root Chamber stele", Secrets.JunglePillars[4].Clue)
	local heartStele = Props.Stele(cham, co, -9, -6, -90, PAL, nil)
	SiteTags.Inscription(heartStele, "jungle_heart", "Scratched burial plaque", ("\"Below the Sun's house, four stones are sealed. The HEART sleeps beneath the %s's gaze. The others hold only dust.\""):format(Secrets.HeartStatue:upper()))
	local burial = Props.DigSite(cham, co, 2, 0, SOIL)
	SiteTags.Register(burial, "DigSite", ZONE, { DisplayName = "Root Burial", Fragile = true, MinTool = 2 })
	burial:SetAttribute("RareBoost", 2.2)
	Props.Torch(cham, co, 10, 0, -10)

	-- ── 6. INNER TEMPLE: the stepped pyramid ───────────────────────────────
	local pyr = Build.Folder(zone, "Pyramid")
	local tiers = { { 70, 60 }, { 56, 48 }, { 42, 36 }, { 28, 24 } }
	for i, t in tiers do
		local y0 = (i - 1) * 8
		local col = STONE:Lerp(STONE_DARK, (i - 1) * 0.15)
		Build.Part(pyr, o, V(t[1], 8, t[2]), CF(0, y0 + 4, 110), P(col, M.Slate))
		Build.Part(pyr, o, V(t[1] + 0.4, 0.5, t[2] + 0.4), CF(0, y0 + 8.1, 110), P(MOSS, M.Grass, { CanCollide = false }))
		Props.Vines(pyr, o, CF(-t[1] / 4, y0 + 8, 110 - t[2] / 2 - 0.3), t[1] / 3, 6, rng)
	end
	-- Front stairs to the top
	for i = 1, 20 do
		Build.Box(pyr, o, V(-5, 0, 72 + (i - 1) * 1.5), V(5, 1.6 * i, 72 + i * 1.5), P(STONE:Lerp(STONE_DARK, 0.25), M.Slate))
	end
	-- Rooftop shrine with a hidden alcove (difficult to reach)
	local top = o * CF(0, 32, 110)
	for _, p in { V(-5, 0, -5), V(5, 0, -5), V(-5, 0, 5), V(5, 0, 5) } do
		Build.Part(pyr, top, V(1.6, 7, 1.6), CF(p.X, 3.5, p.Z), P(STONE, M.Slate))
	end
	Build.Part(pyr, top, V(13, 1.4, 13), CF(0, 7.7, 0), P(STONE_DARK, M.Slate))
	local bowl = Build.Part(pyr, top, V(1.2, 3, 3), CF(0, 1.2, 0) * UP, P(GOLD, M.Metal, { Shape = Enum.PartType.Cylinder }))
	SiteTags.Register(bowl, "Hidden", ZONE, { DisplayName = "Sky Shrine Offering" })
	Build.Light(bowl, C(255, 210, 120), 16, 1)

	-- Sanctum entrance (in front of the pyramid, right of the stairs) and a
	-- ramp that descends under the pyramid
	local doorFrame = o * CF(16, 0, 66)
	Build.Part(pyr, doorFrame, V(2, 9, 3), CF(-5, 4.5, -0.5), P(STONE_DARK, M.Slate))
	Build.Part(pyr, doorFrame, V(2, 9, 3), CF(5, 4.5, -0.5), P(STONE_DARK, M.Slate))
	Build.Part(pyr, doorFrame, V(12, 2, 3), CF(0, 9, -0.5), P(STONE_DARK, M.Slate))
	local door = Build.Part(pyr, doorFrame, V(8, 8, 1.6), CF(0, 4, -0.6), P(C(110, 115, 95), M.Slate, { Name = "SanctumDoor" }))
	Build.Label(door, Enum.NormalId.Front, "SEALED BY THE GUARDIANS", GOLD, Enum.Font.Fondamento)
	CollectionService:AddTag(door, "SanctumDoor")
	-- Ramp: 10 steps down (starts outside, so there's head room under the pyramid)
	for i = 1, 10 do
		Build.Box(pyr, o, V(11, -1.1 * i - 1, 66 + (i - 1) * 2.5), V(21, -1.1 * i, 66 + i * 2.5), P(STONE_DARK, M.Slate))
	end
	Build.Box(pyr, o, V(10, -12, 66), V(11, 0.5, 93), P(STONE_DARK, M.Slate))
	Build.Box(pyr, o, V(21, -12, 66), V(22, 0.5, 93), P(STONE_DARK, M.Slate))

	-- The sanctum room (under the pyramid)
	local so = o * CF(0, -11, 112)
	local sanctum = Build.Folder(zone, "Sanctum")
	Build.Box(sanctum, so, V(-27, -1, -21), V(27, 0, 21), P(STONE_DARK, M.Slate))
	Build.Box(sanctum, so, V(-27, 9, -21), V(27, 11, 21), P(STONE_DARK, M.Slate)) -- ceiling
	Build.Wall(sanctum, so, -27, -21, 27, -21, 0, 9, 1.4, P(STONE, M.Slate), { Center = 16, Width = 10, Height = 9 })
	Build.Wall(sanctum, so, -27, 21, 27, 21, 0, 9, 1.4, P(STONE, M.Slate))
	Build.Wall(sanctum, so, -27, -20, -27, 20, 0, 9, 1.4, P(STONE, M.Slate))
	Build.Wall(sanctum, so, 27, -20, 27, 20, 0, 9, 1.4, P(STONE, M.Slate))
	Build.Part(sanctum, so, V(6, 3, 6), CF(0, 1.5, 2), P(STONE, M.Slate))
	local sunOnAltar = Build.Part(sanctum, so, V(0.5, 4, 4), CF(0, 5.2, 2) * CFrame.Angles(0, rad(90), 0), P(GOLD, M.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	Build.Light(sunOnAltar, C(255, 200, 120), 30, 1.2)
	local altarStele = Build.Part(sanctum, so, V(5, 2, 0.2), CF(0, 1.6, -1.1), P(STONE, M.Slate, { CanCollide = false }))
	Build.Label(altarStele, Enum.NormalId.Front, "ONLY ONE STONE HOLDS THE HEART", GOLD, Enum.Font.Fondamento)
	local statues = {
		{ Animal = "Jaguar", Pos = V(-20, 0, 14), Yaw = 0 },
		{ Animal = "Serpent", Pos = V(-7, 0, 17), Yaw = 0 },
		{ Animal = "Eagle", Pos = V(7, 0, 17), Yaw = 0 },
		{ Animal = "Monkey", Pos = V(20, 0, 14), Yaw = 0 },
	}
	for _, s in statues do
		animalStatue(sanctum, so * CF(s.Pos) * CFrame.Angles(0, rad(s.Yaw), 0), s.Animal)
		local stone = Build.Part(sanctum, so, V(5, 0.6, 5), CF(s.Pos.X, 0.3, s.Pos.Z - 7), P(C(125, 120, 100), M.Slate))
		SiteTags.Register(stone, "DigSite", ZONE, { DisplayName = s.Animal .. " Floor Stone", Heavy = true, MinTool = 2, Special = "SanctumStone" })
		stone:SetAttribute("Animal", s.Animal)
	end
	for _, x in { -22, 22 } do
		SiteTags.Register(Props.Chest(sanctum, so, CF(x, 0, -12)), "Chest", ZONE)
		Props.Torch(sanctum, so, x, 0, -19)
	end
	-- Sanctum access trigger (server checks who walked in while the door was open)
	local trigger = Build.Part(sanctum, o, V(10, 8, 3), CF(16, -4, 74), P(C(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CanCollide = false, Name = "SanctumTrigger" }))
	CollectionService:AddTag(trigger, "SanctumTrigger")
	local sanctumBox = Build.Part(sanctum, so, V(54, 10, 42), CF(0, 5, 0), P(C(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanTouch = false, CanQuery = false, Name = "SanctumBounds" }))
	CollectionService:AddTag(sanctumBox, "SanctumBounds")

	-- Deep finds around the pyramid
	Props.Statue(pyr, o, 56, 120, -120, PAL, nil, true)
	cache("jungle_statue", V(60, 0, 126), 3, 2.6)
	cache("jungle_deep", V(-140, 0, -140), 3, 2.8)
	cache("jungle_empty", V(-50, 0, 140), 2, 1, true, "Empty")

	-- Trees across the map (not on paths, courtyard or pyramid)
	for _ = 1, 30 do
		local x, z = rng:NextNumber(-160, 160), rng:NextNumber(-150, 160)
		local onYard = math.abs(x) < 50 and z > -40 and z < 48
		local onPyramid = math.abs(x) < 42 and z > 66 and z < 145
		local onWater = x > 50 and x < 105 and z > -75 and z < 40
		local onRuins = x > -130 and x < -50 and z > -45 and z < 85
		local onPath = math.abs(x) < 35 and z < -35
		if not (onYard or onPyramid or onWater or onRuins or onPath) then
			Props.JungleTree(zone, o, x, z, rng)
		end
	end
	for _ = 1, 30 do
		Props.Fern(zone, o, rng:NextNumber(-160, 160), rng:NextNumber(-150, 160), rng)
	end

	-- Boundary
	local bp = zoneProps()
	Build.Box(zone, o, V(-182, -12, -182), V(182, 80, -180), bp)
	Build.Box(zone, o, V(-182, -12, 180), V(182, 80, 182), bp)
	Build.Box(zone, o, V(-182, -12, -180), V(-180, 80, 180), bp)
	Build.Box(zone, o, V(180, -12, -180), V(182, 80, 180), bp)

	-- Initial pillar symbols are set by PuzzleService.
end

return JungleBuilder
