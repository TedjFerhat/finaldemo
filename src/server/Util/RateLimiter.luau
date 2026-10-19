--[[
	RateLimiter
	Token-bucket limiter: each player may make `rate` requests per second with a
	short `burst`. Exploiters spamming remotes are simply ignored.
]]

local Players = game:GetService("Players")

local RateLimiter = {}
RateLimiter.__index = RateLimiter

export type Limiter = typeof(setmetatable({} :: { Rate: number, Burst: number, Buckets: { [Player]: { Tokens: number, Last: number } } }, RateLimiter))

function RateLimiter.new(rate: number, burst: number): Limiter
	local self = setmetatable({ Rate = rate, Burst = burst, Buckets = {} }, RateLimiter)
	Players.PlayerRemoving:Connect(function(player)
		self.Buckets[player] = nil
	end)
	return self
end

-- Returns true if the request is allowed.
function RateLimiter.Check(self: Limiter, player: Player): boolean
	local now = os.clock()
	local bucket = self.Buckets[player]
	if not bucket then
		bucket = { Tokens = self.Burst, Last = now }
		self.Buckets[player] = bucket
	end
	bucket.Tokens = math.min(self.Burst, bucket.Tokens + (now - bucket.Last) * self.Rate)
	bucket.Last = now
	if bucket.Tokens >= 1 then
		bucket.Tokens -= 1
		return true
	end
	return false
end

return RateLimiter
