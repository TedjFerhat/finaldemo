--[[
	FlyController (client)
	Moves YOUR character while the server says you may fly.

	  • The server alone decides: it sets the player attribute "FlyActive"
	    after checking the Game Pass and the game state. This script never
	    starts flying on its own, so editing/exploiting the client cannot give
	    anyone the ability (and the server watchdog ends impossible flights).
	  • Controls: F toggles (or the Fly button). Move = normal movement keys /
	    thumbstick relative to the camera (look up to climb). Space / A = up,
	    Left Ctrl / Q / B = down. On touch screens Up / Down buttons appear.
	  • Flight stops cleanly on death, respawn, or when the server turns it off.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetization = require(Shared.Monetization)

local Theme = require(script.Parent.Parent.UI.Theme)
local ClientNet = require(script.Parent.Parent.ClientNet)
local ClientState = require(script.Parent.Parent.ClientState)

local FlyController = {}

local player = Players.LocalPlayer
local cfg = Monetization.Fly

local indicator: Frame
local flyButton: TextButton
local upButton: TextButton
local downButton: TextButton

local renderConn: RBXScriptConnection? = nil
local diedConn: RBXScriptConnection? = nil
local created: { Instance } = {}
local velocity = Vector3.zero
local holdUp, holdDown = false, false
local controls: any = nil

local function getControls(): any
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 3)
		return module and (require(module) :: any):GetControls()
	end)
	if ok and result then
		controls = result
	end
	return controls
end

local function humanoidAndRoot(): (Humanoid?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if hum and root and root:IsA("BasePart") then
		return hum, root
	end
	return nil, nil
end

local function stopFlying()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	if diedConn then
		diedConn:Disconnect()
		diedConn = nil
	end
	for _, inst in created do
		inst:Destroy()
	end
	table.clear(created)
	velocity = Vector3.zero
	holdUp, holdDown = false, false
	local hum = humanoidAndRoot()
	if hum and hum.Health > 0 then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
end

local function verticalInput(): number
	local up = holdUp or UserInputService:IsKeyDown(Enum.KeyCode.Space) or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonA)
	local down = holdDown
		or UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or UserInputService:IsKeyDown(Enum.KeyCode.Q)
		or UserInputService:IsGamepadButtonDown(Enum.UserInputType.Gamepad1, Enum.KeyCode.ButtonB)
	return (if up then 1 else 0) - (if down then 1 else 0)
end

local function startFlying()
	local hum, root = humanoidAndRoot()
	if not hum or not root or hum.Health <= 0 then
		return
	end
	stopFlying()

	local att = Instance.new("Attachment")
	att.Name = "FlyAttachment"
	att.Parent = root

	local lv = Instance.new("LinearVelocity")
	lv.Name = "FlyVelocity"
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root

	local ao = Instance.new("AlignOrientation")
	ao.Name = "FlyOrientation"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = false
	ao.MaxTorque = math.huge
	ao.Responsiveness = 20
	ao.CFrame = root.CFrame
	ao.Parent = root

	created = { att, lv, ao }
	hum.PlatformStand = true
	diedConn = hum.Died:Connect(stopFlying)

	renderConn = RunService.RenderStepped:Connect(function(dt)
		local cam = workspace.CurrentCamera
		if not cam or not root.Parent then
			return
		end
		-- movement relative to the camera (includes pitch: look up to climb)
		local dir = Vector3.zero
		local ctl = getControls()
		local okMove, mv = false, nil
		if ctl then
			okMove, mv = pcall(function()
				return ctl:GetMoveVector()
			end)
		end
		if okMove and mv then
			dir = cam.CFrame:VectorToWorldSpace(mv)
		else
			dir = hum.MoveDirection
		end
		local target = dir * cfg.Speed + Vector3.new(0, verticalInput() * cfg.VerticalSpeed, 0)
		if target.Magnitude > cfg.Speed * 1.2 then
			target = target.Unit * cfg.Speed * 1.2
		end
		velocity = velocity:Lerp(target, 1 - math.exp(-8 * dt))
		lv.VectorVelocity = velocity

		local look = cam.CFrame.LookVector
		local flat = Vector3.new(look.X, 0, look.Z)
		if flat.Magnitude > 0.01 then
			ao.CFrame = CFrame.lookAt(root.Position, root.Position + flat)
		end
	end)
end

local function refreshUi()
	local state = ClientState.Get()
	local owns = state ~= nil and state.Premium ~= nil and state.Premium.Fly == true
	local active = player:GetAttribute("FlyActive") == true
	flyButton.Visible = owns
	flyButton.Text = if active then "🪽 Land (F)" else "🪽 Fly (F)"
	indicator.Visible = active
	local touch = UserInputService.TouchEnabled
	upButton.Visible = active and touch
	downButton.Visible = active and touch
end

local function onFlyAttribute()
	if player:GetAttribute("FlyActive") == true then
		startFlying()
	else
		stopFlying()
	end
	refreshUi()
end

local function toggle()
	-- The server decides. If we're not allowed it answers with the reason (shown as a toast).
	local wantOn = player:GetAttribute("FlyActive") ~= true
	task.spawn(function()
		ClientNet.Call("SetFly", true, wantOn)
	end)
end

local function holdButton(b: TextButton, set: (boolean) -> ())
	b.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			set(true)
		end
	end)
	b.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			set(false)
		end
	end)
end

function FlyController.Init(screen: ScreenGui)
	local touch = UserInputService.TouchEnabled

	indicator = Theme.New("Frame", {
		Name = "FlyIndicator",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 12),
		Size = UDim2.fromOffset(250, 34),
		BackgroundColor3 = Theme.Colors.WoodDark,
		BackgroundTransparency = 0.15,
		Visible = false,
		Parent = screen,
	})
	Theme.Corner(indicator, 17)
	Theme.Label("🪽 FLYING — F to land", { Size = UDim2.fromScale(1, 1), TextColor3 = Theme.Colors.ButtonText, Parent = indicator }, 16)

	flyButton = Theme.Button("🪽 Fly (F)", Theme.Colors.Blue, toggle, 16)
	flyButton.AnchorPoint = Vector2.new(1, 1)
	flyButton.Position = if touch then UDim2.new(1, -16, 1, -310) else UDim2.new(1, -16, 1, -24)
	flyButton.Size = UDim2.fromOffset(touch and 120 or 130, 44)
	flyButton.Visible = false
	flyButton.Parent = screen

	upButton = Theme.Button("▲ Up", Theme.Colors.Success, nil, 16)
	upButton.AnchorPoint = Vector2.new(1, 1)
	upButton.Position = UDim2.new(1, -16, 1, -240)
	upButton.Size = UDim2.fromOffset(120, 56)
	upButton.Visible = false
	upButton.Parent = screen
	holdButton(upButton, function(v)
		holdUp = v
	end)

	downButton = Theme.Button("▼ Down", Theme.Colors.Danger, nil, 16)
	downButton.AnchorPoint = Vector2.new(1, 1)
	downButton.Position = UDim2.new(1, -16, 1, -170)
	downButton.Size = UDim2.fromOffset(120, 56)
	downButton.Visible = false
	downButton.Parent = screen
	holdButton(downButton, function(v)
		holdDown = v
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == cfg.Key then
			toggle()
		end
	end)

	player:GetAttributeChangedSignal("FlyActive"):Connect(onFlyAttribute)
	player.CharacterAdded:Connect(function()
		stopFlying() -- the server also clears the attribute for the new character
		refreshUi()
	end)
	player.CharacterRemoving:Connect(stopFlying)
	ClientState.OnChanged(refreshUi)
	onFlyAttribute()
end

return FlyController
