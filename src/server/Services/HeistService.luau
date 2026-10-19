--[[
	HeistService (core version)

	A heist on another ONLINE player's museum:
	  1. Choose a target on the Heist Board (eligible museums only).
	  2. Pick up to 3 gadgets (lockpicks, glass cutters, camera jammers).
	  3. You start in their front yard. The entrance is sealed for you by an
	     after-hours shutter only you collide with: pick the lock
	     (difficulty = their Door Locks level vs your lockpick).
	  4. Inside, real cameras raise SUSPICION while they can see you
	     (sneak to be less visible, jam them for a few seconds).
	  5. Steal ONE exhibit: cut the glass (Reinforced Glass level vs your
	     cutter) or lift it off its pressure pad (Pressure Alarm level).
	  6. Escape to the getaway cart in the front yard.

	Suspicion 100 › ALARM: the owner is alerted, and you have 60 s before the
	police arrive. The owner can also catch you in person ("Apprehend").
	Caught › returned exhibit, a short jail sentence and a small fine paid to
	the defender. Escaped › the exhibit's ownership really transfers
	(LedgerService), and the victim gets insurance if they own the Security
	System.

	The server owns every decision: mission state, detection, challenge
	results, extraction, escape and the transfer. Leaving or resetting
	mid-heist never keeps the loot.

	Not in this version (planned): recon/intel, alternative entry routes,
	guards, lasers, motion sensors, security-panel hacking.
]]

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local HeistConfig = require(Shared.HeistConfig)
local ItemCatalog = require(Shared.ItemCatalog)
local Rarities = require(Shared.Rarities)
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local MuseumService = require(script.Parent.MuseumService)
local PlotService = require(script.Parent.PlotService)
local SecurityService = require(script.Parent.SecurityService)
local ChallengeService = require(script.Parent.ChallengeService)
local LedgerService = require(script.Parent.LedgerService)
local JailService = require(script.Parent.JailService)
local AchievementService = require(script.Parent.AchievementService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)
local Notifier = require(script.Parent.Parent.Util.Notifier)

local HeistService = {}

type Mission = {
	Id: string,
	Attacker: Player,
	Owner: Player,
	Origin: CFrame,
	State: string, -- Entry | Inside | Escaping | Done
	Suspicion: number,
	Alarm: boolean,
	AlarmAt: number,
	Started: number,
	Loadout: { string },
	Folder: Folder,
	Barrier: BasePart?,
	Getaway: BasePart,
	StealPrompts: { ProximityPrompt },
	ApprehendPrompt: ProximityPrompt?,
	AlarmSound: Sound?,
	TargetUid: string?,
	TargetSlot: string?,
	Jammed: { [string]: number },
	Sneaking: boolean,
	Seen: boolean,
	Busy: boolean,
	LastSend: number,
	Connections: { RBXScriptConnection },
}

local missions: { [Player]: Mission } = {} -- by attacker
local byOwner: { [Player]: Mission } = {}
local recentTargets: { [number]: { { Target: number, Time: number } } } = {}

-- Museum footprint per room, in plot space (x1, z1, x2, z2).
local ROOMS = {
	{ Room = "base", Box = { -20, -10, 20, 30 } },
	{ Room = "east_wing", Box = { 20, -5, 50, 25 } },
	{ Room = "fossil_hall", Box = { 21, 25, 50, 55 } },
	{ Room = "west_wing", Box = { -50, -5, -20, 25 } },
	{ Room = "treasure_vault", Box = { -50, 25, -21, 55 } },
	{ Room = "grand_gallery", Box = { -20, 30, 20, 62 } },
}
local GETAWAY = Vector3.new(-56, 0, -22)
local START = Vector3.new(10, 3, -25)

-- ── Helpers ────────────────────────────────────────────────────────────────
local function hrpOf(player: Player): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	return character and character:FindFirstChildOfClass("Humanoid")
end

local function isInside(mission: Mission, pos: Vector3): boolean
	local data = PlayerDataService.GetData(mission.Owner)
	if not data then
		return false
	end
	local p = mission.Origin:PointToObjectSpace(pos)
	if p.Y < -2 or p.Y > 24 then
		return false
	end
	for _, room in ROOMS do
		if room.Room == "base" or data.Upgrades[room.Room] then
			local b = room.Box
			if p.X > b[1] and p.X < b[3] and p.Z > b[2] and p.Z < b[4] then
				return true
			end
		end
	end
	return false
end

local function eligibleExhibits(owner: Player): { { SlotId: string, Uid: string, Def: any } }
	local data = PlayerDataService.GetData(owner)
	local list = {}
	if not data then
		return list
	end
	for slotId, uid in data.Displays do
		local item = data.Inventory[uid]
		local def = item and ItemCatalog.Get(item.Id)
		if def and def.Heistable and not item.Reserved then
			table.insert(list, { SlotId = slotId, Uid = uid, Def = def })
		end
	end
	return list
end

local function securityScore(data: any): number
	local total = 0
	for id in HeistConfig.Systems do
		total += data.Security[id] or 0
	end
	return total
end

local function recentCount(attacker: Player, targetId: number): number
	local list: { { Target: number, Time: number } } = recentTargets[attacker.UserId] or {}
	local n = 0
	for _, entry in list do
		if entry.Target == targetId and os.time() - entry.Time < HeistConfig.RepeatWindow then
			n += 1
		end
	end
	return n
end

-- Can `attacker` start a heist at all?
local function attackerStatus(attacker: Player): (boolean, string?)
	local data = PlayerDataService.GetData(attacker)
	if not data then
		return false, "Data not loaded"
	end
	if Upgrades.ComputeLevel(data.Upgrades) < HeistConfig.AttackerMinLevel then
		return false, ("Reach Museum Level %d to plan heists"):format(HeistConfig.AttackerMinLevel)
	end
	if JailService.IsJailed(attacker) then
		return false, "You're in jail"
	end
	if missions[attacker] then
		return false, "You're already on a heist"
	end
	local wait = data.Heist.CooldownUntil - os.time()
	if wait > 0 then
		return false, ("Lie low for %s before your next heist"):format(Format.Seconds(wait))
	end
	return true, nil
end

-- Is `target` a fair target for `attacker` right now?
local function targetStatus(attacker: Player, target: Player): (boolean, string?)
	if target == attacker then
		return false, "That's your own museum"
	end
	local data = PlayerDataService.GetData(target)
	if not data or not PlotService.GetPlot(target) or not MuseumService.GetState(target) then
		return false, "Museum closed"
	end
	if Upgrades.ComputeLevel(data.Upgrades) < HeistConfig.TargetMinLevel then
		return false, "Protected (new museum)"
	end
	if PlayerDataService.PlaySeconds(target) < HeistConfig.TargetMinPlaySeconds then
		return false, "Protected (new curator)"
	end
	if data.Heist.ProtectedUntil > os.time() then
		return false, ("Protected for %s"):format(Format.Seconds(data.Heist.ProtectedUntil - os.time()))
	end
	if byOwner[target] then
		return false, "Already being robbed"
	end
	if JailService.IsJailed(target) or missions[target] then
		return false, "Owner is busy"
	end
	if recentCount(attacker, target.UserId) >= HeistConfig.RepeatMaxPerTarget then
		return false, "You've hit this museum enough for now"
	end
	if #eligibleExhibits(target) == 0 then
		return false, "Nothing worth stealing"
	end
	return true, nil
end

local function describe(target: Player): { [string]: any }
	local data = PlayerDataService.GetData(target)
	local score = if data then securityScore(data) else 0
	local best = 0
	for _, e in eligibleExhibits(target) do
		best = math.max(best, Rarities.Order(e.Def.Rarity))
	end
	local securityText = if score <= 2 then "Low" elseif score <= 5 then "Medium" elseif score <= 8 then "High" else "Fortress"
	local valueText = if best <= 2 then "Modest" elseif best <= 4 then "Valuable" else "Priceless"
	local difficulty = score + math.max(0, best - 2)
	local difficultyText = if difficulty <= 2 then "Easy" elseif difficulty <= 5 then "Moderate" elseif difficulty <= 8 then "Hard" else "Extreme"
	return {
		Level = if data then Upgrades.ComputeLevel(data.Upgrades) else 1,
		Security = securityText,
		Value = valueText,
		Difficulty = difficultyText,
		LockLevel = if data then data.Security.Locks else 0,
	}
end

-- ── Collision groups (after-hours shutter only blocks the thief) ──────────
local function setupCollisionGroups()
	pcall(function()
		PhysicsService:RegisterCollisionGroup("HeistBarrier")
	end)
	pcall(function()
		PhysicsService:RegisterCollisionGroup("Heister")
	end)
	PhysicsService:CollisionGroupSetCollidable("HeistBarrier", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("HeistBarrier", "HeistBarrier", false)
	PhysicsService:CollisionGroupSetCollidable("HeistBarrier", "Heister", true)
end

local function setCharacterGroup(character: Model?, group: string)
	if not character then
		return
	end
	for _, d in character:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

-- ── Sending state ──────────────────────────────────────────────────────────
local function gadgetSummary(mission: Mission): { any }
	local data = PlayerDataService.GetData(mission.Attacker)
	local list = {}
	if not data then
		return list
	end
	for _, uid in mission.Loadout do
		local item = data.Inventory[uid]
		local def = item and ItemCatalog.Get(item.Id)
		if item and def and def.Gadget then
			table.insert(list, { Uid = uid, Name = def.Name, Type = def.Gadget.Type, Tier = def.Gadget.Tier, Charges = item.Charges or 0 })
		end
	end
	return list
end

local function objective(mission: Mission): string
	if mission.State == "Entry" then
		return "Pick the lock on the front entrance."
	elseif mission.State == "Inside" then
		return "Find an exhibit and steal it. Avoid the cameras."
	elseif mission.State == "Escaping" then
		return "Escape to the getaway cart in the front yard!"
	end
	return ""
end

local function statusText(mission: Mission): string
	if mission.Alarm then
		return "ALARM — POLICE ON THE WAY"
	end
	local t = HeistConfig.Thresholds
	if mission.Suspicion >= t.Investigating then
		return "Investigating"
	elseif mission.Suspicion >= t.Suspicious then
		return "Suspicious activity"
	end
	return if mission.State == "Escaping" then "Artefact acquired" else "Undetected"
end

local function send(mission: Mission)
	mission.LastSend = os.clock()
	local now = os.clock()
	Net.Fire("HeistUpdate", mission.Attacker, {
		Active = true,
		State = mission.State,
		Status = statusText(mission),
		Objective = objective(mission),
		Suspicion = math.floor(mission.Suspicion),
		Alarm = mission.Alarm,
		AlarmLeft = if mission.Alarm then math.max(0, HeistConfig.AlarmEscapeSeconds - (now - mission.AlarmAt)) else nil,
		TimeLeft = math.max(0, HeistConfig.MaxMissionSeconds - (now - mission.Started)),
		Seen = mission.Seen,
		Sneaking = mission.Sneaking,
		Gadgets = gadgetSummary(mission),
		OwnerName = mission.Owner.DisplayName,
	})
end

local function alertOwner(mission: Mission, kind: string, text: string)
	Net.Fire("SecurityAlert", mission.Owner, { Kind = kind, Text = text })
	Notifier.Send(mission.Owner, text, if kind == "Caught" then "Reward" else "Error")
end

local function addIncident(owner: Player, entry: { [string]: any })
	local data = PlayerDataService.GetData(owner)
	if not data then
		return
	end
	entry.Time = os.time()
	table.insert(data.Heist.Incidents, 1, entry)
	while #data.Heist.Incidents > 15 do
		table.remove(data.Heist.Incidents)
	end
	StateSync.Mark(owner)
end

-- ── Ending a mission ───────────────────────────────────────────────────────
local function cleanup(mission: Mission)
	for _, c in mission.Connections do
		c:Disconnect()
	end
	for _, p in mission.StealPrompts do
		p:Destroy()
	end
	if mission.ApprehendPrompt then
		mission.ApprehendPrompt:Destroy()
	end
	mission.Folder:Destroy()
	setCharacterGroup(mission.Attacker.Character, "Default")
	local humanoid = humanoidOf(mission.Attacker)
	if humanoid then
		humanoid.WalkSpeed = HeistConfig.NormalSpeed
	end
	mission.Attacker:SetAttribute("InHeist", nil)
	local attackerData = PlayerDataService.GetData(mission.Attacker)
	if attackerData then
		InventoryService.ReleaseAll(attackerData, "Loadout", mission.Id)
		StateSync.Mark(mission.Attacker)
	end
	ChallengeService.Cancel(mission.Attacker, "Heist ended")
	missions[mission.Attacker] = nil
	if byOwner[mission.Owner] == mission then
		byOwner[mission.Owner] = nil
	end
end

local function returnExhibit(mission: Mission)
	local ownerData = PlayerDataService.GetData(mission.Owner)
	if ownerData and mission.TargetUid then
		InventoryService.Release(ownerData, mission.TargetUid, "Heist", mission.Id)
		if mission.TargetSlot then
			MuseumService.RefreshSlot(mission.Owner, mission.TargetSlot)
		end
		StateSync.Mark(mission.Owner)
	end
end

local endMission: (Mission, string, string) -> ()

endMission = function(mission: Mission, outcome: string, reason: string)
	if mission.State == "Done" then
		return
	end
	local wasState = mission.State
	mission.State = "Done"
	local attacker, owner = mission.Attacker, mission.Owner
	local attackerData = PlayerDataService.GetData(attacker)
	local ownerData = PlayerDataService.GetData(owner)
	local now = os.time()
	local itemName = nil
	if mission.TargetUid and ownerData and ownerData.Inventory[mission.TargetUid] then
		local def = ItemCatalog.Get(ownerData.Inventory[mission.TargetUid].Id)
		itemName = def and def.Name
	end

	if outcome == "Escaped" and mission.TargetUid and ownerData and attackerData then
		local item = ownerData.Inventory[mission.TargetUid]
		local def = item and ItemCatalog.Get(item.Id)
		if item and def then
			local loot = table.clone(item)
			loot.Reserved = nil
			loot.Locked = false
			loot.Provenance = ("Stolen from %s's museum"):format(owner.DisplayName)
			local insurance = if ownerData.Upgrades.security then math.floor(InventoryService.ValueOf(item) * HeistConfig.InsuranceRate) else 0
			local ok, err = LedgerService.Commit(mission.Id, {
				[owner] = { Remove = { mission.TargetUid }, Add = {}, Cash = insurance },
				[attacker] = { Remove = {}, Add = { loot }, Cash = 0 },
			})
			if ok then
				attackerData.Heist.Successes += 1
				ownerData.Heist.Robbed += 1
				ownerData.Heist.ProtectedUntil = now + HeistConfig.TargetProtectAfterTheft
				attackerData.Heist.CooldownUntil = now + HeistConfig.AttackerCooldown
				AchievementService.Award(attacker, "heist_success")
				addIncident(owner, { Thief = attacker.DisplayName, Outcome = "Stolen", Item = def.Name, Insurance = insurance })
				alertOwner(mission, "Stolen", ("%s escaped with your %s!%s"):format(attacker.DisplayName, def.Name, if insurance > 0 then (" Insurance paid %s."):format(Format.Cash(insurance)) else ""))
				Notifier.Send(attacker, ("You got away with the %s!"):format(def.Name), "Reward")
				cleanup(mission)
				MuseumService.RefreshAll(owner)
				Net.Fire("HeistUpdate", attacker, { Active = false, Outcome = "Escaped", Reason = ("You escaped with the %s."):format(def.Name), ItemId = def.Id })
				return
			end
			Notifier.Send(attacker, err or "The getaway failed.", "Error")
			outcome = "Aborted"
			reason = "The getaway failed — the exhibit was left behind."
		end
	end

	returnExhibit(mission)

	if outcome == "Captured" then
		if attackerData then
			attackerData.Heist.Captures += 1
			attackerData.Heist.CooldownUntil = now + HeistConfig.CaptureCooldown
			local fine = math.min(HeistConfig.FineCap, math.floor(attackerData.Cash * HeistConfig.FineRate))
			if fine > 0 and EconomyService.Spend(attacker, fine, "HeistFine") then
				EconomyService.Add(owner, fine, "HeistBounty")
			end
			JailService.Jail(attacker, Config.JailSeconds, reason)
			Notifier.Send(attacker, ("Caught! %s Fine: %s."):format(reason, Format.Cash(fine)), "Error")
		end
		if ownerData then
			ownerData.Heist.Defended += 1
			ownerData.Heist.ProtectedUntil = math.max(ownerData.Heist.ProtectedUntil, now + HeistConfig.TargetProtectAfterAttempt)
			AchievementService.Award(owner, "museum_defended")
		end
		addIncident(owner, { Thief = attacker.DisplayName, Outcome = "Caught", Item = itemName })
		alertOwner(mission, "Caught", ("Thief caught: %s (%s)"):format(attacker.DisplayName, reason))
	else
		if attackerData then
			attackerData.Heist.CooldownUntil = now + HeistConfig.AttackerCooldown
		end
		if ownerData and wasState ~= "Entry" then
			ownerData.Heist.ProtectedUntil = math.max(ownerData.Heist.ProtectedUntil, now + HeistConfig.TargetProtectAfterAttempt)
			addIncident(owner, { Thief = attacker.DisplayName, Outcome = "Fled", Item = itemName })
		end
		Net.Fire("SecurityAlert", owner, { Kind = "Fled", Text = ("The intruder (%s) is gone. %s"):format(attacker.DisplayName, reason) })
		if attacker.Parent and not JailService.IsJailed(attacker) then
			PlotService.TeleportHome(attacker)
		end
	end
	cleanup(mission)
	if attacker.Parent then
		Net.Fire("HeistUpdate", attacker, { Active = false, Outcome = outcome, Reason = reason })
	end
	StateSync.Mark(attacker)
	StateSync.Mark(owner)
end

local function triggerAlarm(mission: Mission, why: string)
	if mission.Alarm or mission.State == "Done" then
		return
	end
	mission.Alarm = true
	mission.AlarmAt = os.clock()
	mission.Suspicion = HeistConfig.Thresholds.Alarm
	local sound = Instance.new("Sound")
	sound.Name = "AlarmSound"
	sound.SoundId = Config.Sounds.Alarm
	sound.Looped = true
	sound.Volume = 0.8
	sound.PlaybackSpeed = 0.6
	sound.RollOffMaxDistance = 160
	sound.Parent = mission.Getaway
	sound:Play()
	mission.AlarmSound = sound
	alertOwner(mission, "Alarm", ("ALARM in your museum! %s (%s)"):format(why, mission.Attacker.DisplayName))
	Notifier.Send(mission.Attacker, ("ALARM! %s — escape within %ds!"):format(why, HeistConfig.AlarmEscapeSeconds), "Error")
	send(mission)
end

local function addSuspicion(mission: Mission, amount: number, why: string?)
	if mission.State == "Done" or mission.Alarm then
		return
	end
	mission.Suspicion = math.clamp(mission.Suspicion + amount, 0, HeistConfig.Thresholds.Alarm)
	if mission.Suspicion >= HeistConfig.Thresholds.Alarm then
		triggerAlarm(mission, why or "Too much suspicion")
	end
end

-- ── Gadget lookup ──────────────────────────────────────────────────────────
local function findGadget(mission: Mission, gadgetType: string, minTier: number): (string?, any?)
	local data = PlayerDataService.GetData(mission.Attacker)
	if not data then
		return nil, nil
	end
	local bestUid, bestDef = nil, nil
	for _, uid in mission.Loadout do
		local item = data.Inventory[uid]
		local def = item and ItemCatalog.Get(item.Id)
		if def and def.Gadget and def.Gadget.Type == gadgetType and def.Gadget.Tier >= minTier and (item.Charges or 0) > 0 then
			if not bestDef or def.Gadget.Tier > bestDef.Gadget.Tier then
				bestUid, bestDef = uid, def
			end
		end
	end
	return bestUid, bestDef
end

-- ── Entering ───────────────────────────────────────────────────────────────
local function openEntrance(mission: Mission)
	if mission.Barrier then
		mission.Barrier:Destroy()
		mission.Barrier = nil
	end
	mission.State = "Inside"
	Notifier.Send(mission.Attacker, "You're in. Find an exhibit — and stay out of the cameras' sight.", "Success")
	send(mission)
end

local function onLockPrompt(mission: Mission, who: Player)
	if who ~= mission.Attacker or mission.State ~= "Entry" or mission.Busy then
		return
	end
	local lockTier = SecurityService.Level(mission.Owner, "Locks")
	if lockTier <= 0 then
		openEntrance(mission)
		return
	end
	local uid, def = findGadget(mission, "Lockpick", lockTier)
	if not uid or not def then
		local anyPick = findGadget(mission, "Lockpick", 1)
		Notifier.Send(who, if anyPick then "This lock is too good for your picks — you need Master Lockpicks." else "You need a Lockpick Set in your loadout.", "Error")
		return
	end
	local cfg = HeistConfig.Lockpick
	mission.Busy = true
	local barrier = mission.Barrier :: BasePart
	ChallengeService.Begin(who, {
		Kind = "Timing",
		Title = ("Picking the lock (%s)"):format(HeistConfig.Systems.Locks.Levels[lockTier]),
		Subtitle = ("Set each pin when the marker is in the gold zone. %d misses snaps your pick."):format(cfg.MaxMisses),
		Theme = "Lockpick",
		Presses = 2 + lockTier,
		Speed = cfg.BaseSpeed + cfg.SpeedPerTier * lockTier,
		ZoneWidth = math.max(0.08, (cfg.Zone[def.Gadget.Tier] or 0.17) - cfg.ZonePerTier * lockTier),
		MaxMisses = cfg.MaxMisses,
		MaxSeconds = 25,
		Anchor = barrier.Position,
		Radius = 12,
	}, function(result)
		mission.Busy = false
		if mission.State ~= "Entry" then
			return
		end
		if result.Cancelled then
			return
		end
		InventoryService.UseCharge(who, uid)
		if result.Success then
			openEntrance(mission)
		else
			Notifier.Send(who, "Snap! Your pick broke. That was loud...", "Error")
			addSuspicion(mission, cfg.BreakSuspicion, "A loud snap at the door")
			send(mission)
		end
	end, function(hit)
		if not hit then
			addSuspicion(mission, cfg.MissSuspicion, "Rattling at the door")
		end
	end)
end

-- ── Stealing ───────────────────────────────────────────────────────────────
local function takeExhibit(mission: Mission, slotId: string, uid: string)
	local ownerData = PlayerDataService.GetData(mission.Owner)
	if not ownerData or mission.State ~= "Inside" then
		return
	end
	if not InventoryService.Reserve(ownerData, uid, "Heist", mission.Id) then
		Notifier.Send(mission.Attacker, "Someone moved that exhibit.", "Error")
		return
	end
	mission.TargetUid = uid
	mission.TargetSlot = slotId
	mission.State = "Escaping"
	for _, p in mission.StealPrompts do
		p:Destroy()
	end
	mission.StealPrompts = {}
	MuseumService.RefreshSlot(mission.Owner, slotId)
	StateSync.Mark(mission.Owner)
	local def = ItemCatalog.Get(ownerData.Inventory[uid].Id)
	local rarity = if def then def.Rarity else "Common"
	addSuspicion(mission, HeistConfig.ExtractSuspicion + (HeistConfig.ValueSuspicion[rarity] or 0), "An exhibit went missing")
	Net.Fire("SecurityAlert", mission.Owner, { Kind = "Intruder", Text = "Something's wrong in your museum... an exhibit is missing!" })
	Notifier.Send(mission.Attacker, ("Got the %s! Now get to the getaway cart!"):format(if def then def.Name else "exhibit"), "Reward")
	send(mission)
end

local function onStealPrompt(mission: Mission, who: Player, slotId: string, fixture: any)
	if who ~= mission.Attacker or mission.State ~= "Inside" or mission.Busy then
		return
	end
	local ownerData = PlayerDataService.GetData(mission.Owner)
	local uid = ownerData and ownerData.Displays[slotId]
	local item = uid and ownerData.Inventory[uid]
	local def = item and ItemCatalog.Get(item.Id)
	if not uid or not item or not def or not def.Heistable or item.Reserved then
		Notifier.Send(who, "Nothing you can take here.", "Error")
		return
	end
	local hrp = hrpOf(who)
	if not hrp or (hrp.Position - fixture.PromptPart.Position).Magnitude > 12 then
		return
	end
	local slotType = fixture.Model:GetAttribute("SlotType")
	local caseTier = SecurityService.CaseTier(mission.Owner, slotType)
	if caseTier > 0 then
		local cutterUid, cutterDef = findGadget(mission, "Cutter", caseTier)
		if not cutterUid or not cutterDef then
			Notifier.Send(who, ("This glass is tier %d — you need a cutter that can handle it."):format(caseTier), "Error")
			return
		end
		local cfg = HeistConfig.Cutter
		mission.Busy = true
		ChallengeService.Begin(who, {
			Kind = "Timing",
			Title = ("Cutting tier %d glass"):format(caseTier),
			Subtitle = "Steady strokes. 2 slips and the glass cracks loudly.",
			Theme = "Glass",
			Presses = cfg.Strokes,
			Speed = cfg.BaseSpeed + cfg.SpeedPerTier * caseTier,
			ZoneWidth = math.max(0.08, (cfg.Zone[cutterDef.Gadget.Tier] or 0.19) - cfg.ZonePerTier * caseTier),
			MaxMisses = 2,
			MaxSeconds = 20,
			Anchor = fixture.PromptPart.Position,
			Radius = 12,
		}, function(result)
			mission.Busy = false
			if result.Cancelled or mission.State ~= "Inside" then
				return
			end
			InventoryService.UseCharge(who, cutterUid)
			if result.Success then
				takeExhibit(mission, slotId, uid)
			else
				Notifier.Send(who, "The glass cracked with a loud bang!", "Error")
				addSuspicion(mission, cfg.FailSuspicion, "Breaking glass")
				send(mission)
			end
		end)
		return
	end
	local alarmTier = SecurityService.Level(mission.Owner, "Alarm")
	if alarmTier <= 0 then
		takeExhibit(mission, slotId, uid)
		return
	end
	local cfg = HeistConfig.Plate
	mission.Busy = true
	ChallengeService.Begin(who, {
		Kind = "Timing",
		Title = "Lifting it off the pressure pad",
		Subtitle = if alarmTier >= 2 then "Swap the weight perfectly — a mistake trips the alarm!" else "Swap the weight smoothly.",
		Theme = "Plate",
		Presses = 1,
		Speed = cfg.Speed,
		ZoneWidth = math.max(0.08, cfg.BaseZone - cfg.ZonePerTier * alarmTier),
		MaxMisses = 1,
		MaxSeconds = 12,
		Anchor = fixture.PromptPart.Position,
		Radius = 12,
	}, function(result)
		mission.Busy = false
		if result.Cancelled or mission.State ~= "Inside" then
			return
		end
		if result.Success then
			takeExhibit(mission, slotId, uid)
		elseif alarmTier >= 2 then
			triggerAlarm(mission, "Pressure pad triggered")
		else
			Notifier.Send(who, "The pad clicked... someone might have noticed.", "Error")
			addSuspicion(mission, cfg.FailSuspicion, "Pressure pad")
			send(mission)
		end
	end)
end

-- ── Detection tick ─────────────────────────────────────────────────────────
local function cameraSees(mission: Mission, cam: SecurityService.CameraInfo, hrp: BasePart): boolean
	local toTarget = hrp.Position - cam.CFrame.Position
	local dist = toTarget.Magnitude
	if dist > cam.Range or dist < 0.5 then
		return false
	end
	local angle = math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(toTarget.Unit), -1, 1)))
	if angle > cam.Fov / 2 then
		return false
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude: { Instance } = { cam.Model, mission.Folder }
	if mission.Attacker.Character then
		table.insert(exclude, mission.Attacker.Character)
	end
	params.FilterDescendantsInstances = exclude
	local hit = workspace:Raycast(cam.CFrame.Position, toTarget, params)
	return hit == nil
end

local function tick(mission: Mission, dt: number)
	if mission.State == "Done" then
		return
	end
	local now = os.clock()
	local hrp = hrpOf(mission.Attacker)
	local humanoid = humanoidOf(mission.Attacker)
	if not hrp or not humanoid or humanoid.Health <= 0 then
		endMission(mission, if mission.State == "Escaping" then "Captured" else "Aborted", "You were knocked out")
		return
	end
	if not mission.Owner.Parent or not MuseumService.GetState(mission.Owner) then
		endMission(mission, "Aborted", "The museum closed")
		return
	end
	-- Anti-exploit: inside before the entrance was opened = through a wall.
	if mission.State == "Entry" and isInside(mission, hrp.Position) then
		endMission(mission, "Captured", "Security spotted you climbing through a wall")
		return
	end
	if now - mission.Started > HeistConfig.MaxMissionSeconds then
		endMission(mission, if mission.State == "Escaping" then "Captured" else "Aborted", "Dawn broke — out of time")
		return
	end
	if mission.Alarm and now - mission.AlarmAt > HeistConfig.AlarmEscapeSeconds then
		endMission(mission, "Captured", "The police arrived")
		return
	end
	if mission.State == "Escaping" then
		local flat = Vector3.new(hrp.Position.X - mission.Getaway.Position.X, 0, hrp.Position.Z - mission.Getaway.Position.Z)
		if flat.Magnitude <= 9 then
			endMission(mission, "Escaped", "Clean getaway")
			return
		end
	end

	-- Cameras
	local seen = false
	if mission.State ~= "Entry" then
		for _, cam in SecurityService.GetCameras(mission.Owner) do
			local jammed = (mission.Jammed[cam.Id] or 0) > now
			if cam.Led.Parent then
				cam.Led.Color = if jammed then Color3.fromRGB(30, 30, 30) else Color3.fromRGB(255, 40, 40)
			end
			if not jammed and cameraSees(mission, cam, hrp) then
				seen = true
			end
		end
	end
	mission.Seen = seen
	if not mission.Alarm then
		if seen then
			local camLevel = SecurityService.Level(mission.Owner, "Cameras")
			local rate = HeistConfig.CameraRate * (1 + 0.3 * (camLevel - 1)) * (if mission.Sneaking then 0.6 else 1)
			addSuspicion(mission, rate * dt, "Spotted on camera")
		else
			mission.Suspicion = math.max(0, mission.Suspicion - HeistConfig.SuspicionDecay * dt)
		end
	end
	if now - mission.LastSend > 0.25 then
		send(mission)
	end
end

-- ── Starting ───────────────────────────────────────────────────────────────
local function makeGetaway(folder: Folder, origin: CFrame): BasePart
	local base = origin * CFrame.new(GETAWAY)
	local function p(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): Part
		local part = Instance.new("Part")
		part.Anchored = true
		part.CanCollide = false
		part.Size = size
		part.CFrame = base * offset
		part.Color = color
		part.Material = material or Enum.Material.Wood
		part.Parent = folder
		return part
	end
	local cart = p(Vector3.new(6, 2.4, 4), CFrame.new(0, 2.2, 0), Color3.fromRGB(70, 50, 35))
	cart.Name = "GetawayCart"
	p(Vector3.new(6.4, 0.4, 4.4), CFrame.new(0, 3.5, 0), Color3.fromRGB(40, 30, 25))
	for _, x in { -2.2, 2.2 } do
		for _, z in { -2.3, 2.3 } do
			p(Vector3.new(0.4, 2, 2), CFrame.new(x, 1, z) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(30, 25, 20)).Shape = Enum.PartType.Cylinder
		end
	end
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromOffset(160, 40)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 5, 0)
	sign.AlwaysOnTop = true
	sign.MaxDistance = 300
	sign.Adornee = cart
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.TextScaled = true
	label.Font = Enum.Font.GothamBold
	label.TextColor3 = Color3.fromRGB(255, 220, 120)
	label.TextStrokeTransparency = 0.3
	label.Text = "GETAWAY"
	label.Parent = sign
	sign.Parent = cart
	sign:SetAttribute("HeistFor", 0)
	return cart
end

function HeistService.StartHeist(attacker: Player, targetUserId: any, gadgetUids: any): (boolean, string?)
	local ok, why = attackerStatus(attacker)
	if not ok then
		return false, why
	end
	if not Net.IsInt(targetUserId, 1, 2 ^ 53) then
		return false, "Invalid target"
	end
	local owner = Players:GetPlayerByUserId(targetUserId)
	if not owner then
		return false, "That museum is closed"
	end
	local okTarget, whyTarget = targetStatus(attacker, owner)
	if not okTarget then
		return false, whyTarget
	end
	local attackerData = PlayerDataService.GetData(attacker) :: any
	-- Loadout validation
	local loadout = {}
	if type(gadgetUids) == "table" then
		for _, uid in gadgetUids do
			if #loadout >= HeistConfig.MaxLoadout then
				break
			end
			if type(uid) == "string" and not table.find(loadout, uid) then
				local item = attackerData.Inventory[uid]
				local def = item and ItemCatalog.Get(item.Id)
				if def and def.Gadget and not item.Reserved and (item.Charges or 0) > 0 then
					table.insert(loadout, uid)
				end
			end
		end
	end
	local hrp = hrpOf(attacker)
	if not hrp then
		return false, "You need to be alive"
	end
	local state = MuseumService.GetState(owner)
	local origin: CFrame = state.Origin
	for _, uid in loadout do
		InventoryService.Reserve(attackerData, uid, "Loadout", "pending")
	end

	local folder = Instance.new("Folder")
	folder.Name = "HeistMission"
	folder.Parent = state.Folder
	-- After-hours shutter at the entrance (only collides with the thief)
	local barrier = Instance.new("Part")
	barrier.Name = "HeistShutter"
	barrier.Anchored = true
	barrier.Size = Vector3.new(10, 12, 1)
	barrier.CFrame = origin * CFrame.new(0, 7, -10)
	barrier.Color = Color3.fromRGB(150, 40, 40)
	barrier.Material = Enum.Material.DiamondPlate
	barrier.Transparency = 0.35
	barrier.CollisionGroup = "HeistBarrier"
	barrier.CanTouch = false
	barrier:SetAttribute("HeistFor", attacker.UserId)
	CollectionService:AddTag(barrier, "HeistOnly")
	barrier.Parent = folder

	local mission: Mission = {
		Id = LedgerService.NewId(),
		Attacker = attacker,
		Owner = owner,
		Origin = origin,
		State = "Entry",
		Suspicion = 0,
		Alarm = false,
		AlarmAt = 0,
		Started = os.clock(),
		Loadout = loadout,
		Folder = folder,
		Barrier = barrier,
		Getaway = makeGetaway(folder, origin),
		StealPrompts = {},
		ApprehendPrompt = nil,
		AlarmSound = nil,
		TargetUid = nil,
		TargetSlot = nil,
		Jammed = {},
		Sneaking = false,
		Seen = false,
		Busy = false,
		LastSend = 0,
		Connections = {},
	}
	for _, uid in loadout do
		local item = attackerData.Inventory[uid]
		if item and item.Reserved then
			item.Reserved.Id = mission.Id
		end
	end
	missions[attacker] = mission
	byOwner[owner] = mission
	attacker:SetAttribute("InHeist", true)
	attackerData.Heist.Attempts += 1
	recentTargets[attacker.UserId] = recentTargets[attacker.UserId] or {}
	table.insert(recentTargets[attacker.UserId], { Target = owner.UserId, Time = os.time() })

	-- Lock prompt (only the thief sees it; the client hides HeistOnly prompts)
	local lockTier = SecurityService.Level(owner, "Locks")
	local lockPrompt = Instance.new("ProximityPrompt")
	lockPrompt.ActionText = if lockTier > 0 then "Pick Lock" else "Slip Inside"
	lockPrompt.ObjectText = "Entrance shutter"
	lockPrompt.HoldDuration = 0
	lockPrompt.MaxActivationDistance = 10
	lockPrompt.RequiresLineOfSight = false
	lockPrompt:SetAttribute("HeistFor", attacker.UserId)
	CollectionService:AddTag(lockPrompt, "HeistOnly")
	lockPrompt.Parent = barrier
	table.insert(mission.Connections, lockPrompt.Triggered:Connect(function(who)
		onLockPrompt(mission, who)
	end))

	-- Steal prompts on eligible exhibits
	for _, e in eligibleExhibits(owner) do
		local fixture = state.Fixtures[e.SlotId]
		if fixture then
			local p = Instance.new("ProximityPrompt")
			p.ActionText = "Steal"
			p.ObjectText = e.Def.Name
			p.HoldDuration = 0.4
			p.MaxActivationDistance = 9
			p.RequiresLineOfSight = false
			p.KeyboardKeyCode = Enum.KeyCode.F
			p:SetAttribute("HeistFor", attacker.UserId)
			CollectionService:AddTag(p, "HeistOnly")
			p.Parent = fixture.PromptPart
			table.insert(mission.StealPrompts, p)
			table.insert(mission.Connections, p.Triggered:Connect(function(who)
				onStealPrompt(mission, who, e.SlotId, fixture)
			end))
		end
	end

	-- The owner can catch the thief in person
	local apprehend = Instance.new("ProximityPrompt")
	apprehend.ActionText = "Apprehend Thief"
	apprehend.ObjectText = attacker.DisplayName
	apprehend.HoldDuration = 0.5
	apprehend.MaxActivationDistance = HeistConfig.ApprehendRadius
	apprehend.RequiresLineOfSight = false
	apprehend.KeyboardKeyCode = Enum.KeyCode.F
	apprehend:SetAttribute("HeistFor", owner.UserId)
	CollectionService:AddTag(apprehend, "HeistOnly")
	apprehend.Parent = hrp
	mission.ApprehendPrompt = apprehend
	table.insert(mission.Connections, apprehend.Triggered:Connect(function(who)
		if who == owner and mission.State ~= "Done" then
			endMission(mission, "Captured", ("%s caught you red-handed"):format(owner.DisplayName))
		end
	end))

	-- Thief collides with the shutter; reset = mission over
	setCharacterGroup(attacker.Character, "Heister")
	local character = attacker.Character :: Model
	table.insert(mission.Connections, character.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			d.CollisionGroup = "Heister"
		end
	end))
	table.insert(mission.Connections, attacker.CharacterRemoving:Connect(function()
		endMission(mission, if mission.State == "Escaping" then "Captured" else "Aborted", "You vanished mid-heist")
	end))

	character:PivotTo(CFrame.lookAt((origin * CFrame.new(START)).Position, (origin * CFrame.new(0, 3, 0)).Position))
	Notifier.Send(attacker, ("Heist on %s's museum! Pick the lock, steal one exhibit, reach the GETAWAY cart."):format(owner.DisplayName), "Info")
	send(mission)
	return true, nil
end

function HeistService.Action(player: Player, action: any): (boolean, string?)
	local mission = missions[player]
	if not mission or mission.State == "Done" then
		return false, "You're not on a heist"
	end
	if action == "Sneak" then
		mission.Sneaking = not mission.Sneaking
		local humanoid = humanoidOf(player)
		if humanoid then
			humanoid.WalkSpeed = if mission.Sneaking then HeistConfig.SneakSpeed else HeistConfig.NormalSpeed
		end
		send(mission)
		return true, nil
	elseif action == "Jammer" then
		local uid = findGadget(mission, "Jammer", 1)
		if not uid then
			return false, "No Camera Jammer charges left"
		end
		local hrp = hrpOf(player)
		if not hrp then
			return false, nil
		end
		local camLevel = math.clamp(SecurityService.Level(mission.Owner, "Cameras"), 1, 3)
		local untilTime = os.clock() + HeistConfig.JammerSeconds[camLevel]
		local count = 0
		for _, cam in SecurityService.GetCameras(mission.Owner) do
			if (cam.CFrame.Position - hrp.Position).Magnitude <= 40 then
				mission.Jammed[cam.Id] = untilTime
				count += 1
			end
		end
		if count == 0 then
			return false, "No cameras in range of the jammer"
		end
		InventoryService.UseCharge(player, uid)
		send(mission)
		return true, ("Jammed %d camera(s) for %ds"):format(count, HeistConfig.JammerSeconds[camLevel])
	elseif action == "Abort" then
		if mission.State == "Escaping" then
			endMission(mission, "Captured", "You surrendered")
		else
			endMission(mission, "Aborted", "You called off the heist")
		end
		return true, nil
	end
	return false, "Unknown action"
end

function HeistService.GetTargets(player: Player): (boolean, string?, any)
	local okAttacker, why = attackerStatus(player)
	local list = {}
	for _, other in Players:GetPlayers() do
		if other ~= player and PlayerDataService.GetData(other) then
			local ok, reason = targetStatus(player, other)
			local info = describe(other)
			info.UserId = other.UserId
			info.Name = other.DisplayName
			info.Available = ok
			info.Reason = reason
			table.insert(list, info)
		end
	end
	table.sort(list, function(a, b)
		if a.Available ~= b.Available then
			return a.Available
		end
		return a.Level > b.Level
	end)
	return true, nil, { CanHeist = okAttacker, Reason = why, Targets = list, MaxLoadout = HeistConfig.MaxLoadout }
end

function HeistService.Init() end

function HeistService.Start()
	setupCollisionGroups()
	Net.Handle("GetHeistTargets", HeistService.GetTargets)
	Net.Handle("StartHeist", HeistService.StartHeist)
	Net.Handle("HeistAction", HeistService.Action)

	-- Leaving mid-heist: the thief never keeps loot, the owner keeps the exhibit.
	PlayerDataService.OnReleasing(function(player)
		local m = missions[player]
		if m then
			endMission(m, if m.State == "Escaping" then "Captured" else "Aborted", "Left the game during the heist")
		end
		local o = byOwner[player]
		if o then
			endMission(o, "Aborted", "The museum owner left")
		end
	end)

	local accumulator = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulator += dt
		if accumulator < HeistConfig.TickSeconds then
			return
		end
		local step = accumulator
		accumulator = 0
		for _, mission in missions do
			local ok, err = pcall(tick, mission, step)
			if not ok then
				warn("[Heist] tick error: " .. tostring(err))
			end
		end
	end)
end

return HeistService
