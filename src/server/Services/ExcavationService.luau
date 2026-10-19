--[[
	ExcavationService
	The multi-stage discovery loop:

	  1. PREPARE   — your kit decides scan range, precision, dig depth, tools.
	  2. DETECT    — Scan: Weak / Moderate / Strong / Pinpoint, an imperfect
	                 direction, maybe depth & material. Readings can be false
	                 positives; mineral deposits and empty pockets fool basic
	                 scanners.
	  3. NARROW    — follow the signal until it says Pinpoint, then Dig Here.
	                 Visible dig sites skip straight to step 4.
	  4. CHOOSE    — Brush (gentle), Trowel (quick) or Pick (heavy stone).
	                 The server tells you what it can about the find first,
	                 including the risk.
	  5. EXCAVATE  — a server-judged timing challenge.
	  6. RECOVER   — Perfect / Clean / Damaged (or broken into fragments for
	                 a careless dig on a very fragile, ordinary find).

	Everything is rolled and judged on the server. The artefact is rolled when
	you first reach the dig, and walking away does NOT re-roll it.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local ItemCatalog = require(Shared.ItemCatalog)
local Rarities = require(Shared.Rarities)
local Equipment = require(Shared.Equipment)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local ProgressionService = require(script.Parent.ProgressionService)
local DiscoveryService = require(script.Parent.DiscoveryService)
local ChallengeService = require(script.Parent.ChallengeService)
local AchievementService = require(script.Parent.AchievementService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Secrets = require(script.Parent.Parent.World.Secrets)

local ExcavationService = {}

type Roll = { ItemId: string?, DecoyKind: string? }

type Target = {
	Key: string, -- cooldown / roll key
	Kind: string, -- "Site" | "Cache"
	Zone: string,
	Name: string,
	Position: Vector3,
	RareBoost: number,
	ScrapChance: number,
	Heavy: boolean,
	Fragile: boolean,
	MinTool: number,
	Depth: number,
	Part: BasePart?,
	Cache: Secrets.CacheDef?,
	Special: string?,
}

type Session = { Id: string, Target: Target, Roll: Roll, Started: boolean, Heavy: boolean }

export type SpecialHandler = {
	Check: (Player, BasePart) -> (boolean, string?),
	Roll: (Player, BasePart) -> Roll,
	After: (Player, BasePart, string?, string?) -> (), -- (player, part, itemId, condition)
}

local specials: { [string]: SpecialHandler } = {}
local sessions: { [Player]: Session } = {}
local pendingRolls: { [Player]: { [string]: Roll } } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local lastScan: { [Player]: number } = {}
local hollowRevealed: { [Player]: { [string]: number } } = {}
local rng = Random.new()

local DEPTH_NAMES = { "Shallow", "Medium", "Deep" }
local MATERIAL_NAMES = {
	Metal = "Metallic",
	Stone = "Dense stone",
	Ceramic = "Fired clay",
	Organic = "Bone / organic",
	Gem = "Crystalline (gem)",
	Paper = "Fibrous (scroll or cloth)",
}

local function root(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and hrp and hrp:IsA("BasePart") then
		return hrp
	end
	return nil
end

local function flatDistance(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function onCooldown(player: Player, key: string): number
	local t = cooldowns[player] and cooldowns[player][key]
	if t and t > os.clock() then
		return t - os.clock()
	end
	return 0
end

local function setCooldown(player: Player, key: string, seconds: number)
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player][key] = os.clock() + seconds
end

local function kitFor(player: Player): Equipment.ToolDef
	local data = PlayerDataService.GetData(player)
	return Equipment.Get(if data then data.ToolTier else 1)
end

local function rollFor(player: Player, target: Target): Roll
	pendingRolls[player] = pendingRolls[player] or {}
	local existing = pendingRolls[player][target.Key]
	if existing then
		return existing
	end
	local roll: Roll
	if target.Special and specials[target.Special] and target.Part then
		roll = specials[target.Special].Roll(player, target.Part)
	elseif target.Cache and target.Cache.Decoy then
		roll = { ItemId = nil, DecoyKind = target.Cache.DecoyKind }
	else
		local kit = kitFor(player)
		local itemId = DiscoveryService.RollWith(target.Zone, target.RareBoost, kit.Luck, target.ScrapChance)
		-- A fragile dig site favours fragile finds: one re-roll toward fragility.
		if itemId and target.Fragile then
			local def = ItemCatalog.Get(itemId)
			if def and def.Fragility < 0.5 then
				itemId = DiscoveryService.RollWith(target.Zone, target.RareBoost, kit.Luck, 0) or itemId
			end
		end
		roll = { ItemId = itemId, DecoyKind = nil }
	end
	pendingRolls[player][target.Key] = roll
	return roll
end

-- ── Scanning ───────────────────────────────────────────────────────────────
local function scanRange(player: Player, zoneId: string): (number, boolean)
	local data = PlayerDataService.GetData(player)
	local kit = kitFor(player)
	local range = kit.ScanRange
	local material = kit.ShowsMaterial
	if data then
		for id, owned in data.Attachments do
			local att = Equipment.Attachments[id]
			if owned and att and att.Zone == zoneId then
				range *= att.RangeMultiplier
				material = material or att.ShowsMaterial
			end
		end
	end
	return range, material
end

local function scan(player: Player): (boolean, string?, any)
	local now = os.clock()
	if (lastScan[player] or 0) + Config.ScanCooldownSeconds > now then
		return false, nil, nil
	end
	lastScan[player] = now
	local zoneId = player:GetAttribute("Zone")
	if type(zoneId) ~= "string" or not Zones.ById[zoneId] then
		return false, "The scanner only works on expeditions.", nil
	end
	local hrp = root(player)
	if not hrp then
		return false, nil, nil
	end
	local pos = hrp.Position
	local kit = kitFor(player)
	local range, showsMaterial = scanRange(player, zoneId)

	local reading: { [string]: any } = { Signal = "None", Range = math.floor(range) }

	-- Hollow walls (Jungle Root Chamber)
	for _, hollow in Secrets.Hollows do
		if hollow.Zone == zoneId and (hollow.Position - pos).Magnitude <= Config.HollowScanRadius then
			hollowRevealed[player] = hollowRevealed[player] or {}
			hollowRevealed[player][hollow.Id] = now + 180
			reading.Hollow = true
		end
	end

	-- Nearest eligible cache
	local best: Secrets.CacheDef? = nil
	local bestDist = math.huge
	for _, cache in Secrets.Caches do
		if cache.Zone == zoneId and onCooldown(player, cache.Id) <= 0 then
			local d = flatDistance(cache.Position, pos)
			if d < bestDist then
				best, bestDist = cache, d
			end
		end
	end

	if best and bestDist <= range then
		local signal = if bestDist <= Config.DigHereRadius
			then "Pinpoint"
			elseif bestDist < range * 0.25 then "Strong"
			elseif bestDist < range * 0.55 then "Moderate"
			else "Weak"
		reading.Signal = signal
		reading.CanDig = signal == "Pinpoint"
		if kit.DirectionError and signal ~= "Pinpoint" then
			local dx, dz = best.Position.X - pos.X, best.Position.Z - pos.Z
			local angle = math.deg(math.atan2(dx, dz)) + rng:NextNumber(-kit.DirectionError, kit.DirectionError)
			reading.Direction = angle -- world yaw (0 = +Z); client turns it into an arrow
			reading.DirectionError = kit.DirectionError
		end
		if kit.ShowsDepth then
			reading.Depth = DEPTH_NAMES[best.Depth]
			reading.TooDeep = best.Depth > kit.DigDepth
		end
		if best.Decoy then
			if kit.FlagsFalseSignals then
				reading.Note = "Signal unstable — probably a " .. (if best.DecoyKind == "Mineral" then "mineral deposit" else "hollow pocket") .. "."
			end
			if showsMaterial then
				reading.Material = if best.DecoyKind == "Mineral" then "Mineral crystals" else "Nothing solid"
			end
		elseif showsMaterial and signal ~= "Weak" then
			local target: Target = ExcavationService._cacheTarget(best)
			local roll = rollFor(player, target)
			local def = roll.ItemId and ItemCatalog.Get(roll.ItemId)
			reading.Material = if def then (MATERIAL_NAMES[def.Material] or def.Material) else "Unclear"
		end
	elseif kit.Tier <= 2 and rng:NextNumber() < 0.15 then
		-- Cheap detectors sometimes crackle at nothing.
		reading.Signal = "Weak"
		reading.Note = "Faint crackle... could be interference."
	end
	return true, nil, reading
end

-- ── Excavation targets ─────────────────────────────────────────────────────
function ExcavationService._cacheTarget(cache: Secrets.CacheDef): Target
	return {
		Key = cache.Id,
		Kind = "Cache",
		Zone = cache.Zone,
		Name = cache.Name,
		Position = cache.Position,
		RareBoost = cache.RareBoost,
		ScrapChance = Zones.SiteTypes.Cache.ScrapChance,
		Heavy = false,
		Fragile = false,
		MinTool = 1,
		Depth = cache.Depth,
		Part = nil,
		Cache = cache,
		Special = nil,
	}
end

local function siteTarget(part: BasePart): Target
	return {
		Key = part:GetAttribute("SiteId") :: string,
		Kind = "Site",
		Zone = part:GetAttribute("ZoneId") :: string,
		Name = (part:GetAttribute("DisplayName") :: string?) or "Excavation Site",
		Position = part.Position,
		RareBoost = (part:GetAttribute("RareBoost") :: number?) or Zones.SiteTypes.DigSite.RareBoost,
		ScrapChance = Zones.SiteTypes.DigSite.ScrapChance,
		Heavy = part:GetAttribute("Heavy") == true,
		Fragile = part:GetAttribute("Fragile") == true,
		MinTool = (part:GetAttribute("MinTool") :: number?) or 1,
		Depth = 1,
		Part = part,
		Cache = nil,
		Special = part:GetAttribute("Special") :: string?,
	}
end

local function offer(player: Player, target: Target)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	if sessions[player] or ChallengeService.IsActive(player) then
		Notifier.Send(player, "Finish what you're doing first.", "Error")
		return
	end
	local kit = kitFor(player)
	if kit.Tier < target.MinTool then
		Notifier.Send(player, ("You need the %s for this dig."):format(Equipment.Get(target.MinTool).Name), "Error")
		return
	end
	if target.Depth > kit.DigDepth then
		Notifier.Send(player, ("Too deep for your kit — the %s can reach it."):format(Equipment.Get(target.Depth == 2 and 2 or 3).Name), "Error")
		return
	end
	local wait = onCooldown(player, target.Key)
	if wait > 0 then
		Notifier.Send(player, ("Already excavated. Try again in %ds."):format(math.ceil(wait)), "Info")
		return
	end
	if target.Special and specials[target.Special] and target.Part then
		local ok, reason = specials[target.Special].Check(player, target.Part)
		if not ok then
			Notifier.Send(player, reason or "You can't dig here yet.", "Error")
			return
		end
	end
	local roll = rollFor(player, target)
	local def = roll.ItemId and ItemCatalog.Get(roll.ItemId)
	if def and not InventoryService.HasSpace(data) then
		Notifier.Send(player, "Your storage is full! Display or sell some items first.", "Error")
		return
	end

	-- What the archaeologist can tell before digging
	local fragility = if def then def.Fragility else 0.3
	local heavy = target.Heavy or (def ~= nil and def.Heavy)
	if heavy and not table.find(kit.ExcavationTools, "Pick") then
		Notifier.Send(player, ("Something heavy is buried here. You'll need the pick from the %s."):format(Equipment.Get(2).Name), "Error")
		return
	end
	local hints = {}
	if heavy then
		table.insert(hints, "Heavy stone — you'll need a Pick.")
	end
	if kit.Tier >= 2 or target.Fragile then
		if fragility >= 0.7 then
			table.insert(hints, "Thin, brittle edges show through the soil: very FRAGILE.")
		elseif fragility >= 0.45 then
			table.insert(hints, "It looks delicate. Take care.")
		else
			table.insert(hints, "Something solid and sturdy.")
		end
	else
		table.insert(hints, "Your basic kit can't tell how fragile it is.")
	end
	if kit.ShowsMaterial and def then
		table.insert(hints, "Material: " .. (MATERIAL_NAMES[def.Material] or def.Material))
	end
	local risk = nil
	if fragility >= 0.7 then
		risk = "A careless dig with a harsh tool can damage it — ordinary finds may even break into fragments."
	elseif def and Rarities.Order(def.Rarity) >= 5 then
		risk = "Your detector is going wild. Whatever this is, it's valuable — dig carefully."
	end

	local tools = {}
	for _, name in kit.ExcavationTools do
		local t = Equipment.ExcavationTools[name]
		table.insert(tools, { Name = name, Description = t.Description, Strokes = t.Strokes })
	end
	local session: Session = { Id = HttpService:GenerateGUID(false), Target = target, Roll = roll, Started = false, Heavy = heavy }
	sessions[player] = session
	Net.Fire("ExcavationOffer", player, {
		SessionId = session.Id,
		SiteName = target.Name,
		Hints = hints,
		Risk = risk,
		Tools = tools,
		Heavy = heavy,
	})
	-- Offer expires if ignored
	task.delay(30, function()
		if sessions[player] == session and not session.Started then
			sessions[player] = nil
		end
	end)
end

local function finishExcavation(player: Player, session: Session, toolName: string, result: ChallengeService.Result)
	sessions[player] = nil
	local target = session.Target
	if result.Cancelled then
		Notifier.Send(player, ("Excavation stopped (%s). The find is still buried here."):format(result.Reason or "cancelled"), "Info")
		return
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	-- Consumed: start cooldown, forget the pending roll.
	setCooldown(player, target.Key, if target.Kind == "Cache" then Config.CacheCooldownSeconds else Config.SiteCooldownSeconds * 1.5)
	if pendingRolls[player] then
		pendingRolls[player][target.Key] = nil
	end
	data.Stats.Searches += 1
	ProgressionService.RecordExcavation(player, target.Zone)
	AchievementService.Award(player, "first_excavation")

	local roll = session.Roll
	local def = roll.ItemId and ItemCatalog.Get(roll.ItemId)
	if not def then
		local text, fragments = DiscoveryService.GrantFalseLead(player, target.Zone, roll.DecoyKind)
		Net.Fire("Discovery", player, { FalseLead = text, ItemId = fragments and fragments.Id, Uid = fragments and fragments.Uid })
		if target.Special and specials[target.Special] and target.Part then
			specials[target.Special].After(player, target.Part, nil, nil)
		end
		return
	end

	-- Recovery quality
	local tool = Equipment.ExcavationTools[toolName]
	local harshPenalty = if tool.Harshness * def.Fragility >= 0.45 then 1 else 0
	local damage = result.Misses + harshPenalty
	local condition = if damage == 0 then "Perfect" elseif damage == 1 then "Clean" else "Damaged"
	local order = Rarities.Order(def.Rarity)
	local itemId = def.Id
	local broken = def.Fragility >= 0.7 and order <= 3 and damage >= result.Presses
	if broken then
		itemId = "historical_fragments"
		condition = "Damaged"
	end
	local zoneName = Zones.ById[target.Zone] and Zones.ById[target.Zone].Name or target.Zone
	local instance, err = InventoryService.Grant(player, itemId, target.Zone, {
		Condition = condition,
		Provenance = ("Excavated at %s on %s"):format(zoneName, os.date("!%Y-%m-%d")),
	})
	if not instance then
		Notifier.Send(player, err or "Couldn't recover the find.", "Error")
		return
	end
	if broken then
		Notifier.Send(player, ("Crack! The %s shattered — you saved the fragments."):format(def.Name), "Error")
	end
	if condition == "Perfect" and not broken then
		data.Stats.PerfectRecoveries += 1
		AchievementService.Award(player, "perfect_recovery")
	end
	if order >= 3 and not broken then
		AchievementService.Award(player, "rare_recovery")
	end
	if target.Kind == "Cache" then
		AchievementService.Award(player, "hidden_cache")
	end
	Net.Fire("Discovery", player, { ItemId = instance.Id, Uid = instance.Uid, Rarity = def.Rarity, Condition = condition })
	if order >= 5 and not broken then
		for _, other in Players:GetPlayers() do
			if other ~= player then
				Notifier.Send(other, ("%s excavated %s (%s)!"):format(player.DisplayName, def.Name, def.Rarity), "Reward")
			end
		end
	end
	if target.Special and specials[target.Special] and target.Part then
		specials[target.Special].After(player, target.Part, instance.Id, condition)
	end
	StateSync.Mark(player)
end

local function chooseTool(player: Player, sessionId: any, toolName: any): (boolean, string?)
	local session = sessions[player]
	if not session or session.Id ~= sessionId or session.Started then
		return false, "That excavation has expired"
	end
	if type(toolName) ~= "string" then
		return false, "Pick a tool"
	end
	local kit = kitFor(player)
	if not table.find(kit.ExcavationTools, toolName) then
		return false, "Your kit doesn't have that tool"
	end
	local target = session.Target
	local hrp = root(player)
	if not hrp or (hrp.Position - target.Position).Magnitude > Config.ExcavationMaxDistance + 4 then
		sessions[player] = nil
		return false, "Walk closer to the dig"
	end
	local def = session.Roll.ItemId and ItemCatalog.Get(session.Roll.ItemId)
	if session.Heavy and toolName ~= "Pick" then
		return false, "The stone seal won't budge — use the Pick."
	end
	local tool = Equipment.ExcavationTools[toolName]
	local fragility = if def then def.Fragility else 0.3
	session.Started = true
	ChallengeService.Begin(player, {
		Kind = "Timing",
		Title = ("Excavating: %s"):format(target.Name),
		Subtitle = ("%s — press when the marker is in the gold zone (%d strokes)"):format(toolName, tool.Strokes),
		Theme = toolName,
		Presses = tool.Strokes,
		Speed = tool.Speed + fragility * 0.1,
		ZoneWidth = math.clamp(tool.ZoneWidth + kit.Precision - fragility * 0.04, 0.08, 0.4),
		MaxSeconds = 5 + tool.Strokes * 3,
		Anchor = target.Position,
		Radius = Config.ExcavationMaxDistance + 4,
	}, function(result)
		finishExcavation(player, session, toolName, result)
	end)
	return true, nil
end

local function digHere(player: Player): (boolean, string?)
	local zoneId = player:GetAttribute("Zone")
	local hrp = root(player)
	if type(zoneId) ~= "string" or not hrp then
		return false, "You can't dig here"
	end
	local best: Secrets.CacheDef? = nil
	local bestDist = math.huge
	for _, cache in Secrets.Caches do
		if cache.Zone == zoneId then
			local d = flatDistance(cache.Position, hrp.Position)
			if d < bestDist then
				best, bestDist = cache, d
			end
		end
	end
	if not best or bestDist > Config.DigHereRadius + 1 then
		return false, "Nothing here. Scan again and follow the signal."
	end
	offer(player, ExcavationService._cacheTarget(best))
	return true, nil
end

-- ── Public API ─────────────────────────────────────────────────────────────
function ExcavationService.RegisterSpecial(name: string, handler: SpecialHandler)
	specials[name] = handler
end

function ExcavationService.HasRevealedHollow(player: Player, hollowId: string): boolean
	local t = hollowRevealed[player] and hollowRevealed[player][hollowId]
	return t ~= nil and t > os.clock()
end

function ExcavationService.Init() end

function ExcavationService.Start()
	Net.Handle("Scan", scan)
	Net.Handle("DigHere", digHere)
	Net.Handle("ChooseExcavationTool", chooseTool)

	local function setup(part: Instance)
		if not part:IsA("BasePart") then
			return
		end
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "ExcavatePrompt"
		prompt.ActionText = "Excavate"
		prompt.ObjectText = (part:GetAttribute("DisplayName") :: string?) or "Excavation Site"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 10
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = part
		prompt.Triggered:Connect(function(player)
			offer(player, siteTarget(part))
		end)
	end
	for _, part in CollectionService:GetTagged("ExcavationSite") do
		setup(part)
	end

	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		pendingRolls[player] = nil
		cooldowns[player] = nil
		lastScan[player] = nil
		hollowRevealed[player] = nil
	end)
end

return ExcavationService
