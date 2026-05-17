-- HUDButtonBar.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Last updated: 2026-04-23 23:35
-- Bottom-center clickable button bar for all menus. Uses scale-based layout and viewport text scaling.
-- Clicking a button fires a BindableEvent that the corresponding menu script listens to.
-- Keyboard shortcuts still work independently in each menu script.
-- FIX: PlayerGui is cleared on respawn; we restore the bar and HUDToggleMenu on CharacterAdded.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TextService = game:GetService("TextService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")

-- #region agent log
local function _agentLog(hypothesisId, location, message, data)
	local payload
	local okEnc = pcall(function()
		payload = HttpService:JSONEncode({
			sessionId = "0954a4",
			hypothesisId = hypothesisId,
			location = location,
			message = message,
			data = data or {},
			timestamp = math.floor(tick() * 1000),
			runId = "pre-fix",
		})
	end)
	if not okEnc or not payload then return end
	local dataEnc = ""
	pcall(function() dataEnc = HttpService:JSONEncode(data or {}) end)
	warn("[AGENT0954] " .. tostring(hypothesisId) .. " | " .. tostring(location) .. " | " .. tostring(message) .. " | " .. dataEnc)
	pcall(function()
		HttpService:PostAsync(
			"http://127.0.0.1:7882/ingest/0e60cc12-9e09-414c-83d4-0479f687e09e",
			payload,
			Enum.HttpContentType.ApplicationJson,
			false,
			{ ["X-Debug-Session-Id"] = "0954a4" }
		)
	end)
end
-- #endregion

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local toggleEvent
local sg
local setActiveAndMoveFunc -- set by buildHUDButtonBar, used by CAS for H key

-- Design constants (glassmorphism + golden ring)
local TOOLBAR_BG = Color3.fromRGB(14, 16, 24)
local TOOLBAR_BG_TRANSPARENCY = 0.18
local TOOLBAR_STROKE = Color3.fromRGB(60, 60, 80)
local TOOLBAR_CORNER_RADIUS = 18
local GOLD_RING = Color3.fromRGB(196, 151, 70)  -- #c49746
local GOLD_GLOW = Color3.fromRGB(232, 175, 72)  -- #e8af48
local GOLD_GLOW_TRANSPARENCY = 0.85

-- Button definitions (module-level so InputBegan can reference after restore)
local buttonDefs = {
	{ label = "[K] Codex",      key = "K", menuName = "CodexGuide",     color = Color3.fromRGB(180, 140, 255), desc = "Guide, Lore, creatures" },
	{ label = "[M] Map",        key = "M", menuName = "WorldMapGUI",    color = Color3.fromRGB(120, 200, 255), desc = "World map & your position" },
	{ label = "[Q] SiegelinQ",   key = "Q", menuName = "InventoryUI",    color = Color3.fromRGB(60, 160, 255), desc = "Manage creatures" },
	-- FIX #34: Sigils & Rebirth moved into Profile tabs (removed standalone buttons)
	{ label = "[G] Shop",       key = "G", menuName = "ShopHubGUI",     color = Color3.fromRGB(120, 220, 170), desc = "Eggs, swag, and cosmetics" },
	{ label = "[V] Friends",    key = "V", menuName = "FriendsListGUI", color = Color3.fromRGB(255, 130, 80), desc = "Base access list" },
	{ label = "[X] Leaders",    key = "X", menuName = "LeaderboardGUI", color = Color3.fromRGB(100, 220, 160), desc = "Leaderboards" },
	{ label = "[P] Profile",    key = "P", menuName = "ProfileGUI",     color = Color3.fromRGB(200, 180, 255), desc = "Player profile, sigils & rebirth" },
	{ label = "[H] Recall", key = "H", menuName = "GoHome",  color = Color3.fromRGB(255, 220, 100), desc = "Channel 5s to return to base (interrupt on damage)" },
}

local indicatorMenuAliases = {
	EggShopGUI = "ShopHubGUI",
	BuffShopGUI = "ShopHubGUI",
	CosmeticShopGUI = "ShopHubGUI",
	ScoinsShopGUI = "ShopHubGUI",
	GemsShopGUI = "ShopHubGUI",
}

local function normalizeIndicatorMenuName(menuName)
	return indicatorMenuAliases[menuName] or menuName
end

-- Create or reuse shared BindableEvent for menu toggling (so menu scripts can connect before we run)
local function ensureToggleEvent()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if evt and evt:IsA("BindableEvent") then
		toggleEvent = evt
		return evt
	end
	toggleEvent = Instance.new("BindableEvent")
	toggleEvent.Name = "HUDToggleMenu"
	toggleEvent.Parent = playerGui
	return toggleEvent
end

local function buildHUDButtonBar()
	-- Build new bar FIRST so we never have a frame with no bar (avoids disappearance if we error mid-build)
	ensureToggleEvent()

	local old = playerGui:FindFirstChild("HUDButtonBar")
	-- Screen GUI
	sg = Instance.new("ScreenGui")
	sg.Name = "HUDButtonBar"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 40
	sg.Parent = playerGui
	-- Remove old bar only after new one is safely parented (avoids disappearance if build errors)
	if old and old ~= sg then old:Destroy() end

	--[[ TEXT SCALING (viewport-based, same approach as LaunchScreen)
     getTextScale() returns a multiplier from CurrentCamera.ViewportSize vs reference resolution.
     TEXT_SIZE_MULTIPLIER boosts result for readability; tune if text is too small/large. ]]
local TEXT_REFERENCE_WIDTH = 1920
local TEXT_REFERENCE_HEIGHT = 1080
local TEXT_SCALE_CLAMP_MIN = 0.6
local TEXT_SCALE_CLAMP_MAX = 1.5
local TEXT_SIZE_MULTIPLIER = 1.85

local function getTextScale()
	local camera = workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(TEXT_REFERENCE_WIDTH, TEXT_REFERENCE_HEIGHT)
	local raw = math.min(viewport.X / TEXT_REFERENCE_WIDTH, viewport.Y / TEXT_REFERENCE_HEIGHT)
	return math.clamp(raw, TEXT_SCALE_CLAMP_MIN, TEXT_SCALE_CLAMP_MAX) * TEXT_SIZE_MULTIPLIER
end

local textScale = getTextScale()


-- BAR LAYOUT (scale-based, design reference 1920x1080)sd
-- Container sits at bottom-center; BAR_HEIGHT_SCALE = bar height (reduced to give more space for target UI above)
local BAR_HEIGHT_SCALE = 32/1080
-- Button height +50% (selectable buttons around the text)
local BUTTON_HEIGHT_MULTIPLIER = 1.0
-- Scale entire bar/buttons up or down (e.g. 1.3 = 30% larger)
local BUTTON_BAR_SCALE = 1.35
-- Mobile: taller bar and larger touch targets (easier to tap); +35% height, lifted
local MOBILE_BAR_SCALE = 1.55 * 1.35  -- 35% taller on mobile
local MOBILE_BAR_LIFT_PX = 1         -- lift bar up (lowered another 5px on mobile)
local MOBILE_BUTTON_HEIGHT_MULTIPLIER = 1.40  -- +25% button height on mobile only
local MOBILE_MIN_BUTTON_WIDTH = 44   -- minimum tap target (Apple HIG ~44pt)
local MOBILE_MIN_BUTTON_GAP = 4      -- minimum gap between buttons (no crossover)
-- Gap between buttons (pixels) for dynamic bubble sizing
local BAR_BUTTON_PADDING_PX = 6
local BAR_BUTTON_TEXT_PADDING_PX = 16  -- horizontal padding inside each button so text doesn't touch edge

	-- Mobile: narrower viewport or touch input = larger tap targets
	local camera = workspace.CurrentCamera
	local vw0 = (camera and camera.ViewportSize.X) or 1920
	local isMobile = vw0 < 700 or UserInputService.TouchEnabled
	local barScale = isMobile and MOBILE_BAR_SCALE or BUTTON_BAR_SCALE
	local buttonGap = isMobile and math.max(BAR_BUTTON_PADDING_PX, MOBILE_MIN_BUTTON_GAP) or BAR_BUTTON_PADDING_PX

	-- Toolbar wrapper: dark glassmorphism, centered at bottom; mobile: +25% button height
	local mobileHeightMult = isMobile and MOBILE_BUTTON_HEIGHT_MULTIPLIER or 1
	local toolbar = Instance.new("Frame")
	toolbar.Name = "Toolbar"
	toolbar.AnchorPoint = Vector2.new(0.5, 1)
	toolbar.Size = UDim2.new(0, 0, BAR_HEIGHT_SCALE * barScale * BUTTON_HEIGHT_MULTIPLIER * mobileHeightMult, 0)
	toolbar.AutomaticSize = Enum.AutomaticSize.X
	toolbar.Position = UDim2.new(0.5, 0, 1, isMobile and -MOBILE_BAR_LIFT_PX or 0)
	toolbar:SetAttribute("BottomLiftPx", isMobile and MOBILE_BAR_LIFT_PX or 0)
	toolbar.BackgroundColor3 = TOOLBAR_BG
	toolbar.BackgroundTransparency = 1  -- no background bar (was distracting)
	toolbar.BorderSizePixel = 0
	toolbar.Parent = sg
	local toolbarCorner = Instance.new("UICorner", toolbar)
	toolbarCorner.CornerRadius = UDim.new(0, TOOLBAR_CORNER_RADIUS)

	-- Padding inside toolbar (so glassmorphism frame wraps content)
	local toolbarPadding = Instance.new("UIPadding", toolbar)
	toolbarPadding.PaddingLeft = UDim.new(0, 12)
	toolbarPadding.PaddingRight = UDim.new(0, 12)
	toolbarPadding.PaddingTop = UDim.new(0, 6)
	toolbarPadding.PaddingBottom = UDim.new(0, 6)

	local container = Instance.new("Frame")
	container.Name = "ButtonContainer"
	container.Size = UDim2.new(0, 0, 1, 0)
	container.AutomaticSize = Enum.AutomaticSize.X
	container.Position = UDim2.new(0, 0, 0, 0)
	container.BackgroundTransparency = 1
	container.Parent = toolbar

-- Horizontal list; button widths set dynamically to fit text (bubbles scale to text length)
local list = Instance.new("UIListLayout")
list.Parent = container
list.FillDirection = Enum.FillDirection.Horizontal
list.HorizontalAlignment = Enum.HorizontalAlignment.Center
list.VerticalAlignment = Enum.VerticalAlignment.Center
list.Padding = UDim.new(0, buttonGap)
list.SortOrder = Enum.SortOrder.LayoutOrder

	-- Day/Night read-only indicator (sun when day, moon when night)
	local SUN_ICON = "rbxassetid://6031094678"
	local MOON_ICON = "rbxassetid://6031097220"
	local function isNight()
		local ok, cfg = pcall(function() return require(ReplicatedStorage.Modules.GameConfig) end)
		if not ok or not cfg or not cfg.DayNightCycleEnabled then return false end
		local ct = Lighting.ClockTime
		local startH = tonumber(cfg.NightStartHour) or 18
		local endH = tonumber(cfg.NightEndHour) or 6
		if startH > endH then
			return ct >= startH or ct < endH
		end
		return ct >= startH and ct < endH
	end
	local dayNightFrame = Instance.new("Frame")
	dayNightFrame.Name = "DayNightIndicator"
	dayNightFrame.LayoutOrder = 999
	dayNightFrame.Size = UDim2.new(0, 28, 1, 0)
	dayNightFrame.BackgroundTransparency = 1
	dayNightFrame.Parent = container
	local sunImg = Instance.new("ImageLabel")
	sunImg.Name = "Sun"
	sunImg.Size = UDim2.new(0.7, 0, 0.7, 0)
	sunImg.Position = UDim2.new(0.15, 0, 0.15, 0)
	sunImg.BackgroundTransparency = 1
	sunImg.Image = SUN_ICON
	sunImg.ImageColor3 = Color3.fromRGB(255, 220, 100)
	sunImg.ImageTransparency = 0
	sunImg.ScaleType = Enum.ScaleType.Fit
	sunImg.Parent = dayNightFrame
	local moonImg = Instance.new("ImageLabel")
	moonImg.Name = "Moon"
	moonImg.Size = UDim2.new(0.7, 0, 0.7, 0)
	moonImg.Position = UDim2.new(0.15, 0, 0.15, 0)
	moonImg.BackgroundTransparency = 1
	moonImg.Image = MOON_ICON
	moonImg.ImageColor3 = Color3.fromRGB(200, 210, 255)
	moonImg.ImageTransparency = 1
	moonImg.ScaleType = Enum.ScaleType.Fit
	moonImg.Parent = dayNightFrame
	local function updateDayNight()
		local night = isNight()
		TweenService:Create(sunImg, TweenInfo.new(0.5), { ImageTransparency = night and 1 or 0 }):Play()
		TweenService:Create(moonImg, TweenInfo.new(0.5), { ImageTransparency = night and 0 or 1 }):Play()
		if night then
			TweenService:Create(moonImg, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0.8, 0, 0.8, 0) }):Play()
			task.delay(0.3, function() if moonImg.Parent then TweenService:Create(moonImg, TweenInfo.new(0.25), { Size = UDim2.new(0.7, 0, 0.7, 0) }):Play() end end)
		else
			TweenService:Create(sunImg, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = UDim2.new(0.8, 0, 0.8, 0) }):Play()
			task.delay(0.3, function() if sunImg.Parent then TweenService:Create(sunImg, TweenInfo.new(0.25), { Size = UDim2.new(0.7, 0, 0.7, 0) }):Play() end end)
		end
	end
	updateDayNight()
	Lighting:GetPropertyChangedSignal("ClockTime"):Connect(updateDayNight)
	task.spawn(function()
		while toolbar and toolbar.Parent do
			task.wait(2)
			if toolbar and toolbar.Parent then updateDayNight() end
		end
	end)

	-- Golden active indicator (slides between buttons with Elastic easing)
	-- Renders behind buttons; exact outline of button (same size and rounded corners)
	local BUTTON_CORNER_RADIUS = 8
	local indicator = Instance.new("Frame")
	indicator.Name = "ActiveIndicator"
	indicator.BackgroundTransparency = 1
	indicator.BorderSizePixel = 0
	indicator.Size = UDim2.new(0, 60, 0, 36)
	indicator.Position = UDim2.new(0, 0, 0, 0)
	indicator.AnchorPoint = Vector2.new(0.5, 0.5)
	indicator.ZIndex = 0
	indicator.Visible = false
	indicator.Parent = toolbar
	local indCorner = Instance.new("UICorner", indicator)
	indCorner.CornerRadius = UDim.new(0, BUTTON_CORNER_RADIUS)
	local indStroke = Instance.new("UIStroke", indicator)
	indStroke.Color = GOLD_RING
	indStroke.Thickness = 2
	indStroke.Transparency = 0
	-- Glow behind ring (same shape and size as indicator for clean outline)
	local indGlow = Instance.new("Frame")
	indGlow.Name = "Glow"
	indGlow.Size = UDim2.new(1, 0, 1, 0)
	indGlow.Position = UDim2.new(0.5, 0, 0.5, 0)
	indGlow.AnchorPoint = Vector2.new(0.5, 0.5)
	indGlow.BackgroundColor3 = GOLD_GLOW
	indGlow.BackgroundTransparency = GOLD_GLOW_TRANSPARENCY
	indGlow.BorderSizePixel = 0
	indGlow.ZIndex = -1
	indGlow.Parent = indicator
	Instance.new("UICorner", indGlow).CornerRadius = UDim.new(0, BUTTON_CORNER_RADIUS)

	local activeMenuName = nil
	local function moveIndicatorToButton(btn, animate)
		if not btn or not btn.Parent or not toolbar.Parent then return end
		indicator.Visible = true
		local btnPos = btn.AbsolutePosition
		local btnSize = btn.AbsoluteSize
		local toolPos = toolbar.AbsolutePosition
		-- FIX #19: Indicator position must subtract toolbar UIPadding (Left=12, Top=6)
		-- because indicator.Position is relative to the padded content area, but
		-- AbsolutePosition differences are relative to toolbar's outer edge.
		local x = (btnPos.X - toolPos.X) + btnSize.X / 2 - 12
		local y = (btnPos.Y - toolPos.Y) + btnSize.Y / 2 - 4
		indicator.Size = UDim2.new(0, btnSize.X + 4, 0, btnSize.Y + 4)
		indGlow.Size = UDim2.new(1, 0, 1, 0)
		local targetPos = UDim2.new(0, x, 0, y)
		if animate then
			TweenService:Create(indicator, TweenInfo.new(0.4, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Position = targetPos }):Play()
		else
			indicator.Position = targetPos
		end
	end
	local function moveIndicatorToActive(animate)
		if activeMenuName then
			local btn = container:FindFirstChild(activeMenuName)
			if btn and btn:IsA("GuiObject") then
				moveIndicatorToButton(btn, animate)
			end
		else
			indicator.Visible = false
		end
	end
	local function setActiveAndMove(menuName, animate)
		activeMenuName = menuName
		moveIndicatorToActive(animate)
	end
	setActiveAndMoveFunc = setActiveAndMove

-- Tooltip (auto-sizes to fit text; position is set in pixels above the hovered button)
local TOOLTIP_GAP_PX = 6
local TOOLTIP_PADDING_PX = 10
local tipLabel = Instance.new("TextLabel")
tipLabel.AutomaticSize = Enum.AutomaticSize.XY
tipLabel.Size = UDim2.new(0, 0, 0, 0)
tipLabel.AnchorPoint = Vector2.new(0.5, 1)
tipLabel.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
tipLabel.BackgroundTransparency = 0.1
tipLabel.BorderSizePixel = 0
tipLabel.Visible = false
tipLabel.Font = Enum.Font.GothamMedium
tipLabel.TextSize = math.max(10, math.floor(10 * textScale))
tipLabel.TextColor3 = Color3.fromRGB(180, 185, 200)
tipLabel.TextXAlignment = Enum.TextXAlignment.Center
tipLabel.TextYAlignment = Enum.TextYAlignment.Center
tipLabel.Parent = sg
Instance.new("UICorner", tipLabel).CornerRadius = UDim.new(0, 6)
local tipPadding = Instance.new("UIPadding", tipLabel)
tipPadding.PaddingLeft = UDim.new(0, TOOLTIP_PADDING_PX)
tipPadding.PaddingRight = UDim.new(0, TOOLTIP_PADDING_PX)
tipPadding.PaddingTop = UDim.new(0, 6)
tipPadding.PaddingBottom = UDim.new(0, 6)

-- Update each button width to fit its text (dynamic bubble sizing so text doesn't hang off)
-- On mobile: larger tap targets (min 44px), no overlap; scale down only if needed to fit
local function updateBarButtonSizes()
	local camera = workspace.CurrentCamera
	if not camera then return end
	local vw = camera.ViewportSize.X
	local vh = camera.ViewportSize.Y
	local mobile = vw < 700 or UserInputService.TouchEnabled
	local currentBarScale = mobile and MOBILE_BAR_SCALE or BUTTON_BAR_SCALE
	local mobileHeightMult = mobile and MOBILE_BUTTON_HEIGHT_MULTIPLIER or 1
	local barHeightPx = math.max(mobile and 48 or 20, (BAR_HEIGHT_SCALE * currentBarScale * BUTTON_HEIGHT_MULTIPLIER * mobileHeightMult) * vh)
	local fontSize = math.max(10, math.floor(11 * getTextScale()))
	local minBtnWidth = mobile and MOBILE_MIN_BUTTON_WIDTH or 40
	local listPadding = mobile and math.max(BAR_BUTTON_PADDING_PX, MOBILE_MIN_BUTTON_GAP) or BAR_BUTTON_PADDING_PX
	-- Update list padding for mobile (no crossover)
	list.Padding = UDim.new(0, listPadding)
	-- Update toolbar height (includes BUTTON_HEIGHT_MULTIPLIER; +25% on mobile)
	if toolbar and toolbar.Parent then
		toolbar.Size = UDim2.new(0, 0, BAR_HEIGHT_SCALE * currentBarScale * BUTTON_HEIGHT_MULTIPLIER * mobileHeightMult, 0)
	end
	-- Compute ideal widths first
	local widths = {}
	local totalWidth = 0
	for i, def in ipairs(buttonDefs) do
		local btn = container:FindFirstChild(def.menuName)
		if btn and btn:IsA("TextButton") then
			local textSize = TextService:GetTextSize(def.label, fontSize, Enum.Font.GothamBold, Vector2.new(10000, barHeightPx))
			local w = math.max(minBtnWidth, textSize.X + BAR_BUTTON_TEXT_PADDING_PX)
			widths[i] = w
			totalWidth = totalWidth + w
		end
	end
	-- Include gaps, toolbar padding, day/night (no dividers or close X)
	totalWidth = totalWidth + 9 + 9 * listPadding + 28
	local availableWidth = vw * 0.96
	local scale = 1
	if totalWidth > availableWidth then
		scale = availableWidth / totalWidth
	end
	for i, def in ipairs(buttonDefs) do
		local btn = container:FindFirstChild(def.menuName)
		if btn and btn:IsA("TextButton") and widths[i] then
			local w = math.max(minBtnWidth, math.floor(widths[i] * scale))
			btn.Size = UDim2.new(0, w, 1, 0)
		end
	end
	-- Scale entire toolbar if still overflowing (never let buttons crossover off-screen)
	if toolbar and toolbar.Parent then
		task.defer(function()
			if toolbar and toolbar.Parent and toolbar.AbsoluteSize.X > vw * 0.98 then
				local uiScale = toolbar:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", toolbar)
				uiScale.Scale = (vw * 0.96) / toolbar.AbsoluteSize.X
			else
				local uiScale = toolbar:FindFirstChildOfClass("UIScale")
				if uiScale then uiScale.Scale = 1 end
			end
		end)
	end
end

-- Build buttons (each button: width set by updateBarButtonSizes to fit text, full height of container)
	for i, def in ipairs(buttonDefs) do
	local btn = Instance.new("TextButton")
	btn.Name = def.menuName
	btn.LayoutOrder = i
	btn.Size = UDim2.new(0, 80, 1, 0)
	btn.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = def.label
	btn.TextColor3 = def.color
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = math.max(10, math.floor(11 * textScale))
	btn.AutoButtonColor = false
	btn.Parent = container
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)

	-- No UIStroke on bar buttons (avoids double-line effect with dividers; separators are dividers only)
	local stroke = Instance.new("UIStroke", btn)
	stroke.Color = def.color
	stroke.Thickness = 1
	stroke.Transparency = 1  -- hidden; dividers provide single-line separation between buttons

	-- Hover: show tooltip and subtle stroke
	btn.MouseEnter:Connect(function()
		stroke.Transparency = 0.3
		btn.BackgroundTransparency = 0.05
		tipLabel.Text = def.desc .. " (" .. def.key .. ")"
		tipLabel.TextColor3 = def.color
		tipLabel.Visible = true
		-- Position tooltip above this button (defer + wait one frame so AutomaticSize updates)
		task.defer(function()
			task.wait() -- allow layout to update for AutomaticSize
			if not tipLabel.Visible then return end
			local btnPos, btnSize = btn.AbsolutePosition, btn.AbsoluteSize
			local tipSize = tipLabel.AbsoluteSize
			local centerX = btnPos.X + btnSize.X / 2
			local tipX = centerX - tipSize.X / 2
			local tipY = btnPos.Y - TOOLTIP_GAP_PX - tipSize.Y
			tipLabel.Position = UDim2.new(0, tipX, 0, tipY)
		end)
	end)

	btn.MouseLeave:Connect(function()
		stroke.Transparency = 1
		btn.BackgroundTransparency = 0.15
		tipLabel.Visible = false
	end)

	-- Tap/click: use Activated so touch + mouse both open menus (MouseButton1Click alone is flaky on some mobile clients).
	btn.Activated:Connect(function()
		setActiveAndMove(def.menuName, true)
		-- Click bounce (scale 1 -> 1.25 -> 1 with Elastic)
		local uiScale = btn:FindFirstChildOfClass("UIScale") or Instance.new("UIScale", btn)
		uiScale.Scale = 1
		TweenService:Create(uiScale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.25 }):Play()
		task.delay(0.15, function()
			if uiScale and uiScale.Parent then
				TweenService:Create(uiScale, TweenInfo.new(0.35, Enum.EasingStyle.Elastic, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			end
		end)
		-- Visual flash
		btn.BackgroundColor3 = def.color
		btn.TextColor3 = Color3.new(0, 0, 0)
		task.delay(0.12, function()
			if btn and btn.Parent then
				btn.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
				btn.TextColor3 = def.color
			end
		end)
		-- Fire the toggle event (special case: GoHome fires remote directly)
		if def.menuName == "GoHome" then
			local events = ReplicatedStorage:FindFirstChild("Events")
			local goHomeEvt = events and events:FindFirstChild("GoHome")
			if goHomeEvt then goHomeEvt:FireServer() end
		else
			toggleEvent:Fire(def.menuName)
		end
	end)
	end

	-- Size each button to fit its text (dynamic bubbles)
	local function onBarLayout()
		updateBarButtonSizes()
		moveIndicatorToActive(false)
	end
	onBarLayout()
	local camera = workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(onBarLayout)
	end
	toolbar:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		task.defer(moveIndicatorToActive, false)
	end)

	-- Keyboard shortcuts fire HUDToggleMenu; sync active indicator
	toggleEvent.Event:Connect(function(menuName)
		setActiveAndMove(normalizeIndicatorMenuName(menuName), true)
	end)

	-- Combat hint (top center; recreated on restore so it survives respawn)
	local HINT_WIDTH_SCALE = 420/1920
	local HINT_HEIGHT_SCALE = 26/1080
	local HINT_TOP_OFFSET_SCALE = 6/1080
	local hintFrame = Instance.new("Frame")
	hintFrame.AnchorPoint = Vector2.new(0.5, 0)
	hintFrame.Size = UDim2.new(HINT_WIDTH_SCALE, 0, HINT_HEIGHT_SCALE, 0)
	hintFrame.Position = UDim2.new(0.5, 0, 0, HINT_TOP_OFFSET_SCALE)
	hintFrame.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	hintFrame.BackgroundTransparency = 0.3
	hintFrame.BorderSizePixel = 0
	hintFrame.Parent = sg
	Instance.new("UICorner", hintFrame).CornerRadius = UDim.new(0, 8)
	local hintLbl = Instance.new("TextLabel")
	hintLbl.Size = UDim2.new(1, 0, 1, 0)
	hintLbl.BackgroundTransparency = 1
	hintLbl.Text = "Select target to attack | [F] Ranged/Melee | [E] Target nearest | [Shift] Sprint"
	hintLbl.TextColor3 = Color3.fromRGB(140, 150, 180)
	hintLbl.Font = Enum.Font.GothamMedium
	hintLbl.TextSize = math.max(10, math.floor(10 * textScale))
	hintLbl.Parent = hintFrame
	task.delay(15, function()
		if hintFrame and hintFrame.Parent then
			TweenService:Create(hintFrame, TweenInfo.new(2), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(hintLbl, TweenInfo.new(2), { TextTransparency = 1 }):Play()
			task.delay(2.1, function() if hintFrame then hintFrame.Visible = false end end)
		end
	end)
end

-- Keyboard shortcuts via UserInputService.InputBegan (ContextActionService can fail to fire for keyboard on some setups)
local keyToEnum = {
	Q = Enum.KeyCode.Q, W = Enum.KeyCode.W, E = Enum.KeyCode.E, R = Enum.KeyCode.R,
	T = Enum.KeyCode.T, Y = Enum.KeyCode.Y, U = Enum.KeyCode.U, I = Enum.KeyCode.I,
	O = Enum.KeyCode.O, P = Enum.KeyCode.P, A = Enum.KeyCode.A, S = Enum.KeyCode.S,
	D = Enum.KeyCode.D, F = Enum.KeyCode.F, G = Enum.KeyCode.G, H = Enum.KeyCode.H,
	J = Enum.KeyCode.J, K = Enum.KeyCode.K, L = Enum.KeyCode.L, Z = Enum.KeyCode.Z,
	X = Enum.KeyCode.X, C = Enum.KeyCode.C, V = Enum.KeyCode.V, B = Enum.KeyCode.B,
	N = Enum.KeyCode.N, M = Enum.KeyCode.M,
}
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	-- Skip if typing in chat/TextBox
	if UserInputService:GetFocusedTextBox() then return end
	-- Must be keyboard with a valid KeyCode
	if input.UserInputType ~= Enum.UserInputType.Keyboard or not input.KeyCode or input.KeyCode == Enum.KeyCode.Unknown then return end
	ensureToggleEvent()
	for _, def in ipairs(buttonDefs) do
		local keyEnum = keyToEnum[def.key]
		if keyEnum and input.KeyCode == keyEnum then
			if setActiveAndMoveFunc then setActiveAndMoveFunc(def.menuName, true) end
			if toggleEvent then
				if def.menuName == "GoHome" then
					local events = ReplicatedStorage:FindFirstChild("Events")
					local goHomeEvt = events and events:FindFirstChild("GoHome")
					if goHomeEvt then goHomeEvt:FireServer() end
				else
					if def.menuName == "InventoryUI" then
						_agentLog("H5", "HUDButtonBar:InputBegan", "fire_HUDToggleMenu", {})
					end
					toggleEvent:Fire(def.menuName)
				end
			end
			break
		end
	end
end)

-- Initial build
buildHUDButtonBar()

-- Restore on respawn (PlayerGui is cleared on death; recreate bar and HUDToggleMenu)
player.CharacterAdded:Connect(function()
	task.wait(0.15)
	buildHUDButtonBar()
end)

