--[[
	SecurityPanel
	Buy museum security levels and read your incident log. Everything bought
	here appears in your museum and is exactly what thieves have to beat.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local HeistConfig = require(Shared.HeistConfig)
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local SecurityPanel = {}

local NAME = "Security"
local list: ScrollingFrame
local summary: TextLabel

local function refresh()
	local state = ClientState.Get()
	if not state or not list then
		return
	end
	for _, c in list:GetChildren() do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local hs = state.HeistStats or {}
	summary.Text = ("Defended: <b>%d</b> · Robbed: <b>%d</b> · Your heists: %d won, %d caught%s"):format(
		hs.Defended or 0, hs.Robbed or 0, hs.Successes or 0, hs.Captures or 0,
		if (hs.ProtectedLeft or 0) > 0 then (" · <font color=\"#2E7D32\">Protected for %s</font>"):format(Format.Seconds(hs.ProtectedLeft)) else ""
	)
	for i, entry in HeistConfig.SystemList() do
		local id, def = entry.Id, entry.Def
		local level = state.Security and state.Security[id] or 0
		local nextLevel = level + 1
		local maxed = level >= def.Max
		local needs = def.RequiresUpgrade and nextLevel >= (def.RequiresUpgradeFrom or 1) and not state.Upgrades[def.RequiresUpgrade]
		local row = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, -8, 0, 80), LayoutOrder = i, Parent = list })
		Theme.Corner(row, 10)
		Theme.Padding(row, 8)
		local current = if level > 0 then def.Levels[level] else "Not installed"
		local nextText = if maxed then "Maximum level" else ("Next: %s"):format(def.Levels[nextLevel])
		if needs then
			nextText ..= (" <font color=\"#C0392B\">(needs %s)</font>"):format(Upgrades.ById[def.RequiresUpgrade].Name)
		end
		Theme.Label(("<b>%s</b>  Lv %d/%d — %s\n<font color=\"#8A6A4A\">%s\n%s</font>"):format(def.Name, level, def.Max, current, def.Effect, nextText), {
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Size = UDim2.new(0.72, 0, 1, 0),
			Parent = row,
		}, 14)
		local cost = def.Costs[nextLevel]
		local b = Theme.Button(if maxed then "Max" else Format.Cash(cost or 0), Theme.Colors.Success, function()
			ClientNet.Call("BuySecurity", true, id)
		end, 17)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, 0, 0.5, 0)
		b.Size = UDim2.new(0.25, 0, 0, 42)
		Theme.SetButtonEnabled(b, not maxed and not needs and state.Cash >= (cost or math.huge), Theme.Colors.Success)
		b.Parent = row
	end
	Theme.Label("<b>Incident log</b>", { Size = UDim2.new(1, -8, 0, 24), LayoutOrder = 100, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold, Parent = list }, 17)
	local incidents = state.Incidents or {}
	if #incidents == 0 then
		Theme.Label("No incidents. Long may it last.", { Size = UDim2.new(1, -8, 0, 20), LayoutOrder = 101, TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.TextDim, Parent = list }, 14)
	end
	for i, inc in incidents do
		local text = if inc.Outcome == "Stolen"
			then ("%s stole your %s%s"):format(tostring(inc.Thief), tostring(inc.Item), if (inc.Insurance or 0) > 0 then (" (insurance %s)"):format(Format.Cash(inc.Insurance)) else "")
			elseif inc.Outcome == "Caught" then ("%s was caught%s"):format(tostring(inc.Thief), if inc.Item then " trying to take your " .. tostring(inc.Item) else "")
			else ("%s broke in but fled"):format(tostring(inc.Thief))
		Theme.Label(("%s  <font color=\"#8A6A4A\">%s</font>"):format(text, os.date("%d %b %H:%M", inc.Time or 0)), {
			Size = UDim2.new(1, -8, 0, 20),
			LayoutOrder = 101 + i,
			TextXAlignment = Enum.TextXAlignment.Left,
			Parent = list,
		}, 14)
	end
end

function SecurityPanel.Init()
	local content = Window.Create(NAME, "Museum Security", refresh)
	summary = Theme.Label("", { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.TextDim }, 15)
	summary.Parent = content
	list = Theme.Scroller({ Position = UDim2.fromOffset(0, 28), Size = UDim2.new(1, 0, 1, -28) })
	list.Parent = content
	Theme.ListLayout(list, 8)
	Theme.Padding(list, 4)
	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			refresh()
		end
	end)
end

function SecurityPanel.Open()
	Window.Open(NAME)
end

return SecurityPanel
