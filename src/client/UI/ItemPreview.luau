--[[
	ItemPreview
	A ViewportFrame showing an item's 3D model (used in the inventory, the
	journal and the discovery pop-up).
]]

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local ItemModels = require(Shared.ItemModels)

local ItemPreview = {}

-- Creates a viewport. If `spin` is true the model slowly rotates while visible.
function ItemPreview.Create(itemId: string, spin: boolean?): ViewportFrame
	local viewport = Instance.new("ViewportFrame")
	viewport.BackgroundTransparency = 1
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.Ambient = Color3.fromRGB(170, 160, 150)
	viewport.LightColor = Color3.fromRGB(255, 240, 220)
	viewport.LightDirection = Vector3.new(-1, -1.5, 1)

	local world = Instance.new("WorldModel")
	world.Parent = viewport
	local model = ItemModels.Build(itemId)
	model.Parent = world

	local boxCFrame, size = model:GetBoundingBox()
	local center = boxCFrame.Position
	local radius = math.max(size.X, size.Y, size.Z)
	local camera = Instance.new("Camera")
	camera.FieldOfView = 35
	camera.CFrame = CFrame.lookAt(center + Vector3.new(radius * 0.35, radius * 0.45, -radius * 2.2), center)
	camera.Parent = viewport
	viewport.CurrentCamera = camera

	if spin then
		local pivot = model:GetPivot()
		local angle = 0
		local connection: RBXScriptConnection
		connection = RunService.RenderStepped:Connect(function(dt)
			if viewport.Parent == nil then
				connection:Disconnect()
				return
			end
			if viewport.Visible then
				angle += dt * 0.9
				model:PivotTo(CFrame.new(center) * CFrame.Angles(0, angle, 0) * CFrame.new(-center) * pivot)
			end
		end)
	end
	return viewport
end

return ItemPreview
