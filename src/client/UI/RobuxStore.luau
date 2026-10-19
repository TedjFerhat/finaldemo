--[[
	RobuxStore
	Opened by the "+" button next to your cash.
	  • Cash packs   — Developer Products (repeatable). Cash arrives only after
	                   Roblox confirms the purchase on the server.
	  • Powers       — Game Passes: Fly, Fast Walk, High Jump. Owned powers get an
	                   ON/OFF switch; not-owned ones get a Buy button.
	  • Gear bundles — Developer Products (heist gear).
	The client only asks. The server opens the purchase prompt, verifies
	ownership and applies every power. Items whose Id is still 0 show
	"Not available yet" (see Shared/Monetization.luau).
]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Monetization = require(Shared.Monetization)
local Format = require(Shared.Format)

local Theme = require(script.Parent.Theme)
local Window = require(script.Parent.Window)
local ClientState = require(script.Parent.Parent.ClientState)
local ClientNet = require(script.Parent.Parent.ClientNet)

local RobuxStore = {}

local NAME = "RobuxStore"
local player = Players.LocalPlayer
local list: ScrollingFrame

local POWER_ORDER = { "FlyMode", "FastWalk", "HighJump" }
local CASH_ORDER = { "CashSmall", "CashMedium", "CashLarge" }
local BUNDLE_ORDER = { "LocksmithBundle", "SafecrackerBundle" }

-- Live Robux prices from Roblox (never hardcoded). false = lookup in flight/failed.
local priceCache: { [string]: string | boolean } = {}
local function priceText(kind: string, id: number): string
	local key = kind .. id
	local cached = priceCache[key]
	if type(cached) == "string" then
		return cached
	elseif cached == nil then
		priceCache[key] = false
		task.spawn(function()
			local ok, info = pcall(function()
				return MarketplaceService:GetProductInfo(id, if kind == "Pass" then Enum.InfoType.GamePass else Enum.InfoType.Product)
			end)
			if ok and info and info.PriceInRobux then
				priceCache[key] = "R$ " .. tostring(info.PriceInRobux)
				RobuxStore.Refresh()
			end
		end)
	end
	return "Buy"
end

local function header(order: number, text: string)
	Theme.Eyebrow(text, { LayoutOrder = order, Size = UDim2.new(1, -8, 0, 22), Parent = list })
end

local function row(order: number, title: string, desc: string, buttonText: string, enabled: boolean, color: Color3, onClick: () -> (), highlight: boolean?)
	local f = Theme.New("Frame", {
		BackgroundColor3 = if highlight then Color3.fromRGB(34, 70, 50) else Theme.Colors.PanelLight,
		Size = UDim2.new(1, -8, 0, 92),
		LayoutOrder = order,
		Parent = list,
	})
	Theme.Corner(f, 10)
	Theme.Padding(f, 8)
	Theme.Label(title, { TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(0.68, 0, 0, 22), Parent = f }, 17)
	Theme.Label(desc, {
		TextColor3 = Theme.Colors.TextDim,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true,
		Position = UDim2.fromOffset(0, 24),
		Size = UDim2.new(0.68, 0, 1, -24),
		Parent = f,
	}, 13)
	local b = Theme.Button(buttonText, color, onClick, 17)
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.Position = UDim2.new(1, 0, 0.5, 0)
	b.Size = UDim2.new(0.3, 0, 0, 44)
	Theme.SetButtonEnabled(b, enabled, color)
	b.Parent = f
end

local function isOwned(state: any, key: string): boolean
	return state.Premium ~= nil and state.Premium.Owned ~= nil and state.Premium.Owned[key] == true
end

local function powerIsOn(key: string): boolean
	if key == "FlyMode" then
		return player:GetAttribute("FlyActive") == true
	end
	return player:GetAttribute("Power_" .. key) == true
end

local function drawPowers(state: any, order: number): number
	header(order, "POWERS  ·  permanent, switch on/off any time")
	for _, key in POWER_ORDER do
		local def = Monetization.Passes[key]
		if def then
			order += 1
			local owned = isOwned(state, key)
			local ready = Monetization.IsConfigured(def)
			local on = owned and powerIsOn(key)
			local label, color
			if owned then
				label, color = if on then "ON" else "OFF", if on then Theme.Colors.Success else Theme.Colors.Disabled
			else
				label, color = if ready then priceText("Pass", def.Id) else "Not available yet", Theme.Colors.Blue
			end
			local tag = if owned then "  <font color=\"#2E7D32\">OWNED</font>" else "  <font color=\"#7E5C3E\">permanent</font>"
			row(order, ("<b>%s %s</b>%s"):format(def.Icon, def.Name, tag), def.Description, label, owned or ready, if owned then (if on then Theme.Colors.Success else Theme.Colors.Wood) else color, function()
				if owned then
					if key == "FlyMode" then
						ClientNet.Call("SetFly", true, not on)
					else
						ClientNet.Call("SetPower", true, key, not on)
					end
				else
					ClientNet.Call("PromptPurchase", true, "Pass", key)
				end
			end, on)
		end
	end
	return order
end

local function drawProducts(order: number, title: string, keys: { string }, source: { [string]: Monetization.ProductDef }): number
	header(order, title)
	for _, key in keys do
		local def = source[key]
		if def then
			order += 1
			local ready = Monetization.IsConfigured(def)
			local desc = def.Description
			if def.Cash then
				desc = ("+%s cash. %s"):format(Format.Cash(def.Cash), "Added after Roblox confirms the purchase.")
			end
			row(order, ("<b>%s %s</b>"):format(def.Icon, def.Name), desc, if ready then priceText("Product", def.Id) else "Not available yet", ready, Theme.Colors.Danger, function()
				ClientNet.Call("PromptPurchase", true, "Product", key)
			end)
		end
	end
	return order
end

local function refresh()
	local state = ClientState.Get()
	if not state or not list then
		return
	end
	for _, child in list:GetChildren() do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end
	local order = 0
	order = drawProducts(order, "CASH  ·  instant museum funds", CASH_ORDER, Monetization.CashPacks) + 1
	order = drawPowers(state, order + 1) + 1
	drawProducts(order + 1, "HEIST GEAR BUNDLES  ·  normal security rules still apply", BUNDLE_ORDER, Monetization.Products)
end

function RobuxStore.Refresh()
	if Window.IsOpen(NAME) then
		refresh()
	end
end

function RobuxStore.Init()
	local content = Window.Create(NAME, "Robux Store", refresh)
	list = Theme.Scroller({ Size = UDim2.fromScale(1, 1) })
	list.Parent = content
	Theme.ListLayout(list, 8)
	Theme.Padding(list, 4)
	ClientState.OnChanged(RobuxStore.Refresh)
	for _, attr in { "FlyActive", "Power_FastWalk", "Power_HighJump" } do
		player:GetAttributeChangedSignal(attr):Connect(RobuxStore.Refresh)
	end
end

function RobuxStore.Open()
	Window.Open(NAME)
end

return RobuxStore
