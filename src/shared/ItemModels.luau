--[[
	ItemModels
	Builds a 3D model for any item. Used by the server (museum displays) and
	the client (inventory previews, discovery pop-ups).

	By default every item gets a PLACEHOLDER model made of Roblox parts, based
	on the item's Model.Shape in ItemCatalog.

	REPLACING A PLACEHOLDER WITH A REAL MODEL (optional, any time):
	  1. In Roblox Studio create a Folder named "ItemModels" in ReplicatedStorage
	     (not managed by Rojo, so Rojo leaves it alone).
	  2. Put a Model inside it named exactly like the item Id (e.g. "coin_gold_sun").
	  3. The bottom of the model should rest at the model's pivot point.
	  That model is then used everywhere automatically.

	Every model returned:
	  • has all parts Anchored, CanCollide = false, CanTouch = false
	  • has its pivot at the BOTTOM CENTRE, facing -Z (towards the viewer)
	  • is roughly 2 studs tall at scale 1
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ItemCatalog = require(script.Parent.ItemCatalog)
local Rarities = require(script.Parent.Rarities)

local ItemModels = {}

type Ctx = { Model: Model, Color: Color3, Accent: Color3, Material: Enum.Material }

local function part(ctx: Ctx, size: Vector3, cf: CFrame, color: Color3?, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color or ctx.Color
	p.Material = material or ctx.Material
	p.Parent = ctx.Model
	return p
end

local Ball = Enum.PartType.Ball
local Cyl = Enum.PartType.Cylinder
local rad = math.rad
local V = Vector3.new
local CF = CFrame.new
local ANG = CFrame.Angles
-- Cylinders point along X. These rotations make them face the viewer / stand upright.
local FACE = ANG(0, rad(90), 0) -- disc facing -Z
local UP = ANG(0, 0, rad(90)) -- vertical tube

local Builders: { [string]: (Ctx) -> () } = {}

Builders.Coin = function(c)
	local dark = c.Color:Lerp(Color3.new(0, 0, 0), 0.3)
	part(c, V(0.18, 1.6, 1.6), CF(0, 0.8, 0) * FACE, dark, nil, Cyl) -- worn edge
	part(c, V(0.22, 1.42, 1.42), CF(0, 0.8, 0) * FACE, nil, nil, Cyl) -- face
	-- raised rim beads
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		part(c, V(0.12, 0.12, 0.1), CF(math.cos(a) * 0.62, 0.8 + math.sin(a) * 0.62, -0.13), dark)
	end
	-- raised emblem (a profile / owl / sun shape)
	part(c, V(0.5, 0.6, 0.1), CF(0, 0.85, -0.14), c.Color:Lerp(Color3.new(1, 1, 1), 0.15))
	part(c, V(0.2, 0.25, 0.1), CF(0.12, 1.2, -0.14), c.Color:Lerp(Color3.new(1, 1, 1), 0.15))
end

local function handles(c: Ctx, y: number, out: number, size: number)
	for _, x in { -out, out } do
		part(c, V(0.18, size, 0.18), CF(x, y, 0))
		part(c, V(math.abs(out) * 0.45, 0.18, 0.18), CF(x * 0.78, y + size / 2 - 0.05, 0))
		part(c, V(math.abs(out) * 0.45, 0.18, 0.18), CF(x * 0.78, y - size / 2 + 0.05, 0))
	end
end

Builders.Pot = function(c)
	part(c, V(1.6, 1.5, 1.6), CF(0, 0.8, 0), nil, nil, Ball)
	part(c, V(0.5, 0.8, 0.8), CF(0, 1.75, 0) * UP, nil, nil, Cyl)
	part(c, V(0.15, 1.0, 1.0), CF(0, 2.0, 0) * UP, nil, nil, Cyl)
	handles(c, 1.4, 0.95, 0.6)
	-- the crack
	part(c, V(0.06, 0.7, 0.05), CF(0.25, 1.0, -0.79) * CFrame.Angles(0, 0, rad(25)), Color3.fromRGB(40, 25, 20), Enum.Material.SmoothPlastic)
end

Builders.Vase = function(c)
	part(c, V(0.3, 0.8, 0.8), CF(0, 0.15, 0) * UP, nil, nil, Cyl)
	part(c, V(1.4, 1.4, 1.4), CF(0, 1.0, 0), nil, nil, Ball)
	part(c, V(0.3, 1.45, 1.45), CF(0, 1.0, 0) * UP, c.Accent, nil, Cyl)
	part(c, V(0.9, 0.55, 0.55), CF(0, 1.9, 0) * UP, nil, nil, Cyl)
	part(c, V(0.15, 0.9, 0.9), CF(0, 2.35, 0) * UP, nil, nil, Cyl)
	handles(c, 1.75, 0.6, 0.55)
end

Builders.Tablet = function(c)
	part(c, V(1.4, 1.8, 0.3), CF(0, 0.9, 0))
	for i = 0, 3 do
		part(c, V(1.0, 0.08, 0.05), CF(0, 1.4 - i * 0.3, -0.17), c.Accent, Enum.Material.SmoothPlastic)
	end
end

Builders.Scroll = function(c)
	part(c, V(2.0, 0.6, 0.6), CF(0, 0.4, 0), nil, Enum.Material.Fabric, Cyl)
	part(c, V(0.15, 0.75, 0.75), CF(-1.05, 0.4, 0), c.Accent, Enum.Material.Wood, Cyl)
	part(c, V(0.15, 0.75, 0.75), CF(1.05, 0.4, 0), c.Accent, Enum.Material.Wood, Cyl)
	part(c, V(1.6, 0.05, 0.9), CF(0, 0.12, -0.55), nil, Enum.Material.Fabric)
end

Builders.Sword = function(c)
	part(c, V(0.4, 2.4, 0.12), CF(0, 1.9, 0))
	part(c, V(1.2, 0.2, 0.3), CF(0, 0.65, 0), c.Accent)
	part(c, V(0.2, 0.55, 0.2), CF(0, 0.3, 0), Color3.fromRGB(70, 45, 30), Enum.Material.Wood)
	part(c, V(0.3, 0.3, 0.3), CF(0, 0.05, 0), c.Accent, nil, Ball)
end

Builders.Spear = function(c)
	part(c, V(1.1, 1.1, 0.25), CF(0, 1.6, 0) * ANG(0, 0, rad(45)))
	part(c, V(0.25, 1.2, 0.25), CF(0, 0.6, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Wood)
end

Builders.Shield = function(c)
	part(c, V(0.25, 2.4, 2.4), CF(0, 1.2, 0) * FACE, nil, nil, Cyl)
	part(c, V(0.3, 2.0, 2.0), CF(0, 1.2, -0.02) * FACE, c.Accent, nil, Cyl)
	part(c, V(0.6, 0.6, 0.6), CF(0, 1.2, -0.2), c.Color, nil, Ball)
end

Builders.Bust = function(c)
	part(c, V(1.0, 0.4, 1.0), CF(0, 0.2, 0))
	part(c, V(1.6, 0.8, 0.8), CF(0, 0.8, 0))
	part(c, V(0.5, 0.4, 0.5), CF(0, 1.35, 0))
	part(c, V(1.0, 1.0, 1.0), CF(0, 1.9, 0), nil, nil, Ball)
end

Builders.Owl = function(c)
	part(c, V(1.2, 1.5, 1.0), CF(0, 0.75, 0))
	part(c, V(1.1, 1.1, 1.1), CF(0, 1.8, 0), nil, nil, Ball)
	part(c, V(0.3, 0.3, 0.3), CF(-0.25, 1.9, -0.45), Color3.fromRGB(20, 20, 20), Enum.Material.Glass, Ball)
	part(c, V(0.3, 0.3, 0.3), CF(0.25, 1.9, -0.45), Color3.fromRGB(20, 20, 20), Enum.Material.Glass, Ball)
	part(c, V(0.3, 0.4, 0.3), CF(-0.35, 2.4, 0), nil, nil, nil)
	part(c, V(0.3, 0.4, 0.3), CF(0.35, 2.4, 0), nil, nil, nil)
end

Builders.Painting = function(c)
	part(c, V(3.4, 2.6, 0.2), CF(0, 1.3, 0), Color3.fromRGB(190, 145, 55), Enum.Material.Wood)
	part(c, V(3.0, 2.2, 0.1), CF(0, 1.3, -0.1), c.Color, Enum.Material.SmoothPlastic)
	part(c, V(3.0, 0.8, 0.1), CF(0, 0.6, -0.11), c.Accent, Enum.Material.SmoothPlastic)
	part(c, V(0.6, 0.6, 0.1), CF(0.8, 1.8, -0.12), Color3.fromRGB(240, 210, 120), Enum.Material.SmoothPlastic, nil)
end

Builders.Ring = function(c)
	part(c, V(0.35, 1.2, 1.2), CF(0, 0.6, 0) * FACE, nil, nil, Cyl)
	part(c, V(0.36, 0.8, 0.8), CF(0, 0.6, 0) * FACE, Color3.fromRGB(25, 25, 25), Enum.Material.SmoothPlastic, Cyl)
	part(c, V(0.45, 0.45, 0.45), CF(0, 1.25, 0), c.Color:Lerp(Color3.new(1, 1, 1), 0.3), Enum.Material.Glass, Ball)
end

Builders.Necklace = function(c)
	local beads = 9
	for i = 0, beads - 1 do
		local a = math.pi * (i / (beads - 1))
		part(c, V(0.32, 0.32, 0.32), CF(math.cos(a) * 0.9, 1.8 - math.sin(a) * 1.1, 0), nil, Enum.Material.SmoothPlastic, Ball)
	end
	part(c, V(0.5, 0.5, 0.2), CF(0, 0.45, 0) * ANG(0, 0, rad(45)), c.Accent, Enum.Material.Metal)
end

Builders.Gem = function(c)
	local g = part(c, V(1.1, 1.1, 1.1), CF(0, 0.9, 0) * ANG(rad(45), rad(35), rad(45)))
	g.Transparency = if c.Material == Enum.Material.Glass then 0.15 else 0
	local light = Instance.new("PointLight")
	light.Color = c.Color
	light.Range = 6
	light.Brightness = 1.2
	light.Parent = g
end

Builders.Mask = function(c)
	part(c, V(0.3, 1.6, 1.6), CF(0, 1.0, 0) * FACE, nil, nil, Cyl)
	part(c, V(0.35, 0.18, 0.1), CF(-0.35, 1.25, -0.17), Color3.fromRGB(15, 15, 15), Enum.Material.SmoothPlastic)
	part(c, V(0.35, 0.18, 0.1), CF(0.35, 1.25, -0.17), Color3.fromRGB(15, 15, 15), Enum.Material.SmoothPlastic)
	part(c, V(0.6, 0.12, 0.1), CF(0, 0.6, -0.17), Color3.fromRGB(15, 15, 15), Enum.Material.SmoothPlastic)
	part(c, V(0.2, 0.4, 0.25), CF(0, 0.95, -0.2))
end

Builders.Bone = function(c)
	part(c, V(2.0, 0.35, 0.35), CF(0, 0.3, 0), nil, nil, Cyl)
	for _, x in { -1.0, 1.0 } do
		part(c, V(0.45, 0.45, 0.45), CF(x, 0.3, -0.18), nil, nil, Ball)
		part(c, V(0.45, 0.45, 0.45), CF(x, 0.3, 0.18), nil, nil, Ball)
	end
end

Builders.Ammonite = function(c)
	part(c, V(0.5, 1.9, 1.9), CF(0, 0.95, 0) * FACE, nil, nil, Cyl)
	part(c, V(0.55, 1.3, 1.3), CF(0.05, 1.0, 0) * FACE, c.Color:Lerp(Color3.new(0, 0, 0), 0.15), nil, Cyl)
	part(c, V(0.6, 0.7, 0.7), CF(0.1, 1.05, 0) * FACE, c.Color:Lerp(Color3.new(0, 0, 0), 0.3), nil, Cyl)
end

Builders.Skull = function(c)
	part(c, V(1.3, 1.3, 1.3), CF(0, 0.75, 0.3), nil, nil, Ball)
	part(c, V(0.9, 0.5, 1.4), CF(0, 0.45, -0.6))
	part(c, V(0.25, 0.25, 0.1), CF(-0.3, 0.95, -0.25), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
	part(c, V(0.25, 0.25, 0.1), CF(0.3, 0.95, -0.25), Color3.fromRGB(20, 20, 20), Enum.Material.SmoothPlastic)
	for i = -2, 2 do
		part(c, V(0.1, 0.22, 0.1), CF(i * 0.16, 0.12, -1.25), Color3.fromRGB(245, 240, 225), Enum.Material.SmoothPlastic)
	end
end

Builders.Idol = function(c)
	part(c, V(1.0, 0.3, 0.8), CF(0, 0.15, 0))
	part(c, V(0.8, 1.2, 0.6), CF(0, 0.9, 0))
	part(c, V(0.9, 0.8, 0.7), CF(0, 1.9, 0))
	part(c, V(1.4, 0.25, 0.4), CF(0, 1.2, 0))
	part(c, V(0.15, 0.15, 0.1), CF(-0.2, 2.0, -0.36), Color3.fromRGB(240, 200, 70), Enum.Material.Neon)
	part(c, V(0.15, 0.15, 0.1), CF(0.2, 2.0, -0.36), Color3.fromRGB(240, 200, 70), Enum.Material.Neon)
end

Builders.Scepter = function(c)
	part(c, V(2.4, 0.22, 0.22), CF(0, 1.2, 0) * UP, nil, nil, Cyl)
	part(c, V(0.2, 0.5, 0.5), CF(0, 2.2, 0) * UP, nil, nil, Cyl)
	local orb = part(c, V(0.6, 0.6, 0.6), CF(0, 2.6, 0), c.Accent, Enum.Material.Glass, Ball)
	local light = Instance.new("PointLight")
	light.Color = c.Accent
	light.Range = 5
	light.Parent = orb
end

Builders.Crown = function(c)
	part(c, V(0.6, 1.8, 1.8), CF(0, 0.3, 0) * UP, nil, nil, Cyl)
	for i = 0, 5 do
		local a = (i / 6) * math.pi * 2
		part(c, V(0.25, 0.6, 0.25), CF(math.cos(a) * 0.8, 0.85, math.sin(a) * 0.8))
		part(c, V(0.22, 0.22, 0.22), CF(math.cos(a) * 0.8, 1.2, math.sin(a) * 0.8), c.Accent, Enum.Material.Glass, Ball)
	end
	part(c, V(0.4, 0.4, 0.4), CF(0, 0.35, -0.9), c.Accent, Enum.Material.Glass, Ball)
end

Builders.Lion = function(c)
	part(c, V(1.0, 0.8, 2.2), CF(0, 1.0, 0.2))
	for _, p in { V(-0.35, 0.3, -0.6), V(0.35, 0.3, -0.6), V(-0.35, 0.3, 1.0), V(0.35, 0.3, 1.0) } do
		part(c, V(0.3, 0.6, 0.3), CF(p))
	end
	part(c, V(1.4, 1.4, 1.4), CF(0, 1.6, -0.9), c.Color:Lerp(Color3.fromRGB(150, 80, 20), 0.3), nil, Ball)
	part(c, V(0.8, 0.7, 0.8), CF(0, 1.6, -1.4))
	part(c, V(0.15, 0.15, 1.0), CF(0, 1.3, 1.6) * ANG(rad(30), 0, 0))
end

Builders.Chest = function(c)
	part(c, V(2.2, 1.1, 1.4), CF(0, 0.55, 0), nil, Enum.Material.Wood)
	part(c, V(2.2, 1.4, 1.4), CF(0, 1.1, 0), nil, Enum.Material.Wood, Cyl)
	for _, x in { -0.8, 0, 0.8 } do
		part(c, V(0.15, 1.15, 1.45), CF(x, 0.6, 0), c.Accent, Enum.Material.Metal)
	end
	part(c, V(0.4, 0.4, 0.15), CF(0, 0.9, -0.75), c.Accent, Enum.Material.Metal)
	local gold = part(c, V(1.6, 0.3, 1.0), CF(0, 1.55, 0), Color3.fromRGB(250, 210, 80), Enum.Material.Neon)
	gold.Transparency = 0.2
end

-- ── v2: Jungle Temple artefacts ────────────────────────────────────────────
Builders.Fragments = function(c)
	for i, p in { V(-0.5, 0.15, 0), V(0.4, 0.12, 0.3), V(0.1, 0.18, -0.4), V(0.6, 0.1, -0.2) } do
		part(c, V(0.8 - i * 0.08, 0.15, 0.6), CF(p) * CFrame.Angles(rad(i * 12), rad(i * 50), rad(i * 8)))
	end
	part(c, V(0.5, 0.1, 0.12), CF(-0.5, 0.25, -0.1) * CFrame.Angles(0, rad(20), 0), c.Color:Lerp(Color3.new(0, 0, 0), 0.4))
end

Builders.ObsidianBlade = function(c)
	part(c, V(0.7, 2.2, 0.12), CF(0, 1.9, 0)) -- leaf-shaped blade
	part(c, V(0.45, 0.5, 0.12), CF(0, 3.1, 0) * CFrame.Angles(0, 0, rad(45)))
	part(c, V(0.3, 0.9, 0.3), CF(0, 0.45, 0), c.Accent, Enum.Material.Fabric) -- wrapped handle
	for i = 0, 2 do
		part(c, V(0.34, 0.08, 0.34), CF(0, 0.2 + i * 0.3, 0), Color3.fromRGB(200, 170, 110), Enum.Material.Fabric)
	end
end

Builders.BirdWhistle = function(c)
	part(c, V(1.3, 1.0, 1.0), CF(0, 0.6, 0), nil, nil, Ball)
	part(c, V(0.7, 0.7, 0.7), CF(0, 1.25, -0.45), nil, nil, Ball)
	part(c, V(0.15, 0.15, 0.4), CF(0, 1.2, -0.95), Color3.fromRGB(220, 170, 60))
	part(c, V(0.5, 0.1, 0.6), CF(0, 0.85, 0.75) * CFrame.Angles(rad(-25), 0, 0))
	part(c, V(0.6, 0.12, 0.12), CF(0, 0.75, -0.2), c.Accent) -- painted wing stripe
	part(c, V(0.6, 0.12, 0.12), CF(0, 0.55, 0.15), c.Accent)
end

Builders.RitualVessel = function(c)
	for _, a in { 0, 2.1, 4.2 } do
		part(c, V(0.25, 0.4, 0.25), CF(math.cos(a) * 0.55, 0.2, math.sin(a) * 0.55)) -- tripod feet
	end
	part(c, V(1.6, 1.3, 1.3), CF(0, 1.2, 0) * UP, nil, nil, Cyl)
	part(c, V(0.3, 1.36, 1.36), CF(0, 1.3, 0) * UP, c.Accent, nil, Cyl) -- painted band
	part(c, V(0.2, 1.6, 1.6), CF(0, 2.05, 0) * UP, nil, nil, Cyl) -- flared rim
	for i = 0, 3 do
		local a = i / 4 * math.pi * 2
		part(c, V(0.22, 0.22, 0.05), CF(math.cos(a) * 0.68, 1.3, math.sin(a) * 0.68) * CFrame.Angles(0, -a + math.pi / 2, 0), Color3.fromRGB(230, 200, 120))
	end
end

Builders.CalendarStone = function(c)
	part(c, V(0.6, 2.6, 2.6), CF(0, 1.3, 0) * FACE, nil, nil, Cyl)
	part(c, V(0.7, 1.0, 1.0), CF(0, 1.3, -0.03) * FACE, c.Accent, nil, Cyl) -- central sun
	for i = 0, 9 do
		local a = i / 10 * math.pi * 2
		part(c, V(0.3, 0.3, 0.12), CF(math.cos(a) * 0.95, 1.3 + math.sin(a) * 0.95, -0.33), c.Accent) -- day glyphs
	end
	part(c, V(1.6, 0.3, 1), CF(0, 0.15, 0), c.Color:Lerp(Color3.new(0, 0, 0), 0.25))
end

Builders.JadeJaguar = function(c)
	part(c, V(0.9, 0.8, 1.8), CF(0, 0.7, 0.1)) -- crouched body
	part(c, V(0.9, 0.8, 0.8), CF(0, 1.1, -0.85)) -- head
	part(c, V(0.25, 0.25, 0.2), CF(-0.3, 1.6, -0.85))
	part(c, V(0.25, 0.25, 0.2), CF(0.3, 1.6, -0.85))
	part(c, V(0.5, 0.25, 0.3), CF(0, 0.95, -1.3)) -- muzzle
	for _, p in { V(-0.3, 0.2, -0.6), V(0.3, 0.2, -0.6), V(-0.3, 0.2, 0.7), V(0.3, 0.2, 0.7) } do
		part(c, V(0.3, 0.4, 0.4), CF(p))
	end
	part(c, V(0.2, 0.2, 1.2), CF(0, 0.6, 1.4) * CFrame.Angles(rad(30), 0, 0))
end

Builders.MosaicMask = function(c)
	part(c, V(1.8, 2.3, 0.5), CF(0, 1.4, 0), nil, nil, Ball)
	-- mosaic tiles in alternating jade tones
	for row = 0, 4 do
		for col = 0, 3 do
			local x = -0.6 + col * 0.4
			local y = 0.6 + row * 0.4
			if math.abs(x) + math.abs(y - 1.4) < 1.15 then
				part(c, V(0.34, 0.34, 0.06), CF(x, y, -0.22), c.Color:Lerp(Color3.new(0, 0, 0), ((row + col) % 2) * 0.25))
			end
		end
	end
	for _, x in { -0.38, 0.38 } do
		part(c, V(0.4, 0.22, 0.06), CF(x, 1.65, -0.27), c.Accent, Enum.Material.SmoothPlastic) -- shell eyes
		part(c, V(0.14, 0.14, 0.06), CF(x, 1.65, -0.3), Color3.fromRGB(15, 15, 20), Enum.Material.Glass) -- obsidian pupils
	end
	part(c, V(0.25, 0.45, 0.25), CF(0, 1.3, -0.3)) -- nose
	part(c, V(0.6, 0.12, 0.06), CF(0, 0.85, -0.27), Color3.fromRGB(150, 40, 40), Enum.Material.SmoothPlastic) -- lips
end

Builders.SerpentPectoral = function(c)
	local beads = 12
	for i = 0, beads - 1 do
		local a = math.pi * 0.15 + (i / (beads - 1)) * math.pi * 1.7
		local s = 0.42 - i * 0.015
		part(c, V(s, s, s), CF(math.cos(a) * 0.9, 1.3 + math.sin(a) * 0.9, 0), nil, nil, Ball)
	end
	part(c, V(0.6, 0.45, 0.4), CF(math.cos(math.pi * 0.15) * 0.9, 1.3 + math.sin(math.pi * 0.15) * 0.9, -0.05)) -- serpent head
	part(c, V(0.7, 0.7, 0.25), CF(0, 1.3, 0) * CFrame.Angles(0, 0, rad(45)), c.Accent, Enum.Material.Glass) -- jade heart
	for _, x in { -0.5, 0.5 } do
		part(c, V(0.1, 1.0, 0.1), CF(x, 2.6, 0.05) * CFrame.Angles(0, 0, rad(x * 30)), nil) -- chain
	end
end

Builders.SunDisk = function(c)
	part(c, V(0.3, 2.4, 2.4), CF(0, 1.6, 0) * FACE, nil, nil, Cyl)
	part(c, V(0.36, 1.6, 1.6), CF(0, 1.6, -0.02) * FACE, c.Color:Lerp(Color3.new(0, 0, 0), 0.15), nil, Cyl)
	part(c, V(0.42, 0.7, 0.7), CF(0, 1.6, -0.05) * FACE, c.Accent, Enum.Material.Glass, Cyl) -- jade sun-face
	for i = 0, 11 do
		local a = i / 12 * math.pi * 2
		part(c, V(0.28, 0.75, 0.15), CF(math.cos(a) * 1.5, 1.6 + math.sin(a) * 1.5, 0) * CFrame.Angles(0, 0, a - math.pi / 2)) -- rays
	end
	part(c, V(1.2, 0.3, 0.6), CF(0, 0.15, 0), c.Color:Lerp(Color3.new(0, 0, 0), 0.3)) -- stand
end

-- ── v2: heist gadgets ──────────────────────────────────────────────────────
Builders.Lockpick = function(c)
	part(c, V(1.6, 0.2, 0.9), CF(0, 0.1, 0), Color3.fromRGB(90, 60, 40), Enum.Material.Leather)
	for i = 0, 3 do
		part(c, V(1.3, 0.06, 0.06), CF(0, 0.25, -0.3 + i * 0.2) * CFrame.Angles(0, rad(i * 4), 0))
	end
end

Builders.Cutter = function(c)
	part(c, V(0.25, 1.4, 0.25), CF(0, 0.7, 0), Color3.fromRGB(40, 40, 45))
	part(c, V(0.1, 0.5, 0.5), CF(0, 1.55, 0) * FACE, nil, nil, Cyl)
end

Builders.Jammer = function(c)
	part(c, V(1.0, 0.6, 0.7), CF(0, 0.3, 0))
	part(c, V(0.08, 1.0, 0.08), CF(0.35, 1.1, 0))
	part(c, V(0.18, 0.18, 0.05), CF(-0.25, 0.4, -0.37), c.Accent, Enum.Material.Neon)
end

local function fallback(c: Ctx)
	part(c, V(1, 1, 1), CF(0, 0.5, 0))
end

local function overrideFolder(): Instance?
	return ReplicatedStorage:FindFirstChild("ItemModels")
end

-- Returns a NEW model for the item id (never nil for valid ids).
function ItemModels.Build(itemId: string, extraScale: number?): Model
	local def = ItemCatalog.Get(itemId)
	local model: Model

	local folder = overrideFolder()
	local custom = folder and folder:FindFirstChild(itemId)
	if custom and custom:IsA("Model") then
		model = custom:Clone()
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
				d.CanTouch = false
			end
		end
	else
		model = Instance.new("Model")
		local root = Instance.new("Part")
		root.Name = "Root"
		root.Size = Vector3.new(0.2, 0.2, 0.2)
		root.Transparency = 1
		root.Anchored = true
		root.CanCollide = false
		root.CanTouch = false
		root.CanQuery = false
		root.CFrame = CFrame.new()
		root.Parent = model
		model.PrimaryPart = root

		if def then
			local ctx: Ctx = {
				Model = model,
				Color = def.Model.Color,
				Accent = def.Model.Accent or def.Model.Color:Lerp(Color3.new(1, 1, 1), 0.35),
				Material = def.Model.Material or Enum.Material.SmoothPlastic,
			}
			local builder = Builders[def.Model.Shape] or fallback
			builder(ctx)
		else
			fallback({ Model = model, Color = Color3.new(1, 0, 1), Accent = Color3.new(1, 1, 1), Material = Enum.Material.Plastic })
		end
	end

	model.Name = itemId
	local scale = ((def and def.Model.Scale) or 1) * (extraScale or 1)
	if math.abs(scale - 1) > 0.01 then
		model:ScaleTo(scale)
	end
	return model
end

-- Adds a soft light + sparkles to Epic+ items so they stand out on display.
function ItemModels.AddRarityGlow(model: Model, rarityId: string)
	local rarity = Rarities.Get(rarityId)
	if not rarity.Glow then
		return
	end
	local _, size = model:GetBoundingBox()
	local anchor = Instance.new("Part")
	anchor.Name = "Glow"
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CFrame = model:GetPivot() * CFrame.new(0, size.Y / 2, 0)
	anchor.Parent = model

	local light = Instance.new("PointLight")
	light.Color = rarity.Color
	light.Color = rarity.Color:Lerp(Color3.fromRGB(255, 236, 204), 0.5) -- tinted, not saturated
	light.Range = 7
	light.Brightness = 0.6
	light.Parent = anchor

	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Color = ColorSequence.new(rarity.Color)
	sparkle.LightEmission = 0.4
	sparkle.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) })
	sparkle.Transparency = NumberSequence.new(0.4)
	sparkle.Lifetime = NumberRange.new(0.8, 1.4)
	sparkle.Rate = if rarityId == "Mythic" then 5 elseif rarityId == "Legendary" then 3 else 2
	sparkle.Speed = NumberRange.new(0.5, 1.5)
	sparkle.SpreadAngle = Vector2.new(180, 180)
	sparkle.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparkle.Parent = anchor
end

return ItemModels
