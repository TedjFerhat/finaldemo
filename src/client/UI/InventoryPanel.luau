--[[
	InventoryPanel
	Shows every item you own with a 3D preview, rarity, value and status.
	Filter by rarity/category, sort by value/rarity/name/newest.
	Select an item to sell it, lock it, or (in placement mode) put it on display.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ItemCatalog = require(Shared.ItemCatalog)
local Rarities = require(Shared.Rarities)
local CollectionSets = require(Shared.CollectionSets)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ItemPreview = require(script.Parent.ItemPreview)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)
local MarketPanel = require(script.Parent.MarketPanel)

local InventoryPanel = {}

local NAME = "Inventory"
local SORTS = { "Value", "Rarity", "Name", "Newest" }

local rarityFilters = { "All" }
for _, r in Rarities.List do
	table.insert(rarityFilters, r.Id)
end
local categoryFilters = { "All" }
for category in ItemCatalog.Categories do
	table.insert(categoryFilters, category)
end
table.sort(categoryFilters, function(a, b)
	if a == "All" then
		return true
	elseif b == "All" then
		return false
	end
	return a < b
end)

local filterRarity = 1
local filterCategory = 1
local sortIndex = 1
local selectedUid: string? = nil
local placement: { SlotId: string, SlotType: string }? = nil

local grid: ScrollingFrame
local header: TextLabel
local capacityLabel: TextLabel
local rarityButton: TextButton
local categoryButton: TextButton
local sortButton: TextButton
local details: Frame
local cards: { [string]: Frame } = {}

local refresh: () -> ()

local function cycle(index: number, count: number): number
	return (index % count) + 1
end

-- ── Item card ──────────────────────────────────────────────────────────────
local function makeCard(item: any): Frame
	local def = ItemCatalog.Get(item.Id)
	local rarityColor = Rarities.Color(def and def.Rarity or "Common")
	local card = Theme.New("TextButton", {
		Name = item.Uid,
		AutoButtonColor = true,
		Text = "",
		BackgroundColor3 = Theme.Colors.PanelLight,
	})
	Theme.Corner(card, 10)
	local stroke = Theme.Stroke(card, rarityColor, 2)
	stroke.Name = "RarityStroke"

	local preview = ItemPreview.Create(item.Id)
	preview.Size = UDim2.new(1, -8, 0.62, 0)
	preview.Position = UDim2.fromOffset(4, 4)
	preview.Parent = card

	local nameLabel = Theme.Label(def and def.Name or item.Id, {
		Name = "ItemName",
		Font = Theme.Fonts.Bold,
		Position = UDim2.new(0, 4, 0.63, 0),
		Size = UDim2.new(1, -8, 0.2, 0),
	}, 14)
	nameLabel.Parent = card
	local valueLabel = Theme.Label("", {
		Name = "Info",
		TextColor3 = rarityColor,
		Position = UDim2.new(0, 4, 0.83, 0),
		Size = UDim2.new(1, -8, 0.15, 0),
	}, 13)
	valueLabel.Parent = card

	local badge = Theme.Label("", {
		Name = "Badge",
		Font = Theme.Fonts.Bold,
		BackgroundTransparency = 0.15,
		BackgroundColor3 = Theme.Colors.Panel,
		Position = UDim2.fromOffset(4, 4),
		Size = UDim2.new(1, -8, 0, 18),
		Visible = false,
	}, 12)
	Theme.Corner(badge, 6)
	badge.Parent = card

	card.Activated:Connect(function()
		selectedUid = item.Uid
		refresh()
	end)
	return card
end

local function updateCard(card: Frame, item: any)
	local def = ItemCatalog.Get(item.Id)
	local info = card:FindFirstChild("Info") :: TextLabel
	local value = if def then ItemCatalog.InstanceValue(def, item.Condition, item.Charges) else 0
	info.Text = ("%s · %s"):format(if item.Condition then item.Condition else (def and def.Rarity or "?"), Format.Cash(value))
	local badge = card:FindFirstChild("Badge") :: TextLabel
	local RESERVED = { Listing = "ON MARKET", Trade = "IN TRADE", Heist = "BEING STOLEN", Loadout = "IN LOADOUT" }
	if item.Reserved then
		badge.Visible = true
		badge.Text = RESERVED[item.Reserved] or "BUSY"
		badge.TextColor3 = Color3.fromRGB(255, 170, 120)
	elseif item.DisplayedIn then
		badge.Visible = true
		badge.Text = "ON DISPLAY"
		badge.TextColor3 = Theme.Colors.Gold
	elseif item.Charges then
		badge.Visible = true
		badge.Text = ("%d CHARGES"):format(item.Charges)
		badge.TextColor3 = Color3.fromRGB(150, 200, 255)
	elseif item.Locked then
		badge.Visible = true
		badge.Text = "LOCKED"
		badge.TextColor3 = Theme.Colors.TextDim
	else
		badge.Visible = false
	end
	card.BackgroundColor3 = if item.Uid == selectedUid then Theme.Colors.PanelLighter else Theme.Colors.PanelLight
end

-- ── Filtering & sorting ────────────────────────────────────────────────────
local function visibleItems(state: any): { any }
	local list = {}
	for _, item in state.Inventory do
		local def = ItemCatalog.Get(item.Id)
		if def then
			local ok = true
			if filterRarity > 1 and def.Rarity ~= rarityFilters[filterRarity] then
				ok = false
			end
			if filterCategory > 1 and def.Category ~= categoryFilters[filterCategory] then
				ok = false
			end
			if placement then
				-- Placement mode: only items that fit this slot and aren't displayed
				if item.DisplayedIn or item.Reserved or not ItemCatalog.FitsSlot(def, placement.SlotType) then
					ok = false
				end
			end
			if ok then
				table.insert(list, item)
			end
		end
	end
	local sort = SORTS[sortIndex]
	table.sort(list, function(a, b)
		local da, db = ItemCatalog.Get(a.Id) :: any, ItemCatalog.Get(b.Id) :: any
		if sort == "Value" and da.Value ~= db.Value then
			return da.Value > db.Value
		elseif sort == "Rarity" and da.Rarity ~= db.Rarity then
			return Rarities.Order(da.Rarity) > Rarities.Order(db.Rarity)
		elseif sort == "Newest" and a.Found ~= b.Found then
			return a.Found > b.Found
		elseif da.Name ~= db.Name then
			return da.Name < db.Name
		end
		return a.Uid < b.Uid
	end)
	return list
end

-- ── Details pane ───────────────────────────────────────────────────────────
local function clearDetails()
	for _, child in details:GetChildren() do
		if not child:IsA("UIListLayout") and not child:IsA("UIPadding") and not child:IsA("UICorner") then
			child:Destroy()
		end
	end
end

local function detailLine(text: string, height: number, order: number, props: { [string]: any }?, maxSize: number?): TextLabel
	local label = Theme.Label(text, {
		Size = UDim2.new(1, 0, 0, height),
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = order,
	}, maxSize or 16)
	if props then
		for k, v in props do
			(label :: any)[k] = v
		end
	end
	label.Parent = details
	return label
end

local function showDetails(state: any)
	clearDetails()
	local item = selectedUid and ClientState.FindItem(selectedUid)
	local def = item and ItemCatalog.Get(item.Id)
	if not item or not def then
		detailLine(if placement then "Choose an exhibit for this display." else "Select an item to see its details.", 60, 1, { TextColor3 = Theme.Colors.TextDim, TextWrapped = true })
		return
	end
	local color = Rarities.Color(def.Rarity)
	local preview = ItemPreview.Create(def.Id, true)
	preview.Size = UDim2.new(1, 0, 0, 110)
	preview.LayoutOrder = 0
	preview.Parent = details
	detailLine(def.Name, 26, 1, { Font = Theme.Fonts.Title, TextColor3 = Theme.Colors.Gold }, 22)
	detailLine(("<font color=\"%s\"><b>%s</b></font> · %s"):format(Theme.Hex(color), def.Rarity, ItemCatalog.CategoryName(def.Category)), 18, 2)
	local value = ItemCatalog.InstanceValue(def, item.Condition, item.Charges)
	if def.Gadget then
		detailLine(("Heist gear · %d / %d charges · worth %s"):format(item.Charges or 0, def.Gadget.Charges, Format.Cash(value)), 18, 3)
	else
		detailLine(("<b>%s</b> condition · Value %s · Earns %s/min on display"):format(item.Condition or "Clean", Format.Cash(value), Format.Cash(ItemCatalog.InstanceIncome(def, item.Condition))), 18, 3)
	end
	if item.Provenance then
		detailLine("Provenance: " .. item.Provenance, 18, 3, { TextColor3 = Theme.Colors.TextDim })
	end
	local setName = def.Set and CollectionSets.ById[def.Set] and CollectionSets.ById[def.Set].Name
	detailLine(("Fits: %s%s"):format(table.concat(def.Display, ", "), if def.RequiresSecurity then " (needs Security)" else ""), 18, 4, { TextColor3 = Theme.Colors.TextDim })
	if setName then
		detailLine("Collection: " .. setName, 18, 5, { TextColor3 = Theme.Colors.TextDim })
	end
	detailLine(def.Lore, 54, 6, { TextColor3 = Theme.Colors.Parchment, TextWrapped = true, Font = Enum.Font.Merriweather }, 14)
	if item.DisplayedIn then
		detailLine("Currently on display. Press E at the display to take it down.", 34, 7, { TextColor3 = Theme.Colors.Gold, TextWrapped = true }, 14)
	end

	local row = Theme.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 42), LayoutOrder = 8, Parent = details })
	Theme.ListLayout(row, 6, true)
	if placement then
		local placeButton = Theme.Button("Place Here", Theme.Colors.Success, function()
			local current = placement
			if not current then
				return
			end
			local result = ClientNet.Call("PlaceItem", true, current.SlotId, item.Uid)
			if result.Ok then
				placement = nil
				Window.Close()
			end
		end)
		placeButton.Size = UDim2.new(1, 0, 1, 0)
		placeButton.Parent = row
	else
		local price = math.floor(value * Config.NpcSellRate)
		local sell = Theme.Button("Sell " .. Format.Cash(price), Theme.Colors.Danger, function()
			ClientNet.Call("SellItem", true, item.Uid)
			selectedUid = nil
		end, 15)
		sell.Size = UDim2.new(0.38, -4, 1, 0)
		Theme.SetButtonEnabled(sell, not item.Locked and not item.Reserved and item.DisplayedIn == nil and def.Sellable, Theme.Colors.Danger)
		sell.Parent = row
		local market = Theme.Button("Market", Theme.Colors.Success, function()
			MarketPanel.OpenSell(item.Uid)
		end, 15)
		market.Size = UDim2.new(0.32, -4, 1, 0)
		Theme.SetButtonEnabled(market, def.Tradable and not item.Bound and not item.Locked and not item.Reserved, Theme.Colors.Success)
		market.Parent = row
		local lock = Theme.Button(if item.Locked then "Unlock" else "Lock", Theme.Colors.Blue, function()
			ClientNet.Call("ToggleLock", false, item.Uid)
		end, 15)
		lock.Size = UDim2.new(0.3, -4, 1, 0)
		lock.Parent = row
	end
	local _ = state
end

-- ── Main refresh ───────────────────────────────────────────────────────────
refresh = function()
	local state = ClientState.Get()
	if not state or not grid then
		return
	end
	rarityButton.Text = "Rarity: " .. rarityFilters[filterRarity]
	categoryButton.Text = "Type: " .. (if filterCategory == 1 then "All" else ItemCatalog.CategoryName(categoryFilters[filterCategory]))
	sortButton.Text = "Sort: " .. SORTS[sortIndex]
	capacityLabel.Text = ("Storage %d / %d"):format(state.StorageCount or 0, state.Capacity or 0)
	capacityLabel.TextColor3 = if (state.StorageCount or 0) >= (state.Capacity or 1) then Theme.Colors.Danger else Theme.Colors.TextDim
	header.Text = if placement then ("Choose an exhibit for this <b>%s</b>"):format(placement.SlotType) else "Your collection"

	if selectedUid and not ClientState.FindItem(selectedUid) then
		selectedUid = nil
	end

	local items = visibleItems(state)
	local seen: { [string]: boolean } = {}
	for index, item in items do
		seen[item.Uid] = true
		local card = cards[item.Uid]
		if not card then
			card = makeCard(item)
			cards[item.Uid] = card
			card.Parent = grid
		end
		card.LayoutOrder = index
		card.Visible = true
		updateCard(card, item)
	end
	for uid, card in cards do
		if not seen[uid] then
			if ClientState.FindItem(uid) then
				card.Visible = false -- filtered out, keep for later
			else
				card:Destroy()
				cards[uid] = nil
			end
		end
	end
	if #items == 0 then
		header.Text ..= if placement then "  —  nothing fits here yet. Go exploring!" else "  —  empty"
	end
	showDetails(state)
end

-- ── Public ─────────────────────────────────────────────────────────────────
function InventoryPanel.Init()
	local content = Window.Create(NAME, "Inventory", function()
		refresh()
	end)
	Window.OnChanged(function(openName)
		if openName ~= NAME then
			placement = nil
		end
	end)

	local top = Theme.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = content })
	Theme.ListLayout(top, 6, true)
	rarityButton = Theme.Button("Rarity: All", Theme.Colors.PanelLighter, function()
		filterRarity = cycle(filterRarity, #rarityFilters)
		refresh()
	end, 14)
	rarityButton.Size = UDim2.new(0.24, 0, 1, 0)
	rarityButton.Parent = top
	categoryButton = Theme.Button("Type: All", Theme.Colors.PanelLighter, function()
		filterCategory = cycle(filterCategory, #categoryFilters)
		refresh()
	end, 14)
	categoryButton.Size = UDim2.new(0.3, 0, 1, 0)
	categoryButton.Parent = top
	sortButton = Theme.Button("Sort: Value", Theme.Colors.PanelLighter, function()
		sortIndex = cycle(sortIndex, #SORTS)
		refresh()
	end, 14)
	sortButton.Size = UDim2.new(0.2, 0, 1, 0)
	sortButton.Parent = top
	capacityLabel = Theme.Label("", { Size = UDim2.new(0.22, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Right }, 15)
	capacityLabel.Parent = top

	header = Theme.Label("Your collection", {
		Position = UDim2.fromOffset(0, 40),
		Size = UDim2.new(0.6, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextColor3 = Theme.Colors.Gold,
	}, 16)
	header.Parent = content

	grid = Theme.Scroller({ Position = UDim2.fromOffset(0, 66), Size = UDim2.new(0.6, -8, 1, -66) })
	grid.Parent = content
	Theme.New("UIGridLayout", {
		CellSize = UDim2.fromOffset(104, 132),
		CellPadding = UDim2.fromOffset(8, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	Theme.Padding(grid, 4)

	details = Theme.Scroller({
		BackgroundTransparency = 0,
		BackgroundColor3 = Theme.Colors.PanelLight,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, 0, 0, 40),
		Size = UDim2.new(0.4, 0, 1, -40),
	}) :: any
	details.Parent = content
	Theme.Corner(details, 10)
	Theme.Padding(details, 10)
	Theme.ListLayout(details, 4)

	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			refresh()
		end
	end)
end

function InventoryPanel.Open()
	placement = nil
	Window.SetTitle(NAME, "Inventory")
	Window.Open(NAME)
end

-- Opened by the server when you press E on an empty display.
function InventoryPanel.OpenForPlacement(slotId: string, slotType: string)
	Window.Open(NAME) -- (opening resets placement via OnChanged, so set it after)
	placement = { SlotId = slotId, SlotType = slotType }
	selectedUid = nil
	Window.SetTitle(NAME, "Place an Exhibit")
	refresh()
end

return InventoryPanel
