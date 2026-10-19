--[[
	PuzzleService
	Clue chains and puzzles. All state lives on the server; clients only press
	prompts and step on plates.

	Forgotten Ruins
	  • Three Watcher statues each carry part of a riddle (journal clues).
	  • Glyph plates in front of the temple: step in the Watchers' order to
	    open the secret door.

	Jungle Temple
	  • Four steles hidden around the map say which beast each Guardian Pillar
	    serves. Turn the pillars to match › the sanctum door opens.
	  • A cracked, root-covered wall: scan it to detect the hollow behind it,
	    then break through with a pick › the Root Chamber.
	  • The sanctum: four sealed floor stones. A plaque in the Root Chamber
	    says which one hides the heart. Wrong stones are decoys and lock the
	    sanctum for you for a while — so it pays to find the clue first.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Zones = require(Shared.Zones)
local Equipment = require(Shared.Equipment)

local PlayerDataService = require(script.Parent.PlayerDataService)
local ProgressionService = require(script.Parent.ProgressionService)
local AchievementService = require(script.Parent.AchievementService)
local ChallengeService = require(script.Parent.ChallengeService)
local ExcavationService = require(script.Parent.ExcavationService)
local DiscoveryService = require(script.Parent.DiscoveryService)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local Secrets = require(script.Parent.Parent.World.Secrets)

local PuzzleService = {}

local function playerFromHit(hit: BasePart): Player?
	local model = hit:FindFirstAncestorOfClass("Model")
	return model and Players:GetPlayerFromCharacter(model)
end

local function rootOf(player: Player): BasePart?
	local character = player.Character
	local hrp = character and character:FindFirstChild("HumanoidRootPart")
	return if hrp and hrp:IsA("BasePart") then hrp else nil
end

local function playersNear(position: Vector3, radius: number): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		local hrp = rootOf(p)
		if hrp and (hrp.Position - position).Magnitude <= radius then
			table.insert(list, p)
		end
	end
	return list
end

local function prompt(parent: BasePart, action: string, object: string, distance: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = 0
	p.MaxActivationDistance = distance or 10
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = parent
	return p
end

-- ── Inscriptions › journal clues ───────────────────────────────────────────
local function setupInscription(part: BasePart)
	local clueId = part:GetAttribute("ClueId") :: string
	local title = (part:GetAttribute("ClueTitle") :: string?) or "Inscription"
	local text = (part:GetAttribute("ClueText") :: string?) or ""
	local p = prompt(part, "Read", title, 12)
	p.Triggered:Connect(function(player)
		ProgressionService.RecordClue(player, clueId, title .. ": " .. text)
		Notifier.Send(player, title .. "\n" .. text, "Clue")
	end)
end

-- ── Forgotten Ruins: glyph plates ──────────────────────────────────────────
local glyphProgress: { [Player]: { string } } = {}
local lastGlyph: { [Player]: { Glyph: string, Time: number } } = {}
local secretDoorUntil = 0

local function openSecretDoor()
	local door = CollectionService:GetTagged("SecretDoor")[1]
	if not door or not door:IsA("BasePart") then
		return
	end
	secretDoorUntil = os.clock() + Zones.RuinsSecretDoorOpenSeconds
	door.CanCollide = false
	door.Transparency = 0.85
	for _, p in playersNear(door.Position, 90) do
		ProgressionService.RecordPuzzle(p, "ruins_glyphs")
		AchievementService.Award(p, "ruins_secret")
	end
	task.delay(Zones.RuinsSecretDoorOpenSeconds + 0.1, function()
		if os.clock() >= secretDoorUntil then
			door.CanCollide = true
			door.Transparency = 0
		end
	end)
end

local glyphMisses: { [Player]: number } = {}
local litPlates: { [BasePart]: number } = {}

-- Where each Watcher stands (used for friendly hints after mistakes).
local WATCHER_HINT = {
	Sun = "the SUN Watcher stands by the fallen Colossus",
	Moon = "the MOON Watcher stands at the canyon mouth",
	Star = "the STAR Watcher waits on the high rocks to the north-west",
}

local function lightPlate(plate: BasePart, seconds: number)
	local token = os.clock()
	litPlates[plate] = token
	if not plate:GetAttribute("BaseMaterial") then
		plate:SetAttribute("BaseMaterial", plate.Material.Name)
	end
	plate.Material = Enum.Material.Neon
	task.delay(seconds, function()
		if litPlates[plate] == token then
			litPlates[plate] = nil
			plate.Material = (Enum.Material :: any)[plate:GetAttribute("BaseMaterial") :: string] or Enum.Material.Slate
		end
	end)
end

local function progressLine(order: { string }, count: number): string
	local bits = {}
	for i, g in order do
		table.insert(bits, if i <= count then string.upper(g) .. " ★" else "?")
	end
	return table.concat(bits, "  ›  ")
end

-- Ruins glyph plates. Forgiving version: a wrong plate never wipes your
-- progress, lit plates stay lit while you work, and after two mistakes the
-- game tells you which Watcher to read for the next step.
local function onGlyph(plate: BasePart, hit: BasePart)
	local player = playerFromHit(hit)
	if not player then
		return
	end
	local glyph = plate:GetAttribute("Glyph") :: string
	local last = lastGlyph[player]
	if last and last.Glyph == glyph and os.clock() - last.Time < 2 then
		return
	end
	lastGlyph[player] = { Glyph = glyph, Time = os.clock() }
	local order = Zones.RuinsGlyphOrder
	local progress = glyphProgress[player] or {}
	if table.find(progress, glyph) then
		return -- already done this step; standing on it again is harmless
	end
	local expected = order[#progress + 1]
	if glyph == expected then
		table.insert(progress, glyph)
		glyphMisses[player] = 0
		lightPlate(plate, 30)
		if #progress == #order then
			glyphProgress[player] = {}
			openSecretDoor()
			Notifier.Send(player, "All three glyphs blaze with light — the temple's secret door is open!", "Reward")
		else
			glyphProgress[player] = progress
			Notifier.Send(player, "The glyph glows!  " .. progressLine(order, #progress), "Success")
		end
	else
		local misses = (glyphMisses[player] or 0) + 1
		glyphMisses[player] = misses
		glyphProgress[player] = progress
		if misses >= 2 then
			Notifier.Send(player, ("Not yet. Hint: %s — read its words."):format(WATCHER_HINT[expected] or "find the Watchers"), "Info")
		else
			Notifier.Send(player, "The glyph stays dark... it isn't this one's turn yet.  " .. progressLine(order, #progress), "Info")
		end
	end
end

-- ── Jungle: Guardian Pillars ───────────────────────────────────────────────
local pillarState: { [string]: number } = {}
local pillarHeads: { [string]: BasePart } = {}
local sanctumOpenUntil = 0
local sanctumAccess: { [Player]: boolean } = {}
local lastTurn: { [string]: number } = {}

local function symbolOf(pillarId: string): string
	return Zones.JungleSymbols[pillarState[pillarId] or 1]
end

local function answerOf(pillarId: string): string?
	for _, def in Secrets.JunglePillars do
		if def.Id == pillarId then
			return def.Answer
		end
	end
	return nil
end

local function refreshPillar(pillarId: string)
	local head = pillarHeads[pillarId]
	if not head then
		return
	end
	-- Instant feedback: a pillar showing the right animal glows green.
	local correct = symbolOf(pillarId) == answerOf(pillarId)
	if not head:GetAttribute("BaseColor") then
		head:SetAttribute("BaseColor", head.Color)
	end
	head.Color = if correct then Color3.fromRGB(120, 200, 120) else head:GetAttribute("BaseColor") :: Color3
	local glow = head:FindFirstChild("AlignedGlow") :: PointLight?
	if not glow then
		local light = Instance.new("PointLight")
		light.Name = "AlignedGlow"
		light.Color = Color3.fromRGB(140, 255, 150)
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = head
		glow = light
	end
	if glow then
		glow.Enabled = correct
	end
	for _, gui in head:GetChildren() do
		local label = gui:IsA("SurfaceGui") and gui:FindFirstChild("Symbol")
		if label and label:IsA("TextLabel") then
			label.Text = string.upper(symbolOf(pillarId))
		end
	end
end

local function solved(): boolean
	for _, def in Secrets.JunglePillars do
		if symbolOf(def.Id) ~= def.Answer then
			return false
		end
	end
	return true
end

local function scramble()
	local rng = Random.new()
	repeat
		for _, def in Secrets.JunglePillars do
			pillarState[def.Id] = rng:NextInteger(1, #Zones.JungleSymbols)
		end
	until not solved()
	for id in pillarHeads do
		refreshPillar(id)
	end
end

local function sanctumDoor(): BasePart?
	local d = CollectionService:GetTagged("SanctumDoor")[1]
	return if d and d:IsA("BasePart") then d else nil
end

local function insideSanctum(player: Player): boolean
	local bounds = CollectionService:GetTagged("SanctumBounds")[1]
	local hrp = rootOf(player)
	if not bounds or not bounds:IsA("BasePart") or not hrp then
		return false
	end
	local rel = bounds.CFrame:PointToObjectSpace(hrp.Position)
	local half = bounds.Size / 2
	return math.abs(rel.X) <= half.X and math.abs(rel.Y) <= half.Y + 2 and math.abs(rel.Z) <= half.Z
end

local function openSanctum()
	local door = sanctumDoor()
	if not door then
		return
	end
	sanctumOpenUntil = os.clock() + Zones.JungleDoorOpenSeconds
	door.CanCollide = false
	door.Transparency = 0.85
	for _, p in playersNear(door.Position, 120) do
		ProgressionService.RecordPuzzle(p, "jungle_guardians")
		AchievementService.Award(p, "jungle_guardians")
		Notifier.Send(p, "The Guardians are aligned. Stone grinds on stone... the sanctum is open!", "Reward")
	end
	task.delay(Zones.JungleDoorOpenSeconds + 0.1, function()
		if os.clock() >= sanctumOpenUntil then
			door.CanCollide = true
			door.Transparency = 0
			scramble()
		end
	end)
end

local function turnPillar(player: Player, pillarId: string)
	if os.clock() < sanctumOpenUntil then
		Notifier.Send(player, "The Guardians are locked in place while the sanctum is open.", "Info")
		return
	end
	if (lastTurn[pillarId] or 0) + 0.4 > os.clock() then
		return
	end
	lastTurn[pillarId] = os.clock()
	pillarState[pillarId] = (pillarState[pillarId] or 1) % #Zones.JungleSymbols + 1
	refreshPillar(pillarId)
	if solved() then
		openSanctum()
	else
		local aligned = 0
		for _, def in Secrets.JunglePillars do
			if symbolOf(def.Id) == def.Answer then
				aligned += 1
			end
		end
		local mine = if symbolOf(pillarId) == answerOf(pillarId) then "This guardian glows — it's right! " else ""
		Notifier.Send(player, ("%s%d/%d guardians aligned."):format(mine, aligned, #Secrets.JunglePillars), if mine ~= "" then "Success" else "Info")
	end
end

-- ── Jungle: the hollow wall › Root Chamber ─────────────────────────────────
local hollowOpenUntil: { [string]: number } = {}

local function breakHollow(player: Player, wall: BasePart)
	local hollowId = wall:GetAttribute("HollowId") :: string
	if (hollowOpenUntil[hollowId] or 0) > os.clock() then
		return
	end
	if not ExcavationService.HasRevealedHollow(player, hollowId) then
		Notifier.Send(player, "Just an old wall covered in roots... or is it? Use your SCANNER here (Expedition panel › Scan) to check for a hollow space.", "Info")
		return
	end
	local data = PlayerDataService.GetData(player)
	local kit = Equipment.Get(if data then data.ToolTier else 1)
	if not table.find(kit.ExcavationTools, "Pick") then
		Notifier.Send(player, ("There's a hollow space behind this wall, but you need the pick from the %s."):format(Equipment.Get(2).Name), "Error")
		return
	end
	if ChallengeService.IsActive(player) then
		return
	end
	ChallengeService.Begin(player, {
		Kind = "Timing",
		Title = "Breaking through the cracked wall",
		Subtitle = "Strike the weak points (3 strikes)",
		Theme = "Pick",
		Presses = 3,
		Speed = 0.5,
		ZoneWidth = 0.3,
		MaxMisses = 3,
		MaxSeconds = 15,
		Anchor = wall.Position,
		Radius = 14,
	}, function(result)
		if result.Cancelled then
			return
		end
		if not result.Success then
			Notifier.Send(player, "The wall cracks but holds. Try again.", "Error")
			return
		end
		hollowOpenUntil[hollowId] = os.clock() + 90
		wall.CanCollide = false
		wall.Transparency = 1
		ProgressionService.RecordPuzzle(player, "jungle_root_chamber")
		AchievementService.Award(player, "root_chamber")
		Notifier.Send(player, "The wall collapses — a hidden chamber, choked with roots!", "Reward")
		task.delay(90, function()
			-- Reseal (but never trap anyone: wait until the doorway is clear)
			while #playersNear(wall.Position, 4) > 0 do
				task.wait(2)
			end
			wall.CanCollide = true
			wall.Transparency = 0
		end)
	end)
end

-- ── Jungle: sanctum floor stones (special excavation) ──────────────────────
local altarLock: { [Player]: number } = {}

local function setupSanctumStones()
	ExcavationService.RegisterSpecial("SanctumStone", {
		Check = function(player: Player, _part: BasePart): (boolean, string?)
			if not sanctumAccess[player] and not insideSanctum(player) then
				return false, "You shouldn't be here..."
			end
			sanctumAccess[player] = true
			local lockedFor = (altarLock[player] or 0) - os.clock()
			if lockedFor > 0 then
				return false, ("The sanctum stones won't move for you. Return in %d min."):format(math.ceil(lockedFor / 60))
			end
			return true, nil
		end,
		Roll = function(_player: Player, part: BasePart)
			if part:GetAttribute("Animal") == Secrets.HeartStatue then
				if math.random() < 0.4 then
					return { ItemId = "jg_sun_disk", DecoyKind = nil }
				end
				return { ItemId = DiscoveryService.RollWith("JungleTemple", 3, 1, 0, 4) or "jg_mosaic_mask", DecoyKind = nil }
			end
			return { ItemId = nil, DecoyKind = "Empty" }
		end,
		After = function(player: Player, part: BasePart, itemId: string?, _condition: string?)
			if part:GetAttribute("Animal") == Secrets.HeartStatue then
				altarLock[player] = os.clock() + 15 * 60
				if itemId == "jg_sun_disk" then
					AchievementService.Award(player, "jaguar_heart")
				end
			else
				altarLock[player] = os.clock() + 2 * 60
				ProgressionService.RecordClue(player, "jungle_decoy", "Sanctum decoy: \"Not here. The heart sleeps elsewhere.\"")
				Notifier.Send(player, "A decoy! Hint: the heart sleeps beneath the gaze of the one whose shadow reaches the deepest soil. Try again in 2 minutes.", "Error")
			end
		end,
	})
end

function PuzzleService.Init() end

function PuzzleService.Start()
	for _, part in CollectionService:GetTagged("Inscription") do
		if part:IsA("BasePart") then
			setupInscription(part)
		end
	end
	for _, plate in CollectionService:GetTagged("GlyphPlate") do
		if plate:IsA("BasePart") then
			plate.Touched:Connect(function(hit)
				onGlyph(plate, hit)
			end)
		end
	end
	for _, exitPad in CollectionService:GetTagged("ChamberExit") do
		if exitPad:IsA("BasePart") then
			exitPad.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				local target = exitPad:GetAttribute("ExitTo")
				if player and player.Character and typeof(target) == "CFrame" then
					player.Character:PivotTo(target)
				end
			end)
		end
	end
	for _, head in CollectionService:GetTagged("GuardianPillar") do
		if head:IsA("BasePart") then
			local id = head:GetAttribute("PillarId") :: string
			pillarHeads[id] = head
			local p = prompt(head, "Turn Guardian", id .. " Guardian", 14)
			p.Triggered:Connect(function(player)
				turnPillar(player, id)
			end)
		end
	end
	scramble()
	for _, wall in CollectionService:GetTagged("HollowWall") do
		if wall:IsA("BasePart") then
			local p = prompt(wall, "Inspect / Break", "Cracked wall", 10)
			p.Triggered:Connect(function(player)
				breakHollow(player, wall)
			end)
		end
	end
	for _, trigger in CollectionService:GetTagged("SanctumTrigger") do
		if trigger:IsA("BasePart") then
			trigger.Touched:Connect(function(hit)
				local player = playerFromHit(hit)
				if player and os.clock() < sanctumOpenUntil then
					sanctumAccess[player] = true
				end
			end)
		end
	end
	setupSanctumStones()

	-- Leaving the zone ends sanctum access
	local function watch(player: Player)
		player:GetAttributeChangedSignal("Zone"):Connect(function()
			if player:GetAttribute("Zone") ~= "JungleTemple" then
				sanctumAccess[player] = nil
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		glyphProgress[player] = nil
		lastGlyph[player] = nil
		sanctumAccess[player] = nil
		altarLock[player] = nil
	end)
end

return PuzzleService
