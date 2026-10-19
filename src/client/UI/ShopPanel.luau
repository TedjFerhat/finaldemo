--[[
	ShopPanel
	Two tabs:
	  • Archaeology — kits (account-bound) and the Jungle Echo-Sounder.
	  • Heist Gear  — lockpicks, glass cutters and camera jammers. Each buy is
	                  an item with charges; it can be traded or sold.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Equipment = require(Shared.Equipment)
local ItemCatalog = require(Shared.ItemCatalog)
local HeistConfig = require(Shared.HeistConfig)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local ShopPanel = {}

local NAME = "Shop"
local list: ScrollingFrame
local tab = 1
local tabButtons: { TextButton } = {}

local function row(order: number, title: string, desc: string, buttonText: string, enabled: boolean, color: Color3, onClick: () -> (), highlight: boolean?, height: number?)
	local f = Theme.New("Frame", {
		BackgroundColor3 = if highlight then Color3.fromRGB(34, 70, 50) else Theme.Colors.PanelLight,
		Size = UDim2.new(1, -8, 0, height or 80),
		LayoutOrder = order,
		Parent = list,
	})
	Theme.Corner(f, 10)
	Theme.Padding(f, 8)
	Theme.Label(title, { TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.7, 0, 0, 22), Parent = f }, 17)
	Theme.Label(desc, {
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(0.7, 0, 1, -24),
		Parent = f,
	}, 13)
	local b = Theme.Button(buttonText, color, onClick, 17)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, 0, 0.5, 0)
	b.Size = UDim2.new(0.27, 0, 0, 44)
	Theme.SetButtonEnabled(b, enabled, color)
	b.Parent = f
end

local function drawKits(state: any)
	for _, tool in Equipment.Tools do
		local owned = state.ToolTier >= tool.Tier
		local levelOk = (state.Level or 1) >= tool.RequiredLevel
		local caps = { ("Scan range %d"):format(tool.ScanRange) }
		table.insert(caps, if tool.DirectionError then ("direction ±%d°"):format(tool.DirectionError) else "no direction")
		if tool.ShowsDepth then
			table.insert(caps, "depth")
		end
		if tool.ShowsMaterial then
			table.insert(caps, "material")
		end
		if tool.FlagsFalseSignals then
			table.insert(caps, "flags false signals")
		end
		table.insert(caps, "tools: " .. table.concat(tool.ExcavationTools, "/"))
		local desc = tool.Description .. "\n" .. table.concat(caps, " · ")
		if not levelOk then
			desc ..= ("\n<font color=\"#C0392B\">Requires Museum Level %d</font>"):format(tool.RequiredLevel)
		end
		row(tool.Tier, ("<b>%s</b>%s"):format(tool.Name, if state.ToolTier == tool.Tier then "  <font color=\"#2E7D32\">EQUIPPED</font>" else ""), desc, if owned then "Owned" else Format.Cash(tool.Cost), not owned and levelOk and state.Cash >= tool.Cost, Theme.Colors.Success, function()
			ClientNet.Call("BuyTool", true, tool.Tier)
		end, state.ToolTier == tool.Tier)
	end
	local order = 10
	for id, att in Equipment.Attachments do
		order += 1
		local owned = state.Attachments and state.Attachments[id]
		local levelOk = (state.Level or 1) >= att.RequiredLevel
		row(order, ("<b>%s</b>%s"):format(att.Name, if owned then "  <font color=\"#2E7D32\">INSTALLED</font>" else ""), att.Description .. (if levelOk then "" else ("\n<font color=\"#C0392B\">Requires Museum Level %d</font>"):format(att.RequiredLevel)), if owned then "Owned" else Format.Cash(att.Cost), not owned and levelOk and state.Cash >= att.Cost, Theme.Colors.Success, function()
			ClientNet.Call("BuyAttachment", true, id)
		end, owned)
	end
end

local function drawGear(state: any)
	local levelOk = (state.Level or 1) >= HeistConfig.AttackerMinLevel
	local order = 0
	for _, id in ItemCatalog.Order do
		local def = ItemCatalog.Items[id]
		if def.Gadget then
			order += 1
			local owned = 0
			for _, item in state.Inventory do
				if item.Id == id then
					owned += item.Charges or 0
				end
			end
			local desc = ("%s\nTier %d · %d charges · you have %d charges"):format(def.Gadget.Description, def.Gadget.Tier, def.Gadget.Charges, owned)
			if not levelOk then
				desc ..= ("\n<font color=\"#C0392B\">Unlocks at Museum Level %d</font>"):format(HeistConfig.AttackerMinLevel)
			end
			row(order, "<b>" .. def.Name .. "</b>", desc, Format.Cash(def.Gadget.Cost), levelOk and state.Cash >= def.Gadget.Cost, Theme.Colors.Danger, function()
				ClientNet.Call("BuyGadget", true, id)
			end)
		end
	end
end

local function refresh()
	local state = ClientState.Get()
	if not state or not list then
		return
	end
	for i, b in tabButtons do
		b.BackgroundColor3 = if i == tab then Theme.Colors.Gold else Theme.Colors.PanelLighter
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if tab == 1 then
		drawKits(state)
	else
		drawGear(state)
	end
end

function ShopPanel.Init()
	local content = Window.Create(NAME, "Expedition Outfitters", refresh)
	local tabs = Theme.New("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 36), Parent = content })
	Theme.ListLayout(tabs, 6, true)
	for i, name in { "Archaeology", "Heist Gear" } do
		local b = Theme.Button(name, Theme.Colors.PanelLighter, function()
			tab = i
			refresh()
		end, 16)
		b.Size = UDim2.new(0.5, -6, 1, 0)
		b.Parent = tabs
		tabButtons[i] = b
	end
	list = Theme.Scroller({ Position = UDim2.fromOffset(0, 42), Size = UDim2.new(1, 0, 1, -42) })
	list.Parent = content
	Theme.ListLayout(list, 8)
	Theme.Padding(list, 4)
	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			refresh()
		end
	end)
end

function ShopPanel.Open()
	Window.Open(NAME)
end

return ShopPanel
