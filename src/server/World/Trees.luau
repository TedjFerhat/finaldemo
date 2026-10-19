--[[
	Trees — reusable stylised vegetation (blocky low-poly, like the reference)

	Each kind is built ONCE as a template in ServerStorage/TreeTemplates and
	then cloned, so every tree in the game shares the same proportions.
	Templates are pivoted at the base centre. Trunks collide; foliage doesn't
	(players never get stuck in leaves).

	Kinds: Round, Tall, Small, Jungle, Pine, SnowPine, Palm, Bush, Cactus
	Custom models: put a Model named after a kind in ServerStorage/CustomTrees
	(pivot anywhere — it is re-based to its bottom centre) to replace it.
	Usage: Trees.Place("Round", parent, CFrame.new(x, groundY, z), scale, rng)
]]

local ServerStorage = game:GetService("ServerStorage")

local Trees = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad

local C = Color3.fromRGB
local TRUNK = C(122, 84, 52)
local TRUNK_DARK = C(96, 64, 40)
local LEAF = { C(76, 168, 62), C(96, 186, 72), C(62, 146, 54) }
local JUNGLE = { C(38, 122, 58), C(52, 146, 66), C(30, 102, 50) }
local PINE = { C(40, 110, 72), C(52, 128, 82) }
local SNOW = C(242, 246, 250)
local PALM = { C(88, 170, 70), C(70, 150, 60) }

local templates: Folder? = nil

local function part(model: Model, size: Vector3, cf: CFrame, color: Color3, collide: boolean, leaf: boolean?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = collide
	p.CanTouch = false
	p.CanQuery = collide
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	if leaf then
		p:SetAttribute("Leaf", true)
	end
	p.Parent = model
	return p
end

local function wedge(model: Model, size: Vector3, cf: CFrame, color: Color3)
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.CanCollide = false
	w.CanTouch = false
	w.CanQuery = false
	w.Material = Enum.Material.SmoothPlastic
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w:SetAttribute("Leaf", true)
	w.Parent = model
end

-- A faceted low-poly leaf clump: a cube turned on all three axes reads as a
-- many-sided gem shape, the classic stylised-foliage look.
local function clump(m: Model, rng: Random, pos: Vector3, size: number, color: Color3, squash: number?)
	local cf = CF(pos) * CFrame.Angles(rng:NextNumber(-0.7, 0.7), rng:NextNumber(0, math.pi), rng:NextNumber(-0.7, 0.7))
	part(m, V(size, size * (squash or 1), size), cf, color, false, true)
end

-- Tapered trunk from `from` to `to` (bottom width w0, top width w1).
local function limb(m: Model, from: Vector3, to: Vector3, w0: number, w1: number, color: Color3, collide: boolean)
	local len = (to - from).Magnitude
	local dir = (to - from).Unit
	local upHint = if math.abs(dir.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis -- avoid a degenerate lookAt
	local up = CFrame.lookAt(from, to, upHint) * CFrame.Angles(math.rad(-90), 0, 0) -- local Y along the limb
	part(m, V(w0, len * 0.55, w0), up * CF(0, len * 0.275, 0), color, collide)
	part(m, V(w1, len * 0.5, w1), up * CF(0, len * 0.75, 0), color, collide)
end

local Builders: { [string]: (Model) -> () } = {}

-- Broadleaf: flared trunk, two branches, a rounded canopy of faceted clumps.
Builders.Round = function(m)
	local rng = Random.new(101)
	part(m, V(2.6, 0.8, 2.6), CF(0, 0.4, 0) * CFrame.Angles(0, rad(45), 0), TRUNK_DARK, true)
	limb(m, V(0, 0, 0), V(0.3, 9, 0), 1.9, 1.4, TRUNK, true)
	limb(m, V(0.2, 6, 0), V(3.4, 10, 0.8), 0.9, 0.6, TRUNK, false)
	limb(m, V(0.2, 6.6, 0), V(-3, 10.4, -1), 0.9, 0.6, TRUNK, false)
	local clumps = {
		{ V(0.3, 12.2, 0), 7.4, 1 }, { V(3.4, 10.8, 1), 5.6, 2 }, { V(-3, 11, -1.2), 5.8, 3 },
		{ V(0.8, 15, -0.5), 5.2, 2 }, { V(-1.4, 11.4, 3), 5, 1 }, { V(1.8, 11.4, -3), 5, 3 }, { V(-1.6, 14.2, 1.4), 4.4, 1 },
	}
	for _, c in clumps do
		clump(m, rng, c[1] :: Vector3, c[2] :: number, LEAF[c[3] :: number])
	end
end

-- Tall poplar-style tree: slim trunk and a stacked oval crown.
Builders.Tall = function(m)
	local rng = Random.new(202)
	limb(m, V(0, 0, 0), V(0, 13, 0), 1.5, 1.0, TRUNK, true)
	for i, c in { { 8.5, 5.8 }, { 11.8, 6.4 }, { 15.2, 5.6 }, { 18.2, 4.4 }, { 20.6, 2.8 } } do
		clump(m, rng, V(rng:NextNumber(-0.5, 0.5), c[1], rng:NextNumber(-0.5, 0.5)), c[2], LEAF[(i % 3) + 1], 1.15)
	end
end

-- Compact decorative tree (gardens, planters).
Builders.Small = function(m)
	local rng = Random.new(303)
	limb(m, V(0, 0, 0), V(0.2, 5, 0), 1, 0.7, TRUNK, true)
	clump(m, rng, V(0.2, 6.2, 0), 4.4, LEAF[1])
	clump(m, rng, V(1.2, 5.6, 0.6), 3.2, LEAF[3])
	clump(m, rng, V(-0.8, 7.6, -0.4), 3.2, LEAF[2])
end

-- Big jungle tree: buttress roots, tall tapering trunk, broad layered canopy.
Builders.Jungle = function(m)
	local rng = Random.new(404)
	limb(m, V(0, 0, 0), V(0.6, 23, 0.4), 3.4, 2.2, TRUNK_DARK, true)
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		local cf = CF(math.cos(a) * 2.6, 2.4, math.sin(a) * 2.6) * CFrame.Angles(0, -a - math.pi / 2, 0) -- tall edge against the trunk
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.Size = V(0.9, 4.8, 3.2)
		w.CFrame = cf
		w.Color = TRUNK_DARK
		w.Material = Enum.Material.SmoothPlastic
		w.Parent = m
	end
	limb(m, V(0.4, 16, 0.2), V(6, 22, 3), 1.2, 0.8, TRUNK_DARK, false)
	limb(m, V(0.4, 17, 0.2), V(-5.5, 22.5, -3), 1.2, 0.8, TRUNK_DARK, false)
	local slabs = {
		{ V(0.5, 24.5, 0), V(15, 4, 13), 1 }, { V(6, 23, 3), V(10, 3.4, 9), 2 }, { V(-5.5, 23.6, -3), V(10, 3.4, 9), 3 },
		{ V(2, 27.6, -1.5), V(9, 3.2, 8), 2 }, { V(-3, 26.8, 4), V(8, 3, 7), 1 },
	}
	for _, sl in slabs do
		local cf = CF(sl[1] :: Vector3) * CFrame.Angles(rng:NextNumber(-0.12, 0.12), rng:NextNumber(0, math.pi), rng:NextNumber(-0.12, 0.12))
		part(m, sl[2] :: Vector3, cf, JUNGLE[sl[3] :: number], false, true)
	end
	for _, v in { V(-6, 0, 5), V(7, 0, 4), V(2, 0, -7), V(-4, 0, -4) } do
		part(m, V(0.3, 9, 0.3), CF(v.X, 18.5, v.Z), C(64, 128, 58), false, true)
	end
end

-- Pine: each tier is two crossed triangular "gables" (four wedges), so the
-- silhouette is a proper cone from every side.
local function pine(m: Model, snowy: boolean)
	limb(m, V(0, 0, 0), V(0, 6, 0), 1.3, 0.9, TRUNK_DARK, true)
	local tiers = { { 8.4, 4.6, 3.4 }, { 6.6, 4.2, 6.6 }, { 4.8, 3.8, 9.5 }, { 3, 3.2, 12 } }
	for i, t in tiers do
		local w, h, y = t[1], t[2], t[3]
		local color = if snowy and i == #tiers then SNOW else PINE[(i % 2) + 1]
		for _, turn in { 0, 90 } do
			local base = CF(0, y + h / 2, 0) * CFrame.Angles(0, rad(turn + i * 20), 0)
			wedge(m, V(w, h, w / 2), base * CF(-w / 4, 0, 0) * CFrame.Angles(0, rad(90), 0), color)
			wedge(m, V(w, h, w / 2), base * CF(w / 4, 0, 0) * CFrame.Angles(0, rad(-90), 0), color)
		end
		if snowy and i < #tiers then
			part(m, V(w * 0.35, 0.4, w * 0.35), CF(0, y + h * 0.55, 0) * CFrame.Angles(0, rad(45), 0), SNOW, false)
		end
	end
end
Builders.Pine = function(m)
	pine(m, false)
end
Builders.SnowPine = function(m)
	pine(m, true)
end

-- Palm: curved segmented trunk, two-part drooping fronds, coconuts.
Builders.Palm = function(m)
	local x = 0
	for i = 0, 4 do
		x = i * 0.45
		part(m, V(1.3 - i * 0.08, 3.1, 1.3 - i * 0.08), CF(x, 1.5 + i * 2.9, 0) * CFrame.Angles(0, rad(i * 18), rad(-6)), if i % 2 == 0 then TRUNK else TRUNK_DARK, true)
	end
	local top = CF(x + 0.3, 15, 0)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2 + (i % 2) * 0.15
		local base = top * CFrame.Angles(0, -a, 0)
		local color = PALM[(i % 2) + 1]
		local lift = rad(if i % 2 == 0 then 18 else 8)
		local inner = base * CFrame.Angles(0, 0, lift)
		part(m, V(4.8, 0.45, 2.6), inner * CF(2.4, 0, 0), color, false, true)
		part(m, V(5, 0.4, 2), inner * CF(4.8, 0, 0) * CFrame.Angles(0, 0, rad(-42)) * CF(2.4, 0, 0), color, false, true)
		part(m, V(2.2, 0.35, 1.2), inner * CF(4.8, 0, 0) * CFrame.Angles(0, 0, rad(-42)) * CF(4.8, 0, 0) * CFrame.Angles(0, 0, rad(-30)) * CF(1, 0, 0), color, false, true)
	end
	part(m, V(2.2, 1.6, 2.2), top * CFrame.Angles(0, rad(45), 0), PALM[2], false, true)
	for _, o in { V(0.7, -1.1, 0.6), V(-0.6, -1.1, -0.5), V(0.4, -1.2, -0.7) } do
		part(m, V(0.9, 0.9, 0.9), top * CF(o), C(110, 80, 40), false)
	end
end

-- Hedge-style shrub (plazas and gardens).
Builders.Bush = function(m)
	local rng = Random.new(505)
	clump(m, rng, V(0, 1.6, 0), 3.2, LEAF[3])
	clump(m, rng, V(1.4, 1.3, 0.6), 2.4, LEAF[1])
	clump(m, rng, V(-1.2, 1.4, -0.5), 2.6, LEAF[2])
end

-- Blocky cactus for the desert.
Builders.Cactus = function(m)
	local green = C(90, 150, 80)
	part(m, V(1.6, 7, 1.6), CF(0, 3.5, 0), green, true)
	part(m, V(2.4, 1, 1), CF(1.6, 3, 0), green, false)
	part(m, V(1, 2.6, 1), CF(2.6, 4.2, 0), green, false)
	part(m, V(2, 1, 1), CF(-1.4, 4.2, 0), green, false)
	part(m, V(1, 2, 1), CF(-2.2, 5.2, 0), green, false)
end

-- A model you import yourself (Studio › ServerStorage/CustomTrees/<Kind>)
-- replaces the built-in shape of that kind. Scripts inside it are removed.
local function customTemplate(kind: string): Model?
	local folder = ServerStorage:FindFirstChild("CustomTrees")
	local custom = folder and folder:FindFirstChild(kind)
	if not custom or not custom:IsA("Model") then
		return nil
	end
	local m = custom:Clone()
	for _, d in m:GetDescendants() do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
		end
	end
	local cf, size = m:GetBoundingBox()
	m.WorldPivot = CFrame.new(cf.Position - Vector3.new(0, size.Y / 2, 0))
	m:PivotTo(CFrame.new())
	return m
end

local function getTemplates(): Folder
	if templates then
		return templates
	end
	local folder = ServerStorage:FindFirstChild("TreeTemplates")
	if folder then
		folder:Destroy() -- rebuilt fresh each server start (no duplicates)
	end
	local f = Instance.new("Folder")
	f.Name = "TreeTemplates"
	for kind, builder in Builders do
		local m = customTemplate(kind)
		if not m then
			m = Instance.new("Model")
			builder(m)
			m.WorldPivot = CFrame.new()
		end
		m.Name = kind
		m.Parent = f
	end
	f.Parent = ServerStorage
	templates = f
	return f
end

-- Places a tree. `cf` is the base position (ground level); a random yaw is
-- added. Foliage colours vary slightly so forests don't look copy-pasted.
function Trees.Place(kind: string, parent: Instance, cf: CFrame, scale: number?, rng: Random?): Model?
	local template = getTemplates():FindFirstChild(kind)
	if not template or not template:IsA("Model") then
		warn("[Trees] Unknown tree kind: " .. tostring(kind))
		return nil
	end
	local r = rng or Random.new()
	local tree = template:Clone()
	tree:PivotTo(cf * CFrame.Angles(0, r:NextNumber(0, math.pi * 2), 0))
	local s = scale or 1
	if math.abs(s - 1) > 0.01 then
		tree:ScaleTo(s)
	end
	local tint = r:NextNumber(-0.06, 0.06)
	for _, p in tree:GetDescendants() do
		if p:IsA("BasePart") and p:GetAttribute("Leaf") then
			local h, sat, v = p.Color:ToHSV()
			p.Color = Color3.fromHSV(h, sat, math.clamp(v + tint, 0, 1))
		end
	end
	tree.Parent = parent
	return tree
end

return Trees
