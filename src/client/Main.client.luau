--[[
	Main (client entry point)
	Creates the screen, starts every UI module and connects server events.
	Nothing here can change game state — every button asks the server.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local ClientState = require(script.Parent.ClientState)
local ClientNet = require(script.Parent.ClientNet)
local UI = script.Parent.UI
local Theme = require(UI.Theme)
local Sounds = require(UI.Sounds)
local Notifications = require(UI.Notifications)
local Window = require(UI.Window)
local HUD = require(UI.HUD)
local InventoryPanel = require(UI.InventoryPanel)
local UpgradesPanel = require(UI.UpgradesPanel)
local JournalPanel = require(UI.JournalPanel)
local ShopPanel = require(UI.ShopPanel)
local RobuxStore = require(UI.RobuxStore)
local TravelPanel = require(UI.TravelPanel)
local MuseumsPanel = require(UI.MuseumsPanel)
local SearchBar = require(UI.SearchBar)
local DiscoveryPopup = require(UI.DiscoveryPopup)
local Dialog = require(UI.Dialog)
local TimingBar = require(UI.TimingBar)
local ExpeditionUI = require(UI.ExpeditionUI)
local HeistUI = require(UI.HeistUI)
local SecurityPanel = require(UI.SecurityPanel)
local MarketPanel = require(UI.MarketPanel)
local TradePanel = require(UI.TradePanel)
local SettingsPanel = require(UI.SettingsPanel)
local ZoneLighting = require(script.Parent.Controllers.ZoneLighting)
local HeistVisuals = require(script.Parent.Controllers.HeistVisuals)
local FlyController = require(script.Parent.Controllers.FlyController)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local screen = Instance.new("ScreenGui")
screen.Name = "MuseumUI"
screen.ResetOnSpawn = false
screen.IgnoreGuiInset = false
screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screen.Parent = playerGui

Theme.SetClickSound(function()
	Sounds.Play("Click", 0.35)
end)

local function safely(label: string, fn: () -> ())
	local ok, err = pcall(fn)
	if not ok then
		warn(("[MuseumTycoon] client %s FAILED: %s"):format(label, tostring(err)))
	end
end

ClientState.Init()
Notifications.Init(screen)
ClientNet.SetToast(Notifications.Show)
Window.Init(screen)
Dialog.Init(screen)
Notifications.SetClueHandler(Dialog.Card)

safely("InventoryPanel", InventoryPanel.Init)
safely("UpgradesPanel", UpgradesPanel.Init)
safely("JournalPanel", JournalPanel.Init)
safely("ShopPanel", ShopPanel.Init)
safely("RobuxStore", RobuxStore.Init)
safely("TravelPanel", TravelPanel.Init)
safely("MuseumsPanel", MuseumsPanel.Init)
safely("SecurityPanel", SecurityPanel.Init)
safely("MarketPanel", MarketPanel.Init)
safely("TradePanel", TradePanel.Init)
safely("SettingsPanel", SettingsPanel.Init)
safely("HeistUI", function() HeistUI.Init(screen) end)

-- Navigation: five main buttons on the rail, the rest under "More".
-- Every entry opens the same window/action it always did.
HUD.Init(screen, {
	{ Primary = true, Icon = "🎒", Text = "Inventory", Window = "Inventory", OnClick = function()
		if Window.IsOpen("Inventory") then
			Window.Close()
		else
			InventoryPanel.Open()
		end
	end },
	{ Primary = true, Icon = "🏛️", Text = "Museum", Window = "Upgrades", OnClick = function()
		Window.Toggle("Upgrades")
	end },
	{ Primary = true, Icon = "🧭", Text = "Travel", Window = "Travel", OnClick = function()
		Window.Toggle("Travel")
	end },
	{ Primary = true, Icon = "📖", Text = "Journal", Window = "Journal", OnClick = function()
		Window.Toggle("Journal")
	end },
	{ Primary = true, Icon = "🏪", Text = "Market", Window = "Market", OnClick = function()
		Window.Toggle("Market")
	end },
	{ Icon = "⛏️", Text = "Shop", Window = "Shop", OnClick = function()
		Window.Toggle("Shop")
	end },
	{ Icon = "🛡️", Text = "Security", Window = "Security", OnClick = function()
		Window.Toggle("Security")
	end },
	{ Icon = "🕵️", Text = "Heists", Window = "Heists", OnClick = function()
		Window.Toggle("Heists")
	end },
	{ Icon = "👥", Text = "Players", Window = "Museums", OnClick = function()
		if TradePanel.IsActive() then
			TradePanel.Open()
		else
			Window.Toggle("Museums")
		end
	end },
	{ Icon = "🏠", Text = "Home", OnClick = function()
		ClientNet.Call("TravelTo", true, "Museum")
	end },
	{ Icon = "⚙️", Text = "Settings", Window = "Settings", OnClick = function()
		Window.Toggle("Settings")
	end },
})
SettingsPanel.SetObjectiveSetter(HUD.SetObjectiveEnabled)
HUD.SetAddCashHandler(function()
	Window.Toggle("RobuxStore")
end)

safely("SearchBar", function() SearchBar.Init(screen) end)
safely("DiscoveryPopup", function() DiscoveryPopup.Init(screen) end)
safely("TimingBar", function() TimingBar.Init(screen) end)
safely("ExpeditionUI", function() ExpeditionUI.Init(screen) end)
safely("ZoneLighting", ZoneLighting.Init)
safely("HeistVisuals", HeistVisuals.Init)
safely("FlyController", function() FlyController.Init(screen) end)

-- Server › client events
Remotes.Event("Notify").OnClientEvent:Connect(function(info)
	if type(info) == "table" and type(info.Text) == "string" then
		Notifications.Show(info.Text, info.Kind)
	end
end)

Remotes.Event("OpenPlacement").OnClientEvent:Connect(function(info)
	if type(info) == "table" and type(info.SlotId) == "string" and type(info.SlotType) == "string" then
		InventoryPanel.OpenForPlacement(info.SlotId, info.SlotType)
	end
end)

Remotes.Event("Purchased").OnClientEvent:Connect(function()
	Sounds.Play("Purchase", 0.6, 0.8)
end)


safely("AutoPolish", function() Theme.AutoPolish(screen) end)

print("[MuseumTycoon] Client started.")
