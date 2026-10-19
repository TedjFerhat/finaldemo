--[[
	VisitorService
	• Museum revenue: every few seconds each museum earns income (formula in
	  ProgressionService) into its Ticket Desk, up to a storage cap. Players
	  walk to the desk and press E to collect.
	• NPC visitors: lightweight walking figures (no physics, no Humanoid) that
	  tour the exhibits. They are purely visual — revenue never depends on them
	  — and they only spawn while someone is nearby to see them.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ProgressionService = require(script.Parent.ProgressionService)
local MuseumService = require(script.Parent.MuseumService)
local StateSync = require(script.Parent.StateSync)
local Notifier = require(script.Parent.Parent.Util.Notifier)

local VisitorService = {}

type PlotRuntime = {
	Owner: Player,
	DeskLabel: TextLabel?,
	Visitors: { Model },
	Folder: Folder,
}

local runtimes: { [Player]: PlotRuntime } = {}
local rng = Random.new()

local SHIRTS = {
	Color3.fromRGB(70, 110, 180),
	Color3.fromRGB(180, 70, 70),
	Color3.fromRGB(70, 150, 90),
	Color3.fromRGB(200, 160, 60),
	Color3.fromRGB(140, 90, 170),
	Color3.fromRGB(60, 60, 70),
}
local SKIN = {
	Color3.fromRGB(255, 220, 180),
	Color3.fromRGB(210, 160, 120),
	Color3.fromRGB(150, 100, 70),
	Color3.fromRGB(95, 65, 45),
}

-- ── Revenue ────────────────────────────────────────────────────────────────
function VisitorService.Collect(player: Player): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded"
	end
	local amount = math.floor(data.PendingRevenue)
	if amount < 1 then
		return false, "No earnings yet — display more exhibits!"
	end
	-- Clear first, then pay, so revenue can't be collected twice.
	data.PendingRevenue -= amount
	data.Stats.TotalCollected += amount
	EconomyService.Add(player, amount, "TicketDesk")
	StateSync.Mark(player)
	return true, ("Collected %s from the ticket desk!"):format(Format.Cash(amount))
end

local function updateDeskLabel(player: Player, cap: number)
	local runtime = runtimes[player]
	local data = PlayerDataService.GetData(player)
	if not runtime or not runtime.DeskLabel or not data then
		return
	end
	local pending = math.floor(data.PendingRevenue)
	local full = pending >= cap
	runtime.DeskLabel.Text = ("<b>Ticket Desk</b>\n<font color=\"%s\">%s / %s</font>"):format(if full then "#FF8C6E" else "#8CF5AA", Format.Cash(pending), Format.Cash(cap))
end

local function revenueTick()
	for player, profile in PlayerDataService.AllProfiles() do
		local data = profile.Data
		if not profile.Released and runtimes[player] then
			local income = ProgressionService.ComputeIncome(data)
			local cap = ProgressionService.RevenueCap(income.PerMinute)
			local before = math.floor(data.PendingRevenue)
			data.PendingRevenue = math.min(cap, data.PendingRevenue + income.PerMinute * Config.RevenueTickSeconds / 60)
			updateDeskLabel(player, cap)
			if math.floor(data.PendingRevenue) ~= before then
				StateSync.Mark(player)
			end
		end
	end
end

-- ── NPC visitors ───────────────────────────────────────────────────────────
local function makeVisitor(parent: Instance, startCFrame: CFrame): Model
	local model = Instance.new("Model")
	model.Name = "Visitor"
	local function bodyPart(name: string, size: Vector3, offset: CFrame, color: Color3, shape: Enum.PartType?): Part
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Color = color
		p.Material = Enum.Material.SmoothPlastic
		if shape then
			p.Shape = shape
		end
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Anchored = false
		p.Massless = true
		p.CFrame = startCFrame * offset
		p.Parent = model
		return p
	end
	local torso = bodyPart("Torso", Vector3.new(2, 2.4, 1.2), CFrame.new(0, 3.4, 0), SHIRTS[rng:NextInteger(1, #SHIRTS)])
	torso.Anchored = true
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local pieces = {
		bodyPart("Head", Vector3.new(1.4, 1.4, 1.4), CFrame.new(0, 5.3, 0), skin, Enum.PartType.Ball),
		bodyPart("Legs", Vector3.new(1.8, 2.2, 1), CFrame.new(0, 1.1, 0), Color3.fromRGB(50, 50, 60)),
		bodyPart("ArmL", Vector3.new(0.6, 2.2, 0.8), CFrame.new(-1.3, 3.4, 0), skin),
		bodyPart("ArmR", Vector3.new(0.6, 2.2, 0.8), CFrame.new(1.3, 3.4, 0), skin),
	}
	for _, p in pieces do
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = torso
		weld.Part1 = p
		weld.Parent = torso
	end
	model.PrimaryPart = torso
	model.Parent = parent
	return model
end

-- Walks a visitor through world-space points. Returns false if it was removed.
local function walk(visitor: Model, points: { Vector3 }): boolean
	local torso = visitor.PrimaryPart
	for _, point in points do
		if not torso or visitor.Parent == nil then
			return false
		end
		-- point.Y is the floor height there; the torso rides 3.4 studs above it
		local target = Vector3.new(point.X, point.Y + 3.4, point.Z)
		local from = torso.Position
		local distance = (target - from).Magnitude
		if distance > 0.1 then
			local look = CFrame.lookAt(from, target)
			torso.CFrame = look
			local tween = TweenService:Create(torso, TweenInfo.new(distance / Config.VisitorWalkSpeed, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(target, target + look.LookVector) })
			tween:Play()
			tween.Completed:Wait()
		end
	end
	return visitor.Parent ~= nil
end

local function toWorld(origin: CFrame, path: { { number } }): { Vector3 }
	local points = {}
	for _, p in path do
		-- ground floor is y = 1; p[3] is an optional elevation (stairs/upper floor)
		table.insert(points, (origin * CFrame.new(p[1], 1 + (p[3] or 0), p[2])).Position)
	end
	return points
end

local function reversed<T>(list: { T }): { T }
	local out = {}
	for i = #list, 1, -1 do
		table.insert(out, list[i])
	end
	return out
end

local function runVisitor(player: Player, runtime: PlotRuntime)
	local state = MuseumService.GetState(player)
	local data = PlayerDataService.GetData(player)
	if not state or not data then
		return
	end
	-- Pick up to 3 occupied displays to look at
	local occupied = {}
	for slotId in data.Displays do
		local entry = Upgrades.SlotById[slotId]
		if entry then
			table.insert(occupied, entry.Slot)
		end
	end
	if #occupied == 0 then
		return
	end

	local origin: CFrame = state.Origin
	local entrance = origin * CFrame.new(rng:NextNumber(-3, 3), 1, -28)
	local visitor = makeVisitor(runtime.Folder, entrance)
	table.insert(runtime.Visitors, visitor)

	-- `back` = the points that lead from where the visitor stands to the hall.
	local back: { { number } } = { { 0, -22 }, { 0, -10 } }
	for _ = 1, math.min(3, #occupied) do
		local slot = occupied[rng:NextInteger(1, #occupied)]
		local roomPath = Upgrades.RoomPaths[slot.Room] or Upgrades.RoomPaths.Hall
		-- Stand ~5 studs in front of the exhibit
		local face = CFrame.Angles(0, math.rad(slot.Face), 0)
		local standOffset = face:VectorToWorldSpace(Vector3.new(0, 0, -5))
		-- roomPath[1..2] are outside/doorway; from [3] (hall centre) onwards leads into the room
		local inPath: { { number } } = {}
		for i = 3, #roomPath do
			table.insert(inPath, roomPath[i])
		end
		local elevation = if slot.Y and slot.Y >= 4 then 10 else 0
		table.insert(inPath, { slot.X + standOffset.X, slot.Z + standOffset.Z, elevation })

		local route = table.clone(back)
		for _, p in inPath do
			table.insert(route, p)
		end
		if not walk(visitor, toWorld(origin, route)) then
			return
		end
		task.wait(rng:NextNumber(2.5, 5))
		back = reversed(inPath)
	end
	-- Leave through the entrance
	local exitRoute = table.clone(back)
	table.insert(exitRoute, { 0, -10 })
	table.insert(exitRoute, { 0, -28 })
	walk(visitor, toWorld(origin, exitRoute))
	local index = table.find(runtime.Visitors, visitor)
	if index then
		table.remove(runtime.Visitors, index)
	end
	visitor:Destroy()
end

local function anyPlayerNear(position: Vector3): boolean
	for _, p in Players:GetPlayers() do
		local character = p.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		if root and root:IsA("BasePart") and (root.Position - position).Magnitude < Config.VisitorActiveRadius then
			return true
		end
	end
	return false
end

local function visitorTick()
	for player, runtime in runtimes do
		local state = MuseumService.GetState(player)
		local data = PlayerDataService.GetData(player)
		if state and data then
			local displays = 0
			for _ in data.Displays do
				displays += 1
			end
			local target = math.min(Config.MaxVisitorsPerPlot, math.ceil(displays / 2))
			if #runtime.Visitors < target and anyPlayerNear(state.Origin.Position) then
				task.spawn(runVisitor, player, runtime)
			end
		end
	end
end

-- ── Setup ──────────────────────────────────────────────────────────────────
local function onMuseumBuilt(player: Player, state: any)
	local old = runtimes[player]
	if old then
		old.Folder:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "Visitors"
	folder.Parent = state.Folder

	local desk: BasePart = state.Base.Desk
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "Collect Earnings"
	prompt.ObjectText = "Ticket Desk"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = desk
	prompt.Triggered:Connect(function(who: Player)
		if who ~= player then
			Notifier.Send(who, "Only " .. player.DisplayName .. " can collect these earnings.", "Info")
			return
		end
		local ok, message = VisitorService.Collect(player)
		Notifier.Send(player, message or "", if ok then "Success" else "Info")
	end)

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DeskBillboard"
	billboard.Size = UDim2.fromOffset(200, 60)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	billboard.MaxDistance = 70
	billboard.LightInfluence = 0
	billboard.Adornee = desk
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.RichText = true
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = "Ticket Desk"
	label.Parent = billboard
	billboard.Parent = desk

	runtimes[player] = { Owner = player, DeskLabel = label, Visitors = {}, Folder = folder }
end

function VisitorService.Init() end

function VisitorService.Start()
	MuseumService.OnBuilt(onMuseumBuilt)
	PlayerDataService.OnReleasing(function(player)
		local runtime = runtimes[player]
		if runtime then
			runtime.Folder:Destroy()
			runtimes[player] = nil
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.RevenueTickSeconds)
			local ok, err = pcall(revenueTick)
			if not ok then
				warn("[VisitorService] revenue tick error: " .. tostring(err))
			end
		end
	end)
	task.spawn(function()
		while true do
			task.wait(3)
			local ok, err = pcall(visitorTick)
			if not ok then
				warn("[VisitorService] visitor tick error: " .. tostring(err))
			end
		end
	end)
end

return VisitorService
