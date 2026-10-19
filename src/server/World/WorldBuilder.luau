--[[
	WorldBuilder
	Generates the whole map when the server starts:
	  • the main island with the central plaza, roads and 8 museum plots
	  • the Forgotten Ruins exploration zone (far away, its own island)
	  • portals, signs, the museum directory board, lighting atmosphere

	Everything is created under Workspace/World and Workspace/Plots, so you can
	look at it in the Explorer while play-testing.
]]

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Build = require(script.Parent.Build)
local Trees = require(script.Parent.Trees)

local WorldBuilder = {}

local V = Vector3.new
local CF = CFrame.new
local rad = math.rad
local UP = CFrame.Angles(0, 0, rad(90))
local M = Enum.Material

WorldBuilder.RuinsOrigin = CF(0, 0, 1000)
WorldBuilder.JungleOrigin = CF(0, 0, 2000)
WorldBuilder.JailCFrame = CF(-150, 3, 0)

local RuinsBuilder = require(script.Parent.RuinsBuilder)
local JungleBuilder = require(script.Parent.JungleBuilder)

local function P(color: Color3, material: Enum.Material?, extra: { [string]: any }?): Build.PartProps
	local p: any = { Color = color, Material = material or M.SmoothPlastic }
	if extra then
		for k, v in extra do
			p[k] = v
		end
	end
	return p
end

local C = Color3.fromRGB

local RUIN = C(196, 180, 150)
local RUIN_DARK = C(150, 135, 110)
local GOLD = C(214, 172, 60)

-- Invisible walls so players can't walk off the edge of an island.
local function boundary(parent: Instance, origin: CFrame, halfX: number, halfZ: number, height: number)
	local props = P(C(255, 255, 255), M.SmoothPlastic, { Transparency = 1, CastShadow = false })
	Build.Box(parent, origin, V(-halfX - 2, 0, -halfZ - 2), V(halfX + 2, height, -halfZ), props)
	Build.Box(parent, origin, V(-halfX - 2, 0, halfZ), V(halfX + 2, height, halfZ + 2), props)
	Build.Box(parent, origin, V(-halfX - 2, 0, -halfZ), V(-halfX, height, halfZ), props)
	Build.Box(parent, origin, V(halfX, 0, -halfZ), V(halfX + 2, height, halfZ), props)
end

local function tree(parent: Instance, origin: CFrame, x: number, z: number, rng: Random)
	local r = rng:NextNumber()
	local kind = if r < 0.5 then "Round" elseif r < 0.8 then "Tall" else "Pine"
	Trees.Place(kind, parent, origin * CF(x, 0, z), rng:NextNumber(0.9, 1.25), rng)
end

local function lampPost(parent: Instance, origin: CFrame, x: number, z: number)
	Build.Box(parent, origin, V(x - 0.4, 0, z - 0.4), V(x + 0.4, 10, z + 0.4), P(C(40, 40, 45), M.Metal))
	local bulb = Build.Box(parent, origin, V(x - 0.7, 10, z - 0.7), V(x + 0.7, 11.6, z + 0.7), P(C(255, 226, 170), M.Glass, { Transparency = 0.15 }))
	Build.Box(parent, origin, V(x - 0.9, 11.6, z - 0.9), V(x + 0.9, 11.9, z + 0.9), P(C(40, 40, 45), M.Metal))
	Build.Light(bulb, C(255, 214, 160), 18, 0.6)
end

-- ── Plots ───────────────────────────────────────────────────────────────────
-- Returns the plot-origin CFrame for plot i (1..8). Entrances face the plaza.
function WorldBuilder.PlotOrigin(i: number): CFrame
	local xs = { -225, -75, 75, 225 }
	local col = ((i - 1) % 4) + 1
	if i <= 4 then
		return CF(xs[col], 0, 110)
	else
		return CF(xs[col], 0, -110) * CFrame.Angles(0, math.pi, 0)
	end
end

local function buildPlots(): Folder
	local plots = Build.Folder(workspace, "Plots")
	for i = 1, Config.PlotCount do
		local origin = WorldBuilder.PlotOrigin(i)
		local model = Instance.new("Model")
		model.Name = "Plot_" .. i
		model:SetAttribute("PlotIndex", i)
		model:SetAttribute("Origin", origin)
		model:SetAttribute("OwnerUserId", 0)

		local ground = Build.Box(model, origin, V(-65, -0.5, -30), V(65, 0.1, 80), P(C(96, 150, 78), M.Grass, { Name = "Ground" }))
		model.PrimaryPart = ground
		-- Curb around the plot
		local curb = P(C(205, 195, 175), M.Concrete)
		Build.Box(model, origin, V(-65, 0, 79), V(65, 0.8, 80), curb)
		Build.Box(model, origin, V(-65, 0, -30), V(-64, 0.8, 80), curb)
		Build.Box(model, origin, V(64, 0, -30), V(65, 0.8, 80), curb)
		Build.Box(model, origin, V(-65, 0, -30), V(-6, 0.8, -29), curb)
		Build.Box(model, origin, V(6, 0, -30), V(65, 0.8, -29), curb)

		-- Gate piers at the plot entrance (limestone, bronze lanterns); the
		-- owner's name is on a bronze-framed navy plaque on the left pier.
		local stone = P(C(236, 228, 208), M.Limestone)
		local shade = P(C(184, 168, 140), M.Limestone)
		for _, x in { -7.4, 7.4 } do
			Build.Box(model, origin, V(x - 1.5, 0, -30.9), V(x + 1.5, 0.8, -27.9), shade)
			Build.Box(model, origin, V(x - 1.2, 0.8, -30.6), V(x + 1.2, 5.6, -28.2), stone)
			Build.Box(model, origin, V(x - 1.45, 5.6, -30.85), V(x + 1.45, 6.1, -27.95), shade)
			Build.Box(model, origin, V(x - 0.5, 6.1, -29.9), V(x + 0.5, 6.4, -28.9), P(C(52, 40, 30), M.Metal))
			local glass = Build.Box(model, origin, V(x - 0.42, 6.4, -29.82), V(x + 0.42, 7.6, -28.98), P(C(255, 222, 160), M.Glass, { Transparency = 0.2 }))
			Build.Box(model, origin, V(x - 0.6, 7.6, -30), V(x + 0.6, 7.85, -28.8), P(C(52, 40, 30), M.Metal))
			Build.Light(glass, C(255, 208, 150), 14, 0.6)
		end
		Build.Box(model, origin, V(-8.6, 1.9, -30.68), V(-6.2, 4.5, -30.6), P(C(196, 156, 72), M.Metal))
		local signPart = Build.Box(model, origin, V(-8.45, 2.05, -30.75), V(-6.35, 4.35, -30.68), P(C(24, 36, 66), M.SmoothPlastic, { Name = "OwnerSign" }))
		local label = Build.Label(signPart, Enum.NormalId.Front, "Plot available", C(240, 226, 190), Enum.Font.GothamBold)
		label.Name = "OwnerText"

		local museum = Build.Folder(model, "Museum")
		local _ = museum
		model.Parent = plots
	end
	return plots
end

-- ── Hub (plaza, roads, portal, directory board) ────────────────────────────
local function buildHub(world: Folder)
	local hub = Build.Folder(world, "Hub")
	local o = CFrame.new()
	local rng = Build.Random(7)

	Build.Box(hub, o, V(-340, -4, -215), V(340, 0, 215), P(C(110, 160, 88), M.Grass, { Name = "IslandGround" }))
	boundary(hub, o, 340, 215, 80)

	local road = P(C(170, 160, 145), M.Pavement)
	Build.Box(hub, o, V(-300, 0, 62), V(300, 0.12, 78), road)
	Build.Box(hub, o, V(-300, 0, -78), V(300, 0.12, -62), road)
	Build.Box(hub, o, V(-8, 0, -62), V(8, 0.12, 62), road)
	Build.Part(hub, o, V(0.3, 92, 92), CF(0, 0.12, 0) * UP, P(C(225, 214, 190), M.Cobblestone, { Shape = Enum.PartType.Cylinder, Name = "Plaza" }))
	Build.Part(hub, o, V(0.35, 30, 30), CF(0, 0.14, 0) * UP, P(C(200, 170, 110), M.Marble, { Shape = Enum.PartType.Cylinder }))

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "HubSpawn"
	spawn.Anchored = true
	spawn.Neutral = true
	spawn.Size = V(8, 1, 8)
	spawn.CFrame = CF(0, 0.5, -20)
	spawn.Material = M.Marble
	spawn.Color = C(230, 220, 200)
	spawn.Duration = 0
	spawn.Parent = hub

	-- Central statue
	Build.Box(hub, o, V(-3, 0, -3), V(3, 4, 3), P(C(230, 225, 215), M.Marble))
	local orb = Build.Part(hub, o, V(4, 4, 4), CF(0, 6.5, 0), P(GOLD, M.Metal, { Shape = Enum.PartType.Ball }))
	Build.Light(orb, C(255, 214, 160), 30, 1)

	-- Expedition portal (east side of the plaza)
	local portalFolder = Build.Folder(hub, "Portal")
	local pf = CF(40, 0, 0) * CFrame.Angles(0, rad(90), 0) -- faces the plaza centre (-X)
	Build.Part(portalFolder, pf, V(3, 16, 3), CF(-7, 8, 0), P(RUIN, M.Sandstone))
	Build.Part(portalFolder, pf, V(3, 16, 3), CF(7, 8, 0), P(RUIN, M.Sandstone))
	Build.Part(portalFolder, pf, V(18, 3, 3.4), CF(0, 17, 0), P(RUIN_DARK, M.Sandstone))
	local swirl = Build.Part(portalFolder, pf, V(11, 14, 0.6), CF(0, 8, 0), P(C(90, 200, 255), M.Neon, { Transparency = 0.35, CanCollide = false, Name = "RuinsPortal" }))
	swirl:SetAttribute("ZoneId", "ForgottenRuins")
	Build.Light(swirl, C(90, 200, 255), 24, 2)
	local portalSign = Build.Part(portalFolder, pf, V(14, 2.4, 0.4), CF(0, 21, -0.2), P(C(28, 44, 82)))
	Build.Label(portalSign, Enum.NormalId.Front, "EXPEDITION: FORGOTTEN RUINS", GOLD)

	-- Jungle Temple portal (east side, south of the ruins portal)
	local jf = CF(40, 0, 30) * CFrame.Angles(0, rad(90), 0)
	Build.Part(portalFolder, jf, V(3, 16, 3), CF(-7, 8, 0), P(C(110, 118, 100), M.Slate))
	Build.Part(portalFolder, jf, V(3, 16, 3), CF(7, 8, 0), P(C(110, 118, 100), M.Slate))
	Build.Part(portalFolder, jf, V(18, 3, 3.4), CF(0, 17, 0), P(C(80, 90, 74), M.Slate))
	Build.Part(portalFolder, jf, V(18.4, 0.5, 3.8), CF(0, 18.6, 0), P(C(70, 110, 60), M.Grass))
	local jswirl = Build.Part(portalFolder, jf, V(11, 14, 0.6), CF(0, 8, 0), P(C(80, 220, 130), M.Neon, { Transparency = 0.35, CanCollide = false, Name = "JunglePortal" }))
	jswirl:SetAttribute("ZoneId", "JungleTemple")
	Build.Light(jswirl, C(80, 220, 130), 24, 2)
	local jsign = Build.Part(portalFolder, jf, V(14, 2.4, 0.4), CF(0, 21, -0.2), P(C(28, 44, 82)))
	Build.Label(jsign, Enum.NormalId.Front, "EXPEDITION: JUNGLE TEMPLE (LEVEL 3)", GOLD)

	-- Jail (thieves who get caught wait here)
	local jail = Build.Folder(hub, "Jail")
	local jo = CF(-150, 0, 0)
	Build.Box(jail, jo, V(-12, 0, -12), V(12, 1, 12), P(C(90, 90, 95), M.Concrete))
	Build.Box(jail, jo, V(-12, 13, -12), V(12, 14, 12), P(C(70, 70, 75), M.Concrete))
	Build.Wall(jail, jo, -12, 12, 12, 12, 1, 13, 1, P(C(120, 120, 125), M.Brick))
	Build.Wall(jail, jo, -12, -11.5, -12, 11.5, 1, 13, 1, P(C(120, 120, 125), M.Brick))
	Build.Wall(jail, jo, 12, -11.5, 12, 11.5, 1, 13, 1, P(C(120, 120, 125), M.Brick))
	for x = -11, 11, 2 do
		Build.Box(jail, jo, V(x - 0.2, 1, -12.2), V(x + 0.2, 13, -11.8), P(C(50, 50, 55), M.Metal))
	end
	Build.Box(jail, jo, V(-12, 6.6, -12.3), V(12, 7.2, -11.7), P(C(50, 50, 55), M.Metal))
	local jailSign = Build.Box(jail, jo, V(-7, 14.2, -12.6), V(7, 17.4, -12.2), P(C(40, 40, 45), M.SmoothPlastic))
	Build.Label(jailSign, Enum.NormalId.Front, "MUSEUM SECURITY HOLDING CELL", C(255, 120, 100))
	local cellLight = Build.Part(jail, jo, V(2, 0.3, 2), CF(0, 12.7, 0), P(C(255, 240, 220), M.Neon, { CanCollide = false }))
	Build.Light(cellLight, C(255, 240, 220), 20, 1)

	-- Museum directory board (west side of the plaza) — filled in by HubService
	local bf = CF(-40, 0, 0) * CFrame.Angles(0, rad(-90), 0) -- faces +X
	Build.Part(hub, bf, V(1, 12, 1), CF(-9, 6, 0.5), P(C(60, 45, 35), M.Wood))
	Build.Part(hub, bf, V(1, 12, 1), CF(9, 6, 0.5), P(C(60, 45, 35), M.Wood))
	local board = Build.Part(hub, bf, V(18, 11, 0.5), CF(0, 9, 0), P(C(24, 32, 52), M.SmoothPlastic, { Name = "DirectoryBoard" }))
	local gui = Instance.new("SurfaceGui")
	gui.Name = "DirectoryGui"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 30
	gui.LightInfluence = 0.2
	gui.Parent = board
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.RichText = true
	text.TextScaled = true
	text.Font = Enum.Font.Merriweather
	text.TextColor3 = C(255, 240, 200)
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Text = "MUSEUM DIRECTORY"
	text.Parent = gui
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0.04, 0)
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.PaddingBottom = UDim.new(0.04, 0)
	pad.Parent = text

	-- Decoration: lamps along the roads, trees around the edge
	for x = -280, 280, 70 do
		lampPost(hub, o, x, 80.5)
		lampPost(hub, o, x, -80.5)
	end
	for _, pos in { V(-30, 0, -30), V(30, 0, -30), V(-30, 0, 30), V(30, 0, 30) } do
		lampPost(hub, o, pos.X, pos.Z)
	end
	for _ = 1, 40 do
		local x = rng:NextNumber(-320, 320)
		local z = if rng:NextNumber() < 0.5 then rng:NextNumber(-208, -196) else rng:NextNumber(196, 208)
		tree(hub, o, x, z, rng)
	end
	for _ = 1, 12 do
		local z = rng:NextNumber(-55, 55)
		local x = if rng:NextNumber() < 0.5 then rng:NextNumber(-330, -305) else rng:NextNumber(305, 330)
		tree(hub, o, x, z, rng)
	end
end

-- Clean, readable daylight: soft haze, no bloom, no stacked post effects.
-- Per-zone tweaks (museum bright / desert warm / jungle green) are done on the
-- client by Controllers/ZoneLighting, which only edits these same objects.
local function setupLighting()
	for _, child in Lighting:GetChildren() do
		if child:IsA("BloomEffect") or child:IsA("SunRaysEffect") or child:IsA("BlurEffect") or child:IsA("DepthOfFieldEffect") then
			child:Destroy()
		end
	end
	-- Balanced daylight. The previous values (Brightness 2.2 with ambient
	-- around 110-150) flattened shadows and washed out the cream stone.
	-- Late-afternoon light: the sun comes in low from the side, so columns,
	-- cornices and arches cast real shadows (a high noon sun flattened them and,
	-- with high ambient, washed the ivory stone out to white in play-tests).
	Lighting.ClockTime = 15.6
	Lighting.GeographicLatitude = 35
	Lighting.Brightness = 1.7
	Lighting.ExposureCompensation = -0.65
	Lighting.EnvironmentDiffuseScale = 0.45
	Lighting.EnvironmentSpecularScale = 0.35 -- subtle reflections on glass and bronze
	Lighting.Ambient = C(86, 76, 64) -- indoor fill: soft warm ivory
	Lighting.OutdoorAmbient = C(104, 100, 98) -- neutral-warm shadow fill
	Lighting.ShadowSoftness = 0.15
	Lighting.GlobalShadows = true
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere") or Instance.new("Atmosphere")
	atmo.Density = 0.32
	atmo.Offset = 0.2
	atmo.Color = C(222, 210, 192)
	atmo.Decay = C(150, 140, 135)
	atmo.Glare = 0.05
	atmo.Haze = 0.9 -- gentle aerial perspective: distant plots fade softly
	atmo.Parent = Lighting
	if not Lighting:FindFirstChildOfClass("Sky") then
		Instance.new("Sky").Parent = Lighting
	end
	local cc = Lighting:FindFirstChild("ZoneColor") or Instance.new("ColorCorrectionEffect")
	cc.Name = "ZoneColor"
	cc.Brightness = 0
	cc.Contrast = 0.06
	cc.Saturation = 0.03
	cc.TintColor = C(255, 248, 238)
	cc.Parent = Lighting
	-- Remove any other colour corrections so nothing stacks on top.
	for _, child in Lighting:GetChildren() do
		if child:IsA("ColorCorrectionEffect") and child ~= cc then
			child:Destroy()
		end
	end
end

function WorldBuilder.Build()
	-- Remove the default template objects (the island replaces them).
	for _, name in { "Baseplate", "SpawnLocation" } do
		local old = workspace:FindFirstChild(name)
		if old and old:IsA("BasePart") then
			old:Destroy()
		end
	end

	local world = Build.Folder(workspace, "World")
	-- A broken zone must never stop the plots (and so the whole game) loading.
	local function step(label: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			warn(("[WorldBuilder] %s FAILED: %s"):format(label, tostring(err)))
		end
	end
	step("Plots", buildPlots)
	step("Hub", function()
		buildHub(world)
	end)
	step("Forgotten Ruins", function()
		RuinsBuilder.Build(world, WorldBuilder.RuinsOrigin)
	end)
	step("Jungle Temple", function()
		JungleBuilder.Build(world, WorldBuilder.JungleOrigin)
	end)
	step("Safety floors", function()
		-- Invisible floors under each zone's terrain: if terrain ever fails to
		-- build or load, players land here instead of falling forever.
		for _, origin in { WorldBuilder.RuinsOrigin, WorldBuilder.JungleOrigin } do
			local floor = Build.Part(world, origin, V(420, 2, 420), CF(0, -17, 0), P(C(200, 180, 140), M.SmoothPlastic, { Transparency = 1, Name = "SafetyFloor" }))
			floor.CastShadow = false
		end
	end)
	step("Lighting", setupLighting)
end

return WorldBuilder
