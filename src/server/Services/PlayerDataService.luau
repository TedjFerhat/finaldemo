--[[
	PlayerDataService
	The ONLY script that reads or writes player save data.

	Safety features:
	  • Session locking — a server "locks" a player's save while they play there.
	    Another server that tries to load the same player waits (or the player is
	    asked to rejoin) instead of loading stale data. This prevents item
	    duplication by quickly hopping between servers.
	  • Failed loads NEVER create a blank profile that could be saved over real
	    data — the player is kicked with a friendly message instead.
	  • Retries with limits, autosave, save on leave, save on server shutdown.
	  • Data versioning + migrations, and missing fields are filled from defaults.
	  • Studio without API access: the game still runs, but nothing is saved
	    (you get a clear warning).
]]

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(script.Parent.Parent.Util.Net)

export type ItemInstance = {
	Uid: string,
	Id: string,
	Found: number,
	Zone: string,
	Locked: boolean,
	-- v2
	Condition: string?, -- Perfect | Clean | Damaged
	Provenance: string?, -- "Excavated at ...", "Bought from ...", "Stolen from ..."
	Charges: number?, -- gadgets only
	Bound: boolean?, -- can't be traded/listed (e.g. Robux-bought gadgets)
	Reserved: { Kind: string, Id: string }?, -- Listing | Trade | Heist | Loadout
}

export type ProfileData = {
	Version: number,
	Cash: number,
	Upgrades: { [string]: boolean },
	Inventory: { [string]: ItemInstance },
	Displays: { [string]: string },
	ToolTier: number,
	Journal: {
		Discovered: { [string]: number },
		ZonesVisited: { [string]: boolean },
		CompletedSets: { [string]: boolean },
		Clues: { [string]: string },
		Puzzles: { [string]: number },
		Excavations: { [string]: number },
	},
	Stats: {
		Searches: number,
		ItemsFound: number,
		ItemsSold: number,
		TotalEarned: number,
		TotalCollected: number,
		PlaySeconds: number,
		Excavated: number,
		PerfectRecoveries: number,
		MarketSales: number,
		MarketPurchases: number,
		Trades: number,
	},
	PendingRevenue: number,
	StarterGranted: boolean,
	Created: number,
	-- v2
	Security: { [string]: number },
	Attachments: { [string]: boolean },
	Premium: { Receipts: { [string]: boolean }, ReceiptLog: { string } }, -- Developer Product receipts already granted
	DisplayRot: { [string]: number },
	Achievements: { [string]: number },
	Heist: {
		Attempts: number,
		Successes: number,
		Captures: number,
		Defended: number,
		Robbed: number,
		CooldownUntil: number,
		JailUntil: number,
		ProtectedUntil: number,
		Incidents: { any },
	},
	Listings: { [string]: any },
	PendingPurchases: { [string]: any },
	MarketHistory: { any },
	AppliedTx: { [string]: number },
}

export type Profile = {
	Player: Player,
	Key: string,
	Data: ProfileData,
	NoSave: boolean,
	Released: boolean,
}

local PlayerDataService = {}

local JOB_ID = if game.JobId ~= "" then game.JobId else "Studio"
local LOAD_ATTEMPTS = 8
local SAVE_ATTEMPTS = 3

local store: DataStore? = nil
local storeUnavailableReason: string? = nil

local profiles: { [Player]: Profile } = {}
local releasing: { [number]: boolean } = {} -- userId -> a save+release is in progress
local loadedCallbacks: { (Player, Profile) -> () } = {}
local loadHooks: { (Player, Profile) -> () } = {}
local busy: { [Player]: number } = {}
local sessionStart: { [Player]: number } = {}
local durable: boolean? = nil -- nil until the startup probe finishes
local releaseCallbacks: { (Player, Profile) -> () } = {}
local shuttingDown = false

-- ── Defaults & migrations ───────────────────────────────────────────────────
local function template(): ProfileData
	return {
		Version = Config.DataVersion,
		Cash = Config.StartingCash,
		Upgrades = {},
		Inventory = {},
		Displays = {},
		ToolTier = 1,
		Journal = { Discovered = {}, ZonesVisited = {}, CompletedSets = {}, Clues = {}, Puzzles = {}, Excavations = {} },
		Stats = {
			Searches = 0,
			ItemsFound = 0,
			ItemsSold = 0,
			TotalEarned = 0,
			TotalCollected = 0,
			PlaySeconds = 0,
			Excavated = 0,
			PerfectRecoveries = 0,
			MarketSales = 0,
			MarketPurchases = 0,
			Trades = 0,
		},
		PendingRevenue = 0,
		StarterGranted = false,
		Created = os.time(),
		Security = { Locks = 1, Cameras = 0, Alarm = 0, Cases = 0 },
		Attachments = {},
		Premium = { Receipts = {}, ReceiptLog = {} },
		DisplayRot = {},
		Achievements = {},
		Heist = { Attempts = 0, Successes = 0, Captures = 0, Defended = 0, Robbed = 0, CooldownUntil = 0, JailUntil = 0, ProtectedUntil = 0, Incidents = {} },
		Listings = {},
		PendingPurchases = {},
		MarketHistory = {},
		AppliedTx = {},
	}
end

-- Fill in any fields that are missing (e.g. after we add a new feature).
local function reconcile(target: { [any]: any }, defaults: { [any]: any })
	for key, value in defaults do
		if target[key] == nil then
			if type(value) == "table" then
				local copy = {}
				reconcile(copy, value)
				target[key] = copy
			else
				target[key] = value
			end
		elseif type(value) == "table" and type(target[key]) == "table" and next(value) ~= nil then
			reconcile(target[key], value)
		end
	end
end

-- MIGRATIONS: when you change the save format, increase Config.DataVersion
-- and add a function here that upgrades data from the previous version.
-- Example: migrations[2] = function(data) data.NewField = data.OldField; data.OldField = nil end
local migrations: { [number]: (any) -> () } = {}

-- v1 › v2: every existing item gets a condition and a provenance line.
-- (New top-level fields are filled in by reconcile() from the template.)
migrations[2] = function(data)
	if type(data.Inventory) == "table" then
		for _, item in data.Inventory do
			if type(item) == "table" then
				item.Condition = item.Condition or "Clean"
				if not item.Provenance then
					item.Provenance = if item.Zone == "Starter" then "A gift for your new museum" else "Found in the field"
				end
			end
		end
	end
end

local function migrate(data: any)
	data.Version = data.Version or 1
	while data.Version < Config.DataVersion do
		local nextVersion = data.Version + 1
		local step = migrations[nextVersion]
		if step then
			step(data)
		end
		data.Version = nextVersion
	end
end

-- ── DataStore access ────────────────────────────────────────────────────────
local function getStore(): DataStore?
	if store or storeUnavailableReason then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		storeUnavailableReason = tostring(result)
	end
	return store
end

local function isStudioAccessError(message: string): boolean
	return RunService:IsStudio()
		and (
			string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
			or string.find(message, "403", 1, true) ~= nil
			or string.find(message, "publish", 1, true) ~= nil
			or game.PlaceId == 0
		)
end

type LoadResult = { Status: "ok", Data: any } | { Status: "locked" } | { Status: "error", Message: string }

local function tryLoad(key: string): LoadResult
	local ds = getStore()
	if not ds then
		return { Status = "error", Message = storeUnavailableReason or "DataStore unavailable" }
	end
	local lockedByOther = false
	local loadedData: any = nil
	local ok, err = pcall(function()
		ds:UpdateAsync(key, function(old: any)
			-- This function may run more than once; reset the outputs each time.
			lockedByOther = false
			loadedData = nil
			if type(old) == "table" and type(old.Lock) == "table" then
				local lock = old.Lock
				local age = os.time() - (tonumber(lock.Time) or 0)
				if lock.JobId ~= JOB_ID and age < Config.SessionLockStaleSeconds then
					lockedByOther = true
					return nil -- cancel the write, leave data untouched
				end
			end
			local doc = if type(old) == "table" then old else {}
			doc.Lock = { JobId = JOB_ID, Time = os.time() }
			loadedData = doc.Data
			return doc
		end)
	end)
	if not ok then
		return { Status = "error", Message = tostring(err) }
	end
	if lockedByOther then
		return { Status = "locked" }
	end
	return { Status = "ok", Data = loadedData }
end

-- Writes the profile. If `release` is true the session lock is removed.
-- Returns true on success.
local function writeProfile(profile: Profile, release: boolean): boolean
	if profile.NoSave then
		return true
	end
	local ds = getStore()
	if not ds then
		return false
	end
	local lockStolen = false
	for attempt = 1, SAVE_ATTEMPTS do
		lockStolen = false
		local ok, err = pcall(function()
			ds:UpdateAsync(profile.Key, function(old: any)
				lockStolen = false
				if type(old) == "table" and type(old.Lock) == "table" and old.Lock.JobId ~= JOB_ID then
					-- Another server took over this player's data. Do NOT overwrite it.
					lockStolen = true
					return nil
				end
				return {
					Data = profile.Data,
					Lock = if release then nil else { JobId = JOB_ID, Time = os.time() },
					SavedAt = os.time(),
				}
			end)
		end)
		if ok then
			if lockStolen then
				warn(("[PlayerData] Session for %s was taken by another server; not saving."):format(profile.Key))
				local player = profile.Player
				if player.Parent and not release then
					player:Kick("You joined from another server. Please rejoin.")
				end
				return false
			end
			return true
		end
		warn(("[PlayerData] Save attempt %d for %s failed: %s"):format(attempt, profile.Key, tostring(err)))
		if attempt < SAVE_ATTEMPTS then
			task.wait(2 ^ attempt)
		end
	end
	return false
end

-- ── Loading ─────────────────────────────────────────────────────────────────
local function loadPlayer(player: Player)
	local key = "Player_" .. player.UserId

	-- If this player just left this same server, wait for that save to finish.
	local waited = 0
	while releasing[player.UserId] and waited < 30 do
		waited += task.wait(0.5)
	end

	local data: any = nil
	local noSave = false
	local loaded = false

	for attempt = 1, LOAD_ATTEMPTS do
		if player.Parent == nil then
			return
		end
		local result = tryLoad(key)
		if result.Status == "ok" then
			data = (result :: any).Data
			loaded = true
			break
		elseif result.Status == "locked" then
			-- Their previous server is probably still saving. Wait and retry.
			task.wait(5)
		else
			local message = (result :: any).Message
			if isStudioAccessError(message) then
				warn(
					"[PlayerData] DataStores are not available in Studio. Progress will NOT be saved this session.\n"
						.. "Fix: publish the place, then Game Settings > Security > Enable Studio Access to API Services."
				)
				noSave = true
				loaded = true
				break
			end
			warn(("[PlayerData] Load attempt %d for %s failed: %s"):format(attempt, player.Name, message))
			task.wait(math.min(2 ^ attempt, 10))
		end
	end

	if not loaded then
		player:Kick("We couldn't load your museum right now. Your progress is safe — please rejoin in a minute.")
		return
	end

	if type(data) ~= "table" then
		data = template() -- genuinely new player (no save existed)
	else
		if (tonumber(data.Version) or 1) > Config.DataVersion then
			-- Saved by a NEWER version of the game. Don't touch it.
			player:Kick("This server is running an older version of the game. Please rejoin.")
			return
		end
		migrate(data)
		reconcile(data, template())
	end

	local profile: Profile = {
		Player = player,
		Key = key,
		Data = data,
		NoSave = noSave,
		Released = false,
	}

	if player.Parent == nil then
		-- Left while loading: give the lock back straight away.
		writeProfile(profile, true)
		return
	end

	-- Clear reservations left behind by a crash. Trades, heists and loadouts
	-- only live while both players are on one server; listings are durable
	-- and are reconciled by the marketplace's load hook instead.
	for _, item in data.Inventory do
		if type(item) == "table" and item.Reserved and item.Reserved.Kind ~= "Listing" then
			item.Reserved = nil
		end
	end

	-- Hooks that must finish BEFORE the profile is used (transaction recovery,
	-- marketplace settlement). They may yield.
	for _, hook in loadHooks do
		local ok, err = pcall(hook, player, profile)
		if not ok then
			warn("[PlayerData] load hook failed for " .. player.Name .. ": " .. tostring(err))
		end
	end
	if player.Parent == nil then
		writeProfile(profile, true)
		return
	end

	profiles[player] = profile
	sessionStart[player] = os.clock()
	if noSave then
		player:SetAttribute("SaveDisabled", true)
	end
	for _, callback in loadedCallbacks do
		task.spawn(callback, player, profile)
	end
end

local function addPlayTime(player: Player, profile: Profile)
	local started = sessionStart[player]
	if started then
		local now = os.clock()
		profile.Data.Stats.PlaySeconds += math.floor(now - started)
		sessionStart[player] = now
	end
end

local function releasePlayer(player: Player)
	local profile = profiles[player]
	if not profile or profile.Released then
		return
	end
	-- Let an in-progress trade/heist transfer finish first (max 15 s).
	local waited = 0
	while busy[player] and waited < 15 do
		waited += task.wait(0.2)
	end
	busy[player] = nil
	addPlayTime(player, profile)
	sessionStart[player] = nil
	profile.Released = true
	for _, callback in releaseCallbacks do
		local ok, err = pcall(callback, player, profile)
		if not ok then
			warn("[PlayerData] release callback error: " .. tostring(err))
		end
	end
	releasing[player.UserId] = true
	-- Release callbacks above may have changed data (e.g. heist cleanup), so
	-- this save includes them.
	writeProfile(profile, true)
	releasing[player.UserId] = nil
	profiles[player] = nil
end

-- ── Public API ─────────────────────────────────────────────────────────────
function PlayerDataService.Get(player: Player): Profile?
	local profile = profiles[player]
	if profile and not profile.Released then
		return profile
	end
	return nil
end

function PlayerDataService.GetData(player: Player): ProfileData?
	local profile = PlayerDataService.Get(player)
	return profile and profile.Data
end

function PlayerDataService.IsLoaded(player: Player): boolean
	return PlayerDataService.Get(player) ~= nil
end

function PlayerDataService.AllProfiles(): { [Player]: Profile }
	return profiles
end

-- Callback runs (once) when a player's data has loaded.
function PlayerDataService.OnLoaded(callback: (Player, Profile) -> ())
	table.insert(loadedCallbacks, callback)
	for player, profile in profiles do
		task.spawn(callback, player, profile)
	end
end

-- Hook runs after a profile is read but BEFORE anything else can use it.
-- Used for crash recovery (ledger, marketplace). May yield.
function PlayerDataService.AddLoadHook(hook: (Player, Profile) -> ())
	table.insert(loadHooks, hook)
end

-- While busy, money/items can't be spent (used during multi-player transfers).
function PlayerDataService.SetBusy(player: Player, isBusy: boolean)
	if isBusy then
		busy[player] = os.clock()
	else
		busy[player] = nil
	end
end

function PlayerDataService.IsBusy(player: Player): boolean
	local since = busy[player]
	if since and os.clock() - since > 20 then
		busy[player] = nil -- safety valve
		return false
	end
	return since ~= nil
end

-- true = real DataStores work; false = Studio without API access (local only).
function PlayerDataService.IsDurable(): boolean
	while durable == nil do
		task.wait(0.1)
	end
	return durable == true
end

function PlayerDataService.PlaySeconds(player: Player): number
	local profile = PlayerDataService.Get(player)
	if not profile then
		return 0
	end
	local extra = if sessionStart[player] then os.clock() - sessionStart[player] else 0
	return profile.Data.Stats.PlaySeconds + extra
end

-- Callback runs when a player leaves, BEFORE their data is saved.
function PlayerDataService.OnReleasing(callback: (Player, Profile) -> ())
	table.insert(releaseCallbacks, callback)
end

-- Save immediately (use after very important changes, e.g. trades).
function PlayerDataService.SaveNow(player: Player): boolean
	local profile = PlayerDataService.Get(player)
	if not profile then
		return false
	end
	return writeProfile(profile, false)
end

function PlayerDataService.Init()
	Net.SetReadyCheck(PlayerDataService.IsLoaded)
end

function PlayerDataService.Start()
	-- Probe once: can this server use DataStores at all?
	task.spawn(function()
		local ds = getStore()
		if not ds then
			durable = false
			return
		end
		local ok = pcall(function()
			return ds:GetAsync("__probe")
		end)
		durable = ok
		if not ok then
			warn("[PlayerData] DataStores unavailable — marketplace and ledger run in local (this-server-only) mode.")
		end
	end)
	Players.PlayerAdded:Connect(loadPlayer)
	for _, player in Players:GetPlayers() do
		task.spawn(loadPlayer, player)
	end
	Players.PlayerRemoving:Connect(releasePlayer)

	-- Autosave (also refreshes the session lock so it never looks stale).
	task.spawn(function()
		while not shuttingDown do
			task.wait(Config.AutosaveSeconds)
			for player, profile in profiles do
				if not profile.Released and not shuttingDown then
					addPlayTime(player, profile)
					task.spawn(writeProfile, profile, false)
					task.wait(0.5) -- spread requests out
				end
			end
		end
	end)

	game:BindToClose(function()
		shuttingDown = true
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				releasePlayer(player)
				pending -= 1
			end)
		end
		local started = os.clock()
		while pending > 0 and os.clock() - started < 25 do
			task.wait(0.2)
		end
	end)
end

return PlayerDataService
