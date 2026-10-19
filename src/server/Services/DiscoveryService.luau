--[[
	DiscoveryService
	Searching and treasure rolls. 100% server-controlled:
	  • the client only presses a ProximityPrompt
	  • the server checks distance, cooldowns, storage space and equipment
	  • the server times the search, then checks the player is STILL nearby
	  • the server rolls the reward with configurable weights

	Every search gives something: an artefact (journal progress, income, sale
	value) or, sometimes, scrap cash.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Zones = require(Shared.Zones)
local Rarities = require(Shared.Rarities)
local ItemCatalog = require(Shared.ItemCatalog)
local Equipment = require(Shared.Equipment)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local InventoryService = require(script.Parent.InventoryService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)
local Notifier = require(script.Parent.Parent.Util.Notifier)

local DiscoveryService = {}

type Session = { SiteId: string, Token: number }

local sessions: { [Player]: Session } = {}
local cooldowns: { [Player]: { [string]: number } } = {}
local sites: { [string]: BasePart } = {}
local tokenCounter = 0
local rng = Random.new()

local function characterRoot(player: Player): BasePart?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if humanoid and humanoid.Health > 0 and root and root:IsA("BasePart") then
		return root
	end
	return nil
end

local function isNear(player: Player, site: BasePart): boolean
	local root = characterRoot(player)
	if not root then
		return false
	end
	-- Distance to the closest point of the site's bounding box (works for big parts).
	local rel = site.CFrame:PointToObjectSpace(root.Position)
	local half = site.Size / 2
	local closest = Vector3.new(math.clamp(rel.X, -half.X, half.X), math.clamp(rel.Y, -half.Y, half.Y), math.clamp(rel.Z, -half.Z, half.Z))
	return (rel - closest).Magnitude <= Config.SearchMaxDistance
end

-- ── The loot roll ──────────────────────────────────────────────────────────
-- Generic weighted roll. Returns an item id, or nil for a false lead.
-- minOrder forces at least that rarity order (e.g. 4 = Epic or better).
function DiscoveryService.RollWith(zoneId: string, rareBoost: number, luck: number, scrapChance: number, minOrder: number?): string?
	if rng:NextNumber() < scrapChance then
		return nil
	end
	local pool = ItemCatalog.ForZone(zoneId)
	-- Group the zone's items by rarity
	local byRarity: { [string]: { string } } = {}
	for _, def in pool do
		byRarity[def.Rarity] = byRarity[def.Rarity] or {}
		table.insert(byRarity[def.Rarity], def.Id)
	end
	-- Weighted rarity pick; better sites/tools boost Rare and above.
	local total = 0
	local weights: { { Rarity: string, Weight: number } } = {}
	for _, rarity in Rarities.List do
		if byRarity[rarity.Id] and rarity.Order >= (minOrder or 1) then
			local w = rarity.Weight
			if rarity.Order >= 3 then
				w *= rareBoost * luck
			end
			total += w
			table.insert(weights, { Rarity = rarity.Id, Weight = w })
		end
	end
	if total <= 0 then
		return nil
	end
	local pick = rng:NextNumber() * total
	local chosen = weights[#weights].Rarity
	for _, entry in weights do
		pick -= entry.Weight
		if pick <= 0 then
			chosen = entry.Rarity
			break
		end
	end
	local options = byRarity[chosen]
	return options[rng:NextInteger(1, #options)]
end

function DiscoveryService.Roll(zoneId: string, siteType: Zones.SiteType, toolTier: number): string?
	return DiscoveryService.RollWith(zoneId, siteType.RareBoost, Equipment.Get(toolTier).Luck, siteType.ScrapChance)
end

-- A false lead still pays a little: fragments for the journal or scrap cash.
-- Returns a short description for the player.
function DiscoveryService.GrantFalseLead(player: Player, zoneId: string, kind: string?): (string, any?)
	local data = PlayerDataService.GetData(player)
	if data and rng:NextNumber() < 0.5 and InventoryService.HasSpace(data) then
		local instance = InventoryService.Grant(player, "historical_fragments", zoneId, { Condition = "Damaged", Provenance = "Picked from a false lead" })
		if instance then
			return "Only broken fragments... but scholars still pay for those.", instance
		end
	end
	local scrap = rng:NextInteger(Config.FalseLeadCash.Min, Config.FalseLeadCash.Max)
	EconomyService.Add(player, scrap, "FalseLead")
	local text = if kind == "Mineral"
		then ("Just a mineral deposit. You chip off a few crystals worth %s."):format(Format.Cash(scrap))
		elseif kind == "Empty" then ("An empty pocket in the earth. A few old coins worth %s lie at the bottom."):format(Format.Cash(scrap))
		else ("Just some old scrap... sold it for %s."):format(Format.Cash(scrap))
	return text, nil
end

-- ── Search flow ────────────────────────────────────────────────────────────
local function finishSearch(player: Player, token: number)
	local session = sessions[player]
	if not session or session.Token ~= token then
		return -- cancelled or replaced
	end
	sessions[player] = nil
	local site = sites[session.SiteId]
	local data = PlayerDataService.GetData(player)
	if not site or not data then
		return
	end
	if not isNear(player, site) then
		Net.Fire("SearchEnded", player, { Success = false, Reason = "You moved too far away." })
		return
	end

	local siteType = Zones.SiteTypes[site:GetAttribute("SiteType") :: string]
	local zoneId = site:GetAttribute("ZoneId") :: string
	cooldowns[player] = cooldowns[player] or {}
	cooldowns[player][session.SiteId] = os.clock() + (if siteType.Hidden then Config.HiddenSiteCooldownSeconds else Config.SiteCooldownSeconds)
	data.Stats.Searches += 1

	local itemId = DiscoveryService.Roll(zoneId, siteType, data.ToolTier)
	if itemId then
		local instance, err = InventoryService.Grant(player, itemId, zoneId, { Condition = "Clean", Provenance = ("Found in a %s, %s"):format(siteType.Name:lower(), os.date("!%Y-%m-%d")) })
		if instance then
			local def = ItemCatalog.Get(itemId)
			Net.Fire("SearchEnded", player, { Success = true })
			Net.Fire("Discovery", player, { ItemId = itemId, Uid = instance.Uid, Rarity = def and def.Rarity })
			if def and Rarities.Order(def.Rarity) >= 5 then
				-- Server-wide announcement for Legendary/Mythic finds
				for _, other in Players:GetPlayers() do
					if other ~= player then
						Notifier.Send(other, ("%s discovered %s (%s)!"):format(player.DisplayName, def.Name, def.Rarity), "Reward")
					end
				end
			end
			StateSync.Mark(player)
			return
		end
		Net.Fire("SearchEnded", player, { Success = false, Reason = err or "Couldn't collect the item." })
		return
	end

	local text, fragments = DiscoveryService.GrantFalseLead(player, zoneId, nil)
	Net.Fire("SearchEnded", player, { Success = true })
	Net.Fire("Discovery", player, { FalseLead = text, ItemId = fragments and fragments.Id, Uid = fragments and fragments.Uid })
	StateSync.Mark(player)
end

local function startSearch(player: Player, site: BasePart)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	local siteId = site:GetAttribute("SiteId") :: string
	local siteType = Zones.SiteTypes[site:GetAttribute("SiteType") :: string]
	if not siteType then
		return
	end
	if sessions[player] then
		Notifier.Send(player, "You're already searching!", "Error")
		return
	end
	local minTool = (site:GetAttribute("MinTool") :: number?) or 1
	if data.ToolTier < minTool then
		Notifier.Send(player, ("You need a %s to dig here."):format(Equipment.Get(minTool).Name), "Error")
		return
	end
	local readyAt = cooldowns[player] and cooldowns[player][siteId]
	if readyAt and readyAt > os.clock() then
		Notifier.Send(player, ("You've already searched here. Come back in %s."):format(Format.Seconds(readyAt - os.clock())), "Info")
		return
	end
	if not InventoryService.HasSpace(data) then
		Notifier.Send(player, "Your storage is full! Display or sell some items first.", "Error")
		return
	end
	if not isNear(player, site) then
		return
	end

	local duration = Equipment.Get(data.ToolTier).SearchSeconds * siteType.DurationMultiplier
	tokenCounter += 1
	local token = tokenCounter
	sessions[player] = { SiteId = siteId, Token = token }

	local name = (site:GetAttribute("DisplayName") :: string?) or siteType.Name
	Net.Fire("SearchStarted", player, { SiteName = name, Duration = duration, SitePosition = site.Position })

	-- Dust effect at the site while searching
	local dust = site:FindFirstChild("SearchDust") :: ParticleEmitter?
	if dust then
		dust.Enabled = true
		task.delay(duration, function()
			dust.Enabled = false
		end)
	end

	task.delay(duration, finishSearch, player, token)
end

local function setupSite(site: BasePart)
	local siteId = site:GetAttribute("SiteId")
	local siteTypeId = site:GetAttribute("SiteType")
	if type(siteId) ~= "string" or type(siteTypeId) ~= "string" or not Zones.SiteTypes[siteTypeId] then
		warn("[Discovery] Ignoring badly configured search site: " .. site:GetFullName())
		return
	end
	sites[siteId] = site
	local siteType = Zones.SiteTypes[siteTypeId]

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "SearchPrompt"
	prompt.ActionText = siteType.ActionText
	prompt.ObjectText = (site:GetAttribute("DisplayName") :: string?) or siteType.Name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = site
	prompt.Triggered:Connect(function(player)
		startSearch(player, site)
	end)

	local dust = Instance.new("ParticleEmitter")
	dust.Name = "SearchDust"
	dust.Enabled = false
	dust.Color = ColorSequence.new(Color3.fromRGB(200, 170, 120))
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.6, 1.2)
	dust.Rate = 25
	dust.Speed = NumberRange.new(3, 6)
	dust.SpreadAngle = Vector2.new(60, 60)
	dust.Acceleration = Vector3.new(0, -6, 0)
	dust.Parent = site
end

-- Cancels a search in progress (e.g. when the player teleports away).
function DiscoveryService.Cancel(player: Player)
	if sessions[player] then
		sessions[player] = nil
		Net.Fire("SearchEnded", player, { Success = false, Reason = "Search cancelled." })
	end
end

function DiscoveryService.Init() end

function DiscoveryService.Start()
	for _, site in CollectionService:GetTagged("SearchSite") do
		if site:IsA("BasePart") then
			setupSite(site)
		end
	end
	Players.PlayerRemoving:Connect(function(player)
		sessions[player] = nil
		cooldowns[player] = nil
	end)
end

return DiscoveryService
