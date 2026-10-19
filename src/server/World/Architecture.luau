--[[
	Architecture — a small kit of neoclassical building pieces so every museum
	section shares the same details, proportions and materials:

	  Window      framed dark glazing, sill, mullions, pediment or flat hood
	  Column      round shaft with plinth, base ring, capital and abacus
	  Pilaster    flat wall column
	  Balustrade  rails + round balusters between two points
	  Dress       cornice (3 layered mouldings), parapet balustrade, plinth,
	              belt course and corner pilasters around a rectangular block

	All positions are in PLOT space (pass the plot origin CFrame).
]]

local Architecture = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local M = Enum.Material
local C = Color3.fromRGB

-- Art direction: warm ivory stone, dark bronze, deep navy, restrained gold.
-- Tones are deliberately mid-value (not near-white) so trim, shadow and
-- mouldings stay readable in daylight instead of blowing out to white.
Architecture.Colors = {
	Wall = C(214, 198, 166), -- warm ivory plaster
	Trim = C(236, 228, 208), -- carved limestone trim
	TrimShade = C(184, 168, 140), -- plinths, shadowed mouldings
	Groove = C(158, 142, 114), -- rustication joints
	Glass = C(34, 40, 52),
	Bronze = C(88, 64, 42),
	BronzeDark = C(52, 40, 30),
	Navy = C(24, 36, 66),
	Gold = C(196, 156, 72),
}
local COL = Architecture.Colors

-- Default material by colour role (stone reads as stone, not plastic).
local function materialFor(color: Color3): Enum.Material
	if color == COL.Wall then
		return M.Plaster
	elseif color == COL.Trim or color == COL.TrimShade or color == COL.Groove then
		return M.Limestone
	elseif color == COL.Bronze or color == COL.BronzeDark or color == COL.Gold then
		return M.Metal
	end
	return M.SmoothPlastic
end
Architecture.MaterialFor = materialFor

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or materialFor(color)
	p.CanCollide = collide ~= false
	p.CastShadow = true
	p.Parent = parent
	return p
end
Architecture.Part = part

local function wedge(parent: Instance, size: Vector3, cf: CFrame, color: Color3): WedgePart
	local w = Instance.new("WedgePart")
	w.Anchored = true
	w.Size = size
	w.CFrame = cf
	w.Color = color
	w.Material = materialFor(color)
	w.CanCollide = false
	w.Parent = parent
	return w
end

local UPRIGHT = CFrame.Angles(0, 0, rad(90)) -- cylinder axis X -> Y

-- A frame on a wall face: `pos` is the window centre ON the outer face,
-- `outward` the face normal. Style: "Pediment" | "Flat".
function Architecture.Window(parent: Instance, origin: CFrame, pos: Vector3, outward: Vector3, w: number, h: number, style: string?)
	local f = origin * CFrame.lookAt(pos, pos + outward) -- -Z (look) = outward
	local function at(x: number, y: number, z: number): CFrame
		return f * CF(x, y, -z)
	end
	local pane = part(parent, V(w, h, 0.2), at(0, 0, 0.1), COL.Glass, M.Glass, true)
	pane.Reflectance = 0.1
	pane.Transparency = 0.45 -- see-through: the walls have real openings behind
	-- surround
	part(parent, V(0.45, h + 0.9, 0.36), at(-(w / 2 + 0.225), 0, 0.18), COL.Trim, nil, false)
	part(parent, V(0.45, h + 0.9, 0.36), at(w / 2 + 0.225, 0, 0.18), COL.Trim, nil, false)
	part(parent, V(w + 0.9, 0.45, 0.36), at(0, h / 2 + 0.225, 0.18), COL.Trim, nil, false)
	part(parent, V(w + 0.9, 0.45, 0.36), at(0, -(h / 2 + 0.225), 0.18), COL.Trim, nil, false)
	-- glazing bars
	part(parent, V(0.16, h, 0.26), at(0, 0, 0.13), COL.Trim, nil, false)
	part(parent, V(w, 0.16, 0.26), at(0, h * 0.2, 0.13), COL.Trim, nil, false)
	-- sill with a small apron
	part(parent, V(w + 1.5, 0.32, 0.8), at(0, -(h / 2 + 0.6), 0.4), COL.Trim, nil, false)
	part(parent, V(w * 0.7, 0.5, 0.22), at(0, -(h / 2 + 1.0), 0.11), COL.TrimShade, nil, false)
	-- hood
	local top = h / 2 + 0.45
	part(parent, V(w + 1.7, 0.32, 0.7), at(0, top + 0.16, 0.35), COL.Trim, nil, false)
	if style == "Pediment" then
		local ph, pw = 1.05, w + 1.7
		wedge(parent, V(0.55, ph, pw / 2), at(-pw / 4, top + 0.32 + ph / 2, 0.3) * CFrame.Angles(0, rad(90), 0), COL.Trim)
		wedge(parent, V(0.55, ph, pw / 2), at(pw / 4, top + 0.32 + ph / 2, 0.3) * CFrame.Angles(0, rad(-90), 0), COL.Trim)
	else
		part(parent, V(0.8, 0.7, 0.45), at(0, top - 0.05, 0.28), COL.TrimShade, nil, false) -- keystone
	end
end

-- Arched window: rectangular lights below the spring line and a round head
-- above it, with a moulded archivolt and keystone. `pos` is the centre of the
-- rectangular part on the wall face; `h` is the height up to the spring line.
function Architecture.ArchWindow(parent: Instance, origin: CFrame, pos: Vector3, outward: Vector3, w: number, h: number, keystone: Color3?)
	local f = origin * CFrame.lookAt(pos, pos + outward)
	local function at(x: number, y: number, z: number): CFrame
		return f * CF(x, y, -z)
	end
	local spring = h / 2
	local rt = w / 2 + 0.5
	local AXIS = CFrame.Angles(0, rad(90), 0) -- cylinder axis along the wall normal
	-- archivolt (behind) and glazed head (in front)
	part(parent, V(0.3, rt * 2, rt * 2), at(0, spring, 0.15) * AXIS, COL.Trim, nil, false, Enum.PartType.Cylinder)
	local head = part(parent, V(0.15, w, w), at(0, spring, 0.375) * AXIS, COL.Glass, M.Glass, false, Enum.PartType.Cylinder)
	head.Reflectance = 0.12
	local glass = part(parent, V(w, h, 0.15), at(0, 0, 0.375), COL.Glass, M.Glass, true)
	glass.Reflectance = 0.12
	glass.Transparency = 0.45
	-- jambs, sill, glazing bars, keystone
	part(parent, V(0.5, h + 0.6, 0.55), at(-(w / 2 + 0.25), -0.3, 0.275), COL.Trim, nil, false)
	part(parent, V(0.5, h + 0.6, 0.55), at(w / 2 + 0.25, -0.3, 0.275), COL.Trim, nil, false)
	part(parent, V(w + 1.6, 0.35, 0.85), at(0, -(h / 2 + 0.6), 0.425), COL.Trim, nil, false)
	part(parent, V(w * 0.6, 0.5, 0.25), at(0, -(h / 2 + 1.0), 0.125), COL.TrimShade, nil, false)
	part(parent, V(0.16, h + w / 2, 0.2), at(0, w / 4, 0.5), COL.Trim, nil, false)
	part(parent, V(w, 0.16, 0.2), at(0, spring, 0.5), COL.Trim, nil, false)
	part(parent, V(w, 0.14, 0.2), at(0, spring - h * 0.45, 0.5), COL.Trim, nil, false)
	part(parent, V(0.9, 1.1, 0.6), at(0, spring + rt - 0.35, 0.3), keystone or COL.TrimShade, nil, false)
end

-- Horizontal rustication joints on a wall face (classic banded stone base).
-- `a`/`b` are the ends of the run on the face (plot space, at the wall
-- surface); joints run from y0 to y1 every `step` studs.
function Architecture.Rustication(parent: Instance, origin: CFrame, a: Vector3, b: Vector3, outward: Vector3, y0: number, y1: number, step: number?)
	local len = (b - a).Magnitude
	if len < 0.5 then
		return
	end
	local mid = (a + b) / 2
	local f = origin * CFrame.lookAt(Vector3.new(mid.X, 0, mid.Z), Vector3.new(mid.X, 0, mid.Z) + outward)
	local y = y0 + (step or 1.4)
	while y < y1 - 0.2 do
		part(parent, V(len, 0.2, 0.12), f * CF(0, y, -0.06), COL.Groove, nil, false)
		y += step or 1.4
	end
end

-- Round column standing at `base` (plot space, bottom centre).
function Architecture.Column(parent: Instance, origin: CFrame, base: Vector3, height: number, diameter: number?)
	local d = diameter or 1.7
	local o = origin * CF(base)
	part(parent, V(d + 0.8, 0.6, d + 0.8), o * CF(0, 0.3, 0), COL.TrimShade)
	part(parent, V(0.5, d + 0.45, d + 0.45), o * CF(0, 0.85, 0) * UPRIGHT, COL.Trim, nil, true, Enum.PartType.Cylinder)
	local shaftH = height - 2.3
	part(parent, V(shaftH * 0.5, d, d), o * CF(0, 1.1 + shaftH * 0.25, 0) * UPRIGHT, COL.Trim, nil, true, Enum.PartType.Cylinder)
	part(parent, V(shaftH * 0.5, d * 0.93, d * 0.93), o * CF(0, 1.1 + shaftH * 0.75, 0) * UPRIGHT, COL.Trim, nil, true, Enum.PartType.Cylinder)
	part(parent, V(0.25, d + 0.15, d + 0.15), o * CF(0, 1.1 + shaftH * 0.5, 0) * UPRIGHT, COL.TrimShade, nil, false, Enum.PartType.Cylinder) -- entasis ring
	part(parent, V(0.5, d + 0.35, d + 0.35), o * CF(0, height - 1.0, 0) * UPRIGHT, COL.Trim, nil, false, Enum.PartType.Cylinder)
	part(parent, V(d + 0.9, 0.7, d + 0.9), o * CF(0, height - 0.35, 0), COL.Trim)
end

-- Flat pilaster on a wall face (bottom centre at `base`).
function Architecture.Pilaster(parent: Instance, origin: CFrame, base: Vector3, outward: Vector3, width: number, height: number)
	local f = origin * CFrame.lookAt(base, base + outward)
	part(parent, V(width + 0.5, 1.2, 0.7), f * CF(0, 0.6, -0.35), COL.TrimShade, nil, false)
	part(parent, V(width, height - 1.9, 0.4), f * CF(0, 1.2 + (height - 1.9) / 2, -0.2), COL.Trim, nil, false)
	part(parent, V(width + 0.5, 0.7, 0.6), f * CF(0, height - 0.35, -0.3), COL.Trim, nil, false)
end

-- Balustrade from a to b (both at the parapet base height, plot space).
function Architecture.Balustrade(parent: Instance, origin: CFrame, a: Vector3, b: Vector3, height: number?, endPosts: boolean?)
	local h = height or 1.8
	local len = (b - a).Magnitude
	if len < 0.6 then
		return
	end
	local mid = (a + b) / 2
	local f = origin * CFrame.lookAt(mid, b) -- -Z runs along the rail
	part(parent, V(0.8, 0.32, len), f * CF(0, 0.16, 0), COL.TrimShade)
	part(parent, V(0.95, 0.32, len), f * CF(0, h - 0.16, 0), COL.Trim)
	local n = math.max(1, math.floor(len / 1.15))
	for i = 1, n do
		local z = -len / 2 + (i - 0.5) * len / n
		part(parent, V(h - 0.64, 0.42, 0.42), f * CF(0, h / 2, z) * UPRIGHT, COL.Trim, nil, false, Enum.PartType.Cylinder)
	end
	if endPosts ~= false then
		for _, z in { -len / 2, len / 2 } do
			part(parent, V(0.9, h + 0.15, 0.9), f * CF(0, (h + 0.15) / 2, z), COL.Trim)
		end
	end
end

type Gap = { number }
type Face = "Front" | "Back" | "Left" | "Right"
export type DressSpec = {
	X0: number, X1: number, Z0: number, Z1: number,
	Top: number, -- wall top (roof slab sits from Top to Top+1)
	Faces: { [string]: boolean }, -- which faces are exterior
	Rail: boolean?, -- parapet balustrade (default true)
	Belt: number?, -- height of a belt course between floors
	Plinth: boolean?, -- default true
	Gaps: { [string]: { Gap } }?, -- spans along a face kept clear (doors, bays)
	RailGaps: { [string]: { Gap } }?,
	Corners: boolean?, -- corner pilasters (default true)
}

-- Splits [a,b] by the gaps.
local function spans(a: number, b: number, gaps: { Gap }?): { Gap }
	local out = { { a, b } }
	local list: { Gap } = gaps or {}
	for _, g in list do
		local nextOut = {}
		for _, s in out do
			if g[2] <= s[1] or g[1] >= s[2] then
				table.insert(nextOut, s)
			else
				if g[1] > s[1] then
					table.insert(nextOut, { s[1], g[1] })
				end
				if g[2] < s[2] then
					table.insert(nextOut, { g[2], s[2] })
				end
			end
		end
		out = nextOut
	end
	return out
end

function Architecture.Dress(parent: Instance, origin: CFrame, spec: DressSpec)
	local faces = {
		Front = { Axis = "X", Fixed = spec.Z0, Out = V(0, 0, -1), A = spec.X0, B = spec.X1, Prev = "Left", Next = "Right" },
		Back = { Axis = "X", Fixed = spec.Z1, Out = V(0, 0, 1), A = spec.X0, B = spec.X1, Prev = "Left", Next = "Right" },
		Left = { Axis = "Z", Fixed = spec.X0, Out = V(-1, 0, 0), A = spec.Z0, B = spec.Z1, Prev = "Front", Next = "Back" },
		Right = { Axis = "Z", Fixed = spec.X1, Out = V(1, 0, 0), A = spec.Z0, B = spec.Z1, Prev = "Front", Next = "Back" },
	}
	local top = spec.Top
	-- Box along a face: from s1..s2 along the face, y0..y1, from `inset` inside
	-- the face to `out` outside it.
	local function band(face: any, s1: number, s2: number, y0: number, y1: number, out: number, inset: number, color: Color3, collide: boolean?)
		local min, max
		if face.Axis == "X" then
			local z0 = face.Fixed - face.Out.Z * inset
			local z1 = face.Fixed + face.Out.Z * out
			min, max = V(s1, y0, math.min(z0, z1)), V(s2, y1, math.max(z0, z1))
		else
			local x0 = face.Fixed - face.Out.X * inset
			local x1 = face.Fixed + face.Out.X * out
			min, max = V(math.min(x0, x1), y0, s1), V(math.max(x0, x1), y1, s2)
		end
		part(parent, max - min, origin * CF((min + max) / 2), color, nil, collide)
	end
	local layers = { { -0.8, -0.2, 0.5, COL.Trim }, { -0.2, 0.4, 0.9, COL.Trim }, { 0.4, 1.0, 1.2, COL.TrimShade } }
	for name, face in faces do
		if not spec.Faces[name] then
			continue
		end
		-- Cornice: wraps round corners only where the neighbour is dressed too.
		for _, L in layers do
			local out = L[3] :: number
			local s1 = face.A - (if spec.Faces[face.Prev] then out else 0)
			local s2 = face.B + (if spec.Faces[face.Next] then out else 0)
			band(face, s1, s2, top + (L[1] :: number), top + (L[2] :: number), out, 0, L[4] :: Color3, false)
		end
		local gaps = spec.Gaps and spec.Gaps[name]
		if spec.Plinth ~= false then
			for _, s in spans(face.A, face.B, gaps) do
				band(face, s[1], s[2], 0, 1.5, 0.35, 0, COL.TrimShade, true)
				band(face, s[1], s[2], 1.5, 1.8, 0.2, 0, COL.Trim, false)
			end
		end
		if spec.Belt then
			for _, s in spans(face.A, face.B, gaps) do
				band(face, s[1], s[2], spec.Belt - 0.35, spec.Belt + 0.35, 0.3, 0, COL.Trim, false)
			end
		end
		if spec.Rail ~= false then
			local y = top + 1
			for _, s in spans(face.A + 0.6, face.B - 0.6, spec.RailGaps and spec.RailGaps[name]) do
				local a = if face.Axis == "X" then V(s[1], y, face.Fixed - face.Out.Z * 0.2) else V(face.Fixed - face.Out.X * 0.2, y, s[1])
				local b = if face.Axis == "X" then V(s[2], y, face.Fixed - face.Out.Z * 0.2) else V(face.Fixed - face.Out.X * 0.2, y, s[2])
				Architecture.Balustrade(parent, origin, a, b)
			end
		end
	end
	if spec.Corners ~= false then
		local corners = {
			{ "Front", "Left", spec.X0, spec.Z0 },
			{ "Front", "Right", spec.X1, spec.Z0 },
			{ "Back", "Left", spec.X0, spec.Z1 },
			{ "Back", "Right", spec.X1, spec.Z1 },
		}
		for _, c in corners do
			if spec.Faces[c[1]] and spec.Faces[c[2]] then
				local x, z = c[3] :: number, c[4] :: number
				local sx = if x == spec.X0 then 1 else -1
				local sz = if z == spec.Z0 then 1 else -1
				-- quoin block wrapping the corner
				part(parent, V(2, top - 1.8 - 0.8, 2), origin * CF(x + sx * 0.75, 1.8 + (top - 2.6) / 2, z + sz * 0.75), COL.Trim, nil, true)
			end
		end
	end
end

return Architecture
