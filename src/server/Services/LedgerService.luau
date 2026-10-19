--[[
	LedgerService
	Moves items and cash between two (or more) players safely.

	Roblox DataStores can't save two player keys atomically, so a transfer is
	made durable FIRST and applied SECOND:

	  1. Tx_<id>         ← { Status = "Prepared", Sides }       (one key)
	  2. UserTx_<userId> ← append { Id, Time }  for every participant
	  3. Tx_<id>         ← "Committed"  (only if still Prepared) ← COMMIT POINT
	  4. apply each side in memory, record the id in AppliedTx, save profiles

	If the server crashes after step 3, every participant's next load reads
	their UserTx list, finds the committed transaction missing from their
	AppliedTx and applies their half then (TxCore is idempotent). If it crashes
	before step 3, nothing was applied anywhere and the Prepared record is
	aborted later. Used by heists and direct trades.

	Studio without API access: transfers apply directly in memory.
]]

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local PlayerDataService = require(script.Parent.PlayerDataService)
local StateSync = require(script.Parent.StateSync)
local TxCore = require(script.Parent.Parent.Core.TxCore)

local LedgerService = {}

local KEEP_SECONDS = 14 * 24 * 3600
local ABORT_AFTER = 120
local MAX_USER_ENTRIES = 60

local store: DataStore? = nil

local function getStore(): DataStore?
	if store then
		return store
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.LedgerStoreName)
	end)
	if ok then
		store = result
	end
	return store
end

local function update(key: string, fn: (any) -> any): (boolean, any)
	local ds = getStore()
	if not ds then
		return false, nil
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return ds:UpdateAsync(key, fn)
		end)
		if ok then
			return true, result
		end
		warn(("[Ledger] UpdateAsync %s failed (%d): %s"):format(key, attempt, tostring(result)))
		task.wait(attempt)
	end
	return false, nil
end

local function get(key: string): (boolean, any)
	local ds = getStore()
	if not ds then
		return false, nil
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return ds:GetAsync(key)
		end)
		if ok then
			return true, result
		end
		task.wait(attempt)
	end
	return false, nil
end

function LedgerService.NewId(): string
	return HttpService:GenerateGUID(false)
end

-- sides: { [Player] = TxCore.Side }. All players must be loaded on this server.
-- Returns true when the transfer is committed AND applied in memory.
function LedgerService.Commit(txId: string, sides: { [Player]: TxCore.Side }): (boolean, string?)
	-- Validate against the current in-memory state
	for player, side in sides do
		local data = PlayerDataService.GetData(player)
		if not data then
			return false, player.Name .. "'s data isn't loaded"
		end
		local ok, err = TxCore.CanApply(data, side)
		if not ok then
			return false, err
		end
	end
	for player in sides do
		PlayerDataService.SetBusy(player, true)
	end
	local function done(ok: boolean, err: string?): (boolean, string?)
		for player in sides do
			PlayerDataService.SetBusy(player, false)
		end
		return ok, err
	end

	if PlayerDataService.IsDurable() then
		local now = os.time()
		local stored: { [string]: any } = {}
		for player, side in sides do
			stored[tostring(player.UserId)] = TxCore.DeepCopy(side)
		end
		-- 1. Prepared
		local ok1 = update("Tx_" .. txId, function(old)
			if old ~= nil then
				return nil
			end
			return { Status = "Prepared", Sides = stored, Time = now }
		end)
		if not ok1 then
			return done(false, "Couldn't reach the save servers. Nothing was transferred.")
		end
		-- 2. Index for each participant
		for player in sides do
			local okIndex = update("UserTx_" .. player.UserId, function(old)
				local doc = if type(old) == "table" then old else { List = {} }
				local list = {}
				for _, entry in doc.List or {} do
					if type(entry) == "table" and now - (entry.Time or 0) < KEEP_SECONDS then
						table.insert(list, entry)
					end
				end
				table.insert(list, { Id = txId, Time = now })
				while #list > MAX_USER_ENTRIES do
					table.remove(list, 1)
				end
				doc.List = list
				return doc
			end)
			if not okIndex then
				update("Tx_" .. txId, function(old)
					if type(old) == "table" and old.Status == "Prepared" then
						old.Status = "Aborted"
						return old
					end
					return nil
				end)
				return done(false, "Couldn't reach the save servers. Nothing was transferred.")
			end
		end
		-- 3. Commit point
		local committed = false
		local ok3 = update("Tx_" .. txId, function(old)
			committed = false
			if type(old) == "table" and old.Status == "Prepared" then
				old.Status = "Committed"
				committed = true
				return old
			end
			return nil
		end)
		if not ok3 or not committed then
			return done(false, "The transfer couldn't be completed. Nothing was transferred.")
		end
	end

	-- 4. Apply in memory (no yields in this loop)
	local now = os.time()
	for player, side in sides do
		local data = PlayerDataService.GetData(player)
		if data then
			TxCore.ApplySide(data, side, txId, now)
			StateSync.Mark(player)
		end
	end
	done(true, nil)
	for player in sides do
		task.spawn(PlayerDataService.SaveNow, player)
	end
	return true, nil
end

-- Crash recovery on load: apply committed transfers this profile missed.
local function recover(player: Player, profile: any)
	if profile.NoSave or not PlayerDataService.IsDurable() then
		return
	end
	local data = profile.Data
	TxCore.PruneApplied(data, os.time(), KEEP_SECONDS * 2)
	local ok, index = get("UserTx_" .. player.UserId)
	if not ok or type(index) ~= "table" then
		return
	end
	local now = os.time()
	for _, entry in index.List or {} do
		if type(entry) == "table" and type(entry.Id) == "string" and not TxCore.IsApplied(data, entry.Id) and now - (entry.Time or 0) < KEEP_SECONDS then
			local okTx, tx = get("Tx_" .. entry.Id)
			if okTx and type(tx) == "table" then
				if tx.Status == "Committed" then
					local side = tx.Sides and tx.Sides[tostring(player.UserId)]
					if side then
						TxCore.ApplySide(data, side, entry.Id, now)
						warn(("[Ledger] Recovered transfer %s for %s"):format(entry.Id, player.Name))
					end
				elseif tx.Status == "Prepared" and now - (tx.Time or 0) > ABORT_AFTER then
					update("Tx_" .. entry.Id, function(old)
						if type(old) == "table" and old.Status == "Prepared" then
							old.Status = "Aborted"
							return old
						end
						return nil
					end)
				end
			end
		end
	end
end

function LedgerService.Init()
	PlayerDataService.AddLoadHook(recover)
end

function LedgerService.Start() end

return LedgerService
