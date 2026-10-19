--!strict
--[[
	TxCore (pure logic, no Roblox APIs — unit-tested in tests/run_tests.luau)

	Applies one participant's half of a committed transfer to their profile
	data. Idempotent: applying the same transaction twice does nothing the
	second time, because the transaction id is recorded in data.AppliedTx in
	the SAME save as the changes.

	A "side" says what happens to one player:
	  Remove = { uid, ... }   -- instances that leave this player
	  Add    = { item, ... }  -- full item instances that arrive (same Uid!)
	  Cash   = number         -- + received / - paid
]]

export type Side = {
	Remove: { string },
	Add: { { [string]: any } },
	Cash: number,
}

local TxCore = {}

local function deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = deepCopy(v)
	end
	return out
end
TxCore.DeepCopy = deepCopy

function TxCore.IsApplied(data: any, txId: string): boolean
	return data.AppliedTx ~= nil and data.AppliedTx[txId] ~= nil
end

-- Returns true if it changed the data.
function TxCore.ApplySide(data: any, side: Side, txId: string, now: number): boolean
	data.AppliedTx = data.AppliedTx or {}
	if data.AppliedTx[txId] then
		return false
	end
	local removeList: { string } = side.Remove or {}
	for _, uid in removeList do
		if data.Inventory[uid] then
			data.Inventory[uid] = nil
		end
		for slotId, displayed in data.Displays do
			if displayed == uid then
				data.Displays[slotId] = nil
				if data.DisplayRot then
					data.DisplayRot[slotId] = nil
				end
			end
		end
	end
	local addList: { { [string]: any } } = side.Add or {}
	for _, item in addList do
		if type(item) == "table" and type(item.Uid) == "string" and data.Inventory[item.Uid] == nil then
			local copy = deepCopy(item)
			copy.Reserved = nil
			copy.Locked = false
			data.Inventory[item.Uid] = copy
		end
	end
	local cash = side.Cash or 0
	data.Cash = math.max(0, math.floor((data.Cash or 0) + cash))
	data.AppliedTx[txId] = now
	return true
end

-- Forget very old transaction ids (keeps saves small).
function TxCore.PruneApplied(data: any, now: number, maxAgeSeconds: number)
	if not data.AppliedTx then
		return
	end
	for id, t in data.AppliedTx do
		if type(t) ~= "number" or now - t > maxAgeSeconds then
			data.AppliedTx[id] = nil
		end
	end
end

-- Validates that `data` can afford its side right now (used before commit).
function TxCore.CanApply(data: any, side: Side): (boolean, string?)
	local removeList: { string } = side.Remove or {}
	for _, uid in removeList do
		if not data.Inventory[uid] then
			return false, "An item in the deal no longer exists"
		end
	end
	if (side.Cash or 0) < 0 and (data.Cash or 0) + side.Cash < 0 then
		return false, "Not enough cash"
	end
	return true, nil
end

return TxCore
