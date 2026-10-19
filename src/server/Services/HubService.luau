--[[
	HubService
	Keeps the Museum Directory board in the plaza up to date: the top museums
	on this server by prestige. (Players can visit them from the Museums menu.)
]]

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Upgrades = require(Shared.Upgrades)

local HubService = {}

local function refresh()
	local world = workspace:FindFirstChild("World")
	local board = world and world:FindFirstChild("DirectoryBoard", true)
	local label = board and board:FindFirstChild("Text", true)
	if not label or not label:IsA("TextLabel") then
		return
	end
	local entries = {}
	for _, player in Players:GetPlayers() do
		local prestige = player:GetAttribute("Prestige")
		local level = player:GetAttribute("MuseumLevel")
		if type(prestige) == "number" and type(level) == "number" then
			table.insert(entries, { Name = player.DisplayName, Prestige = prestige, Level = level })
		end
	end
	table.sort(entries, function(a, b)
		return a.Prestige > b.Prestige
	end)
	local lines = { "<b>MUSEUM DIRECTORY</b>", "<font size=\"20\">Most prestigious museums on this server</font>", "" }
	for i = 1, math.min(8, #entries) do
		local e = entries[i]
		table.insert(lines, ("%d. %s  —  %s  ·  %d prestige"):format(i, e.Name, Upgrades.LevelNames[e.Level] or "", e.Prestige))
	end
	if #entries == 0 then
		table.insert(lines, "No museums open yet.")
	end
	label.Text = table.concat(lines, "\n")
end

function HubService.Init() end

function HubService.Start()
	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(10)
		end
	end)
end

return HubService
