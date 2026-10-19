--[[
	JailService
	Caught thieves spend a short, visible sentence in the holding cell in the
	hub. The sentence is saved (os.time), so leaving and rejoining doesn't
	skip it. Nothing else is taken away here — the heist system decides any
	(modest) fine.
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local PlayerDataService = require(script.Parent.PlayerDataService)
local PlotService = require(script.Parent.PlotService)
local Net = require(script.Parent.Parent.Util.Net)
local SafeTeleport = require(script.Parent.Parent.Util.SafeTeleport)
local WorldBuilder = require(script.Parent.Parent.World.WorldBuilder)

local JailService = {}

local reasons: { [Player]: string } = {}

local function secondsLeft(player: Player): number
	local data = PlayerDataService.GetData(player)
	if not data then
		return 0
	end
	return math.max(0, data.Heist.JailUntil - os.time())
end

local function sendUpdate(player: Player)
	local left = secondsLeft(player)
	Net.Fire("JailUpdate", player, { Active = left > 0, SecondsLeft = left, Reason = reasons[player] })
end

local function placeInCell(player: Player)
	if player.Character then
		SafeTeleport.To(player, WorldBuilder.JailCFrame)
	end
end

local function release(player: Player)
	player:SetAttribute("Jailed", nil)
	reasons[player] = nil
	sendUpdate(player)
	PlotService.TeleportHome(player)
end

function JailService.IsJailed(player: Player): boolean
	return player:GetAttribute("Jailed") == true
end

function JailService.Jail(player: Player, seconds: number, reason: string)
	local data = PlayerDataService.GetData(player)
	if not data then
		return
	end
	data.Heist.JailUntil = os.time() + seconds
	reasons[player] = reason
	player:SetAttribute("Jailed", true)
	placeInCell(player)
	sendUpdate(player)
end

function JailService.Init() end

function JailService.Start()
	-- Resume a saved sentence on join
	PlayerDataService.OnLoaded(function(player)
		if secondsLeft(player) > 0 then
			reasons[player] = "You left during a heist."
			player:SetAttribute("Jailed", true)
			task.wait(1.5) -- let PlotService place the character first
			placeInCell(player)
			sendUpdate(player)
		end
	end)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			if JailService.IsJailed(player) then
				task.wait(0.2)
				placeInCell(player)
			end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in Players:GetPlayers() do
		watch(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		reasons[player] = nil
	end)
	-- Keep prisoners in the cell; release when the time is up.
	task.spawn(function()
		while true do
			task.wait(1)
			for _, player in Players:GetPlayers() do
				if JailService.IsJailed(player) then
					if secondsLeft(player) <= 0 then
						release(player)
					else
						local character = player.Character
						local root = character and character:FindFirstChild("HumanoidRootPart")
						if root and root:IsA("BasePart") and (root.Position - WorldBuilder.JailCFrame.Position).Magnitude > Config.JailRadius then
							placeInCell(player)
						end
						sendUpdate(player)
					end
				end
			end
		end
	end)
end

return JailService
