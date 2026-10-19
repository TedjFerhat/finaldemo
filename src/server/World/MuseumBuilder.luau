--[[
	MuseumBuilder
	All museum geometry, generated from code. Every function builds in PLOT
	space (the `origin` CFrame is the plot centre at ground level; the museum
	entrance faces local -Z).

	Want a nicer museum later? Replace the inside of any Builders.<upgradeId>
	function, or build a model in Studio and clone it here instead.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)
local Build = require(script.Parent.Build)
local Trees = require(script.Parent.Trees)
local Architecture = require(script.Parent.Architecture)
local Grounds = require(script.Parent.Grounds)
local Interior = require(script.Parent.Interior)
local AC = Architecture.Colors

local MuseumBuilder = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local UP = CFrame.Angles(0, 0, rad(90))

local M = Enum.Material
-- Palette matches the reference: cream stone, light floors, navy accents.
local COLORS = {
	Stone = Color3.fromRGB(238, 228, 206), -- cream walls
	StoneDark = Color3.fromRGB(206, 194, 170), -- plinth / cornice trim
	Marble = Color3.fromRGB(244, 240, 232),
	Floor = Color3.fromRGB(226, 218, 204),
	Paving = Color3.fromRGB(214, 208, 196),
	Window = Color3.fromRGB(46, 62, 84),
	Navy = Color3.fromRGB(28, 44, 82),
	Pedestal = Color3.fromRGB(52, 58, 72),
	Hedge = Color3.fromRGB(62, 140, 62),
	Wood = Color3.fromRGB(142, 96, 58),
	WoodDark = Color3.fromRGB(96, 62, 38),
	Roof = Color3.fromRGB(196, 192, 184),
	Gold = Color3.fromRGB(214, 172, 60),
	Green = Color3.fromRGB(28, 44, 82), -- signs are navy now
	Blue = Color3.fromRGB(34, 54, 98),
	Red = Color3.fromRGB(128, 32, 42),
	Metal = Color3.fromRGB(70, 72, 78),
	Warm = Color3.fromRGB(255, 236, 210),
}

local function props(color: Color3, material: Enum.Material?, extra: { [string]: any }?): Build.PartProps
	local p: any = { Color = color, Material = material or Architecture.MaterialFor(color) }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local function ceilingLight(parent: Instance, origin: CFrame, x: number, y: number, z: number, range: number?)
	-- A soft fixture (not neon) with a gentle warm light.
	local lamp = Build.Part(parent, origin, V(2.2, 0.25, 2.2), CF(x, y, z), props(Color3.fromRGB(250, 238, 220), M.SmoothPlastic, { CanCollide = false }))
	Build.Light(lamp, COLORS.Warm, range or 40, 0.4, false)
end

local function roomSign(parent: Instance, origin: CFrame, min: Vector3, max: Vector3, face: Enum.NormalId, text: string)
	local sign = Build.Box(parent, origin, min, max, props(COLORS.Green, M.SmoothPlastic, { CanCollide = false }))
	Build.Label(sign, face, text, Color3.new(1, 1, 1))
end

export type BaseRefs = { Desk: BasePart, SignLabel: TextLabel }

-- ── Base museum (free) ──────────────────────────────────────────────────────
-- Neoclassical two-storey hall after the reference: a curved glass entrance
-- bay with white mullions, four round columns, semicircular steps, an arched
-- crown with the museum name, framed windows (pediments upstairs), belt
-- course, layered cornice and a roof balustrade. Footprint, doorways, desk and
-- display slots are unchanged.
local BAY_R = 9 -- radius of the glass bay (centre on the facade at z = -10.5)
local BAY_N = 7 -- glass segments
local BAY_Z = -10.5

local function bayAngle(k: number): number
	return math.pi + k * math.pi / BAY_N
end

local function bayPos(angle: number, r: number, y: number): Vector3
	return V(math.cos(angle) * r, y, BAY_Z + math.sin(angle) * r)
end

local function disc(f: Instance, origin: CFrame, radius: number, y0: number, y1: number, color: Color3, material: Enum.Material?, collide: boolean?)
	Build.Part(f, origin, V(y1 - y0, radius * 2, radius * 2), CF(0, (y0 + y1) / 2, BAY_Z) * UP, props(color, material, { Shape = Enum.PartType.Cylinder, CanCollide = collide ~= false }))
end

local function buildBay(f: Instance, origin: CFrame)
	local glass = props(AC.Glass, M.Glass, { Transparency = 0.2, Reflectance = 0.08 })
	local chord = 2 * BAY_R * math.sin(math.pi / (2 * BAY_N))
	local rMid = BAY_R * math.cos(math.pi / (2 * BAY_N))
	for i = 0, BAY_N - 1 do
		local am = math.pi + (i + 0.5) * math.pi / BAY_N
		local out = V(math.cos(am), 0, math.sin(am))
		local function seg(y0: number, y1: number, depth: number, color: Build.PartProps, inset: number?)
			local pos = bayPos(am, rMid - (inset or 0), (y0 + y1) / 2)
			Build.Part(f, origin, V(chord + 0.05, y1 - y0, depth), CFrame.lookAt(pos, pos + out), color)
		end
		local entrance = i >= 2 and i <= 4
		if entrance then
			seg(8, 9.6, 0.3, glass) -- transom over the doors
		else
			seg(1, 1.6, 0.4, props(AC.TrimShade))
			seg(1.6, 9.6, 0.3, glass)
		end
		seg(9.6, 10.4, 0.8, props(AC.Trim)) -- belt course
		seg(10.4, 18.2, 0.3, glass)
	end
	-- Mullions (wider where the bay meets the facade)
	for k = 0, BAY_N do
		local a = bayAngle(k)
		local pos = bayPos(a, BAY_R - 0.05, 9.6)
		local wide = k == 0 or k == BAY_N
		Build.Part(f, origin, V(if wide then 1.3 else 0.5, 17.2, 0.75), CFrame.lookAt(pos, pos + V(math.cos(a), 0, math.sin(a))), props(AC.Trim))
	end
	-- Floor, steps and the overhanging cornice/entablature
	disc(f, origin, BAY_R + 0.1, 0, 1.01, COLORS.Floor)
	disc(f, origin, 11.5, 0, 1, AC.Trim)
	disc(f, origin, 12.05, 0, 0.66, AC.TrimShade)
	disc(f, origin, 12.6, 0, 0.33, AC.Trim)
	disc(f, origin, 11.6, 18.2, 18.8, AC.Trim)
	disc(f, origin, 11.9, 18.8, 19.4, AC.Trim)
	disc(f, origin, 12.1, 19.4, 20, AC.TrimShade)
	-- Four columns carrying the entablature
	for _, deg in { -76, -42, 42, 76 } do
		local a = 1.5 * math.pi + rad(deg)
		Architecture.Column(f, origin, bayPos(a, 10.2, 1), 17.2, 1.6)
	end
	-- Balustrade round the bay roof, interrupted by the crown
	local cut = math.acos(5.3 / 11.4) -- angle from the axis where the crown ends
	local function railArc(a0: number, a1: number)
		Architecture.Balustrade(f, origin, bayPos(a0, 11.4, 20), bayPos(a1, 11.4, 20))
	end
	for i = 0, BAY_N - 1 do
		local a0, a1 = bayAngle(i), bayAngle(i + 1)
		if i == 2 then
			railArc(a0, math.pi + cut)
		elseif i == 4 then
			railArc(2 * math.pi - cut, a1)
		elseif i ~= 3 then
			railArc(a0, a1)
		end
	end
	-- Lobby light
	local lobby = Build.Part(f, origin, V(0.3, 3, 3), CF(0, 18.05, -15) * UP, props(Color3.fromRGB(255, 240, 220), M.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	Build.Light(lobby, COLORS.Warm, 26, 0.7)
end

-- Arched crown above the bay. Returns the label used for the owner's name.
local function buildCrown(f: Instance, origin: CFrame): TextLabel
	local block = Build.Box(f, origin, V(-5.2, 20, -21.6), V(5.2, 23.6, -20.4), props(AC.Trim, nil, { Name = "Crown" }))
	Build.Box(f, origin, V(-5.7, 23.6, -21.9), V(5.7, 24, -20.2), props(AC.TrimShade))
	Build.Part(f, origin, V(1, 6.2, 6.2), CF(0, 23.6, -21) * CFrame.Angles(0, rad(90), 0), props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, origin, V(0.3, 1.8, 1.8), CF(0, 25, -21.55) * CFrame.Angles(0, rad(90), 0), props(AC.TrimShade, nil, { Shape = Enum.PartType.Cylinder, CanCollide = false, Name = "Emblem" }))
	for _, x in { -5, 5 } do
		Build.Box(f, origin, V(x - 0.5, 24, -21.4), V(x + 0.5, 25.2, -20.4), props(AC.Trim))
	end
	local _ = block
	-- Navy inset plaque with gold-trimmed edge carries the owner's name.
	Build.Box(f, origin, V(-4.5, 20.5, -21.75), V(4.5, 23.1, -21.6), props(AC.Gold, M.Metal, { CanCollide = false }))
	local plaque = Build.Box(f, origin, V(-4.3, 20.7, -21.8), V(4.3, 22.9, -21.7), props(AC.Navy, M.SmoothPlastic, { CanCollide = false, Name = "CrownPlaque" }))
	return Build.Label(plaque, Enum.NormalId.Front, "Available Museum", Color3.fromRGB(240, 226, 190), Enum.Font.GothamBold)
end

-- A 1-stud wall along X (at z = fixed) or Z (at x = fixed) from a1 to a2,
-- y 1..19, with rectangular openings { centre, width, bottom, top }.
local function shellWall(f: Instance, origin: CFrame, axis: string, fixed: number, a1: number, a2: number, openings: { { number } }, p: Build.PartProps)
	local function box(s1: number, s2: number, y0: number, y1: number)
		if s2 - s1 < 0.05 or y1 - y0 < 0.05 then
			return
		end
		if axis == "X" then
			Build.Box(f, origin, V(s1, y0, fixed - 0.5), V(s2, y1, fixed + 0.5), p)
		else
			Build.Box(f, origin, V(fixed - 0.5, y0, s1), V(fixed + 0.5, y1, s2), p)
		end
	end
	-- group openings into columns (same centre) so piers run full height
	table.sort(openings, function(x, y)
		return x[1] < y[1]
	end)
	local cursor = a1
	local i = 1
	while i <= #openings do
		local c, w = openings[i][1], openings[i][2]
		local column = {}
		local half = w / 2
		while i <= #openings and math.abs(openings[i][1] - c) < 0.01 do
			table.insert(column, openings[i])
			half = math.max(half, openings[i][2] / 2)
			i += 1
		end
		box(cursor, c - half, 1, 19)
		table.sort(column, function(x, y)
			return x[3] < y[3]
		end)
		local y = 1
		for _, o in column do
			box(c - half, c + half, y, o[3])
			y = o[4]
		end
		box(c - half, c + half, y, 19)
		cursor = c + half
	end
	box(cursor, a2, 1, 19)
end

function MuseumBuilder.BuildBase(parent: Instance, origin: CFrame): BaseRefs
	local f = Build.Folder(parent, "Base")
	local wall = props(AC.Wall, M.Plaster)

	-- Floor and forecourt (kept clear of the upgrade pads)
	Build.Box(f, origin, V(-20.5, 0, -10.5), V(20.5, 1, 30.5), props(Color3.fromRGB(228, 220, 204), M.Marble))
	Grounds.Build(f, origin)

	-- Shell (doorways to the wings are closed by barriers until purchased)
	-- Walls with real openings for the doors and every window, so daylight
	-- comes in and the interior can be seen from outside.
	local GROUND_WIN = { 3.1, 7.3 } -- arched windows (rectangular part)
	local UPPER_WIN = { 10.9, 16.1 }
	local function openingsAt(centres: { number }, w: number, door: { number }?): { { number } }
		local list = {}
		for _, c in centres do
			table.insert(list, { c, w, GROUND_WIN[1], GROUND_WIN[2] })
			table.insert(list, { c, w + 0.2, UPPER_WIN[1], UPPER_WIN[2] })
		end
		if door then
			table.insert(list, door)
		end
		return list
	end
	shellWall(f, origin, "X", -10, -20.5, 20.5, openingsAt({ -15.4, 15.4 }, 3, { 0, 10, 1, 13 }), wall)
	shellWall(f, origin, "X", 30, -20.5, 20.5, openingsAt({ -13, 13 }, 3, { 0, 10, 1, 10.4 }), wall)
	shellWall(f, origin, "Z", 20, -9.5, 29.5, openingsAt({ -4, 24 }, 3, { 10, 10, 1, 10.4 }), wall)
	shellWall(f, origin, "Z", -20, -9.5, 29.5, openingsAt({ -4, 24 }, 3, { 10, 10, 1, 10.4 }), wall)
	Build.Box(f, origin, V(-20.5, 19, -10.5), V(20.5, 20, 30.5), props(COLORS.Roof))

	Architecture.Dress(f, origin, {
		X0 = -20.5, X1 = 20.5, Z0 = -10.5, Z1 = 30.5, Top = 19, Belt = 10,
		Faces = { Front = true, Back = true, Left = true, Right = true },
		Gaps = { Front = { { -12.7, 12.7 } }, Left = { { 4.6, 15.4 } }, Right = { { 4.6, 15.4 } }, Back = { { -5.4, 5.4 } } },
		RailGaps = { Front = { { -11.6, 11.6 } } },
	})
	buildBay(f, origin)
	local label = buildCrown(f, origin)

	-- Pilasters where the bay meets the facade and round the doorways
	for _, side in { -1, 1 } do
		Architecture.Pilaster(f, origin, V(side * 10.3, 1, -10.5), V(0, 0, -1), 1.4, 17.2)
		Architecture.Pilaster(f, origin, V(side * 20.5, 1.8, 3.8), V(side, 0, 0), 1.2, 15.4)
		Architecture.Pilaster(f, origin, V(side * 20.5, 1.8, 16.2), V(side, 0, 0), 1.2, 15.4)
		Architecture.Pilaster(f, origin, V(side * 6.2, 1.8, 30.5), V(0, 0, 1), 1.2, 15.4)
	end

	-- Rusticated (banded) stone on the ground floor of every exterior face
	for _, side in { -1, 1 } do
		Architecture.Rustication(f, origin, V(side * 11.1, 0, -10.5), V(side * 18.7, 0, -10.5), V(0, 0, -1), 1.8, 9.6)
		Architecture.Rustication(f, origin, V(side * 20.5, 0, -8.6), V(side * 20.5, 0, 3.1), V(side, 0, 0), 1.8, 9.6)
		Architecture.Rustication(f, origin, V(side * 20.5, 0, 16.9), V(side * 20.5, 0, 28.6), V(side, 0, 0), 1.8, 9.6)
		Architecture.Rustication(f, origin, V(side * 6.9, 0, 30.5), V(side * 18.7, 0, 30.5), V(0, 0, 1), 1.8, 9.6)
	end
	-- Windows: arched downstairs; upstairs French windows (with balconies on
	-- the front) under pediments.
	for _, side in { -1, 1 } do
		for _, w in { { V(side * 15.4, 0, -10.5), V(0, 0, -1) }, { V(side * 20.5, 0, -4), V(side, 0, 0) }, { V(side * 20.5, 0, 24), V(side, 0, 0) }, { V(side * 13, 0, 30.5), V(0, 0, 1) } } do
			local pos, out = w[1] :: Vector3, w[2] :: Vector3
			Architecture.ArchWindow(f, origin, V(pos.X, 5.2, pos.Z), out, 3, 4.2, if out.Z < 0 then AC.Gold else nil)
			Architecture.Window(f, origin, V(pos.X, 13.5, pos.Z), out, 3.2, 5.2, "Pediment")
		end
		-- stone balcony on carved brackets under the front upper windows
		local bx = side * 15.4
		Build.Box(f, origin, V(bx - 2.9, 10.35, -12.3), V(bx + 2.9, 10.8, -10.5), props(AC.Trim))
		Build.Box(f, origin, V(bx - 3.05, 10.8, -12.45), V(bx + 3.05, 10.95, -10.5), props(AC.TrimShade))
		for _, dx in { -2.2, 2.2 } do
			Build.Box(f, origin, V(bx + dx - 0.35, 9.2, -11.6), V(bx + dx + 0.35, 10.35, -10.5), props(AC.TrimShade))
		end
		Architecture.Balustrade(f, origin, V(bx - 2.7, 10.95, -12.1), V(bx + 2.7, 10.95, -12.1), 1.5)
		Architecture.Balustrade(f, origin, V(bx - 2.7, 10.95, -12.1), V(bx - 2.7, 10.95, -10.6), 1.5, false)
		Architecture.Balustrade(f, origin, V(bx + 2.7, 10.95, -12.1), V(bx + 2.7, 10.95, -10.6), 1.5, false)
	end

	-- ── Entrance portal (the focal point seen through the glass bay) ──
	-- Stone jambs, a voussoir arch with a gold keystone, a navy "MUSEUM"
	-- plaque in the tympanum, open bronze doors and warm light from inside.
	for _, sx in { -1, 1 } do
		Build.Box(f, origin, V(math.min(sx * 5, sx * 6.1), 1, -11), V(math.max(sx * 5, sx * 6.1), 13, -10.5), props(AC.Trim))
		Build.Box(f, origin, V(math.min(sx * 4.85, sx * 6.25), 1, -11.1), V(math.max(sx * 4.85, sx * 6.25), 1.8, -10.5), props(AC.TrimShade))
	end
	local archC = V(0, 12.5, -10.75)
	for i = 0, 8 do
		local a = math.pi * (i + 0.5) / 9
		local r = 5.2
		local pos = archC + V(math.cos(a) * r, math.sin(a) * r, 0)
		local key = i == 4
		Build.Part(f, origin, V(if key then 1.5 else 1.15, if key then 1.7 else 1.2, if key then 0.8 else 0.55), CFrame.new(pos) * CFrame.Angles(0, 0, a - math.pi / 2), props(if key then AC.Gold else AC.Trim, if key then M.Metal else nil, { CanCollide = false }))
	end
	local tymp = Build.Box(f, origin, V(-3.4, 13.7, -10.65), V(3.4, 15.5, -10.55), props(AC.Navy, M.SmoothPlastic, { CanCollide = false }))
	Build.Label(tymp, Enum.NormalId.Front, "MUSEUM", Color3.fromRGB(226, 190, 110), Enum.Font.GothamBold)
	-- open bronze doors (swung into the lobby, never blocking the way)
	for _, sx in { -1, 1 } do
		local hinge = V(sx * 4.85, 6.85, -9.7)
		local dir = V(-sx * 0.26, 0, 0.966)
		local centre = hinge + dir * 1.25
		Build.Part(f, origin, V(0.3, 11.7, 2.5), CFrame.lookAt(centre, centre + dir), props(AC.BronzeDark, M.Metal, { CanCollide = false }))
		local handle = centre + V(-sx * 0.25, -0.6, 0) + dir * 0.9
		Build.Part(f, origin, V(0.2, 1.4, 0.2), CFrame.new(handle), props(AC.Gold, M.Metal, { CanCollide = false }))
	end
	-- warm interior glow spilling out of the doorway
	local glow = Build.Part(f, origin, V(1, 1, 1), CF(0, 7, -6.5), props(COLORS.Warm, M.SmoothPlastic, { Transparency = 1, CanCollide = false, CanQuery = false }))
	Build.Light(glow, Color3.fromRGB(255, 196, 130), 20, 1.4)
	-- ── Extra exterior detail ──
	-- Paved apron round the building
	local apron = props(COLORS.Paving)
	Build.Box(f, origin, V(-22.5, 0, 30.5), V(22.5, 0.12, 32.5), apron)
	Build.Box(f, origin, V(-22.5, 0, -10.5), V(-20.5, 0.12, 30.5), apron)
	Build.Box(f, origin, V(20.5, 0, -10.5), V(22.5, 0.12, 30.5), apron)
	-- ── Dome over the main hall (the museum's signature silhouette) ──
	local dc = V(0, 20, 13)
	local domeColor = Color3.fromRGB(40, 54, 84)
	Build.Part(f, origin, V(0.8, 15, 15), CF(dc.X, 20.4, dc.Z) * UP, props(AC.TrimShade, nil, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, origin, V(5, 13, 13), CF(dc.X, 23.3, dc.Z) * UP, props(AC.Wall, M.Plaster, { Shape = Enum.PartType.Cylinder }))
	for i = 0, 11 do -- drum pilasters
		local a = i / 12 * math.pi * 2
		local pos = V(dc.X + math.cos(a) * 6.55, 23.3, dc.Z + math.sin(a) * 6.55)
		Build.Part(f, origin, V(0.7, 5, 0.35), CFrame.lookAt(pos, pos + V(math.cos(a), 0, math.sin(a))), props(AC.Trim, nil, { CanCollide = false }))
		if i % 2 == 0 then -- small round windows between pilasters
			local wa = a + math.pi / 12
			local wpos = V(dc.X + math.cos(wa) * 6.52, 23.4, dc.Z + math.sin(wa) * 6.52)
			Build.Part(f, origin, V(0.15, 1.4, 1.4), CFrame.lookAt(wpos, wpos + V(math.cos(wa), 0, math.sin(wa))) * CFrame.Angles(0, rad(90), 0), props(AC.Glass, M.Glass, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
		end
	end
	Build.Part(f, origin, V(0.6, 14.2, 14.2), CF(dc.X, 26.05, dc.Z) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, origin, V(12.6, 12.6, 12.6), CF(dc.X, 26.3, dc.Z), props(domeColor, M.Metal, { Shape = Enum.PartType.Ball }))
	-- gilded ribs following the dome's curve
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local prev = nil
		for k = 0, 4 do
			local el = k / 4 * math.pi / 2 * 0.92
			local p = V(dc.X + math.cos(a) * math.cos(el) * 6.35, 26.3 + math.sin(el) * 6.35, dc.Z + math.sin(a) * math.cos(el) * 6.35)
			if prev then
				local mid = (prev + p) / 2
				Build.Part(f, origin, V(0.22, 0.22, (p - prev).Magnitude + 0.1), CFrame.lookAt(mid, p), props(AC.Gold, M.Metal, { CanCollide = false }))
			end
			prev = p
		end
	end
	-- lantern (cupola) with gold finial
	Build.Part(f, origin, V(2.2, 2.6, 2.6), CF(dc.X, 33.3, dc.Z) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, origin, V(0.4, 3.2, 3.2), CF(dc.X, 34.5, dc.Z) * UP, props(AC.TrimShade, nil, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, origin, V(2.6, 2.6, 2.6), CF(dc.X, 34.7, dc.Z), props(domeColor, M.Metal, { Shape = Enum.PartType.Ball }))
	Build.Part(f, origin, V(0.7, 0.7, 0.7), CF(dc.X, 36.2, dc.Z), props(AC.Gold, M.Metal, { Shape = Enum.PartType.Ball }))
	Build.Part(f, origin, V(1.6, 0.18, 0.18), CF(dc.X, 37.2, dc.Z) * UP, props(AC.Gold, M.Metal))
	-- Urns on the balustrade corners
	for _, c in { V(-20.3, 0, -10.3), V(20.3, 0, -10.3), V(-20.3, 0, 30.3), V(20.3, 0, 30.3) } do
		Build.Box(f, origin, V(c.X - 0.6, 21.95, c.Z - 0.6), V(c.X + 0.6, 22.35, c.Z + 0.6), props(AC.TrimShade))
		Build.Part(f, origin, V(1.3, 1.3, 1.3), CF(c.X, 23, c.Z), props(AC.Trim, nil, { Shape = Enum.PartType.Ball }))
		Build.Part(f, origin, V(0.4, 0.6, 0.6), CF(c.X, 23.75, c.Z) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
	end
	-- Dentil course under the front cornice
	for _, side in { -1, 1 } do
		for x = 12.2, 20, 0.95 do
			if math.abs(x - 15.4) < 2.9 then
				continue -- leave room for the window pediment
			end
			Build.Box(f, origin, V(side * x - 0.22, 17.75, -10.85), V(side * x + 0.22, 18.2, -10.5), props(AC.Trim, nil, { CanCollide = false }))
		end
	end
	-- Flagpoles beside the crown
	for _, side in { -1, 1 } do
		local x = side * 7.6
		Build.Part(f, origin, V(9, 0.3, 0.3), CF(x, 24.5, -18.8) * UP, props(Color3.fromRGB(200, 200, 205), M.Metal))
		Build.Part(f, origin, V(0.6, 0.6, 0.6), CF(x, 29.1, -18.8), props(AC.Gold, M.Metal, { Shape = Enum.PartType.Ball }))
		Build.Box(f, origin, V(math.min(x, x + side * 3.4), 26.2, -18.85), V(math.max(x, x + side * 3.4), 28.4, -18.75), props(COLORS.Navy, M.Fabric, { CanCollide = false }))
		Build.Box(f, origin, V(math.min(x + side * 1.2, x + side * 2.2), 26.8, -18.9), V(math.max(x + side * 1.2, x + side * 2.2), 27.8, -18.7), props(AC.Gold, M.SmoothPlastic, { CanCollide = false }))
	end
	-- ── Interior (see World/Interior: rotunda, stairs, upper galleries) ──
	local desk = Interior.Build(f, origin)
	-- Wainscot with a rail on the ground-floor walls (doorways left clear)
	local wains = props(Color3.fromRGB(110, 74, 48), M.Wood, { CanCollide = false })
	local railP = props(AC.Trim, nil, { CanCollide = false })
	for _, span in { { -19.5, -5 }, { 5, 19.5 } } do
		Build.Box(f, origin, V(span[1], 1, -9.5), V(span[2], 3, -9.35), wains)
		Build.Box(f, origin, V(span[1], 3, -9.5), V(span[2], 3.25, -9.25), railP)
		Build.Box(f, origin, V(span[1], 1, 29.35), V(span[2], 3, 29.5), wains)
		Build.Box(f, origin, V(span[1], 3, 29.25), V(span[2], 3.25, 29.5), railP)
	end
	for _, side in { -1, 1 } do
		local x0 = side * 19.5
		for _, span in { { -9.5, 5 }, { 15, 29.5 } } do
			Build.Box(f, origin, V(math.min(x0, x0 - side * 0.15), 1, span[1]), V(math.max(x0, x0 - side * 0.15), 3, span[2]), wains)
			Build.Box(f, origin, V(math.min(x0, x0 - side * 0.25), 3, span[1]), V(math.max(x0, x0 - side * 0.25), 3.25, span[2]), railP)
		end
	end
	-- Coffered ceiling beams (rotunda and upper galleries)
	local beam = props(AC.Trim, nil, { CanCollide = false })
	for _, z in { 2.5, 10.5, 18.5 } do
		Build.Box(f, origin, V(-19.5, 18.3, z - 0.4), V(19.5, 19, z + 0.4), beam)
	end
	for _, x in { -7, 7 } do
		Build.Box(f, origin, V(x - 0.4, 18.3, -9.5), V(x + 0.4, 19, 29.5), beam)
	end

	-- Garden trees on the plot sides (away from pads and wings)
	local rng = Random.new(3)
	for _, side in { -1, 1 } do
		Trees.Place("Round", f, origin * CF(side * 58, 0, 52), 1, rng)
		Trees.Place("Small", f, origin * CF(side * 58, 0, 62), 1.1, rng)
		Trees.Place("Tall", f, origin * CF(side * 58, 0, 74), 1, rng)
	end

	return { Desk = desk, SignLabel = label }
end

-- ── Barriers ("coming soon" walls in front of locked wings) ────────────────
-- Upgrade = what removes it; Host = what must be built for it to exist.
local BARRIERS = {
	-- (wing doorways are 9.4 high now: the upper floor sits above them)
	{ Upgrade = "east_wing", Host = "base", Min = V(19.6, 1, 5), Max = V(20.4, 10.4, 15), Face = Enum.NormalId.Left },
	{ Upgrade = "west_wing", Host = "base", Min = V(-20.4, 1, 5), Max = V(-19.6, 10.4, 15), Face = Enum.NormalId.Right },
	{ Upgrade = "grand_gallery", Host = "base", Min = V(-5, 1, 29.6), Max = V(5, 10.4, 30.4), Face = Enum.NormalId.Front },
	{ Upgrade = "fossil_hall", Host = "east_wing", Min = V(30, 1, 24.6), Max = V(40, 11, 25.4), Face = Enum.NormalId.Front },
	{ Upgrade = "treasure_vault", Host = "west_wing", Min = V(-40, 1, 24.6), Max = V(-30, 11, 25.4), Face = Enum.NormalId.Front },
}

function MuseumBuilder.BuildBarriers(parent: Instance, origin: CFrame, owned: { [string]: boolean })
	-- A navy velvet curtain on a bronze rail closes each future doorway, with
	-- a small bronze plaque naming the upgrade that opens it.
	local normals = { [Enum.NormalId.Left] = V(-1, 0, 0), [Enum.NormalId.Right] = V(1, 0, 0), [Enum.NormalId.Front] = V(0, 0, -1) }
	for _, b in BARRIERS do
		local hostBuilt = b.Host == "base" or owned[b.Host]
		if hostBuilt and not owned[b.Upgrade] then
			local up = Upgrades.ById[b.Upgrade]
			if (b :: any).Invisible then
				local wall = Build.Box(parent, origin, b.Min, b.Max, props(Color3.new(1, 1, 1), M.SmoothPlastic, { Transparency = 1, CastShadow = false, CanQuery = false }))
				wall.Name = "BarrierBlock_" .. b.Upgrade
				continue
			end
			local part = Build.Box(parent, origin, b.Min, b.Max, props(Color3.fromRGB(34, 44, 78), M.Fabric))
			part.Name = "Barrier_" .. b.Upgrade
			local n = normals[b.Face] or V(0, 0, -1)
			local size = b.Max - b.Min
			local centre = (b.Min + b.Max) / 2
			local along = if math.abs(n.X) > 0 then V(0, 0, 1) else V(1, 0, 0)
			local width = if math.abs(n.X) > 0 then size.Z else size.X
			local depth = if math.abs(n.X) > 0 then size.X else size.Z
			local railPos = V(centre.X, b.Max.Y + 0.2, centre.Z) + n * (depth / 2 + 0.15)
			Build.Part(parent, origin, V(width + 0.8, 0.3, 0.3), CFrame.lookAt(railPos, railPos + along) * CFrame.Angles(0, rad(90), 0), props(AC.Bronze, M.Metal, { CanCollide = false }))
			local plaquePos = V(centre.X, 7, centre.Z) + n * (depth / 2 + 0.06)
			local plaque = Build.Part(parent, origin, V(3.6, 1.3, 0.1), CFrame.lookAt(plaquePos, plaquePos + n), props(AC.Bronze, M.Metal, { CanCollide = false }))
			Build.Label(plaque, Enum.NormalId.Front, ("Coming soon\n<b>%s</b>"):format(up.Name), Color3.fromRGB(240, 222, 180), Enum.Font.GothamMedium).RichText = true
		end
	end
end

-- ── Upgrade pads (stand on them to buy) ────────────────────────────────────
function MuseumBuilder.BuildPad(parent: Instance, origin: CFrame, up: Upgrades.UpgradeDef, costText: string): BasePart
	-- A bronze-ringed stone plinth with a softly lit green inlay. The label
	-- only shows when you're near, so a row of pads never turns into a wall
	-- of floating text.
	local at = CF(up.Pad.X, 0, up.Pad.Z)
	local ring = Build.Part(parent, origin, V(0.35, 7.2, 7.2), at * CF(0, 0.175, 0) * UP, props(AC.TrimShade, nil, { CanCollide = false, Shape = Enum.PartType.Cylinder }))
	ring.Name = "PadRing"
	local trim = Build.Part(parent, origin, V(0.4, 6.4, 6.4), at * CF(0, 0.2, 0) * UP, props(AC.Bronze, M.Metal, { CanCollide = false, Shape = Enum.PartType.Cylinder }))
	local pad = Build.Part(parent, origin, V(0.45, 5.6, 5.6), at * CF(0, 0.225, 0) * UP, props(Color3.fromRGB(86, 176, 128), M.SmoothPlastic, { Name = "Pad_" .. up.Id, Shape = Enum.PartType.Cylinder }))
	pad:SetAttribute("UpgradeId", up.Id)
	ring.Parent = pad
	trim.Parent = pad
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(140, 255, 190)
	glow.Range = 8
	glow.Brightness = 0.6
	glow.Parent = pad
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Size = UDim2.fromOffset(190, 46)
	gui.StudsOffsetWorldSpace = V(0, 3.2, 0)
	gui.MaxDistance = 34
	gui.LightInfluence = 0
	gui.Adornee = pad
	gui.Parent = pad
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(16, 21, 36)
	bg.BackgroundTransparency = 0.2
	bg.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = bg
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -12, 1, -6)
	label.Position = UDim2.fromOffset(6, 3)
	label.RichText = true
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = ("%s\n<font color=\"#E2BE6E\">%s</font>"):format(up.Name, costText)
	label.Parent = bg
	return pad
end

-- ── Display slot fixtures ──────────────────────────────────────────────────
export type Fixture = { Model: Model, PromptPart: BasePart, Anchor: CFrame, Scale: number }

function MuseumBuilder.BuildSlot(parent: Instance, origin: CFrame, slot: Upgrades.SlotDef): Fixture
	local model = Instance.new("Model")
	model.Name = "Slot_" .. slot.Id
	model:SetAttribute("SlotId", slot.Id)
	model:SetAttribute("SlotType", slot.Type)
	local frame = origin * CF(slot.X, slot.Y or 0, slot.Z) * CFrame.Angles(0, rad(slot.Face), 0)

	local promptPart: BasePart
	local anchor: CFrame
	local scale = 1

	local deco = function(color: Color3, material: Enum.Material?): Build.PartProps
		return props(color, material, { CanCollide = false })
	end
	local function plaque(cf: CFrame, w: number, h: number)
		local plate = Build.Part(model, frame, V(w + 0.16, h + 0.16, 0.06), cf * CF(0, 0, 0.02), deco(AC.Gold, M.Metal))
		plate.Name = "PlaqueFrame"
		local face = Build.Part(model, frame, V(w, h, 0.08), cf, deco(AC.Bronze, M.Metal))
		face.Name = "Plaque"
	end

	if slot.Type == "Pedestal" then
		-- Stepped marble base, navy shaft with an inset gilt frame, moulded cap.
		promptPart = Build.Part(model, frame, V(2.7, 3.2, 2.7), CF(0, 2.85, 0), props(COLORS.Pedestal))
		Build.Part(model, frame, V(3.7, 0.35, 3.7), CF(0, 1.175, 0), props(AC.TrimShade))
		Build.Part(model, frame, V(3.3, 0.35, 3.3), CF(0, 1.5, 0), props(AC.Trim))
		Build.Part(model, frame, V(3.0, 0.2, 3.0), CF(0, 4.3, 0), props(AC.Gold, M.Metal, { CanCollide = false }))
		Build.Part(model, frame, V(3.4, 0.35, 3.4), CF(0, 4.575, 0), props(AC.TrimShade))
		for _, sx in { -1, 1 } do -- vertical gilt fillets on the shaft corners
			for _, sz in { -1, 1 } do
				Build.Part(model, frame, V(0.12, 2.9, 0.12), CF(sx * 1.36, 2.85, sz * 1.36), deco(AC.Gold, M.Metal))
			end
		end
		plaque(CF(0, 3.05, -1.4), 1.9, 0.75)
		-- velvet-rope stanchions (decorative, walk-through)
		for _, c in { V(-2.7, 0, -2.7), V(2.7, 0, -2.7), V(-2.7, 0, 2.7), V(2.7, 0, 2.7) } do
			Build.Part(model, frame, V(0.6, 0.15, 0.6), CF(c.X, 1.075, c.Z), deco(AC.Bronze, M.Metal))
			Build.Part(model, frame, V(0.18, 2.2, 0.18), CF(c.X, 2.1, c.Z), deco(AC.Bronze, M.Metal))
			Build.Part(model, frame, V(0.35, 0.35, 0.35), CF(c.X, 3.25, c.Z), props(AC.Gold, M.Metal, { Shape = Enum.PartType.Ball, CanCollide = false }))
		end
		for _, r in { { V(5.4, 0.16, 0.16), CF(0, 2.75, 2.7) }, { V(0.16, 0.16, 5.4), CF(-2.7, 2.75, 0) }, { V(0.16, 0.16, 5.4), CF(2.7, 2.75, 0) } } do
			Build.Part(model, frame, r[1] :: Vector3, r[2] :: CFrame, deco(Color3.fromRGB(140, 30, 44), M.Fabric))
		end
		anchor = frame * CF(0, 4.75, 0)
	elseif slot.Type == "Case" then
		-- Walnut cabinet with raised panels, brass-cornered vitrine, crown moulding.
		promptPart = Build.Part(model, frame, V(3.4, 3, 3.4), CF(0, 2.5, 0), props(COLORS.WoodDark, M.Wood))
		Build.Part(model, frame, V(3.7, 0.35, 3.7), CF(0, 1.175, 0), deco(COLORS.Pedestal))
		for _, f in { CF(0, 2.4, -1.72), CF(0, 2.4, 1.72), CF(-1.72, 2.4, 0) * CFrame.Angles(0, math.pi / 2, 0), CF(1.72, 2.4, 0) * CFrame.Angles(0, math.pi / 2, 0) } do
			Build.Part(model, frame, V(2.6, 1.5, 0.06), f, deco(Color3.fromRGB(118, 80, 50), M.Wood))
		end
		Build.Part(model, frame, V(3.6, 0.15, 3.6), CF(0, 4.05, 0), deco(AC.Trim))
		Build.Part(model, frame, V(3, 3, 3), CF(0, 5.6, 0), props(Color3.fromRGB(205, 228, 245), M.Glass, { Transparency = 0.78, Name = "Glass" }))
		for _, c in { V(-1.52, 0, -1.52), V(1.52, 0, -1.52), V(-1.52, 0, 1.52), V(1.52, 0, 1.52) } do
			Build.Part(model, frame, V(0.16, 3.0, 0.16), CF(c.X, 5.6, c.Z), deco(AC.Bronze, M.Metal))
		end
		Build.Part(model, frame, V(3.4, 0.2, 3.4), CF(0, 7.2, 0), props(COLORS.Gold, M.Metal, { Name = "Frame" }))
		Build.Part(model, frame, V(3.0, 0.25, 3.0), CF(0, 7.42, 0), deco(COLORS.WoodDark, M.Wood))
		local caseLight = Build.Part(model, frame, V(0.3, 0.05, 0.3), CF(0, 7.05, 0), deco(Color3.fromRGB(255, 240, 220), M.SmoothPlastic))
		Build.Light(caseLight, Color3.fromRGB(255, 232, 200), 6, 0.3)
		plaque(CF(0, 3.35, -1.76), 1.7, 0.6)
		anchor = frame * CF(0, 4.12, 0)
		scale = 0.85
	elseif slot.Type == "Wall" then
		-- Navy backing in a moulded gilt frame, a brass picture light above and
		-- a plaque below.
		promptPart = Build.Part(model, frame, V(5, 4.6, 0.3), CF(0, 8, 0.35), props(COLORS.Navy, M.Fabric))
		Build.Part(model, frame, V(5.4, 0.3, 0.5), CF(0, 5.6, 0.2), props(AC.Bronze, M.Metal))
		for _, e in { { V(5.7, 0.35, 0.25), CF(0, 10.45, 0.22) }, { V(0.35, 5.05, 0.25), CF(-2.68, 8, 0.22) }, { V(0.35, 5.05, 0.25), CF(2.68, 8, 0.22) } } do
			Build.Part(model, frame, e[1] :: Vector3, e[2] :: CFrame, deco(AC.Gold, M.Metal))
		end
		Build.Part(model, frame, V(0.12, 0.12, 0.9), CF(0, 11.1, 0.05), deco(AC.Bronze, M.Metal))
		local lamp = Build.Part(model, frame, V(1.6, 0.25, 0.35), CF(0, 11.1, -0.4), deco(AC.Bronze, M.Metal))
		Build.Light(lamp, Color3.fromRGB(255, 230, 190), 7, 0.3)
		plaque(CF(0, 4.85, 0.25), 1.8, 0.6)
		anchor = frame * CF(0, 5.9, -0.1)
	elseif slot.Type == "Platform" then
		-- Two-step stone podium with brass posts and navy ropes.
		promptPart = Build.Part(model, frame, V(8, 1.2, 8), CF(0, 1.6, 0), props(AC.TrimShade))
		Build.Part(model, frame, V(7.2, 0.3, 7.2), CF(0, 2.35, 0), props(AC.Trim))
		for _, p in { V(-3.8, 0, -3.8), V(3.8, 0, -3.8), V(-3.8, 0, 3.8), V(3.8, 0, 3.8) } do
			Build.Part(model, frame, V(0.35, 2.4, 0.35), CF(p.X, 3.4, p.Z), deco(AC.Bronze, M.Metal))
			Build.Part(model, frame, V(0.45, 0.45, 0.45), CF(p.X, 4.7, p.Z), props(AC.Gold, M.Metal, { Shape = Enum.PartType.Ball, CanCollide = false }))
		end
		for _, side in { { V(0, 0, -3.8), 7.6, 0.15 }, { V(0, 0, 3.8), 7.6, 0.15 }, { V(-3.8, 0, 0), 0.15, 7.6 }, { V(3.8, 0, 0), 0.15, 7.6 } } do
			local pos = side[1] :: Vector3
			Build.Part(model, frame, V(side[2] :: number, 0.15, side[3] :: number), CF(pos.X, 4.3, pos.Z), deco(COLORS.Navy, M.Fabric))
		end
		plaque(CF(0, 1.6, -4.03), 2.2, 0.7)
		anchor = frame * CF(0, 2.5, 0)
		scale = 1.8
	else -- Vault
		promptPart = Build.Part(model, frame, V(4, 3, 4), CF(0, 2.5, 0), props(COLORS.Metal, M.DiamondPlate))
		Build.Part(model, frame, V(3.6, 4, 3.6), CF(0, 6, 0), props(Color3.fromRGB(255, 225, 205), M.Glass, { Transparency = 0.8, Name = "Glass" }))
		Build.Part(model, frame, V(4.2, 0.3, 4.2), CF(0, 8.1, 0), props(COLORS.Gold, M.Metal, { Name = "Frame" }))
		Build.Part(model, frame, V(4.2, 0.3, 4.2), CF(0, 4.05, 0), props(COLORS.Gold, M.Metal))
		for _, c in { V(-1.85, 0, -1.85), V(1.85, 0, -1.85), V(-1.85, 0, 1.85), V(1.85, 0, 1.85) } do
			Build.Part(model, frame, V(0.22, 4, 0.22), CF(c.X, 6, c.Z), deco(Color3.fromRGB(60, 62, 70), M.Metal))
		end
		plaque(CF(0, 2.6, -2.03), 2.0, 0.7)
		anchor = frame * CF(0, 4.2, 0)
		scale = 1.1
	end
	promptPart.Name = "PromptPart"
	model.PrimaryPart = promptPart
	model:SetAttribute("Anchor", anchor)
	model:SetAttribute("Scale", scale)
	model.Parent = parent
	return { Model = model, PromptPart = promptPart, Anchor = anchor, Scale = scale }
end

-- ── Upgrade geometry ───────────────────────────────────────────────────────
local Builders: { [string]: (Instance, CFrame) -> () } = {}

Builders.grand_entrance = function(f, o)
	-- Stone urn planters on the steps and a carpeted welcome.
	for _, side in { -1, 1 } do
		local x = side * 9.6
		Build.Box(f, o, V(x - 1, 0, -19.6), V(x + 1, 0.5, -17.6), props(AC.TrimShade))
		Build.Part(f, o, V(1.6, 1.6, 1.6), CF(x, 1.3, -18.6) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
		Build.Part(f, o, V(0.4, 2.2, 2.2), CF(x, 2.2, -18.6) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
		Trees.Place("Small", f, o * CF(x, 2.3, -18.6), 0.45, Random.new(5))
	end
	Build.Box(f, o, V(-2.4, 0.15, -29), V(2.4, 0.2, -23.1), props(Color3.fromRGB(150, 36, 46), M.Fabric, { CanCollide = false }))
	for i, r in { 12.6, 12.05, 11.5 } do
		local y = i * 0.33 + (if i == 3 then 0.01 else 0)
		Build.Box(f, o, V(-2.4, y, BAY_Z - r), V(2.4, y + 0.04, BAY_Z - r + 0.55), props(Color3.fromRGB(150, 36, 46), M.Fabric, { CanCollide = false }))
	end
end

Builders.hall_cases = function(f, o)
	-- The cases themselves are display slots; add small information stands beside them.
	for _, x in { -12.4, 12.4 } do
		Build.Box(f, o, V(x - 0.3, 1, 18.7), V(x + 0.3, 3.2, 19.3), props(AC.Bronze, M.Metal))
		local plaque = Build.Box(f, o, V(x - 1, 3.2, 18.9), V(x + 1, 4.6, 19.1), props(COLORS.Navy, M.SmoothPlastic, { CanCollide = false }))
		Build.Label(plaque, Enum.NormalId.Front, "Treasures of the Ancients", Color3.new(1, 1, 1))
	end
end

local function wingInterior(f: Instance, o: CFrame, x0: number, x1: number, carpet: Color3)
	Build.Box(f, o, V(x0 + 5.5, 1, 0), V(x1 - 5.5, 1.05, 20), props(carpet, M.Fabric, { CanCollide = false }))
	for _, x in { x0 + 10, x1 - 10 } do
		Build.Box(f, o, V(x - 0.35, 14.2, -4.5), V(x + 0.35, 15, 24.5), props(AC.Trim, nil, { CanCollide = false }))
	end
end

Builders.east_wing = function(f, o)
	local wall = props(AC.Wall)
	Build.Box(f, o, V(20.5, 0, -5.5), V(50.5, 1, 25.5), props(COLORS.Floor))
	Build.Wall(f, o, 20.5, -5, 50.5, -5, 1, 15, 1, wall)
	Build.Wall(f, o, 50, -4.5, 50, 24.5, 1, 15, 1, wall)
	Build.Wall(f, o, 20.5, 25, 50.5, 25, 1, 15, 1, wall, { Center = 35, Width = 10, Height = 10 })
	Build.Box(f, o, V(20.5, 15, -5.5), V(50.5, 16, 25.5), props(COLORS.Roof))
	Architecture.Dress(f, o, { X0 = 20.5, X1 = 50.5, Z0 = -5.5, Z1 = 25.5, Top = 15, Faces = { Front = true, Right = true } })
	for _, x in { 28, 35.5, 43 } do
		Architecture.Window(f, o, V(x, 7.6, -5.5), V(0, 0, -1), 3.4, 6.4, "Pediment")
	end
	for _, z in { 2.5, 10, 17.5 } do
		Architecture.Window(f, o, V(50.5, 7.6, z), V(1, 0, 0), 3.4, 6.4, "Pediment")
	end
	wingInterior(f, o, 20.5, 50.5, COLORS.Navy)
	ceilingLight(f, o, 35, 14.7, 10, 32)
	roomSign(f, o, V(19.3, 13.2, 6), V(19.5, 15.4, 14), Enum.NormalId.Left, "EAST GALLERY")
end

Builders.benches_plants = function(f, o)
	local function bench(x: number, z: number, alongZ: boolean)
		local sx, sz = if alongZ then 2 else 6, if alongZ then 6 else 2
		Build.Box(f, o, V(x - sx / 2, 2.2, z - sz / 2), V(x + sx / 2, 2.7, z + sz / 2), props(COLORS.Wood, M.Wood))
		for _, d in { -1, 1 } do
			local lx = if alongZ then x else x + d * 2.4
			local lz = if alongZ then z + d * 2.4 else z
			Build.Box(f, o, V(lx - 0.3, 1, lz - 0.3), V(lx + 0.3, 2.2, lz + 0.3), props(COLORS.Metal, M.Metal))
		end
	end
	local rng = Random.new(11)
	local function plant(x: number, z: number)
		Build.Box(f, o, V(x - 1.1, 1, z - 1.1), V(x + 1.1, 2.8, z + 1.1), props(COLORS.Pedestal))
		Build.Box(f, o, V(x - 1.25, 2.8, z - 1.25), V(x + 1.25, 3, z + 1.25), props(COLORS.Marble))
		Trees.Place("Small", f, o * CF(x, 3, z), 0.5, rng)
	end
	bench(-16.2, 27.6, false)
	bench(16.2, 27.6, false)
	bench(42, 20, false)
	plant(-17.4, -3.9)
	plant(17.4, -3.9)
	plant(-17.8, 23)
	plant(17.8, 23)
	plant(46.5, -1.5)
	plant(46.5, 22.5)
end

Builders.fossil_hall = function(f, o)
	local wall = props(AC.Wall)
	Build.Box(f, o, V(21, 0, 25.5), V(50.5, 1, 55.5), props(Color3.fromRGB(206, 192, 162)))
	Build.Wall(f, o, 21, 25.5, 21, 55, 1, 17, 1, wall)
	Build.Wall(f, o, 50, 25.5, 50, 55, 1, 17, 1, wall)
	Build.Wall(f, o, 20.5, 55, 50.5, 55, 1, 17, 1, wall)
	Build.Box(f, o, V(20.5, 15, 24.5), V(50.5, 17, 25.5), wall) -- header above the east wing roof
	Build.Box(f, o, V(20.5, 17, 24.5), V(50.5, 18, 55.5), props(COLORS.Roof))
	Architecture.Dress(f, o, { X0 = 20.5, X1 = 50.5, Z0 = 24.5, Z1 = 55.5, Top = 17, Faces = { Right = true, Back = true }, Plinth = true })
	for _, z in { 33, 41, 49 } do
		Architecture.Window(f, o, V(50.5, 8.4, z), V(1, 0, 0), 3.4, 7, "Pediment")
	end
	for _, x in { 28, 35.5, 43 } do
		Architecture.Window(f, o, V(x, 8.4, 55.5), V(0, 0, 1), 3.4, 7, "Pediment")
	end
	-- Sand pit with a big decorative skeleton
	Build.Box(f, o, V(26, 1, 46), V(46, 1.5, 52), props(AC.TrimShade))
	Build.Box(f, o, V(26.5, 1.5, 46.5), V(45.5, 1.6, 51.5), props(Color3.fromRGB(220, 195, 140), M.Sand, { CanCollide = false }))
	for i = 0, 6 do
		Build.Part(f, o, V(0.6, 0.6, 2.2 - i * 0.15), CF(28 + i * 2.6, 2.2 + math.sin(i / 6 * math.pi) * 1.5, 49), props(Color3.fromRGB(235, 225, 200), M.SmoothPlastic, { CanCollide = false }))
	end
	Build.Part(f, o, V(2.4, 2, 1.6), CF(46.5, 3.6, 49), props(Color3.fromRGB(235, 225, 200), M.SmoothPlastic, { CanCollide = false }))
	ceilingLight(f, o, 36, 16.7, 40, 36)
	roomSign(f, o, V(31, 11.4, 24.3), V(39, 13.6, 24.5), Enum.NormalId.Front, "FOSSIL HALL")
end

Builders.chandeliers = function(f, o)
	local function chandelier(x: number, y: number, z: number, ceiling: number)
		Build.Box(f, o, V(x - 0.15, y, z - 0.15), V(x + 0.15, ceiling, z + 0.15), props(COLORS.Gold, M.Metal, { CanCollide = false }))
		Build.Part(f, o, V(0.4, 6, 6), CF(x, y, z) * UP, props(COLORS.Gold, M.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			Build.Part(f, o, V(0.7, 0.7, 0.7), CF(x + math.cos(a) * 2.8, y + 0.6, z + math.sin(a) * 2.8), props(Color3.fromRGB(255, 238, 205), M.Glass, { Shape = Enum.PartType.Ball, CanCollide = false }))
		end
		local core = Build.Part(f, o, V(1.4, 1.4, 1.4), CF(x, y - 0.6, z), props(Color3.fromRGB(255, 240, 200), M.Glass, { Shape = Enum.PartType.Ball, CanCollide = false }))
		Build.Light(core, COLORS.Warm, 30, 0.85, true)
	end
	chandelier(0, 14.5, 10, 19)
	chandelier(35, 11.5, 10, 15)
	chandelier(36, 13, 40, 17)
end

Builders.security = function(f, o)
	-- The control room console. The actual cameras, locks and alarm pads are
	-- built by SecurityService from the owner's real security levels, so what
	-- you see always matches what a thief has to beat.
	-- The security terminal in the entrance hall (mirrors the ticket desk).
	local desk = Build.Box(f, o, V(-15.5, 1, -7.2), V(-11, 3.6, -4.8), props(Color3.fromRGB(52, 54, 62), M.Metal, { Name = "SecurityTerminal" }))
	desk:SetAttribute("SecurityTerminal", true)
	Build.Box(f, o, V(-15.7, 3.6, -7.4), V(-10.8, 3.85, -4.6), props(AC.Trim))
	for i, x in { -14.6, -13.25, -11.9 } do
		local screen = Build.Box(f, o, V(x - 0.6, 3.95, -6.2), V(x + 0.6, 4.85, -6.1), props(Color3.fromRGB(26, 52, 70), M.Glass, { CanCollide = false }))
		Build.Label(screen, Enum.NormalId.Front, ("CAM %d"):format(i), Color3.fromRGB(150, 220, 255), Enum.Font.Code)
	end
	local glow = Build.Box(f, o, V(-14, 4.9, -6.3), V(-12.5, 5.0, -6.0), props(Color3.fromRGB(120, 200, 255), M.SmoothPlastic, { CanCollide = false, Transparency = 1 }))
	Build.Light(glow, Color3.fromRGB(120, 190, 255), 8, 0.5)
end

Builders.west_wing = function(f, o)
	local wall = props(AC.Wall)
	Build.Box(f, o, V(-50.5, 0, -5.5), V(-20.5, 1, 25.5), props(COLORS.Floor))
	Build.Wall(f, o, -50.5, -5, -20.5, -5, 1, 15, 1, wall)
	Build.Wall(f, o, -50, -4.5, -50, 24.5, 1, 15, 1, wall)
	Build.Wall(f, o, -50.5, 25, -20.5, 25, 1, 15, 1, wall, { Center = -35, Width = 10, Height = 10 })
	Build.Box(f, o, V(-50.5, 15, -5.5), V(-20.5, 16, 25.5), props(COLORS.Roof))
	Architecture.Dress(f, o, { X0 = -50.5, X1 = -20.5, Z0 = -5.5, Z1 = 25.5, Top = 15, Faces = { Front = true, Left = true } })
	for _, x in { -28, -35.5, -43 } do
		Architecture.Window(f, o, V(x, 7.6, -5.5), V(0, 0, -1), 3.4, 6.4, "Pediment")
	end
	for _, z in { 2.5, 10, 17.5 } do
		Architecture.Window(f, o, V(-50.5, 7.6, z), V(-1, 0, 0), 3.4, 6.4, "Pediment")
	end
	wingInterior(f, o, -50.5, -20.5, COLORS.Navy)
	for _, z in { 0, 10, 20 } do
		Architecture.Pilaster(f, o, V(-49.5, 1, z), V(1, 0, 0), 1.4, 13.2)
	end
	ceilingLight(f, o, -35, 14.7, 10, 32)
	roomSign(f, o, V(-19.5, 13.2, 6), V(-19.3, 15.4, 14), Enum.NormalId.Right, "ANCIENT HISTORY")
end

Builders.grand_gallery = function(f, o)
	local wall = props(AC.Wall)
	Build.Box(f, o, V(-20.5, 0, 30.5), V(20.5, 1, 62.5), props(COLORS.Floor))
	Build.Wall(f, o, -20, 30.5, -20, 62, 1, 21, 1, wall)
	Build.Wall(f, o, 20, 30.5, 20, 62, 1, 21, 1, wall)
	Build.Wall(f, o, -20.5, 62, 20.5, 62, 1, 21, 1, wall)
	Build.Box(f, o, V(-21, 19, 29.5), V(21, 21, 30.5), wall) -- header above the hall roof
	Build.Box(f, o, V(-20.5, 21, 30.5), V(20.5, 22, 62.5), props(COLORS.Roof))
	Architecture.Dress(f, o, { X0 = -20.5, X1 = 20.5, Z0 = 30.5, Z1 = 62.5, Top = 21, Faces = { Back = true, Left = true, Right = true }, Plinth = false })
	for _, x in { -14, -7, 7, 14 } do
		Architecture.Window(f, o, V(x, 11, 62.5), V(0, 0, 1), 3.4, 8, "Pediment")
	end
	-- Skylight (soft, not glowing) and a run of interior columns
	Build.Box(f, o, V(-4, 20.6, 34), V(4, 20.9, 58), props(Color3.fromRGB(235, 238, 240), M.SmoothPlastic, { CanCollide = false }))
	for _, z in { 36, 46, 56 } do
		Architecture.Pilaster(f, o, V(-19.5, 1, z), V(1, 0, 0), 1.6, 19.2)
		Architecture.Pilaster(f, o, V(19.5, 1, z), V(-1, 0, 0), 1.6, 19.2)
	end
	Build.Box(f, o, V(-3, 1, 31), V(3, 1.05, 61), props(COLORS.Navy, M.Fabric, { CanCollide = false }))
	ceilingLight(f, o, 0, 20.5, 40, 40)
	ceilingLight(f, o, 0, 20.5, 54, 40)
	roomSign(f, o, V(-4, 13.4, 29.3), V(4, 15.6, 29.5), Enum.NormalId.Front, "GRAND GALLERY")
end

Builders.fountain_facade = function(f, o)
	local function fountain(x: number, z: number)
		local c = o * CF(x, 0, z)
		Build.Part(f, c, V(1.2, 9.4, 9.4), CF(0, 0.6, 0) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
		Build.Part(f, c, V(1.25, 8.4, 8.4), CF(0, 0.6, 0) * UP, props(AC.TrimShade, nil, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
		Build.Part(f, c, V(0.1, 8.2, 8.2), CF(0, 1.1, 0) * UP, props(Color3.fromRGB(70, 130, 170), M.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.2, CanCollide = false }))
		Build.Part(f, c, V(4, 1.2, 1.2), CF(0, 2.6, 0) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
		Build.Part(f, c, V(0.5, 4.5, 4.5), CF(0, 4.6, 0) * UP, props(AC.Trim, nil, { Shape = Enum.PartType.Cylinder }))
		Build.Part(f, c, V(0.08, 4, 4), CF(0, 4.88, 0) * UP, props(Color3.fromRGB(70, 130, 170), M.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.2, CanCollide = false }))
		local top = Build.Part(f, c, V(1.4, 0.7, 0.7), CF(0, 5.5, 0) * UP, props(AC.Gold, M.Metal, { Shape = Enum.PartType.Cylinder }))
		local water = Instance.new("ParticleEmitter")
		water.Color = ColorSequence.new(Color3.fromRGB(190, 225, 245))
		water.Size = NumberSequence.new(0.3)
		water.Transparency = NumberSequence.new(0.35)
		water.LightEmission = 0
		water.Lifetime = NumberRange.new(0.7, 0.9)
		water.Rate = 30
		water.Speed = NumberRange.new(7, 9)
		water.SpreadAngle = Vector2.new(16, 16)
		water.Acceleration = Vector3.new(0, -25, 0)
		water.EmissionDirection = Enum.NormalId.Top
		water.Parent = top
	end
	-- In the centres of the two front gardens (over the round flower beds)
	for _, spot in Grounds.FountainSpots do
		fountain(spot.X, spot.Z)
	end
	-- Gilded details on the crown and a gold band along the facade plinth
	Build.Part(f, o, V(0.35, 1.9, 1.9), CF(0, 25, -21.62) * CFrame.Angles(0, rad(90), 0), props(AC.Gold, M.Metal, { Shape = Enum.PartType.Cylinder, CanCollide = false }))
	for _, x in { -5, 5 } do
		Build.Part(f, o, V(0.9, 0.9, 0.9), CF(x, 25.65, -20.9), props(AC.Gold, M.Metal, { Shape = Enum.PartType.Ball, CanCollide = false }))
	end
	for _, side in { -1, 1 } do
		Build.Box(f, o, V(math.min(side * 12.7, side * 20.5), 1.8, -10.9), V(math.max(side * 12.7, side * 20.5), 2, -10.5), props(AC.Gold, M.Metal, { CanCollide = false }))
	end
end

Builders.treasure_vault = function(f, o)
	local wall = props(AC.Wall)
	local lining = props(Color3.fromRGB(85, 88, 96), M.DiamondPlate, { CanCollide = false })
	Build.Box(f, o, V(-50.5, 0, 25.5), V(-21, 1, 55.5), props(Color3.fromRGB(60, 60, 66), M.DiamondPlate))
	Build.Wall(f, o, -21, 25.5, -21, 55, 1, 13, 1, wall)
	Build.Wall(f, o, -50, 25.5, -50, 55, 1, 13, 1, wall)
	Build.Wall(f, o, -50.5, 55, -20.5, 55, 1, 13, 1, wall)
	Build.Box(f, o, V(-50.5, 13, 24.5), V(-20.5, 14, 55.5), props(COLORS.Roof))
	Architecture.Dress(f, o, { X0 = -50.5, X1 = -20.5, Z0 = 24.5, Z1 = 55.5, Top = 13, Faces = { Left = true, Back = true } })
	-- Steel lining inside; small barred windows outside
	Build.Box(f, o, V(-49.5, 1, 25.5), V(-49.3, 13, 54.5), lining)
	Build.Box(f, o, V(-21.7, 1, 25.5), V(-21.5, 13, 54.5), lining)
	Build.Box(f, o, V(-49.5, 1, 54.3), V(-21.5, 13, 54.5), lining)
	for _, z in { 33, 41, 49 } do
		Architecture.Window(f, o, V(-50.5, 9, z), V(-1, 0, 0), 2.2, 2.4, "Flat")
	end
	for _, x in { -44, -36, -28 } do
		Architecture.Window(f, o, V(x, 9, 55.5), V(0, 0, 1), 2.2, 2.4, "Flat")
	end
	-- The giant open vault door
	Build.Part(f, o, V(1.4, 9, 9), CF(-27.5, 5.6, 27.5) * CFrame.Angles(0, rad(-60), 0), props(Color3.fromRGB(150, 150, 160), M.Metal, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, o, V(1.6, 3, 3), CF(-27.5, 5.6, 27.5) * CFrame.Angles(0, rad(-60), 0), props(COLORS.Gold, M.Metal, { Shape = Enum.PartType.Cylinder }))
	-- Gold piles
	for i, p in { V(-46, 0, 52), V(-25, 0, 52), V(-36, 0, 53) } do
		Build.Part(f, o, V(3 + i * 0.4, 1.4, 2.6), CF(p.X, 1.6, p.Z), props(Color3.fromRGB(230, 190, 70), M.Metal, { CanCollide = false }))
	end
	local lampPart = Build.Part(f, o, V(2, 0.3, 2), CF(-36, 12.7, 40), props(Color3.fromRGB(255, 236, 210), M.SmoothPlastic, { CanCollide = false }))
	Build.Light(lampPart, Color3.fromRGB(255, 200, 140), 32, 0.9)
	roomSign(f, o, V(-39, 11.4, 24.3), V(-31, 13.6, 24.5), Enum.NormalId.Front, "TREASURE VAULT")
end

-- Builds the geometry for one upgrade into its own folder. Returns the folder.
function MuseumBuilder.BuildUpgrade(parent: Instance, origin: CFrame, upgradeId: string): Folder
	local folder = Build.Folder(parent, "Upgrade_" .. upgradeId)
	local builder = Builders[upgradeId]
	if builder then
		builder(folder, origin)
	else
		warn("[MuseumBuilder] No geometry for upgrade " .. upgradeId)
	end
	return folder
end

-- Sanity check: every upgrade must have geometry.
for _, up in Upgrades.List do
	assert(Builders[up.Id], "MuseumBuilder is missing a builder for upgrade " .. up.Id)
end

return MuseumBuilder
