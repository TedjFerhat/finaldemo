--[[
	Window
	Creates the menu windows (Inventory, Museum, Journal...) and makes sure
	only one is open at a time. Each window is a centred panel with a title
	bar, a close button and a Content frame.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)

local Window = {}

type WindowRecord = { Frame: Frame, Content: Frame, Title: TextLabel, OnOpen: (() -> ())? }

local windows: { [string]: WindowRecord } = {}
local openName: string? = nil
local screen: ScreenGui
local changedCallbacks: { (string?) -> () } = {}

function Window.Init(screenGui: ScreenGui)
	screen = screenGui
end

function Window.Create(name: string, title: string, onOpen: (() -> ())?): Frame
	-- Carved wood frame around a parchment panel, a cream title board that
	-- sits on the top edge, and a red close button on the corner.
	local holder, frame = Theme.Card({
		Name = name .. "Window",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromScale(0.9, 0.76),
		Visible = false,
		ZIndex = 5,
		Parent = screen,
	}, 22, 10)
	Theme.New("UISizeConstraint", { MaxSize = Vector2.new(780, 500), Parent = holder })
	Theme.New("UIScale", { Name = "OpenScale", Parent = holder })

	-- Title board (with a darker "roof" beam behind it)
	local board = Theme.New("Frame", {
		Name = "TitleBoard",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0, 4),
		Size = UDim2.new(0.46, 0, 0, 50),
		BackgroundColor3 = Theme.Colors.Board,
		ZIndex = 8,
		Parent = holder,
	})
	Theme.New("UISizeConstraint", { MinSize = Vector2.new(220, 50), MaxSize = Vector2.new(360, 50), Parent = board })
	Theme.Corner(board, 10)
	Theme.New("UIStroke", { Color = Theme.Colors.Outline, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = board })
	Theme.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(232, 214, 184)), Parent = board })
	local roof = Theme.New("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0, 6),
		Size = UDim2.new(1, 22, 0, 14),
		BackgroundColor3 = Theme.Colors.WoodDark,
		ZIndex = 7,
		Parent = board,
	})
	Theme.Corner(roof, 6)
	Theme.New("UIStroke", { Color = Theme.Colors.Outline, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = roof })
	local titleLabel = Theme.Label(string.upper(title), {
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Text,
		Position = UDim2.fromOffset(12, 6),
		Size = UDim2.new(1, -24, 1, -12),
		ZIndex = 9,
		Parent = board,
	}, 28)

	-- Red close button on the top-right corner
	local close = Theme.Button("X", Theme.Colors.Danger, function()
		Window.Close()
	end, 24)
	close.AnchorPoint = Vector2.new(0.5, 0.5)
	close.Position = UDim2.new(1, -14, 0, 14)
	close.Size = UDim2.fromOffset(44, 44)
	close.ZIndex = 9
	close.TextColor3 = Color3.new(1, 1, 1)
	local closeStroke = close:FindFirstChildOfClass("UIStroke")
	if closeStroke then
		closeStroke.Color = Theme.Colors.Board
		closeStroke.Thickness = 3
	end
	close.Parent = holder

	local content = Theme.New("Frame", {
		Name = "Content",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 36),
		Size = UDim2.new(1, -32, 1, -50),
		Parent = frame,
	})

	windows[name] = { Frame = holder, Content = content, Title = titleLabel, OnOpen = onOpen }
	return content
end

function Window.SetTitle(name: string, title: string)
	local w = windows[name]
	if w then
		w.Title.Text = string.upper(title)
	end
end

function Window.Open(name: string)
	local w = windows[name]
	if not w then
		return
	end
	if openName and openName ~= name and windows[openName] then
		windows[openName].Frame.Visible = false
	end
	openName = name
	w.Frame.Visible = true
	local scale = w.Frame:FindFirstChild("OpenScale") :: UIScale
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.28, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	Sounds.Play("Open", 0.3)
	if w.OnOpen then
		task.spawn(w.OnOpen)
	end
	for _, cb in changedCallbacks do
		task.spawn(cb, openName)
	end
end

function Window.Toggle(name: string)
	if openName == name then
		Window.Close()
	else
		Window.Open(name)
	end
end

function Window.Close()
	if openName and windows[openName] then
		windows[openName].Frame.Visible = false
	end
	openName = nil
	for _, cb in changedCallbacks do
		task.spawn(cb, nil)
	end
end

function Window.IsOpen(name: string): boolean
	return openName == name
end

function Window.OnChanged(callback: (string?) -> ())
	table.insert(changedCallbacks, callback)
end

return Window
