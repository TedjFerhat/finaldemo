--[[
	JournalPanel
	Your collection journal:
	  • Collections — sets, what's missing, rewards (claimed automatically, once)
	  • Discoveries — every artefact in the game; undiscovered ones show "???"
	  • Statistics — your milestones
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ItemCatalog = require(Shared.ItemCatalog)
local CollectionSets = require(Shared.CollectionSets)
local Rarities = require(Shared.Rarities)
local Zones = require(Shared.Zones)
local Format = require(Shared.Format)
local Achievements = require(Shared.Achievements)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientState = require(script.Parent.Parent.ClientState)

local JournalPanel = {}

local NAME = "Journal"
local TABS = { "Collections", "Discoveries", "Clues", "Feats", "Stats" }
local tab = 1
local tabButtons: { TextButton } = {}
local body: ScrollingFrame
local gridLayout: UIGridLayout
local listLayout: UIListLayout

local function clear()
	for _, child in body:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
end

local function ownedCounts(state: any): { [string]: number }
	local counts = {}
	for _, item in state.Inventory do
		counts[item.Id] = (counts[item.Id] or 0) + 1
	end
	return counts
end

local function drawCollections(state: any)
	gridLayout.Parent = nil
	listLayout.Parent = body
	local owned = ownedCounts(state)
	for i, set in CollectionSets.List do
		local done = state.Journal.CompletedSets[set.Id] == true
		local found = 0
		for _, id in set.Items do
			if state.Journal.Discovered[id] then
				found += 1
			end
		end
		local card = Theme.New("Frame", {
			BackgroundColor3 = if done then Color3.fromRGB(70, 60, 25) else Theme.Colors.PanelLight,
			Size = UDim2.new(1, -8, 0, 96),
			LayoutOrder = i,
			Parent = body,
		})
		Theme.Corner(card, 10)
		Theme.Padding(card, 8)
		if done then
			Theme.Stroke(card, Theme.Colors.Gold, 2)
		end
		Theme.Label(("<b>%s</b>  %s"):format(set.Name, if done then "<font color=\"#A8741A\">COMPLETE</font>" else ("(%d/%d)"):format(found, #set.Items)), {
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, 0, 0, 22),
			Parent = card,
		}, 18)
		Theme.Label(("Reward: %s and +%d prestige%s"):format(Format.Cash(set.RewardCash), set.RewardPrestige, if done then " (claimed)" else ""), {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = Theme.Colors.TextDim,
			Position = UDim2.fromOffset(0, 22),
			Size = UDim2.new(1, 0, 0, 18),
			Parent = card,
		}, 14)
		local chips = Theme.New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 0, 34), Parent = card })
		Theme.ListLayout(chips, 6, true)
		for _, id in set.Items do
			local def = ItemCatalog.Get(id)
			local discovered = state.Journal.Discovered[id] ~= nil
			local chip = Theme.New("Frame", {
				BackgroundColor3 = if discovered then Theme.Colors.PanelLighter else Theme.Colors.Panel,
				Size = UDim2.new(1 / #set.Items, -6, 1, 0),
				Parent = chips,
			})
			Theme.Corner(chip, 6)
			Theme.Stroke(chip, if def then Rarities.Color(def.Rarity) else Theme.Colors.TextDim, 1.5)
			local text = if discovered and def then def.Name else "???"
			if discovered and (owned[id] or 0) > 0 then
				text ..= (" <font color=\"#2E7D32\">x%d</font>"):format(owned[id])
			end
			Theme.Label(text, { TextColor3 = if discovered then Theme.Colors.Text else Theme.Colors.TextDim, Parent = chip }, 13)
		end
	end
end

local function drawDiscoveries(state: any)
	listLayout.Parent = nil
	gridLayout.Parent = body
	for i, id in ItemCatalog.Order do
		local def = ItemCatalog.Items[id]
		local count = state.Journal.Discovered[id]
		local cell = Theme.New("Frame", {
			BackgroundColor3 = if count then Theme.Colors.PanelLight else Theme.Colors.Panel,
			LayoutOrder = i,
			Parent = body,
		})
		Theme.Corner(cell, 8)
		Theme.Stroke(cell, Rarities.Color(def.Rarity), 1.5)
		Theme.Padding(cell, 4)
		local zone = Zones.ById[def.Zone]
		local text = if count
			then ("<b>%s</b>\n<font color=\"%s\">%s</font>\nFound x%d"):format(def.Name, Theme.Hex(Rarities.Color(def.Rarity)), def.Rarity, count)
			else ("<b>???</b>\n<font color=\"%s\">%s</font>\n%s"):format(Theme.Hex(Rarities.Color(def.Rarity)), def.Rarity, if zone then zone.Name else "")
		Theme.Label(text, { TextColor3 = if count then Theme.Colors.Text else Theme.Colors.TextDim, Parent = cell }, 14)
	end
end

local function drawStats(state: any)
	gridLayout.Parent = nil
	listLayout.Parent = body
	local discovered, total = 0, #ItemCatalog.Order
	for _ in state.Journal.Discovered do
		discovered += 1
	end
	local completed = 0
	for _ in state.Journal.CompletedSets do
		completed += 1
	end
	local zones = {}
	for zoneId in state.Journal.ZonesVisited do
		table.insert(zones, Zones.ById[zoneId] and Zones.ById[zoneId].Name or zoneId)
	end
	local lines = {
		("Title: <b>%s</b>"):format(state.Title or ""),
		("Prestige: <b>%d</b>"):format(state.Prestige or 0),
		("Artefacts discovered: <b>%d / %d</b>"):format(discovered, total),
		("Collections completed: <b>%d / %d</b>"):format(completed, #CollectionSets.List),
		("Searches made: <b>%d</b>"):format(state.Stats.Searches),
		("Items found: <b>%d</b>"):format(state.Stats.ItemsFound),
		("Items sold: <b>%d</b>"):format(state.Stats.ItemsSold),
		("Ticket desk earnings collected: <b>%s</b>"):format(Format.Cash(state.Stats.TotalCollected)),
		("Total money earned: <b>%s</b>"):format(Format.Cash(state.Stats.TotalEarned)),
		("Excavations: <b>%d</b> (%d perfect)"):format(state.Stats.Excavated or 0, state.Stats.PerfectRecoveries or 0),
		("Market: %d sold, %d bought · Trades: %d"):format(state.Stats.MarketSales or 0, state.Stats.MarketPurchases or 0, state.Stats.Trades or 0),
		("Zones visited: <b>%s</b>"):format(if #zones > 0 then table.concat(zones, ", ") else "none yet"),
	}
	for i, line in lines do
		Theme.Label(line, {
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(1, -8, 0, 26),
			LayoutOrder = i,
			Parent = body,
		}, 18)
	end
end

local PUZZLE_NAMES = {
	ruins_glyphs = "The Watchers' riddle (Forgotten Ruins)",
	jungle_guardians = "The Guardian Pillars (Jungle Temple)",
	jungle_root_chamber = "The hidden Root Chamber (Jungle Temple)",
}

local function drawClues(state: any)
	gridLayout.Parent = nil
	listLayout.Parent = body
	local order = 0
	local function line(text: string, color: Color3?, height: number?)
		order += 1
		Theme.Label(text, {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			TextColor3 = color or Theme.Colors.Text,
			Size = UDim2.new(1, -8, 0, height or 22),
			LayoutOrder = order,
			Parent = body,
		}, 15)
	end
	line("<b>Clues</b>", Theme.Colors.Gold)
	local any = false
	for _, text in state.Journal.Clues or {} do
		if type(text) == "string" then
			any = true
			line("• " .. text, Theme.Colors.Parchment, 44)
		end
	end
	if not any then
		line("No clues yet. Read inscriptions (press E on steles and statues) on your expeditions.", Theme.Colors.TextDim, 40)
	end
	line("<b>Secrets solved</b>", Theme.Colors.Gold)
	local solved = false
	for id, count in state.Journal.Puzzles or {} do
		solved = true
		line(("• %s ×%d"):format(PUZZLE_NAMES[id] or id, tonumber(count) or 1))
	end
	if not solved then
		line("None yet.", Theme.Colors.TextDim)
	end
	line("<b>Excavations</b>", Theme.Colors.Gold)
	for _, z in Zones.List do
		line(("• %s: %d completed"):format(z.Name, (state.Journal.Excavations or {})[z.Id] or 0))
	end
end

local function drawAchievements(state: any)
	gridLayout.Parent = nil
	listLayout.Parent = body
	for i, a in Achievements.List do
		local got = state.Achievements and state.Achievements[a.Id]
		local row = Theme.New("Frame", { BackgroundColor3 = if got then Color3.fromRGB(70, 60, 25) else Theme.Colors.PanelLight, Size = UDim2.new(1, -8, 0, 44), LayoutOrder = i, Parent = body })
		Theme.Corner(row, 8)
		Theme.Padding(row, 6)
		Theme.Label(("%s <b>%s</b> — %s  <font color=\"#8A6A4A\">(+%s)</font>"):format(if got then "★" else "☆", a.Name, a.Description, Format.Cash(a.RewardCash)), {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = if got then Theme.Colors.Gold else Theme.Colors.Text,
			Parent = row,
		}, 15)
	end
end

local function refresh()
	local state = ClientState.Get()
	if not state or not body then
		return
	end
	for i, button in tabButtons do
		button.BackgroundColor3 = if i == tab then Theme.Colors.Gold else Theme.Colors.PanelLighter
	end
	clear()
	if tab == 1 then
		drawCollections(state)
	elseif tab == 2 then
		drawDiscoveries(state)
	elseif tab == 3 then
		drawClues(state)
	elseif tab == 4 then
		drawAchievements(state)
	else
		drawStats(state)
	end
end

function JournalPanel.Init()
	local content = Window.Create(NAME, "Collector's Journal", refresh)
	local tabsRow = Theme.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 38), Parent = content })
	Theme.ListLayout(tabsRow, 6, true)
	for i, name in TABS do
		local button = Theme.Button(name, Theme.Colors.PanelLighter, function()
			tab = i
			refresh()
		end, 16)
		button.Size = UDim2.new(1 / #TABS, -6, 1, 0)
		button.Parent = tabsRow
		tabButtons[i] = button
	end
	body = Theme.Scroller({ Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 1, -46) })
	body.Parent = content
	Theme.Padding(body, 4)
	listLayout = Theme.ListLayout(body, 8)
	gridLayout = Theme.New("UIGridLayout", {
		CellSize = UDim2.fromOffset(150, 74),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			refresh()
		end
	end)
end

function JournalPanel.Open()
	Window.Open(NAME)
end

return JournalPanel
