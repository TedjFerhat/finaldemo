--[[
	Monetization
	ALL Robux settings live here. Nothing is purchasable until you replace the
	placeholder Ids (0) with the real ones from the Creator Dashboard.
	An item whose Id is 0 shows "Not available yet" in the shop and can't be
	bought — there is no fake/test purchase path anywhere in the code.

	  • Game Pass         = permanent unlock (Fly Mode)
	  • Developer Product = repeatable purchase (heist gear bundles)

	Prices are NOT set here: you set them in the Creator Dashboard and the shop
	reads the live price from Roblox.
]]

local Monetization = {}

export type PassDef = { Key: string, Id: number, Name: string, Description: string, Icon: string }
export type ProductDef = {
	Key: string,
	Id: number,
	Name: string,
	Description: string,
	Icon: string,
	Grants: { { ItemId: string, Count: number } }, -- existing ItemCatalog gadget ids
	Cash: number?, -- cash packs: in-game cash granted (Grants is empty)
}

-- ── CONFIG: REPLACE THESE IDS (see the setup tutorial) ─────────────────────
Monetization.Passes = {
	FlyMode = {
		Key = "FlyMode",
		Id = 0, -- ◀◀◀ PUT YOUR FLY MODE GAME PASS ID HERE
		Name = "Explorer's Wings — Fly Mode",
		Description = "Permanently unlock flight. Toggle with F (or the Fly button) to soar over the ruins and the jungle. Flight turns off automatically during heists, digs and minigames, so it never replaces the real gameplay.",
		Icon = "🪽",
	},
} :: { [string]: PassDef }

-- Powers = permanent Game Passes the player can switch on/off in the Robux Store.
-- (Fly Mode is separate: see Monetization.Fly and FlyController.)
Monetization.Passes.FastWalk = {
	Key = "FastWalk",
	Id = 0, -- ◀◀◀ PUT YOUR FAST WALK GAME PASS ID HERE
	Name = "Swift Boots — Fast Walk",
	Description = "Run faster everywhere. Switches off automatically during heists and in jail.",
	Icon = "👟",
}
Monetization.Passes.HighJump = {
	Key = "HighJump",
	Id = 0, -- ◀◀◀ PUT YOUR HIGH JUMP GAME PASS ID HERE
	Name = "Spring Boots — High Jump",
	Description = "Jump much higher to reach ledges and roofs. Switches off automatically during heists and in jail.",
	Icon = "🦘",
}

Monetization.Powers = {
	FastWalk = { Pass = "FastWalk", WalkSpeed = 28 }, -- normal speed is 16
	HighJump = { Pass = "HighJump", JumpPower = 95, JumpHeight = 17 }, -- normal 50 / 7.2
} :: { [string]: { Pass: string, WalkSpeed: number?, JumpPower: number?, JumpHeight: number? } }

-- Cash packs (Developer Products, repeatable). Amounts are in-game cash;
-- edit freely. Price (Robux) is set in the Creator Dashboard.
Monetization.CashPacks = {
	CashSmall = { Key = "CashSmall", Id = 0, Name = "Pouch of Coins", Icon = "💰", Cash = 5000, Grants = {}, Description = "$5,000 added to your museum funds instantly." }, -- ◀◀◀ ID
	CashMedium = { Key = "CashMedium", Id = 0, Name = "Chest of Gold", Icon = "🪙", Cash = 30000, Grants = {}, Description = "$30,000 added to your museum funds instantly." }, -- ◀◀◀ ID
	CashLarge = { Key = "CashLarge", Id = 0, Name = "Royal Treasury", Icon = "👑", Cash = 150000, Grants = {}, Description = "$150,000 added to your museum funds instantly." }, -- ◀◀◀ ID
} :: { [string]: ProductDef }

Monetization.Products = {
	LocksmithBundle = {
		Key = "LocksmithBundle",
		Id = 0, -- ◀◀◀ PUT YOUR LOCKSMITH BUNDLE DEVELOPER PRODUCT ID HERE
		Name = "Locksmith Bundle",
		Description = "Master Lockpicks + a Lockpick Set. Normal heist rules still apply: alarms, cameras and cooldowns are not bypassed.",
		Icon = "🗝️",
		Grants = { { ItemId = "gd_lockpick_pro", Count = 1 }, { ItemId = "gd_lockpick", Count = 1 } },
	},
	SafecrackerBundle = {
		Key = "SafecrackerBundle",
		Id = 0, -- ◀◀◀ PUT YOUR SAFECRACKER BUNDLE DEVELOPER PRODUCT ID HERE
		Name = "Safecracker Bundle",
		Description = "Diamond Cutter + Camera Jammer. Same charges and same security checks as the in-game shop gear.",
		Icon = "💎",
		Grants = { { ItemId = "gd_cutter_pro", Count = 1 }, { ItemId = "gd_jammer", Count = 1 } },
	},
} :: { [string]: ProductDef }

-- ── Fly Mode tuning ────────────────────────────────────────────────────────
Monetization.Fly = {
	Speed = 42, -- studs/second horizontal (walking is 16)
	VerticalSpeed = 28,
	MaxServerSpeed = 70, -- the server snaps back anyone faster than this while flying
	MaxHeight = 220, -- studs above the ground level the player took off from
	ToggleCooldown = 0.6, -- seconds between toggle requests
	Key = Enum.KeyCode.F,
}

-- How many purchase receipts to remember per player (duplicate protection).
Monetization.MaxStoredReceipts = 400

function Monetization.ProductById(id: number): ProductDef?
	if id <= 0 then
		return nil
	end
	for _, p in Monetization.Products do
		if p.Id == id then
			return p
		end
	end
	for _, p in Monetization.CashPacks do
		if p.Id == id then
			return p
		end
	end
	return nil
end

function Monetization.IsConfigured(def: { Id: number }): boolean
	return def.Id > 0
end

return Monetization
