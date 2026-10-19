--[[
	EconomyService
	The ONLY place cash changes. Every other script asks this service to add or
	spend money, so there is exactly one cash system.
]]

local PlayerDataService = require(script.Parent.PlayerDataService)
local StateSync = require(script.Parent.StateSync)

local EconomyService = {}

local function isValidAmount(amount: number): boolean
	return type(amount) == "number" and amount == amount and amount >= 0 and amount < math.huge
end

local function updateLeaderstats(player: Player, cash: number)
	local stats = player:FindFirstChild("leaderstats")
	local value = stats and stats:FindFirstChild("Cash")
	if value and value:IsA("IntValue") then
		value.Value = math.floor(cash)
	end
end

function EconomyService.GetCash(player: Player): number
	local data = PlayerDataService.GetData(player)
	return if data then data.Cash else 0
end

-- Adds money (rounded down). `reason` is for debugging/analytics.
function EconomyService.Add(player: Player, amount: number, reason: string): boolean
	local data = PlayerDataService.GetData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	amount = math.floor(amount)
	data.Cash += amount
	data.Stats.TotalEarned += amount
	updateLeaderstats(player, data.Cash)
	StateSync.Mark(player)
	return true
end

-- Spends money if the player has enough. Returns true if paid.
function EconomyService.Spend(player: Player, amount: number, reason: string): boolean
	local data = PlayerDataService.GetData(player)
	if not data or not isValidAmount(amount) then
		return false
	end
	if PlayerDataService.IsBusy(player) then
		return false
	end
	amount = math.floor(amount)
	if data.Cash < amount then
		return false
	end
	data.Cash -= amount
	updateLeaderstats(player, data.Cash)
	StateSync.Mark(player)
	return true
end

function EconomyService.Init() end

function EconomyService.Start()
	PlayerDataService.OnLoaded(function(player, profile)
		local stats = player:FindFirstChild("leaderstats")
		if not stats then
			stats = Instance.new("Folder")
			stats.Name = "leaderstats"
			stats.Parent = player
		end
		for _, name in { "Cash", "Prestige" } do
			if not stats:FindFirstChild(name) then
				local v = Instance.new("IntValue")
				v.Name = name
				v.Parent = stats
			end
		end
		updateLeaderstats(player, profile.Data.Cash)
	end)
end

return EconomyService
