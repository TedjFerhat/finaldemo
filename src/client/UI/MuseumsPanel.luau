--[[
	MuseumsPanel
	Lists every museum on the server (sorted by prestige) so you can visit
	other players and admire their collections.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientNet = require(script.Parent.Parent.ClientNet)
local TradePanel = require(script.Parent.TradePanel)

local MuseumsPanel = {}

local NAME = "Museums"
local list: ScrollingFrame

local function refresh()
	if not list then
		return
	end
	local result = ClientNet.Call("GetMuseumList", false)
	for _, child in list:GetChildren() do
		if child:IsA("Frame") or child:IsA("TextLabel") then
			child:Destroy()
		end
	end
	local entries = if result.Ok and type(result.Data) == "table" then result.Data else {}
	if #entries == 0 then
		Theme.Label("No museums are open yet.", { Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Colors.TextDim, Parent = list }, 18)
		return
	end
	for i, entry in entries do
		local isMe = entry.UserId == Players.LocalPlayer.UserId
		local row = Theme.New("Frame", {
			BackgroundColor3 = if isMe then Theme.Colors.PanelLighter else Theme.Colors.PanelLight,
			Size = UDim2.new(1, -8, 0, 68),
			LayoutOrder = i,
			Parent = list,
		})
		Theme.Corner(row, 10)
		Theme.Padding(row, 8)
		Theme.Label(
			("<b>#%d  %s</b>%s\n<font color=\"#A8741A\">%s</font> · %s · %d prestige · %d exhibits"):format(
				i,
				tostring(entry.Name),
				if isMe then " (you)" else "",
				tostring(entry.Title),
				Upgrades.LevelNames[entry.Level] or "",
				tonumber(entry.Prestige) or 0,
				tonumber(entry.Displays) or 0
			),
			{ TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Size = UDim2.new(0.68, 0, 1, 0), Parent = row },
			16
		)
		local button = Theme.Button(if isMe then "Go Home" else "Visit", Theme.Colors.Blue, function()
			local r = ClientNet.Call("VisitMuseum", true, entry.UserId)
			if r.Ok then
				Window.Close()
			end
		end, 18)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
		button.Size = UDim2.new(0.13, 0, 0, 44)
		button.Parent = row
		if not isMe then
			local trade = Theme.Button("Trade", Theme.Colors.Success, function()
				if TradePanel.IsActive() then
					TradePanel.Open()
				else
					TradePanel.RequestTrade(entry.UserId)
				end
			end, 16)
			trade.AnchorPoint = Vector2.new(1, 0.5)
			trade.Position = UDim2.new(0.86, -6, 0.5, 0)
			trade.Size = UDim2.new(0.12, 0, 0, 44)
			trade.Parent = row
		end
	end
end

function MuseumsPanel.Init()
	local content = Window.Create(NAME, "Museums & Players", refresh)
	list = Theme.Scroller()
	list.Parent = content
	Theme.ListLayout(list, 8)
	Theme.Padding(list, 4)
end

function MuseumsPanel.Open()
	Window.Open(NAME)
end

return MuseumsPanel
