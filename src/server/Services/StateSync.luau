--[[
	StateSync
	Sends each player a snapshot of THEIR OWN state (cash, inventory, museum...)
	whenever something changes. Services call StateSync.Mark(player); many
	changes in the same moment are merged into one network message.

	Other services add extra computed fields with StateSync.AddProvider.
	The client never sends state back — it only displays it.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local PlayerDataService = require(script.Parent.PlayerDataService)

local StateSync = {}

local providers: { (Player, any, { [string]: any }) -> () } = {}
local scheduled: { [Player]: boolean } = {}

-- provider(player, profileData, snapshot) adds fields to the snapshot.
function StateSync.AddProvider(provider: (Player, any, { [string]: any }) -> ())
	table.insert(providers, provider)
end

local function send(player: Player)
	scheduled[player] = nil
	local data = PlayerDataService.GetData(player)
	if not data or player.Parent == nil then
		return
	end

	-- Reverse lookup: which slot is each item displayed in?
	local displayedIn: { [string]: string } = {}
	for slotId, uid in data.Displays do
		displayedIn[uid] = slotId
	end

	local inventory = {}
	for uid, item in data.Inventory do
		table.insert(inventory, {
			Uid = uid,
			Id = item.Id,
			Found = item.Found,
			Zone = item.Zone,
			Locked = item.Locked,
			DisplayedIn = displayedIn[uid],
			Condition = item.Condition,
			Provenance = item.Provenance,
			Charges = item.Charges,
			Bound = item.Bound,
			Reserved = if item.Reserved then item.Reserved.Kind else nil,
		})
	end

	local snapshot: { [string]: any } = {
		Cash = data.Cash,
		Upgrades = data.Upgrades,
		Displays = data.Displays,
		Inventory = inventory,
		ToolTier = data.ToolTier,
		Journal = data.Journal,
		Stats = data.Stats,
		PendingRevenue = math.floor(data.PendingRevenue),
		Security = data.Security,
		Attachments = data.Attachments,
		Achievements = data.Achievements,
		DisplayRot = data.DisplayRot,
		HeistStats = {
			Attempts = data.Heist.Attempts,
			Successes = data.Heist.Successes,
			Captures = data.Heist.Captures,
			Defended = data.Heist.Defended,
			Robbed = data.Heist.Robbed,
			CooldownLeft = math.max(0, data.Heist.CooldownUntil - os.time()),
			ProtectedLeft = math.max(0, data.Heist.ProtectedUntil - os.time()),
		},
		Incidents = data.Heist.Incidents,
		SaveEnabled = player:GetAttribute("SaveDisabled") ~= true,
	}
	for _, provider in providers do
		local ok, err = pcall(provider, player, data, snapshot)
		if not ok then
			warn("[StateSync] provider error: " .. tostring(err))
		end
	end
	Remotes.Event("StateUpdated"):FireClient(player, snapshot)
end

function StateSync.Mark(player: Player)
	if scheduled[player] then
		return
	end
	scheduled[player] = true
	task.delay(0.1, send, player)
end

function StateSync.Init() end

function StateSync.Start()
	PlayerDataService.OnLoaded(function(player)
		StateSync.Mark(player)
	end)
end

return StateSync
