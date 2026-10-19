--[[
	ChallengeService
	Server-judged minigames used by excavation and heists.

	Kinds:
	  • Timing   — a marker bounces along a bar; press when it's inside the
	               zone. Used for brushing soil, picking locks, cutting glass,
	               lifting exhibits off pressure pads and rappelling.
	  • Sequence — memorise a short symbol sequence, then repeat it.
	               Used to hack a museum's security panel.

	The client only draws. The SERVER generates the zones, owns the clock
	(workspace:GetServerTimeNow is synchronised to every client) and judges
	each press when it arrives, compensating for the player's ping. The client
	can never report "I won".
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Minigame = require(Shared.Minigame)

local Net = require(script.Parent.Parent.Util.Net)

local ChallengeService = {}

export type Spec = {
	Kind: string,
	Title: string,
	Subtitle: string?,
	Theme: string,
	-- Timing
	Presses: number?,
	Speed: number?,
	ZoneWidth: number?,
	MaxMisses: number?,
	-- Sequence
	Length: number?,
	Symbols: { string }?,
	ShowSeconds: number?,
	-- Both
	MaxSeconds: number,
	Anchor: Vector3?,
	Radius: number?,
}

export type Result = {
	Hits: number,
	Misses: number,
	Presses: number,
	Success: boolean, -- Sequence: correct answer. Timing: finished without hitting MaxMisses.
	Cancelled: boolean,
	Reason: string?,
}

type Session = {
	Id: string,
	Player: Player,
	Spec: Spec,
	T0: number,
	Centers: { number },
	Sequence: { string }?,
	Index: number,
	Hits: number,
	Misses: number,
	LastPress: number,
	Ended: boolean,
	OnPress: ((boolean, number) -> ())?,
	OnEnd: (Result) -> (),
}

local sessions: { [Player]: Session } = {}
local rng = Random.new()
local MIN_PRESS_GAP = 0.2

local function now(): number
	return workspace:GetServerTimeNow()
end

local function oneWayLatency(player: Player): number
	local ok, ping = pcall(function()
		return player:GetNetworkPing()
	end)
	if ok and type(ping) == "number" then
		return math.clamp(ping / 2, 0, 0.3)
	end
	return 0.06
end

local function finish(session: Session, result: Result)
	if session.Ended then
		return
	end
	session.Ended = true
	if sessions[session.Player] == session then
		sessions[session.Player] = nil
	end
	if session.Player.Parent then
		Net.Fire("ChallengeEnd", session.Player, {
			Id = session.Id,
			Hits = result.Hits,
			Misses = result.Misses,
			Success = result.Success,
			Cancelled = result.Cancelled,
			Reason = result.Reason,
		})
	end
	local ok, err = pcall(session.OnEnd, result)
	if not ok then
		warn("[Challenge] OnEnd error: " .. tostring(err))
	end
end

local function resultOf(session: Session, cancelled: boolean, reason: string?, success: boolean?): Result
	local presses = session.Spec.Presses or 0
	local misses = session.Misses
	if cancelled then
		-- Everything not pressed counts as missed.
		misses += math.max(0, presses - session.Index + 1)
	end
	local maxMisses = session.Spec.MaxMisses
	local timingSuccess = not cancelled and (maxMisses == nil or misses < maxMisses)
	return {
		Hits = session.Hits,
		Misses = misses,
		Presses = presses,
		Success = if success ~= nil then success else timingSuccess,
		Cancelled = cancelled,
		Reason = reason,
	}
end

local function tooFar(session: Session): boolean
	local anchor = session.Spec.Anchor
	if not anchor then
		return false
	end
	local character = session.Player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return true
	end
	return (root.Position - anchor).Magnitude > (session.Spec.Radius or 12)
end

-- Starts a challenge. `onEnd` ALWAYS runs exactly once (success, failure,
-- cancel, timeout, player leaving).
function ChallengeService.Begin(player: Player, spec: Spec, onEnd: (Result) -> (), onPress: ((boolean, number) -> ())?): string
	local old = sessions[player]
	if old then
		finish(old, resultOf(old, true, "Replaced"))
	end
	local id = HttpService:GenerateGUID(false)
	local t0 = now() + 0.8 -- short countdown before the marker moves
	local session: Session = {
		Id = id,
		Player = player,
		Spec = spec,
		T0 = t0,
		Centers = {},
		Sequence = nil,
		Index = 1,
		Hits = 0,
		Misses = 0,
		LastPress = 0,
		Ended = false,
		OnPress = onPress,
		OnEnd = onEnd,
	}
	local payload: { [string]: any } = {
		Id = id,
		Kind = spec.Kind,
		Title = spec.Title,
		Subtitle = spec.Subtitle,
		Theme = spec.Theme,
		T0 = t0,
		MaxSeconds = spec.MaxSeconds,
	}
	if spec.Kind == "Timing" then
		session.Centers = Minigame.ZoneCenters(rng:NextInteger(1, 2 ^ 30), spec.Presses or 1)
		payload.Presses = spec.Presses
		payload.Speed = spec.Speed
		payload.ZoneWidth = spec.ZoneWidth
		payload.Centers = session.Centers
		payload.MaxMisses = spec.MaxMisses
	else
		local symbols = spec.Symbols or { "A", "B", "C", "D" }
		local sequence = {}
		for i = 1, spec.Length or 4 do
			sequence[i] = symbols[rng:NextInteger(1, #symbols)]
		end
		session.Sequence = sequence
		payload.Sequence = sequence
		payload.Symbols = symbols
		payload.ShowSeconds = spec.ShowSeconds
	end
	sessions[player] = session
	Net.Fire("ChallengeStart", player, payload)

	task.delay(spec.MaxSeconds + 1, function()
		if not session.Ended then
			finish(session, resultOf(session, true, "Out of time"))
		end
	end)
	return id
end

function ChallengeService.Cancel(player: Player, reason: string?)
	local session = sessions[player]
	if session then
		finish(session, resultOf(session, true, reason or "Cancelled"))
	end
end

function ChallengeService.IsActive(player: Player): boolean
	return sessions[player] ~= nil
end

local function handleInput(player: Player, id: any, action: any, payload: any): (boolean, string?)
	local session = sessions[player]
	if not session or session.Id ~= id or type(action) ~= "string" then
		return false, nil
	end
	if action == "Cancel" then
		finish(session, resultOf(session, true, "Cancelled"))
		return true, nil
	end
	if tooFar(session) then
		finish(session, resultOf(session, true, "You moved away"))
		return false, "You moved away"
	end
	local t = now()
	if session.Spec.Kind == "Timing" and action == "Press" then
		if t < session.T0 then
			return false, nil -- pressed during the countdown: ignored
		end
		if t - session.LastPress < MIN_PRESS_GAP then
			return false, nil
		end
		session.LastPress = t
		local index = session.Index
		local center = session.Centers[index]
		if not center then
			return false, nil
		end
		local hit = Minigame.JudgePress(t, oneWayLatency(player), session.T0, session.Spec.Speed or 0.6, center, session.Spec.ZoneWidth or 0.2)
		if hit then
			session.Hits += 1
		else
			session.Misses += 1
		end
		session.Index += 1
		Net.Fire("ChallengeFeedback", player, { Id = session.Id, Index = index, Hit = hit })
		if session.OnPress then
			pcall(session.OnPress, hit, index)
		end
		local maxMisses = session.Spec.MaxMisses
		if session.Index > (session.Spec.Presses or 1) or (maxMisses and session.Misses >= maxMisses) then
			finish(session, resultOf(session, false, nil))
		end
		return true, nil
	elseif session.Spec.Kind == "Sequence" and action == "Answer" then
		local sequence = session.Sequence :: { string }
		local minTime = session.T0 + (session.Spec.ShowSeconds or 2) + 0.3 * #sequence
		if t < minTime then
			return false, nil -- too fast to be a human answer
		end
		local correct = type(payload) == "table" and #payload == #sequence
		if correct then
			for i, symbol in sequence do
				if payload[i] ~= symbol then
					correct = false
					break
				end
			end
		end
		session.Hits = if correct then 1 else 0
		session.Misses = if correct then 0 else 1
		finish(session, resultOf(session, false, nil, correct))
		return true, nil
	end
	return false, nil
end

function ChallengeService.Init() end

function ChallengeService.Start()
	Net.Handle("ChallengeInput", handleInput)
	Players.PlayerRemoving:Connect(function(player)
		local session = sessions[player]
		if session then
			finish(session, resultOf(session, true, "Left the game"))
		end
	end)
end

return ChallengeService
