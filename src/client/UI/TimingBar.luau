--[[
	TimingBar
	Shows the timing meter for server-judged actions (brushing soil, swinging
	a pick, working a lock, cutting glass, lifting an exhibit).

	The marker is drawn from shared maths + the synced server clock, so the
	picture matches what the server judges. The client only says "now".
	Input: the big button, Space, or gamepad A. The × button stops.
]]

local RunService = game:GetService("RunService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Minigame = require(Shared.Minigame)

local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)
local Notifications = require(script.Parent.Notifications)

local TimingBar = {}

local ACTION = "MuseumTimingPress"
local THEME_COLORS = {
	Brush = Color3.fromRGB(120, 190, 120),
	Trowel = Color3.fromRGB(200, 160, 90),
	Pick = Color3.fromRGB(170, 170, 180),
	Lockpick = Color3.fromRGB(150, 180, 230),
	Glass = Color3.fromRGB(150, 220, 240),
	Plate = Color3.fromRGB(230, 140, 110),
}

type Active = { Id: string, Info: any, Index: number, Pips: { Frame }, Conn: RBXScriptConnection? }

local panel: Frame
local titleLabel: TextLabel
local subLabel: TextLabel
local zone: Frame
local marker: Frame
local pipRow: Frame
local hint: TextLabel
local active: Active? = nil

local function invoke(action: string)
	local a = active
	if not a then
		return
	end
	task.spawn(function()
		pcall(function()
			Remotes.Function("ChallengeInput"):InvokeServer(a.Id, action)
		end)
	end)
end

local function placeZone(info: any, index: number)
	local center = info.Centers and info.Centers[index]
	if not center then
		zone.Visible = false
		return
	end
	zone.Visible = true
	zone.Size = UDim2.fromScale(info.ZoneWidth or 0.2, 1)
	zone.Position = UDim2.fromScale(center, 0.5)
end

local function stop()
	local a = active
	active = nil
	if a and a.Conn then
		a.Conn:Disconnect()
	end
	ContextActionService:UnbindAction(ACTION)
	panel.Visible = false
end

local function begin(info: any)
	stop()
	if info.Kind ~= "Timing" then
		-- (Only timing challenges exist in this version.)
		return
	end
	local a: Active = { Id = info.Id, Info = info, Index = 1, Pips = {}, Conn = nil }
	active = a
	titleLabel.Text = info.Title or ""
	subLabel.Text = info.Subtitle or ""
	zone.BackgroundColor3 = THEME_COLORS[info.Theme] or Theme.Colors.Gold
	for _, c in pipRow:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for i = 1, info.Presses or 1 do
		local pip = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLighter, Size = UDim2.fromOffset(18, 18), LayoutOrder = i, Parent = pipRow })
		Theme.Corner(pip, 9)
		a.Pips[i] = pip
	end
	placeZone(info, 1)
	panel.Visible = true
	Sounds.Play("Open", 0.3)

	a.Conn = RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		if now < info.T0 then
			hint.Text = ("Get ready... %.1f"):format(info.T0 - now)
		else
			hint.Text = "Press when the marker is inside the coloured zone"
		end
		marker.Position = UDim2.fromScale(Minigame.MarkerPos(now, info.T0, info.Speed or 0.6), 0.5)
	end)
	ContextActionService:BindActionAtPriority(ACTION, function(_, state)
		if state == Enum.UserInputState.Begin then
			invoke("Press")
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
end

function TimingBar.Init(screen: ScreenGui)
	panel = Theme.New("Frame", {
		Name = "TimingBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.92, 0),
		Size = UDim2.new(0.6, 0, 0, 196),
		BackgroundColor3 = Theme.Colors.Panel,
		Visible = false,
		ZIndex = 20,
		Parent = screen,
	})
	Theme.New("UISizeConstraint", { MaxSize = Vector2.new(560, 196), MinSize = Vector2.new(280, 0), Parent = panel })
	Theme.Corner(panel, 12)
	Theme.Stroke(panel, Theme.Colors.Gold, 2)
	Theme.Padding(panel, 10)
	titleLabel = Theme.Label("", { Font = Theme.Fonts.Bold, Size = UDim2.new(1, -44, 0, 24), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21, Parent = panel }, 18)
	subLabel = Theme.Label("", { TextColor3 = Theme.Colors.TextDim, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 21, Parent = panel }, 14)
	local close = Theme.Button("X", Theme.Colors.Danger, function()
		invoke("Cancel")
	end, 18)
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.fromScale(1, 0)
	close.Size = UDim2.fromOffset(36, 30)
	close.ZIndex = 22
	close.Parent = panel

	local track = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLighter, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 30), ZIndex = 21, Parent = panel })
	Theme.Corner(track, 8)
	zone = Theme.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Colors.Gold, ZIndex = 22, Parent = track })
	Theme.Corner(zone, 6)
	marker = Theme.New("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Color3.new(1, 1, 1), Size = UDim2.new(0, 6, 1, 10), ZIndex = 23, Parent = track })
	Theme.Corner(marker, 3)

	pipRow = Theme.New("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 88), Size = UDim2.new(0.5, 0, 0, 18), ZIndex = 21, Parent = panel })
	Theme.ListLayout(pipRow, 6, true)
	hint = Theme.Label("", { TextColor3 = Theme.Colors.TextDim, Position = UDim2.new(0.5, 0, 0, 88), Size = UDim2.new(0.5, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 21, Parent = panel }, 13)

	local press = Theme.Button("NOW!  (Space)", Theme.Colors.Success, function()
		invoke("Press")
	end, 22)
	press.Position = UDim2.fromOffset(0, 114)
	press.Size = UDim2.new(1, 0, 0, 58)
	press.ZIndex = 22
	press.Parent = panel

	Remotes.Event("ChallengeStart").OnClientEvent:Connect(function(info)
		if type(info) == "table" then
			begin(info)
		end
	end)
	Remotes.Event("ChallengeFeedback").OnClientEvent:Connect(function(info)
		local a = active
		if not a or type(info) ~= "table" or info.Id ~= a.Id then
			return
		end
		local pip = a.Pips[info.Index]
		if pip then
			pip.BackgroundColor3 = if info.Hit then Theme.Colors.Success else Theme.Colors.Danger
		end
		Sounds.Play(if info.Hit then "Hit" else "Miss", 0.5, if info.Hit then 1.2 else 0.8)
		a.Index = info.Index + 1
		placeZone(a.Info, a.Index)
	end)
	Remotes.Event("ChallengeEnd").OnClientEvent:Connect(function(info)
		if active and type(info) == "table" and info.Id == active.Id then
			stop()
			if info.Cancelled and info.Reason and info.Reason ~= "Cancelled" then
				Notifications.Show(tostring(info.Reason), "Info")
			end
		end
	end)
end

return TimingBar
