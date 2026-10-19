--[[
	SearchBar
	The progress bar shown while you search a site. The SERVER decides how
	long the search takes and what you find; this only shows progress.
]]

local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local Theme = require(script.Parent.Theme)
local Sounds = require(script.Parent.Sounds)
local Notifications = require(script.Parent.Notifications)

local SearchBar = {}

local frame: Frame
local fill: Frame
local label: TextLabel
local activeToken = 0

local function hide()
	activeToken += 1
	frame.Visible = false
end

function SearchBar.Init(screen: ScreenGui)
	frame = Theme.New("Frame", {
		Name = "SearchBar",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 0.8, 0),
		Size = UDim2.new(0.4, 0, 0, 58),
		BackgroundColor3 = Theme.Colors.Panel,
		Visible = false,
		Parent = screen,
	})
	Theme.New("UISizeConstraint", { MaxSize = Vector2.new(440, 58), MinSize = Vector2.new(240, 0), Parent = frame })
	Theme.Corner(frame, 12)
	Theme.Stroke(frame, Theme.Colors.Gold, 2)
	label = Theme.Label("Searching...", { Font = Theme.Fonts.Bold, Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 22) }, 18)
	label.Parent = frame
	local track = Theme.New("Frame", {
		BackgroundColor3 = Theme.Colors.PanelLighter,
		Position = UDim2.new(0, 10, 0, 32),
		Size = UDim2.new(1, -20, 0, 16),
		Parent = frame,
	})
	Theme.Corner(track, 8)
	fill = Theme.New("Frame", { BackgroundColor3 = Theme.Colors.Gold, Size = UDim2.fromScale(0, 1), Parent = track })
	Theme.Corner(fill, 8)

	Remotes.Event("SearchStarted").OnClientEvent:Connect(function(info)
		if type(info) ~= "table" then
			return
		end
		activeToken += 1
		local token = activeToken
		local duration = math.max(0.1, tonumber(info.Duration) or 1)
		label.Text = ("Searching %s..."):format(tostring(info.SiteName or "site"))
		fill.Size = UDim2.fromScale(0, 1)
		frame.Visible = true
		TweenService:Create(fill, TweenInfo.new(duration, Enum.EasingStyle.Linear), { Size = UDim2.fromScale(1, 1) }):Play()
		-- Digging sound loop while the search is running
		task.spawn(function()
			local started = os.clock()
			while activeToken == token and os.clock() - started < duration do
				Sounds.Play("Search", 0.35, 0.8 + math.random() * 0.4)
				task.wait(0.45)
			end
		end)
		-- Safety: hide if the server never answers
		task.delay(duration + 3, function()
			if activeToken == token then
				hide()
			end
		end)
	end)

	Remotes.Event("SearchEnded").OnClientEvent:Connect(function(info)
		hide()
		if type(info) == "table" and not info.Success and info.Reason then
			Notifications.Show(tostring(info.Reason), "Error")
		end
	end)
end

return SearchBar
