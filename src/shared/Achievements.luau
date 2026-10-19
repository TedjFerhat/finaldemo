--[[
	Achievements
	One-time milestones. The server records each one in save data the moment
	it is earned, so the reward can never be paid twice.
]]

export type AchievementDef = {
	Id: string,
	Name: string,
	Description: string,
	RewardCash: number,
	Order: number,
}

local List: { AchievementDef } = {
	{ Id = "first_excavation", Name = "Breaking Ground", Description = "Complete your first excavation.", RewardCash = 150, Order = 1 },
	{ Id = "perfect_recovery", Name = "Steady Hands", Description = "Recover an artefact in Perfect condition.", RewardCash = 300, Order = 2 },
	{ Id = "rare_recovery", Name = "Rare Find", Description = "Excavate a Rare or better artefact.", RewardCash = 400, Order = 3 },
	{ Id = "hidden_cache", Name = "Signal Found", Description = "Dig up a hidden cache located with your scanner.", RewardCash = 300, Order = 4 },
	{ Id = "ruins_secret", Name = "The Watchers' Riddle", Description = "Open the secret chamber of the Forgotten Ruins.", RewardCash = 500, Order = 5 },
	{ Id = "jungle_guardians", Name = "Guardians Aligned", Description = "Open the inner sanctum of the Jungle Temple.", RewardCash = 800, Order = 6 },
	{ Id = "root_chamber", Name = "Under the Roots", Description = "Discover the hidden Root Chamber.", RewardCash = 600, Order = 7 },
	{ Id = "jaguar_heart", Name = "Heart of the Jaguar", Description = "Recover the treasure beneath the eagle's gaze.", RewardCash = 2500, Order = 8 },
	{ Id = "collection_complete", Name = "Curator", Description = "Complete any collection set.", RewardCash = 500, Order = 9 },
	{ Id = "heist_success", Name = "Phantom", Description = "Escape from a museum heist with an artefact.", RewardCash = 500, Order = 10 },
	{ Id = "museum_defended", Name = "Night Watch", Description = "Have a thief caught in your museum.", RewardCash = 500, Order = 11 },
	{ Id = "market_sale", Name = "Dealer", Description = "Sell an item on the Collectors' Market.", RewardCash = 250, Order = 12 },
	{ Id = "market_purchase", Name = "Collector's Eye", Description = "Buy an item on the Collectors' Market.", RewardCash = 250, Order = 13 },
	{ Id = "trade_complete", Name = "Fair Exchange", Description = "Complete a direct trade with another player.", RewardCash = 250, Order = 14 },
}

local Achievements = {}
Achievements.List = List
Achievements.ById = {} :: { [string]: AchievementDef }
for _, a in List do
	Achievements.ById[a.Id] = a
end

return Achievements
