--[[
	Unit tests for the pure game logic (no Roblox needed).
	Run with the Luau CLI from the project root:
	    luau tests/run_tests.luau
	Covers: TxCore (ledger transfers), MarketCore (listings, purchases,
	settlement, crash recovery) and Minigame (server timing judgement).
]]

local TxCore = require("../src/server/Core/TxCore")
local MarketCore = require("../src/server/Core/MarketCore")
local Minigame = require("../src/shared/Minigame")

local passed, failed = 0, 0
local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
		print("  ok   " .. name)
	else
		failed += 1
		print("  FAIL " .. name .. "\n       " .. tostring(err))
	end
end
local function eq(a: any, b: any, msg: string?)
	if a ~= b then
		error((msg or "values differ") .. (": expected %s, got %s"):format(tostring(b), tostring(a)), 2)
	end
end
local function truthy(v: any, msg: string?)
	if not v then
		error(msg or "expected truthy", 2)
	end
end

local function profile(cash: number): any
	return { Cash = cash, Inventory = {}, Displays = {}, DisplayRot = {}, AppliedTx = {}, Listings = {}, PendingPurchases = {}, MarketHistory = {}, Stats = {} }
end
local function item(uid: string, id: string): any
	return { Uid = uid, Id = id, Found = 0, Zone = "Test", Locked = false, Condition = "Clean" }
end

-- ── TxCore ────────────────────────────────────────────────────────────────
print("TxCore")
test("transfer moves the same instance, not a copy", function()
	local victim, thief = profile(100), profile(50)
	victim.Inventory.U1 = item("U1", "coin_gold_sun")
	victim.Displays.H1 = "U1"
	local loot = TxCore.DeepCopy(victim.Inventory.U1)
	TxCore.ApplySide(victim, { Remove = { "U1" }, Add = {}, Cash = 20 }, "tx1", 1)
	TxCore.ApplySide(thief, { Remove = {}, Add = { loot }, Cash = 0 }, "tx1", 1)
	eq(victim.Inventory.U1, nil, "victim lost item")
	eq(victim.Displays.H1, nil, "display cleared")
	eq(victim.Cash, 120, "insurance paid")
	eq(thief.Inventory.U1.Id, "coin_gold_sun", "thief has item with same uid")
end)
test("applying the same transaction twice does nothing (crash replay)", function()
	local a = profile(100)
	local side = { Remove = {}, Add = { item("U2", "vase_painted") }, Cash = -30 }
	truthy(TxCore.ApplySide(a, side, "txA", 1))
	eq(TxCore.ApplySide(a, side, "txA", 2), false)
	eq(a.Cash, 70)
end)
test("replay after a lost save re-applies exactly once", function()
	-- The saved (old) profile never got the tx: recovery applies it once.
	local saved = profile(500)
	saved.Inventory.X = item("X", "amphora_oil")
	local side = { Remove = { "X" }, Add = {}, Cash = 200 }
	TxCore.ApplySide(saved, side, "txB", 10)
	TxCore.ApplySide(saved, side, "txB", 11)
	eq(saved.Inventory.X, nil)
	eq(saved.Cash, 700)
end)
test("CanApply rejects missing items and overdrafts", function()
	local a = profile(10)
	local ok1 = TxCore.CanApply(a, { Remove = { "nope" }, Add = {}, Cash = 0 })
	eq(ok1, false)
	local ok2 = TxCore.CanApply(a, { Remove = {}, Add = {}, Cash = -11 })
	eq(ok2, false)
	local ok3 = TxCore.CanApply(a, { Remove = {}, Add = {}, Cash = -10 })
	eq(ok3, true)
end)
test("added items arrive unreserved and unlocked", function()
	local a = profile(0)
	local incoming = item("U9", "ring_copper")
	incoming.Reserved = { Kind = "Trade", Id = "t" }
	incoming.Locked = true
	TxCore.ApplySide(a, { Remove = {}, Add = { incoming }, Cash = 0 }, "tx9", 1)
	eq(a.Inventory.U9.Reserved, nil)
	eq(a.Inventory.U9.Locked, false)
end)

-- ── MarketCore ────────────────────────────────────────────────────────────
print("MarketCore")
local store: { [string]: any } = {}
local function update(key: string, fn: (any) -> any): any
	local new = fn(store[key] and TxCore.DeepCopy(store[key]))
	if new ~= nil then
		store[key] = TxCore.DeepCopy(new)
	end
	return store[key] and TxCore.DeepCopy(store[key])
end

local function listFor(seller: any, sellerId: number, uid: string, price: number, now: number): string
	local id = "L-" .. uid
	seller.Inventory[uid].Reserved = { Kind = "Listing", Id = id }
	seller.Listings[id] = { Uid = uid, ItemId = seller.Inventory[uid].Id, Price = price, Created = now }
	local doc = MarketCore.NewListingDoc(id, sellerId, "Seller", seller.Inventory[uid], price, 0.05, now, 7)
	update(id, function(old)
		return MarketCore.CreateIfAbsent(old, doc)
	end)
	return id
end

local function buy(buyer: any, buyerId: number, id: string, now: number): string
	local doc = store[id]
	buyer.Cash -= doc.Price
	buyer.PendingPurchases[id] = { Price = doc.Price, Time = now }
	local current = update(id, function(old)
		return (MarketCore.PurchaseTransition(old, buyerId, "Buyer", now))
	end)
	return MarketCore.ResolvePurchase(buyer, id, current, buyerId, now, 25)
end

test("full sale: buyer gets the item, seller paid minus 5% fee", function()
	store = {}
	local seller, buyer = profile(0), profile(1000)
	seller.Inventory.S1 = item("S1", "coin_gold_sun")
	local id = listFor(seller, 1, "S1", 400, 100)
	eq(buy(buyer, 2, id, 101), "Granted")
	eq(buyer.Cash, 600)
	eq(buyer.Inventory.S1.Id, "coin_gold_sun")
	local r = MarketCore.SettleSeller(seller, id, store[id], 102, 25)
	eq(r.Kind, "Sold")
	eq(r.Payout, 380)
	eq(seller.Cash, 380)
	eq(seller.Inventory.S1, nil, "seller's copy removed")
	eq(seller.Listings[id], nil)
end)
test("a listing can only be sold once (two buyers race)", function()
	store = {}
	local seller, b1, b2 = profile(0), profile(1000), profile(1000)
	seller.Inventory.S2 = item("S2", "amphora_oil")
	local id = listFor(seller, 1, "S2", 200, 0)
	eq(buy(b1, 2, id, 1), "Granted")
	eq(buy(b2, 3, id, 2), "Refunded")
	eq(b1.Cash, 800)
	eq(b2.Cash, 1000, "loser fully refunded")
	eq(b2.Inventory.S2, nil)
end)
test("seller can't buy their own listing", function()
	store = {}
	local seller = profile(1000)
	seller.Inventory.S3 = item("S3", "amphora_oil")
	local id = listFor(seller, 1, "S3", 200, 0)
	eq(buy(seller, 1, id, 1), "Refunded")
	eq(seller.Cash, 1000)
	eq(store[id].Status, "Active")
end)
test("cancel then buy fails; item returns to seller", function()
	store = {}
	local seller, buyer = profile(0), profile(500)
	seller.Inventory.S4 = item("S4", "ring_copper")
	local id = listFor(seller, 1, "S4", 150, 0)
	update(id, function(old)
		return (MarketCore.CancelTransition(old, 1))
	end)
	eq(buy(buyer, 2, id, 1), "Refunded")
	local r = MarketCore.SettleSeller(seller, id, store[id], 2, 25)
	eq(r.Kind, "Returned")
	eq(seller.Inventory.S4.Reserved, nil, "unreserved")
	eq(buyer.Cash, 500)
end)
test("buyer crash after paying but before the sale: refunded on reload", function()
	store = {}
	local seller, buyer = profile(0), profile(300)
	seller.Inventory.S5 = item("S5", "ring_copper")
	local id = listFor(seller, 1, "S5", 120, 0)
	buyer.Cash -= 120
	buyer.PendingPurchases[id] = { Price = 120, Time = 0 }
	-- crash: the compare-and-set never happened. Next load:
	eq(MarketCore.ResolvePurchase(buyer, id, store[id], 2, 5, 25), "Refunded")
	eq(buyer.Cash, 300)
	eq(store[id].Status, "Active", "listing still for sale")
end)
test("buyer crash after the sale but before granting: granted on reload", function()
	store = {}
	local seller, buyer = profile(0), profile(300)
	seller.Inventory.S6 = item("S6", "ring_copper")
	local id = listFor(seller, 1, "S6", 120, 0)
	buyer.Cash -= 120
	buyer.PendingPurchases[id] = { Price = 120, Time = 0 }
	update(id, function(old)
		return (MarketCore.PurchaseTransition(old, 2, "Buyer", 1))
	end)
	-- crash before ResolvePurchase. Next load:
	eq(MarketCore.ResolvePurchase(buyer, id, store[id], 2, 5, 25), "Granted")
	eq(buyer.Inventory.S6.Id, "ring_copper")
	eq(buyer.Cash, 180)
	-- and resolving again does nothing (pending was cleared in the same save)
	eq(MarketCore.ResolvePurchase(buyer, id, store[id], 2, 6, 25), "None")
end)
test("settling a sale twice pays once", function()
	store = {}
	local seller, buyer = profile(0), profile(1000)
	seller.Inventory.S7 = item("S7", "vase_painted")
	local id = listFor(seller, 1, "S7", 300, 0)
	buy(buyer, 2, id, 1)
	MarketCore.SettleSeller(seller, id, store[id], 2, 25)
	local again = MarketCore.SettleSeller(seller, id, store[id], 3, 25)
	eq(again.Kind, "None")
	eq(seller.Cash, 285)
end)
test("lost create: tombstone prevents a late listing from appearing", function()
	store = {}
	update("L-x", MarketCore.VoidIfMissing)
	local doc = MarketCore.NewListingDoc("L-x", 1, "S", item("x", "ring_copper"), 100, 0.05, 0, 7)
	update("L-x", function(old)
		return MarketCore.CreateIfAbsent(old, doc)
	end)
	eq(store["L-x"].Status, "Void", "late create refused")
end)
test("expired listings can't be bought", function()
	store = {}
	local seller, buyer = profile(0), profile(1000)
	seller.Inventory.S8 = item("S8", "ring_copper")
	local id = listFor(seller, 1, "S8", 100, 0)
	eq(buy(buyer, 2, id, 8 * 86400), "Refunded")
	eq(buyer.Cash, 1000)
end)
test("price bounds", function()
	local low, high = MarketCore.PriceBounds(400, 0.25, 20, 10000000)
	eq(low, 100)
	eq(high, 8000)
	local low2 = MarketCore.PriceBounds(12, 0.25, 20, 10000000)
	eq(low2, 10, "minimum price floor")
end)

-- ── Minigame ──────────────────────────────────────────────────────────────
print("Minigame")
test("marker bounces 0 → 1 → 0", function()
	eq(Minigame.MarkerPos(0, 0, 1), 0)
	eq(Minigame.MarkerPos(0.25, 0, 1), 0.5)
	eq(Minigame.MarkerPos(0.5, 0, 1), 1)
	eq(Minigame.MarkerPos(0.75, 0, 1), 0.5)
end)
test("a press in the zone is a hit, far outside is a miss", function()
	-- speed 0.5: at t=0.5 marker is at 0.5
	truthy(Minigame.JudgePress(0.5, 0, 0, 0.5, 0.5, 0.2), "centre hit")
	eq(Minigame.JudgePress(0.1, 0, 0, 0.5, 0.9, 0.2), false, "far miss")
end)
test("latency compensation accepts a press that was on time when sent", function()
	-- marker reaches zone centre 0.5 at t=0.5; the server receives it 0.15s later
	truthy(Minigame.JudgePress(0.65, 0.15, 0, 0.5, 0.5, 0.12))
end)
test("zone centres are deterministic and inside the bar", function()
	local a = Minigame.ZoneCenters(12345, 5)
	local b = Minigame.ZoneCenters(12345, 5)
	for i = 1, 5 do
		eq(a[i], b[i])
		truthy(a[i] >= 0.15 and a[i] <= 0.85)
	end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("tests failed")
end
