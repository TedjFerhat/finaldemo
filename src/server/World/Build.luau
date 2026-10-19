--[[
	Build
	Tiny helpers for making anchored parts in code. All world geometry
	(plots, museum rooms, the ruins) is generated from code so you don't have
	to build anything by hand — and so every player's museum is identical.

	Positions are given in LOCAL space relative to an `origin` CFrame.
]]

local Build = {}

export type PartProps = {
	Name: string?,
	Color: Color3?,
	Material: Enum.Material?,
	Shape: Enum.PartType?,
	Transparency: number?,
	CanCollide: boolean?,
	CastShadow: boolean?,
	Reflectance: number?,
	CanQuery: boolean?,
}

-- Creates an anchored part of `size` at origin * localCFrame.
function Build.Part(parent: Instance, origin: CFrame, size: Vector3, localCFrame: CFrame, props: PartProps?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	local o = props or {}
	if o.Shape then
		p.Shape = o.Shape
	end
	p.Name = o.Name or "Part"
	p.Color = o.Color or Color3.fromRGB(200, 190, 170)
	p.Material = o.Material or Enum.Material.SmoothPlastic
	p.Transparency = o.Transparency or 0
	p.Reflectance = o.Reflectance or 0
	if o.CanCollide ~= nil then
		p.CanCollide = o.CanCollide
		if o.CanCollide == false then
			p.CanTouch = false -- decoration: no touch events to process
		end
	end
	if o.CanQuery ~= nil then
		p.CanQuery = o.CanQuery
	end
	if o.CastShadow ~= nil then
		p.CastShadow = o.CastShadow
	end
	p.CFrame = origin * localCFrame
	p.Parent = parent
	return p
end

-- Axis-aligned box given by its minimum and maximum corners (local space).
function Build.Box(parent: Instance, origin: CFrame, min: Vector3, max: Vector3, props: PartProps?): Part
	local size = max - min
	local center = (min + max) / 2
	return Build.Part(parent, origin, Vector3.new(math.abs(size.X), math.abs(size.Y), math.abs(size.Z)), CFrame.new(center), props)
end

-- A straight wall from (x1,z1) to (x2,z2) (must be along X or Z),
-- from height y0 to y1, with an optional doorway.
-- door = { Center = number (along the wall axis), Width = number, Height = number }
function Build.Wall(parent: Instance, origin: CFrame, x1: number, z1: number, x2: number, z2: number, y0: number, y1: number, thickness: number, props: PartProps?, door: { Center: number, Width: number, Height: number }?): { Part }
	local parts = {}
	local alongX = math.abs(z2 - z1) < 0.01
	local a1 = if alongX then math.min(x1, x2) else math.min(z1, z2)
	local a2 = if alongX then math.max(x1, x2) else math.max(z1, z2)
	local fixed = if alongX then z1 else x1
	local half = thickness / 2

	local function seg(s1: number, s2: number, h0: number, h1: number)
		if s2 - s1 < 0.05 or h1 - h0 < 0.05 then
			return
		end
		local min, max
		if alongX then
			min = Vector3.new(s1, h0, fixed - half)
			max = Vector3.new(s2, h1, fixed + half)
		else
			min = Vector3.new(fixed - half, h0, s1)
			max = Vector3.new(fixed + half, h1, s2)
		end
		table.insert(parts, Build.Box(parent, origin, min, max, props))
	end

	if door then
		local d1 = door.Center - door.Width / 2
		local d2 = door.Center + door.Width / 2
		seg(a1, d1, y0, y1)
		seg(d2, a2, y0, y1)
		seg(d1, d2, y0 + door.Height, y1)
	else
		seg(a1, a2, y0, y1)
	end
	return parts
end

-- A SurfaceGui with one big text label on a part's face.
function Build.Label(partInstance: BasePart, face: Enum.NormalId, text: string, color: Color3?, font: Enum.Font?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = partInstance
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = font or Enum.Font.Merriweather
	label.TextColor3 = color or Color3.fromRGB(255, 240, 200)
	label.Text = text
	label.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.05, 0)
	pad.PaddingRight = UDim.new(0.05, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = label
	return label
end

-- A floating label above a part (visible from a distance).
function Build.Billboard(adornee: BasePart, text: string, offsetY: number, maxDistance: number?, sizeX: number?, sizeY: number?): TextLabel
	local gui = Instance.new("BillboardGui")
	gui.Name = "Billboard"
	gui.Size = UDim2.fromScale(sizeX or 8, sizeY or 2.5)
	gui.StudsOffsetWorldSpace = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = maxDistance or 60
	gui.AlwaysOnTop = false
	gui.LightInfluence = 0
	gui.Adornee = adornee
	gui.Parent = adornee
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.RichText = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Text = text
	label.Parent = gui
	return label
end

function Build.Light(parentPart: BasePart, color: Color3, range: number, brightness: number, shadows: boolean?): PointLight
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = shadows == true
	light.Parent = parentPart
	return light
end

function Build.Folder(parent: Instance, name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

-- Seeded random so every world/plot looks the same every time.
function Build.Random(seed: number): Random
	return Random.new(seed)
end

return Build
