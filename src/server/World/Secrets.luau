--[[
	Secrets (SERVER ONLY)
	Data that must never reach clients: hidden cache positions and puzzle
	answers. This module lives in ServerScriptService, which exploiters can't
	read. Clues placed in the world only HINT at these.

	World builders call Secrets.AddCache while placing the visible clue.
]]

local Secrets = {}

export type CacheDef = {
	Id: string,
	Zone: string,
	Position: Vector3, -- world position at ground level
	Depth: number, -- 1 shallow, 2 medium, 3 deep (needs kit DigDepth >= Depth)
	Decoy: boolean, -- false lead (mineral deposit / empty pocket)
	DecoyKind: string?, -- "Mineral" | "Empty"
	RareBoost: number,
	Name: string,
}

Secrets.Caches = {} :: { CacheDef }
Secrets.CacheById = {} :: { [string]: CacheDef }

-- Hollow walls that the scanner can reveal (Jungle Root Chamber).
export type HollowDef = { Id: string, Zone: string, Position: Vector3, Part: BasePart? }
Secrets.Hollows = {} :: { HollowDef }

function Secrets.AddCache(def: CacheDef)
	assert(Secrets.CacheById[def.Id] == nil, "Duplicate cache id " .. def.Id)
	table.insert(Secrets.Caches, def)
	Secrets.CacheById[def.Id] = def
end

function Secrets.AddHollow(def: HollowDef)
	table.insert(Secrets.Hollows, def)
end

-- Puzzle answers ------------------------------------------------------------
-- Forgotten Ruins: the Watchers rose in this order (also in Shared/Zones for
-- the plates, which is fine: the riddle is in *finding* the order).
-- Jungle Temple: which symbol each guardian pillar must show.
Secrets.JunglePillars = {
	{ Id = "Dawn", Clue = "The guardian of DAWN looks upon the SERPENT, who sheds the night like old skin.", Answer = "Serpent" },
	{ Id = "Dusk", Clue = "The guardian of DUSK keeps the JAGUAR, hunter of the falling light.", Answer = "Jaguar" },
	{ Id = "Rain", Clue = "The guardian of RAIN follows the MONKEY, who laughs in the storm-wet canopy.", Answer = "Monkey" },
	{ Id = "Root", Clue = "The guardian of ROOTS bows to the EAGLE, whose shadow reaches the deepest soil.", Answer = "Eagle" },
}
-- The sanctum floor stone that hides the Sun Disk lies before this statue.
Secrets.HeartStatue = "Eagle"

return Secrets
