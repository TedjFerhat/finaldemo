--[[
	Theme
	Colours, fonts and small helpers so every screen looks consistent:
	carved walnut frames around warm parchment panels, a cream title board,
	chunky rounded buttons with dark-ink or cream text, amber highlights.
	(`Gold` is kept as the name of the ACCENT token so every existing panel
	picks up the new style; real gold for money is `Cash`.)
]]

local TweenService = game:GetService("TweenService")

local Theme = {}

Theme.Colors = {
	-- Surfaces: warm parchment inside carved walnut frames
	Panel = Color3.fromRGB(246, 228, 192), -- parchment (window / card inside)
	PanelLight = Color3.fromRGB(236, 210, 166), -- rows, cards on parchment
	PanelLighter = Color3.fromRGB(218, 182, 134), -- tiles, wells, inputs
	Wood = Color3.fromRGB(140, 82, 48), -- frames and primary buttons
	WoodDark = Color3.fromRGB(96, 54, 30),
	Board = Color3.fromRGB(252, 240, 214), -- title boards
	-- Accents
	Gold = Color3.fromRGB(176, 104, 56), -- PRIMARY BUTTON (warm wood) — legacy name
	GoldDark = Color3.fromRGB(120, 66, 34),
	Accent = Color3.fromRGB(232, 154, 46), -- amber highlight (selected tab, active dock tile)
	Accent2 = Color3.fromRGB(196, 96, 40), -- burnt orange (eyebrows, gradients)
	Highlight = Color3.fromRGB(255, 246, 222),
	Outline = Color3.fromRGB(92, 50, 26), -- walnut outline
	Cash = Color3.fromRGB(255, 204, 64),
	-- Text (dark ink on parchment; cream on wood)
	Text = Color3.fromRGB(66, 38, 20),
	TextDim = Color3.fromRGB(126, 92, 62),
	ButtonText = Color3.fromRGB(255, 246, 226),
	Success = Color3.fromRGB(92, 160, 66),
	Danger = Color3.fromRGB(212, 62, 50),
	Blue = Color3.fromRGB(70, 122, 182),
	Disabled = Color3.fromRGB(190, 170, 142),
	Parchment = Color3.fromRGB(246, 228, 192),
}

-- Readable text colour for any background (dark ink on light, cream on dark).
function Theme.TextOn(bg: Color3): Color3
	local lum = 0.299 * bg.R + 0.587 * bg.G + 0.114 * bg.B
	return if lum > 0.62 then Theme.Colors.Text else Theme.Colors.ButtonText
end

-- Style tokens (sizes) shared by the HUD and windows.
Theme.Tokens = {
	Radius = 16,
	RadiusSmall = 10,
	Stroke = 2,
	Pad = 10,
	ButtonHeight = 40,
}

-- Rounded, chunky display font for titles/buttons; clean sans for body text.
Theme.Fonts = {
	Title = Enum.Font.FredokaOne,
	Body = Enum.Font.GothamMedium,
	Bold = Enum.Font.FredokaOne,
}

-- Generic instance creator: Theme.New("Frame", { Size = ... }, { children })
function Theme.New(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for key, value in props do
			if key == "Parent" then
				parent = value
			else
				(inst :: any)[key] = value
			end
		end
	end
	if children then
		for _, child in children do
			child.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Theme.Corner(parent: Instance, radius: number?): UICorner
	return Theme.New("UICorner", { CornerRadius = UDim.new(0, radius or 10), Parent = parent })
end

function Theme.Stroke(parent: Instance, color: Color3?, thickness: number?): UIStroke
	-- Outlines stay subtle: accent-coloured borders are drawn in the outline
	-- tone, and no border is thicker than the token. One stroke per object
	-- (a second call just restyles the existing one).
	local c = color or Theme.Colors.Outline
	if c == Theme.Colors.Gold then
		c = Theme.Colors.Outline
	end
	local existing = parent:FindFirstChildOfClass("UIStroke")
	if existing then
		existing.Color = c
		existing.Transparency = 0.3
		return existing
	end
	return Theme.New("UIStroke", {
		Color = c,
		Thickness = math.min(thickness or Theme.Tokens.Stroke, Theme.Tokens.Stroke),
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = parent,
	})
end

function Theme.Padding(parent: Instance, px: number)
	Theme.New("UIPadding", {
		PaddingTop = UDim.new(0, px),
		PaddingBottom = UDim.new(0, px),
		PaddingLeft = UDim.new(0, px),
		PaddingRight = UDim.new(0, px),
		Parent = parent,
	})
end

-- Text label with sensible defaults. maxTextSize keeps scaled text readable.
function Theme.Label(text: string, props: { [string]: any }?, maxTextSize: number?): TextLabel
	local label = Theme.New("TextLabel", {
		BackgroundTransparency = 1,
		Text = text,
		Font = Theme.Fonts.Body,
		TextColor3 = Theme.Colors.Text,
		TextScaled = true,
		RichText = true,
		Size = UDim2.fromScale(1, 1),
	})
	if props then
		for key, value in props do
			(label :: any)[key] = value
		end
	end
	Theme.New("UITextSizeConstraint", { MaxTextSize = maxTextSize or 22, MinTextSize = 9, Parent = label })
	return label
end

local clickCallback: (() -> ())? = nil
function Theme.SetClickSound(callback: () -> ())
	clickCallback = callback
end

-- Big friendly button (works with mouse, touch and gamepad).
-- Vertical shading gradient (multiplies the background colour): lighter at
-- the top, slightly darker/violet at the bottom. Gives depth to any panel.
function Theme.Shade(inst: GuiObject, strength: number?): UIGradient
	local k = 1 - (strength or 0.2)
	return Theme.New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.new(k, k * 0.97, math.min(1, k * 1.08))),
		Parent = inst,
	})
end

-- Glass edge: a thin stroke that's bright on top and fades at the bottom.
function Theme.GlassEdge(inst: GuiObject, transparency: number?): UIStroke
	local stroke = Theme.New("UIStroke", {
		Color = Theme.Colors.Outline,
		Thickness = 2,
		Transparency = transparency or 0.1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
		Parent = inst,
	})
	Theme.New("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new(0, 0),
		Parent = stroke,
	})
	return stroke
end

-- A framed card in the game's style: soft drop shadow, a carved walnut frame
-- and an inset parchment panel. Returns (holder, panel); put content in the
-- panel. `frameWidth` = thickness of the wood border (0 = parchment only).
function Theme.Card(props: { [string]: any }, radius: number?, frameWidth: number?): (Frame, Frame)
	local r = radius or 16
	local fw = frameWidth or 6
	local holder = Theme.New("Frame", { BackgroundTransparency = 1 })
	for k, v in props do
		(holder :: any)[k] = v
	end
	local shadow = Theme.New("Frame", {
		Name = "Shadow",
		BackgroundColor3 = Color3.fromRGB(40, 20, 8),
		BackgroundTransparency = 0.55,
		Position = UDim2.fromOffset(0, 6),
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = holder.ZIndex,
		Parent = holder,
	})
	Theme.Corner(shadow, r)
	local wood = Theme.New("Frame", {
		Name = "Frame",
		BackgroundColor3 = Theme.Colors.Wood,
		Size = UDim2.fromScale(1, 1),
		ZIndex = holder.ZIndex,
		Parent = holder,
	})
	Theme.Corner(wood, r)
	Theme.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 236, 214), Color3.fromRGB(190, 160, 140)), Parent = wood })
	Theme.New("UIStroke", { Color = Theme.Colors.Outline, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = wood })
	local panel = Theme.New("Frame", {
		Name = "Panel",
		BackgroundColor3 = Theme.Colors.Panel,
		Position = UDim2.fromOffset(fw, fw),
		Size = UDim2.new(1, -2 * fw, 1, -2 * fw),
		ZIndex = holder.ZIndex,
		Parent = wood,
	})
	Theme.Corner(panel, math.max(4, r - fw + 2))
	Theme.New("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(236, 222, 200)), Parent = panel })
	Theme.New("UIStroke", { Color = Theme.Colors.WoodDark, Thickness = 1.5, Transparency = 0.35, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = panel })
	return holder, panel
end

-- Small rounded "eyebrow" label (e.g. OBJECTIVE) in the accent colour.
function Theme.Eyebrow(text: string, props: { [string]: any }?): TextLabel
	local l = Theme.Label(text, { Font = Theme.Fonts.Bold, TextColor3 = Theme.Colors.Accent2, TextXAlignment = Enum.TextXAlignment.Left }, 12)
	if props then
		for k, v in props do
			(l :: any)[k] = v
		end
	end
	return l
end

-- Chunky rounded button with a walnut outline and a soft top-lit gradient.
-- Text colour follows the background automatically (ink on light, cream on
-- dark) and also when the colour changes later.
function Theme.Button(text: string, color: Color3?, onClick: (() -> ())?, maxTextSize: number?): TextButton
	local bg = color or Theme.Colors.Gold
	local button = Theme.New("TextButton", {
		AutoButtonColor = true,
		BackgroundColor3 = bg,
		Text = text,
		Font = Theme.Fonts.Bold,
		TextColor3 = Theme.TextOn(bg),
		TextStrokeColor3 = Theme.Colors.Outline,
		TextStrokeTransparency = if Theme.TextOn(bg) == Theme.Colors.ButtonText then 0.55 else 1,
		TextScaled = true,
		RichText = true,
		Size = UDim2.fromOffset(120, 40),
	})
	Theme.Corner(button, Theme.Tokens.RadiusSmall)
	Theme.New("UIGradient", {
		Rotation = 90,
		Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(206, 186, 168)),
		Parent = button,
	})
	Theme.New("UIStroke", { Color = Theme.Colors.Outline, Transparency = 0.15, Thickness = 2, ApplyStrokeMode = Enum.ApplyStrokeMode.Border, Parent = button })
	Theme.New("UITextSizeConstraint", { MaxTextSize = maxTextSize or 20, MinTextSize = 9, Parent = button })
	Theme.New("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = button })
	button:GetPropertyChangedSignal("BackgroundColor3"):Connect(function()
		local ink = Theme.TextOn(button.BackgroundColor3)
		button.TextColor3 = ink
		button.TextStrokeTransparency = if ink == Theme.Colors.ButtonText then 0.55 else 1
	end)
	local scale = Theme.New("UIScale", { Parent = button })
	button.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1.05 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.95 }):Play()
	end)
	button.MouseButton1Up:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.12, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end)
	if onClick then
		button.Activated:Connect(function()
			if button:GetAttribute("Disabled") then
				return
			end
			if clickCallback then
				clickCallback()
			end
			onClick()
		end)
	end
	return button
end

function Theme.SetButtonEnabled(button: TextButton, enabled: boolean, enabledColor: Color3)
	button:SetAttribute("Disabled", not enabled)
	button.AutoButtonColor = enabled
	button.BackgroundColor3 = if enabled then enabledColor else Theme.Colors.Disabled
	button.TextTransparency = if enabled then 0 else 0.35
end

function Theme.ListLayout(parent: Instance, padding: number?, horizontal: boolean?): UIListLayout
	return Theme.New("UIListLayout", {
		Padding = UDim.new(0, padding or 6),
		FillDirection = if horizontal then Enum.FillDirection.Horizontal else Enum.FillDirection.Vertical,
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = parent,
	})
end

-- Scrolling list whose canvas grows with its content.
function Theme.Scroller(props: { [string]: any }?): ScrollingFrame
	local frame = Theme.New("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ScrollBarThickness = 6,
		ScrollBarImageColor3 = Theme.Colors.Gold,
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollingDirection = Enum.ScrollingDirection.Y,
		Size = UDim2.fromScale(1, 1),
	})
	if props then
		for key, value in props do
			(frame :: any)[key] = value
		end
	end
	return frame
end

-- Gives every dark panel/row on screen the same soft depth gradient, including
-- ones panels create later (list rows etc.), so no window looks flat.
function Theme.AutoPolish(root: Instance)
	local tones = { Theme.Colors.Panel, Theme.Colors.PanelLight, Theme.Colors.PanelLighter }
	local function polish(inst: Instance)
		if not inst:IsA("Frame") or inst.BackgroundTransparency > 0.5 then
			return
		end
		if not table.find(tones, inst.BackgroundColor3) then
			return
		end
		if inst:FindFirstChildOfClass("UIGradient") then
			return
		end
		Theme.Shade(inst, 0.14)
	end
	for _, d in root:GetDescendants() do
		polish(d)
	end
	root.DescendantAdded:Connect(function(d)
		task.defer(polish, d)
	end)
end

function Theme.Hex(c: Color3): string
	return string.format("#%02X%02X%02X", math.floor(c.R * 255), math.floor(c.G * 255), math.floor(c.B * 255))
end

return Theme
