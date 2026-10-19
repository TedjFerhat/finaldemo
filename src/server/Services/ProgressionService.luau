--[[
	ProgressionService
	• Collection journal (what each player has ever discovered)
	• Collection set rewards (paid ONCE per set, recorded in save data)
	• Prestige score
	• Museum income formula (the single source of truth for revenue)
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.ItemCatalog)
local CollectionSets = require(Shared.CollectionSets)
local Rarities = require(Shared.Rarities)
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local StateSync = require(script.Parent.StateSync)
local AchievementService = require(script.Parent.AchievementService)
local Notifier = require(script.Parent.Parent.Util.Notifier)

local ProgressionService = {}

local TITLES = {
	{ Prestige = 0, Title = "Hobby Collector" },
	{ Prestige = 50, Title = "Curious Curator" },
	{ Prestige = 150, Title = "Field Archaeologist" },
	{ Prestige = 350, Title = "Renowned Curator" },
	{ Prestige = 700, Title = "Master of Antiquities" },
	{ Prestige = 1200, Title = "Legendary Collector" },
}

function ProgressionService.GetLevel(data: any): number
	return Upgrades.ComputeLevel(data.Upgrades)
end

function ProgressionService.ComputePrestige(data: any): number
	local prestige = 0
	for itemId in data.Journal.Discovered do
		local def = ItemCatalog.Get(itemId)
		if def then
			prestige += Rarities.Get(def.Rarity).PrestigePoints
		end
	end
	for setId in data.Journal.CompletedSets do
		local set = CollectionSets.ById[setId]
		if set then
			prestige += set.RewardPrestige
		end
	end
	for _, uid in data.Displays do
		local item = data.Inventory[uid]
		local def = item and not item.Reserved and ItemCatalog.Get(item.Id)
		if def then
			prestige += Rarities.Get(def.Rarity).PrestigePoints
		end
	end
	for _ in data.Achievements do
		prestige += 5
	end
	prestige += (ProgressionService.GetLevel(data) - 1) * 10
	return prestige
end

function ProgressionService.TitleFor(prestige: number): string
	local title = TITLES[1].Title
	for _, t in TITLES do
		if prestige >= t.Prestige then
			title = t.Title
		end
	end
	return title
end

export type IncomeBreakdown = {
	Base: number,
	Variety: number,
	Decor: number,
	Level: number,
	Prestige: number,
	PerMinute: number,
}

-- Income per minute from everything on display.
function ProgressionService.ComputeIncome(data: any, prestige: number?): IncomeBreakdown
	local base = 0
	local copies: { [string]: number } = {}
	local categories: { [string]: boolean } = {}
	local categoryCount = 0

	for _, uid in data.Displays do
		local item = data.Inventory[uid]
		-- Reserved = currently being stolen: it earns nothing while missing.
		local def = item and not item.Reserved and ItemCatalog.Get(item.Id)
		if def then
			local n = (copies[def.Id] or 0) + 1
			copies[def.Id] = n
			local income = ItemCatalog.InstanceIncome(def, item.Condition)
			base += if n == 1 then income else income * Config.DuplicateDisplayFactor
			if not categories[def.Category] then
				categories[def.Category] = true
				categoryCount += 1
			end
		end
	end

	local variety = math.min(Config.MaxVarietyBonus, math.max(0, categoryCount - 1) * Config.VarietyBonusPerCategory)
	local decor = Upgrades.IncomeBonus(data.Upgrades)
	local level = (ProgressionService.GetLevel(data) - 1) * Config.LevelIncomeBonus
	local p = prestige or ProgressionService.ComputePrestige(data)
	local prestigeBonus = math.min(Config.MaxPrestigeIncomeBonus, p / Config.PrestigeIncomeDivisor)

	local perMinute = base * (1 + variety) * (1 + decor) * (1 + level) * (1 + prestigeBonus)
	return {
		Base = base,
		Variety = variety,
		Decor = decor,
		Level = level,
		Prestige = prestigeBonus,
		PerMinute = perMinute,
	}
end

-- How much revenue the ticket desk can hold.
function ProgressionService.RevenueCap(perMinute: number): number
	return math.max(Config.MinimumRevenueStorage, math.floor(perMinute * Config.RevenueStorageMinutes))
end

local function checkSets(player: Player, data: any)
	for _, set in CollectionSets.List do
		if not data.Journal.CompletedSets[set.Id] then
			local complete = true
			for _, itemId in set.Items do
				if not data.Journal.Discovered[itemId] then
					complete = false
					break
				end
			end
			if complete then
				-- Record FIRST so the reward can never be paid twice.
				data.Journal.CompletedSets[set.Id] = true
				EconomyService.Add(player, set.RewardCash, "SetReward:" .. set.Id)
				Notifier.Send(
					player,
					("Collection complete: %s! +%s and +%d prestige"):format(set.Name, Format.Cash(set.RewardCash), set.RewardPrestige),
					"Reward"
				)
				AchievementService.Award(player, "collection_complete")
			end
		end
	end
end

-- Call whenever a player obtains an item (search, starter gift, future trades).
function ProgressionService.RecordDiscovery(player: Player, itemId: string)
	local data = PlayerDataService.GetData(player)
	if not data or not ItemCatalog.Exists(itemId) then
		return
	end
	local isNew = data.Journal.Discovered[itemId] == nil
	data.Journal.Discovered[itemId] = (data.Journal.Discovered[itemId] or 0) + 1
	if isNew then
		checkSets(player, data)
	end
	StateSync.Mark(player)
end

-- Journal clues: returns true the first time a clue is found.
function ProgressionService.RecordClue(player: Player, clueId: string, text: string?): boolean
	local data = PlayerDataService.GetData(player)
	if not data or data.Journal.Clues[clueId] then
		return false
	end
	data.Journal.Clues[clueId] = text or "?"
	Notifier.Send(player, "New clue added to your journal.", "Info")
	StateSync.Mark(player)
	return true
end

function ProgressionService.HasClue(player: Player, clueId: string): boolean
	local data = PlayerDataService.GetData(player)
	return data ~= nil and data.Journal.Clues[clueId] ~= nil
end

function ProgressionService.RecordPuzzle(player: Player, puzzleId: string): boolean
	local data = PlayerDataService.GetData(player)
	if not data then
		return false
	end
	local isNew = data.Journal.Puzzles[puzzleId] == nil
	data.Journal.Puzzles[puzzleId] = (data.Journal.Puzzles[puzzleId] or 0) + 1
	StateSync.Mark(player)
	return isNew
end

function ProgressionService.RecordExcavation(player: Player, zoneId: string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	data.Journal.Excavations[zoneId] = (data.Journal.Excavations[zoneId] or 0) + 1
	data.Stats.Excavated += 1
	StateSync.Mark(player)
end

function ProgressionService.RecordZoneVisit(player: Player, zoneId: string)
	local data = PlayerDataService.GetData(player)
	if data and not data.Journal.ZonesVisited[zoneId] then
		data.Journal.ZonesVisited[zoneId] = true
		StateSync.Mark(player)
	end
end

function ProgressionService.Init() end

function ProgressionService.Start()
	StateSync.AddProvider(function(player, data, snapshot)
		local prestige = ProgressionService.ComputePrestige(data)
		local income = ProgressionService.ComputeIncome(data, prestige)
		local level = ProgressionService.GetLevel(data)
		snapshot.Level = level
		snapshot.LevelName = Upgrades.LevelNames[level]
		snapshot.Prestige = prestige
		snapshot.Title = ProgressionService.TitleFor(prestige)
		snapshot.Income = income
		snapshot.RevenueCap = ProgressionService.RevenueCap(income.PerMinute)
		snapshot.HasSecurity = Upgrades.HasSecurity(data.Upgrades)

		player:SetAttribute("MuseumLevel", level)
		player:SetAttribute("Prestige", prestige)
		player:SetAttribute("Title", snapshot.Title)
		local stats = player:FindFirstChild("leaderstats")
		local p = stats and stats:FindFirstChild("Prestige")
		if p and p:IsA("IntValue") then
			p.Value = prestige
		end
	end)
	PlayerDataService.OnLoaded(function(player, profile)
		-- Re-check in case set definitions were added since the last session.
		checkSets(player, profile.Data)
	end)
end

return ProgressionService
