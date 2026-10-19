--[[
	ClientState
	Holds the latest snapshot of YOUR state sent by the server. UI reads from
	here and re-draws when it changes. The client never edits this data — it
	is display-only. All real changes go through the server.
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ClientState = {}

local current: { [string]: any }? = nil
local previous: { [string]: any }? = nil
local listeners: { (any, any?) -> () } = {}

function ClientState.Get(): { [string]: any }?
	return current
end

-- Calls `callback(state, previousState)` now (if loaded) and on every change.
function ClientState.OnChanged(callback: (any, any?) -> ())
	table.insert(listeners, callback)
	if current then
		task.spawn(callback, current, previous)
	end
end

-- Find an item instance in the snapshot by uid
function ClientState.FindItem(uid: string): any?
	if not current then
		return nil
	end
	for _, item in current.Inventory do
		if item.Uid == uid then
			return item
		end
	end
	return nil
end

function ClientState.Init()
	Remotes.Event("StateUpdated").OnClientEvent:Connect(function(snapshot)
		previous = current
		current = snapshot
		for _, callback in listeners do
			task.spawn(callback, snapshot, previous)
		end
	end)
end

return ClientState
