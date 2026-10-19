--[[
	InventoryService
	Creates, removes, sells, locks and reserves item INSTANCES.

	Every instance has a unique server-generated Uid. An instance lives in
	exactly ONE place: its owner's Inventory table.

	Item states (all checked here, used everywhere):
	  • free       — owned, not displayed, not reserved
	  • displayed  — its Uid is in Displays (never copied)
	  • reserved   — item.Reserved = { Kind, Id }:
	      Listing (on the market), Trade (in a trade offer),
	      Heist (being stolen right now), Loadout (gadget taken on a heist)
	A reserved item can't be sold, displayed, listed, traded or stolen.
]]

local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.ItemCatalog)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local ProgressionService = require(script.Parent.ProgressionService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)

local InventoryService = {}

local bonusCapacity: { [any]: number } = setmetatable({}, { __mode = "k" }) :: any

export type GrantOptions = {
	Condition: string?,
	Provenance: string?,
	Charges: number?,
	Bound: boolean?,
	IgnoreCapacity: boolean?,
}

function InventoryService.NewUid(data: any): string
	local uid = HttpService:GenerateGUID(false)
	while data.Inventory[uid] do
		uid = HttpService:GenerateGUID(false)
	end
	return uid
end

function InventoryService.SetBonusCapacity(data: any, amount: number)
	bonusCapacity[data] = amount
end

function InventoryService.Capacity(data: any): number
	local level = ProgressionService.GetLevel(data)
	return Config.BaseInventoryCapacity + Config.InventoryCapacityPerLevel * (level - 1) + (bonusCapacity[data] or 0)
end

function InventoryService.DisplayedSlotOf(data: any, uid: string): string?
	for slotId, displayedUid in data.Displays do
		if displayedUid == uid then
			return slotId
		end
	end
	return nil
end

-- Number of artefacts in storage (not on display, gadgets don't count).
function InventoryService.StorageCount(data: any): number
	local displayed: { [string]: boolean } = {}
	for _, uid in data.Displays do
		displayed[uid] = true
	end
	local count = 0
	for uid, item in data.Inventory do
		local def = ItemCatalog.Get(item.Id)
		if not displayed[uid] and not ItemCatalog.IsGadget(def) then
			count += 1
		end
	end
	return count
end

function InventoryService.HasSpace(data: any, extra: number?): boolean
	return InventoryService.StorageCount(data) + (extra or 1) <= InventoryService.Capacity(data)
end

function InventoryService.Get(player: Player, uid: any): any?
	local data = PlayerDataService.GetData(player)
	if not data or type(uid) ~= "string" then
		return nil
	end
	return data.Inventory[uid]
end

-- Owned, not displayed, not reserved (or reserved by exactly this kind/id).
function InventoryService.IsFree(data: any, uid: string, allowKind: string?, allowId: string?): boolean
	local item = data.Inventory[uid]
	if not item then
		return false
	end
	if item.Reserved then
		if not (allowKind and item.Reserved.Kind == allowKind and item.Reserved.Id == allowId) then
			return false
		end
	end
	return InventoryService.DisplayedSlotOf(data, uid) == nil
end

-- Can this instance ever change owner (market / trade)?
function InventoryService.IsTransferable(item: any): (boolean, string?)
	local def = ItemCatalog.Get(item.Id)
	if not def then
		return false, "Unknown item"
	end
	if not def.Tradable then
		return false, def.Name .. " can't be traded"
	end
	if item.Bound then
		return false, def.Name .. " is account-bound"
	end
	if item.Locked then
		return false, "Unlock " .. def.Name .. " first (it's protected)"
	end
	return true, nil
end

function InventoryService.Reserve(data: any, uid: string, kind: string, id: string): boolean
	local item = data.Inventory[uid]
	if not item or item.Reserved then
		return false
	end
	item.Reserved = { Kind = kind, Id = id }
	return true
end

function InventoryService.Release(data: any, uid: string, kind: string, id: string)
	local item = data.Inventory[uid]
	if item and item.Reserved and item.Reserved.Kind == kind and item.Reserved.Id == id then
		item.Reserved = nil
	end
end

-- Releases every reservation of this kind/id (e.g. when a trade is cancelled).
function InventoryService.ReleaseAll(data: any, kind: string, id: string)
	for _, item in data.Inventory do
		if item.Reserved and item.Reserved.Kind == kind and item.Reserved.Id == id then
			item.Reserved = nil
		end
	end
end

-- Takes an item off display (used before listing/trading).
function InventoryService.Undisplay(data: any, uid: string): boolean
	local slotId = InventoryService.DisplayedSlotOf(data, uid)
	if slotId then
		data.Displays[slotId] = nil
		data.DisplayRot[slotId] = nil
		return true
	end
	return false
end

-- Removes an instance completely (and from any display).
function InventoryService.Remove(data: any, uid: string)
	InventoryService.Undisplay(data, uid)
	data.Inventory[uid] = nil
end

function InventoryService.ValueOf(item: any): number
	local def = ItemCatalog.Get(item.Id)
	if not def then
		return 0
	end
	return ItemCatalog.InstanceValue(def, item.Condition, item.Charges)
end

-- Creates a brand-new item instance for the player. Server only.
function InventoryService.Grant(player: Player, itemId: string, zoneId: string, options: GrantOptions?): (any?, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return nil, "Data not loaded"
	end
	local def = ItemCatalog.Get(itemId)
	if not def then
		return nil, "Unknown item"
	end
	local opts: GrantOptions = options or {}
	if not opts.IgnoreCapacity and not ItemCatalog.IsGadget(def) and not InventoryService.HasSpace(data) then
		return nil, "Your storage is full"
	end
	local uid = InventoryService.NewUid(data)
	local instance = {
		Uid = uid,
		Id = itemId,
		Found = os.time(),
		Zone = zoneId,
		Locked = false,
		Condition = if def.Gadget then nil else (opts.Condition or "Clean"),
		Provenance = opts.Provenance,
		Charges = if def.Gadget then (opts.Charges or def.Gadget.Charges) else nil,
		Bound = opts.Bound,
		Reserved = nil,
	}
	data.Inventory[uid] = instance
	if not def.Gadget then
		data.Stats.ItemsFound += 1
		ProgressionService.RecordDiscovery(player, itemId)
	end
	StateSync.Mark(player)
	return instance, nil
end

-- Uses one charge of a gadget. Returns remaining charges (item removed at 0).
function InventoryService.UseCharge(player: Player, uid: string): number
	local data = PlayerDataService.GetData(player)
	local item = data and data.Inventory[uid]
	if not data or not item or not item.Charges then
		return 0
	end
	item.Charges -= 1
	local left = item.Charges
	if left <= 0 then
		data.Inventory[uid] = nil
	end
	StateSync.Mark(player)
	return math.max(0, left)
end

-- Sells an item to the NPC buyer.
function InventoryService.Sell(player: Player, uid: any): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded"
	end
	if PlayerDataService.IsBusy(player) then
		return false, "Finishing a transfer, try again in a moment"
	end
	if not Net.IsString(uid, 64) then
		return false, "Invalid item"
	end
	local item = data.Inventory[uid]
	if not item then
		return false, "You don't own that item"
	end
	local def = ItemCatalog.Get(item.Id)
	if not def then
		return false, "Unknown item"
	end
	if not def.Sellable then
		return false, "This item can't be sold"
	end
	if item.Locked then
		return false, "Unlock the item before selling it"
	end
	if item.Reserved then
		return false, "That item is busy (" .. item.Reserved.Kind .. ")"
	end
	if InventoryService.DisplayedSlotOf(data, uid) then
		return false, "Remove it from display first"
	end
	local price = math.floor(InventoryService.ValueOf(item) * Config.NpcSellRate)
	-- Remove FIRST, then pay — the item can never be sold twice.
	data.Inventory[uid] = nil
	data.Stats.ItemsSold += 1
	EconomyService.Add(player, price, "NpcSell:" .. def.Id)
	StateSync.Mark(player)
	return true, ("Sold %s for %s"):format(def.Name, Format.Cash(price))
end

function InventoryService.ToggleLock(player: Player, uid: any): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded"
	end
	if not Net.IsString(uid, 64) then
		return false, "Invalid item"
	end
	local item = data.Inventory[uid]
	if not item then
		return false, "You don't own that item"
	end
	if item.Reserved then
		return false, "That item is busy right now"
	end
	item.Locked = not item.Locked
	StateSync.Mark(player)
	return true, if item.Locked then "Item locked (protected from selling and trading)" else "Item unlocked"
end

function InventoryService.Init() end

function InventoryService.Start()
	Net.Handle("SellItem", InventoryService.Sell)
	Net.Handle("ToggleLock", InventoryService.ToggleLock)

	StateSync.AddProvider(function(_player, data, snapshot)
		snapshot.Capacity = InventoryService.Capacity(data)
		snapshot.StorageCount = InventoryService.StorageCount(data)
	end)

	-- One-time starter gift for brand-new players.
	PlayerDataService.OnLoaded(function(player, profile)
		local data = profile.Data
		if not data.StarterGranted then
			data.StarterGranted = true
			for _, itemId in Config.StarterItems do
				InventoryService.Grant(player, itemId, "Starter", { IgnoreCapacity = true, Provenance = "A gift for your new museum" })
			end
		end
	end)
end

return InventoryService
