--[[
	ItemCatalog
	The item DATABASE. Every artefact *definition* lives here.

	IMPORTANT DIFFERENCE:
	  • An item DEFINITION ("coin_gold_sun") describes what an item is.
	  • An item INSTANCE is one specific copy owned by a player. Instances are
	    created only by the server and get their own unique ID (Uid). They are
	    stored in the player's save data as { Id = "coin_gold_sun", Uid = "...", ... }.

	To add a new artefact: add ONE line to the Items list below. No new scripts.
	To use a real 3D model later: put a Model in ReplicatedStorage/ItemModels with
	the same name as the item Id (see ItemModels module) — the placeholder is replaced.

	Kinds:
	  • "Artefact" — found, displayed, sold, traded, stolen.
	  • "Gadget"   — heist equipment with Charges. Kept in the inventory so it can
	                 be traded/sold, but never displayed.
]]

export type ModelSpec = {
	Shape: string, -- which placeholder builder to use (see ItemModels)
	Color: Color3,
	Accent: Color3?,
	Material: Enum.Material?,
	Scale: number?,
}

export type ItemDef = {
	Id: string,
	Name: string,
	Category: string,
	Rarity: string,
	Value: number, -- base market value (NPC buyers pay Value * Config.NpcSellRate)
	Income: number, -- museum income per minute while displayed
	Display: { string }, -- display slot types this item fits in
	RequiresSecurity: boolean,
	Zone: string,
	Set: string?,
	Lore: string,
	Tradable: boolean,
	Sellable: boolean,
	Model: ModelSpec,
	Kind: string, -- "Artefact" | "Gadget"
	Heistable: boolean, -- can be stolen from a museum display
	Fragility: number, -- 0..1, how easily excavation damages it
	Material: string, -- scanner reading: Metal | Stone | Ceramic | Organic | Gem | Paper
	Heavy: boolean, -- excavation needs a Pick
	SpecialOnly: boolean, -- never in random loot (quest/altar reward only)
	Gadget: GadgetSpec?,
}

export type GadgetSpec = {
	Type: string, -- Lockpick | Cutter | Jammer | Mirror | Smoke | Soles | Grapple
	Tier: number,
	Charges: number,
	Cost: number,
	Description: string,
}

-- Categories and the display slot types they fit by default.
-- Slot types: Pedestal, Case, Wall, Platform, Vault
local Categories = {
	Coin = { Name = "Ancient Coins", Display = { "Case" } },
	Pottery = { Name = "Pottery & Ceramics", Display = { "Pedestal", "Case" } },
	Document = { Name = "Historical Documents", Display = { "Case", "Wall" } },
	Weapon = { Name = "Ancient Arms", Display = { "Wall", "Pedestal" } },
	Sculpture = { Name = "Sculptures", Display = { "Pedestal", "Platform" } },
	Painting = { Name = "Paintings & Frescoes", Display = { "Wall" } },
	Jewellery = { Name = "Jewellery", Display = { "Case" } },
	Royal = { Name = "Royal Regalia", Display = { "Case", "Pedestal" } },
	Gemstone = { Name = "Precious Gemstones", Display = { "Case" } },
	Fossil = { Name = "Fossils", Display = { "Platform", "Pedestal" } },
	Relic = { Name = "Ancient Relics", Display = { "Pedestal", "Case" } },
	Treasure = { Name = "Lost Treasures", Display = { "Vault" } },
	Gadget = { Name = "Heist Gear", Display = {} },
}

-- Defaults used by excavation (scanner material, how fragile, needs a pick).
local CategoryTraits = {
	Coin = { Material = "Metal", Fragility = 0.15, Heavy = false },
	Pottery = { Material = "Ceramic", Fragility = 0.8, Heavy = false },
	Document = { Material = "Paper", Fragility = 0.7, Heavy = false },
	Weapon = { Material = "Metal", Fragility = 0.25, Heavy = false },
	Sculpture = { Material = "Stone", Fragility = 0.35, Heavy = true },
	Painting = { Material = "Paper", Fragility = 0.6, Heavy = false },
	Jewellery = { Material = "Metal", Fragility = 0.5, Heavy = false },
	Royal = { Material = "Metal", Fragility = 0.45, Heavy = false },
	Gemstone = { Material = "Gem", Fragility = 0.3, Heavy = false },
	Fossil = { Material = "Organic", Fragility = 0.65, Heavy = false },
	Relic = { Material = "Stone", Fragility = 0.4, Heavy = false },
	Treasure = { Material = "Metal", Fragility = 0.3, Heavy = true },
	Gadget = { Material = "Metal", Fragility = 0, Heavy = false },
}

local Config = require(script.Parent.Config)

local C = Color3.fromRGB
local M = Enum.Material

-- Compact constructor so each item fits on one readable line.
-- I(id, name, category, rarity, value, incomePerMinute, modelSpec, lore, extra?)
local Items: { [string]: ItemDef } = {}
local Order: { string } = {}

local function I(id: string, name: string, category: string, rarity: string, value: number, income: number, model: ModelSpec, lore: string, extra: { [string]: any }?)
	assert(Items[id] == nil, "Duplicate item id: " .. id)
	assert(Categories[category], "Unknown category for " .. id .. ": " .. category)
	local def: ItemDef = {
		Id = id,
		Name = name,
		Category = category,
		Rarity = rarity,
		Value = value,
		Income = income,
		Display = Categories[category].Display,
		RequiresSecurity = (rarity == "Legendary" or rarity == "Mythic"),
		Zone = "ForgottenRuins",
		Set = nil,
		Lore = lore,
		Tradable = true,
		Sellable = true,
		Model = model,
		Kind = if category == "Gadget" then "Gadget" else "Artefact",
		Heistable = category ~= "Gadget",
		Fragility = CategoryTraits[category].Fragility,
		Material = CategoryTraits[category].Material,
		Heavy = CategoryTraits[category].Heavy,
		SpecialOnly = false,
		Gadget = nil,
	}
	if extra then
		for key, v in extra do
			(def :: any)[key] = v
		end
	end
	Items[id] = def
	table.insert(Order, id)
end

-- ── FORGOTTEN RUINS ─────────────────────────────────────────────────────────
-- Common
I("coin_bronze_worn", "Worn Bronze Coin", "Coin", "Common", 35, 5, { Shape = "Coin", Color = C(150, 100, 55), Material = M.Metal }, "Rubbed smooth by a thousand merchants' thumbs. A face can almost be seen.")
I("clay_pot_cracked", "Cracked Clay Pot", "Pottery", "Common", 30, 5, { Shape = "Pot", Color = C(170, 95, 60), Material = M.Slate }, "It once held grain for a family of six. The crack came later.")
I("pottery_shard", "Painted Pottery Shard", "Pottery", "Common", 45, 6, { Shape = "Tablet", Color = C(190, 120, 80), Accent = C(40, 40, 40), Scale = 0.6 }, "A sliver of a larger story — a painted foot, mid-dance.")
I("arrowhead_flint", "Flint Arrowhead", "Weapon", "Common", 40, 5, { Shape = "Spear", Color = C(90, 90, 95), Material = M.Slate, Scale = 0.5 }, "Knapped by a patient hand long before the ruins were ruins.")
I("tablet_clay", "Clay Tally Tablet", "Document", "Common", 50, 6, { Shape = "Tablet", Color = C(160, 120, 85), Accent = C(90, 60, 40) }, "Rows of tiny marks. Someone was very carefully counting goats.")
I("beads_clay", "String of Clay Beads", "Jewellery", "Common", 40, 5, { Shape = "Necklace", Color = C(180, 110, 70) }, "Simple, cheerful beads made for a child.")
I("bone_fragment", "Fossilized Bone Fragment", "Fossil", "Common", 45, 6, { Shape = "Bone", Color = C(215, 200, 170), Material = M.Limestone }, "Older than the ruins by a few million years.")

-- Uncommon
I("coin_silver_drachma", "Silver Ruin Drachma", "Coin", "Uncommon", 120, 13, { Shape = "Coin", Color = C(200, 200, 210), Material = M.Metal }, "Struck with an owl on one side and a wheat stalk on the other.")
I("amphora_oil", "Oil Amphora", "Pottery", "Uncommon", 140, 14, { Shape = "Vase", Color = C(185, 110, 70), Accent = C(30, 30, 30) }, "Still smells faintly of olives. Probably imagination.")
I("scroll_merchant", "Merchant's Ledger Scroll", "Document", "Uncommon", 130, 13, { Shape = "Scroll", Color = C(225, 205, 160) }, "Debts, deals and one angry note about a late shipment of figs.")
I("dagger_bronze", "Bronze Ceremonial Dagger", "Weapon", "Uncommon", 150, 14, { Shape = "Sword", Color = C(170, 120, 60), Material = M.Metal, Scale = 0.6 }, "Too beautiful to fight with. It was carried, never used.")
I("bust_scholar", "Weathered Scholar Bust", "Sculpture", "Uncommon", 170, 15, { Shape = "Bust", Color = C(200, 195, 185), Material = M.Marble }, "A thoughtful face, nose long since lost to time.")
I("ring_copper", "Copper Signet Ring", "Jewellery", "Uncommon", 110, 12, { Shape = "Ring", Color = C(190, 110, 70), Material = M.Metal }, "Pressed into wax to seal letters of the royal household.")
I("ammonite", "Spiral Ammonite", "Fossil", "Uncommon", 160, 15, { Shape = "Ammonite", Color = C(170, 140, 110), Material = M.Limestone }, "A perfect spiral from a sea that no longer exists.")
I("fresco_fragment", "Faded Fresco Fragment", "Painting", "Uncommon", 180, 16, { Shape = "Painting", Color = C(200, 160, 120), Accent = C(90, 130, 150) }, "Blue birds over a blue sea. The blue has outlived the birds.")

-- Rare
I("coin_gold_sun", "Gold Sun Coin", "Coin", "Rare", 340, 34, { Shape = "Coin", Color = C(240, 190, 60), Material = M.Metal }, "Minted only in the year the sun 'stood still'.")
I("vase_painted", "Painted Ruin Vase", "Pottery", "Rare", 300, 32, { Shape = "Vase", Color = C(30, 30, 35), Accent = C(220, 120, 60) }, "Black-figure heroes race around its belly forever.")
I("sword_iron_guard", "Guardian's Iron Sword", "Weapon", "Rare", 380, 36, { Shape = "Sword", Color = C(150, 155, 165), Accent = C(200, 160, 60), Material = M.Metal }, "Belonged to the gate guardian. The gate fell anyway.")
I("statue_owl", "Stone Owl of Wisdom", "Sculpture", "Rare", 400, 38, { Shape = "Owl", Color = C(140, 135, 125), Material = M.Granite }, "Its eyes were once polished obsidian. One remains.")
I("painting_harbor", "Ancient Harbor Fresco", "Painting", "Rare", 420, 40, { Shape = "Painting", Color = C(230, 200, 150), Accent = C(50, 110, 160) }, "The only known picture of the city's lost harbour.")
I("amethyst_rough", "Rough Amethyst", "Gemstone", "Rare", 360, 35, { Shape = "Gem", Color = C(150, 80, 200), Material = M.Glass }, "Pulled from the cave wall, glittering with violet light.")
I("mask_bronze", "Bronze Theatre Mask", "Relic", "Rare", 350, 34, { Shape = "Mask", Color = C(175, 125, 65), Material = M.Metal }, "Worn by the actor who played the King. Every night, he died.")
I("skull_raptor", "Raptor Skull", "Fossil", "Rare", 410, 39, { Shape = "Skull", Color = C(220, 205, 175), Material = M.Limestone }, "The teeth are very, very sharp. Please do not touch.")

-- Epic
I("shield_sunburst", "Sunburst Shield", "Weapon", "Epic", 950, 92, { Shape = "Shield", Color = C(190, 140, 50), Accent = C(240, 210, 90), Material = M.Metal }, "Polished so brightly it was said to blind charging armies.")
I("necklace_lapis", "Lapis Lazuli Collar", "Jewellery", "Epic", 900, 88, { Shape = "Necklace", Color = C(40, 70, 170), Accent = C(240, 200, 70) }, "Deep blue stone carried across three deserts to reach the ruins.")
I("idol_jade", "Jade Guardian Idol", "Relic", "Epic", 1050, 96, { Shape = "Idol", Color = C(60, 160, 110), Material = M.Glass }, "Locals say it watches the doorway. Nobody tests this.")
I("scroll_star_map", "Star Map Scroll", "Document", "Epic", 1000, 94, { Shape = "Scroll", Color = C(30, 40, 80), Accent = C(240, 220, 120) }, "Charts stars that astronomers say should not have been visible.")
I("emerald_temple", "Temple Emerald", "Gemstone", "Epic", 1100, 98, { Shape = "Gem", Color = C(40, 200, 110), Material = M.Glass, Scale = 1.2 }, "Set into the eye of a temple statue. The statue misses it.")

-- Legendary (need the Security System upgrade to display)
I("scepter_ruin_king", "Scepter of the Ruin King", "Royal", "Legendary", 2900, 240, { Shape = "Scepter", Color = C(240, 190, 60), Accent = C(200, 30, 60), Material = M.Metal }, "The last king raised it once, and the city fell silent.")
I("crown_forgotten_queen", "Crown of the Forgotten Queen", "Royal", "Legendary", 3200, 260, { Shape = "Crown", Color = C(245, 200, 70), Accent = C(60, 120, 230), Material = M.Metal }, "Her name was erased from every wall. Her crown was not.")
I("statue_golden_lion", "Golden Lion Statue", "Sculpture", "Legendary", 3000, 250, { Shape = "Lion", Color = C(235, 185, 60), Material = M.Metal }, "Guardian of the treasury. It guarded very well, until now.")

-- Mythic (need the Treasure Vault to display)
I("heart_of_ruins", "Heart of the Ruins", "Treasure", "Mythic", 9500, 720, { Shape = "Gem", Color = C(230, 40, 90), Material = M.Neon, Scale = 1.8 }, "A stone that pulses like a heartbeat. The ruins were built around it.")
I("chest_first_king", "Treasury of the First King", "Treasure", "Mythic", 9000, 700, { Shape = "Chest", Color = C(110, 70, 40), Accent = C(245, 200, 70) }, "Sealed for three thousand years. Still heavy with gold.")

-- Starter gifts can't be stolen (protects brand-new museums).
Items.clay_pot_cracked.Heistable = false
Items.coin_bronze_worn.Heistable = false

-- ── FALSE LEADS (any zone) ──────────────────────────────────────────────────
I("historical_fragments", "Historical Fragments", "Pottery", "Common", 12, 1, { Shape = "Fragments", Color = C(165, 120, 85), Material = M.Slate }, "Broken pieces of something that was once beautiful. Scholars still like them.", { Zone = "Any", SpecialOnly = true, Heistable = false })

-- ── JUNGLE TEMPLE ───────────────────────────────────────────────────────────
local J = { Zone = "JungleTemple" }
local function jungle(extra: { [string]: any }?): { [string]: any }
	local t = table.clone(J)
	if extra then
		for k, v in extra do
			t[k] = v
		end
	end
	return t
end
I("jg_obsidian_blade", "Obsidian Ritual Blade", "Weapon", "Common", 60, 7, { Shape = "ObsidianBlade", Color = C(30, 28, 36), Accent = C(120, 80, 50), Material = M.Glass }, "Volcanic glass, knapped so finely it still catches the light.", jungle())
I("jg_bird_whistle", "Clay Bird Whistle", "Pottery", "Common", 55, 6, { Shape = "BirdWhistle", Color = C(175, 110, 70), Accent = C(60, 120, 100), Material = M.Slate }, "Blow gently and the jungle answers.", jungle())
I("jg_vessel", "Painted Ritual Vessel", "Pottery", "Uncommon", 220, 20, { Shape = "RitualVessel", Color = C(190, 120, 70), Accent = C(40, 30, 25), Material = M.Slate }, "Painted with dancing jaguars. It held cacao for the gods.", jungle({ Fragility = 0.9 }))
I("jg_calendar", "Engraved Calendar Stone", "Document", "Rare", 520, 48, { Shape = "CalendarStone", Color = C(120, 125, 110), Accent = C(70, 90, 60), Material = M.Slate }, "Twenty glyphs circle a central sun. It counts days we no longer remember.", jungle({ Heavy = true, Material = "Stone", Fragility = 0.3 }))
I("jg_jade_jaguar", "Carved Jade Jaguar", "Sculpture", "Rare", 600, 52, { Shape = "JadeJaguar", Color = C(60, 150, 110), Material = M.Glass }, "A crouching jaguar, carved from a single jade boulder.", jungle({ Heavy = false, Material = "Gem", Fragility = 0.55 }))
I("jg_mosaic_mask", "Jade Mosaic Death Mask", "Relic", "Epic", 1500, 130, { Shape = "MosaicMask", Color = C(50, 140, 100), Accent = C(240, 240, 230), Material = M.Glass }, "Hundreds of jade tiles, shell eyes and an obsidian gaze. Made for a king's journey.", jungle({ Fragility = 0.85, Material = "Gem" }))
I("jg_serpent_pectoral", "Gold Serpent Pectoral", "Jewellery", "Legendary", 3800, 300, { Shape = "SerpentPectoral", Color = C(230, 180, 60), Accent = C(40, 150, 120), Material = M.Metal }, "A feathered serpent of beaten gold, coiled around a jade heart.", jungle({ Fragility = 0.4 }))
I("jg_sun_disk", "Sun Disk of the Jaguar King", "Treasure", "Mythic", 12000, 900, { Shape = "SunDisk", Color = C(240, 190, 60), Accent = C(60, 150, 110), Material = M.Metal, Scale = 1.3 }, "Hidden beneath the eagle's gaze. Whoever holds it, the legend says, holds the dawn.", jungle({ SpecialOnly = true, Fragility = 0.35 }))

-- ── HEIST GEAR (gadgets with charges) ───────────────────────────────────────
local function G(id: string, name: string, rarity: string, gadgetType: string, tier: number, charges: number, cost: number, description: string, model: ModelSpec)
	I(id, name, "Gadget", rarity, cost, 0, model, description, {
		Zone = "Shop",
		SpecialOnly = true,
		Heistable = false,
		Gadget = { Type = gadgetType, Tier = tier, Charges = charges, Cost = cost, Description = description },
	})
end
G("gd_lockpick", "Lockpick Set", "Common", "Lockpick", 2, 4, 400, "Picks locks up to tier 2. One charge per lock; a failed lock breaks a pick.", { Shape = "Lockpick", Color = C(160, 160, 170), Material = M.Metal })
G("gd_lockpick_pro", "Master Lockpicks", "Rare", "Lockpick", 3, 4, 2500, "Picks any lock, with a wider sweet spot.", { Shape = "Lockpick", Color = C(230, 190, 80), Material = M.Metal })
G("gd_cutter", "Glass Cutter", "Common", "Cutter", 2, 3, 600, "Cuts display glass up to tier 2. One charge per case.", { Shape = "Cutter", Color = C(120, 160, 200), Material = M.Metal })
G("gd_cutter_pro", "Diamond Cutter", "Rare", "Cutter", 3, 3, 3000, "Cuts any display glass, including vaults.", { Shape = "Cutter", Color = C(200, 230, 255), Material = M.Glass })
G("gd_jammer", "Camera Jammer", "Uncommon", "Jammer", 1, 3, 800, "Blinds the cameras in one room (shorter against hardened cameras).", { Shape = "Jammer", Color = C(50, 55, 60), Accent = C(255, 60, 60), Material = M.Metal })

local ItemCatalog = {}
ItemCatalog.Items = Items
ItemCatalog.Order = Order
ItemCatalog.Categories = Categories

function ItemCatalog.Get(id: string): ItemDef?
	return Items[id]
end

function ItemCatalog.Exists(id: any): boolean
	return type(id) == "string" and Items[id] ~= nil
end

function ItemCatalog.CategoryName(category: string): string
	local c = Categories[category]
	return if c then c.Name else category
end

-- Can this item go into a slot of this type?
function ItemCatalog.FitsSlot(def: ItemDef, slotType: string): boolean
	return table.find(def.Display, slotType) ~= nil
end

-- All randomly-findable items belonging to a zone (used by the loot system).
function ItemCatalog.ForZone(zoneId: string): { ItemDef }
	local result = {}
	for _, id in Order do
		local def = Items[id]
		if def.Zone == zoneId and not def.SpecialOnly then
			table.insert(result, def)
		end
	end
	return result
end

function ItemCatalog.IsGadget(def: ItemDef?): boolean
	return def ~= nil and def.Kind == "Gadget"
end

-- Value of one specific copy: artefacts scale with condition, gadgets with
-- remaining charges.
function ItemCatalog.InstanceValue(def: ItemDef, condition: string?, charges: number?): number
	if def.Gadget then
		local fraction = math.clamp((charges or def.Gadget.Charges) / def.Gadget.Charges, 0, 1)
		return math.floor(def.Value * fraction)
	end
	local cond = Config.Conditions[condition or "Clean"] or Config.Conditions.Clean
	return math.floor(def.Value * cond.Multiplier)
end

-- Museum income of one displayed copy (per minute, before museum bonuses).
function ItemCatalog.InstanceIncome(def: ItemDef, condition: string?): number
	local cond = Config.Conditions[condition or "Clean"] or Config.Conditions.Clean
	return def.Income * cond.Multiplier
end

-- Give every item its collection set id (sets are defined in CollectionSets).
local CollectionSets = require(script.Parent.CollectionSets)
for _, set in CollectionSets.List do
	for _, itemId in set.Items do
		local def = Items[itemId]
		assert(def, "CollectionSets '" .. set.Id .. "' references unknown item: " .. itemId)
		def.Set = set.Id
	end
end

return ItemCatalog
