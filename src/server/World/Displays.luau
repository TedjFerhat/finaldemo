--[[
	Displays — presentation of an exhibit on its fixture.

	  • Plaque: the bronze plate on every fixture gets the artefact's name,
	    rarity and condition in one consistent typographic style (replaces
	    floating billboards, so labels never pile up in the air).
	  • Dressing: what the exhibit rests on and how it's lit depends on its
	    rarity, so valuable finds look valuable through presentation:
	      Common     linen cushion
	      Uncommon   green velvet
	      Rare       blue velvet + a rarity-coloured band on the plaque
	      Epic       purple velvet + band + a soft accent light
	      Legendary  crimson velvet with gold piping + band + light + halo ring
	      Mythic     black velvet with gold piping + band + brighter light + halo
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Rarities = require(Shared.Rarities)

local Displays = {}

local V = Vector3.new
local CF = CFrame.new
local C = Color3.fromRGB

local CUSHION = {
	Common = C(176, 166, 144),
	Uncommon = C(52, 104, 64),
	Rare = C(36, 64, 132),
	Epic = C(84, 44, 124),
	Legendary = C(132, 26, 38),
	Mythic = C(24, 22, 30),
}
local GOLD = C(196, 156, 72)

-- cushion footprint per fixture type (none for wall hangings / platforms)
local CUSHION_SIZE = { Pedestal = 2.5, Case = 2.3, Vault = 2.7 }

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	if shape then
		p.Shape = shape
	end
	p.Parent = parent
	return p
end

local function hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

-- Largest exhibit that fits each fixture type: Width = footprint (X/Z, studs),
-- Height = clear height above the anchor. To support a new fixture type, add
-- one line here. Wall hangings only constrain width (they are shallow).
Displays.Limits = {
	Pedestal = { Width = 2.8, Height = 4.5 },
	Case = { Width = 2.5, Height = 2.7 }, -- inside the glass (3 wide, ~3 tall)
	Vault = { Width = 3.0, Height = 3.6 },
	Platform = { Width = 6.0, Height = 7.0 },
	Wall = { Width = 4.3, Height = 4.2, WidthOnly = true },
} :: { [string]: { Width: number, Height: number, WidthOnly: boolean? } }

local REST_HEIGHT = 0.05 -- top of the cushion above the anchor

-- Seats an exhibit on its fixture: shrinks it if it would poke through the
-- glass / overhang the stand, then lifts it so its lowest point rests exactly
-- on the surface (no floating, no sinking). Safe to call on any slot type.
function Displays.Fit(model: Model, anchor: CFrame, slotType: string)
	local limit = Displays.Limits[slotType]
	if limit then
		local _, size = model:GetBoundingBox()
		local w = if limit.WidthOnly then size.X else math.max(size.X, size.Z)
		local ratio = math.min(1, limit.Width / math.max(w, 0.01), limit.Height / math.max(size.Y, 0.01))
		if ratio < 0.999 then
			model:ScaleTo(model:GetScale() * ratio)
		end
	end
	-- Rest the lowest point on the surface (cushion top for cushioned fixtures).
	local cf, size = model:GetBoundingBox()
	local bottom = cf.Position.Y - size.Y / 2
	local target = anchor.Position.Y + (if CUSHION_SIZE[slotType] then REST_HEIGHT else 0)
	local delta = target - bottom
	if math.abs(delta) > 0.01 then
		model:PivotTo(model:GetPivot() + Vector3.new(0, delta, 0))
	end
end

function Displays.Clear(fixtureModel: Model)
	local dressing = fixtureModel:FindFirstChild("Dressing")
	if dressing then
		dressing:Destroy()
	end
	local plaque = fixtureModel:FindFirstChild("Plaque")
	if plaque then
		for _, child in plaque:GetChildren() do
			if child.Name == "PlaqueGui" or child.Name == "RarityBand" then
				child:Destroy()
			end
		end
	end
end

function Displays.Dress(fixtureModel: Model, anchor: CFrame, slotType: string, rarity: string)
	local folder = Instance.new("Model")
	folder.Name = "Dressing"
	local order = Rarities.Order(rarity)
	local size = CUSHION_SIZE[slotType]
	if size then
		local cushion = part(folder, V(size, 0.22, size), anchor * CF(0, -0.06, 0), CUSHION[rarity] or CUSHION.Common, Enum.Material.Fabric)
		cushion.Name = "Cushion"
		if order >= 5 then
			for _, e in { { V(size + 0.1, 0.08, 0.1), CF(0, 0.2, size / 2) }, { V(size + 0.1, 0.08, 0.1), CF(0, 0.2, -size / 2) }, { V(0.1, 0.08, size), CF(size / 2, 0.2, 0) }, { V(0.1, 0.08, size), CF(-size / 2, 0.2, 0) } } do
				part(folder, e[1] :: Vector3, anchor * CF(0, -0.17, 0) * (e[2] :: CFrame), GOLD, Enum.Material.Metal)
			end
		end
	end
	if order >= 4 then
		local glow = part(folder, V(0.2, 0.2, 0.2), anchor * CF(0, 2.2, 0), C(255, 255, 255), Enum.Material.SmoothPlastic)
		glow.Transparency = 1
		local light = Instance.new("PointLight")
		light.Color = Rarities.Color(rarity):Lerp(C(255, 240, 220), 0.55)
		light.Range = if order >= 6 then 9 else 7
		light.Brightness = if order >= 6 then 0.5 else 0.3
		light.Shadows = false
		light.Parent = glow
	end
	if order >= 5 and slotType ~= "Wall" then
		-- a thin gilded inlay ring under the exhibit
		-- (a flush brass inlay on the cushion's surface, not a floating halo)
		part(folder, V(0.04, 2.0, 2.0), anchor * CF(0, 0.07, 0) * CFrame.Angles(0, 0, math.rad(90)), GOLD, Enum.Material.Metal, Enum.PartType.Cylinder)
	end
	folder.Parent = fixtureModel
end

-- Writes the exhibit's name onto the fixture's bronze plaque. Returns false
-- if this fixture has no plaque (the caller can fall back to a billboard).
function Displays.SetPlaque(fixtureModel: Model, name: string, rarity: string, detail: string): boolean
	local plaque = fixtureModel:FindFirstChild("Plaque")
	if not plaque or not plaque:IsA("BasePart") then
		return false
	end
	local order = Rarities.Order(rarity)
	if order >= 3 then
		local band = part(plaque, V(plaque.Size.X, 0.08, 0.02), plaque.CFrame * CF(0, plaque.Size.Y / 2 - 0.04, -plaque.Size.Z / 2 - 0.011), Rarities.Color(rarity), Enum.Material.SmoothPlastic)
		band.Name = "RarityBand"
	end
	local gui = Instance.new("SurfaceGui")
	gui.Name = "PlaqueGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 90
	gui.LightInfluence = 0.35
	gui.MaxDistance = 40
	gui.Parent = plaque
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.new(1, -10, 1, -6)
	label.Position = UDim2.fromOffset(5, 3)
	label.RichText = true
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = C(248, 232, 196)
	label.Text = ("%s\n<font color=\"%s\" size=\"14\">%s</font><font size=\"14\" color=\"#D9C9A4\"> · %s</font>"):format(name, hex(Rarities.Color(rarity):Lerp(C(255, 255, 255), 0.25)), string.upper(rarity), detail)
	label.Parent = gui
	return true
end

return Displays
