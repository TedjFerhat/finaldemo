--[[
	Main (server entry point)
	Builds the world, then initialises and starts every service in order.
	PlayerDataService starts LAST so every other service has registered its
	"when a player's data loads" callbacks before anyone's data loads.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Services = script.Parent.Services
local WorldBuilder = require(script.Parent.World.WorldBuilder)

-- 1. Create all RemoteEvents/RemoteFunctions
Remotes.Event("StateUpdated")

-- 2. Generate the map (each zone is protected inside WorldBuilder.Build)
WorldBuilder.Build()

-- 3. Services
local order = {
	"PlayerDataService",
	"StateSync",
	"EconomyService",
	"AchievementService",
	"ProgressionService",
	"InventoryService",
	"LedgerService",
	"PlotService",
	"MuseumService",
	"SecurityService",
	"DiscoveryService",
	"ChallengeService",
	"ExcavationService",
	"PuzzleService",
	"ExplorationService",
	"VisitorService",
	"EquipmentService",
	"MonetizationService",
	"JailService",
	"HeistService",
	"MarketService",
	"TradeService",
	"HubService",
}

local modules = {}
-- Every step is protected: if one system has a bug, it is reported clearly
-- in Output and everything else (saving, plots, museums, travel) keeps working.
local failures = 0
local function safely(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		failures += 1
		warn(("[MuseumTycoon] %s FAILED: %s\n%s"):format(label, tostring(err), debug.traceback()))
	end
end

for _, name in order do
	safely("require " .. name, function()
		modules[name] = require(Services:WaitForChild(name)) :: any
	end)
end
for _, name in order do
	if modules[name] then
		safely(name .. ".Init", modules[name].Init)
	end
end
for _, name in order do
	if name ~= "PlayerDataService" and modules[name] then
		safely(name .. ".Start", modules[name].Start)
	end
end
-- Player loading starts last and must always run.
modules.PlayerDataService.Start()

print(("[MuseumTycoon] Server started%s."):format(if failures > 0 then (" with %d problem(s) — see the warnings above"):format(failures) else ""))
