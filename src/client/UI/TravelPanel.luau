--[[
	TravelPanel
	Expedition menu: travel to unlocked zones or back to your museum.
	(The portal in the plaza does the same for the Forgotten Ruins.)
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Zones = require(Shared.Zones)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local TravelPanel = {}

local NAME = "Travel"
local list: ScrollingFrame

local function travel(destination: string)
	local result = ClientNet.Call("TravelTo", true, destination)
	if result.Ok then
		Window.Close()
	end
end

local function refresh()
	local state = ClientState.Get()
	if not state or not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local home = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLighter, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = 0, Parent = list })
	Theme.Corner(home, 10)
	Theme.Padding(home, 8)
	Theme.Label("<b>Your Museum</b>\nCollect earnings, display finds and build.", {
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0.68, 0, 1, 0),
		Parent = home,
	}, 16)
	local homeButton = Theme.Button("Go Home", Theme.Colors.Blue, function()
		travel("Museum")
	end, 18)
	homeButton.AnchorPoint = Vector2.new(1, 0.5)
	homeButton.Position = UDim2.new(1, 0, 0.5, 0)
	homeButton.Size = UDim2.new(0.28, 0, 0, 44)
	homeButton.Parent = home

	for _, zone in Zones.List do
		local levelOk = (state.Level or 1) >= zone.RequiredLevel
		local row = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, -8, 0, 74), LayoutOrder = zone.Order, Parent = list })
		Theme.Corner(row, 10)
		Theme.Padding(row, 8)
		local status = if not zone.Built
			then "<font color=\"#8A6A4A\">Coming soon</font>"
			elseif not levelOk then ("<font color=\"#C0392B\">Requires Museum Level %d</font>"):format(zone.RequiredLevel)
			elseif state.Journal.ZonesVisited[zone.Id] then "<font color=\"#2E7D32\">Visited</font>"
			else "<font color=\"#A8741A\">New!</font>"
		Theme.Label(("<b>%s</b>  %s\n%s"):format(zone.Name, status, zone.Description), {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextWrapped = true,
			Size = UDim2.new(0.68, 0, 1, 0),
			Parent = row,
		}, 16)
		local button = Theme.Button("Travel", Theme.Colors.Success, function()
			travel(zone.Id)
		end, 18)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
		button.Size = UDim2.new(0.28, 0, 0, 44)
		Theme.SetButtonEnabled(button, zone.Built and levelOk, Theme.Colors.Success)
		button.Parent = row
	end
end

function TravelPanel.Init()
	local content = Window.Create(NAME, "Expeditions", refresh)
	list = Theme.Scroller()
	list.Parent = content
	Theme.ListLayout(list, 8)
	Theme.Padding(list, 4)
	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			refresh()
		end
	end)
end

function TravelPanel.Open()
	Window.Open(NAME)
end

return TravelPanel
