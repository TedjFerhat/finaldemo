--[[
	ZoneLighting
	Changes the mood when you travel: warm afternoon at the museums, a hazy
	golden dusk in the Forgotten Ruins. Only changes YOUR screen.
]]

local Lighting = game:GetService("Lighting")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ZoneLighting = {}

-- Balanced daylight presets (same values the server sets for the museum).
-- Museum = neutral, ruins = warm desert, jungle = green and a little humid.
local PRESETS = {
	Museum = {
		Lighting = { ClockTime = 15.6, Brightness = 1.7, ExposureCompensation = -0.65, Ambient = Color3.fromRGB(86, 76, 64), OutdoorAmbient = Color3.fromRGB(104, 100, 98) },
		Atmosphere = { Density = 0.32, Haze = 0.9, Color = Color3.fromRGB(222, 210, 192) },
		Color = { Saturation = 0.03, Contrast = 0.06, TintColor = Color3.fromRGB(255, 248, 238) },
	},
	JungleTemple = {
		Lighting = { ClockTime = 14, Brightness = 1.6, ExposureCompensation = -0.1, Ambient = Color3.fromRGB(60, 70, 60), OutdoorAmbient = Color3.fromRGB(96, 112, 96) },
		Atmosphere = { Density = 0.36, Haze = 0.8, Color = Color3.fromRGB(196, 220, 196) },
		Color = { Saturation = 0.06, Contrast = 0.05, TintColor = Color3.fromRGB(244, 255, 244) },
	},
	ForgottenRuins = {
		Lighting = { ClockTime = 15, Brightness = 1.9, ExposureCompensation = -0.15, Ambient = Color3.fromRGB(78, 70, 62), OutdoorAmbient = Color3.fromRGB(122, 112, 100) },
		Atmosphere = { Density = 0.3, Haze = 0.6, Color = Color3.fromRGB(232, 214, 188) },
		Color = { Saturation = 0.04, Contrast = 0.05, TintColor = Color3.fromRGB(255, 248, 238) },
	},
}

local function apply(zoneId: string)
	local preset = PRESETS[zoneId] or PRESETS.Museum
	local info = TweenInfo.new(1.5, Enum.EasingStyle.Sine)
	TweenService:Create(Lighting, info, preset.Lighting):Play()
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		TweenService:Create(atmosphere, info, preset.Atmosphere):Play()
	end
	local cc = Lighting:FindFirstChild("ZoneColor")
	if cc and cc:IsA("ColorCorrectionEffect") then
		TweenService:Create(cc, info, preset.Color):Play()
	end
end

function ZoneLighting.Init()
	Remotes.Event("ZoneChanged").OnClientEvent:Connect(function(zoneId)
		if type(zoneId) == "string" then
			apply(zoneId)
		end
	end)
end

return ZoneLighting
