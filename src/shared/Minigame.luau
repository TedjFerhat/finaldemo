--[[
	Minigame
	Pure maths shared by the server (which JUDGES every press) and the client
	(which only DRAWS the marker). Both use workspace:GetServerTimeNow(), which
	Roblox keeps synchronised between server and clients.

	No Roblox APIs are used here, so this module is unit-tested outside Studio
	(see tests/run_tests.luau).
]]

local Minigame = {}

-- Marker position 0..1 for a marker bouncing back and forth.
-- `speed` = full back-and-forth cycles per second.
function Minigame.MarkerPos(t: number, t0: number, speed: number): number
	local elapsed = math.max(0, t - t0)
	local phase = (elapsed * speed) % 1
	if phase < 0.5 then
		return phase * 2
	end
	return 2 - phase * 2
end

-- Is `pos` inside the zone centred on `center` with total width `width`?
-- `tolerance` widens the zone a little to absorb network jitter.
function Minigame.InZone(pos: number, center: number, width: number, tolerance: number): boolean
	return math.abs(pos - center) <= width / 2 + tolerance
end

-- Judges a press received by the server at `serverTime`.
-- `oneWayLatency` is subtracted (the player pressed slightly before the
-- server received it). We also accept the press if the marker was in the zone
-- at any point within the latency uncertainty window, so laggy players are
-- not punished.
function Minigame.JudgePress(serverTime: number, oneWayLatency: number, t0: number, speed: number, center: number, width: number): boolean
	local tolerance = 0.025
	local latency = math.clamp(oneWayLatency, 0, 0.3)
	local samples = 6
	for i = 0, samples do
		local t = serverTime - latency * (i / samples) * 1.6
		if Minigame.InZone(Minigame.MarkerPos(t, t0, speed), center, width, tolerance) then
			return true
		end
	end
	return false
end

-- Deterministic pseudo-random zone centres from a seed (server picks the seed).
function Minigame.ZoneCenters(seed: number, count: number): { number }
	local centers = {}
	local state = seed % 2147483647
	if state <= 0 then
		state += 2147483646
	end
	for i = 1, count do
		state = (state * 16807) % 2147483647
		centers[i] = 0.15 + (state / 2147483647) * 0.7
	end
	return centers
end

return Minigame
