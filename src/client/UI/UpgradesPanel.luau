--[[
	UpgradesPanel
	Lists every museum construction upgrade: owned, available or locked.
	Buying here does exactly the same as stepping on the green pad in your
	front yard — the server checks everything.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local UpgradesPanel = {}

local NAME = "Upgrades"
local list: ScrollingFrame
local summary: TextLabel

local function refresh()
	local state = ClientState.Get()
	if not state or not list then
		return
	end
	summary.Text = ("<b>%s</b>  ·  Level %d  ·  Income %s/min  ·  Decor bonus +%d%%"):format(
		state.LevelName or "",
		state.Level or 1,
		Format.Cash(state.Income and state.Income.PerMinute or 0),
		math.floor((state.Income and state.Income.Decor or 0) * 100 + 0.5)
	)
	for _, child in list:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for _, up in Upgrades.List do
		local owned = state.Upgrades[up.Id] == true
		local available = not owned and Upgrades.RequirementsMet(up, state.Upgrades)
		local row = Theme.New("Frame", {
			BackgroundColor3 = if owned then Color3.fromRGB(34, 70, 50) else Theme.Colors.PanelLight,
			Size = UDim2.new(1, -8, 0, 78),
			LayoutOrder = up.Order + (if owned then 100 else 0),
			Parent = list,
		})
		Theme.Corner(row, 10)
		Theme.Padding(row, 8)
		local title = Theme.Label(up.Name .. (if up.GrantsLevel then ("  <font color=\"#A8741A\">› Level %d</font>"):format(up.GrantsLevel) else ""), {
			Font = Theme.Fonts.Bold,
			TextXAlignment = Enum.TextXAlignment.Left,
			Size = UDim2.new(0.7, 0, 0, 22),
		}, 18)
		title.Parent = row
		local reqText = ""
		if not owned and not available then
			local names = {}
			for _, req in up.Requires do
				if not state.Upgrades[req] then
					table.insert(names, Upgrades.ById[req].Name)
				end
			end
			reqText = ("\n<font color=\"#C0392B\">Requires: %s</font>"):format(table.concat(names, ", "))
		end
		local desc = Theme.Label(up.Description .. reqText, {
			TextColor3 = Theme.Colors.TextDim,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
			TextWrapped = true,
			Position = UDim2.fromOffset(0, 24),
			Size = UDim2.new(0.7, 0, 1, -24),
		}, 14)
		desc.Parent = row

		local buttonText = if owned then "Built" else Format.Cash(up.Cost)
		local canAfford = state.Cash >= up.Cost
		local button = Theme.Button(buttonText, Theme.Colors.Success, function()
			ClientNet.Call("PurchaseUpgrade", true, up.Id)
		end, 18)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
		button.Size = UDim2.new(0.27, 0, 0, 44)
		Theme.SetButtonEnabled(button, available and canAfford, Theme.Colors.Success)
		if available and not canAfford then
			button.BackgroundColor3 = Theme.Colors.GoldDark
		end
		button.Parent = row
	end
end

function UpgradesPanel.Init()
	local content = Window.Create(NAME, "Build Your Museum", refresh)
	summary = Theme.Label("", { Size = UDim2.new(1, 0, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold }, 16)
	summary.Parent = content
	list = Theme.Scroller({ Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30) })
	list.Parent = content
	Theme.ListLayout(list, 8)
	Theme.Padding(list, 4)
	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			refresh()
		end
	end)
end

function UpgradesPanel.Open()
	Window.Open(NAME)
end

return UpgradesPanel
