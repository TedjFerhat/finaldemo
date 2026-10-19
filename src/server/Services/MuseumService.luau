--[[
	MuseumService
	Builds each player's museum on their plot, sells construction upgrades, and
	places/removes exhibits in display slots.

	Anti-duplication: an exhibit is just a reference (slot › item Uid) to an
	item that stays in the player's inventory. Placing, removing or moving it
	never copies the item.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Upgrades = require(Shared.Upgrades)
local ItemCatalog = require(Shared.ItemCatalog)
local ItemModels = require(Shared.ItemModels)
local Displays = require(script.Parent.Parent.World.Displays)
local Rarities = require(Shared.Rarities)
local CollectionSets = require(Shared.CollectionSets)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local PlotService = require(script.Parent.PlotService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Build = require(script.Parent.Parent.World.Build)
local MuseumBuilder = require(script.Parent.Parent.World.MuseumBuilder)

local MuseumService = {}

local PLACE_MAX_DISTANCE = 22
local PAD_DEBOUNCE = 2

type MuseumState = {
	Plot: Model,
	Origin: CFrame,
	Folder: Instance,
	Base: MuseumBuilder.BaseRefs,
	Fixtures: { [string]: MuseumBuilder.Fixture },
	Prompts: { [string]: ProximityPrompt },
	PadTouch: { [string]: number },
}

local states: { [Player]: MuseumState } = {}
local builtCallbacks: { (Player, MuseumState) -> () } = {}
local upgradedCallbacks: { (Player, string) -> () } = {}

-- ── Helpers ────────────────────────────────────────────────────────────────
local function sortedOwnedUpgrades(owned: { [string]: boolean }): { Upgrades.UpgradeDef }
	local list = {}
	for _, up in Upgrades.List do
		if owned[up.Id] then
			table.insert(list, up)
		end
	end
	return list
end

local function slotsForUpgrade(upgradeId: string): { Upgrades.SlotDef }
	if upgradeId == "base" then
		return Upgrades.BaseSlots
	end
	local up = Upgrades.ById[upgradeId]
	return if up then up.Slots else {}
end

local function hexColor(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

-- Construction effect: parts rise from the ground and fade in.
local function animateIn(root: Instance)
	local parts = {}
	if root:IsA("BasePart") then
		table.insert(parts, root)
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			table.insert(parts, d)
		end
	end
	local stagger = math.min(0.03, 1.2 / math.max(1, #parts))
	for i, p in parts do
		local targetCFrame = p.CFrame
		local targetTransparency = p.Transparency
		p.CFrame = targetCFrame * CFrame.new(0, -5, 0)
		p.Transparency = 1
		local info = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, i * stagger)
		TweenService:Create(p, info, { CFrame = targetCFrame, Transparency = targetTransparency }):Play()
	end
end

local function updateSigns(player: Player, state: MuseumState)
	local data = PlayerDataService.GetData(player)
	local level = if data then Upgrades.ComputeLevel(data.Upgrades) else 1
	state.Base.SignLabel.Text = ("%s's Museum\n%s"):format(player.DisplayName, Upgrades.LevelNames[level])
	local ownerSign = state.Plot:FindFirstChild("OwnerSign")
	local label = ownerSign and ownerSign:FindFirstChild("OwnerText", true)
	if label and label:IsA("TextLabel") then
		label.Text = ("%s\nLevel %d"):format(player.DisplayName, level)
	end
end

-- ── Displays ───────────────────────────────────────────────────────────────
local function updatePrompt(player: Player, slotId: string)
	local state = states[player]
	local data = PlayerDataService.GetData(player)
	local prompt = state and state.Prompts[slotId]
	if not prompt or not data then
		return
	end
	local occupied = data.Displays[slotId] ~= nil
	prompt.ActionText = if occupied then "Remove / Inspect" else "Place Exhibit"
end

local function renderSlot(player: Player, slotId: string)
	local state = states[player]
	local data = PlayerDataService.GetData(player)
	if not state or not data then
		return
	end
	local fixture = state.Fixtures[slotId]
	if not fixture then
		return
	end
	local old = fixture.Model:FindFirstChild("Exhibit")
	if old then
		old:Destroy()
	end
	local oldPlate = fixture.PromptPart:FindFirstChild("Nameplate")
	if oldPlate then
		oldPlate:Destroy()
	end
	local oldLamp = fixture.Model:FindFirstChild("Spotlight")
	if oldLamp then
		oldLamp:Destroy()
	end
	Displays.Clear(fixture.Model)

	local uid = data.Displays[slotId]
	local item = uid and data.Inventory[uid]
	local def = item and ItemCatalog.Get(item.Id)
	if def and item.Reserved and item.Reserved.Kind == "Heist" then
		-- Being stolen right now: the exhibit is gone from the case.
		local plate = Instance.new("BillboardGui")
		plate.Name = "Nameplate"
		plate.Adornee = fixture.PromptPart
		plate.Size = UDim2.fromOffset(200, 40)
		plate.StudsOffsetWorldSpace = Vector3.new(0, fixture.Anchor.Position.Y - fixture.PromptPart.Position.Y + 1.5, 0)
		plate.MaxDistance = 40
		plate.LightInfluence = 0
		local label = Instance.new("TextLabel")
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.TextScaled = true
		label.Font = Enum.Font.GothamBold
		label.TextColor3 = Color3.fromRGB(255, 90, 80)
		label.TextStrokeTransparency = 0.3
		label.Text = "EXHIBIT MISSING!"
		label.Parent = plate
		plate.Parent = fixture.PromptPart
	elseif def then
		local model = ItemModels.Build(def.Id, fixture.Scale)
		model.Name = "Exhibit"
		model:PivotTo(fixture.Anchor)
		local slotType = (fixture.Model:GetAttribute("SlotType") :: string?) or "Pedestal"
		Displays.Fit(model, fixture.Anchor, slotType) -- scale to fit + rest on the surface
		ItemModels.AddRarityGlow(model, def.Rarity)
		model.Parent = fixture.Model
		Displays.Dress(fixture.Model, fixture.Anchor, slotType, def.Rarity)
		local hasPlaque = Displays.SetPlaque(fixture.Model, def.Name, def.Rarity, item.Condition or "Clean")

		local boxCFrame, boxSize = model:GetBoundingBox()
		local topY = boxCFrame.Position.Y + boxSize.Y / 2
		if not hasPlaque then -- fixtures without a plaque fall back to a small close-range label
			local plate = Instance.new("BillboardGui")
			plate.Name = "Nameplate"
			plate.Adornee = fixture.PromptPart
			plate.Size = UDim2.fromOffset(190, 58)
			plate.StudsOffsetWorldSpace = Vector3.new(0, topY - fixture.PromptPart.Position.Y + 1.4, 0)
			plate.MaxDistance = 14 -- only the exhibits right next to you, so labels never pile up
			plate.LightInfluence = 0
			local bg = Instance.new("Frame")
			bg.Size = UDim2.fromScale(1, 1)
			bg.BackgroundColor3 = Color3.fromRGB(16, 21, 36)
			bg.BackgroundTransparency = 0.18
			bg.Parent = plate
			local corner = Instance.new("UICorner")
			corner.CornerRadius = UDim.new(0, 10)
			corner.Parent = bg
			local label = Instance.new("TextLabel")
			label.BackgroundTransparency = 1
			label.Position = UDim2.fromOffset(8, 4)
			label.Size = UDim2.new(1, -16, 1, -8)
			label.RichText = true
			label.TextScaled = true
			label.Font = Enum.Font.GothamBold
			label.TextColor3 = Color3.new(1, 1, 1)
			label.TextStrokeTransparency = 1
			local setText = ""
			if def.Set and CollectionSets.ById[def.Set] then
				setText = ("\n<font size=\"14\">%s</font>"):format(CollectionSets.ById[def.Set].Name)
			end
			local condition = item.Condition or "Clean"
			label.Text = ("<font color=\"%s\">%s</font> · %s\n%s%s"):format(hexColor(Rarities.Color(def.Rarity)), string.upper(def.Rarity), condition, def.Name, setText)
			label.Parent = bg
			plate.Parent = fixture.PromptPart
		end

		-- Spotlight above the exhibit (warm museum lighting)
		local lamp = Instance.new("Part")
		lamp.Name = "Spotlight"
		lamp.Anchored = true
		lamp.CanCollide = false
		lamp.CanTouch = false
		lamp.CanQuery = false
		lamp.Transparency = 1
		lamp.Size = Vector3.new(0.4, 0.4, 0.4)
		local lampPos = (fixture.Anchor * CFrame.new(0, boxSize.Y + 6, -2.5)).Position
		lamp.CFrame = CFrame.lookAt(lampPos, boxCFrame.Position)
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 45
		spot.Range = 14
		spot.Brightness = if Rarities.Order(def.Rarity) >= 4 then 0.7 else 0.45
		spot.Color = Color3.fromRGB(255, 232, 196)
		spot.Shadows = false
		spot.Parent = lamp
		lamp.Parent = fixture.Model
	end
	updatePrompt(player, slotId)
end

local function removeExhibit(player: Player, slotId: string): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded"
	end
	local uid = data.Displays[slotId]
	if not uid then
		return false, "Nothing on display here"
	end
	local reservedItem = data.Inventory[uid]
	if reservedItem and reservedItem.Reserved then
		return false, "That exhibit is being stolen! Stop the thief!"
	end
	data.Displays[slotId] = nil
	renderSlot(player, slotId)
	StateSync.Mark(player)
	local item = data.Inventory[uid]
	local def = item and ItemCatalog.Get(item.Id)
	return true, ("%s returned to storage"):format(if def then def.Name else "Item")
end

function MuseumService.PlaceItem(player: Player, slotId: any, uid: any): (boolean, string?)
	if not Net.IsString(slotId, 16) or not Net.IsString(uid, 64) then
		return false, "Invalid request"
	end
	local state = states[player]
	local data = PlayerDataService.GetData(player)
	if not state or not data then
		return false, "Your museum isn't ready yet"
	end
	local slotEntry = Upgrades.SlotById[slotId]
	local fixture = state.Fixtures[slotId]
	if not slotEntry or not fixture or not Upgrades.IsSlotUnlocked(slotId, data.Upgrades) then
		return false, "That display isn't built yet"
	end
	if data.Displays[slotId] then
		return false, "That display is already occupied"
	end
	local item = data.Inventory[uid]
	if not item then
		return false, "You don't own that item"
	end
	if item.Reserved then
		return false, "That item is busy (" .. item.Reserved.Kind .. ")"
	end
	if PlayerDataService.IsBusy(player) then
		return false, "Finishing a transfer, try again in a moment"
	end
	if InventoryService.DisplayedSlotOf(data, uid) then
		return false, "That item is already on display"
	end
	local def = ItemCatalog.Get(item.Id)
	if not def then
		return false, "Unknown item"
	end
	if def.Gadget then
		return false, "Heist gear can't go on display"
	end
	if not ItemCatalog.FitsSlot(def, slotEntry.Slot.Type) then
		return false, ("%s can't go on a %s"):format(def.Name, slotEntry.Slot.Type)
	end
	if def.RequiresSecurity and not Upgrades.HasSecurity(data.Upgrades) then
		return false, "You need the Security System upgrade to display " .. def.Rarity .. " items"
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or ((root :: BasePart).Position - fixture.PromptPart.Position).Magnitude > PLACE_MAX_DISTANCE then
		return false, "Walk closer to the display"
	end

	data.Displays[slotId] = uid
	renderSlot(player, slotId)
	StateSync.Mark(player)
	return true, ("%s is now on display!"):format(def.Name)
end

-- ── Upgrades ───────────────────────────────────────────────────────────────
local refreshPads: (Player) -> ()

local function buildSlotsFor(player: Player, upgradeId: string, animate: boolean)
	local state = states[player]
	if not state then
		return
	end
	local slotsFolder = state.Folder:FindFirstChild("Slots") :: Instance
	for _, slot in slotsForUpgrade(upgradeId) do
		if not state.Fixtures[slot.Id] then
			local fixture = MuseumBuilder.BuildSlot(slotsFolder, state.Origin, slot)
			state.Fixtures[slot.Id] = fixture
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "DisplayPrompt"
			prompt.ObjectText = slot.Type
			prompt.ActionText = "Place Exhibit"
			prompt.HoldDuration = 0
			prompt.MaxActivationDistance = 10
			prompt.RequiresLineOfSight = false
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.Parent = fixture.PromptPart
			state.Prompts[slot.Id] = prompt
			prompt.Triggered:Connect(function(who: Player)
				MuseumService._onSlotTriggered(player, who, slot.Id)
			end)
			if animate then
				animateIn(fixture.Model)
			end
			renderSlot(player, slot.Id)
		end
	end
end

local function rebuildBarriers(player: Player)
	local state = states[player]
	local data = PlayerDataService.GetData(player)
	if not state or not data then
		return
	end
	local folder = state.Folder:FindFirstChild("Barriers") :: Instance
	folder:ClearAllChildren()
	MuseumBuilder.BuildBarriers(folder, state.Origin, data.Upgrades)
end

function MuseumService.PurchaseUpgrade(player: Player, upgradeId: any): (boolean, string?)
	if not Net.IsString(upgradeId, 40) then
		return false, "Invalid upgrade"
	end
	local up = Upgrades.ById[upgradeId]
	local data = PlayerDataService.GetData(player)
	local state = states[player]
	if not up or not data or not state then
		return false, "Invalid upgrade"
	end
	if data.Upgrades[up.Id] then
		return false, "You already own " .. up.Name
	end
	if not Upgrades.RequirementsMet(up, data.Upgrades) then
		local names = {}
		for _, req in up.Requires do
			if not data.Upgrades[req] then
				table.insert(names, Upgrades.ById[req].Name)
			end
		end
		return false, "Build first: " .. table.concat(names, ", ")
	end
	local oldLevel = Upgrades.ComputeLevel(data.Upgrades)
	if not EconomyService.Spend(player, up.Cost, "Upgrade:" .. up.Id) then
		return false, ("You need %s (you have %s)"):format(Format.Cash(up.Cost), Format.Cash(data.Cash))
	end
	data.Upgrades[up.Id] = true

	local geometry = MuseumBuilder.BuildUpgrade(state.Folder:FindFirstChild("Upgrades") :: Instance, state.Origin, up.Id)
	animateIn(geometry)
	buildSlotsFor(player, up.Id, true)
	rebuildBarriers(player)
	refreshPads(player)
	updateSigns(player, state)
	StateSync.Mark(player)
	Net.Fire("Purchased", player, up.Id)
	for _, callback in upgradedCallbacks do
		task.spawn(callback, player, up.Id)
	end

	local newLevel = Upgrades.ComputeLevel(data.Upgrades)
	if newLevel > oldLevel then
		Notifier.Send(player, ("Museum Level %d: %s!"):format(newLevel, Upgrades.LevelNames[newLevel]), "Reward")
	end
	return true, ("Built: %s"):format(up.Name)
end

refreshPads = function(player: Player)
	local state = states[player]
	local data = PlayerDataService.GetData(player)
	if not state or not data then
		return
	end
	local padsFolder = state.Folder:FindFirstChild("Pads") :: Instance
	padsFolder:ClearAllChildren()
	for _, up in Upgrades.List do
		if not data.Upgrades[up.Id] and Upgrades.RequirementsMet(up, data.Upgrades) then
			local pad = MuseumBuilder.BuildPad(padsFolder, state.Origin, up, Format.Cash(up.Cost))
			pad.Touched:Connect(function(hit: BasePart)
				local model = hit:FindFirstAncestorOfClass("Model")
				local toucher = model and Players:GetPlayerFromCharacter(model)
				if toucher ~= player then
					return
				end
				local now = os.clock()
				if (state.PadTouch[up.Id] or 0) > now then
					return
				end
				state.PadTouch[up.Id] = now + PAD_DEBOUNCE
				local ok, message = MuseumService.PurchaseUpgrade(player, up.Id)
				Notifier.Send(player, message or "", if ok then "Success" else "Error")
			end)
		end
	end
end

function MuseumService._onSlotTriggered(owner: Player, who: Player, slotId: string)
	local data = PlayerDataService.GetData(owner)
	if not data then
		return
	end
	local uid = data.Displays[slotId]
	if who ~= owner then
		-- Visitors can inspect, never change anything.
		local item = uid and data.Inventory[uid]
		local def = item and ItemCatalog.Get(item.Id)
		if def then
			Notifier.Send(who, ("%s (%s) — %s"):format(def.Name, def.Rarity, def.Lore), "Info")
		else
			Notifier.Send(who, ("This display belongs to %s."):format(owner.DisplayName), "Info")
		end
		return
	end
	if uid then
		local ok, message = removeExhibit(owner, slotId)
		Notifier.Send(owner, message or "", if ok then "Info" else "Error")
	else
		local entry = Upgrades.SlotById[slotId]
		Net.Fire("OpenPlacement", owner, { SlotId = slotId, SlotType = entry.Slot.Type })
	end
end

-- ── Building & clearing a whole museum ─────────────────────────────────────
local function clearMuseum(plot: Model)
	local folder = plot:FindFirstChild("Museum")
	if folder then
		folder:ClearAllChildren()
	end
	local ownerSign = plot:FindFirstChild("OwnerSign")
	local label = ownerSign and ownerSign:FindFirstChild("OwnerText", true)
	if label and label:IsA("TextLabel") then
		label.Text = "Plot available"
	end
end

local function buildMuseum(player: Player, plot: Model)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	clearMuseum(plot)
	local folder = plot:FindFirstChild("Museum") :: Instance
	local origin = PlotService.GetOrigin(plot)
	-- Museum interiors use daylight only: any light object created anywhere
	-- inside the museum (ceiling, cases, spotlights, pads) is removed.
	if Config.MuseumLights ~= true and not folder:GetAttribute("LightsStripped") then
		folder:SetAttribute("LightsStripped", true)
		folder.DescendantAdded:Connect(function(inst)
			-- "SoftLamp" parts keep their small decorative glow
			if inst:IsA("Light") and not (inst.Parent and inst.Parent.Name == "SoftLamp") then
				inst:Destroy()
			end
		end)
	end
	local base = MuseumBuilder.BuildBase(folder, origin)
	Build.Folder(folder, "Upgrades")
	Build.Folder(folder, "Slots")
	Build.Folder(folder, "Barriers")
	Build.Folder(folder, "Pads")

	local state: MuseumState = {
		Plot = plot,
		Origin = origin,
		Folder = folder,
		Base = base,
		Fixtures = {},
		Prompts = {},
		PadTouch = {},
	}
	states[player] = state

	-- Drop display references to items that no longer exist or slots that
	-- aren't unlocked (protects against corrupted or edited save data).
	for slotId, uid in data.Displays do
		if not data.Inventory[uid] or not Upgrades.IsSlotUnlocked(slotId, data.Upgrades) then
			data.Displays[slotId] = nil
		end
	end

	for _, up in sortedOwnedUpgrades(data.Upgrades) do
		MuseumBuilder.BuildUpgrade(folder:FindFirstChild("Upgrades") :: Instance, origin, up.Id)
	end
	buildSlotsFor(player, "base", false)
	for _, up in sortedOwnedUpgrades(data.Upgrades) do
		buildSlotsFor(player, up.Id, false)
	end
	rebuildBarriers(player)
	refreshPads(player)
	updateSigns(player, state)

	for _, callback in builtCallbacks do
		task.spawn(callback, player, state)
	end
end

-- ── Public API for other services ──────────────────────────────────────────
function MuseumService.OnBuilt(callback: (Player, any) -> ())
	table.insert(builtCallbacks, callback)
end

-- Called after any upgrade is built (security visuals use this).
function MuseumService.OnUpgraded(callback: (Player, string) -> ())
	table.insert(upgradedCallbacks, callback)
end

-- Re-draws one display slot (after a heist reserves/releases its item).
function MuseumService.RefreshSlot(player: Player, slotId: string)
	renderSlot(player, slotId)
end

-- Re-draws every display slot (after a transfer removed exhibits).
function MuseumService.RefreshAll(player: Player)
	local state = states[player]
	if state then
		for slotId in state.Fixtures do
			renderSlot(player, slotId)
		end
	end
end

function MuseumService.GetState(player: Player): any
	return states[player]
end

function MuseumService.Init() end

function MuseumService.Start()
	Net.Handle("PurchaseUpgrade", MuseumService.PurchaseUpgrade)
	Net.Handle("PlaceItem", MuseumService.PlaceItem)

	PlotService.OnAssigned(buildMuseum)
	PlotService.OnReleased(function(player, plot)
		states[player] = nil
		clearMuseum(plot)
	end)
end

return MuseumService
