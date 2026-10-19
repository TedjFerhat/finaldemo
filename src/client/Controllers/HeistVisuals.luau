--[[
	HeistVisuals
	Heist-only objects (the after-hours shutter, Pick Lock / Steal prompts,
	the owner's Apprehend prompt) are tagged "HeistOnly" with a HeistFor
	attribute. Everyone except that player hides them locally. This is only
	presentation — the server checks who triggered every prompt.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local HeistVisuals = {}

local me = Players.LocalPlayer

local function apply(inst: Instance)
	local target = inst:GetAttribute("HeistFor")
	local mine = target == me.UserId
	if inst:IsA("ProximityPrompt") then
		inst.Enabled = mine
	elseif inst:IsA("BasePart") then
		inst.LocalTransparencyModifier = if mine then 0 else 1
	end
end

function HeistVisuals.Init()
	for _, inst in CollectionService:GetTagged("HeistOnly") do
		apply(inst)
	end
	CollectionService:GetInstanceAddedSignal("HeistOnly"):Connect(function(inst)
		task.defer(apply, inst) -- attributes arrive with the instance
	end)
end

return HeistVisuals
