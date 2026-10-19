--[[
	TradeService — direct player-to-player trades (same server)

	Flow: request › accept › both build offers (items + cash) › both LOCK ›
	both CONFIRM › the server re-validates everything and swaps through
	LedgerService (durable, crash-safe, all-or-nothing).

	Safety:
	  • Offered items are reserved (Kind "Trade"): they can't be sold, listed,
	    displayed or stolen while in the window. Displayed items are taken
	    off display when offered.
	  • Any change to either offer clears BOTH locks and confirmations.
	  • Leaving, starting a heist, jail, 3 minutes of inactivity › cancelled,
	    all reservations released.
	  • The client only sends item ids and an amount; the server checks
	    ownership, tradability, balances and storage space.
]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local ItemCatalog = require(Shared.ItemCatalog)

local PlayerDataService = require(script.Parent.PlayerDataService)
local InventoryService = require(script.Parent.InventoryService)
local MuseumService = require(script.Parent.MuseumService)
local LedgerService = require(script.Parent.LedgerService)
local AchievementService = require(script.Parent.AchievementService)
local StateSync = require(script.Parent.StateSync)
local Net = require(script.Parent.Parent.Util.Net)
local Notifier = require(script.Parent.Parent.Util.Notifier)

local TradeService = {}

local TC = Config.Trade

type Offer = { Items: { string }, Cash: number, Locked: boolean, Confirmed: boolean }
type Session = {
	Id: string,
	A: Player,
	B: Player,
	Offers: { [Player]: Offer },
	LastActivity: number,
	Executing: boolean,
	Done: boolean,
}
type Request = { Id: string, From: Player, To: Player, Expires: number }

local sessions: { [Player]: Session } = {}
local requests: { [string]: Request } = {}

local function other(session: Session, player: Player): Player
	return if session.A == player then session.B else session.A
end

local function describeItems(owner: Player, uids: { string }): { any }
	local data = PlayerDataService.GetData(owner)
	local list = {}
	if not data then
		return list
	end
	for _, uid in uids do
		local item = data.Inventory[uid]
		local def = item and ItemCatalog.Get(item.Id)
		if item and def then
			table.insert(list, {
				Uid = uid,
				Id = item.Id,
				Name = def.Name,
				Rarity = def.Rarity,
				Condition = item.Condition,
				Charges = item.Charges,
				Value = InventoryService.ValueOf(item),
			})
		end
	end
	return list
end

local function push(session: Session, message: string?)
	for _, player in { session.A, session.B } do
		if player.Parent then
			local mine = session.Offers[player]
			local partner = other(session, player)
			local theirs = session.Offers[partner]
			Net.Fire("TradeUpdate", player, {
				Active = not session.Done,
				Id = session.Id,
				PartnerName = partner.DisplayName,
				Mine = { Items = describeItems(player, mine.Items), Cash = mine.Cash, Locked = mine.Locked, Confirmed = mine.Confirmed },
				Theirs = { Items = describeItems(partner, theirs.Items), Cash = theirs.Cash, Locked = theirs.Locked, Confirmed = theirs.Confirmed },
				Message = message,
			})
		end
	end
end

local function finish(session: Session, message: string?)
	if session.Done then
		return
	end
	session.Done = true
	for _, player in { session.A, session.B } do
		local data = PlayerDataService.GetData(player)
		if data then
			InventoryService.ReleaseAll(data, "Trade", session.Id)
			StateSync.Mark(player)
		end
		player:SetAttribute("InTrade", nil)
		if sessions[player] == session then
			sessions[player] = nil
		end
		if player.Parent then
			Net.Fire("TradeUpdate", player, { Active = false, Id = session.Id, Message = message })
		end
	end
end

function TradeService.CancelFor(player: Player, reason: string)
	local session = sessions[player]
	if session and not session.Executing then
		finish(session, reason)
	end
end

local function clearLocks(session: Session)
	for _, offer in session.Offers do
		offer.Locked = false
		offer.Confirmed = false
	end
end

local function canTrade(player: Player): (boolean, string?)
	if not PlayerDataService.GetData(player) then
		return false, "Data not loaded"
	end
	if player:GetAttribute("InHeist") then
		return false, "Busy on a heist"
	end
	if player:GetAttribute("Jailed") then
		return false, "In jail"
	end
	if sessions[player] then
		return false, "Already trading"
	end
	return true, nil
end

-- ── Requests ───────────────────────────────────────────────────────────────
function TradeService.Request(player: Player, userId: any): (boolean, string?)
	if not Net.IsInt(userId, 1, 2 ^ 53) then
		return false, "Invalid player"
	end
	local target = Players:GetPlayerByUserId(userId)
	if not target or target == player then
		return false, "That player isn't here"
	end
	local ok, why = canTrade(player)
	if not ok then
		return false, why
	end
	local okTarget, whyTarget = canTrade(target)
	if not okTarget then
		return false, target.DisplayName .. ": " .. (whyTarget or "unavailable")
	end
	for _, r in requests do
		if r.From == player and r.To == target and r.Expires > os.clock() then
			return false, "You already sent a request"
		end
	end
	local id = HttpService:GenerateGUID(false)
	requests[id] = { Id = id, From = player, To = target, Expires = os.clock() + TC.RequestSeconds }
	Net.Fire("TradeRequest", target, { RequestId = id, FromName = player.DisplayName, Seconds = TC.RequestSeconds })
	task.delay(TC.RequestSeconds + 1, function()
		requests[id] = nil
	end)
	return true, ("Trade request sent to %s"):format(target.DisplayName)
end

function TradeService.Respond(player: Player, requestId: any, accept: any): (boolean, string?)
	local request = type(requestId) == "string" and requests[requestId]
	if not request or request.To ~= player or request.Expires < os.clock() then
		return false, "That request has expired"
	end
	requests[requestId] = nil
	local from = request.From
	if accept ~= true then
		if from.Parent then
			Notifier.Send(from, player.DisplayName .. " declined your trade request.", "Info")
		end
		return true, nil
	end
	if not from.Parent then
		return false, "They left"
	end
	local okA, whyA = canTrade(from)
	local okB, whyB = canTrade(player)
	if not okA or not okB then
		return false, whyA or whyB
	end
	local session: Session = {
		Id = HttpService:GenerateGUID(false),
		A = from,
		B = player,
		Offers = {
			[from] = { Items = {}, Cash = 0, Locked = false, Confirmed = false },
			[player] = { Items = {}, Cash = 0, Locked = false, Confirmed = false },
		},
		LastActivity = os.clock(),
		Executing = false,
		Done = false,
	}
	sessions[from] = session
	sessions[player] = session
	from:SetAttribute("InTrade", true)
	player:SetAttribute("InTrade", true)
	push(session, "Trade started. Add items or cash, then Lock and Confirm.")
	return true, nil
end

-- ── Offers ─────────────────────────────────────────────────────────────────
function TradeService.SetOffer(player: Player, uids: any, cash: any): (boolean, string?)
	local session = sessions[player]
	if not session or session.Executing then
		return false, "No active trade"
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, nil
	end
	if type(uids) ~= "table" or #uids > TC.MaxItemsPerSide then
		return false, ("Up to %d items per side"):format(TC.MaxItemsPerSide)
	end
	if not Net.IsInt(cash, 0, 1e9) then
		return false, "Invalid amount"
	end
	if cash > data.Cash then
		return false, "You don't have that much cash"
	end
	local wanted = {}
	for _, uid in uids do
		if type(uid) ~= "string" or table.find(wanted, uid) then
			return false, "Invalid items"
		end
		local item = data.Inventory[uid]
		if not item then
			return false, "You don't own one of those items"
		end
		local ok, why = InventoryService.IsTransferable(item)
		if not ok then
			return false, why
		end
		if item.Reserved and not (item.Reserved.Kind == "Trade" and item.Reserved.Id == session.Id) then
			return false, "One of those items is busy (" .. item.Reserved.Kind .. ")"
		end
		table.insert(wanted, uid)
	end
	-- Release what was removed, reserve what was added
	local offer = session.Offers[player]
	for _, uid in offer.Items do
		if not table.find(wanted, uid) then
			InventoryService.Release(data, uid, "Trade", session.Id)
		end
	end
	local undisplayed = false
	for _, uid in wanted do
		local item = data.Inventory[uid]
		if not item.Reserved then
			if InventoryService.Undisplay(data, uid) then
				undisplayed = true
			end
			InventoryService.Reserve(data, uid, "Trade", session.Id)
		end
	end
	if undisplayed then
		MuseumService.RefreshAll(player)
	end
	offer.Items = wanted
	offer.Cash = cash
	clearLocks(session)
	session.LastActivity = os.clock()
	StateSync.Mark(player)
	push(session, player.DisplayName .. " changed their offer.")
	return true, nil
end

function TradeService.Lock(player: Player, locked: any): (boolean, string?)
	local session = sessions[player]
	if not session or session.Executing then
		return false, "No active trade"
	end
	local offer = session.Offers[player]
	if locked == true then
		offer.Locked = true
	else
		clearLocks(session)
	end
	session.LastActivity = os.clock()
	push(session, if locked == true then player.DisplayName .. " locked their offer." else player.DisplayName .. " unlocked.")
	return true, nil
end

local function execute(session: Session)
	session.Executing = true
	local A, B = session.A, session.B
	local offerA, offerB = session.Offers[A], session.Offers[B]
	local dataA, dataB = PlayerDataService.GetData(A), PlayerDataService.GetData(B)
	if not dataA or not dataB then
		session.Executing = false
		finish(session, "Trade cancelled")
		return
	end
	-- Re-validate everything right before the swap
	local function snapshots(data: any, uids: { string }): ({ any }?, string?)
		local list = {}
		for _, uid in uids do
			local item = data.Inventory[uid]
			if not item or not item.Reserved or item.Reserved.Kind ~= "Trade" or item.Reserved.Id ~= session.Id then
				return nil, "An item changed"
			end
			local copy = table.clone(item)
			copy.Reserved = nil
			copy.Provenance = item.Provenance
			table.insert(list, copy)
		end
		return list, nil
	end
	local itemsA, errA = snapshots(dataA, offerA.Items)
	local itemsB, errB = snapshots(dataB, offerB.Items)
	if not itemsA or not itemsB then
		session.Executing = false
		finish(session, errA or errB)
		return
	end
	if dataA.Cash < offerA.Cash or dataB.Cash < offerB.Cash then
		session.Executing = false
		finish(session, "Someone no longer has enough cash")
		return
	end
	local function artefactCount(items: { any }): number
		local n = 0
		for _, it in items do
			if not ItemCatalog.IsGadget(ItemCatalog.Get(it.Id)) then
				n += 1
			end
		end
		return n
	end
	local netA = artefactCount(itemsB) - artefactCount(itemsA)
	local netB = artefactCount(itemsA) - artefactCount(itemsB)
	if (netA > 0 and not InventoryService.HasSpace(dataA, netA)) or (netB > 0 and not InventoryService.HasSpace(dataB, netB)) then
		session.Executing = false
		finish(session, "Someone doesn't have enough storage space")
		return
	end
	local ok, err = LedgerService.Commit(session.Id, {
		[A] = { Remove = offerA.Items, Add = itemsB, Cash = offerB.Cash - offerA.Cash },
		[B] = { Remove = offerB.Items, Add = itemsA, Cash = offerA.Cash - offerB.Cash },
	})
	session.Executing = false
	if not ok then
		finish(session, err or "Trade failed. Nothing was exchanged.")
		return
	end
	for _, p in { A, B } do
		local data = PlayerDataService.GetData(p)
		if data then
			data.Stats.Trades += 1
		end
		AchievementService.Award(p, "trade_complete")
		MuseumService.RefreshAll(p)
	end
	finish(session, "Trade complete!")
	Notifier.Send(A, ("Trade with %s complete."):format(B.DisplayName), "Success")
	Notifier.Send(B, ("Trade with %s complete."):format(A.DisplayName), "Success")
end

function TradeService.Confirm(player: Player): (boolean, string?)
	local session = sessions[player]
	if not session or session.Executing then
		return false, "No active trade"
	end
	local mine, theirs = session.Offers[player], session.Offers[other(session, player)]
	if not mine.Locked or not theirs.Locked then
		return false, "Both offers must be locked first"
	end
	if #mine.Items == 0 and #theirs.Items == 0 and mine.Cash == 0 and theirs.Cash == 0 then
		return false, "The trade is empty"
	end
	mine.Confirmed = true
	session.LastActivity = os.clock()
	if theirs.Confirmed then
		push(session, "Both confirmed — exchanging...")
		execute(session)
	else
		push(session, player.DisplayName .. " confirmed. Waiting for the other player...")
	end
	return true, nil
end

function TradeService.Cancel(player: Player): (boolean, string?)
	local session = sessions[player]
	if not session or session.Executing then
		return false, "No active trade"
	end
	finish(session, player.DisplayName .. " cancelled the trade.")
	return true, nil
end

function TradeService.Init() end

function TradeService.Start()
	Net.Handle("RequestTrade", TradeService.Request)
	Net.Handle("TradeRespond", TradeService.Respond)
	Net.Handle("TradeSetOffer", TradeService.SetOffer)
	Net.Handle("TradeLock", TradeService.Lock)
	Net.Handle("TradeConfirm", TradeService.Confirm)
	Net.Handle("TradeCancel", TradeService.Cancel)

	PlayerDataService.OnReleasing(function(player)
		TradeService.CancelFor(player, player.DisplayName .. " left the game.")
	end)
	local function watch(player: Player)
		player:GetAttributeChangedSignal("InHeist"):Connect(function()
			if player:GetAttribute("InHeist") then
				TradeService.CancelFor(player, "Trade cancelled (heist started).")
			end
		end)
		player:GetAttributeChangedSignal("Jailed"):Connect(function()
			if player:GetAttribute("Jailed") then
				TradeService.CancelFor(player, "Trade cancelled.")
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	task.spawn(function()
		while true do
			task.wait(5)
			local seen: { [Session]: boolean } = {}
			for _, session in sessions do
				if not seen[session] then
					seen[session] = true
					if not session.Executing and os.clock() - session.LastActivity > TC.SessionIdleSeconds then
						finish(session, "Trade expired (inactive).")
					end
				end
			end
		end
	end)
end

return TradeService
