--[[
	Equipment
	Archaeology kits. Owning a tier means you use it automatically (the best
	kit you own is always equipped). Kits are ACCOUNT-BOUND progression items:
	they can't be traded or sold, so nobody can lose their progress.

	Better kits search faster, scan further and more precisely, unlock deeper
	digs and better excavation tools — they never guarantee rare items, and no
	scanner reveals every treasure: you still have to investigate.
]]

export type ToolDef = {
	Tier: number,
	Name: string,
	Description: string,
	Cost: number,
	RequiredLevel: number,
	SearchSeconds: number, -- quick-site search time
	Luck: number, -- multiplies Rare+ weights
	ScanRange: number, -- studs
	DirectionError: number?, -- degrees of error; nil = no direction at all
	ShowsDepth: boolean,
	ShowsMaterial: boolean,
	FlagsFalseSignals: boolean, -- can tell some mineral deposits apart
	DigDepth: number, -- 1 shallow, 2 medium, 3 deep
	ExcavationTools: { string },
	Precision: number, -- widens excavation sweet spots
	Color: Color3,
}

export type AttachmentDef = {
	Id: string,
	Name: string,
	Description: string,
	Cost: number,
	RequiredLevel: number,
	Zone: string,
	RangeMultiplier: number,
	ShowsMaterial: boolean,
}

local Equipment = {}

Equipment.Tools = {
	{
		Tier = 1, Name = "Rusty Trowel Kit", Description = "A trowel, a brush and a crackly old detector. Signal strength only.",
		Cost = 0, RequiredLevel = 1, SearchSeconds = 4.0, Luck = 1.0,
		ScanRange = 30, DirectionError = nil, ShowsDepth = false, ShowsMaterial = false, FlagsFalseSignals = false,
		DigDepth = 1, ExcavationTools = { "Brush", "Trowel" }, Precision = 0,
		Color = Color3.fromRGB(140, 110, 80),
	},
	{
		Tier = 2, Name = "Brass Excavator's Kit", Description = "Adds a pick for heavy finds, a rough direction arrow and medium-depth digs.",
		Cost = 500, RequiredLevel = 1, SearchSeconds = 3.2, Luck = 1.15,
		ScanRange = 40, DirectionError = 45, ShowsDepth = false, ShowsMaterial = false, FlagsFalseSignals = false,
		DigDepth = 2, ExcavationTools = { "Brush", "Trowel", "Pick" }, Precision = 0.02,
		Color = Color3.fromRGB(200, 160, 70),
	},
	{
		Tier = 3, Name = "Field Detector Kit", Description = "Accurate direction, depth readings and deep digs.",
		Cost = 3000, RequiredLevel = 2, SearchSeconds = 2.5, Luck = 1.3,
		ScanRange = 55, DirectionError = 20, ShowsDepth = true, ShowsMaterial = false, FlagsFalseSignals = false,
		DigDepth = 3, ExcavationTools = { "Brush", "Trowel", "Pick" }, Precision = 0.04,
		Color = Color3.fromRGB(80, 160, 200),
	},
	{
		Tier = 4, Name = "Archaeo-Scanner Kit", Description = "Precise direction, material analysis, and it flags many false signals.",
		Cost = 15000, RequiredLevel = 3, SearchSeconds = 1.8, Luck = 1.5,
		ScanRange = 70, DirectionError = 10, ShowsDepth = true, ShowsMaterial = true, FlagsFalseSignals = true,
		DigDepth = 3, ExcavationTools = { "Brush", "Trowel", "Pick" }, Precision = 0.06,
		Color = Color3.fromRGB(160, 90, 220),
	},
} :: { ToolDef }

Equipment.MaxTier = #Equipment.Tools

-- Specialised attachments (also account-bound).
Equipment.Attachments = {
	echo_sounder = {
		Id = "echo_sounder",
		Name = "Jungle Echo-Sounder",
		Description = "Sound waves pass through roots and vines: +60% scan range and material readings in the Jungle Temple.",
		Cost = 4000,
		RequiredLevel = 3,
		Zone = "JungleTemple",
		RangeMultiplier = 1.6,
		ShowsMaterial = true,
	},
} :: { [string]: AttachmentDef }

-- Excavation tools: how many strokes, how wide the sweet spot, how harsh on
-- fragile artefacts.
Equipment.ExcavationTools = {
	Brush = { Name = "Brush", Strokes = 5, ZoneWidth = 0.24, Speed = 0.5, Harshness = 0.2, Description = "Slow and gentle. Best for fragile finds." },
	Trowel = { Name = "Trowel", Strokes = 3, ZoneWidth = 0.18, Speed = 0.6, Harshness = 0.6, Description = "Quick. Risky on fragile finds." },
	Pick = { Name = "Pick", Strokes = 3, ZoneWidth = 0.16, Speed = 0.65, Harshness = 1.0, Description = "Breaks heavy stone. Very harsh on fragile finds." },
}

function Equipment.Get(tier: number): ToolDef
	return Equipment.Tools[math.clamp(math.floor(tier), 1, Equipment.MaxTier)]
end

return Equipment
