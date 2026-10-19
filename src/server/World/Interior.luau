--[[
	Interior — the main museum building's inside (plot space, floor top y = 1).

	Concept: a two-storey neoclassical hall organised around a rotunda.
	  Ground floor
	    • Entrance hall (double height): ticket desk right, security terminal left
	    • Rotunda: a raised centrepiece exhibit under the dome (the focal point)
	    • Imperial staircase: central flight → landing → two side flights
	    • Arcaded aisles left/right under the upper floor
	  Upper floor (y = 11), reached by the stairs
	    • West gallery  "Hall of Collections"  (navy)
	    • East gallery  "Treasury of Rarities" (burgundy)
	    • Rear bridge overlooking the rotunda
	The upper floor is always built; the "Second Floor" upgrade opens the
	velvet barrier at the foot of the stairs and adds its display slots.

	Everything here is decoration/structure — display slots are built by
	MuseumBuilder.BuildSlot from Upgrades data, like everywhere else.
]]

local Build = require(script.Parent.Build)
local Architecture = require(script.Parent.Architecture)
local AC = Architecture.Colors

local Interior = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local M = Enum.Material
local C = Color3.fromRGB
local UP = CFrame.Angles(0, 0, rad(90))

-- Layout constants (shared with Upgrades slot positions and BARRIERS)
Interior.GalleryX = 9.5 -- upper galleries span |x| 9.5..19.5
Interior.SlabBottom = 10.4
Interior.UpperFloor = 11 -- walking surface of the upper floor
Interior.BridgeZ = 22 -- rear bridge spans z 22..29.5
Interior.CentreZ = 10 -- the rotunda centrepiece sits in the middle of the hall (hall spans z -10..30)

local MARBLE_DARK = C(64, 60, 70)
local WARM = C(255, 226, 188)

local function props(color: Color3, material: Enum.Material?, extra: { [string]: any }?): Build.PartProps
	local p: any = { Color = color, Material = material or Architecture.MaterialFor(color) }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local function box(f: Instance, o: CFrame, a: Vector3, b: Vector3, p: Build.PartProps): BasePart
	return Build.Box(f, o, V(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)), V(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)), p)
end

local function deco(color: Color3, material: Enum.Material?): Build.PartProps
	return props(color, material, { CanCollide = false })
end

-- Soft ceiling fixture: a pale disc with a warm, low-brightness light.
local function fixture(f: Instance, o: CFrame, x: number, y: number, z: number, range: number?, brightness: number?)
	local disc = Build.Part(f, o, V(0.25, 2.4, 2.4), CF(x, y, z) * UP, props(C(250, 240, 222), M.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	Build.Part(f, o, V(0.2, 2.9, 2.9), CF(x, y + 0.1, z) * UP, deco(AC.Bronze, M.Metal)).Shape = Enum.PartType.Cylinder
	Build.Light(disc, WARM, range or 26, brightness or 0.7)
end

-- ── Ground floor ────────────────────────────────────────────────────────────
local function floors(f: Instance, o: CFrame)
	-- marble border band and rotunda medallion (the floor slab itself is in BuildBase)
	local band = deco(MARBLE_DARK, M.Marble)
	box(f, o, V(-18, 1, -8), V(18, 1.03, -7.4), band)
	box(f, o, V(-18, 1, 27.4), V(18, 1.03, 28), band)
	box(f, o, V(-18, 1, -7.4), V(-17.4, 1.03, 27.4), band)
	box(f, o, V(17.4, 1, -7.4), V(18, 1.03, 27.4), band)
	for _, ring in { { 5.2, MARBLE_DARK, M.Marble, 1.02 }, { 4.6, AC.Gold, M.Metal, 1.03 }, { 4.35, AC.Navy, M.Marble, 1.04 } } do
		Build.Part(f, o, V(0.04, ring[1] :: number * 2, ring[1] :: number * 2), CF(0, ring[4] :: number, Interior.CentreZ) * UP, deco(ring[2] :: Color3, ring[3] :: Enum.Material)).Shape = Enum.PartType.Cylinder
	end
	-- navy runner from the door to the rotunda
	box(f, o, V(-2, 1, -9.5), V(2, 1.045, Interior.CentreZ - 5.2), deco(AC.Navy, M.Fabric))
	box(f, o, V(-2.2, 1, -9.5), V(-2, 1.05, Interior.CentreZ - 5.2), deco(AC.Gold, M.Metal))
	box(f, o, V(2, 1, -9.5), V(2.2, 1.05, Interior.CentreZ - 5.2), deco(AC.Gold, M.Metal))
end

-- The rotunda centrepiece: "The Heart of the Museum" (a gilded sun relic in
-- a glass vitrine on a stepped dais, under a spotlight).
local function centrepiece(f: Instance, o: CFrame)
	o = o * CF(0, 0, Interior.CentreZ) -- everything below is built around the middle of the hall
	local function disc(r: number, y0: number, y1: number, color: Color3, material: Enum.Material?, collide: boolean?)
		local p = Build.Part(f, o, V(y1 - y0, r * 2, r * 2), CF(0, (y0 + y1) / 2, 0) * UP, props(color, material, { Shape = Enum.PartType.Cylinder, CanCollide = collide ~= false }))
		return p
	end
	disc(3.0, 1, 1.45, AC.TrimShade)
	disc(2.5, 1, 1.9, AC.Trim)
	disc(1.15, 1.9, 5.1, AC.Navy, M.SmoothPlastic)
	disc(1.35, 5.1, 5.35, AC.Gold, M.Metal)
	disc(1.3, 1.9, 2.2, AC.Gold, M.Metal)
	local glass = disc(1.15, 5.35, 9.2, C(214, 230, 240), M.Glass, false)
	glass.Transparency = 0.78
	disc(1.3, 9.2, 9.45, AC.Gold, M.Metal)
	disc(0.5, 9.45, 9.9, AC.Gold, M.Metal)
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		box(f, o, V(math.cos(a) * 1.15 - 0.08, 5.35, math.sin(a) * 1.15 - 0.08), V(math.cos(a) * 1.15 + 0.08, 9.2, math.sin(a) * 1.15 + 0.08), deco(AC.Gold, M.Metal))
	end
	-- the relic: a gilded sun disc with rays and a jade heart, on a small stand
	box(f, o, V(-0.35, 5.35, -0.25), V(0.35, 6.2, 0.25), deco(AC.BronzeDark, M.Metal))
	local relic = CF(0, 7.4, 0)
	Build.Part(f, o, V(0.22, 1.5, 1.5), relic * CFrame.Angles(0, rad(90), 0), deco(C(236, 184, 64), M.Metal)).Shape = Enum.PartType.Cylinder
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		local long = i % 2 == 0
		Build.Part(f, o, V(0.18, if long then 0.55 else 0.35, 0.18), relic * CF(math.cos(a) * (if long then 1.0 else 0.92), math.sin(a) * (if long then 1.0 else 0.92), 0) * CFrame.Angles(0, 0, a - math.pi / 2), deco(C(236, 184, 64), M.Metal))
	end
	Build.Part(f, o, V(0.5, 0.5, 0.5), relic * CF(0, 0, -0.12), deco(C(60, 150, 110), M.Glass)).Shape = Enum.PartType.Ball
	local glow = Build.Part(f, o, V(0.2, 0.2, 0.2), relic, props(WARM, M.SmoothPlastic, { CanCollide = false, Name = "SoftLamp" }))
	glow.Transparency = 1
	Build.Light(glow, C(255, 214, 160), 14, 0.35) -- a soft glow on the relic
	-- bronze stanchions and velvet ropes
	local posts = {}
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2 + math.pi / 4
		local p = V(math.cos(a) * 3.5, 1, math.sin(a) * 3.5)
		table.insert(posts, p)
		Build.Part(f, o, V(0.7, 0.15, 0.7), CF(p.X, 1.08, p.Z), deco(AC.Bronze, M.Metal))
		Build.Part(f, o, V(0.2, 2.3, 0.2), CF(p.X, 2.3, p.Z), deco(AC.Bronze, M.Metal))
		local ball = Build.Part(f, o, V(0.4, 0.4, 0.4), CF(p.X, 3.5, p.Z), props(AC.Gold, M.Metal, { CanCollide = false, Name = "SoftLamp" }))
		ball.Shape = Enum.PartType.Ball
		Build.Light(ball, C(255, 220, 170), 8, 0.22) -- tiny warm glow on each post
	end
	for i = 1, 4 do
		local a, b = posts[i] + V(0, 2.25, 0), posts[(i % 4) + 1] + V(0, 2.25, 0)
		Build.Part(f, o, V(0.16, 0.16, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), deco(C(140, 30, 44), M.Fabric))
	end
	-- a bronze lectern with the exhibit's title
	box(f, o, V(-0.2, 1, -4.6), V(0.2, 3.1, -4.3), deco(AC.BronzeDark, M.Metal))
	local plate = Build.Part(f, o, V(1.8, 0.1, 1.0), CF(0, 3.25, -4.55) * CFrame.Angles(rad(-35), 0, 0), deco(AC.Bronze, M.Metal))
	local gui = Build.Label(plate, Enum.NormalId.Top, "THE HEART OF THE MUSEUM\nSun relic of the first kings", C(250, 232, 190), Enum.Font.GothamBold)
	local _ = gui
	-- a spotlight from the rotunda ceiling
	local lamp = Build.Part(f, o, V(0.6, 0.6, 0.6), CF(0, 18.3, 0), deco(AC.BronzeDark, M.Metal))
	local spot = Instance.new("SpotLight")
	spot.Face = Enum.NormalId.Bottom
	spot.Angle = 28
	spot.Range = 22
	spot.Brightness = 0.7
	spot.Color = C(255, 230, 196)
	spot.Parent = lamp
end

local function lobby(f: Instance, o: CFrame): BasePart
	-- Ticket desk (revenue collection point — name and box kept for VisitorService)
	local desk = Build.Box(f, o, V(10, 1, -7), V(17, 4, -5), props(C(96, 62, 38), M.Wood))
	desk.Name = "TicketDesk"
	box(f, o, V(9.8, 4, -7.2), V(17.2, 4.3, -4.8), props(AC.Trim))
	box(f, o, V(9.9, 1, -7.15), V(17.1, 1.4, -4.85), props(AC.TrimShade))
	for _, x in { 11.5, 13.5, 15.5 } do
		box(f, o, V(x - 0.7, 1.8, -7.12), V(x + 0.7, 3.5, -7.05), deco(C(118, 78, 48), M.Wood))
	end
	local deskSign = box(f, o, V(11.5, 4.3, -6.15), V(15.5, 5.8, -6), deco(AC.Navy, M.SmoothPlastic))
	Build.Label(deskSign, Enum.NormalId.Front, "TICKETS", C(236, 206, 140), Enum.Font.GothamBold)
	-- grand chandelier-style pendant over the entrance hall
	box(f, o, V(-0.08, 15.5, -4.58), V(0.08, 19, -4.42), deco(AC.Gold, M.Metal))
	local ring = Build.Part(f, o, V(0.35, 4.6, 4.6), CF(0, 15.4, -4.5) * UP, deco(AC.Gold, M.Metal))
	ring.Shape = Enum.PartType.Cylinder
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Build.Part(f, o, V(0.55, 0.55, 0.55), CF(math.cos(a) * 2.1, 15.85, -4.5 + math.sin(a) * 2.1), deco(C(255, 236, 205), M.Glass)).Shape = Enum.PartType.Ball
	end
	local core = Build.Part(f, o, V(1, 1, 1), CF(0, 14.9, -4.5), deco(C(255, 236, 205), M.Glass))
	core.Shape = Enum.PartType.Ball
	Build.Light(core, WARM, 30, 0.9)
	return desk
end

function Interior.Build(f: Instance, o: CFrame): BasePart
	-- Single-floor hall: the rotunda centrepiece is the focal point under the
	-- full-height coffered ceiling; aisles and lobby stay open.
	floors(f, o)
	centrepiece(f, o)
	for _, sx in { -1, 1 } do -- full-height pilasters, clear of the wing doorways
		for _, z in { -2.2, 3.8, 16.2, 26.5 } do
			Architecture.Pilaster(f, o, V(sx * 19.5, 1, z), V(-sx, 0, 0), 1.3, 17.2)
		end
		for _, z in { -4, 10, 24 } do
			fixture(f, o, sx * 13.5, 18.6, z, 30, 0.55)
		end
	end
	fixture(f, o, 0, 18.6, 12, 30, 0.55)
	fixture(f, o, 0, 18.6, 24, 28, 0.55)
	return lobby(f, o)
end

return Interior
