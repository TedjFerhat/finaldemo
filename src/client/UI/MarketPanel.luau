--[[
	MarketPanel — the Collectors' Market
	Tabs: Browse (search, category/rarity filters, price range, sort, pages)
	      Sell (pick an item, set a price; limits and the fee are shown first)
	      Mine (active listings with Cancel, plus your sales/purchase history)
	The server re-checks everything; buttons lock while a request is running.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ItemCatalog = require(Shared.ItemCatalog)
local Rarities = require(Shared.Rarities)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local Dialog = require(script.Parent.Dialog)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local MarketPanel = {}

local NAME = "Market"
local MC = Config.Market
local TABS = { "Browse", "Sell", "Mine" }
local SORTS = { "Newest", "PriceLow", "PriceHigh", "Rarity" }
local SORT_NAMES = { Newest = "Newest", PriceLow = "Price ↑", PriceHigh = "Price ↓", Rarity = "Rarity" }

local tab = 1
local tabButtons: { TextButton } = {}
local body: Frame
local busy = false
local query = { Search = "", Category = "All", Rarity = "All", MinPrice = 0, MaxPrice = 0, Sort = "Newest", Page = 1 }
local sellUid: string? = nil

local rarityList = { "All" }
for _, r in Rarities.List do
	table.insert(rarityList, r.Id)
end
local categoryList = { "All" }
for c in ItemCatalog.Categories do
	table.insert(categoryList, c)
end
table.sort(categoryList, function(a, b)
	if a == "All" then
		return true
	elseif b == "All" then
		return false
	end
	return a < b
end)

local refresh: () -> ()

local function nextIn(list: { string }, value: string): string
	local i = table.find(list, value) or 0
	return list[(i % #list) + 1]
end

local function call(name: string, ...: any): any
	if busy then
		return { Ok = false }
	end
	busy = true
	local r = ClientNet.Call(name, true, ...)
	busy = false
	return r
end

local function clear()
	for _, c in body:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function itemLine(itemId: string, condition: string?, charges: number?): string
	local def = ItemCatalog.Get(itemId)
	if not def then
		return itemId
	end
	local extra = if charges then (" · %d charges"):format(charges) elseif condition then " · " .. condition else ""
	return ("<b>%s</b>  <font color=\"%s\">%s</font>%s"):format(def.Name, Theme.Hex(Rarities.Color(def.Rarity)), def.Rarity, extra)
end

local function textBox(parent: Instance, placeholder: string, text: string, size: UDim2, order: number): TextBox
	local box = Theme.New("TextBox", {
		BackgroundColor3 = Theme.Colors.PanelLighter,
		PlaceholderText = placeholder,
		Text = text,
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Body,
		TextSize = 15,
		TextColor3 = Theme.Colors.Text,
		PlaceholderColor3 = Theme.Colors.TextDim,
		Size = size,
		LayoutOrder = order,
		Parent = parent,
	})
	Theme.Corner(box, 6)
	return box
end

-- ── Browse ─────────────────────────────────────────────────────────────────
local function drawBrowse()
	local filters = Theme.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 34), Parent = body })
	Theme.ListLayout(filters, 6, true)
	local search = textBox(filters, "Search name…", query.Search, UDim2.new(0.22, 0, 1, 0), 1)
	search.FocusLost:Connect(function()
		query.Search = search.Text
		query.Page = 1
		refresh()
	end)
	local cat = Theme.Button("Type: " .. query.Category, Theme.Colors.PanelLighter, function()
		query.Category = nextIn(categoryList, query.Category)
		query.Page = 1
		refresh()
	end, 13)
	cat.Size = UDim2.new(0.18, 0, 1, 0)
	cat.LayoutOrder = 2
	cat.Parent = filters
	local rar = Theme.Button("Rarity: " .. query.Rarity, Theme.Colors.PanelLighter, function()
		query.Rarity = nextIn(rarityList, query.Rarity)
		query.Page = 1
		refresh()
	end, 13)
	rar.Size = UDim2.new(0.17, 0, 1, 0)
	rar.LayoutOrder = 3
	rar.Parent = filters
	local minBox = textBox(filters, "Min $", if query.MinPrice > 0 then tostring(query.MinPrice) else "", UDim2.new(0.1, 0, 1, 0), 4)
	local maxBox = textBox(filters, "Max $", if query.MaxPrice > 0 then tostring(query.MaxPrice) else "", UDim2.new(0.1, 0, 1, 0), 5)
	local function applyPrices()
		query.MinPrice = tonumber(minBox.Text) or 0
		query.MaxPrice = tonumber(maxBox.Text) or 0
		query.Page = 1
		refresh()
	end
	minBox.FocusLost:Connect(applyPrices)
	maxBox.FocusLost:Connect(applyPrices)
	local sort = Theme.Button("Sort: " .. SORT_NAMES[query.Sort], Theme.Colors.PanelLighter, function()
		query.Sort = nextIn(SORTS, query.Sort)
		refresh()
	end, 13)
	sort.Size = UDim2.new(0.17, 0, 1, 0)
	sort.LayoutOrder = 6
	sort.Parent = filters

	local listFrame = Theme.Scroller({ Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 1, -84) })
	listFrame.Parent = body
	Theme.ListLayout(listFrame, 6)
	Theme.Padding(listFrame, 4)
	local status = Theme.Label("Loading…", { Size = UDim2.new(1, -8, 0, 24), TextColor3 = Theme.Colors.TextDim, Parent = listFrame }, 15)

	local r = ClientNet.Call("MarketBrowse", false, query)
	if not r.Ok or type(r.Data) ~= "table" then
		status.Text = tostring(r.Message or "The market is unavailable right now.")
		return
	end
	local data = r.Data
	status.Text = if data.Total == 0 then "No listings match. Try other filters — or be the first to sell!" else ("%d listing(s)%s"):format(data.Total, if data.Durable then "" else " (local test mode — this server only)")
	for i, row in data.Rows do
		local f = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, -8, 0, 52), LayoutOrder = i + 1, Parent = listFrame })
		Theme.Corner(f, 8)
		Theme.Padding(f, 6)
		Theme.Label(itemLine(row.ItemId, row.Condition, row.Charges) .. ("\n<font color=\"#8A6A4A\">Seller: %s</font>"):format(tostring(row.SellerName)), {
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.68, 0, 1, 0),
			Parent = f,
		}, 15)
		local b = Theme.Button(if row.IsMine then "Yours" else Format.Cash(row.Price), Theme.Colors.Success, function()
			Dialog.Choice("Buy " .. tostring(row.Name) .. "?", ("Price: %s\nThe seller receives it minus a %d%% market fee."):format(Format.Cash(row.Price), math.floor(MC.FeeRate * 100)), {
				{ Text = "Buy", Color = Theme.Colors.Success, OnClick = function()
					call("MarketBuy", row.Id)
					refresh()
				end },
				{ Text = "Cancel", Color = Theme.Colors.PanelLighter },
			})
		end, 16)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, 0, 0.5, 0)
		b.Size = UDim2.new(0.28, 0, 0, 38)
		local state = ClientState.Get()
		Theme.SetButtonEnabled(b, not row.IsMine and state ~= nil and state.Cash >= row.Price, Theme.Colors.Success)
		b.Parent = f
	end
	local pager = Theme.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 38), Parent = body })
	Theme.ListLayout(pager, 8, true).HorizontalAlignment = Enum.HorizontalAlignment.Center
	local pages = math.max(1, math.ceil(data.Total / data.PageSize))
	local prev = Theme.Button("◀ Prev", Theme.Colors.PanelLighter, function()
		query.Page = math.max(1, query.Page - 1)
		refresh()
	end, 14)
	prev.Size = UDim2.fromOffset(100, 36)
	Theme.SetButtonEnabled(prev, query.Page > 1, Theme.Colors.PanelLighter)
	prev.Parent = pager
	Theme.Label(("Page %d / %d"):format(query.Page, pages), { Size = UDim2.fromOffset(110, 36), LayoutOrder = 1, Parent = pager }, 15)
	local nxt = Theme.Button("Next ▶", Theme.Colors.PanelLighter, function()
		query.Page = math.min(pages, query.Page + 1)
		refresh()
	end, 14)
	nxt.Size = UDim2.fromOffset(100, 36)
	nxt.LayoutOrder = 2
	Theme.SetButtonEnabled(nxt, query.Page < pages, Theme.Colors.PanelLighter)
	nxt.Parent = pager
end

-- ── Sell ───────────────────────────────────────────────────────────────────
local function sellable(item: any): boolean
	local def = ItemCatalog.Get(item.Id)
	return def ~= nil and def.Tradable and not item.Bound and not item.Locked and not item.Reserved
end

local function valueOf(item: any): number
	local def = ItemCatalog.Get(item.Id)
	return if def then ItemCatalog.InstanceValue(def, item.Condition, item.Charges) else 0
end

local function drawSell()
	local state = ClientState.Get()
	if not state then
		return
	end
	local left = Theme.Scroller({ Size = UDim2.new(0.55, -6, 1, 0) })
	left.Parent = body
	Theme.ListLayout(left, 6)
	Theme.Padding(left, 4)
	local items = {}
	for _, item in state.Inventory do
		if sellable(item) then
			table.insert(items, item)
		end
	end
	table.sort(items, function(a, b)
		return valueOf(a) > valueOf(b)
	end)
	if #items == 0 then
		Theme.Label("Nothing to sell. (Locked, bound or busy items can't be listed.)", { Size = UDim2.new(1, -8, 0, 40), TextWrapped = true, TextColor3 = Theme.Colors.TextDim, Parent = left }, 14)
	end
	for i, item in items do
		local b = Theme.Button(itemLine(item.Id, item.Condition, item.Charges) .. (if item.DisplayedIn then "  <font color=\"#A8741A\">(on display)</font>" else ""), if item.Uid == sellUid then Theme.Colors.PanelLighter else Theme.Colors.PanelLight, function()
			sellUid = item.Uid
			refresh()
		end, 14)
		b.Size = UDim2.new(1, -8, 0, 40)
		b.LayoutOrder = i
		b.TextXAlignment = Enum.TextXAlignment.Left
		b.Parent = left
	end

	local right = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.45, 0, 1, 0), Parent = body })
	Theme.Corner(right, 10)
	Theme.Padding(right, 10)
	local chosen = nil
	for _, item in items do
		if item.Uid == sellUid then
			chosen = item
		end
	end
	if not chosen then
		Theme.Label("Pick an item on the left to list it.", { TextColor3 = Theme.Colors.TextDim, Size = UDim2.new(1, 0, 0, 40), TextWrapped = true, Parent = right }, 15)
		return
	end
	local value = valueOf(chosen)
	local low = math.max(10, math.floor(value * MC.MinPriceRate))
	local high = math.min(MC.AbsoluteMaxPrice, math.max(low, math.floor(value * MC.MaxPriceRate)))
	Theme.Label(itemLine(chosen.Id, chosen.Condition, chosen.Charges), { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Parent = right }, 16)
	Theme.Label(("Estimated value %s · NPC buyers pay %s\nAllowed price: %s – %s"):format(Format.Cash(value), Format.Cash(math.floor(value * Config.NpcSellRate)), Format.Cash(low), Format.Cash(high)), {
		Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.TextDim, TextWrapped = true, Parent = right,
	}, 14)
	local box = textBox(right, "Price", tostring(math.max(low, value)), UDim2.new(1, 0, 0, 36), 0)
	box.Position = UDim2.fromOffset(0, 72)
	local feeLabel = Theme.Label("", { Position = UDim2.fromOffset(0, 112), Size = UDim2.new(1, 0, 0, 36), TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Parent = right }, 14)
	local function updateFee()
		local price = math.floor(tonumber(box.Text) or 0)
		local fee = math.floor(price * MC.FeeRate)
		feeLabel.Text = ("Fee if it sells: %s (%d%%) › you receive <b>%s</b>%s"):format(Format.Cash(fee), math.floor(MC.FeeRate * 100), Format.Cash(price - fee), if chosen.DisplayedIn then "\nIt will be taken off display." else "")
	end
	box:GetPropertyChangedSignal("Text"):Connect(updateFee)
	updateFee()
	local list = Theme.Button("List for sale", Theme.Colors.Success, function()
		local price = math.floor(tonumber(box.Text) or 0)
		local r = call("MarketCreate", chosen.Uid, price)
		if r.Ok then
			sellUid = nil
			tab = 3
		end
		refresh()
	end, 18)
	list.AnchorPoint = Vector2.new(0, 1)
	list.Position = UDim2.fromScale(0, 1)
	list.Size = UDim2.new(1, 0, 0, 44)
	list.Parent = right
end

-- ── Mine ───────────────────────────────────────────────────────────────────
local function drawMine()
	local scroll = Theme.Scroller()
	scroll.Parent = body
	Theme.ListLayout(scroll, 6)
	Theme.Padding(scroll, 4)
	local r = ClientNet.Call("MarketMine", false)
	if not r.Ok or type(r.Data) ~= "table" then
		Theme.Label(tostring(r.Message or "Unavailable"), { Size = UDim2.new(1, -8, 0, 24), Parent = scroll }, 15)
		return
	end
	local data = r.Data
	Theme.Label(("<b>Active listings</b> (%d / %d)"):format(#data.Listings, data.MaxListings), { Size = UDim2.new(1, -8, 0, 24), LayoutOrder = 0, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold, Parent = scroll }, 16)
	for i, l in data.Listings do
		local f = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, -8, 0, 48), LayoutOrder = i, Parent = scroll })
		Theme.Corner(f, 8)
		Theme.Padding(f, 6)
		Theme.Label(itemLine(l.ItemId, l.Condition, nil) .. ("\n<font color=\"#8A6A4A\">%s%s</font>"):format(Format.Cash(l.Price), if l.Uncertain then " · confirming…" else ""), { TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.7, 0, 1, 0), Parent = f }, 15)
		local b = Theme.Button("Cancel", Theme.Colors.Danger, function()
			call("MarketCancel", l.Id)
			refresh()
		end, 15)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, 0, 0.5, 0)
		b.Size = UDim2.new(0.25, 0, 0, 36)
		b.Parent = f
	end
	Theme.Label("<b>History</b>", { Size = UDim2.new(1, -8, 0, 24), LayoutOrder = 100, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold, Parent = scroll }, 16)
	for i, h in data.History or {} do
		local def = ItemCatalog.Get(h.ItemId)
		local text = if h.Kind == "Sold"
			then ("Sold %s to %s for %s (fee %s)"):format(def and def.Name or "?", tostring(h.Other), Format.Cash(h.Price or 0), Format.Cash(h.Fee or 0))
			else ("Bought %s from %s for %s"):format(def and def.Name or "?", tostring(h.Other), Format.Cash(h.Price or 0))
		Theme.Label(text, { Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 100 + i, TextXAlignment = Enum.TextXAlignment.Left, Parent = scroll }, 14)
	end
end

refresh = function()
	if not body then
		return
	end
	for i, b in tabButtons do
		b.BackgroundColor3 = if i == tab then Theme.Colors.Gold else Theme.Colors.PanelLighter
	end
	clear()
	if tab == 1 then
		drawBrowse()
	elseif tab == 2 then
		drawSell()
	else
		drawMine()
	end
end

function MarketPanel.Init()
	local content = Window.Create(NAME, "Collectors' Market", refresh)
	local row = Theme.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = content })
	Theme.ListLayout(row, 6, true)
	for i, name in TABS do
		local b = Theme.Button(if name == "Mine" then "My listings" else name, Theme.Colors.PanelLighter, function()
			tab = i
			refresh()
		end, 16)
		b.Size = UDim2.new(1 / #TABS, -6, 1, 0)
		b.Parent = row
		tabButtons[i] = b
	end
	body = Theme.New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), Parent = content })
	Remotes.Event("MarketChanged").OnClientEvent:Connect(function()
		if Window.IsOpen(NAME) and tab ~= 1 then
			refresh()
		end
	end)
end

function MarketPanel.Open()
	Window.Open(NAME)
end

-- Opened from the inventory: go straight to "Sell" with an item chosen.
function MarketPanel.OpenSell(uid: string)
	sellUid = uid
	tab = 2
	Window.Open(NAME)
end

return MarketPanel
