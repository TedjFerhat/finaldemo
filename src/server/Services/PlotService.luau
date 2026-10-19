--[[
	PlotService
	Gives every player their own plot, frees it when they leave, and moves
	characters to their plot when they spawn.
]]

local Players = game:GetService("Players")

local PlayerDataService = require(script.Parent.PlayerDataService)
local Notifier = require(script.Parent.Parent.Util.Notifier)
local SafeTeleport = require(script.Parent.Parent.Util.SafeTeleport)

local PlotService = {}

local plotOwners: { [Model]: Player } = {}
local playerPlots: { [Player]: Model } = {}
local assignedCallbacks: { (Player, Model) -> () } = {}
local releasedCallbacks: { (Player, Model) -> () } = {}

local function plotsFolder(): Folder
	return workspace:WaitForChild("Plots") :: Folder
end

function PlotService.GetPlot(player: Player): Model?
	return playerPlots[player]
end

function PlotService.GetOwner(plot: Model): Player?
	return plotOwners[plot]
end

function PlotService.GetOrigin(plot: Model): CFrame
	return plot:GetAttribute("Origin") :: CFrame
end

-- Where a player appears on a plot: the front yard, looking at the museum.
function PlotService.SpawnCFrame(plot: Model): CFrame
	return PlotService.GetOrigin(plot) * CFrame.new(0, 4, -26) * CFrame.Angles(0, math.pi, 0)
end

function PlotService.TeleportHome(player: Player): boolean
	local plot = playerPlots[player]
	local character = player.Character
	if not plot or not character then
		return false
	end
	return SafeTeleport.To(player, PlotService.SpawnCFrame(plot))
end

function PlotService.TeleportToPlot(player: Player, plot: Model): boolean
	local character = player.Character
	if not character then
		return false
	end
	return SafeTeleport.To(player, PlotService.SpawnCFrame(plot))
end

-- Callback when a player gets a plot / loses it.
function PlotService.OnAssigned(callback: (Player, Model) -> ())
	table.insert(assignedCallbacks, callback)
end

function PlotService.OnReleased(callback: (Player, Model) -> ())
	table.insert(releasedCallbacks, callback)
end

local function assign(player: Player)
	if playerPlots[player] then
		return
	end
	local plots = plotsFolder():GetChildren()
	table.sort(plots, function(a, b)
		return (a:GetAttribute("PlotIndex") or 0) < (b:GetAttribute("PlotIndex") or 0)
	end)
	for _, plot in plots do
		if plot:IsA("Model") and plotOwners[plot] == nil then
			plotOwners[plot] = player
			playerPlots[player] = plot
			plot:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("PlotIndex", plot:GetAttribute("PlotIndex"))
			for _, callback in assignedCallbacks do
				task.spawn(callback, player, plot)
			end
			PlotService.TeleportHome(player)
			return
		end
	end
	Notifier.Send(player, "This server is full of museums! Please join another server.", "Error")
	task.wait(3)
	player:Kick("This server has no free museum plots. Please join another server.")
end

local function release(player: Player)
	local plot = playerPlots[player]
	if not plot then
		return
	end
	for _, callback in releasedCallbacks do
		local ok, err = pcall(callback, player, plot)
		if not ok then
			warn("[PlotService] release callback error: " .. tostring(err))
		end
	end
	playerPlots[player] = nil
	plotOwners[plot] = nil
	plot:SetAttribute("OwnerUserId", 0)
end

function PlotService.Init() end

function PlotService.Start()
	PlayerDataService.OnLoaded(function(player)
		assign(player)
	end)
	-- Runs before the data is saved, while the plot still exists.
	PlayerDataService.OnReleasing(function(player)
		release(player)
	end)
	Players.PlayerRemoving:Connect(release) -- in case data never loaded

	local function onCharacter(player: Player, character: Model)
		-- Wait until the character is physically in the world, then move it home.
		character:WaitForChild("HumanoidRootPart", 10)
		task.wait()
		if playerPlots[player] and not player:GetAttribute("Jailed") then
			PlotService.TeleportHome(player)
		end
	end
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacter(player, character)
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, player in Players:GetPlayers() do
		watch(player)
	end
end

return PlotService
