--[[
	Remotes
	Every RemoteEvent / RemoteFunction the game uses is listed here ONCE.
	The server creates them (in ReplicatedStorage/Remotes) when it starts;
	clients wait for them. You do NOT need to create any remotes by hand.

	Server › Client events are fired by the server only.
	Client › Server functions are ALWAYS validated on the server: the client
	only asks; the server decides.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.Events = {
	"StateUpdated", -- S›C full snapshot of the player's own state
	"Notify", -- S›C toast message { Text, Kind }
	"Discovery", -- S›C a search result
	"SearchStarted", -- S›C { SiteName, Duration }
	"SearchEnded", -- S›C { Success, Reason }
	"OpenPlacement", -- S›C owner opened an empty display slot
	"ZoneChanged", -- S›C zone id the player is now in ("Museum" or a zone id)
	"Purchased", -- S›C an upgrade was built (for sounds/effects)
	-- v2
	"ChallengeStart", -- S›C a server-judged minigame begins
	"ChallengeFeedback", -- S›C hit/miss for one press
	"ChallengeEnd", -- S›C minigame finished
	"ExcavationOffer", -- S›C choose an excavation tool
	"HeistUpdate", -- S›C attacker's mission status
	"SecurityAlert", -- S›C defender alerts
	"JailUpdate", -- S›C jail countdown
	"TradeUpdate", -- S›C trade window state
	"TradeRequest", -- S›C someone wants to trade
	"MarketChanged", -- S›C your listings/sales changed
}

Remotes.Functions = {
	"PurchaseUpgrade", -- (upgradeId) -> { Ok, Message }
	"PlaceItem", -- (slotId, itemUid) -> { Ok, Message }
	"SellItem", -- (itemUid) -> { Ok, Message }
	"ToggleLock", -- (itemUid) -> { Ok, Message }
	"BuyTool", -- (tier) -> { Ok, Message }
	"TravelTo", -- (zoneId | "Museum") -> { Ok, Message }
	"VisitMuseum", -- (userId) -> { Ok, Message }
	"GetMuseumList", -- () -> list of { UserId, Name, Level, Prestige, Displays }
	-- v2: shop
	"BuyGadget", -- (itemId)
	"BuyAttachment", -- (attachmentId)
	-- v2: treasure hunting
	"Scan", -- () -> scanner reading
	"DigHere", -- () -> starts an excavation at a pinpointed cache
	"ChooseExcavationTool", -- (sessionId, toolName)
	"ChallengeInput", -- (challengeId, action, payload?)
	-- v2: security & heists
	"BuySecurity", -- (systemId)
	"GetHeistTargets", -- () -> eligible museums
	"StartHeist", -- (targetUserId, gadgetUids)
	"HeistAction", -- (action) jammer, sneak, abort
	-- v2: marketplace & trading
	"MarketBrowse", -- (query) -> page of listings
	"MarketCreate", -- (itemUid, price)
	"MarketCancel", -- (listingId)
	"MarketBuy", -- (listingId)
	"MarketMine", -- () -> my listings + history
	"RequestTrade", -- (userId)  (was TradeRequest: clashed with the S›C event)
	"TradeRespond", -- (requestId, accept)
	"TradeSetOffer", -- (itemUids, cash)
	"TradeLock", -- (locked)
	"TradeConfirm", -- ()
	"TradeCancel", -- ()
	-- v3: Robux shop & Fly Mode (the server validates everything)
	"PromptPurchase", -- ("Pass" | "Product", key) -> opens Roblox's purchase prompt
	"SetFly", -- (enabled: boolean) -> server checks the Game Pass and conditions
	"SetPower", -- (powerKey, enabled) -> Fast Walk / High Jump, server-checked
}

local FOLDER_NAME = "Remotes"

local function getFolder(): Folder
	if RunService:IsServer() then
		local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
		if not folder then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			for _, name in Remotes.Events do
				local e = Instance.new("RemoteEvent")
				e.Name = name
				e.Parent = folder
			end
			for _, name in Remotes.Functions do
				local f = Instance.new("RemoteFunction")
				f.Name = name
				f.Parent = folder
			end
			folder.Parent = ReplicatedStorage
		end
		return folder :: Folder
	else
		return ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
	end
end

function Remotes.Event(name: string): RemoteEvent
	assert(table.find(Remotes.Events, name), "Unknown RemoteEvent: " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.Function(name: string): RemoteFunction
	assert(table.find(Remotes.Functions, name), "Unknown RemoteFunction: " .. name)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
