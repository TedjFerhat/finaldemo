--[[
	CollectionSets
	Groups of items. When a player has DISCOVERED every item in a set (it is
	recorded in their journal forever, even if they later sell the items),
	they receive the reward ONCE. The server records claimed sets in the save
	data so the reward can never be paid twice.

	Pure data — no requires — so ItemCatalog can safely read it.
]]

export type SetDef = {
	Id: string,
	Name: string,
	Zone: string,
	Items: { string },
	RewardCash: number,
	RewardPrestige: number,
}

local List: { SetDef } = {
	{
		Id = "old_coins",
		Name = "Coins of the Old Kingdom",
		Zone = "ForgottenRuins",
		Items = { "coin_bronze_worn", "coin_silver_drachma", "coin_gold_sun" },
		RewardCash = 500,
		RewardPrestige = 25,
	},
	{
		Id = "potters_legacy",
		Name = "The Potter's Legacy",
		Zone = "ForgottenRuins",
		Items = { "clay_pot_cracked", "pottery_shard", "amphora_oil", "vase_painted" },
		RewardCash = 700,
		RewardPrestige = 25,
	},
	{
		Id = "fossil_record",
		Name = "The Fossil Record",
		Zone = "ForgottenRuins",
		Items = { "bone_fragment", "ammonite", "skull_raptor" },
		RewardCash = 900,
		RewardPrestige = 30,
	},
	{
		Id = "scholars_archive",
		Name = "The Scholar's Archive",
		Zone = "ForgottenRuins",
		Items = { "tablet_clay", "scroll_merchant", "bust_scholar", "scroll_star_map" },
		RewardCash = 2000,
		RewardPrestige = 50,
	},
	{
		Id = "gate_armory",
		Name = "Armory of the Gate",
		Zone = "ForgottenRuins",
		Items = { "arrowhead_flint", "dagger_bronze", "sword_iron_guard", "shield_sunburst" },
		RewardCash = 2500,
		RewardPrestige = 50,
	},
	{
		Id = "royal_regalia",
		Name = "Regalia of the Ruin Kings",
		Zone = "ForgottenRuins",
		Items = { "ring_copper", "scepter_ruin_king", "crown_forgotten_queen" },
		RewardCash = 10000,
		RewardPrestige = 150,
	},
	{
		Id = "jaguar_temple",
		Name = "Treasures of the Jaguar Temple",
		Zone = "JungleTemple",
		Items = { "jg_vessel", "jg_calendar", "jg_jade_jaguar", "jg_mosaic_mask" },
		RewardCash = 4000,
		RewardPrestige = 60,
	},
	{
		Id = "jungle_daily_life",
		Name = "Life Beneath the Canopy",
		Zone = "JungleTemple",
		Items = { "jg_obsidian_blade", "jg_bird_whistle", "jg_serpent_pectoral" },
		RewardCash = 3000,
		RewardPrestige = 40,
	},
}

local CollectionSets = {}
CollectionSets.List = List
CollectionSets.ById = {} :: { [string]: SetDef }
for _, set in List do
	CollectionSets.ById[set.Id] = set
end

return CollectionSets
