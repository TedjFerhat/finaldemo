--[[
	Dialog
	Small modal cards used across the game:
	  • Dialog.Choice  — a question with 1–4 buttons (confirmations, tool
	                     choice, trade requests). Buttons disable themselves
	                     after a click to prevent double submissions.
	  • Dialog.Card    — a parchment card for inscriptions / clues.
	Only one dialog is shown at a time; a new one replaces the old one.
]]

local TweenService = game:GetService("TweenService")

local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)

local Dialog = {}

export type Option = { Text: string, Color: Color3?, OnClick: (() -> ())? }

local screen: ScreenGui
local current: Frame? = nil

function Dialog.Init(screenGui: ScreenGui)
	screen = screenGui
end

function Dialog.Close()
	if current then
		current:Destroy()
		current = nil
	end
end

local function frame(width: number, height: number, color: Color3?): Frame
	Dialog.Close()
	local f = Theme.New("Frame", {
		Name = "Dialog",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, height),
		BackgroundColor3 = color or Theme.Colors.Panel,
		ZIndex = 30,
		Parent = screen,
	})
	Theme.New("UISizeConstraint", { MaxSize = Vector2.new(width, height), Parent = f })
	Theme.Corner(f, 12)
	Theme.Stroke(f, Theme.Colors.Gold, 2.5)
	Theme.Padding(f, 14)
	local scale = Theme.New("UIScale", { Scale = 0.85, Parent = f })
	TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	current = f
	Sounds.Play("Open", 0.3)
	return f
end

-- Shows a choice. Every option closes the dialog unless it returns false.
function Dialog.Choice(title: string, body: string, options: { Option }, timeoutSeconds: number?)
	local f = frame(460, 240)
	Theme.Label(title, {
		Font = Theme.Fonts.Title,
		TextColor3 = Theme.Colors.Gold,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, 0, 0, 28),
		ZIndex = 31,
		Parent = f,
	}, 22)
	Theme.Label(body, {
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.fromOffset(0, 32),
		Size = UDim2.new(1, 0, 1, -90),
		ZIndex = 31,
		Parent = f,
	}, 16)
	local row = Theme.New("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.new(1, 0, 0, 46),
		ZIndex = 31,
		Parent = f,
	})
	Theme.ListLayout(row, 8, true).HorizontalAlignment = Enum.HorizontalAlignment.Right
	local clicked = false
	for i, option in options do
		local b = Theme.Button(option.Text, option.Color or Theme.Colors.Success, function()
			if clicked then
				return
			end
			clicked = true
			Dialog.Close()
			if option.OnClick then
				option.OnClick()
			end
		end, 17)
		b.Size = UDim2.new(1 / #options, -8, 1, 0)
		b.LayoutOrder = i
		b.ZIndex = 32
		b.Parent = row
	end
	if timeoutSeconds then
		local mine = f
		task.delay(timeoutSeconds, function()
			if current == mine then
				Dialog.Close()
			end
		end)
	end
end

-- Parchment card for clues and inscriptions.
function Dialog.Card(title: string, text: string)
	local f = frame(480, 260, Theme.Colors.Parchment)
	Theme.Label(title, {
		Font = Theme.Fonts.Title,
		TextColor3 = Color3.fromRGB(110, 70, 30),
		Size = UDim2.new(1, 0, 0, 30),
		ZIndex = 31,
		Parent = f,
	}, 22)
	Theme.Label(text, {
		Font = Enum.Font.Fondamento,
		TextColor3 = Color3.fromRGB(60, 40, 20),
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 36),
		Size = UDim2.new(1, 0, 1, -86),
		ZIndex = 31,
		Parent = f,
	}, 20)
	local ok = Theme.Button("Noted in journal", Color3.fromRGB(120, 85, 45), function()
		Dialog.Close()
	end, 16)
	ok.AnchorPoint = Vector2.new(0.5, 1)
	ok.Position = UDim2.fromScale(0.5, 1)
	ok.Size = UDim2.fromOffset(200, 40)
	ok.ZIndex = 32
	ok.Parent = f
end

return Dialog
