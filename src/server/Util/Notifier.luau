--[[
	Notifier
	Sends toast messages to a player's screen.
	Kinds: "Info", "Success", "Error", "Reward"
]]

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Notifier = {}

function Notifier.Send(player: Player, text: string, kind: string?)
	if player.Parent == nil then
		return
	end
	Remotes.Event("Notify"):FireClient(player, { Text = text, Kind = kind or "Info" })
end

return Notifier
