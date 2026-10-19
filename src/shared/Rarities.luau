--[[
	Rarities
	One place for rarity order, colours, discovery weights and prestige points.
	The colours are used EVERYWHERE (inventory, notifications, nameplates,
	journal) so rarity always looks the same.
]]

export type RarityDef = {
	Id: string,
	Order: number,
	Color: Color3,
	Weight: number, -- base discovery weight before zone/site/equipment changes
	PrestigePoints: number,
	Glow: boolean, -- displayed items get a light + sparkles
}

local list: { RarityDef } = {
	{ Id = "Common", Order = 1, Color = Color3.fromRGB(176, 168, 152), Weight = 55, PrestigePoints = 1, Glow = false },
	{ Id = "Uncommon", Order = 2, Color = Color3.fromRGB(96, 186, 110), Weight = 27, PrestigePoints = 2, Glow = false },
	{ Id = "Rare", Order = 3, Color = Color3.fromRGB(70, 140, 230), Weight = 12, PrestigePoints = 4, Glow = false },
	{ Id = "Epic", Order = 4, Color = Color3.fromRGB(168, 92, 230), Weight = 4.5, PrestigePoints = 8, Glow = true },
	{ Id = "Legendary", Order = 5, Color = Color3.fromRGB(245, 176, 46), Weight = 1.2, PrestigePoints = 16, Glow = true },
	{ Id = "Mythic", Order = 6, Color = Color3.fromRGB(240, 70, 110), Weight = 0.3, PrestigePoints = 32, Glow = true },
}

local Rarities = {}
Rarities.List = list
Rarities.ById = {} :: { [string]: RarityDef }
for _, def in list do
	Rarities.ById[def.Id] = def
end

function Rarities.Get(id: string): RarityDef
	return Rarities.ById[id] or list[1]
end

function Rarities.Color(id: string): Color3
	return Rarities.Get(id).Color
end

function Rarities.Order(id: string): number
	return Rarities.Get(id).Order
end

return Rarities
