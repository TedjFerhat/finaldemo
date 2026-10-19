--[[
	DiscoveryPopup
	The "you found something!" card: a spinning 3D model, the rarity colour,
	the value, and a NEW! tag for first-time discoveries. Legendary and
	Mythic finds also flash the screen.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ItemCatalog = require(Shared.ItemCatalog)
local Rarities = require(Shared.Rarities)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)
local ItemPreview = require(script.Parent.ItemPreview)
local Notifications = require(script.Parent.Notifications)
local ClientState = require(script.Parent.Parent.ClientState)

local DiscoveryPopup = {}

local screenGui: ScreenGui
local current: Frame? = nil

local function flash(color: Color3)
	local f = Theme.New("Frame", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0.35,
		Size = UDim2.fromScale(1, 1),
		ZIndex = 20,
		Parent = screenGui,
	})
	TweenService:Create(f, TweenInfo.new(0.8), { BackgroundTransparency = 1 }):Play()
	task.delay(0.85, function()
		f:Destroy()
	end)
end

local function show(itemId: string, condition: string?)
	local def = ItemCatalog.Get(itemId)
	if not def then
		return
	end
	-- The server sends this pop-up ~0.1s BEFORE the updated journal, so the
	-- journal we hold right now still shows whether we'd found it before.
	local state = ClientState.Get()
	local isNew = state == nil or state.Journal.Discovered[itemId] == nil

	if current then
		current:Destroy()
	end
	local color = Rarities.Color(def.Rarity)
	local order = Rarities.Order(def.Rarity)

	local card = Theme.New("TextButton", {
		Name = "Discovery",
		AutoButtonColor = false,
		Text = "",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(320, 250),
		BackgroundColor3 = Theme.Colors.Panel,
		ZIndex = 15,
		Parent = screenGui,
	})
	current = card
	Theme.Corner(card, 16)
	Theme.Stroke(card, color, 4)
	local scale = Theme.New("UIScale", { Scale = 0.3, Parent = card })

	Theme.Label(if isNew then "NEW DISCOVERY!" else "DISCOVERY!", {
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Gold,
		Position = UDim2.fromOffset(10, 8),
		Size = UDim2.new(1, -20, 0, 28),
		ZIndex = 16,
		Parent = card,
	}, 26)
	local preview = ItemPreview.Create(itemId, true)
	preview.Position = UDim2.fromOffset(10, 38)
	preview.Size = UDim2.new(1, -20, 0, 120)
	preview.ZIndex = 16
	preview.Parent = card
	Theme.Label(("<b>%s</b>"):format(def.Name), {
		Position = UDim2.fromOffset(10, 160),
		Size = UDim2.new(1, -20, 0, 26),
		ZIndex = 16,
		Parent = card,
	}, 22)
	Theme.Label(("<font color=\"%s\"><b>%s</b></font>%s · Worth %s · Earns %s/min"):format(
		Theme.Hex(color),
		string.upper(def.Rarity),
		if condition then " · " .. condition else "",
		Format.Cash(ItemCatalog.InstanceValue(def, condition, nil)),
		Format.Cash(ItemCatalog.InstanceIncome(def, condition))
	), {
		Position = UDim2.fromOffset(10, 188),
		Size = UDim2.new(1, -20, 0, 20),
		ZIndex = 16,
		Parent = card,
	}, 16)
	Theme.Label("Display it in your museum or keep exploring! (tap to close)", {
		TextColor3 = Theme.Colors.TextDim,
		Position = UDim2.fromOffset(10, 214),
		Size = UDim2.new(1, -20, 0, 18),
		ZIndex = 16,
		Parent = card,
	}, 13)

	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Sounds.Play("Discover", 0.6, 0.9 + order * 0.08)
	if order >= 5 then
		flash(color)
	end

	local function close()
		if card.Parent then
			card:Destroy()
		end
		if current == card then
			current = nil
		end
	end
	card.Activated:Connect(close)
	task.delay(if order >= 4 then 6 else 4, close)
end

function DiscoveryPopup.Init(screen: ScreenGui)
	screenGui = screen
	Remotes.Event("Discovery").OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		if info.FalseLead then
			Notifications.Show(tostring(info.FalseLead), "Info")
			Sounds.Play("Click", 0.4)
			return
		end
		if type(info.ItemId) == "string" then
			show(info.ItemId, info.Condition)
		end
	end)
end

return DiscoveryPopup
