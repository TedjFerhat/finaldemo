--[[
	Zones
	Exploration zones and the kinds of search sites inside them.

	Two styles of discovery:
	  • Quick sites (Rubble, Urn, Chest, Hidden) — press E, short timed search.
	    Kept quick on purpose so common finds stay accessible.
	  • Excavations (DigSite = visible dig site, Cache = hidden, scanner only) —
	    choose a tool, then a skill-based excavation that decides the
	    artefact's condition.

	Secret positions (hidden caches, puzzle answers) are NOT stored here,
	because ReplicatedStorage can be read by exploiters. They live on the
	server in ServerScriptService/Server/World.
]]

export type SiteType = {
	Id: string,
	Name: string,
	ActionText: string,
	RareBoost: number, -- multiplies the weight of Rare and better results
	DurationMultiplier: number,
	ScrapChance: number, -- chance the search is a false lead (scrap/fragments)
	Hidden: boolean?, -- uses the longer hidden cooldown
	Excavation: boolean?, -- uses the excavation challenge instead of a timer
}

export type ZoneDef = {
	Id: string,
	Name: string,
	Description: string,
	RequiredLevel: number,
	Built: boolean,
	Order: number,
}

local Zones = {}

Zones.SiteTypes = {
	DigSite = { Id = "DigSite", Name = "Excavation Site", ActionText = "Excavate", RareBoost = 1.1, DurationMultiplier = 1, ScrapChance = 0.15, Excavation = true },
	Cache = { Id = "Cache", Name = "Buried Cache", ActionText = "Dig Here", RareBoost = 2.0, DurationMultiplier = 1, ScrapChance = 0.12, Excavation = true },
	Rubble = { Id = "Rubble", Name = "Collapsed Rubble", ActionText = "Search", RareBoost = 0.9, DurationMultiplier = 1.0, ScrapChance = 0.2 },
	Urn = { Id = "Urn", Name = "Sealed Urn", ActionText = "Open", RareBoost = 1.15, DurationMultiplier = 0.8, ScrapChance = 0.18 },
	Chest = { Id = "Chest", Name = "Ancient Chest", ActionText = "Unlock", RareBoost = 1.5, DurationMultiplier = 1.0, ScrapChance = 0.08 },
	Hidden = { Id = "Hidden", Name = "Hidden Alcove", ActionText = "Search", RareBoost = 2.6, DurationMultiplier = 1.0, ScrapChance = 0.0, Hidden = true },
} :: { [string]: SiteType }

Zones.List = {
	{ Id = "ForgottenRuins", Name = "Forgotten Ruins", Description = "Sun-bleached ruins, a sunken temple, a colossus and a cave full of secrets.", RequiredLevel = 1, Built = true, Order = 1 },
	{ Id = "JungleTemple", Name = "Jungle Temple Ruins", Description = "A temple swallowed by the jungle. Guardians, a waterfall, and a heart that sleeps.", RequiredLevel = 3, Built = true, Order = 2 },
} :: { ZoneDef }

Zones.ById = {} :: { [string]: ZoneDef }
for _, z in Zones.List do
	Zones.ById[z.Id] = z
end

-- Forgotten Ruins glyph puzzle: the order is learned from the three Watcher
-- statues (their inscriptions say first / second / third).
Zones.RuinsGlyphOrder = { "Sun", "Moon", "Star" }
Zones.RuinsSecretDoorOpenSeconds = 45

-- Jungle Temple guardian pillars
Zones.JungleSymbols = { "Jaguar", "Serpent", "Eagle", "Monkey" }
Zones.JungleDoorOpenSeconds = 60

return Zones
