--[[
	AchievementService
	Awards one-time achievements. The achievement is recorded in save data
	BEFORE the cash reward is paid, so it can never pay out twice.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Achievements = require(Shared.Achievements)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local StateSync = require(script.Parent.StateSync)
local Notifier = require(script.Parent.Parent.Util.Notifier)

local AchievementService = {}

function AchievementService.Award(player: Player, achievementId: string): boolean
	local def = Achievements.ById[achievementId]
	local data = PlayerDataService.GetData(player)
	if not def or not data then
		if not def then
			warn("[Achievements] Unknown achievement id: " .. tostring(achievementId))
		end
		return false
	end
	if data.Achievements[achievementId] then
		return false
	end
	data.Achievements[achievementId] = os.time()
	if def.RewardCash > 0 then
		EconomyService.Add(player, def.RewardCash, "Achievement:" .. achievementId)
	end
	Notifier.Send(player, ("Achievement unlocked: %s! +%s"):format(def.Name, Format.Cash(def.RewardCash)), "Reward")
	StateSync.Mark(player)
	return true
end

function AchievementService.Init() end
function AchievementService.Start() end

return AchievementService
