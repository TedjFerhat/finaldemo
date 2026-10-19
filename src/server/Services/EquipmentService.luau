--[[
	EquipmentService
	Buying better search tools. Owning a tier means you use it automatically
	(the best tool you own is always equipped).
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Equipment = require(Shared.Equipment)
local Upgrades = require(Shared.Upgrades)
local Format = require(Shared.Format)
local ItemCatalog = require(Shared.ItemCatalog)
local HeistConfig = require(Shared.HeistConfig)

local PlayerDataService = require(script.Parent.PlayerDataService)
local EconomyService = require(script.Parent.EconomyService)
local StateSync = require(script.Parent.StateSync)
local InventoryService = require(script.Parent.InventoryService)
local Net = require(script.Parent.Parent.Util.Net)

local EquipmentService = {}

function EquipmentService.BuyTool(player: Player, tier: any): (boolean, string?)
	if not Net.IsInt(tier, 1, Equipment.MaxTier) then
		return false, "Invalid tool"
	end
	local data = PlayerDataService.GetData(player)
	if not data then
		return false, "Data not loaded"
	end
	local tool = Equipment.Get(tier)
	if data.ToolTier >= tool.Tier then
		return false, "You already own this tool (or a better one)"
	end
	if Upgrades.ComputeLevel(data.Upgrades) < tool.RequiredLevel then
		return false, ("Requires Museum Level %d"):format(tool.RequiredLevel)
	end
	if not EconomyService.Spend(player, tool.Cost, "Tool:" .. tool.Tier) then
		return false, ("You need %s"):format(Format.Cash(tool.Cost))
	end
	data.ToolTier = tool.Tier
	StateSync.Mark(player)
	return true, ("Equipped: %s!"):format(tool.Name)
end

-- Specialised scanner attachments (account-bound).
function EquipmentService.BuyAttachment(player: Player, attachmentId: any): (boolean, string?)
	if type(attachmentId) ~= "string" then
		return false, "Invalid attachment"
	end
	local att = Equipment.Attachments[attachmentId]
	local data = PlayerDataService.GetData(player)
	if not att or not data then
		return false, "Invalid attachment"
	end
	if data.Attachments[attachmentId] then
		return false, "You already own the " .. att.Name
	end
	if Upgrades.ComputeLevel(data.Upgrades) < att.RequiredLevel then
		return false, ("Requires Museum Level %d"):format(att.RequiredLevel)
	end
	if not EconomyService.Spend(player, att.Cost, "Attachment:" .. attachmentId) then
		return false, ("You need %s"):format(Format.Cash(att.Cost))
	end
	data.Attachments[attachmentId] = true
	StateSync.Mark(player)
	return true, ("Installed: %s"):format(att.Name)
end

-- Heist gear: each purchase is a new tradable item instance with full charges.
function EquipmentService.BuyGadget(player: Player, itemId: any): (boolean, string?)
	local def = type(itemId) == "string" and ItemCatalog.Get(itemId)
	local data = PlayerDataService.GetData(player)
	if not def or not def.Gadget or not data then
		return false, "Invalid gadget"
	end
	if Upgrades.ComputeLevel(data.Upgrades) < HeistConfig.AttackerMinLevel then
		return false, ("Heist gear unlocks at Museum Level %d"):format(HeistConfig.AttackerMinLevel)
	end
	if not EconomyService.Spend(player, def.Gadget.Cost, "Gadget:" .. def.Id) then
		return false, ("You need %s"):format(Format.Cash(def.Gadget.Cost))
	end
	InventoryService.Grant(player, def.Id, "Shop", { Provenance = "Bought from the Black Market", IgnoreCapacity = true })
	return true, ("Bought %s (%d charges)"):format(def.Name, def.Gadget.Charges)
end

function EquipmentService.Init() end

function EquipmentService.Start()
	Net.Handle("BuyTool", EquipmentService.BuyTool)
	Net.Handle("BuyAttachment", EquipmentService.BuyAttachment)
	Net.Handle("BuyGadget", EquipmentService.BuyGadget)
end

return EquipmentService
