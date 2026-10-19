--[[
	Config
	Central game settings. Every price, timer and balance number that is not
	tied to one specific item/upgrade lives here, so you can rebalance the game
	without hunting through scripts.

	Used by: server AND client (it contains no secrets).
]]

local Config = {}

-- ── Player start ────────────────────────────────────────────────────────────
Config.StartingCash = 100
-- Item IDs (see ItemCatalog) every brand-new player receives once.
Config.StarterItems = { "clay_pot_cracked", "coin_bronze_worn" }

-- ── Inventory ───────────────────────────────────────────────────────────────
-- Only items in storage (NOT on display) count towards capacity.
Config.BaseInventoryCapacity = 30
Config.InventoryCapacityPerLevel = 10

-- ── Selling to NPC collectors ───────────────────────────────────────────────
-- Players receive this fraction of an item's base value when selling to the
-- museum's NPC buyer. Kept well below 1 so the future player marketplace is
-- always the better deal for valuable items.
Config.NpcSellRate = 0.6

-- ── Museum revenue ──────────────────────────────────────────────────────────
Config.RevenueTickSeconds = 5
-- The ticket desk stores at most this many minutes of income before it is full.
Config.RevenueStorageMinutes = 30
Config.MinimumRevenueStorage = 250
-- The 2nd, 3rd... copy of the SAME item on display earns this fraction.
Config.DuplicateDisplayFactor = 0.5
-- Each different category on display adds this bonus (first one adds nothing).
Config.VarietyBonusPerCategory = 0.08
Config.MaxVarietyBonus = 0.8
-- Each museum level above 1 adds this bonus.
Config.LevelIncomeBonus = 0.1
-- Prestige adds (prestige / PrestigeIncomeDivisor) bonus, capped.
Config.PrestigeIncomeDivisor = 1000
Config.MaxPrestigeIncomeBonus = 0.5

-- ── NPC visitors (visual only — revenue does not depend on them existing) ──
Config.MaxVisitorsPerPlot = 6
Config.VisitorWalkSpeed = 7
Config.VisitorActiveRadius = 260 -- only spawn visitors when a player is this close

-- ── Searching ───────────────────────────────────────────────────────────────
Config.SearchMaxDistance = 14 -- studs between character and search site
Config.SiteCooldownSeconds = 60 -- per player, per site
Config.HiddenSiteCooldownSeconds = 180
Config.ScrapCashMin = 12
Config.ScrapCashMax = 35

-- ── Artefact condition (set by excavation quality) ──────────────────────────
-- Multiplies an item's value and museum income.
Config.Conditions = {
	Perfect = { Multiplier = 1.25, Color = Color3.fromRGB(120, 230, 160), Order = 3 },
	Clean = { Multiplier = 1.0, Color = Color3.fromRGB(220, 215, 200), Order = 2 },
	Damaged = { Multiplier = 0.6, Color = Color3.fromRGB(230, 140, 100), Order = 1 },
}

-- ── Scanner & excavation ────────────────────────────────────────────────────
Config.ScanCooldownSeconds = 1.2
Config.DigHereRadius = 5 -- how close you must stand to a hidden cache to dig
Config.CacheCooldownSeconds = 240 -- per player, per hidden cache
Config.ExcavationMaxDistance = 12
Config.FalseLeadCash = { Min = 15, Max = 45 }
Config.HollowScanRadius = 14 -- scanning this close to a hollow wall reveals it

-- ── Marketplace ─────────────────────────────────────────────────────────────
Config.Market = {
	FeeRate = 0.05, -- taken from the seller on a successful sale (money sink)
	MaxActiveListings = 8,
	MinPriceRate = 0.25, -- min price = item value * this
	MaxPriceRate = 20, -- max price = item value * this
	AbsoluteMaxPrice = 10000000,
	ListingDays = 7,
	BrowsePageSize = 25,
	IndexCacheSeconds = 5,
	SettleIntervalSeconds = 90,
	HistoryLength = 25,
}

-- ── Direct trading ──────────────────────────────────────────────────────────
Config.Trade = {
	MaxItemsPerSide = 8,
	RequestSeconds = 30,
	SessionIdleSeconds = 180,
	MaxDistance = 80, -- players must be reasonably near each other to start
}

-- ── Jail ────────────────────────────────────────────────────────────────────
Config.JailSeconds = 45
Config.JailRadius = 14

-- ── Persistence ─────────────────────────────────────────────────────────────
Config.DataStoreName = "MuseumTycoon_PlayerData_v1" -- unchanged: keeps existing saves
Config.LedgerStoreName = "MuseumTycoon_Ledger_v1"
Config.MarketStoreName = "MuseumTycoon_Market_v1"
Config.MarketIndexName = "MuseumTycoon_ListingIndex_v1"
Config.DataVersion = 2

-- false = no lamps/spotlights inside museums (daylight only). true = restore them.
Config.MuseumLights = false
Config.AutosaveSeconds = 60
-- A session lock older than this is treated as abandoned (crashed server).
Config.SessionLockStaleSeconds = 180

-- ── Plots ───────────────────────────────────────────────────────────────────
Config.PlotCount = 8 -- set "Max Players" in Game Settings to this number

-- ── Remote rate limits (requests per second, burst) ────────────────────────
Config.RemoteRate = 6
Config.RemoteBurst = 10

-- ── Sounds ─────────────────────────────────────────────────────────────────
-- These are sounds that ship with every Roblox client, so they always work.
-- Replace with Creator Store sound IDs ("rbxassetid://123...") whenever you like.
Config.Sounds = {
	Click = "rbxasset://sounds/button.wav",
	Open = "rbxasset://sounds/button.wav", -- swoosh.wav is blocked in some Studio builds
	Search = "rbxasset://sounds/action_footsteps_plastic.mp3",
	Discover = "rbxasset://sounds/electronicpingshort.wav",
	Purchase = "rbxasset://sounds/electronicpingshort.wav",
	Error = "rbxasset://sounds/clickfast.wav",
	Alarm = "rbxasset://sounds/electronicpingshort.wav",
	Hit = "rbxasset://sounds/button.wav",
	Miss = "rbxasset://sounds/clickfast.wav",
	Scan = "rbxasset://sounds/electronicpingshort.wav",
	Water = "rbxasset://sounds/impact_water.mp3",
	-- Optional ambience loops: paste Creator Store sound ids here (leave "" for none).
	RuinsAmbience = "",
	JungleAmbience = "",
}

return Config
