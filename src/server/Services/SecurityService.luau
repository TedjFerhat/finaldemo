--[[
	SecurityService
	Museum owners buy security levels (Locks, Cameras, Pressure Alarms,
	Reinforced Glass). Every level is VISIBLE in the museum and is exactly
	what the heist system uses:
	  • Cameras  › real camera models whose position, facing, range and
	               field of view decide detection.
	  • Glass    › display-case glass tint + frame colour per tier.
	  • Alarms   › metal pressure pads under pedestal/wall/platform exhibits.
	  • Locks    › a lock plaque by the entrance.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local HeistConfig = require(Shared.HeistConfig)
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local MuseumService = require(script.Parent.MuseumService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)
local Build = require(script.Parent.Parent.World.Build)

local SecurityService = {}

local V = Vector3.new

-- Camera mounting points (plot space). Room = upgrade that must be owned.
local CAMERA_POINTS = {
	{ Id = "HallA", Room = "base", MinLevel = 1, Pos = V(-18.5, 16.5, -8.5), Look = V(4, 2, 14) },
	{ Id = "HallB", Room = "base", MinLevel = 2, Pos = V(18.5, 16.5, 28.5), Look = V(-4, 2, 4) },
	{ Id = "East", Room = "east_wing", MinLevel = 2, Pos = V(48.5, 13, -3.5), Look = V(30, 2, 16) },
	{ Id = "Fossil", Room = "fossil_hall", MinLevel = 2, Pos = V(22.5, 15, 53.5), Look = V(42, 2, 34) },
	{ Id = "West", Room = "west_wing", MinLevel = 2, Pos = V(-48.5, 13, -3.5), Look = V(-30, 2, 16) },
	{ Id = "Gallery", Room = "grand_gallery", MinLevel = 2, Pos = V(-18.5, 19, 60.5), Look = V(6, 2, 38) },
	{ Id = "Vault", Room = "treasure_vault", MinLevel = 1, Pos = V(-48.5, 11, 53.5), Look = V(-30, 2, 32) },
}

local GLASS_TINTS = {
	[0] = { Glass = Color3.fromRGB(200, 230, 255), Transparency = 0.75, Frame = Color3.fromRGB(214, 172, 60) },
	[1] = { Glass = Color3.fromRGB(190, 225, 245), Transparency = 0.7, Frame = Color3.fromRGB(190, 195, 205) },
	[2] = { Glass = Color3.fromRGB(165, 210, 235), Transparency = 0.62, Frame = Color3.fromRGB(110, 115, 125) },
	[3] = { Glass = Color3.fromRGB(140, 190, 230), Transparency = 0.55, Frame = Color3.fromRGB(55, 60, 70) },
}

export type CameraInfo = { Id: string, CFrame: CFrame, Range: number, Fov: number, Led: BasePart, Model: Model }

local cameras: { [Player]: { CameraInfo } } = {}

function SecurityService.Level(player: Player, system: string): number
	local data = PlayerDataService.GetData(player)
	return if data then (data.Security[system] or 0) else 0
end

-- Display-case protection tier for a slot type (0 = none).
function SecurityService.CaseTier(player: Player, slotType: string): number
	local cases = SecurityService.Level(player, "Cases")
	if slotType == "Case" then
		return math.max(1, cases)
	elseif slotType == "Vault" then
		return math.min(3, math.max(2, cases + 1))
	end
	return 0
end

function SecurityService.GetCameras(player: Player): { CameraInfo }
	return cameras[player] or {}
end

local function roomOwned(data: any, room: string): boolean
	return room == "base" or data.Upgrades[room] == true
end

local function buildCamera(parent: Instance, origin: CFrame, point: any, tier: number): CameraInfo
	local cf = CFrame.lookAt((origin * CFrame.new(point.Pos)).Position, (origin * CFrame.new(point.Look)).Position)
	local model = Instance.new("Model")
	model.Name = "Camera_" .. point.Id
	local function p(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Size = size
		part.CFrame = cf * offset
		part.Color = color
		part.Material = material or Enum.Material.Metal
		part.Parent = model
		return part
	end
	local bodyColor = if tier >= 3 then Color3.fromRGB(20, 20, 25) else Color3.fromRGB(45, 45, 52)
	p(V(0.4, 0.4, 0.9), CFrame.new(0, 0.5, 0.9), Color3.fromRGB(60, 60, 66)) -- mount arm
	p(V(0.9, 0.8, 1.7), CFrame.new(), bodyColor)
	p(V(0.55, 0.55, 0.2), CFrame.new(0, 0, -0.9), Color3.fromRGB(10, 10, 15), Enum.Material.Glass)
	local led = p(V(0.18, 0.18, 0.1), CFrame.new(0.3, 0.3, -0.86), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
	led.Name = "Led"
	if tier >= 3 then
		p(V(1.1, 0.12, 1.9), CFrame.new(0, 0.46, 0), Color3.fromRGB(90, 90, 100)) -- armoured hood
	end
	model.Parent = parent
	return {
		Id = point.Id,
		CFrame = cf,
		Range = HeistConfig.CameraRange[math.clamp(tier, 1, 3)],
		Fov = HeistConfig.CameraFov[math.clamp(tier, 1, 3)],
		Led = led,
		Model = model,
	}
end

-- (Re)builds every security visual for a museum.
function SecurityService.Rebuild(player: Player)
	local state = MuseumService.GetState(player)
	local data = PlayerDataService.GetData(player)
	if not state or not data then
		return
	end
	local old = state.Folder:FindFirstChild("Security")
	if old then
		old:Destroy()
	end
	local folder = Build.Folder(state.Folder, "Security")
	local origin: CFrame = state.Origin

	-- Cameras
	local list = {}
	local camLevel = data.Security.Cameras or 0
	for _, point in CAMERA_POINTS do
		if camLevel >= point.MinLevel and roomOwned(data, point.Room) then
			table.insert(list, buildCamera(folder, origin, point, camLevel))
		end
	end
	cameras[player] = list

	-- Lock plaque by the entrance
	local lockLevel = data.Security.Locks or 0
	local plaque = Build.Part(folder, origin, V(2.2, 1.3, 0.2), CFrame.new(7.1, 6, -10.7), { Color = Color3.fromRGB(40, 42, 48), Material = Enum.Material.Metal, CanCollide = false })
	local lockName = if lockLevel <= 0 then "No lock" else HeistConfig.Systems.Locks.Levels[lockLevel]
	Build.Label(plaque, Enum.NormalId.Front, "LOCK: " .. string.upper(lockName), Color3.fromRGB(230, 230, 235), Enum.Font.GothamBold)

	-- Glass tiers and pressure pads on every display fixture
	local alarm = data.Security.Alarm or 0
	for _, fixture in state.Fixtures do
		local slotType = fixture.Model:GetAttribute("SlotType")
		local glass = fixture.Model:FindFirstChild("Glass")
		local frame = fixture.Model:FindFirstChild("Frame")
		if glass and glass:IsA("BasePart") then
			local tier = SecurityService.CaseTier(player, slotType)
			local look = GLASS_TINTS[math.clamp((data.Security.Cases or 0), 0, 3)]
			glass.Color = look.Glass
			glass.Transparency = look.Transparency
			if frame and frame:IsA("BasePart") then
				frame.Color = look.Frame
			end
			fixture.Model:SetAttribute("CaseTier", tier)
		elseif alarm > 0 then
			local pad = Instance.new("Part")
			pad.Name = "PressurePad"
			pad.Anchored = true
			pad.CanCollide = false
			pad.CanQuery = false
			pad.CanTouch = false
			pad.Size = V(2.2, 0.08, 2.2)
			pad.CFrame = fixture.Anchor * CFrame.new(0, 0.04, 0)
			pad.Color = if alarm >= 3 then Color3.fromRGB(200, 60, 60) elseif alarm == 2 then Color3.fromRGB(200, 140, 60) else Color3.fromRGB(120, 120, 130)
			pad.Material = Enum.Material.DiamondPlate
			pad.Parent = folder
			fixture.Model:SetAttribute("AlarmTier", alarm)
		end
	end
end

function SecurityService.Buy(player: Player, systemId: any): (boolean, string?)
	if type(systemId) ~= "string" then
		return false, "Invalid system"
	end
	local def = HeistConfig.Systems[systemId]
	local data = PlayerDataService.GetData(player)
	if not def or not data then
		return false, "Invalid system"
	end
	local current = data.Security[systemId] or 0
	if current >= def.Max then
		return false, def.Name .. " is already at maximum"
	end
	local nextLevel = current + 1
	if def.RequiresUpgrade and nextLevel >= (def.RequiresUpgradeFrom or 1) and not data.Upgrades[def.RequiresUpgrade] then
		return false, ("Build the %s first"):format(Upgrades.ById[def.RequiresUpgrade].Name)
	end
	local cost = def.Costs[nextLevel]
	if not EconomyService.Spend(player, cost, "Security:" .. systemId) then
		return false, ("You need %s"):format(Format.Cash(cost))
	end
	data.Security[systemId] = nextLevel
	SecurityService.Rebuild(player)
	StateSync.Mark(player)
	return true, ("%s upgraded: %s"):format(def.Name, def.Levels[nextLevel])
end

function SecurityService.Init() end

function SecurityService.Start()
	Net.Handle("BuySecurity", SecurityService.Buy)
	MuseumService.OnBuilt(function(player)
		SecurityService.Rebuild(player)
	end)
	MuseumService.OnUpgraded(function(player)
		SecurityService.Rebuild(player)
	end)
	PlayerDataService.OnReleasing(function(player)
		cameras[player] = nil
	end)
end

return SecurityService
