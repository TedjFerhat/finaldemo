--[[
	SettingsPanel
	Client-only preferences (they don't change gameplay): sound effects and
	the objective hint. Remembered for this session.
]]

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local Sounds = require(script.Parent.Sounds)

local SettingsPanel = {}

local NAME = "Settings"

type Toggle = { Label: string, Get: () -> boolean, Set: (boolean) -> () }

local state = { Sound = true, Objective = true }
local objectiveSetter: ((boolean) -> ())? = nil

function SettingsPanel.SetObjectiveSetter(fn: (boolean) -> ())
	objectiveSetter = fn
end

function SettingsPanel.Init()
	local content = Window.Create(NAME, "Settings")
	Theme.ListLayout(content, 8)
	local toggles: { Toggle } = {
		{ Label = "Sound effects", Get = function() return state.Sound end, Set = function(on)
			state.Sound = on
			Sounds.SetEnabled(on)
		end },
		{ Label = "Show objective hint", Get = function() return state.Objective end, Set = function(on)
			state.Objective = on
			if objectiveSetter then
				objectiveSetter(on)
			end
		end },
	}
	for i, t in toggles do
		local row = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.PanelLight, Size = UDim2.new(1, 0, 0, 48), LayoutOrder = i, Parent = content })
		Theme.Corner(row, Theme.Tokens.RadiusSmall)
		Theme.Label(t.Label, { TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -130, 1, -16), Parent = row }, 18)
		local button: TextButton
		local function paint()
			local on = t.Get()
			button.Text = if on then "ON" else "OFF"
			button.BackgroundColor3 = if on then Theme.Colors.Accent else Theme.Colors.PanelLighter
		end
		button = Theme.Button("", Theme.Colors.Accent, function()
			t.Set(not t.Get())
			paint()
		end, 16)
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.fromOffset(90, 34)
		button.Parent = row
		paint()
	end
	Theme.Label("These only affect your screen. Gameplay is unchanged.", { TextColor3 = Theme.Colors.TextDim, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 99, Parent = content }, 14)
end

function SettingsPanel.Open()
	Window.Open(NAME)
end

return SettingsPanel
