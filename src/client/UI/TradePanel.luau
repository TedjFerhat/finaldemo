--[[
	TradePanel — direct trades
	Left: your offer (tap items to add/remove, type a cash amount).
	Right: their offer, live. Lock › both Confirm › the server swaps
	everything at once. Any change unlocks both sides.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ItemCatalog = require(Shared.ItemCatalog)
local Rarities = require(Shared.Rarities)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local Dialog = require(script.Parent.Dialog)
local Notifications = require(script.Parent.Notifications)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local TradePanel = {}

local NAME = "Trade"
local current: any = nil
local mineFrame: ScrollingFrame
local theirsFrame: ScrollingFrame
local pickFrame: ScrollingFrame
local cashBox: TextBox
local statusLabel: TextLabel
local lockButton: TextButton
local confirmButton: TextButton
local theirTitle: TextLabel

local function line(it: any): string
	local def = ItemCatalog.Get(it.Id)
	local color = if def then Theme.Hex(Rarities.Color(def.Rarity)) else "#4A2A16"
	local extra = if it.Charges then (" · %d ch"):format(it.Charges) elseif it.Condition then " · " .. it.Condition else ""
	return ("<font color=\"%s\">%s</font>%s"):format(color, tostring(it.Name or (def and def.Name) or it.Id), extra)
end

local function myOfferUids(): { string }
	local out = {}
	if current and current.Mine then
		for _, it in current.Mine.Items do
			table.insert(out, it.Uid)
		end
	end
	return out
end

local function sendOffer(uids: { string })
	ClientNet.Call("TradeSetOffer", true, uids, math.floor(tonumber(cashBox.Text) or 0))
end

local function clearChildren(f: Instance)
	for _, c in f:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
end

local function draw()
	if not current or not mineFrame then
		return
	end
	clearChildren(mineFrame)
	clearChildren(theirsFrame)
	clearChildren(pickFrame)
	theirTitle.Text = tostring(current.PartnerName) .. " offers:"
	for i, it in current.Mine.Items do
		local b = Theme.Button(line(it) .. "  ×", Theme.Colors.PanelLight, function()
			local uids = myOfferUids()
			table.remove(uids, table.find(uids, it.Uid) :: number)
			sendOffer(uids)
		end, 14)
		b.Size = UDim2.new(1, -6, 0, 32)
		b.LayoutOrder = i
		b.Parent = mineFrame
	end
	Theme.Label(("Cash: %s%s%s"):format(Format.Cash(current.Mine.Cash), if current.Mine.Locked then "  🔒" else "", if current.Mine.Confirmed then "  ★" else ""), { Size = UDim2.new(1, -6, 0, 22), LayoutOrder = 99, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold, Parent = mineFrame }, 15)
	for i, it in current.Theirs.Items do
		Theme.Label(line(it), { Size = UDim2.new(1, -6, 0, 28), LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left, Parent = theirsFrame }, 14)
	end
	Theme.Label(("Cash: %s%s%s"):format(Format.Cash(current.Theirs.Cash), if current.Theirs.Locked then "  🔒" else "", if current.Theirs.Confirmed then "  ★" else ""), { Size = UDim2.new(1, -6, 0, 22), LayoutOrder = 99, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold, Parent = theirsFrame }, 15)

	-- Your items you could add
	local state = ClientState.Get()
	local offered: { [string]: boolean } = {}
	for _, uid in myOfferUids() do
		offered[uid] = true
	end
	if state then
		local i = 0
		for _, item in state.Inventory do
			local def = ItemCatalog.Get(item.Id)
			if def and def.Tradable and not item.Bound and not item.Locked and not item.Reserved and not offered[item.Uid] then
				i += 1
				local b = Theme.Button(line({ Id = item.Id, Name = def.Name, Condition = item.Condition, Charges = item.Charges }) .. "  +", Theme.Colors.PanelLighter, function()
					local uids = myOfferUids()
					table.insert(uids, item.Uid)
					sendOffer(uids)
				end, 13)
				b.Size = UDim2.new(1, -6, 0, 30)
				b.LayoutOrder = i
				b.Parent = pickFrame
			end
		end
	end
	lockButton.Text = if current.Mine.Locked then "Unlock" else "Lock offer"
	Theme.SetButtonEnabled(confirmButton, current.Mine.Locked and current.Theirs.Locked and not current.Mine.Confirmed, Theme.Colors.Success)
end

function TradePanel.Init()
	local content = Window.Create(NAME, "Trade", function()
		draw()
	end)
	statusLabel = Theme.Label("", { Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.TextDim }, 14)
	statusLabel.Parent = content
	local function column(x: number, title: string): (ScrollingFrame, TextLabel)
		local t = Theme.Label(title, { Position = UDim2.new(x, 0, 0, 24), Size = UDim2.new(1 / 3, -6, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold, Parent = content }, 15)
		local s = Theme.Scroller({ BackgroundTransparency = 0, BackgroundColor3 = Theme.Colors.Panel, Position = UDim2.new(x, 0, 0, 46), Size = UDim2.new(1 / 3, -6, 1, -150) })
		s.Parent = content
		Theme.ListLayout(s, 4)
		Theme.Padding(s, 4)
		return s, t
	end
	pickFrame = column(0, "Your items (tap to offer)")
	mineFrame = column(1 / 3, "Your offer")
	theirsFrame, theirTitle = column(2 / 3, "Their offer")
	cashBox = Theme.New("TextBox", {
		BackgroundColor3 = Theme.Colors.PanelLighter,
		PlaceholderText = "Cash to add",
		Text = "0",
		ClearTextOnFocus = false,
		Font = Theme.Fonts.Body,
		TextSize = 16,
		TextColor3 = Theme.Colors.Text,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 0, 1, -54),
		Size = UDim2.new(1 / 3, -6, 0, 40),
		Parent = content,
	})
	Theme.Corner(cashBox, 6)
	cashBox.FocusLost:Connect(function()
		sendOffer(myOfferUids())
	end)
	local row = Theme.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 46), Parent = content })
	Theme.ListLayout(row, 6, true)
	lockButton = Theme.Button("Lock offer", Theme.Colors.Blue, function()
		ClientNet.Call("TradeLock", true, not (current and current.Mine.Locked))
	end, 16)
	lockButton.Size = UDim2.new(1 / 3, -6, 1, 0)
	lockButton.Parent = row
	confirmButton = Theme.Button("Confirm", Theme.Colors.Success, function()
		ClientNet.Call("TradeConfirm", true)
	end, 16)
	confirmButton.Size = UDim2.new(1 / 3, -6, 1, 0)
	confirmButton.LayoutOrder = 1
	confirmButton.Parent = row
	local cancel = Theme.Button("Cancel trade", Theme.Colors.Danger, function()
		ClientNet.Call("TradeCancel", true)
	end, 16)
	cancel.Size = UDim2.new(1 / 3, -6, 1, 0)
	cancel.LayoutOrder = 2
	cancel.Parent = row

	Remotes.Event("TradeUpdate").OnClientEvent:Connect(function(u)
		if type(u) ~= "table" then
			return
		end
		if not u.Active then
			current = nil
			if Window.IsOpen(NAME) then
				Window.Close()
			end
			if u.Message then
				Notifications.Show(tostring(u.Message), "Info")
			end
			return
		end
		local isNew = current == nil
		current = u
		statusLabel.Text = tostring(u.Message or "")
		if isNew then
			cashBox.Text = tostring(u.Mine.Cash or 0)
			Window.Open(NAME)
		end
		draw()
	end)
	Remotes.Event("TradeRequest").OnClientEvent:Connect(function(r)
		if type(r) ~= "table" then
			return
		end
		Dialog.Choice("Trade request", ("%s wants to trade with you."):format(tostring(r.FromName)), {
			{ Text = "Accept", Color = Theme.Colors.Success, OnClick = function()
				ClientNet.Call("TradeRespond", true, r.RequestId, true)
			end },
			{ Text = "Decline", Color = Theme.Colors.Danger, OnClick = function()
				ClientNet.Call("TradeRespond", false, r.RequestId, false)
			end },
		}, r.Seconds or 30)
	end)
	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			draw()
		end
	end)
end

function TradePanel.IsActive(): boolean
	return current ~= nil
end

function TradePanel.Open()
	if current then
		Window.Open(NAME)
	end
end

function TradePanel.RequestTrade(userId: number)
	ClientNet.Call("RequestTrade", true, userId)
end

return TradePanel
