--!strict
--[[
	MarketCore (pure logic, no Roblox APIs — unit-tested in tests/run_tests.luau)

	The Collectors' Market keeps each listing in ONE DataStore key. All status
	changes are single-key compare-and-set operations (UpdateAsync), so a
	listing can never be sold twice or sold after it was cancelled.

	Listing life-cycle:   Active ──▶ Sold | Cancelled | Expired
	                      (missing) ──▶ Void   (tombstone: a lost create can
	                                            never appear later)

	Item safety: while listed, the item STAYS in the seller's inventory with
	Reserved = { Kind = "Listing" }, so it can't be used, displayed, traded or
	stolen. When the seller's server sees "Sold" it removes the item and pays
	the seller (price − fee) in the same save — idempotent because the listing
	id is removed from data.Listings in that same save.

	Money safety: the buyer pays FIRST and the debt is saved as
	data.PendingPurchases[id]. After the compare-and-set:
	  • Sold to me  › item granted + pending removed (same save)
	  • otherwise   › refunded + pending removed (same save)
	If the server crashes in between, the next load re-checks the listing and
	does exactly one of those.
]]

local MarketCore = {}

export type ListingDoc = {
	Id: string,
	Status: string,
	Seller: number,
	SellerName: string,
	Item: { [string]: any },
	ItemId: string,
	Price: number,
	Fee: number,
	Created: number,
	Expires: number,
	Buyer: number?,
	BuyerName: string?,
	SoldAt: number?,
}

local function copy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[k] = copy(v)
	end
	return out
end

function MarketCore.Fee(price: number, rate: number): number
	return math.floor(price * rate)
end

function MarketCore.PriceBounds(value: number, minRate: number, maxRate: number, absoluteMax: number): (number, number)
	local low = math.max(10, math.floor(value * minRate))
	local high = math.min(absoluteMax, math.max(low, math.floor(value * maxRate)))
	return low, high
end

function MarketCore.NewListingDoc(id: string, sellerId: number, sellerName: string, item: { [string]: any }, price: number, feeRate: number, now: number, days: number): ListingDoc
	local snapshot = copy(item)
	snapshot.Reserved = nil
	snapshot.Locked = false
	return {
		Id = id,
		Status = "Active",
		Seller = sellerId,
		SellerName = sellerName,
		Item = snapshot,
		ItemId = item.Id,
		Price = price,
		Fee = MarketCore.Fee(price, feeRate),
		Created = now,
		Expires = now + days * 86400,
	}
end

-- UpdateAsync transforms: return the new document, or nil to leave it as is.
function MarketCore.CreateIfAbsent(old: any, doc: ListingDoc): ListingDoc?
	if old ~= nil then
		return nil
	end
	return doc
end

function MarketCore.VoidIfMissing(old: any): any
	if old == nil then
		return { Status = "Void" }
	end
	return nil
end

function MarketCore.PurchaseTransition(old: any, buyerId: number, buyerName: string, now: number): (any, string?)
	if type(old) ~= "table" or old.Status ~= "Active" then
		return nil, "That listing is no longer available"
	end
	if old.Seller == buyerId then
		return nil, "You can't buy your own listing"
	end
	if now >= old.Expires then
		return nil, "That listing has expired"
	end
	local new = copy(old)
	new.Status = "Sold"
	new.Buyer = buyerId
	new.BuyerName = buyerName
	new.SoldAt = now
	return new, nil
end

function MarketCore.CancelTransition(old: any, sellerId: number): (any, string?)
	if type(old) ~= "table" or old.Status ~= "Active" then
		return nil, "That listing can't be cancelled now"
	end
	if old.Seller ~= sellerId then
		return nil, "That isn't your listing"
	end
	local new = copy(old)
	new.Status = "Cancelled"
	return new, nil
end

function MarketCore.ExpireTransition(old: any, now: number): any
	if type(old) == "table" and old.Status == "Active" and now >= old.Expires then
		local new = copy(old)
		new.Status = "Expired"
		return new
	end
	return nil
end

local function pushHistory(data: any, entry: { [string]: any }, maxLength: number)
	data.MarketHistory = data.MarketHistory or {}
	table.insert(data.MarketHistory, 1, entry)
	while #data.MarketHistory > maxLength do
		table.remove(data.MarketHistory)
	end
end

export type SettleResult = { Kind: string, Payout: number }

-- Seller side. `doc` = current listing document (nil = not found).
function MarketCore.SettleSeller(data: any, listingId: string, doc: any, now: number, historyLength: number): SettleResult
	local record = data.Listings[listingId]
	if not record then
		return { Kind = "None", Payout = 0 }
	end
	local uid = record.Uid
	local function release()
		local item = uid and data.Inventory[uid]
		if item and item.Reserved and item.Reserved.Kind == "Listing" and item.Reserved.Id == listingId then
			item.Reserved = nil
		end
		data.Listings[listingId] = nil
	end
	if type(doc) ~= "table" then
		return { Kind = "Missing", Payout = 0 }
	end
	if doc.Status == "Sold" then
		local item = uid and data.Inventory[uid]
		if item and item.Reserved and item.Reserved.Kind == "Listing" and item.Reserved.Id == listingId then
			data.Inventory[uid] = nil
			for slotId, displayed in data.Displays do
				if displayed == uid then
					data.Displays[slotId] = nil
				end
			end
		end
		local payout = math.max(0, (doc.Price or 0) - (doc.Fee or 0))
		data.Cash = (data.Cash or 0) + payout
		data.Listings[listingId] = nil
		if data.Stats then
			data.Stats.MarketSales = (data.Stats.MarketSales or 0) + 1
		end
		pushHistory(data, { Kind = "Sold", ItemId = doc.ItemId, Price = doc.Price, Fee = doc.Fee, Other = doc.BuyerName or "?", Time = doc.SoldAt or now }, historyLength)
		return { Kind = "Sold", Payout = payout }
	elseif doc.Status == "Cancelled" or doc.Status == "Expired" or doc.Status == "Void" then
		release()
		return { Kind = "Returned", Payout = 0 }
	end
	return { Kind = "Active", Payout = 0 }
end

-- Buyer side for a pending (already paid) purchase.
function MarketCore.ResolvePurchase(data: any, listingId: string, doc: any, buyerId: number, now: number, historyLength: number): string
	local pending = data.PendingPurchases[listingId]
	if not pending then
		return "None"
	end
	if type(doc) == "table" and doc.Status == "Sold" and doc.Buyer == buyerId then
		local item = doc.Item
		if type(item) == "table" and type(item.Uid) == "string" and data.Inventory[item.Uid] == nil then
			local granted = copy(item)
			granted.Reserved = nil
			granted.Locked = false
			granted.Provenance = ("Bought from %s on the Collectors' Market"):format(tostring(doc.SellerName))
			data.Inventory[item.Uid] = granted
		end
		data.PendingPurchases[listingId] = nil
		if data.Stats then
			data.Stats.MarketPurchases = (data.Stats.MarketPurchases or 0) + 1
		end
		pushHistory(data, { Kind = "Bought", ItemId = doc.ItemId, Price = doc.Price, Other = doc.SellerName or "?", Time = doc.SoldAt or now }, historyLength)
		return "Granted"
	end
	-- Not sold to us (still active, cancelled, sold to someone else, missing)
	data.Cash = (data.Cash or 0) + (pending.Price or 0)
	data.PendingPurchases[listingId] = nil
	return "Refunded"
end

return MarketCore
