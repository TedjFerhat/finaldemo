--[[
	Upgrades
	Museum construction progression. Each upgrade:
	  • costs cash, may require other upgrades first
	  • builds visible geometry (see server/World/MuseumBuilder — same Id)
	  • may add display slots, raise the museum level, or add an income bonus

	Coordinates are in PLOT SPACE (studs): X = left/right, Z = front(-)/back(+).
	Upgrade pads stand in two tidy rows on the side lawns (x = ±57) so the
	landscaped front garden stays clear.
	The museum entrance faces -Z. Slot "Face" is the direction the exhibit
	faces, in degrees (0 = towards the entrance / -Z).
]]

export type SlotDef = {
	Id: string,
	Type: string, -- Pedestal | Case | Wall | Platform | Vault
	Room: string,
	X: number,
	Z: number,
	Face: number,
	Y: number?, -- height of the floor the fixture stands on (upper floor slots)
}

export type UpgradeDef = {
	Id: string,
	Name: string,
	Description: string,
	Cost: number,
	Requires: { string },
	GrantsLevel: number?,
	IncomeBonus: number?,
	EnablesSecurity: boolean?,
	Slots: { SlotDef },
	Pad: { X: number, Z: number },
	Order: number,
}

local function S(id: string, slotType: string, room: string, x: number, z: number, face: number?, y: number?): SlotDef
	return { Id = id, Type = slotType, Room = room, X = x, Z = z, Face = face or 0, Y = y }
end


local Upgrades = {}

Upgrades.LevelNames = {
	[1] = "Small Collector's Museum",
	[2] = "Expanded Exhibition Hall",
	[3] = "Natural History Museum",
	[4] = "Historical Museum",
	[5] = "Grand Art Gallery",
	[6] = "World-Class Treasure Museum",
}
Upgrades.MaxLevel = 6

-- The free starting building every player owns.
Upgrades.BaseSlots = {
	S("H1", "Pedestal", "Hall", -8, 10), -- either side of the rotunda centrepiece, mid-hall
	S("H2", "Pedestal", "Hall", 8, 10),
	S("H3", "Case", "Hall", -14.5, 1), -- west aisle, by the security terminal
}

-- Visitor walking routes (plot space). Points are { x, z } or { x, z, elevation }
-- (elevation 10 = the upper floor). [1..2] are outside/doorway; from [3] on
-- the route leads from the entrance hall into the room. They go round the
-- rotunda, along the aisles, under the rear bridge and up the stairs.
local HALL = { { 0, -22 }, { 0, -10 }, { 0, -6.5 } }
local function route(...: { number }): { { number } }
	local r = table.clone(HALL)
	for _, p in { ... } do
		table.insert(r, p)
	end
	return r
end
Upgrades.RoomPaths = {
	Hall = route(),
	AisleW = route({ -12, -5.5 }, { -12, 12 }),
	AisleE = route({ 12, -5.5 }, { 12, 12 }),
	East = route({ 12, -5.5 }, { 12, 10 }, { 22, 10 }, { 35, 10 }),
	Fossil = route({ 12, -5.5 }, { 12, 10 }, { 22, 10 }, { 35, 12 }, { 35, 25 }, { 36, 36 }),
	West = route({ -12, -5.5 }, { -12, 10 }, { -22, 10 }, { -35, 10 }),
	Vault = route({ -12, -5.5 }, { -12, 10 }, { -22, 10 }, { -35, 12 }, { -35, 25 }, { -36, 36 }),
	Gallery = route({ 12, -5.5 }, { 12, 26 }, { 0, 26 }, { 0, 32 }, { 0, 40 }),
}

Upgrades.List = {
	{
		Id = "grand_entrance",
		Name = "Grand Entrance",
		Description = "Stone urn planters and a red-carpet welcome up the steps. Visitors love a good first impression. (+5% income)",
		Cost = 150,
		Requires = {},
		IncomeBonus = 0.05,
		Slots = {},
		Pad = { X = -57, Z = 0 },
		Order = 1,
	},
	{
		Id = "hall_cases",
		Name = "Glass Display Cases",
		Description = "Two glass cases for coins, jewellery and other small treasures.",
		Cost = 300,
		Requires = {},
		Slots = { S("H4", "Case", "AisleW", -15.5, 19), S("H5", "Case", "AisleE", 15.5, 19) },
		Pad = { X = 57, Z = 0 },
		Order = 2,
	},
	{
		Id = "east_wing",
		Name = "East Gallery",
		Description = "A new wing with wall hangings for paintings and arms. Museum Level 2.",
		Cost = 1200,
		Requires = { "hall_cases" },
		GrantsLevel = 2,
		Slots = {
			S("E1", "Wall", "East", 49, 2, 90),
			S("E2", "Wall", "East", 49, 18, 90),
			S("E3", "Pedestal", "East", 35, 6),
		},
		Pad = { X = 57, Z = 8 },
		Order = 3,
	},
	{
		Id = "benches_plants",
		Name = "Benches & Greenery",
		Description = "Comfortable benches and potted palms keep visitors around longer. (+10% income)",
		Cost = 900,
		Requires = { "east_wing" },
		IncomeBonus = 0.10,
		Slots = {},
		Pad = { X = -57, Z = 8 },
		Order = 4,
	},
	{
		Id = "fossil_hall",
		Name = "Fossil Hall",
		Description = "Large platforms for fossils and sculptures. Museum Level 3.",
		Cost = 4000,
		Requires = { "east_wing" },
		GrantsLevel = 3,
		Slots = {
			S("F1", "Platform", "Fossil", 29, 40),
			S("F2", "Platform", "Fossil", 44, 40),
			S("F3", "Wall", "Fossil", 36.5, 53.5, 0),
		},
		Pad = { X = 57, Z = 16 },
		Order = 5,
	},
	{
		Id = "chandeliers",
		Name = "Golden Chandeliers",
		Description = "Warm golden light makes every exhibit shine. (+10% income)",
		Cost = 3000,
		Requires = { "fossil_hall" },
		IncomeBonus = 0.10,
		Slots = {},
		Pad = { X = -57, Z = 16 },
		Order = 6,
	},
	{
		Id = "security",
		Name = "Security System",
		Description = "A security control room. Required to display Legendary and Mythic treasures, and to install cameras in every room.",
		Cost = 6000,
		Requires = { "fossil_hall" },
		EnablesSecurity = true,
		Slots = {},
		Pad = { X = 57, Z = 24 },
		Order = 7,
	},
	{
		Id = "west_wing",
		Name = "Ancient History Wing",
		Description = "Pedestals and cases for relics, regalia and sculpture. Museum Level 4.",
		Cost = 9000,
		Requires = { "fossil_hall" },
		GrantsLevel = 4,
		Slots = {
			S("W1", "Pedestal", "West", -28, 2),
			S("W2", "Pedestal", "West", -42, 2),
			S("W3", "Wall", "West", -49, 10, -90),
			S("W4", "Case", "West", -28, 18),
			S("W5", "Case", "West", -44, 18),
		},
		Pad = { X = -57, Z = 24 },
		Order = 8,
	},
	{
		Id = "grand_gallery",
		Name = "Grand Gallery",
		Description = "A soaring rear gallery for your finest paintings. Museum Level 5.",
		Cost = 25000,
		Requires = { "west_wing" },
		GrantsLevel = 5,
		Slots = {
			S("G1", "Wall", "Gallery", -9, 61, 0),
			S("G2", "Wall", "Gallery", 9, 61, 0),
			S("G3", "Wall", "Gallery", -19, 46, -90),
			S("G4", "Wall", "Gallery", 19, 46, 90),
			S("G5", "Case", "Gallery", -8, 44),
			S("G6", "Case", "Gallery", 8, 44),
		},
		Pad = { X = -57, Z = 32 },
		Order = 9,
	},
	{
		Id = "fountain_facade",
		Name = "Golden Facade & Fountain",
		Description = "A fountain, banners and gold trim. Your museum becomes a landmark. (+15% income)",
		Cost = 40000,
		Requires = { "grand_gallery" },
		IncomeBonus = 0.15,
		Slots = {},
		Pad = { X = 57, Z = 32 },
		Order = 10,
	},
	{
		Id = "treasure_vault",
		Name = "Treasure Vault",
		Description = "An armoured vault for Mythic treasures. Museum Level 6.",
		Cost = 60000,
		Requires = { "grand_gallery", "security" },
		GrantsLevel = 6,
		Slots = { S("V1", "Vault", "Vault", -43, 42), S("V2", "Vault", "Vault", -30, 42) },
		Pad = { X = 57, Z = 40 },
		Order = 11,
	},
} :: { UpgradeDef }

Upgrades.ById = {} :: { [string]: UpgradeDef }
-- SlotId -> { Slot = SlotDef, Upgrade = upgradeId or "base" }
Upgrades.SlotById = {} :: { [string]: { Slot: SlotDef, Upgrade: string } }

for _, slot in Upgrades.BaseSlots do
	Upgrades.SlotById[slot.Id] = { Slot = slot, Upgrade = "base" }
end
for _, up in Upgrades.List do
	assert(Upgrades.ById[up.Id] == nil, "Duplicate upgrade id " .. up.Id)
	Upgrades.ById[up.Id] = up
	for _, slot in up.Slots do
		assert(Upgrades.SlotById[slot.Id] == nil, "Duplicate slot id " .. slot.Id)
		Upgrades.SlotById[slot.Id] = { Slot = slot, Upgrade = up.Id }
	end
end
for _, up in Upgrades.List do
	for _, req in up.Requires do
		assert(Upgrades.ById[req], up.Id .. " requires unknown upgrade " .. req)
	end
end

-- owned: set of upgrade ids { [id] = true }
function Upgrades.ComputeLevel(owned: { [string]: boolean }): number
	local level = 1
	for id in owned do
		local up = Upgrades.ById[id]
		if up and up.GrantsLevel and up.GrantsLevel > level then
			level = up.GrantsLevel
		end
	end
	return level
end

function Upgrades.RequirementsMet(up: UpgradeDef, owned: { [string]: boolean }): boolean
	for _, req in up.Requires do
		if not owned[req] then
			return false
		end
	end
	return true
end

function Upgrades.IncomeBonus(owned: { [string]: boolean }): number
	local bonus = 0
	for id in owned do
		local up = Upgrades.ById[id]
		if up and up.IncomeBonus then
			bonus += up.IncomeBonus
		end
	end
	return bonus
end

function Upgrades.HasSecurity(owned: { [string]: boolean }): boolean
	for id in owned do
		local up = Upgrades.ById[id]
		if up and up.EnablesSecurity then
			return true
		end
	end
	return false
end

function Upgrades.IsSlotUnlocked(slotId: string, owned: { [string]: boolean }): boolean
	local entry = Upgrades.SlotById[slotId]
	if not entry then
		return false
	end
	return entry.Upgrade == "base" or owned[entry.Upgrade] == true
end

return Upgrades
