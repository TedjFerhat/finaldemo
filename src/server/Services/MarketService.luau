--[[
	MarketService — the Collectors' Market
	List artefacts and heist gear for a price you choose; buy from other
	players across servers. All rules live in Core/MarketCore (pure, tested).

	Storage:
	  • Durable mode (published game / Studio with API access):
	      DataStore  MarketStoreName  key "L_<id>"  = the listing (source of truth)
	      MemoryStore SortedMap MarketIndexName     = browse index (rebuildable)
	      MessagingService "MarketSold"             = "your item sold" ping
	  • Local mode (Studio without API access): everything in this server's
	    memory — fine for testing, nothing persists.

	Rules: owner only; item must be tradable, not bound, not locked, not
	reserved (it's taken off display automatically); price within limits;
	max active listings; 5% fee on a sale (shown before listing); you can't
	buy your own listing.
]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local MemoryStoreService = game:GetService("MemoryStoreService")
local MessagingService = game:GetService("MessagingService")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.ItemCatalog)
local Rarities = require(Shared.Rarities)
local Format = require(Shared.Format)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local MuseumService = require(script.Parent.MuseumService)
local AchievementService = require(script.Parent.AchievementService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local MarketCore = require(script.Parent.Parent.Core.MarketCore)

local MarketService = {}

local MC = Config.Market
local TOPIC = "MarketSold"

-- ── Backend ────────────────────────────────────────────────────────────────
type Backend = {
	Get: (string) -> (boolean, any),
	Update: (string, (any) -> any) -> (boolean, any),
	IndexPut: (any) -> (),
	IndexRemove: (string) -> (),
	IndexAll: () -> { any },
}

local backend: Backend = nil :: any
local durable = false
local localDocs: { [string]: any } = {}
local localIndex: { [string]: any } = {}

local function deepCopy(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		out[k] = deepCopy(x)
	end
	return out
end

local function makeLocalBackend(): Backend
	return {
		Get = function(id)
			return true, deepCopy(localDocs[id])
		end,
		Update = function(id, fn)
			local result = fn(deepCopy(localDocs[id]))
			if result ~= nil then
				localDocs[id] = deepCopy(result)
			end
			return true, deepCopy(localDocs[id])
		end,
		IndexPut = function(summary)
			localIndex[summary.Id] = summary
		end,
		IndexRemove = function(id)
			localIndex[id] = nil
		end,
		IndexAll = function()
			local list = {}
			for _, s in localIndex do
				table.insert(list, s)
			end
			return list
		end,
	}
end

local function makeDurableBackend(): Backend
	local store = DataStoreService:GetDataStore(Config.MarketStoreName)
	local indexOk, index = pcall(function()
		return MemoryStoreService:GetSortedMap(Config.MarketIndexName)
	end)
	if not indexOk then
		warn("[Market] MemoryStore unavailable; browsing will only show listings made on this server.")
	end
	local function retry<T>(fn: () -> T): (boolean, T?)
		for attempt = 1, 3 do
			local ok, result = pcall(fn)
			if ok then
				return true, result
			end
			warn("[Market] DataStore error: " .. tostring(result))
			task.wait(attempt)
		end
		return false, nil
	end
	return {
		Get = function(id)
			return retry(function()
				return store:GetAsync("L_" .. id)
			end)
		end,
		Update = function(id, fn)
			return retry(function()
				return store:UpdateAsync("L_" .. id, fn)
			end)
		end,
		IndexPut = function(summary)
			localIndex[summary.Id] = summary
			if indexOk then
				pcall(function()
					index:SetAsync(summary.Id, summary, MC.ListingDays * 86400)
				end)
			end
		end,
		IndexRemove = function(id)
			localIndex[id] = nil
			if indexOk then
				pcall(function()
					index:RemoveAsync(id)
				end)
			end
		end,
		IndexAll = function()
			if not indexOk then
				local list = {}
				for _, s in localIndex do
					table.insert(list, s)
				end
				return list
			end
			local ok, entries = pcall(function()
				return index:GetRangeAsync(Enum.SortDirection.Descending, 200)
			end)
			local list = {}
			if ok and type(entries) == "table" then
				for _, entry in entries do
					if type(entry.value) == "table" then
						table.insert(list, entry.value)
					end
				end
			end
			return list
		end,
	}
end

-- ── Helpers ────────────────────────────────────────────────────────────────
local function summaryOf(doc: any): { [string]: any }
	return {
		Id = doc.Id,
		ItemId = doc.ItemId,
		Price = doc.Price,
		Seller = doc.Seller,
		SellerName = doc.SellerName,
		Condition = doc.Item and doc.Item.Condition,
		Charges = doc.Item and doc.Item.Charges,
		Created = doc.Created,
		Expires = doc.Expires,
	}
end

local function save(player: Player): boolean
	if not durable then
		return true
	end
	return PlayerDataService.SaveNow(player)
end

local function notifyMarket(player: Player)
	Net.Fire("MarketChanged", player)
	StateSync.Mark(player)
end

local inFlight: { [Player]: boolean } = {}

-- ── Seller settlement ──────────────────────────────────────────────────────
local function settle(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	local now = os.time()
	local changed = false
	for id, record in data.Listings do
		local ok, doc = backend.Get(id)
		if ok then
			if doc == nil then
				-- Created long enough ago and still missing › tombstone it, then release.
				if record.Uncertain or now - (record.Created or now) > 60 then
					local okVoid, current = backend.Update(id, MarketCore.VoidIfMissing)
					if okVoid then
						doc = current
					end
				end
			elseif doc.Status == "Active" and now >= (doc.Expires or math.huge) then
				local okExp, current = backend.Update(id, function(old)
					return MarketCore.ExpireTransition(old, now)
				end)
				if okExp then
					doc = current
					backend.IndexRemove(id)
				end
			end
			local result = MarketCore.SettleSeller(data, id, doc, now, MC.HistoryLength)
			if result.Kind == "Sold" then
				changed = true
				local def = ItemCatalog.Get(doc.ItemId)
				Notifier.Send(player, ("Sold on the market: %s for %s (you received %s after the %d%% fee)."):format(def and def.Name or "item", Format.Cash(doc.Price), Format.Cash(result.Payout), math.floor(MC.FeeRate * 100)), "Reward")
				AchievementService.Award(player, "market_sale")
				data.Stats.TotalEarned += result.Payout
			elseif result.Kind == "Returned" then
				changed = true
			end
		end
	end
	if changed then
		MuseumService.RefreshAll(player)
		save(player)
		notifyMarket(player)
	end
end

-- ── Buyer recovery (only for purchases that are NOT in flight) ────────────
local function resolvePending(player: Player)
	local data = PlayerDataService.GetData(player)
	if not data or inFlight[player] then
		return
	end
	local changed = false
	for id in data.PendingPurchases do
		local ok, doc = backend.Get(id)
		if ok then
			local kind = MarketCore.ResolvePurchase(data, id, doc, player.UserId, os.time(), MC.HistoryLength)
			if kind ~= "None" then
				changed = true
				if kind == "Granted" then
					Notifier.Send(player, "A market purchase was completed.", "Success")
				else
					Notifier.Send(player, "A market purchase didn't go through — you were refunded.", "Info")
				end
			end
		end
	end
	if changed then
		save(player)
		notifyMarket(player)
	end
end

-- ── Create / cancel / buy ──────────────────────────────────────────────────
function MarketService.Create(player: Player, uid: any, price: any): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded"
	end
	if PlayerDataService.IsBusy(player) or inFlight[player] then
		return false, "Please wait a moment"
	end
	if player:GetAttribute("InHeist") or player:GetAttribute("InTrade") then
		return false, "Finish your heist or trade first"
	end
	if not Net.IsString(uid, 64) or not Net.IsInt(price, 1, MC.AbsoluteMaxPrice) then
		return false, "Invalid listing"
	end
	local item = data.Inventory[uid]
	if not item then
		return false, "You don't own that item"
	end
	local okTransfer, why = InventoryService.IsTransferable(item)
	if not okTransfer then
		return false, why
	end
	if item.Reserved then
		return false, "That item is busy (" .. item.Reserved.Kind .. ")"
	end
	local count = 0
	for _ in data.Listings do
		count += 1
	end
	if count >= MC.MaxActiveListings then
		return false, ("You can have at most %d active listings"):format(MC.MaxActiveListings)
	end
	local def = ItemCatalog.Get(item.Id) :: any
	local low, high = MarketCore.PriceBounds(InventoryService.ValueOf(item), MC.MinPriceRate, MC.MaxPriceRate, MC.AbsoluteMaxPrice)
	if price < low or price > high then
		return false, ("Price must be between %s and %s"):format(Format.Cash(low), Format.Cash(high))
	end

	inFlight[player] = true
	local id = HttpService:GenerateGUID(false)
	local wasDisplayed = InventoryService.Undisplay(data, uid)
	InventoryService.Reserve(data, uid, "Listing", id)
	data.Listings[id] = { Uid = uid, ItemId = item.Id, Price = price, Created = os.time() }
	if wasDisplayed then
		MuseumService.RefreshAll(player)
	end
	if not save(player) then
		InventoryService.Release(data, uid, "Listing", id)
		data.Listings[id] = nil
		inFlight[player] = nil
		notifyMarket(player)
		return false, "Couldn't save right now. Nothing was listed."
	end
	local doc = MarketCore.NewListingDoc(id, player.UserId, player.DisplayName, item, price, MC.FeeRate, os.time(), MC.ListingDays)
	local ok = backend.Update(id, function(old)
		return MarketCore.CreateIfAbsent(old, doc)
	end)
	inFlight[player] = nil
	if not ok then
		-- Unknown outcome: settlement will confirm or void it safely.
		data.Listings[id].Uncertain = true
		notifyMarket(player)
		return false, "The market is busy — your listing will be confirmed or returned shortly."
	end
	backend.IndexPut(summaryOf(doc))
	notifyMarket(player)
	return true, ("Listed %s for %s (fee on sale: %s)"):format(def.Name, Format.Cash(price), Format.Cash(doc.Fee))
end

function MarketService.Cancel(player: Player, id: any): (boolean, string?)
	local data = PlayerDataService.GetData(player)
	if not data or not Net.IsString(id, 64) or not data.Listings[id] then
		return false, "That isn't one of your listings"
	end
	if inFlight[player] then
		return false, "Please wait a moment"
	end
	inFlight[player] = true
	local reason: string? = nil
	local ok, doc = backend.Update(id, function(old)
		local new, why = MarketCore.CancelTransition(old, player.UserId)
		reason = why
		return new
	end)
	inFlight[player] = nil
	if not ok then
		return false, "The market is busy, try again"
	end
	backend.IndexRemove(id)
	local result = MarketCore.SettleSeller(data, id, doc, os.time(), MC.HistoryLength)
	save(player)
	notifyMarket(player)
	if result.Kind == "Sold" then
		return false, "Too late — it already sold! You've been paid."
	elseif result.Kind == "Returned" then
		return true, "Listing cancelled. The item is back in your storage."
	end
	return false, reason or "Couldn't cancel that listing"
end

function MarketService.Buy(buyer: Player, id: any): (boolean, string?)
	local data = PlayerDataService.GetData(buyer)
	if not data or not Net.IsString(id, 64) then
		return false, "Invalid listing"
	end
	if PlayerDataService.IsBusy(buyer) or inFlight[buyer] then
		return false, "Please wait a moment"
	end
	if data.PendingPurchases[id] then
		return false, "That purchase is already being processed"
	end
	local okGet, doc = backend.Get(id)
	if not okGet or type(doc) ~= "table" or doc.Status ~= "Active" or os.time() >= doc.Expires then
		backend.IndexRemove(id)
		return false, "That listing is no longer available"
	end
	if doc.Seller == buyer.UserId then
		return false, "You can't buy your own listing"
	end
	local def = ItemCatalog.Get(doc.ItemId)
	if not def then
		return false, "Unknown item"
	end
	if not def.Gadget and not InventoryService.HasSpace(data) then
		return false, "Your storage is full"
	end
	local price = doc.Price -- from the authoritative listing, never from the client
	if data.Cash < price then
		return false, ("You need %s"):format(Format.Cash(price))
	end

	inFlight[buyer] = true
	-- 1. Pay first and record the debt in the same save.
	data.Cash -= price
	data.PendingPurchases[id] = { Price = price, Time = os.time() }
	StateSync.Mark(buyer)
	if not save(buyer) then
		data.Cash += price
		data.PendingPurchases[id] = nil
		inFlight[buyer] = nil
		StateSync.Mark(buyer)
		return false, "Couldn't save right now. You weren't charged."
	end
	-- 2. Single-key compare-and-set on the listing.
	local reason: string? = nil
	local okUpdate, current = backend.Update(id, function(old)
		local new, why = MarketCore.PurchaseTransition(old, buyer.UserId, buyer.DisplayName, os.time())
		reason = why
		return new
	end)
	if not okUpdate then
		inFlight[buyer] = nil
		task.delay(20, resolvePending, buyer)
		return false, "The market is busy — your purchase will complete or be refunded shortly."
	end
	-- 3. Grant or refund (same save as removing the pending debt).
	local kind = MarketCore.ResolvePurchase(data, id, current, buyer.UserId, os.time(), MC.HistoryLength)
	inFlight[buyer] = nil
	save(buyer)
	notifyMarket(buyer)
	if kind ~= "Granted" then
		return false, reason or "That listing is no longer available. You were refunded."
	end
	backend.IndexRemove(id)
	AchievementService.Award(buyer, "market_purchase")
	-- Tell the seller (same server: settle now; otherwise ping their server).
	local seller = Players:GetPlayerByUserId(doc.Seller)
	if seller then
		task.spawn(settle, seller)
	elseif durable then
		task.spawn(function()
			pcall(function()
				MessagingService:PublishAsync(TOPIC, { Seller = doc.Seller, Id = id })
			end)
		end)
	end
	return true, ("Bought %s for %s!"):format(def.Name, Format.Cash(price))
end

-- ── Browse & my listings ───────────────────────────────────────────────────
local cache: { Time: number, List: { any } } = { Time = 0, List = {} }

local function allListings(): { any }
	if os.clock() - cache.Time > MC.IndexCacheSeconds then
		cache = { Time = os.clock(), List = backend.IndexAll() }
	end
	return cache.List
end

function MarketService.Browse(player: Player, query: any): (boolean, string?, any)
	local q = if type(query) == "table" then query else {}
	local search = if type(q.Search) == "string" then string.lower(string.sub(q.Search, 1, 40)) else ""
	local category = if type(q.Category) == "string" then q.Category else "All"
	local rarity = if type(q.Rarity) == "string" then q.Rarity else "All"
	local minPrice = if type(q.MinPrice) == "number" then q.MinPrice else 0
	local maxPrice = if type(q.MaxPrice) == "number" and q.MaxPrice > 0 then q.MaxPrice else math.huge
	local sort = if type(q.Sort) == "string" then q.Sort else "Newest"
	local page = if Net.IsInt(q.Page, 1, 1000) then q.Page else 1
	local now = os.time()

	local rows = {}
	for _, s in allListings() do
		local def = ItemCatalog.Get(s.ItemId)
		if def and now < (s.Expires or 0) then
			local ok = true
			if search ~= "" and not string.find(string.lower(def.Name), search, 1, true) then
				ok = false
			end
			if category ~= "All" and def.Category ~= category then
				ok = false
			end
			if rarity ~= "All" and def.Rarity ~= rarity then
				ok = false
			end
			if s.Price < minPrice or s.Price > maxPrice then
				ok = false
			end
			if ok then
				table.insert(rows, {
					Id = s.Id,
					ItemId = s.ItemId,
					Name = def.Name,
					Rarity = def.Rarity,
					Category = def.Category,
					Condition = s.Condition,
					Charges = s.Charges,
					Price = s.Price,
					SellerName = s.SellerName,
					IsMine = s.Seller == player.UserId,
					Created = s.Created,
				})
			end
		end
	end
	table.sort(rows, function(a, b)
		if sort == "PriceLow" and a.Price ~= b.Price then
			return a.Price < b.Price
		elseif sort == "PriceHigh" and a.Price ~= b.Price then
			return a.Price > b.Price
		elseif sort == "Rarity" and a.Rarity ~= b.Rarity then
			return Rarities.Order(a.Rarity) > Rarities.Order(b.Rarity)
		end
		return (a.Created or 0) > (b.Created or 0)
	end)
	local total = #rows
	local first = (page - 1) * MC.BrowsePageSize + 1
	local pageRows = {}
	for i = first, math.min(total, first + MC.BrowsePageSize - 1) do
		table.insert(pageRows, rows[i])
	end
	return true, nil, { Rows = pageRows, Total = total, Page = page, PageSize = MC.BrowsePageSize, Durable = durable }
end

function MarketService.Mine(player: Player): (boolean, string?, any)
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded", nil
	end
	local listings = {}
	for id, record in data.Listings do
		local item = data.Inventory[record.Uid]
		table.insert(listings, {
			Id = id,
			ItemId = record.ItemId,
			Price = record.Price,
			Created = record.Created,
			Uncertain = record.Uncertain,
			Condition = item and item.Condition,
		})
	end
	table.sort(listings, function(a, b)
		return (a.Created or 0) > (b.Created or 0)
	end)
	return true, nil, {
		Listings = listings,
		History = data.MarketHistory,
		FeeRate = MC.FeeRate,
		MaxListings = MC.MaxActiveListings,
		MinPriceRate = MC.MinPriceRate,
		MaxPriceRate = MC.MaxPriceRate,
		Durable = durable,
	}
end

function MarketService.Init()
	-- Load hook: settle sales and resolve purchases interrupted by a crash.
	PlayerDataService.AddLoadHook(function(player, profile)
		if profile.NoSave or not PlayerDataService.IsDurable() then
			return
		end
		backend = backend or makeDurableBackend()
		local data = profile.Data
		local now = os.time()
		for id in data.PendingPurchases do
			local ok, doc = backend.Get(id)
			if ok then
				MarketCore.ResolvePurchase(data, id, doc, player.UserId, now, MC.HistoryLength)
			end
		end
		for id, record in data.Listings do
			local ok, doc = backend.Get(id)
			if ok then
				if doc == nil and (record.Uncertain or now - (record.Created or now) > 60) then
					local okVoid, current = backend.Update(id, MarketCore.VoidIfMissing)
					if okVoid then
						doc = current
					end
				end
				MarketCore.SettleSeller(data, id, doc, now, MC.HistoryLength)
			end
		end
	end)
end

function MarketService.Start()
	task.spawn(function()
		durable = PlayerDataService.IsDurable()
		backend = if durable then makeDurableBackend() else makeLocalBackend()
		if durable then
			pcall(function()
				MessagingService:SubscribeAsync(TOPIC, function(message)
					local payload = message.Data
					local seller = type(payload) == "table" and Players:GetPlayerByUserId(payload.Seller)
					if seller then
						settle(seller)
					end
				end)
			end)
		end
	end)
	-- Requests wait until the backend is chosen (a moment after start-up).
	local function ready(fn: (Player, ...any) -> (boolean, string?, any?))
		return function(player: Player, ...: any)
			if not backend then
				return false, "The market is opening, try again in a moment"
			end
			return fn(player, ...)
		end
	end
	Net.Handle("MarketCreate", ready(MarketService.Create))
	Net.Handle("MarketCancel", ready(MarketService.Cancel))
	Net.Handle("MarketBuy", ready(MarketService.Buy))
	Net.Handle("MarketBrowse", ready(MarketService.Browse))
	Net.Handle("MarketMine", ready(MarketService.Mine))
	Players.PlayerRemoving:Connect(function(player)
		inFlight[player] = nil
	end)
	-- Periodic settlement (catches sales on other servers if a ping was missed)
	task.spawn(function()
		while true do
			task.wait(MC.SettleIntervalSeconds)
			if backend then
				for _, player in Players:GetPlayers() do
					local data = PlayerDataService.GetData(player)
					if data and (next(data.Listings) or next(data.PendingPurchases)) then
						pcall(settle, player)
						pcall(resolvePending, player)
					end
				end
			end
		end
	end)
end

return MarketService
