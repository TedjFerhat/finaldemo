--[[
	HeistConfig
	Every heist and museum-security number in ONE place. Rebalance here.

	Difficulty = defender factors (security levels below)
	           × attacker factors (gadgets, skill in the minigames)
	           × mission factors (target value, alarm state).
]]

local HeistConfig = {}

-- ── Museum security systems (bought by museum owners) ──────────────────────
-- Level 0 = not installed. `RequiresUpgrade` = museum upgrade needed first.
HeistConfig.Systems = {
	Locks = {
		Order = 1, Name = "Door Locks", Max = 3, Costs = { 1500, 4000, 9000 }, Default = 1,
		Levels = { "Basic latch", "Reinforced deadbolt", "High-security lock" },
		Effect = "Harder lockpicking at every entrance. Tier 3 needs Master Lockpicks.",
	},
	Cameras = {
		Order = 2, Name = "Security Cameras", Max = 3, Costs = { 1200, 3500, 8000 }, Default = 0,
		Levels = { "Lobby cameras", "Cameras in every room", "Hardened cameras (wider, harder to jam)" },
		Effect = "Cameras raise suspicion when they see an intruder.",
		RequiresUpgradeFrom = 2, RequiresUpgrade = "security",
	},
	Alarm = {
		Order = 3, Name = "Pressure Alarms", Max = 3, Costs = { 1000, 3000, 7000 }, Default = 0,
		Levels = { "Pressure pads", "Sensitive pads (failed grabs trip the alarm)", "Hair-trigger pads" },
		Effect = "Lifting an exhibit off a pedestal, wall or platform becomes a tense timing challenge.",
	},
	Cases = {
		Order = 4, Name = "Reinforced Glass", Max = 3, Costs = { 1500, 4500, 10000 }, Default = 0,
		Levels = { "Laminated glass", "Armoured glass", "Ballistic glass (Diamond Cutter only)" },
		Effect = "Display cases and vaults need a better glass cutter and a steadier hand.",
	},
}

-- ── Eligibility & anti-harassment ──────────────────────────────────────────
HeistConfig.AttackerMinLevel = 2
HeistConfig.TargetMinLevel = 2
HeistConfig.TargetMinPlaySeconds = 30 * 60 -- new players are protected for 30 min of play
HeistConfig.AttackerCooldown = 5 * 60 -- after any heist
HeistConfig.CaptureCooldown = 10 * 60 -- after being caught
HeistConfig.TargetProtectAfterTheft = 20 * 60
HeistConfig.TargetProtectAfterAttempt = 5 * 60
HeistConfig.RepeatWindow = 60 * 60
HeistConfig.RepeatMaxPerTarget = 2 -- same attacker › same target per window

-- ── Mission ────────────────────────────────────────────────────────────────
HeistConfig.MaxLoadout = 3
HeistConfig.MaxMissionSeconds = 6 * 60
HeistConfig.AlarmEscapeSeconds = 60 -- after the alarm, police arrive
HeistConfig.TickSeconds = 0.1
HeistConfig.SneakSpeed = 6
HeistConfig.NormalSpeed = 16
HeistConfig.ApprehendRadius = 9 -- owner catches the thief

-- ── Detection ──────────────────────────────────────────────────────────────
HeistConfig.Thresholds = { Suspicious = 25, Investigating = 60, Alarm = 100 }
HeistConfig.SuspicionDecay = 6 -- per second while unobserved (not after alarm)
HeistConfig.CameraRate = 30 -- per second while seen (× tier factor)
HeistConfig.CameraRange = { 28, 34, 42 }
HeistConfig.CameraFov = { 70, 80, 95 } -- full cone angle, degrees

-- ── Gadget effects ─────────────────────────────────────────────────────────
HeistConfig.JammerSeconds = { 20, 15, 10 } -- by camera tier

-- ── Challenge tuning ───────────────────────────────────────────────────────
HeistConfig.Lockpick = { BaseSpeed = 0.55, SpeedPerTier = 0.12, Zone = { [2] = 0.17, [3] = 0.23 }, ZonePerTier = 0.02, MaxMisses = 3, MissSuspicion = 8, BreakSuspicion = 25 }
HeistConfig.Cutter = { BaseSpeed = 0.6, SpeedPerTier = 0.12, Zone = { [2] = 0.19, [3] = 0.25 }, ZonePerTier = 0.02, Strokes = 3, FailSuspicion = 30 }
HeistConfig.Plate = { Speed = 0.7, BaseZone = 0.22, ZonePerTier = 0.04, FailSuspicion = 40 }
HeistConfig.ExtractSuspicion = 15
HeistConfig.ValueSuspicion = { Common = 0, Uncommon = 0, Rare = 5, Epic = 10, Legendary = 15, Mythic = 25 }

-- ── Consequences ───────────────────────────────────────────────────────────
HeistConfig.FineRate = 0.05 -- of the thief's cash, paid to the defender
HeistConfig.FineCap = 1000
HeistConfig.InsuranceRate = 0.2 -- victims with the Security System get 20% of the value back

-- ── Display labels for the UI ──────────────────────────────────────────────
HeistConfig.StateNames = {
	Planning = "Planning",
	Entry = "Outside — pick the lock",
	Inside = "Inside — find an exhibit",
	Escaping = "Artefact acquired — escape!",
	Captured = "Captured",
	Escaped = "Escaped",
	Aborted = "Aborted",
}

function HeistConfig.SystemList(): { { Id: string, Def: any } }
	local list = {}
	for id, def in HeistConfig.Systems do
		table.insert(list, { Id = id, Def = def })
	end
	table.sort(list, function(a, b)
		return a.Def.Order < b.Def.Order
	end)
	return list
end

return HeistConfig
