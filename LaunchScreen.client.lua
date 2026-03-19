-- LaunchScreen.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- First-time: pick starter creature. Plot is auto-assigned by server.
-- Returning: skip launch screen entirely.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local getInventory = Events:WaitForChild("GetInventory", 10)
local selectStarter = Events:WaitForChild("SelectStarter", 10)

if not getInventory or not selectStarter then
	warn("[LaunchScreen] Missing events")
	return
end

-- Elemental theme: Fire (Red), Wind (Green), Air (White), Ice (Blue)
local FIRE  = Color3.fromRGB(255, 70, 50)
local WIND  = Color3.fromRGB(80, 220, 120)
local AIR   = Color3.fromRGB(248, 252, 255)
local ICE   = Color3.fromRGB(100, 180, 255)

local BG    = Color3.fromRGB(6, 14, 32)
local CARD  = Color3.fromRGB(18, 28, 52)
local ACCENT = FIRE
local TEXT  = AIR
local MUTED = Color3.fromRGB(140, 170, 220)

local ELEMENT_COLOR = {
	Fire = FIRE, Ice = ICE,
	Wind = WIND, Earth = Color3.fromRGB(180, 140, 80),
	Shadow = Color3.fromRGB(120, 50, 180), Light = Color3.fromRGB(255, 250, 200),
	Lightning = Color3.fromRGB(255, 230, 60), Water = Color3.fromRGB(50, 150, 255),
	Psychic = Color3.fromRGB(200, 150, 255),
	Metal = Color3.fromRGB(160, 170, 180), Poison = Color3.fromRGB(120, 220, 80),
	Undead = Color3.fromRGB(140, 120, 160),
}
local RARITY = {
	Common = Color3.fromRGB(120, 125, 140), Uncommon = Color3.fromRGB(50, 200, 90),
	Rare = Color3.fromRGB(50, 130, 255), Epic = Color3.fromRGB(170, 70, 255),
	Legendary = Color3.fromRGB(255, 170, 0),
}

-- ScreenGui (created hidden, shown after data check)
local sg = Instance.new("ScreenGui")
sg.Name = "LaunchScreen"
sg.ResetOnSpawn = false
sg.DisplayOrder = 100
sg.Enabled = false  -- hidden until we confirm it's needed
sg.Parent = playerGui

-- Overlay (full screen, scale-based)
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.BackgroundColor3 = BG
overlay.BackgroundTransparency = 0.1
overlay.BorderSizePixel = 0
overlay.Parent = sg

-- Title (scale-based: ~60/1080 height, ~40/1080 from top)
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, 0, 60/1080, 0)
titleLbl.Position = UDim2.new(0, 0, 40/1080, 0)
titleLbl.BackgroundTransparency = 1
titleLbl.Text = "ELEMINIONS!"
titleLbl.TextColor3 = ACCENT
titleLbl.Font = Enum.Font.GothamBlack
titleLbl.TextSize = 36
titleLbl.Parent = overlay

-- Subtitle (scale-based)
local subtitleLbl = Instance.new("TextLabel")
subtitleLbl.Size = UDim2.new(1, 0, 30/1080, 0)
subtitleLbl.Position = UDim2.new(0, 0, 95/1080, 0)
subtitleLbl.BackgroundTransparency = 1
subtitleLbl.TextColor3 = MUTED
subtitleLbl.Font = Enum.Font.GothamMedium
subtitleLbl.TextSize = 16
subtitleLbl.Parent = overlay

-- Content frame (scale-based, centered horizontally; design base 1920x1080)
local contentFrame = Instance.new("Frame")
contentFrame.AnchorPoint = Vector2.new(0.5, 0)
contentFrame.Size = UDim2.new(700/1920, 0, 380/1080, 0)
contentFrame.Position = UDim2.new(0.5, 0, 140/1080, 0)
contentFrame.BackgroundTransparency = 1
contentFrame.Parent = overlay

-- Wait for server data (retry aggressively)
local data = nil

-- Avoid hammering GetInventory during server startup: wait for critical-ready signal first.
do
	local criticalReady = Events:FindFirstChild("LoadingCriticalReady")
	if criticalReady then
		local signaled = false
		local conn
		conn = criticalReady.OnClientEvent:Connect(function()
			signaled = true
			if conn then conn:Disconnect() end
		end)
		local deadline = tick() + (GameConfig.LoadingCriticalMaxWait or 18)
		while not signaled and tick() < deadline do
			task.wait(0.1)
		end
		if conn then conn:Disconnect() end
	end
end

for attempt = 1, 4 do
	local ok, r = pcall(function() return getInventory:InvokeServer() end)
	if ok and r then data = r; break end
	task.wait(attempt == 1 and 0.35 or 0.6)
end
if not data then warn("[LaunchScreen] Could not get player data"); sg:Destroy(); return end

-- Check if new player (no creatures)
local isNew = #data.inventory == 0

-- Nothing to show - returning player with creatures (plot auto-assigned by server)
if not isNew then
	print("[LaunchScreen] Returning player - skipping (plot auto-assigned)")
	sg:Destroy()
	return
end

-- Show the screen now that we know it's needed
sg.Enabled = true

--[[ TEXT SCALING (viewport-based)
     getTextScale() returns a multiplier from CurrentCamera.ViewportSize vs reference resolution.
     textScale is then used for all TextSize values so text scales with screen size.
     TEXT_SIZE_MULTIPLIER boosts the result so text stays readable (tune if too small/large). ]]
local TEXT_REFERENCE_WIDTH = 1920
local TEXT_REFERENCE_HEIGHT = 1080
local TEXT_SCALE_CLAMP_MIN = 0.6
local TEXT_SCALE_CLAMP_MAX = 1.5
local TEXT_SIZE_MULTIPLIER = 1.85  -- boost so text is larger; increase if still too small

local function getTextScale()
	local camera = workspace.CurrentCamera
	local viewport = (camera and camera.ViewportSize) or Vector2.new(TEXT_REFERENCE_WIDTH, TEXT_REFERENCE_HEIGHT)
	local raw = math.min(viewport.X / TEXT_REFERENCE_WIDTH, viewport.Y / TEXT_REFERENCE_HEIGHT)
	return math.clamp(raw, TEXT_SCALE_CLAMP_MIN, TEXT_SCALE_CLAMP_MAX) * TEXT_SIZE_MULTIPLIER
end

local textScale = getTextScale()

-- Title/subtitle text sizes (scaled; second arg is minimum pixels so text never unreadable)
titleLbl.TextSize = math.max(18, math.floor(36 * textScale))
subtitleLbl.TextSize = math.max(10, math.floor(16 * textScale))

local selectedStarter = nil

-- Close launch screen with animation
local function closeLaunchScreen(message)
	subtitleLbl.Text = message or "Welcome to Eleminions!"
	for _, ch in ipairs(contentFrame:GetChildren()) do ch:Destroy() end
	TweenService:Create(overlay, TweenInfo.new(1.2, Enum.EasingStyle.Quad), {BackgroundTransparency = 1}):Play()
	TweenService:Create(titleLbl, TweenInfo.new(0.8), {TextTransparency = 1}):Play()
	TweenService:Create(subtitleLbl, TweenInfo.new(0.8), {TextTransparency = 1}):Play()
	task.delay(1.3, function() sg:Destroy() end)
end


-- ----------------------------------------
-- STARTER SELECTION (scale-based layout, UIListLayout for cards)
-- ----------------------------------------
local function showStarterSelection()
	subtitleLbl.Text = "Choose your first companion!"

	for _, ch in ipairs(contentFrame:GetChildren()) do ch:Destroy() end

	-- Reuse viewport-based text scale for all card labels (ts = text scale multiplier)
	local ts = textScale

	-- CARD LAYOUT: horizontal list; CARD_PADDING_SCALE = gap between cards (scale of content width)
	local CARD_PADDING_SCALE = 0.02
	local list = Instance.new("UIListLayout")
	list.Parent = contentFrame
	list.FillDirection = Enum.FillDirection.Horizontal
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Top
	list.Padding = UDim.new(CARD_PADDING_SCALE, 0)
	list.SortOrder = Enum.SortOrder.LayoutOrder

	local starters = CreatureData.Starters
	-- Card size: each card gets a share of width/height, then CARD_SIZE_MULT scales them up (e.g. 1.5 = 50% larger)
	local CARD_SIZE_MULT = 2.5
	local cardWScale = ((1 - (#starters - 1) * CARD_PADDING_SCALE) / #starters) * CARD_SIZE_MULT
	local cardHScale = (280/380) * CARD_SIZE_MULT

	for i, sid in ipairs(starters) do
		local info = CreatureData.GetById(sid)
		if not info then continue end

		local rc = RARITY[info.rarity] or MUTED
		local ec = ELEMENT_COLOR[info.element] or MUTED

		local card = Instance.new("TextButton")
		card.LayoutOrder = i
		card.Size = UDim2.new(cardWScale, 0, cardHScale, 0)
		card.BackgroundColor3 = CARD
		card.BorderSizePixel = 0
		card.Text = ""
		card.AutoButtonColor = false
		card.Parent = contentFrame
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 12)

		local stroke = Instance.new("UIStroke")
		stroke.Color = ICE
		stroke.Transparency = 0.4
		stroke.Thickness = 2
		stroke.Parent = card

		-- Orb (scale + UIAspectRatioConstraint so it stays square)
		local orb = Instance.new("Frame")
		orb.AnchorPoint = Vector2.new(0.5, 0)
		orb.Size = UDim2.new(0.4, 0, 0.18, 0)
		orb.Position = UDim2.new(0.5, 0, 0.07, 0)
		orb.BackgroundColor3 = info.primaryColor
		orb.BorderSizePixel = 0
		orb.Parent = card
		Instance.new("UICorner", orb).CornerRadius = UDim.new(1, 0)
		Instance.new("UIStroke", orb).Color = rc
		local aspect = Instance.new("UIAspectRatioConstraint")
		aspect.AspectRatio = 1
		aspect.Parent = orb

		-- Name label: base size 13, scaled by ts; minimum 10px
		local nm = Instance.new("TextLabel")
		nm.Size = UDim2.new(1, -10, 0.07, 0)
		nm.Position = UDim2.new(0, 5, 0.28, 0)
		nm.BackgroundTransparency = 1
		nm.Text = info.displayName
		nm.TextColor3 = TEXT
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = math.max(10, math.floor(13 * ts))
		nm.Parent = card

		-- Element + class label: base 10, min 8
		local el = Instance.new("TextLabel")
		el.Size = UDim2.new(1, -10, 0.05, 0)
		el.Position = UDim2.new(0, 5, 0.36, 0)
		el.BackgroundTransparency = 1
		el.Text = info.element .. " " .. info.class
		el.TextColor3 = ec
		el.Font = Enum.Font.GothamMedium
		el.TextSize = math.max(8, math.floor(10 * ts))
		el.Parent = card

		-- Behavior label: base 9, min 7
		local beh = Instance.new("TextLabel")
		beh.Size = UDim2.new(1, -10, 0.05, 0)
		beh.Position = UDim2.new(0, 5, 0.41, 0)
		beh.BackgroundTransparency = 1
		beh.Text = "Behavior: " .. (info.behavior or "?")
		beh.TextColor3 = MUTED
		beh.Font = Enum.Font.GothamMedium
		beh.TextSize = math.max(7, math.floor(9 * ts))
		beh.Parent = card

		-- Stats label: base 10, min 8
		local statsText = "HP: " .. info.health .. "\nATK: " .. info.attack .. "\nDEF: " .. info.defense .. "\nSPD: " .. info.speed
		local st = Instance.new("TextLabel")
		st.Size = UDim2.new(1, -16, 0.21, 0)
		st.Position = UDim2.new(0, 8, 0.50, 0)
		st.BackgroundTransparency = 1
		st.Text = statsText
		st.TextColor3 = MUTED
		st.Font = Enum.Font.GothamMedium
		st.TextSize = math.max(8, math.floor(10 * ts))
		st.TextXAlignment = Enum.TextXAlignment.Left
		st.TextYAlignment = Enum.TextYAlignment.Top
		st.Parent = card

		-- Description label: base 8, min 6
		local desc = Instance.new("TextLabel")
		desc.Size = UDim2.new(1, -12, 0.14, 0)
		desc.Position = UDim2.new(0, 6, 0.70, 0)
		desc.BackgroundTransparency = 1
		desc.Text = info.description or ""
		desc.TextColor3 = MUTED
		desc.Font = Enum.Font.GothamMedium
		desc.TextSize = math.max(6, math.floor(8 * ts))
		desc.TextWrapped = true
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Parent = card

		-- CHOOSE button: base 12, min 10
		local selBtn = Instance.new("TextButton")
		selBtn.AnchorPoint = Vector2.new(0, 1)
		selBtn.Size = UDim2.new(1, -20, 0.1, 0)
		selBtn.Position = UDim2.new(0, 10, 1, -4)
		selBtn.BackgroundColor3 = FIRE
		selBtn.Text = "CHOOSE"
		selBtn.TextColor3 = AIR
		selBtn.Font = Enum.Font.GothamBold
		selBtn.TextSize = math.max(10, math.floor(12 * ts))
		selBtn.BorderSizePixel = 0
		selBtn.Parent = card
		Instance.new("UICorner", selBtn).CornerRadius = UDim.new(0, 7)

		selBtn.MouseButton1Click:Connect(function()
			selectedStarter = sid

			-- Highlight selected
			for _, ch2 in ipairs(contentFrame:GetChildren()) do
				if ch2:IsA("TextButton") then
					local sk = ch2:FindFirstChildOfClass("UIStroke")
					if sk then sk.Color = ICE; sk.Transparency = 0.4; sk.Thickness = 2 end
				end
			end
			stroke.Color = FIRE; stroke.Transparency = 0; stroke.Thickness = 3

			-- Disable all buttons to prevent double-click
			for _, ch2 in ipairs(contentFrame:GetChildren()) do
				if ch2:IsA("TextButton") then ch2.Active = false end
			end

			-- Fire server and wait for it to process
			subtitleLbl.Text = "Summoning " .. info.displayName .. "..."
			if selectStarter then
				selectStarter:FireServer(sid)
			end
			task.wait(1.5)

			-- Plot is auto-assigned by server, just close
			closeLaunchScreen(info.displayName .. " is ready! Go explore!")
		end)
	end
end

-- ----------------------------------------
-- START
-- ----------------------------------------
if isNew then
	showStarterSelection()
end

print("[LaunchScreen] " .. (isNew and "New player - starter selection" or "Returning player - skipped"))
