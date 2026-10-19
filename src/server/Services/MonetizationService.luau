--[[
	MonetizationService
	Robux purchases and the premium Fly Mode. The client can only ASK; this
	service decides everything.

	Game Pass (Fly Mode)
	  • Ownership is verified with MarketplaceService:UserOwnsGamePassAsync when
	    the player's data loads, and again when Roblox's server-side
	    PromptGamePassPurchaseFinished event reports a completed purchase.
	  • "SetFly" is validated on the server every time: pass owned, character
	    alive, not jailed / in a heist / in a minigame / mid-transfer.
	  • Flight is switched on by the SERVER (player attribute "FlyActive"); the
	    client only moves its own character while that attribute is true. A
	    watchdog stops flight when conditions change or movement is impossible.

	Developer Products (heist gear bundles)
	  • MarketplaceService.ProcessReceipt (the ONLY place it is set) grants the
	    items, records the PurchaseId in the player's save so a retried receipt
	    can never grant twice, saves, and only then returns PurchaseGranted.
	  • Anything unexpected returns NotProcessedYet so Roblox retries later —
	    a purchase is never silently lost and never invented.
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetization = require(Shared.Monetization)
local ItemCatalog = require(Shared.ItemCatalog)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local EconomyService = require(script.Parent.EconomyService)
local StateSync = require(script.Parent.StateSync)
local ChallengeService = require(script.Parent.ChallengeService)
local JailService = require(script.Parent.JailService)
local Net = require(script.Parent.Parent.Util.Net)

local MonetizationService = {}

local FlyCfg = Monetization.Fly

local owned: { [Player]: { [string]: boolean } } = {} -- verified Game Pass ownership, by pass key
local lastPrompt: { [Player]: number } = {}
local lastToggle: { [Player]: number } = {}
local flying: { [Player]: { Pos: Vector3, Time: number, BaseY: number } } = {}
local processing: { [string]: boolean } = {} -- receipts being handled right now
local powerOn: { [Player]: { [string]: boolean } } = {} -- Fast Walk / High Jump switched on
local baseStats: { [Player]: { WalkSpeed: number, JumpPower: number, JumpHeight: number } } = {}
local applyPowers: (Player) -> () -- defined below

local function notify(player: Player, text: string, kind: string)
	if player.Parent then
		Net.Fire("Notify", player, { Text = text, Kind = kind })
	end
end

-- ── Game Pass ownership ────────────────────────────────────────────────────
function MonetizationService.Owns(player: Player, passKey: string): boolean
	local o = owned[player]
	return o ~= nil and o[passKey] == true
end

local function setOwned(player: Player, passKey: string)
	local o = owned[player]
	if o and not o[passKey] then
		o[passKey] = true
		StateSync.Mark(player)
	end
end

local function verifyPass(player: Player, def: Monetization.PassDef): boolean
	if not Monetization.IsConfigured(def) then
		return false
	end
	for attempt = 1, 3 do
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, def.Id)
		end)
		if ok then
			return result == true
		end
		task.wait(attempt) -- back off; Roblox web calls can fail transiently
	end
	warn(("[Monetization] Could not verify %s for %s (Roblox ownership check failed)."):format(def.Key, player.Name))
	return false
end

local function verifyAll(player: Player)
	for key, def in Monetization.Passes do
		if verifyPass(player, def) then
			setOwned(player, key)
		end
	end
end

-- ── Fly Mode ───────────────────────────────────────────────────────────────
local function character(player: Player): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if char and hum and root and root:IsA("BasePart") then
		return char, hum, root
	end
	return nil, nil, nil
end

-- Returns true, or false + a short reason the player can read.
local function canFly(player: Player): (boolean, string?)
	if not MonetizationService.Owns(player, "FlyMode") then
		return false, "Fly Mode is a Game Pass. Get it in the Shop › Premium tab."
	end
	local _, hum = character(player)
	if not hum or hum.Health <= 0 then
		return false, "You can't fly right now."
	end
	if JailService.IsJailed(player) then
		return false, "No flying in jail!"
	end
	if player:GetAttribute("InHeist") == true then
		return false, "Flight is disabled during heists."
	end
	if ChallengeService.IsActive(player) or PlayerDataService.IsBusy(player) then
		return false, "Finish what you're doing first."
	end
	return true, nil
end

local function stopFly(player: Player, reason: string?)
	local was = flying[player] ~= nil or player:GetAttribute("FlyActive") == true
	flying[player] = nil
	if player:GetAttribute("FlyActive") ~= nil then
		player:SetAttribute("FlyActive", nil)
	end
	if was and reason then
		notify(player, reason, "Info")
	end
end

local function startFly(player: Player): (boolean, string?)
	local ok, reason = canFly(player)
	if not ok then
		return false, reason
	end
	local _, _, root = character(player)
	if not root then
		return false, "You can't fly right now."
	end
	flying[player] = { Pos = root.Position, Time = os.clock(), BaseY = root.Position.Y }
	player:SetAttribute("FlyActive", true)
	return true, nil
end

function MonetizationService.SetFly(player: Player, enabled: any): (boolean, string?)
	if type(enabled) ~= "boolean" then
		return false, "Invalid request"
	end
	local now = os.clock()
	if now - (lastToggle[player] or 0) < FlyCfg.ToggleCooldown then
		return false, "Not so fast!"
	end
	lastToggle[player] = now
	if not enabled then
		stopFly(player)
		return true, nil
	end
	if flying[player] then
		return true, nil
	end
	return startFly(player)
end

-- Server watchdog: flight ends the moment it stops being allowed or looks impossible.
local function watchdog()
	local now = os.clock()
	for player in powerOn do
		applyPowers(player)
	end
	for player, info in flying do
		local ok, reason = canFly(player)
		local _, _, root = character(player)
		if not ok or not root then
			stopFly(player, reason or "Flight ended.")
		else
			local dt = math.max(now - info.Time, 0.05)
			local speed = (root.Position - info.Pos).Magnitude / dt
			if speed > FlyCfg.MaxServerSpeed * 2 then
				-- far beyond fly speed: a teleport (travel/portal) or tampering
				stopFly(player, "Flight ended.")
			elseif root.Position.Y - info.BaseY > FlyCfg.MaxHeight then
				stopFly(player, "You can't fly any higher.")
			else
				info.Pos = root.Position
				info.Time = now
			end
		end
	end
end

local function hookCharacter(player: Player, char: Model)
	stopFly(player) -- flight never carries over to a new character
	local hum = char:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		hum.Died:Connect(function()
			stopFly(player)
		end)
		baseStats[player] = { WalkSpeed = hum.WalkSpeed, JumpPower = hum.JumpPower, JumpHeight = hum.JumpHeight }
		applyPowers(player) -- powers the player left switched on carry over a respawn
	end
end

-- ── Powers: Fast Walk / High Jump (Game Passes the player switches on/off) ──
-- Server-applied. Heists/jail always win (HeistService sets its own speeds).
local NORMAL_SPEED = 16

local function powersAllowed(player: Player): boolean
	return player:GetAttribute("InHeist") ~= true and not JailService.IsJailed(player)
end

applyPowers = function(player: Player)
	local _, hum = character(player)
	local base = baseStats[player]
	if not hum or not base then
		return
	end
	local on = powerOn[player] or {}
	local allowed = powersAllowed(player)
	local speed = Monetization.Powers.FastWalk
	local jump = Monetization.Powers.HighJump
	local wantSpeed = allowed and on.FastWalk == true and MonetizationService.Owns(player, "FastWalk")
	local wantJump = allowed and on.HighJump == true and MonetizationService.Owns(player, "HighJump")
	if wantSpeed then
		if hum.WalkSpeed <= NORMAL_SPEED + 0.5 then -- don't override other systems' own speeds
			hum.WalkSpeed = speed.WalkSpeed :: number
		end
	elseif hum.WalkSpeed == speed.WalkSpeed then
		hum.WalkSpeed = base.WalkSpeed
	end
	if hum.UseJumpPower then
		hum.JumpPower = if wantJump then jump.JumpPower :: number else base.JumpPower
	else
		hum.JumpHeight = if wantJump then jump.JumpHeight :: number else base.JumpHeight
	end
end

function MonetizationService.SetPower(player: Player, key: any, enabled: any): (boolean, string?)
	if not Net.IsString(key, 24) or type(enabled) ~= "boolean" then
		return false, "Invalid request"
	end
	local power = Monetization.Powers[key]
	if not power then
		return false, "Invalid request"
	end
	local now = os.clock()
	if now - (lastToggle[player] or 0) < FlyCfg.ToggleCooldown then
		return false, "Not so fast!"
	end
	lastToggle[player] = now
	if enabled then
		if not MonetizationService.Owns(player, power.Pass) then
			return false, "Get this power in the Robux Store first."
		end
		if not powersAllowed(player) then
			return false, "Powers are disabled during heists and in jail."
		end
	end
	powerOn[player] = powerOn[player] or {}
	powerOn[player][key] = enabled
	player:SetAttribute("Power_" .. key, if enabled then true else nil)
	applyPowers(player)
	return true, nil
end

-- ── Developer Product receipts ─────────────────────────────────────────────
-- true = safely written to the player's save (or running in Studio without
-- DataStore access, where nothing can be durable anyway).
local function persist(player: Player): boolean
	if not PlayerDataService.IsDurable() then
		return true
	end
	return PlayerDataService.SaveNow(player)
end

local function processReceipt(info: { [string]: any }): Enum.ProductPurchaseDecision
	local notYet = Enum.ProductPurchaseDecision.NotProcessedYet
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then
		return notYet -- player left; Roblox offers the receipt again when they return
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return notYet -- save not loaded yet; never grant onto an unloaded profile
	end
	local premium = data.Premium
	local receiptId = tostring(info.PurchaseId)

	if premium.Receipts[receiptId] then
		-- Already granted earlier (e.g. Roblox is retrying). Make sure it is saved, then confirm.
		return if persist(player) then Enum.ProductPurchaseDecision.PurchaseGranted else notYet
	end
	if processing[receiptId] then
		return notYet
	end
	processing[receiptId] = true

	local ok, decision = pcall(function(): Enum.ProductPurchaseDecision
		local def = Monetization.ProductById(info.ProductId)
		if not def then
			warn(("[Monetization] Receipt for unknown ProductId %s — check Shared/Monetization.luau"):format(tostring(info.ProductId)))
			return notYet
		end
		-- Validate every grant BEFORE changing anything, so a bundle is all-or-nothing.
		for _, g in def.Grants do
			local item = ItemCatalog.Get(g.ItemId)
			if not item or not item.Gadget then
				warn(("[Monetization] %s grants unknown/non-gadget item %s"):format(def.Key, g.ItemId))
				return notYet
			end
		end
		if def.Cash ~= nil and not (def.Cash > 0 and def.Cash % 1 == 0) then
			warn(("[Monetization] %s has an invalid Cash amount"):format(def.Key))
			return notYet
		end
		-- No yields from here to the save call: grant and receipt are one atomic change.
		if def.Cash then
			if not EconomyService.Add(player, def.Cash, "Robux:" .. def.Key) then
				return notYet
			end
		end
		for _, g in def.Grants do
			for _ = 1, g.Count do
				InventoryService.Grant(player, g.ItemId, "Shop", { Provenance = "Robux purchase: " .. def.Name, IgnoreCapacity = true })
			end
		end
		premium.Receipts[receiptId] = true
		table.insert(premium.ReceiptLog, receiptId)
		while #premium.ReceiptLog > Monetization.MaxStoredReceipts do
			premium.Receipts[table.remove(premium.ReceiptLog, 1) :: string] = nil
		end
		StateSync.Mark(player)
		if not persist(player) then
			return notYet -- receipt stays recorded in memory, so the retry cannot double-grant
		end
		notify(player, if def.Cash then ("%s: +$%d added!"):format(def.Name, def.Cash) else ("Purchased %s! Check your Inventory."):format(def.Name), "Success")
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end)
	processing[receiptId] = nil
	if not ok then
		warn("[Monetization] Receipt error: " .. tostring(decision))
		return notYet
	end
	return decision
end

-- ── Purchase prompts (server-initiated; the client never confirms anything) ─
function MonetizationService.PromptPurchase(player: Player, kind: any, key: any): (boolean, string?)
	if not Net.IsString(kind, 12) or not Net.IsString(key, 40) then
		return false, "Invalid request"
	end
	local now = os.clock()
	if now - (lastPrompt[player] or 0) < 1.5 then
		return false, "One moment..."
	end
	lastPrompt[player] = now
	if kind == "Pass" then
		local def = Monetization.Passes[key]
		if not def or not Monetization.IsConfigured(def) then
			return false, "This item isn't available yet."
		end
		if MonetizationService.Owns(player, def.Key) then
			return false, "You already own this!"
		end
		MarketplaceService:PromptGamePassPurchase(player, def.Id)
		return true, nil
	elseif kind == "Product" then
		local def = Monetization.Products[key] or Monetization.CashPacks[key]
		if not def or not Monetization.IsConfigured(def) then
			return false, "This item isn't available yet."
		end
		MarketplaceService:PromptProductPurchase(player, def.Id)
		return true, nil
	end
	return false, "Invalid request"
end

function MonetizationService.Init() end

function MonetizationService.Start()
	StateSync.AddProvider(function(player, _data, snapshot)
		local ownedKeys = {}
		for key in Monetization.Passes do
			ownedKeys[key] = MonetizationService.Owns(player, key)
		end
		snapshot.Premium = { Fly = ownedKeys.FlyMode == true, Owned = ownedKeys }
	end)

	Net.Handle("PromptPurchase", MonetizationService.PromptPurchase)
	Net.Handle("SetFly", MonetizationService.SetFly)
	Net.Handle("SetPower", MonetizationService.SetPower)

	MarketplaceService.ProcessReceipt = processReceipt

	-- Roblox tells the SERVER when a Game Pass purchase finishes. Only a real,
	-- completed purchase of a pass in our config unlocks anything.
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player: Player, passId: number, wasPurchased: boolean)
		if not wasPurchased or not owned[player] then
			return -- cancelled or failed: nothing is granted
		end
		for key, def in Monetization.Passes do
			if Monetization.IsConfigured(def) and def.Id == passId then
				setOwned(player, key)
				notify(player, ("%s unlocked!"):format(def.Name), "Success")
			end
		end
	end)

	local function onPlayer(player: Player)
		owned[player] = {}
		player.CharacterAdded:Connect(function(char)
			hookCharacter(player, char)
		end)
		player.CharacterRemoving:Connect(function()
			stopFly(player)
		end)
		if player.Character then
			task.spawn(hookCharacter, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, p in Players:GetPlayers() do
		onPlayer(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		stopFly(player)
		owned[player] = nil
		lastPrompt[player] = nil
		lastToggle[player] = nil
		powerOn[player] = nil
		baseStats[player] = nil
	end)

	-- Verify Game Pass ownership as soon as the player's save is loaded (also covers rejoining).
	PlayerDataService.OnLoaded(function(player)
		if owned[player] then
			verifyAll(player)
		end
	end)

	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc >= 0.4 then
			acc = 0
			watchdog()
		end
	end)
end

return MonetizationService
