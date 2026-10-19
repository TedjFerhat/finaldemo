--[[
	HeistUI
	• Heist Board window: eligible museums (estimated security / value /
	  difficulty — not exact details), your loadout (up to 3 gadgets), and a
	  confirmation that explains the risks before you start.
	• Mission overlay: status, suspicion meter, objective, timers, Sneak /
	  Jam Cameras / Abort buttons.
	• Jail overlay: why you were caught and the time left.
	• Owner alerts: a red banner when someone is in your museum.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local ItemCatalog = require(Shared.ItemCatalog)
local HeistConfig = require(Shared.HeistConfig)
local Config = require(Shared.Config)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local Dialog = require(script.Parent.Dialog)
local Sounds = require(script.Parent.Sounds)
local Notifications = require(script.Parent.Notifications)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local HeistUI = {}

local NAME = "Heists"
local list: ScrollingFrame
local loadoutRow: Frame
local header: TextLabel
local selected: { [string]: boolean } = {}

-- ── Board ──────────────────────────────────────────────────────────────────
local function myGadgets(): { any }
	local state = ClientState.Get()
	local out = {}
	if not state then
		return out
	end
	for _, item in state.Inventory do
		local def = ItemCatalog.Get(item.Id)
		if def and def.Gadget and not item.Reserved and (item.Charges or 0) > 0 then
			table.insert(out, { Uid = item.Uid, Def = def, Charges = item.Charges })
		end
	end
	table.sort(out, function(a, b)
		return a.Def.Name < b.Def.Name
	end)
	return out
end

local function selectedList(): { string }
	local out = {}
	for uid in selected do
		table.insert(out, uid)
	end
	return out
end

local function drawLoadout()
	for _, c in loadoutRow:GetChildren() do
		if c:IsA("TextButton") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local gadgets = myGadgets()
	local valid: { [string]: boolean } = {}
	for _, g in gadgets do
		valid[g.Uid] = true
	end
	for uid in selected do
		if not valid[uid] then
			selected[uid] = nil
		end
	end
	if #gadgets == 0 then
		Theme.Label("No heist gear — buy some in Tools › Heist Gear.", { TextColor3 = Theme.Colors.TextDim, Size = UDim2.new(1, 0, 1, 0), Parent = loadoutRow }, 14)
		return
	end
	for i, g in gadgets do
		local on = selected[g.Uid] == true
		local b = Theme.Button(("%s%s\n%d charges"):format(if on then "★ " else "", g.Def.Name, g.Charges), if on then Theme.Colors.Success else Theme.Colors.PanelLighter, function()
			if selected[g.Uid] then
				selected[g.Uid] = nil
			elseif #selectedList() < HeistConfig.MaxLoadout then
				selected[g.Uid] = true
			else
				Notifications.Show(("Loadout is full (max %d)"):format(HeistConfig.MaxLoadout), "Error")
			end
			drawLoadout()
		end, 13)
		b.Size = UDim2.fromOffset(120, 46)
		b.LayoutOrder = i
		b.Parent = loadoutRow
	end
end

local function start(target: any)
	local count = #selectedList()
	Dialog.Choice(
		"Rob " .. tostring(target.Name) .. "'s museum?",
		("Security: %s · Lock level %d · Difficulty: %s\n\nIf you're caught you'll spend %ds in jail, pay a small fine to the owner, and lose the gadget charges you used. Loadout: %d gadget(s)."):format(
			tostring(target.Security),
			tonumber(target.LockLevel) or 0,
			tostring(target.Difficulty),
			Config.JailSeconds,
			count
		),
		{
			{ Text = "Start heist", Color = Theme.Colors.Danger, OnClick = function()
				local r = ClientNet.Call("StartHeist", true, target.UserId, selectedList())
				if r.Ok then
					selected = {}
					Window.Close()
				end
			end },
			{ Text = "Cancel", Color = Theme.Colors.PanelLighter },
		}
	)
end

local function refresh()
	if not list then
		return
	end
	drawLoadout()
	for _, c in list:GetChildren() do
		if c:IsA("Frame") or c:IsA("TextLabel") then
			c:Destroy()
		end
	end
	local r = ClientNet.Call("GetHeistTargets", false)
	local data = if r.Ok and type(r.Data) == "table" then r.Data else { Targets = {}, CanHeist = false, Reason = r.Message }
	header.Text = if data.CanHeist then "Choose a target. Owners must be online; new and recently robbed museums are protected." else ("<font color=\"#C0392B\">%s</font>"):format(tostring(data.Reason or "You can't plan a heist right now."))
	if #data.Targets == 0 then
		Theme.Label("No other museums on this server.", { Size = UDim2.new(1, 0, 0, 30), TextColor3 = Theme.Colors.TextDim, Parent = list }, 16)
		return
	end
	for i, t in data.Targets do
		local row = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, -8, 0, 64), LayoutOrder = i, Parent = list })
		Theme.Corner(row, 10)
		Theme.Padding(row, 8)
		Theme.Label(("<b>%s</b> · Level %d\nSecurity: %s · Loot: %s · Difficulty: <b>%s</b>%s"):format(
			tostring(t.Name), tonumber(t.Level) or 1, tostring(t.Security), tostring(t.Value), tostring(t.Difficulty),
			if t.Available then "" else ("\n<font color=\"#C0392B\">%s</font>"):format(tostring(t.Reason))
		), { TextXAlignment = Enum.TextXAlignment.Left, TextWrapped = true, Size = UDim2.new(0.7, 0, 1, 0), Parent = row }, 15)
		local b = Theme.Button("Plan heist", Theme.Colors.Danger, function()
			start(t)
		end, 16)
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, 0, 0.5, 0)
		b.Size = UDim2.new(0.27, 0, 0, 42)
		Theme.SetButtonEnabled(b, t.Available and data.CanHeist, Theme.Colors.Danger)
		b.Parent = row
	end
end

-- ── Mission overlay ────────────────────────────────────────────────────────
local hud: Frame
local hudStatus: TextLabel
local hudObjective: TextLabel
local hudTimer: TextLabel
local meterFill: Frame
local sneakButton: TextButton
local jamButton: TextButton
local lastAlarm = false

local function onHeistUpdate(u: any)
	if type(u) ~= "table" then
		return
	end
	if not u.Active then
		hud.Visible = false
		lastAlarm = false
		if u.Outcome then
			Dialog.Choice(
				if u.Outcome == "Escaped" then "Clean getaway!" elseif u.Outcome == "Captured" then "Caught!" else "Heist over",
				tostring(u.Reason or ""),
				{ { Text = "OK", Color = Theme.Colors.Blue } }
			)
		end
		return
	end
	hud.Visible = true
	local alarm = u.Alarm == true
	hudStatus.Text = ("%s  <font color=\"#8A6A4A\">(%s's museum)</font>"):format(tostring(u.Status), tostring(u.OwnerName))
	hudStatus.TextColor3 = if alarm then Color3.fromRGB(255, 110, 100) elseif (u.Suspicion or 0) >= HeistConfig.Thresholds.Suspicious then Color3.fromRGB(255, 200, 100) else Theme.Colors.Text
	hudObjective.Text = (if u.Seen then "<font color=\"#C0392B\">● A camera sees you!</font>  " else "") .. tostring(u.Objective)
	local timer = ("Time %s"):format(Format.Seconds(u.TimeLeft or 0))
	if alarm then
		timer = ("<font color=\"#FF6E64\">POLICE IN %s</font>  ·  "):format(Format.Seconds(u.AlarmLeft or 0)) .. timer
	end
	hudTimer.Text = timer
	local frac = math.clamp((u.Suspicion or 0) / HeistConfig.Thresholds.Alarm, 0, 1)
	meterFill.Size = UDim2.fromScale(frac, 1)
	meterFill.BackgroundColor3 = if frac >= 1 then Color3.fromRGB(230, 60, 50) elseif frac >= 0.6 then Color3.fromRGB(240, 150, 60) else Color3.fromRGB(240, 210, 90)
	sneakButton.Text = if u.Sneaking then "Stop sneaking" else "Sneak"
	local jams = 0
	for _, g in u.Gadgets or {} do
		if g.Type == "Jammer" then
			jams += g.Charges
		end
	end
	jamButton.Text = ("Jam cameras (%d)"):format(jams)
	Theme.SetButtonEnabled(jamButton, jams > 0, Theme.Colors.Blue)
	if alarm and not lastAlarm then
		Sounds.Play("Alarm", 0.7, 0.6)
	end
	lastAlarm = alarm
end

-- ── Jail & owner alerts ────────────────────────────────────────────────────
local jail: Frame
local jailLabel: TextLabel
local alertBanner: TextLabel

function HeistUI.Init(screen: ScreenGui)
	local content = Window.Create(NAME, "Heist Board", refresh)
	header = Theme.Label("", { Size = UDim2.new(1, 0, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.Gold }, 15)
	header.Parent = content
	Theme.Label("Loadout (tap to pick, max 3):", { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.TextDim, Parent = content }, 14)
	local loadScroll = Theme.Scroller({ Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 54), ScrollingDirection = Enum.ScrollingDirection.X, AutomaticCanvasSize = Enum.AutomaticSize.X })
	loadScroll.Parent = content
	loadoutRow = loadScroll :: any
	Theme.ListLayout(loadoutRow, 6, true)
	list = Theme.Scroller({ Position = UDim2.fromOffset(0, 108), Size = UDim2.new(1, 0, 1, -108) })
	list.Parent = content
	Theme.ListLayout(list, 8)
	Theme.Padding(list, 4)

	hud = Theme.New("Frame", {
		Name = "HeistHUD",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0.6, 0, 0, 132),
		BackgroundColor3 = Color3.fromRGB(28, 18, 22),
		BackgroundTransparency = 0.05,
		Visible = false,
		Parent = screen,
	})
	Theme.New("UISizeConstraint", { MaxSize = Vector2.new(560, 132), MinSize = Vector2.new(280, 0), Parent = hud })
	Theme.Corner(hud, 10)
	Theme.Stroke(hud, Color3.fromRGB(200, 70, 60), 2)
	Theme.Padding(hud, 8)
	hudStatus = Theme.Label("", { Font = Theme.Fonts.Bold, Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Left, Parent = hud }, 17)
	local meter = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLighter, Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 12), Parent = hud })
	Theme.Corner(meter, 6)
	meterFill = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.Gold, Size = UDim2.fromScale(0, 1), Parent = meter })
	Theme.Corner(meterFill, 6)
	hudObjective = Theme.Label("", { Position = UDim2.fromOffset(0, 40), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left, Parent = hud }, 15)
	hudTimer = Theme.Label("", { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Theme.Colors.TextDim, Parent = hud }, 14)
	local row = Theme.New("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 38), Parent = hud })
	Theme.ListLayout(row, 6, true)
	sneakButton = Theme.Button("Sneak", Theme.Colors.PanelLighter, function()
		ClientNet.Call("HeistAction", true, "Sneak")
	end, 15)
	sneakButton.Size = UDim2.new(1 / 3, -4, 1, 0)
	sneakButton.Parent = row
	jamButton = Theme.Button("Jam cameras", Theme.Colors.Blue, function()
		ClientNet.Call("HeistAction", true, "Jammer")
	end, 15)
	jamButton.Size = UDim2.new(1 / 3, -4, 1, 0)
	jamButton.Parent = row
	local abort = Theme.Button("Abort", Theme.Colors.Danger, function()
		ClientNet.Call("HeistAction", true, "Abort")
	end, 15)
	abort.Size = UDim2.new(1 / 3, -4, 1, 0)
	abort.Parent = row

	jail = Theme.New("Frame", {
		Name = "Jail",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0.5, 0, 0, 70),
		BackgroundColor3 = Color3.fromRGB(40, 40, 46),
		Visible = false,
		Parent = screen,
	})
	Theme.New("UISizeConstraint", { MaxSize = Vector2.new(460, 70), Parent = jail })
	Theme.Corner(jail, 10)
	Theme.Stroke(jail, Color3.fromRGB(200, 200, 210), 2)
	jailLabel = Theme.Label("", { Size = UDim2.fromScale(1, 1), Parent = jail }, 18)

	alertBanner = Theme.Label("", {
		BackgroundColor3 = Color3.fromRGB(150, 30, 30),
		BackgroundTransparency = 0.05,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 100),
		Size = UDim2.new(0.55, 0, 0, 34),
		Visible = false,
		Font = Theme.Fonts.Bold,
		Parent = screen,
	}, 17)
	Theme.Corner(alertBanner, 8)

	Remotes.Event("HeistUpdate").OnClientEvent:Connect(onHeistUpdate)
	Remotes.Event("JailUpdate").OnClientEvent:Connect(function(u)
		if type(u) ~= "table" then
			return
		end
		jail.Visible = u.Active == true
		jailLabel.Text = ("<b>HOLDING CELL</b> — released in %s\n<font size=\"14\">%s</font>"):format(Format.Seconds(u.SecondsLeft or 0), tostring(u.Reason or ""))
	end)
	local alertToken = 0
	Remotes.Event("SecurityAlert").OnClientEvent:Connect(function(a)
		if type(a) ~= "table" then
			return
		end
		alertToken += 1
		local token = alertToken
		alertBanner.Text = tostring(a.Text)
		alertBanner.BackgroundColor3 = if a.Kind == "Caught" then Color3.fromRGB(40, 120, 70) elseif a.Kind == "Fled" then Color3.fromRGB(70, 70, 80) else Color3.fromRGB(150, 30, 30)
		alertBanner.Visible = true
		if a.Kind == "Alarm" or a.Kind == "Intruder" then
			Sounds.Play("Alarm", 0.6, 0.7)
		end
		task.delay(8, function()
			if alertToken == token then
				alertBanner.Visible = false
			end
		end)
	end)
	ClientState.OnChanged(function()
		if Window.IsOpen(NAME) then
			drawLoadout()
		end
	end)
end

function HeistUI.Open()
	Window.Open(NAME)
end

return HeistUI
