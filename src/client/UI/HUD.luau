--[[
	HUD
	Minimal always-visible interface:
	  • status card (top-left): cash, level, ticket-desk earnings, equipped kit
	  • small objective line under it (can be hidden in Settings)
	  • compact navigation rail (left): main buttons + a "More" popover
	Only one window is open at a time (Window handles that); opening a
	window closes the More popover.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)
local ItemCatalog = require(Shared.ItemCatalog)
local Equipment = require(Shared.Equipment)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientState = require(script.Parent.Parent.ClientState)

local HUD = {}

local cashLabel: TextLabel
local levelLabel: TextLabel
local nameLabel: TextLabel
local deskLabel: TextLabel
local kitLabel: TextLabel
local goalFrame: Frame
local dockTiles: { { Button: TextButton, Window: string? } } = {}
local goalLabel: TextLabel
local saveWarning: TextLabel
local morePopover: Frame
local lastCash: number? = nil
local objectiveEnabled = true
local objectiveDismissed = false
local lastGoal = ""

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

-- The tutorial: always one clear, short next step.
local function computeGoal(state: any): string
	local displays = count(state.Displays)
	local stats = state.Stats
	if displays == 0 then
		return "Place your <b>Cracked Clay Pot</b>: walk to a pedestal and press <b>E</b>."
	end
	if stats.TotalCollected == 0 then
		return "Collect your earnings at the <b>Ticket Desk</b>."
	end
	if stats.Searches == 0 then
		return "Open <b>Travel</b> (or use the blue portal) to visit the <b>Forgotten Ruins</b>."
	end
	if stats.Searches < 5 then
		return ("Search sites in the ruins (%d/5)."):format(stats.Searches)
	end
	if not state.Upgrades.hall_cases then
		return "Build <b>Glass Display Cases</b>: step on its pad on the right-hand lawn (or use <b>Museum</b>)."
	end
	if displays < 3 then
		return ("Fill your displays (%d/3 exhibits)."):format(displays)
	end
	if count(state.Journal.CompletedSets) == 0 then
		return "Complete a collection set — check your <b>Journal</b>."
	end
	local nextUp = nil
	for _, up in Upgrades.List do
		if not state.Upgrades[up.Id] and Upgrades.RequirementsMet(up, state.Upgrades) then
			if not nextUp or up.Cost < nextUp.Cost then
				nextUp = up
			end
		end
	end
	if nextUp then
		return ("Next build: <b>%s</b> (%s)"):format(nextUp.Name, Format.Cash(nextUp.Cost))
	end
	return ("Discover every artefact: %d / %d"):format(count(state.Journal.Discovered), #ItemCatalog.Order)
end

local function refreshGoalVisibility()
	if goalFrame then
		goalFrame.Visible = objectiveEnabled and not objectiveDismissed
	end
end

local function update(state: any)
	cashLabel.Text = Format.Cash(state.Cash)
	if lastCash and state.Cash > lastCash then
		local scale = cashLabel:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = 1.1
			TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
	end
	lastCash = state.Cash
	nameLabel.Text = string.upper(state.LevelName or "My Museum")
	levelLabel.Text = ("LV %d  ·  %d ★"):format(state.Level or 1, state.Prestige or 0)
	local income = state.Income and state.Income.PerMinute or 0
	deskLabel.Text = ("🎟  Desk %s / %s   <font color=\"#2E7D32\">+%s/min</font>"):format(Format.Cash(state.PendingRevenue or 0), Format.Cash(state.RevenueCap or 0), Format.Cash(income))
	local ok, kit = pcall(Equipment.Get, state.ToolTier or 1)
	kitLabel.Text = "⛏ " .. (if ok and kit then kit.Name else "Trowel Kit")
	local goal = computeGoal(state)
	if goal ~= lastGoal then
		lastGoal = goal
		objectiveDismissed = false -- a new objective shows again
		refreshGoalVisibility()
	end
	goalLabel.Text = goal
	saveWarning.Visible = state.SaveEnabled == false
end

-- Settings hook (SettingsPanel)
local onAddCash: (() -> ())? = nil
-- Called when the "+" next to the cash is pressed (opens the Robux Store).
function HUD.SetAddCashHandler(fn: () -> ())
	onAddCash = fn
end

function HUD.SetObjectiveEnabled(on: boolean)
	objectiveEnabled = on
	refreshGoalVisibility()
end

function HUD.CloseMore()
	if morePopover then
		morePopover.Visible = false
	end
end

export type MenuEntry = { Icon: string, Text: string, OnClick: () -> (), Primary: boolean?, Window: string? }

-- Rounded "chip" label that sizes itself to its text.
local function chip(parent: Instance, text: string, color: Color3, order: number): TextLabel
	local l = Theme.New("TextLabel", {
		BackgroundColor3 = color,
		BackgroundTransparency = 0,
		AutomaticSize = Enum.AutomaticSize.X,
		Size = UDim2.fromOffset(0, 20),
		Font = Theme.Fonts.Bold,
		TextSize = 12,
		TextColor3 = Theme.Colors.Text,
		Text = text,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.Corner(l, 10)
	Theme.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), Parent = l })
	return l
end

-- Dock tile: icon over a tiny label; lights up with the accent gradient while
-- its window is open.
local function tile(entry: MenuEntry, size: Vector2, onClick: () -> ()): TextButton
	local button = Theme.Button("", Theme.Colors.PanelLight, onClick)
	button.Size = UDim2.fromOffset(size.X, size.Y)
	button.BackgroundTransparency = 0.2
	Theme.Corner(button, 12)
	Theme.Label(entry.Icon, { Position = UDim2.fromOffset(0, 5), Size = UDim2.new(1, 0, 0.55, -2), Parent = button }, 22)
	Theme.Label(entry.Text, { Font = Theme.Fonts.Bold, Position = UDim2.new(0, 0, 0.6, 0), Size = UDim2.new(1, 0, 0.32, 0), TextColor3 = Theme.Colors.TextDim, Name = "Caption", Parent = button }, 10)
	return button
end

local function paintDock(openName: string?)
	for _, t in dockTiles do
		local active = t.Window ~= nil and t.Window == openName
		t.Button.BackgroundColor3 = if active then Theme.Colors.Accent else Theme.Colors.PanelLight
		t.Button.BackgroundTransparency = if active then 0 else 0.2
		local caption = t.Button:FindFirstChild("Caption")
		if caption and caption:IsA("TextLabel") then
			caption.TextColor3 = if active then Theme.Colors.Text else Theme.Colors.TextDim
		end
	end
end

function HUD.Init(screen: ScreenGui, menu: { MenuEntry })
	local uiScale = Theme.New("UIScale", { Parent = screen })

	-- ── Status card (top-left) ──
	local _, card = Theme.Card({ Name = "Status", Position = UDim2.fromOffset(14, 12), Size = UDim2.fromOffset(284, 120), Parent = screen }, 16)
	local coin = Theme.New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(12, 12), Size = UDim2.fromOffset(40, 40), Parent = card })
	Theme.Corner(coin, 20)
	Theme.New("UIGradient", { Rotation = 45, Color = ColorSequence.new(Color3.fromRGB(255, 226, 120), Color3.fromRGB(230, 150, 40)), Parent = coin })
	Theme.Label("$", { Font = Theme.Fonts.Bold, TextColor3 = Color3.fromRGB(110, 70, 10), Parent = coin }, 24)
	nameLabel = Theme.Eyebrow("MY MUSEUM", { Position = UDim2.fromOffset(62, 12), Size = UDim2.new(1, -74, 0, 13), Parent = card })
	cashLabel = Theme.Label("$0", { Font = Theme.Fonts.Bold, TextColor3 = Theme.Colors.Text, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(62, 26), Size = UDim2.new(1, -108, 0, 28), Parent = card }, 26)
	Theme.New("UIScale", { Parent = cashLabel })
	-- "+" : buy cash / powers with Robux
	local plus = Theme.Button("+", Theme.Colors.Success, function()
		if onAddCash then
			HUD.CloseMore()
			onAddCash()
		end
	end, 24)
	plus.AnchorPoint = Vector2.new(1, 0)
	plus.Position = UDim2.new(1, -12, 0, 22)
	plus.Size = UDim2.fromOffset(34, 34)
	Theme.Corner(plus, 17)
	plus.Parent = card
	deskLabel = Theme.Label("", { TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Text, Position = UDim2.fromOffset(12, 60), Size = UDim2.new(1, -24, 0, 15), Parent = card }, 13)
	local chips = Theme.New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(12, 80), Size = UDim2.new(1, -24, 0, 20), Parent = card })
	Theme.ListLayout(chips, 6, true)
	levelLabel = chip(chips, "LV 1", Theme.Colors.Wood, 1)
	levelLabel.TextColor3 = Theme.Colors.ButtonText
	kitLabel = chip(chips, "⛏", Theme.Colors.PanelLighter, 2)

	-- ── Objective card ──
	local goalHolder, goalPanel = Theme.Card({ Name = "Objective", Position = UDim2.fromOffset(14, 142), Size = UDim2.fromOffset(284, 74), Parent = screen }, 14)
	goalFrame = goalHolder
	local bar = Theme.New("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(0, 10), Size = UDim2.new(0, 3, 1, -20), Parent = goalPanel })
	Theme.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Theme.Colors.Accent, Theme.Colors.Accent2), Parent = bar })
	Theme.Eyebrow("◆  OBJECTIVE", { Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -44, 0, 12), Parent = goalPanel })
	goalLabel = Theme.Label("", { TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Position = UDim2.fromOffset(14, 24), Size = UDim2.new(1, -40, 1, -30), Parent = goalPanel }, 13)
	local hide = Theme.Button("×", Theme.Colors.PanelLighter, function()
		objectiveDismissed = true
		refreshGoalVisibility()
	end, 11)
	hide.AnchorPoint = Vector2.new(1, 0)
	hide.Position = UDim2.new(1, -8, 0, 8)
	hide.Size = UDim2.fromOffset(20, 20)
	Theme.Corner(hide, 10)
	hide.Parent = goalPanel

	-- Honest but quiet: a small amber chip in the status card when progress
	-- can't be saved (e.g. Studio without API access), never a screen banner.
	saveWarning = Theme.Label("● Not saving", {
		Font = Theme.Fonts.Bold,
		TextColor3 = Color3.fromRGB(255, 190, 90),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -12, 0, 61),
		Size = UDim2.fromOffset(80, 13),
		Visible = false,
		Parent = card,
	}, 11)

	-- ── Floating dock (left, vertically centred) ──
	local primary, secondary = {}, {}
	for _, entry in menu do
		table.insert(if entry.Primary then primary else secondary, entry)
	end
	local tiles = #primary + (if #secondary > 0 then 1 else 0)
	local _, dock = Theme.Card({
		Name = "Menu",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.58, 0),
		Size = UDim2.fromOffset(78, tiles * 58 + 22),
		Parent = screen,
	}, 18)
	Theme.Padding(dock, 6)
	Theme.ListLayout(dock, 6).HorizontalAlignment = Enum.HorizontalAlignment.Center
	for i, entry in primary do
		local b = tile(entry, Vector2.new(52, 52), function()
			HUD.CloseMore()
			entry.OnClick()
		end)
		b.LayoutOrder = i
		b.Parent = dock
		table.insert(dockTiles, { Button = b, Window = entry.Window })
	end

	-- "More" popover with the secondary entries
	local moreHolder, morePanel = Theme.Card({
		Name = "More",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 102, 0.58, 0),
		Size = UDim2.fromOffset(3 * 62 + 2 * 6 + 28, math.ceil(#secondary / 3) * 58 + 28),
		Visible = false,
		ZIndex = 4,
		Parent = screen,
	}, 16)
	morePopover = moreHolder
	Theme.Padding(morePanel, 8)
	Theme.New("UIGridLayout", { CellSize = UDim2.fromOffset(62, 52), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder, Parent = morePanel })
	for i, entry in secondary do
		local b = tile(entry, Vector2.new(62, 52), function()
			HUD.CloseMore()
			entry.OnClick()
		end)
		b.LayoutOrder = i
		b.Parent = morePanel
		table.insert(dockTiles, { Button = b, Window = entry.Window })
	end
	if #secondary > 0 then
		local more = tile({ Icon = "•••", Text = "More", OnClick = function() end }, Vector2.new(52, 52), function()
			morePopover.Visible = not morePopover.Visible
		end)
		more.LayoutOrder = #primary + 1
		more.Parent = dock
	end
	Window.OnChanged(function(name)
		if name then
			HUD.CloseMore()
		end
		paintDock(name)
	end)

	-- Scale everything down a little on small (phone) screens
	local camera = workspace.CurrentCamera
	local function rescale()
		local size = camera.ViewportSize
		uiScale.Scale = math.clamp(math.min(size.X / 1100, size.Y / 640), 0.7, 1)
	end
	camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	rescale()

	ClientState.OnChanged(update)
end

return HUD
