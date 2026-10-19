--[[
	ExpeditionUI
	• Scanner widget (only on expeditions): SCAN button / Q key, signal bars,
	  a direction arrow relative to your camera, depth/material notes, and a
	  DIG HERE button once the signal is pinpointed.
	• Excavation tool picker: shows what your kit can tell about the find and
	  the risk, then lets you choose Brush / Trowel / Pick.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Zones = require(Shared.Zones)

local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)
local Dialog = require(script.Parent.Dialog)
local ClientNet = require(script.Parent.Parent.ClientNet)

local ExpeditionUI = {}

local player = Players.LocalPlayer
local widget: Frame
local bars: { Frame } = {}
local signalLabel: TextLabel
local detailLabel: TextLabel
local arrow: TextLabel
local digButton: TextButton
local scanButton: TextButton
local direction: number? = nil
local scanning = false

local SIGNAL_LEVEL = { None = 0, Weak = 1, Moderate = 2, Strong = 3, Pinpoint = 4 }
local SIGNAL_COLOR = {
	None = Theme.Colors.TextDim,
	Weak = Color3.fromRGB(200, 170, 90),
	Moderate = Color3.fromRGB(230, 190, 70),
	Strong = Color3.fromRGB(120, 220, 120),
	Pinpoint = Color3.fromRGB(90, 240, 200),
}

local function showReading(r: any)
	local level = SIGNAL_LEVEL[r.Signal] or 0
	local color = SIGNAL_COLOR[r.Signal] or Theme.Colors.TextDim
	for i, bar in bars do
		bar.BackgroundColor3 = if i <= level then color else Theme.Colors.PanelLighter
	end
	signalLabel.Text = ("Signal: <b>%s</b>"):format(tostring(r.Signal))
	signalLabel.TextColor3 = color
	local lines = {}
	if r.Hollow then
		table.insert(lines, "<font color=\"#1F7A6A\">Hollow space detected behind a wall nearby!</font>")
	end
	if r.Depth then
		table.insert(lines, ("Depth: %s%s"):format(r.Depth, if r.TooDeep then " <font color=\"#C0392B\">(too deep for your kit)</font>" else ""))
	end
	if r.Material then
		table.insert(lines, "Material: " .. tostring(r.Material))
	end
	if r.Note then
		table.insert(lines, "<i>" .. tostring(r.Note) .. "</i>")
	end
	if r.Signal ~= "None" and not r.Direction and not r.CanDig then
		table.insert(lines, "No direction — walk around and compare readings.")
	end
	if r.Signal == "None" then
		table.insert(lines, ("Nothing within %d studs."):format(r.Range or 0))
	end
	detailLabel.Text = table.concat(lines, "\n")
	direction = r.Direction
	arrow.Visible = direction ~= nil
	digButton.Visible = r.CanDig == true
	Sounds.Play("Scan", 0.35, 0.6 + level * 0.25)
end

local function scan()
	if scanning then
		return
	end
	scanning = true
	scanButton.Text = "..."
	local result = ClientNet.Call("Scan", false)
	if result.Ok and type(result.Data) == "table" then
		showReading(result.Data)
	elseif result.Message then
		detailLabel.Text = result.Message
	end
	task.wait(0.4)
	scanButton.Text = "SCAN (Q)"
	scanning = false
end

local function updateVisibility()
	local zone = player:GetAttribute("Zone")
	local onExpedition = type(zone) == "string" and Zones.ById[zone] ~= nil
	widget.Visible = onExpedition
	if onExpedition then
		ContextActionService:BindAction("MuseumScan", function(_, state)
			if state == Enum.UserInputState.Begin then
				task.spawn(scan)
			end
			return Enum.ContextActionResult.Sink
		end, false, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	else
		ContextActionService:UnbindAction("MuseumScan")
		digButton.Visible = false
		direction = nil
	end
end

local function onExcavationOffer(info: any)
	local body = table.concat(info.Hints or {}, "\n")
	if info.Risk then
		body ..= "\n\n<font color=\"#C0392B\">Risk: " .. tostring(info.Risk) .. "</font>"
	end
	local options: { Dialog.Option } = {}
	for _, tool in info.Tools or {} do
		local color = if tool.Name == "Brush" then Color3.fromRGB(70, 140, 80) elseif tool.Name == "Pick" then Color3.fromRGB(110, 110, 120) else Color3.fromRGB(160, 120, 50)
		table.insert(options, {
			Text = ("%s (%d)"):format(tool.Name, tool.Strokes),
			Color = color,
			OnClick = function()
				ClientNet.Call("ChooseExcavationTool", true, info.SessionId, tool.Name)
			end,
		})
	end
	table.insert(options, { Text = "Not now", Color = Theme.Colors.Danger })
	Dialog.Choice("Excavate: " .. tostring(info.SiteName), body .. "\n\nBrush = gentle, Trowel = quick, Pick = breaks stone.", options, 30)
end

function ExpeditionUI.Init(screen: ScreenGui)
	widget = Theme.New("Frame", {
		Name = "Scanner",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -12, 1, -12),
		Size = UDim2.fromOffset(250, 210),
		BackgroundColor3 = Theme.Colors.Panel,
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screen,
	})
	Theme.Corner(widget, 12)
	Theme.Stroke(widget, Theme.Colors.Gold, 2)
	Theme.Padding(widget, 10)
	Theme.Label("ARCHAEO SCANNER", { Font = Theme.Fonts.Bold, TextColor3 = Theme.Colors.Gold, Size = UDim2.new(1, -40, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = widget }, 15)
	arrow = Theme.Label("▲", { Font = Theme.Fonts.Bold, AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.fromOffset(36, 36), TextColor3 = Color3.fromRGB(120, 230, 160), Visible = false, Parent = widget }, 30)
	local barRow = Theme.New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 22), Size = UDim2.new(0.6, 0, 0, 22), Parent = widget })
	Theme.ListLayout(barRow, 4, true).VerticalAlignment = Enum.VerticalAlignment.Bottom
	for i = 1, 4 do
		local bar = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLighter, Size = UDim2.fromOffset(16, 6 + i * 4), LayoutOrder = i, Parent = barRow })
		Theme.Corner(bar, 3)
		bars[i] = bar
	end
	signalLabel = Theme.Label("Signal: —", { Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = widget }, 15)
	detailLabel = Theme.Label("Press SCAN to search for buried finds. Clues in the world hint where to look.", {
		TextColor3 = Theme.Colors.TextDim,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 66),
		Size = UDim2.new(1, 0, 0, 66),
		Parent = widget,
	}, 13)
	scanButton = Theme.Button("SCAN (Q)", Theme.Colors.Blue, function()
		task.spawn(scan)
	end, 18)
	scanButton.AnchorPoint = Vector2.new(0, 1)
	scanButton.Position = UDim2.fromScale(0, 1)
	scanButton.Size = UDim2.new(0.5, -4, 0, 44)
	scanButton.Parent = widget
	digButton = Theme.Button("DIG HERE", Theme.Colors.Success, function()
		ClientNet.Call("DigHere", true)
	end, 18)
	digButton.AnchorPoint = Vector2.new(1, 1)
	digButton.Position = UDim2.fromScale(1, 1)
	digButton.Size = UDim2.new(0.5, -4, 0, 44)
	digButton.Visible = false
	digButton.Parent = widget

	-- Arrow points toward the reading, relative to where the camera faces.
	RunService.RenderStepped:Connect(function()
		if direction and widget.Visible then
			local look = workspace.CurrentCamera.CFrame.LookVector
			local camYaw = math.deg(math.atan2(look.X, look.Z))
			arrow.Rotation = camYaw - direction
		end
	end)

	player:GetAttributeChangedSignal("Zone"):Connect(updateVisibility)
	updateVisibility()
	Remotes.Event("ExcavationOffer").OnClientEvent:Connect(function(info)
		if type(info) == "table" then
			onExcavationOffer(info)
		end
	end)
end

return ExpeditionUI
