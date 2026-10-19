--[[
	Grounds — the landscaped front of every museum plot (plot space; the
	museum entrance faces -Z, the plot's street curb is at z = -30).

	Layout (symmetric about x = 0):
	  • central paved path from the gate (z -30) to a stone forecourt that
	    wraps the entrance steps, with matching bronze lanterns and benches
	  • two formal parterre gardens (x ±15..±47): clipped hedge borders, gravel
	    walks, flower beds, topiary cones, a round centre bed (the Fountain
	    upgrade places its fountains here) and a bronze statue at the far end
	  • tall trees framing the front corners
	The upgrade pads live on the side lawns (x ±57) so this view stays clean.
]]

local Build = require(script.Parent.Build)
local Trees = require(script.Parent.Trees)
local Architecture = require(script.Parent.Architecture)
local AC = Architecture.Colors

local Grounds = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local M = Enum.Material
local C = Color3.fromRGB
local UP = CFrame.Angles(0, 0, rad(90))

local PAVING = C(192, 182, 160)
local GRAVEL = C(206, 194, 168)
local HEDGE = C(58, 112, 52)
local LAWN = C(92, 146, 70)
local FLOWERS = { C(196, 58, 70), C(236, 190, 70), C(240, 236, 228), C(132, 86, 168), C(226, 120, 150) }

local function props(color: Color3, material: Enum.Material?, extra: { [string]: any }?): Build.PartProps
	local p: any = { Color = color, Material = material or Architecture.MaterialFor(color) }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end
Grounds.Props = props

local function box(f: Instance, o: CFrame, a: Vector3, b: Vector3, p: Build.PartProps): BasePart
	return Build.Box(f, o, V(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z)), V(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z)), p)
end

-- Coordinated bronze lantern post (the one lamp design used everywhere).
function Grounds.Lantern(f: Instance, o: CFrame, x: number, z: number, height: number?)
	local h = height or 8.5
	local c = o * CF(x, 0, z)
	Build.Box(f, c, V(-0.75, 0, -0.75), V(0.75, 0.9, 0.75), props(AC.TrimShade))
	Build.Box(f, c, V(-0.55, 0.9, -0.55), V(0.55, 1.3, 0.55), props(AC.BronzeDark))
	Build.Part(f, c, V(h - 2.6, 0.38, 0.38), CF(0, 1.3 + (h - 2.6) / 2, 0) * UP, props(AC.BronzeDark, M.Metal, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, c, V(0.3, 0.8, 0.8), CF(0, h - 1.2, 0) * UP, props(AC.Bronze, M.Metal, { Shape = Enum.PartType.Cylinder }))
	local glass = Build.Box(f, c, V(-0.55, h - 1.05, -0.55), V(0.55, h + 0.35, 0.55), props(C(255, 222, 160), M.Glass, { Transparency = 0.2, CanCollide = false }))
	for _, s in { V(-0.55, 0, -0.55), V(0.55, 0, -0.55), V(-0.55, 0, 0.55), V(0.55, 0, 0.55) } do
		Build.Box(f, c, V(s.X - 0.08, h - 1.05, s.Z - 0.08), V(s.X + 0.08, h + 0.35, s.Z + 0.08), props(AC.BronzeDark, M.Metal, { CanCollide = false }))
	end
	Build.Box(f, c, V(-0.8, h + 0.35, -0.8), V(0.8, h + 0.6, 0.8), props(AC.BronzeDark, M.Metal, { CanCollide = false }))
	Build.Part(f, c, V(0.5, 0.5, 0.5), CF(0, h + 0.85, 0), props(AC.Gold, M.Metal, { Shape = Enum.PartType.Ball, CanCollide = false }))
	Build.Light(glass, C(255, 208, 150), 16, 0.7)
end

-- Park bench: stone feet, dark wood slats, bronze arm rests. `yaw` turns it;
-- the seat faces local -Z.
function Grounds.Bench(f: Instance, o: CFrame, x: number, z: number, yaw: number)
	local c = o * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0)
	for _, sx in { -1.9, 1.9 } do
		Build.Box(f, c, V(sx - 0.25, 0, -0.7), V(sx + 0.25, 1.5, 0.7), props(AC.TrimShade))
		Build.Box(f, c, V(sx - 0.18, 1.5, -0.6), V(sx + 0.18, 2.3, -0.4), props(AC.BronzeDark, M.Metal))
	end
	local wood = props(C(104, 70, 44), M.Wood)
	for i = 0, 2 do
		Build.Box(f, c, V(-2.3, 1.5, -0.65 + i * 0.45), V(2.3, 1.68, -0.3 + i * 0.45), wood)
	end
	for i = 0, 1 do
		Build.Box(f, c, V(-2.3, 2.0 + i * 0.55, 0.62), V(2.3, 2.35 + i * 0.55, 0.78), wood)
	end
end

-- Bronze statue (robed figure holding a gilded torch) on a stepped plinth.
function Grounds.Statue(f: Instance, o: CFrame, x: number, z: number, yaw: number)
	local c = o * CF(x, 0, z) * CFrame.Angles(0, rad(yaw), 0)
	Build.Box(f, c, V(-1.6, 0, -1.6), V(1.6, 0.6, 1.6), props(AC.TrimShade))
	Build.Box(f, c, V(-1.25, 0.6, -1.25), V(1.25, 3.4, 1.25), props(AC.Trim))
	Build.Box(f, c, V(-1.45, 3.4, -1.45), V(1.45, 3.8, 1.45), props(AC.TrimShade))
	Build.Box(f, c, V(-0.6, 1.4, -1.27), V(0.6, 2.2, -1.25), props(AC.Bronze, M.Metal, { CanCollide = false })) -- plaque
	local bronze = props(C(70, 82, 70), M.Metal) -- weathered bronze patina
	Build.Part(f, c, V(3.2, 1.5, 1.5), CF(0, 5.4, 0) * UP, props(bronze.Color :: Color3, M.Metal, { Shape = Enum.PartType.Cylinder })) -- robe
	Build.Part(f, c, V(0.6, 1.9, 1.9), CF(0, 4.05, 0) * UP, props(bronze.Color :: Color3, M.Metal, { Shape = Enum.PartType.Cylinder })) -- hem
	Build.Box(f, c, V(-0.85, 6.6, -0.5), V(0.85, 8.2, 0.5), bronze) -- torso
	Build.Part(f, c, V(0.95, 0.95, 0.95), CF(0, 8.75, 0), props(bronze.Color :: Color3, M.Metal, { Shape = Enum.PartType.Ball }))
	Build.Box(f, c, V(-1.25, 6.4, -0.3), V(-0.85, 8, 0.3), bronze) -- lowered arm
	Build.Part(f, c, V(0.4, 2.3, 0.4), CF(1.05, 9.0, 0) * CFrame.Angles(0, 0, rad(-12)), bronze) -- raised arm
	Build.Part(f, c, V(0.3, 1.1, 0.3), CF(1.3, 10.6, 0), props(AC.BronzeDark, M.Metal))
	local flame = Build.Part(f, c, V(0.55, 0.8, 0.55), CF(1.3, 11.4, 0) * CFrame.Angles(0, rad(45), 0), props(AC.Gold, M.Metal))
	Build.Light(flame, C(255, 210, 140), 10, 0.5)
end

local function flowerRow(f: Instance, o: CFrame, x0: number, x1: number, z: number, y: number, colors: { Color3 })
	local n = math.max(2, math.floor(math.abs(x1 - x0) / 1.1))
	for i = 0, n - 1 do
		local x = x0 + (x1 - x0) * (i + 0.5) / n
		Build.Box(f, o, V(x - 0.38, y, z - 0.38), V(x + 0.38, y + 0.5, z + 0.38), props(HEDGE, M.Grass, { CanCollide = false, CastShadow = false }))
		Build.Part(f, o, V(0.5, 0.5, 0.5), CF(x, y + 0.65, z) * CFrame.Angles(0.5, i * 0.7, 0.4), props(colors[(i % #colors) + 1], M.SmoothPlastic, { CanCollide = false, CastShadow = false }))
	end
end

-- One formal parterre garden. `side` = -1 (left) or 1 (right).
local function parterre(f: Instance, o: CFrame, side: number, rng: Random)
	local s = side
	local xi, xo = 15 * s, 47 * s -- inner (path side) and outer edge
	local z0, z1, zc = -29, -13.5, -21.25
	-- gravel ground
	box(f, o, V(xi, 0, z0), V(xo, 0.08, z1), props(GRAVEL, M.Pebble, { CastShadow = false }))
	-- clipped hedge border (entrance gap on the path side)
	local hedge = props(HEDGE, M.Grass)
	box(f, o, V(xi, 0, z0), V(xo, 1, z0 + 0.9), hedge)
	box(f, o, V(xi, 0, z1 - 0.9), V(xo, 1, z1), hedge)
	box(f, o, V(xo - 0.9 * s, 0, z0), V(xo, 1, z1), hedge)
	box(f, o, V(xi, 0, z0), V(xi + 0.9 * s, 1, zc - 1.6), hedge)
	box(f, o, V(xi, 0, zc + 1.6), V(xi + 0.9 * s, 1, z1), hedge)
	-- four lawn beds edged with flowers around a gravel cross
	local beds = {
		{ 16.6, 27, -27.6, -24 }, { 35, 42, -27.6, -24 },
		{ 16.6, 27, -18.5, -14.9 }, { 35, 42, -18.5, -14.9 },
	}
	for _, b in beds do
		local a, c = b[1] * s, b[2] * s
		box(f, o, V(a, 0, b[3]), V(c, 0.32, b[4]), props(LAWN, M.Grass, { CastShadow = false }))
		box(f, o, V(a, 0.32, b[3]), V(c, 0.62, b[3] + 0.5), hedge)
		box(f, o, V(a, 0.32, b[4] - 0.5), V(c, 0.62, b[4]), hedge)
		local midZ = (b[3] + b[4]) / 2
		-- each bed keeps to one coordinated pair (crimson/ivory or gold/violet)
		local pair = if (b[1] < 30) == (b[3] < -20) then { FLOWERS[1], FLOWERS[3] } else { FLOWERS[2], FLOWERS[4] }
		flowerRow(f, o, a + 0.8 * s, c - 0.8 * s, midZ - 0.9, 0.32, pair)
		flowerRow(f, o, a + 0.8 * s, c - 0.8 * s, midZ + 0.9, 0.32, pair)
	end
	-- topiary cones at the bed corners nearest the cross
	for _, p in { V(27.6, 0, -23.4), V(34.4, 0, -23.4), V(27.6, 0, -19.1), V(34.4, 0, -19.1) } do
		Build.Box(f, o, V(p.X * s - 0.7, 0, p.Z - 0.7), V(p.X * s + 0.7, 0.9, p.Z + 0.7), props(AC.TrimShade))
		Trees.Place("Pine", f, o * CF(p.X * s, 0.9, p.Z), 0.3, rng)
	end
	-- round centre bed (the Fountain upgrade builds its fountain over this)
	local cx = 31 * s
	Build.Part(f, o, V(0.4, 5.4, 5.4), CF(cx, 0.2, zc) * UP, props(AC.TrimShade, nil, { Shape = Enum.PartType.Cylinder }))
	Build.Part(f, o, V(0.42, 4.8, 4.8), CF(cx, 0.22, zc) * UP, props(LAWN, M.Grass, { Shape = Enum.PartType.Cylinder, CastShadow = false }))
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		Build.Part(f, o, V(0.6, 0.6, 0.6), CF(cx + math.cos(a) * 1.6, 0.75, zc + math.sin(a) * 1.6), props(FLOWERS[(i % #FLOWERS) + 1], M.SmoothPlastic, { Shape = Enum.PartType.Ball, CanCollide = false }))
	end
	-- statue terminating the garden's long axis, facing the path
	Grounds.Statue(f, o, 44.6 * s, zc, if s > 0 then 90 else -90)
end

function Grounds.Build(f: Instance, o: CFrame)
	local rng = Random.new(21)
	local paving = props(PAVING, M.Pavement)
	local kerb = props(AC.TrimShade)
	-- Forecourt round the steps and the central path to the gate
	box(f, o, V(-13, 0, -24.5), V(13, 0.15, -11), paving)
	box(f, o, V(-4, 0, -30), V(4, 0.15, -24.5), paving)
	box(f, o, V(-13.4, 0, -24.9), V(-4, 0.28, -24.5), kerb)
	box(f, o, V(4, 0, -24.9), V(13.4, 0.28, -24.5), kerb)
	box(f, o, V(-13.4, 0, -24.9), V(-13, 0.28, -11), kerb)
	box(f, o, V(13, 0, -24.9), V(13.4, 0.28, -11), kerb)
	box(f, o, V(-4.4, 0, -30), V(-4, 0.28, -24.9), kerb)
	box(f, o, V(4, 0, -30), V(4.4, 0.28, -24.9), kerb)
	-- (The forecourt is deliberately left open: no benches, lamps or planters
	-- crowd the entrance; the gardens and gate piers frame it from further out.)
	parterre(f, o, -1, rng)
	parterre(f, o, 1, rng)
	-- Framing trees at the front corners and a hedge line along the curb
	for _, s in { -1, 1 } do
		Trees.Place("Tall", f, o * CF(61 * s, 0, -27), 1.1, rng) -- clear of the heist getaway cart (x ±56, z -22)
		Trees.Place("Round", f, o * CF(61 * s, 0, -12), 1, rng)
		Trees.Place("Bush", f, o * CF(51 * s, 0, -27.5), 1, rng)
		Trees.Place("Bush", f, o * CF(51 * s, 0, -15.5), 0.9, rng)
	end
end

-- The two parterre centres (used by the Fountain upgrade).
Grounds.FountainSpots = { V(-31, 0, -21.25), V(31, 0, -21.25) }

return Grounds
