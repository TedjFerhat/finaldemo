--[[
	Props
	Reusable environment models built from parts, shared by the Forgotten
	Ruins and the Jungle Temple so both zones have one consistent style:
	weathered stone, readable silhouettes, a little wear and moss — no
	floating detail, nothing smaller than the camera will notice.

	Every function takes (parent, origin, ...) where positions are local to
	`origin`. Decorative props have no scripts.
]]

local Build = require(script.Parent.Build)
local Trees = require(script.Parent.Trees)

local Props = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local UP = CFrame.Angles(0, 0, rad(90))
local M = Enum.Material
local C = Color3.fromRGB

export type Palette = { Stone: Color3, StoneDark: Color3, Moss: Color3?, Accent: Color3 }

Props.Sand = { Stone = C(205, 186, 150), StoneDark = C(160, 140, 112), Moss = nil, Accent = C(214, 172, 60) } :: Palette
Props.Jungle = { Stone = C(128, 132, 116), StoneDark = C(92, 96, 84), Moss = C(70, 110, 60), Accent = C(196, 160, 70) } :: Palette

local function P(color: Color3, material: Enum.Material?, extra: { [string]: any }?): Build.PartProps
	local p: any = { Color = color, Material = material or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end
Props.P = P

-- Thin moss cap on top of a stone (only for palettes with moss).
local function moss(parent: Instance, origin: CFrame, pal: Palette, cf: CFrame, size: Vector3)
	if pal.Moss then
		Build.Part(parent, origin, V(size.X * 0.9, 0.25, size.Z * 0.9), cf * CF(0, size.Y / 2 + 0.1, 0), P(pal.Moss, M.Grass, { CanCollide = false }))
	end
end

-- Loose rubble: bigger blocks near the centre, smaller stones toward the
-- edge, alternating light/dark stone. Decorative only (no collision).
function Props.Rubble(parent: Instance, origin: CFrame, x: number, z: number, radius: number, count: number, rng: Random, pal: Palette)
	for _ = 1, count do
		local ang = rng:NextNumber(0, math.pi * 2)
		local r = radius * math.sqrt(rng:NextNumber())
		local s = rng:NextNumber(0.5, 1.4) * (1.35 - 0.6 * r / math.max(radius, 0.1))
		local col = if rng:NextNumber() < 0.5 then pal.Stone else pal.StoneDark
		Build.Part(
			parent,
			origin,
			V(s, s * 0.65, s * rng:NextNumber(0.8, 1.3)),
			CF(x + math.cos(ang) * r, s * 0.22, z + math.sin(ang) * r) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), rng:NextNumber(0, 6), rng:NextNumber(-0.25, 0.25)),
			P(col, M.Slate, { CanCollide = false })
		)
	end
end

-- Column with base and capital. broken = jagged short top, no capital.
-- Detail: stacked drum seams, a hairline crack, jagged break teeth and a
-- little rubble at the foot (all deterministic from the position, so the
-- ruins look the same on every server).
function Props.Column(parent: Instance, origin: CFrame, x: number, z: number, height: number, pal: Palette, broken: boolean?, lean: number?)
	local f = origin * CF(x, 0, z) * CFrame.Angles(rad(lean or 0), 0, rad((lean or 0) * 0.5))
	local rng = Random.new(math.floor(x * 31 + z * 17))
	Build.Part(parent, f, V(4.2, 1.2, 4.2), CF(0, 0.6, 0), P(pal.StoneDark, M.Slate))
	Build.Part(parent, f, V(height, 3, 3), CF(0, 1.2 + height / 2, 0) * UP, P(pal.Stone, M.Sandstone, { Shape = Enum.PartType.Cylinder }))
	-- Fluting: two thin darker bands give the column a carved look
	Build.Part(parent, f, V(0.3, 3.1, 3.1), CF(0, 1.6, 0) * UP, P(pal.StoneDark, M.Sandstone, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	-- Drum seams: real columns are stacked stone drums
	for i = 1, math.max(1, math.floor(height / 5)) do
		local y = 1.2 + height * i / (math.floor(height / 5) + 1)
		Build.Part(parent, f, V(0.14, 3.06, 3.06), CF(0, y, 0) * UP, P(pal.StoneDark, M.Slate, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	end
	-- Hairline crack on the shaft
	local crackLen = height * rng:NextNumber(0.35, 0.6)
	Build.Part(parent, f, V(0.1, crackLen, 0.5), CFrame.Angles(0, rad(rng:NextNumber(0, 360)), 0) * CF(1.49, 1.4 + crackLen / 2 + rng:NextNumber(0, height * 0.25), 0) * CFrame.Angles(0, 0, rad(rng:NextNumber(-4, 4))), P(pal.StoneDark:Lerp(C(40, 34, 28), 0.5), M.Slate, { CanCollide = false }))
	if broken then
		Build.Part(parent, f, V(2.2, 1.4, 2.6), CF(0.3, 1.2 + height + 0.3, 0.2) * CFrame.Angles(rad(18), rad(30), rad(-12)), P(pal.Stone, M.Sandstone))
		-- jagged break teeth around the stump
		for k = 0, 2 do
			local a = rad(k * 120 + rng:NextNumber(0, 60))
			local h = rng:NextNumber(0.6, 1.4)
			Build.Part(parent, f, V(0.9, h, 0.7), CF(math.cos(a) * 1.0, 1.2 + height + h / 2 - 0.1, math.sin(a) * 1.0) * CFrame.Angles(rng:NextNumber(-0.25, 0.25), a, rng:NextNumber(-0.25, 0.25)), P(pal.Stone, M.Sandstone, { CanCollide = false }))
		end
		moss(parent, f, pal, CF(0, 1.2 + height, 0), V(3, 0.2, 3))
		Props.Rubble(parent, origin, x, z + 3.2, 2.6, 5, rng, pal)
	else
		Build.Part(parent, f, V(0.6, 3.6, 3.6), CF(0, 1.2 + height - 0.3, 0) * UP, P(pal.StoneDark, M.Sandstone, { Shape = Enum.PartType.Cylinder }))
		Build.Part(parent, f, V(4.6, 1, 4.6), CF(0, 1.2 + height + 0.5, 0), P(pal.Stone, M.Slate))
		moss(parent, f, pal, CF(0, 1.2 + height + 0.5, 0), V(4.6, 1, 4.6))
		Props.Rubble(parent, origin, x, z + 3.2, 2.2, 3, rng, pal)
	end
end

-- A column lying on its side, half sunk into the ground.
function Props.FallenColumn(parent: Instance, origin: CFrame, x: number, z: number, length: number, yaw: number, pal: Palette)
	local f = origin * CF(x, 0.6, z) * CFrame.Angles(0, rad(yaw), 0)
	Build.Part(parent, f, V(length, 3, 3), CF(0, 0, 0), P(pal.Stone, M.Sandstone, { Shape = Enum.PartType.Cylinder }))
	Build.Part(parent, f, V(1.2, 4.2, 4.2), CF(length / 2 + 0.4, 0.5, 0), P(pal.StoneDark, M.Slate))
	-- drum seams and a broken end with a chipped chunk beside it
	for i = 1, 2 do
		Build.Part(parent, f, V(0.14, 3.06, 3.06), CF(-length / 2 + length * i / 3, 0, 0), P(pal.StoneDark, M.Slate, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	end
	Build.Part(parent, f, V(1.6, 1.4, 1.8), CF(-length / 2 - 1.4, -0.3, 1.8) * CFrame.Angles(0.2, 0.7, 0.3), P(pal.Stone, M.Sandstone, { CanCollide = false }))
	moss(parent, f, pal, CF(0, 1.3, 0), V(length * 0.6, 0.2, 2))
end

-- The top of a buried archway poking out of the ground.
function Props.BuriedArch(parent: Instance, origin: CFrame, x: number, z: number, yaw: number, pal: Palette)
	local f = origin * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0)
	Build.Part(parent, f, V(3, 5, 3), CF(-6, 1.5, 0), P(pal.Stone, M.Sandstone))
	Build.Part(parent, f, V(3, 5, 3), CF(6, 1.5, 0), P(pal.Stone, M.Sandstone))
	Build.Part(parent, f, V(15, 2.4, 3.2), CF(0, 4.6, 0), P(pal.StoneDark, M.Sandstone))
	Build.Part(parent, f, V(3, 1.6, 3.4), CF(0, 6.4, 0), P(pal.Accent:Lerp(pal.Stone, 0.6), M.Sandstone)) -- keystone
	moss(parent, f, pal, CF(0, 4.6, 0), V(15, 2.4, 3.2))
end

-- Simple low rock.
function Props.Rock(parent: Instance, origin: CFrame, x: number, z: number, size: number, rng: Random, color: Color3?)
	-- Faceted low-poly boulder: a main block and two smaller turned blocks.
	local col = color or C(150, 135, 115)
	local yaw = rng:NextNumber(0, 6)
	Build.Part(parent, origin, V(size, size * 0.7, size * 0.9), CF(x, size * 0.25, z) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), yaw, rng:NextNumber(-0.3, 0.3)), P(col, M.Slate))
	Build.Part(parent, origin, V(size * 0.7, size * 0.6, size * 0.7), CF(x, size * 0.32, z) * CFrame.Angles(0, yaw, 0) * CF(size * 0.3, 0, size * 0.15) * CFrame.Angles(0.5, 0.6, 0.4), P(col:Lerp(Color3.new(1, 1, 1), 0.08), M.Slate, { CanCollide = false }))
	Build.Part(parent, origin, V(size * 0.55, size * 0.45, size * 0.6), CF(x, size * 0.18, z) * CFrame.Angles(0, yaw, 0) * CF(-size * 0.35, 0, -size * 0.2) * CFrame.Angles(-0.4, 0.9, 0.3), P(col:Lerp(Color3.new(0, 0, 0), 0.08), M.Slate, { CanCollide = false }))
end

-- Scattered small stones (debris).
function Props.Debris(parent: Instance, origin: CFrame, x: number, z: number, radius: number, count: number, rng: Random, color: Color3)
	for _ = 1, count do
		local s = rng:NextNumber(0.6, 1.6)
		Build.Part(parent, origin, V(s, s * 0.6, s), CF(x + rng:NextNumber(-radius, radius), s * 0.25, z + rng:NextNumber(-radius, radius)) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), P(color, M.Slate, { CanCollide = false }))
	end
end

-- Weathered humanoid statue on a plinth. `holding` adds a disc above the head.
function Props.Statue(parent: Instance, origin: CFrame, x: number, z: number, yaw: number, pal: Palette, emblemColor: Color3?, headless: boolean?): BasePart
	local f = origin * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0)
	local plinth = Build.Part(parent, f, V(5, 3, 5), CF(0, 1.5, 0), P(pal.StoneDark, M.Slate))
	Build.Part(parent, f, V(1.2, 4, 1.4), CF(-0.7, 5, 0), P(pal.Stone, M.Sandstone)) -- legs
	Build.Part(parent, f, V(1.2, 4, 1.4), CF(0.7, 5, 0), P(pal.Stone, M.Sandstone))
	Build.Part(parent, f, V(3.4, 4.4, 1.8), CF(0, 9.2, 0), P(pal.Stone, M.Sandstone)) -- torso (robe)
	Build.Part(parent, f, V(1, 3.8, 1), CF(-2.2, 9.3, -0.3) * CFrame.Angles(rad(-20), 0, rad(8)), P(pal.Stone, M.Sandstone))
	Build.Part(parent, f, V(1, 3.8, 1), CF(2.2, 9.3, -0.3) * CFrame.Angles(rad(-20), 0, rad(-8)), P(pal.Stone, M.Sandstone))
	if not headless then
		Build.Part(parent, f, V(2, 2.2, 2), CF(0, 12.6, 0), P(pal.Stone, M.Sandstone))
		Build.Part(parent, f, V(0.4, 0.7, 0.5), CF(0, 12.4, -1.1), P(pal.StoneDark, M.Sandstone, { CanCollide = false })) -- nose
	else
		Build.Part(parent, f, V(1.4, 0.8, 1.2), CF(0.2, 11.7, 0) * CFrame.Angles(0, 0, rad(25)), P(pal.StoneDark, M.Sandstone))
	end
	if emblemColor then
		local emblem = Build.Part(parent, f, V(0.4, 2.6, 2.6), CF(0, 9.4, -1.6) * CFrame.Angles(0, rad(90), 0), P(emblemColor, M.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
		Build.Light(emblem, emblemColor, 10, 0.8)
	end
	moss(parent, f, pal, CF(0, 1.5, 0), V(5, 3, 5))
	return plinth
end

-- A standing inscription stone (stele). Returns the face part for labels/prompts.
function Props.Stele(parent: Instance, origin: CFrame, x: number, z: number, yaw: number, pal: Palette, text: string?): BasePart
	local f = origin * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0)
	Build.Part(parent, f, V(5, 1, 2.4), CF(0, 0.5, 0), P(pal.StoneDark, M.Slate))
	local face = Build.Part(parent, f, V(4, 6, 1), CF(0, 4, 0), P(pal.Stone, M.Slate))
	Build.Part(parent, f, V(4.4, 1, 1.4), CF(0, 7.4, 0) * CFrame.Angles(0, 0, rad(3)), P(pal.StoneDark, M.Slate))
	moss(parent, f, pal, CF(0, 7.4, 0), V(4.4, 1, 1.4))
	if text then
		Build.Label(face, Enum.NormalId.Front, text, C(70, 50, 30), Enum.Font.Fondamento)
	end
	return face
end

-- Wall-mounted torch with real fire and light.
function Props.Torch(parent: Instance, origin: CFrame, x: number, y: number, z: number)
	Build.Box(parent, origin, V(x - 0.25, y, z - 0.25), V(x + 0.25, y + 4, z + 0.25), P(C(90, 60, 40), M.Wood))
	local head = Build.Part(parent, origin, V(0.9, 0.7, 0.9), CF(x, y + 4.3, z), P(C(60, 45, 35), M.Metal))
	local fire = Instance.new("Fire")
	fire.Size = 3
	fire.Heat = 6
	fire.Parent = head
	Build.Light(head, C(255, 160, 80), 22, 1.6)
end

-- Sealed urn (round body, neck, wax seal).
function Props.Urn(parent: Instance, origin: CFrame, x: number, z: number, color: Color3, rng: Random): BasePart
	local f = origin * CF(x, 0, z) * CFrame.Angles(0, rng:NextNumber(0, 6), rng:NextNumber(-0.08, 0.08))
	local body = Build.Part(parent, f, V(3.4, 3.8, 3.4), CF(0, 1.9, 0), P(color, M.Slate, { Shape = Enum.PartType.Ball }))
	Build.Part(parent, f, V(1.6, 1.7, 1.7), CF(0, 4, 0) * UP, P(color, M.Slate, { Shape = Enum.PartType.Cylinder }))
	Build.Part(parent, f, V(0.4, 2.1, 2.1), CF(0, 4.85, 0) * UP, P(color:Lerp(Color3.new(0, 0, 0), 0.2), M.Slate, { Shape = Enum.PartType.Cylinder }))
	Build.Part(parent, f, V(0.3, 1.5, 1.5), CF(0, 5.1, 0) * UP, P(C(150, 40, 40), M.SmoothPlastic, { Shape = Enum.PartType.Cylinder }))
	Build.Part(parent, f, V(0.25, 3.5, 3.5), CF(0, 2.5, 0) * UP, P(color:Lerp(Color3.new(0, 0, 0), 0.35), M.Slate, { Shape = Enum.PartType.Cylinder, CanCollide = false })) -- painted band
	return body
end

-- Iron-bound chest. Returns the body (search site part).
function Props.Chest(parent: Instance, origin: CFrame, cf: CFrame, wood: Color3?): BasePart
	local o = origin * cf
	local body = Build.Part(parent, o, V(4, 2.2, 2.6), CF(0, 1.1, 0), P(wood or C(110, 70, 40), M.Wood))
	Build.Part(parent, o, V(4, 1.6, 2.6), CF(0, 2.2, 0) * CFrame.Angles(0, rad(90), rad(90)) * UP, P(wood or C(110, 70, 40), M.WoodPlanks, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	for _, x in { -1.5, 1.5 } do
		Build.Part(parent, o, V(0.3, 3.1, 2.7), CF(x, 1.55, 0), P(C(70, 70, 75), M.Metal, { CanCollide = false }))
	end
	Build.Part(parent, o, V(0.6, 0.7, 0.2), CF(0, 1.9, -1.35), P(C(214, 172, 60), M.Metal, { CanCollide = false }))
	return body
end

-- Archaeological dig site: dark mound, grid stakes and string, a sieve and a
-- bucket. Returns the mound (the search site part).
function Props.DigSite(parent: Instance, origin: CFrame, x: number, z: number, soil: Color3): BasePart
	local f = origin * CF(x, 0, z)
	local mound = Build.Part(parent, f, V(1.2, 9, 9), CF(0, 0.4, 0) * UP, P(soil, M.Ground, { Shape = Enum.PartType.Cylinder }))
	for _, p in { V(-5, 0, -5), V(5, 0, -5), V(-5, 0, 5), V(5, 0, 5) } do
		Build.Part(parent, f, V(0.3, 2.2, 0.3), CF(p.X, 1.1, p.Z), P(C(150, 110, 70), M.Wood, { CanCollide = false }))
	end
	for _, side in { { CF(0, 1.9, -5), V(10, 0.08, 0.08) }, { CF(0, 1.9, 5), V(10, 0.08, 0.08) }, { CF(-5, 1.9, 0), V(0.08, 0.08, 10) }, { CF(5, 1.9, 0), V(0.08, 0.08, 10) }, { CF(0, 1.9, 0), V(10, 0.08, 0.08) }, { CF(0, 1.9, 0), V(0.08, 0.08, 10) } } do
		Build.Part(parent, f, side[2] :: Vector3, side[1] :: CFrame, P(C(230, 220, 190), M.Fabric, { CanCollide = false }))
	end
	Build.Part(parent, f, V(0.3, 2.4, 2.4), CF(6.5, 0.6, 2) * CFrame.Angles(0, 0, rad(80)) * UP, P(C(140, 100, 60), M.Wood, { Shape = Enum.PartType.Cylinder, CanCollide = false })) -- sieve
	Build.Part(parent, f, V(1.4, 1.2, 1.2), CF(6.4, 0.6, -2) * UP, P(C(90, 90, 100), M.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false })) -- bucket
	return mound
end

-- Trees come from the shared stylised library (World/Trees) so every zone
-- uses the same blocky low-poly look. Signatures kept for existing callers.

-- Palm tree (desert).
function Props.Palm(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	Trees.Place("Palm", parent, origin * CF(x, 0, z), rng:NextNumber(0.9, 1.2), rng)
end

-- Desert vegetation: blocky cactus or a low dry bush.
function Props.Shrub(parent: Instance, origin: CFrame, x: number, z: number, rng: Random, color: Color3?)
	if not color and rng:NextNumber() < 0.35 then
		Trees.Place("Cactus", parent, origin * CF(x, 0, z), rng:NextNumber(0.7, 1.1), rng)
		return
	end
	local col = color or C(150, 140, 78)
	for i = 1, 2 do
		local s = rng:NextNumber(1.4, 2.4) / i
		Build.Part(parent, origin, V(s * 1.3, s * 0.7, s * 1.3), CF(x + rng:NextNumber(-0.6, 0.6), s * 0.35 + (i - 1) * 0.5, z + rng:NextNumber(-0.6, 0.6)) * CFrame.Angles(0, rng:NextNumber(0, 1.5), 0), P(col, M.SmoothPlastic, { CanCollide = false, CastShadow = false }))
	end
end

-- Giant jungle tree (root fins, broad layered canopy, vines).
function Props.JungleTree(parent: Instance, origin: CFrame, x: number, z: number, rng: Random, scale: number?)
	Trees.Place("Jungle", parent, origin * CF(x, 0, z), (scale or 1) * rng:NextNumber(1.2, 1.5), rng)
end

-- Fern / undergrowth clump.
function Props.Fern(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2 + rng:NextNumber(0, 0.5)
		Build.Part(parent, origin, V(3.2, 0.2, 1), CF(x + math.cos(a) * 1.2, 0.9, z + math.sin(a) * 1.2) * CFrame.Angles(0, -a, rad(28)), P(C(60, 120, 55), M.Grass, { CanCollide = false, CastShadow = false }))
	end
end

-- Thick root arching over the ground.
function Props.Root(parent: Instance, origin: CFrame, x: number, z: number, yaw: number, length: number)
	local f = origin * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0)
	Build.Part(parent, f, V(length * 0.55, 1.4, 1.4), CF(-length * 0.22, 0.8, 0) * CFrame.Angles(0, 0, rad(18)), P(C(88, 66, 46), M.Wood, { Shape = Enum.PartType.Cylinder }))
	Build.Part(parent, f, V(length * 0.55, 1.2, 1.2), CF(length * 0.22, 0.8, 0) * CFrame.Angles(0, 0, rad(-18)), P(C(88, 66, 46), M.Wood, { Shape = Enum.PartType.Cylinder }))
end

-- Hanging vines on a wall/edge: a row of strands from (x1..x2, y, z).
function Props.Vines(parent: Instance, origin: CFrame, cf: CFrame, width: number, length: number, rng: Random)
	for i = 0, math.floor(width / 1.5) do
		local len = length * rng:NextNumber(0.4, 1)
		Build.Part(parent, origin * cf, V(0.25, len, 0.25), CF(-width / 2 + i * 1.5, -len / 2, 0), P(C(58, 112, 52), M.Grass, { CanCollide = false, CastShadow = false }))
	end
end

-- Generic clue object: an "unusual soil pattern" — darker, damp-looking ground.
function Props.SoilPattern(parent: Instance, origin: CFrame, x: number, z: number, color: Color3)
	Build.Part(parent, origin, V(0.15, 5, 7), CF(x, 0.05, z) * CFrame.Angles(0, rad(20), 0) * UP, P(color, M.Ground, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	Build.Part(parent, origin, V(0.16, 2.4, 3), CF(x + 1.6, 0.06, z - 0.8) * UP, P(color:Lerp(Color3.new(0, 0, 0), 0.15), M.Mud, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
end

-- Clue: a pottery shard sticking out of the ground.
function Props.PotteryShard(parent: Instance, origin: CFrame, x: number, z: number, color: Color3)
	Build.Part(parent, origin, V(1.8, 1.4, 0.25), CF(x, 0.35, z) * CFrame.Angles(rad(-25), rad(40), rad(15)), P(color, M.Slate, { CanCollide = false }))
	Build.Part(parent, origin, V(1.6, 0.25, 0.3), CF(x, 0.55, z) * CFrame.Angles(rad(-25), rad(40), rad(15)) * CF(0, 0.5, -0.1), P(color:Lerp(Color3.new(0, 0, 0), 0.4), M.Slate, { CanCollide = false }))
end

-- Clue: a ring of deliberately placed stones.
function Props.StoneRing(parent: Instance, origin: CFrame, x: number, z: number, color: Color3)
	for i = 0, 5 do
		local a = i / 6 * math.pi * 2
		Build.Part(parent, origin, V(1.4, 1, 1.2), CF(x + math.cos(a) * 3.2, 0.35, z + math.sin(a) * 3.2) * CFrame.Angles(0, -a, 0), P(color, M.Slate))
	end
end

-- Clue: glinting rocks (often a mineral deposit — a false lead).
function Props.GlintingRocks(parent: Instance, origin: CFrame, x: number, z: number)
	for i = 0, 3 do
		Build.Part(parent, origin, V(1.2, 0.9, 1), CF(x + i * 1.3 - 2, 0.3, z + (i % 2) * 1.1) * CFrame.Angles(0, i, 0.3), P(C(150, 160, 170), M.Foil, { CanCollide = false, Reflectance = 0.3 }))
	end
end

return Props
