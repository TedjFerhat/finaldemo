--[[
	Net
	Safe wrappers for client › server requests.

	Net.Handle("PurchaseUpgrade", function(player, upgradeId) ... end)
	  • rate-limits every player
	  • refuses players whose data has not loaded yet
	  • catches script errors so one bad request cannot break the server
	  • always returns { Ok = boolean, Message = string? } to the client

	Handlers return (ok: boolean, message: string?) or (true, nil, extraData).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local RateLimiter = require(script.Parent.RateLimiter)

local Net = {}

local limiter = RateLimiter.new(Config.RemoteRate, Config.RemoteBurst)
local isReady: (Player) -> boolean = function()
	return false
end

-- PlayerDataService tells Net how to check that a player's data is loaded.
function Net.SetReadyCheck(fn: (Player) -> boolean)
	isReady = fn
end

function Net.Handle(name: string, handler: (Player, ...any) -> (boolean, string?, any?))
	local remote = Remotes.Function(name)
	remote.OnServerInvoke = function(player: Player, ...)
		if not limiter:Check(player) then
			return { Ok = false, Message = "Slow down a little!" }
		end
		if not isReady(player) then
			return { Ok = false, Message = "Your data is still loading..." }
		end
		local results = table.pack(pcall(handler, player, ...))
		if not results[1] then
			warn(("[Net] %s failed for %s: %s"):format(name, player.Name, tostring(results[2])))
			return { Ok = false, Message = "Something went wrong. Please try again." }
		end
		return { Ok = results[2] == true, Message = results[3], Data = results[4] }
	end
end

-- Fire a server › client event to one player.
function Net.Fire(name: string, player: Player, ...: any)
	Remotes.Event(name):FireClient(player, ...)
end

-- ── Validation helpers (never trust client values) ─────────────────────────
function Net.IsString(v: any, maxLen: number?): boolean
	return type(v) == "string" and #v > 0 and #v <= (maxLen or 64)
end

function Net.IsInt(v: any, min: number, max: number): boolean
	return type(v) == "number" and v == v and v % 1 == 0 and v >= min and v <= max
end

return Net
