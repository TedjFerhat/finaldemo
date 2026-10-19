--[[
	SafeTeleport
	Moving a character far away (the ruins are 1,000 studs from the hub) can
	drop the player through the world: with StreamingEnabled the client has not
	loaded the ground at the destination yet, so its physics lets the
	character fall. This module:
	  1. asks Roblox to stream the destination to that player first,
	  2. freezes the character for a moment while the ground arrives,
	  3. moves it, then unfreezes it.
	FallRescue (in ExplorationService) is the backup if anything still slips.
]]

local SafeTeleport = {}

local FREEZE_SECONDS = 0.75

function SafeTeleport.To(player: Player, target: CFrame): boolean
	local character = player.Character
	if not character then
		return false
	end
	if workspace.StreamingEnabled then
		pcall(function()
			player:RequestStreamAroundAsync(target.Position, 6)
		end)
	end
	-- The character may have reset while we waited for streaming.
	if player.Character ~= character or not character.Parent then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
		root.AssemblyLinearVelocity = Vector3.zero
		root.Anchored = true
	end
	character:PivotTo(target)
	if root and root:IsA("BasePart") then
		task.delay(FREEZE_SECONDS, function()
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.zero
				root.Anchored = false
			end
		end)
	end
	return true
end

return SafeTeleport
