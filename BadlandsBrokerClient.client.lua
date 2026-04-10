-- ═══════════════════════════════════════════════════════════════════════════════
-- BadlandsBrokerClient.client.lua
-- ═══════════════════════════════════════════════════════════════════════════════
-- Client-side UI for The Broker NPC in the Arena Hub.
-- Listens for BadlandsContractData from the server (fired when player presses E
-- on The Broker), then shows:
--   • Broker dialogue text (typewriter effect)
--   • ViewportFrame of the WANTED creature (the contract creature)
--   • Scrolling list of qualifying creatures from the player's inventory
--   • "Place" button (green) → selects a creature → "Accept" button
--   • Accept triggers a 10-second recall vortex animation, then fires
--     BadlandsOfferCreature to the server to sacrifice the creature and queue.
--
-- FIX #20: No client script existed to handle BadlandsContractData — pressing E
--          on the Broker did nothing because no UI was created client-side.
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════════════════════════
-- Module requires
-- ═══════════════════════════════════════════════════════════════════════════════
local Modules = ReplicatedStorage:WaitForChild("Modules")
local GameConfig = require(Modules:WaitForChild("GameConfig"))
local CreatureData = require(Modules:WaitForChild("CreatureData"))
local MobileWindowLayout = require(Modules:WaitForChild("MobileWindowLayout"))

-- CodexModelViewer for 3D creature viewport
local CodexModelViewer = nil
do
	local modScript = Modules:FindFirstChild("CodexModelViewer")
	if modScript then
		local ok, result = pcall(require, modScript)
		if ok then CodexModelViewer = result end
	end
end

-- NotificationManager for toasts
local Notify = nil
do
	local notifScript = Modules:FindFirstChild("NotificationManager")
	if notifScript then
		local ok, result = pcall(require, notifScript)
		if ok then Notify = result end
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Events folder
-- ═══════════════════════════════════════════════════════════════════════════════
local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
if not eventsFolder then
	warn("[BadlandsBrokerClient] Events folder not found")
	return
end

local contractDataEvt = eventsFolder:WaitForChild("BadlandsContractData", 10)
local offerCreatureEvt = eventsFolder:WaitForChild("BadlandsOfferCreature", 10)
local queueRejectEvt = eventsFolder:WaitForChild("BadlandsQueueReject", 10)
local runStartEvt = eventsFolder:WaitForChild("BadlandsRunStart", 10)

if not contractDataEvt then
	warn("[BadlandsBrokerClient] BadlandsContractData event not found")
	return
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Color palette (matches game-wide UI)
-- ═══════════════════════════════════════════════════════════════════════════════
local C = {
	bg        = Color3.fromRGB(14, 15, 22),
	bgLight   = Color3.fromRGB(22, 24, 35),
	card      = Color3.fromRGB(28, 30, 42),
	accent    = Color3.fromRGB(180, 80, 255),   -- Broker purple
	green     = Color3.fromRGB(80, 200, 100),
	red       = Color3.fromRGB(220, 60, 60),
	gold      = Color3.fromRGB(255, 200, 50),
	white     = Color3.fromRGB(240, 240, 245),
	textSec   = Color3.fromRGB(140, 145, 160),
	grey      = Color3.fromRGB(80, 85, 100),
	divider   = Color3.fromRGB(40, 42, 55),
	-- Match InventoryUIManager creature-card placement cues
	income    = Color3.fromRGB(50, 220, 120),
	defense   = Color3.fromRGB(220, 60, 70),
	battle    = Color3.fromRGB(130, 100, 255),
}

-- Rarity colors for creature cards
local RARITY_COLORS = {
	Common    = Color3.fromRGB(160, 160, 160),
	Uncommon  = Color3.fromRGB(80, 200, 80),
	Rare      = Color3.fromRGB(60, 140, 255),
	Epic      = Color3.fromRGB(180, 60, 255),
	Legendary = Color3.fromRGB(255, 180, 30),
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════════════
local screenGui = nil         -- ScreenGui instance
local mainFrame = nil         -- Main broker panel
local wantedViewer = nil      -- CodexModelViewer for wanted creature
local selectedUid = nil       -- UID of creature player has selected to offer
local selectedCreatureId = nil -- creature id of selected creature
local selectedOnDefense = false
local selectedOnIncome = false
local selectedOnBattle = false
local isAnimating = false     -- True during recall animation
local isBusy = false          -- Debounce
local viewportLayoutUnbind = nil
local brokerMenuVisible = false
-- Set while Broker UI is open: recomputes inner layout for small mobile panels.
local syncBrokerMobileContent = nil

local BROKER_DESIGN_W = 520
local BROKER_DESIGN_H = 480

local function applyBrokerWindowLayout()
	if not mainFrame then return end

	if screenGui then
		MobileWindowLayout.SyncNpcMenuScreenGui(screenGui, BROKER_DESIGN_W, BROKER_DESIGN_H)
	end

	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(BROKER_DESIGN_W, BROKER_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(
			mainFrame,
			MobileWindowLayout.GetNpcFullscreenBoundsConfig(BROKER_DESIGN_W, BROKER_DESIGN_H, {
				mobileDraggable = true,
			})
		)
		mainFrame.AnchorPoint = Vector2.new(0, 0)
		-- Inner content uses fixed pixel stacks; reflow after outer bounds are known.
		if syncBrokerMobileContent then
			task.defer(function()
				syncBrokerMobileContent()
				-- One more pass next frame (AbsoluteSize can settle after ApplyWindow).
				task.defer(syncBrokerMobileContent)
			end)
		end
		return
	end

	if screenGui then
		screenGui.IgnoreGuiInset = false
	end
	mainFrame.Size = UDim2.new(0, BROKER_DESIGN_W, 0, BROKER_DESIGN_H)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	MobileWindowLayout.RestoreDesktopWindow(mainFrame, { draggable = true })
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: create rounded button
-- ═══════════════════════════════════════════════════════════════════════════════
local function makeButton(parent, text, color, size, position)
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = position
	btn.BackgroundColor3 = color
	btn.BackgroundTransparency = 0.1
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = C.white
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 14
	btn.AutoButtonColor = true
	btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	return btn
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: typewriter text effect
-- ═══════════════════════════════════════════════════════════════════════════════
local function typewriterText(label, fullText, speed)
	speed = speed or 0.03
	label.Text = ""
	for i = 1, #fullText do
		label.Text = fullText:sub(1, i)
		task.wait(speed)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Close / cleanup the broker UI
-- ═══════════════════════════════════════════════════════════════════════════════
local function closeBrokerUI()
	if viewportLayoutUnbind then
		viewportLayoutUnbind()
		viewportLayoutUnbind = nil
	end
	if brokerMenuVisible then
		MobileWindowLayout.NotifyMenuClosed()
		brokerMenuVisible = false
	end
	syncBrokerMobileContent = nil
	if wantedViewer and wantedViewer.Destroy then
		pcall(function() wantedViewer:Destroy() end)
		wantedViewer = nil
	end
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	mainFrame = nil
	selectedUid = nil
	selectedCreatureId = nil
	selectedOnDefense = false
	selectedOnIncome = false
	selectedOnBattle = false
	isBusy = false
	isAnimating = false
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Play the 10-second recall vortex animation over the player character
-- Vortex particles spiral upward, screen darkens, then the player is "pulled in"
-- After 10 seconds, fires BadlandsOfferCreature to finalize the sacrifice
-- ═══════════════════════════════════════════════════════════════════════════════
local function playRecallAnimation(uid, onComplete)
	isAnimating = true

	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then
		isAnimating = false
		if onComplete then onComplete() end
		return
	end

	-- ── Screen overlay (darkens gradually) ──
	local overlay = Instance.new("Frame")
	overlay.Name = "RecallOverlay"
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.Position = UDim2.new(0, 0, 0, 0)
	overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	overlay.BackgroundTransparency = 1
	overlay.BorderSizePixel = 0
	overlay.ZIndex = 100
	overlay.Parent = screenGui

	-- "Entering The Badlands..." text
	local recallLabel = Instance.new("TextLabel")
	recallLabel.Name = "RecallText"
	recallLabel.Size = UDim2.new(0.6, 0, 0, 50)
	recallLabel.Position = UDim2.new(0.2, 0, 0.4, 0)
	recallLabel.BackgroundTransparency = 1
	recallLabel.Text = ""
	recallLabel.TextColor3 = C.accent
	recallLabel.Font = Enum.Font.GothamBlack
	recallLabel.TextSize = 28
	recallLabel.TextTransparency = 0
	recallLabel.ZIndex = 101
	recallLabel.Parent = overlay

	-- Countdown label
	local countdownLabel = Instance.new("TextLabel")
	countdownLabel.Name = "Countdown"
	countdownLabel.Size = UDim2.new(0.4, 0, 0, 30)
	countdownLabel.Position = UDim2.new(0.3, 0, 0.48, 0)
	countdownLabel.BackgroundTransparency = 1
	countdownLabel.Text = "10"
	countdownLabel.TextColor3 = C.white
	countdownLabel.Font = Enum.Font.GothamMedium
	countdownLabel.TextSize = 22
	countdownLabel.TextTransparency = 0
	countdownLabel.ZIndex = 101
	countdownLabel.Parent = overlay

	-- Progress bar background
	local barBg = Instance.new("Frame")
	barBg.Name = "BarBG"
	barBg.Size = UDim2.new(0.5, 0, 0, 8)
	barBg.Position = UDim2.new(0.25, 0, 0.54, 0)
	barBg.BackgroundColor3 = C.grey
	barBg.BackgroundTransparency = 0.5
	barBg.BorderSizePixel = 0
	barBg.ZIndex = 101
	barBg.Parent = overlay
	Instance.new("UICorner", barBg).CornerRadius = UDim.new(0, 4)

	local barFill = Instance.new("Frame")
	barFill.Name = "BarFill"
	barFill.Size = UDim2.new(0, 0, 1, 0)
	barFill.BackgroundColor3 = C.accent
	barFill.BorderSizePixel = 0
	barFill.ZIndex = 102
	barFill.Parent = barBg
	Instance.new("UICorner", barFill).CornerRadius = UDim.new(0, 4)

	-- ── 3D vortex particles around the player ──
	local vortexParts = {}
	local vortexFolder = Instance.new("Folder")
	vortexFolder.Name = "RecallVortex"
	vortexFolder.Parent = workspace

	-- Create a ring of glowing particles around the player
	local RING_COUNT = 12
	for i = 1, RING_COUNT do
		local p = Instance.new("Part")
		p.Name = "VortexOrb" .. i
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(0.6, 0.6, 0.6)
		p.Material = Enum.Material.Neon
		p.Color = C.accent
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Transparency = 0.3
		p.Parent = vortexFolder
		table.insert(vortexParts, p)
	end

	-- Main particle emitter on character
	local emitterPart = Instance.new("Part")
	emitterPart.Name = "RecallEmitter"
	emitterPart.Size = Vector3.new(1, 1, 1)
	emitterPart.Transparency = 1
	emitterPart.Anchored = true
	emitterPart.CanCollide = false
	emitterPart.CanQuery = false
	emitterPart.CanTouch = false
	emitterPart.Parent = vortexFolder

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "RecallParticles"
	pe.Texture = "rbxassetid://5860841663" -- Star texture
	pe.Color = ColorSequence.new(C.accent, Color3.fromRGB(100, 40, 180))
	pe.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1),
	})
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	pe.Lifetime = NumberRange.new(0.8, 1.5)
	pe.Rate = 60
	pe.Speed = NumberRange.new(3, 8)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Acceleration = Vector3.new(0, 15, 0) -- Particles spiral upward
	pe.Parent = emitterPart

	-- ── Animation loop: 10 seconds ──
	local RECALL_DURATION = 10
	local startTime = tick()
	local heartbeatConn

	-- Typewriter the text
	task.spawn(function()
		typewriterText(recallLabel, "Entering The Badlands...", 0.06)
	end)

	heartbeatConn = RunService.Heartbeat:Connect(function()
		local elapsed = tick() - startTime
		local progress = math.clamp(elapsed / RECALL_DURATION, 0, 1)

		-- Update countdown
		local remaining = math.ceil(RECALL_DURATION - elapsed)
		if remaining < 0 then remaining = 0 end
		countdownLabel.Text = tostring(remaining)

		-- Progress bar
		barFill.Size = UDim2.new(progress, 0, 1, 0)

		-- Darken overlay gradually (0 → 0.7 transparency → 0.3 transparency = more opaque)
		overlay.BackgroundTransparency = 1 - (progress * 0.8)

		-- Spin vortex orbs around the player with increasing speed + rising
		local rootPos = root and root.Position or Vector3.new(0, 5, 0)
		emitterPart.Position = rootPos

		local angularSpeed = 2 + progress * 8 -- speeds up over time
		local radius = 5 - progress * 3        -- closes in from 5 to 2 studs
		local rise = progress * 10              -- rises from 0 to 10 studs

		for idx, orb in ipairs(vortexParts) do
			local angle = (idx / RING_COUNT) * math.pi * 2 + elapsed * angularSpeed
			local orbRadius = math.max(0.5, radius)
			local x = rootPos.X + math.cos(angle) * orbRadius
			local z = rootPos.Z + math.sin(angle) * orbRadius
			local y = rootPos.Y + (idx / RING_COUNT) * rise
			orb.Position = Vector3.new(x, y, z)

			-- Orbs shrink and brighten as they converge
			local orbSize = 0.6 - progress * 0.3
			orb.Size = Vector3.new(orbSize, orbSize, orbSize)
			orb.Transparency = progress * 0.5
		end

		-- Done
		if elapsed >= RECALL_DURATION then
			heartbeatConn:Disconnect()

			-- Flash white
			overlay.BackgroundColor3 = Color3.fromRGB(200, 150, 255)
			overlay.BackgroundTransparency = 0

			-- Clean up vortex
			vortexFolder:Destroy()

			-- Fade out overlay after a beat
			task.delay(0.5, function()
				local fadeOut = TweenService:Create(overlay, TweenInfo.new(1, Enum.EasingStyle.Quad), {
					BackgroundTransparency = 1,
				})
				fadeOut:Play()
				fadeOut.Completed:Connect(function()
					if overlay and overlay.Parent then overlay:Destroy() end
				end)
			end)

			isAnimating = false
			if onComplete then onComplete() end
		end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Build the Broker UI
-- Called when BadlandsContractData arrives from the server.
-- @param data table — { rarity, element, minLevel, description, dateKey,
--                        qualifying, wantedCreatureId, brokerDialogue }
-- ═══════════════════════════════════════════════════════════════════════════════
local function showBrokerUI(data)
	-- Close any existing UI
	closeBrokerUI()

	local qualifying = data.qualifying or {}

	-- ── ScreenGui ──
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BadlandsBrokerUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 45
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	-- ── Main panel (centered, dark bg with purple accent stroke) ──
	mainFrame = Instance.new("Frame")
	mainFrame.Name = "BrokerPanel"
	mainFrame.Size = UDim2.new(0, 520, 0, 480)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BackgroundTransparency = 0.05
	mainFrame.BorderSizePixel = 0
	mainFrame.Active = true
	mainFrame.Draggable = true
	mainFrame.Parent = screenGui
	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke", mainFrame)
	stroke.Color = C.accent
	stroke.Thickness = 2

	-- ── Title bar ──
	local titleBar = Instance.new("Frame")
	titleBar.Name = "TitleBar"
	titleBar.Size = UDim2.new(1, 0, 0, 40)
	titleBar.BackgroundColor3 = C.bgLight
	titleBar.BackgroundTransparency = 0.3
	titleBar.BorderSizePixel = 0
	titleBar.Parent = mainFrame
	Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 10)

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -80, 1, 0)
	titleLabel.Position = UDim2.new(0, 16, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "⬥ The Broker ⬥"
	titleLabel.TextColor3 = C.accent
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 18
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Parent = titleBar

	-- Close button (X)
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -40, 0, 2)
	closeBtn.BackgroundColor3 = C.red
	closeBtn.BackgroundTransparency = 0.6
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "X"
	closeBtn.TextColor3 = C.white
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 16
	closeBtn.AutoButtonColor = true
	closeBtn.Parent = titleBar
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

	closeBtn.MouseButton1Click:Connect(function()
		if not isAnimating then
			closeBrokerUI()
		end
	end)

	-- ═══════════════════════════════════════════════════════════════════
	-- LEFT COLUMN: Dialogue + Wanted Creature Viewport
	-- ═══════════════════════════════════════════════════════════════════
	local leftCol = Instance.new("Frame")
	leftCol.Name = "LeftColumn"
	leftCol.Size = UDim2.new(0.5, -8, 1, -48)
	leftCol.Position = UDim2.new(0, 8, 0, 44)
	leftCol.BackgroundTransparency = 1
	leftCol.Parent = mainFrame

	-- ── Contract demand (RichText with colored segments) ──
	local rarityStr = data.rarity or "?"
	local elementStr = data.element or "?"
	local minLvl = data.minLevel or 1
	local rarityColor = RARITY_COLORS[rarityStr] or C.textSec
	local elemData = CreatureData.Elements and CreatureData.Elements[elementStr]
	local elemColor = elemData and elemData.color or C.textSec
	local badlandsColor = C.accent

	local function colorHex(c)
		return string.format("#%02X%02X%02X",
			math.floor(c.R * 255 + 0.5),
			math.floor(c.G * 255 + 0.5),
			math.floor(c.B * 255 + 0.5))
	end

	-- Level difficulty color: green <=5, gold 6-10, red 11+
	local lvlColor
	if minLvl <= 5 then
		lvlColor = C.green
	elseif minLvl <= 10 then
		lvlColor = C.gold
	else
		lvlColor = C.red
	end

	local demandRich = string.format(
		'Bring me a <b><font color="%s">%s</font></b> <font color="%s">%s</font> Siegeling, at least <font color="%s"><b>LEVEL %d</b></font>, and I will send you to the <font color="%s"><b>BADLANDS</b></font>.',
		colorHex(rarityColor), rarityStr:upper(),
		colorHex(elemColor), elementStr:upper(),
		colorHex(lvlColor), minLvl,
		colorHex(badlandsColor)
	)

	-- Bonus creature line (gold)
	local bonusName = data.bonusCreatureName
	if bonusName then
		demandRich = demandRich .. string.format(
			'\n\nBring <font color="%s"><b>%s</b></font> for a <font color="%s"><b>BONUS!</b></font>',
			colorHex(C.gold), bonusName,
			colorHex(C.gold)
		)
	end

	local demandFrame = Instance.new("Frame")
	demandFrame.Name = "DemandFrame"
	demandFrame.Size = UDim2.new(1, 0, 0, bonusName and 130 or 110)
	demandFrame.Position = UDim2.new(0, 0, 0, 0)
	demandFrame.BackgroundColor3 = C.card
	demandFrame.BackgroundTransparency = 0.3
	demandFrame.BorderSizePixel = 0
	demandFrame.Parent = leftCol
	Instance.new("UICorner", demandFrame).CornerRadius = UDim.new(0, 8)

	local demandLabel = Instance.new("TextLabel")
	demandLabel.Name = "DemandText"
	demandLabel.Size = UDim2.new(1, -16, 1, -8)
	demandLabel.Position = UDim2.new(0, 8, 0, 4)
	demandLabel.BackgroundTransparency = 1
	demandLabel.RichText = true
	demandLabel.Text = demandRich
	demandLabel.TextColor3 = C.white
	demandLabel.Font = Enum.Font.GothamMedium
	demandLabel.TextSize = 14
	demandLabel.TextWrapped = true
	demandLabel.TextXAlignment = Enum.TextXAlignment.Left
	demandLabel.TextYAlignment = Enum.TextYAlignment.Top
	demandLabel.Parent = demandFrame

	-- ── ViewportFrame for wanted creature ──
	local vpTop = bonusName and 138 or 118
	local viewportContainer = Instance.new("Frame")
	viewportContainer.Name = "ViewportContainer"
	viewportContainer.Size = UDim2.new(1, 0, 0, 200)
	viewportContainer.Position = UDim2.new(0, 0, 0, vpTop)
	viewportContainer.BackgroundColor3 = C.card
	viewportContainer.BackgroundTransparency = 0.2
	viewportContainer.BorderSizePixel = 0
	viewportContainer.ClipsDescendants = true
	viewportContainer.Parent = leftCol
	Instance.new("UICorner", viewportContainer).CornerRadius = UDim.new(0, 8)

	local vpStroke = Instance.new("UIStroke", viewportContainer)
	vpStroke.Color = RARITY_COLORS[data.rarity] or C.accent
	vpStroke.Thickness = 1.5

	-- Use CodexModelViewer if available for full 3D preview with themed lighting
	if CodexModelViewer and data.wantedCreatureId then
		wantedViewer = CodexModelViewer.new(viewportContainer, {
			size = UDim2.new(1, 0, 1, 0),
			autoRotate = true,
			autoRotateSpeed = 0.4,
			showFloor = true,
			themedLighting = true,
			interactable = true,
			playIdleAnimation = true,
		})
		wantedViewer:SetCreature(data.wantedCreatureId)
	else
		-- Fallback: show a "?" placeholder
		local placeholder = Instance.new("TextLabel")
		placeholder.Size = UDim2.new(1, 0, 1, 0)
		placeholder.BackgroundTransparency = 1
		placeholder.Text = "?"
		placeholder.TextColor3 = C.accent
		placeholder.Font = Enum.Font.GothamBlack
		placeholder.TextSize = 72
		placeholder.Parent = viewportContainer
	end

	-- ═══════════════════════════════════════════════════════════════════
	-- RIGHT COLUMN: Qualifying Creatures List + Action Button
	-- ═══════════════════════════════════════════════════════════════════
	local rightCol = Instance.new("Frame")
	rightCol.Name = "RightColumn"
	rightCol.Size = UDim2.new(0.5, -8, 1, -48)
	rightCol.Position = UDim2.new(0.5, 4, 0, 44)
	rightCol.BackgroundTransparency = 1
	rightCol.Parent = mainFrame

	-- ── "Your Siegelings" header ──
	local listHeader = Instance.new("TextLabel")
	listHeader.Name = "ListHeader"
	listHeader.Size = UDim2.new(1, 0, 0, 24)
	listHeader.Position = UDim2.new(0, 0, 0, 0)
	listHeader.BackgroundTransparency = 1
	listHeader.Text = "Your Qualifying Siegelings"
	listHeader.TextColor3 = C.white
	listHeader.Font = Enum.Font.GothamBold
	listHeader.TextSize = 14
	listHeader.TextXAlignment = Enum.TextXAlignment.Left
	listHeader.Parent = rightCol

	-- ── Scrolling list frame ──
	local listFrame = Instance.new("ScrollingFrame")
	listFrame.Name = "CreatureList"
	listFrame.Size = UDim2.new(1, 0, 0, 310)
	listFrame.Position = UDim2.new(0, 0, 0, 28)
	listFrame.BackgroundColor3 = C.card
	listFrame.BackgroundTransparency = 0.4
	listFrame.BorderSizePixel = 0
	listFrame.ScrollBarThickness = 6
	listFrame.ScrollBarImageColor3 = C.grey
	listFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
	listFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
	listFrame.Parent = rightCol
	Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 8)

	local listLayout = Instance.new("UIListLayout")
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 4)
	listLayout.Parent = listFrame

	local listPadding = Instance.new("UIPadding")
	listPadding.PaddingLeft = UDim.new(0, 4)
	listPadding.PaddingRight = UDim.new(0, 4)
	listPadding.PaddingTop = UDim.new(0, 4)
	listPadding.PaddingBottom = UDim.new(0, 4)
	listPadding.Parent = listFrame

	-- ── Action button (Place / Accept) ──
	local actionBtn = makeButton(
		rightCol,
		"Select a Siegeling",
		C.grey,
		UDim2.new(1, 0, 0, 40),
		UDim2.new(0, 0, 1, -44)
	)
	actionBtn.Name = "ActionBtn"
	-- Long accept labels (e.g. defense/income/battle) must shrink to fit the button width.
	actionBtn.TextScaled = true
	actionBtn.TextWrapped = true
	actionBtn.TextSize = 16 -- reference size; scaling is bounded below
	local actionBtnTextConstraint = Instance.new("UITextSizeConstraint")
	actionBtnTextConstraint.MinTextSize = 7
	actionBtnTextConstraint.MaxTextSize = 16
	actionBtnTextConstraint.Parent = actionBtn
	local actionBtnPad = Instance.new("UIPadding")
	actionBtnPad.PaddingLeft = UDim.new(0, 10)
	actionBtnPad.PaddingRight = UDim.new(0, 10)
	actionBtnPad.PaddingTop = UDim.new(0, 4)
	actionBtnPad.PaddingBottom = UDim.new(0, 4)
	actionBtnPad.Parent = actionBtn

	-- Track which creature card is currently highlighted
	local selectedCard = nil

	-- ── Update action button state ──
	local actionState = "none" -- "none" | "place" | "accept"

	local function getAcceptButtonLabel()
		local parts = {}
		if selectedOnDefense then table.insert(parts, "defense") end
		if selectedOnIncome then table.insert(parts, "income") end
		if selectedOnBattle then table.insert(parts, "battle") end
		if #parts == 0 then
			return "Accept — Sacrifice & Enter"
		end
		if #parts == 1 then
			if selectedOnDefense then
				return "Accept and remove from defense point?"
			end
			if selectedOnIncome then
				return "Accept and remove from income point?"
			end
			return "Accept and remove from battle team?"
		end
		return "Accept and clear " .. table.concat(parts, ", ") .. "?"
	end

	local function updateActionButton()
		if actionState == "none" then
			actionBtn.Text = "Select a Siegeling"
			actionBtn.BackgroundColor3 = C.grey
			actionBtn.BackgroundTransparency = 0.4
		elseif actionState == "place" then
			actionBtn.Text = "Place"
			actionBtn.BackgroundColor3 = C.green
			actionBtn.BackgroundTransparency = 0.1
		elseif actionState == "accept" then
			actionBtn.Text = getAcceptButtonLabel()
			actionBtn.BackgroundColor3 = C.green
			actionBtn.BackgroundTransparency = 0.1
		end
	end

	-- ── Populate creature list ──
	if #qualifying == 0 then
		local noCreatures = Instance.new("TextLabel")
		noCreatures.Size = UDim2.new(1, -8, 0, 80)
		noCreatures.BackgroundTransparency = 1
		noCreatures.RichText = true
		noCreatures.Text = "You have no Siegelings that match today's contract.\n\nThe Broker demands:\n"
			.. string.format('Bring me a <b><font color="%s">%s</font></b> <font color="%s">%s</font> Siegeling, at least <font color="%s"><b>Level %d</b></font>',
				colorHex(rarityColor), rarityStr:upper(),
				colorHex(elemColor), elementStr:upper(),
				colorHex(lvlColor), minLvl)
		noCreatures.TextColor3 = C.textSec
		noCreatures.Font = Enum.Font.GothamMedium
		noCreatures.TextSize = 12
		noCreatures.TextWrapped = true
		noCreatures.Parent = listFrame
	else
		local MAX_QUALIFYING_SHOWN = 5
		for i, creature in ipairs(qualifying) do
			if i > MAX_QUALIFYING_SHOWN then break end
			local onDef = creature.onDefense == true
			local onInc = creature.onIncome == true
			local onBat = creature.onBattle == true
			local cardBg = C.bgLight
			local wmText, wmColor = nil, nil
			-- Same priority feel as inventory: defense / income / battle
			if onDef then
				cardBg = Color3.fromRGB(40, 22, 22)
				wmText, wmColor = "DEFENSE", C.defense
			elseif onInc then
				cardBg = Color3.fromRGB(22, 38, 28)
				wmText, wmColor = "INCOME", C.income
			elseif onBat then
				cardBg = Color3.fromRGB(25, 24, 38)
				wmText, wmColor = "BATTLE", C.battle
			end

			local card = Instance.new("TextButton")
			card.Name = "Card_" .. (creature.uid or i)
			card.Size = UDim2.new(1, -8, 0, 50)
			card.BackgroundColor3 = cardBg
			card.BackgroundTransparency = 0.2
			card.BorderSizePixel = 0
			card.Text = ""
			card.AutoButtonColor = true
			card.LayoutOrder = i
			card.Parent = listFrame
			Instance.new("UICorner", card).CornerRadius = UDim.new(0, 6)

			local cardStroke = Instance.new("UIStroke", card)
			cardStroke.Color = C.divider
			cardStroke.Thickness = 1

			-- Inventory-style status watermark (background flavor text)
			if wmText then
				local watermark = Instance.new("TextLabel")
				watermark.Name = "StatusWatermark"
				watermark.Size = UDim2.new(1, 0, 1, 0)
				watermark.BackgroundTransparency = 1
				watermark.RichText = true
				watermark.Text = "<i>" .. wmText .. "</i>"
				watermark.TextColor3 = wmColor
				watermark.TextTransparency = 0.92
				watermark.Font = Enum.Font.GothamBlack
				watermark.TextScaled = true
				watermark.TextXAlignment = Enum.TextXAlignment.Left
				watermark.TextYAlignment = Enum.TextYAlignment.Center
				watermark.ZIndex = 1
				watermark.Parent = card
			end

			-- Rarity indicator bar (left edge)
			local rarityBar = Instance.new("Frame")
			rarityBar.Name = "RarityBar"
			rarityBar.Size = UDim2.new(0, 4, 1, -4)
			rarityBar.Position = UDim2.new(0, 2, 0, 2)
			rarityBar.BackgroundColor3 = RARITY_COLORS[creature.rarity] or C.grey
			rarityBar.BorderSizePixel = 0
			rarityBar.ZIndex = 2
			rarityBar.Parent = card
			Instance.new("UICorner", rarityBar).CornerRadius = UDim.new(0, 2)

			-- Creature name
			local nameLabel = Instance.new("TextLabel")
			nameLabel.Size = UDim2.new(1, -80, 0, 22)
			nameLabel.Position = UDim2.new(0, 14, 0, 4)
			nameLabel.BackgroundTransparency = 1
			nameLabel.Text = creature.displayName or creature.id or "???"
			nameLabel.TextColor3 = C.white
			nameLabel.Font = Enum.Font.GothamBold
			nameLabel.TextSize = 13
			nameLabel.TextXAlignment = Enum.TextXAlignment.Left
			nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
			nameLabel.ZIndex = 2
			nameLabel.Parent = card

			-- Details line: Lv, variant, element
			local detailLabel = Instance.new("TextLabel")
			detailLabel.Size = UDim2.new(1, -80, 0, 16)
			detailLabel.Position = UDim2.new(0, 14, 0, 26)
			detailLabel.BackgroundTransparency = 1
			detailLabel.Text = "Lv" .. (creature.level or 1)
				.. " • " .. (creature.variant or "Normal")
				.. " • " .. (creature.element or "?")
			detailLabel.TextColor3 = C.textSec
			detailLabel.Font = Enum.Font.GothamMedium
			detailLabel.TextSize = 11
			detailLabel.TextXAlignment = Enum.TextXAlignment.Left
			detailLabel.ZIndex = 2
			detailLabel.Parent = card

			-- Rarity label (right side)
			local rarityLabel = Instance.new("TextLabel")
			rarityLabel.Size = UDim2.new(0, 70, 0, 16)
			rarityLabel.Position = UDim2.new(1, -72, 0, 4)
			rarityLabel.BackgroundTransparency = 1
			rarityLabel.Text = creature.rarity or "?"
			rarityLabel.TextColor3 = RARITY_COLORS[creature.rarity] or C.textSec
			rarityLabel.Font = Enum.Font.GothamBold
			rarityLabel.TextSize = 11
			rarityLabel.TextXAlignment = Enum.TextXAlignment.Right
			rarityLabel.ZIndex = 2
			rarityLabel.Parent = card

			-- Bonus tag if this creature matches the Broker's bonus pick
			if data.bonusCreatureId and creature.id == data.bonusCreatureId then
				local bonusTag = Instance.new("TextLabel")
				bonusTag.Name = "BonusTag"
				bonusTag.Size = UDim2.new(0, 70, 0, 14)
				bonusTag.Position = UDim2.new(1, -72, 0, 22)
				bonusTag.BackgroundTransparency = 1
				bonusTag.Text = "★ BONUS"
				bonusTag.TextColor3 = C.gold
				bonusTag.Font = Enum.Font.GothamBold
				bonusTag.TextSize = 10
				bonusTag.TextXAlignment = Enum.TextXAlignment.Right
				bonusTag.ZIndex = 2
				bonusTag.Parent = card

				cardStroke.Color = C.gold
				cardStroke.Thickness = 1.5
			end

			-- Click handler: select this creature
			card.MouseButton1Click:Connect(function()
				if isBusy or isAnimating then return end

				-- Deselect previous
				if selectedCard then
					local prevStroke = selectedCard:FindFirstChildWhichIsA("UIStroke")
					if prevStroke then
						prevStroke.Color = C.divider
						prevStroke.Thickness = 1
					end
				end

				-- Select this one
				selectedCard = card
				selectedUid = creature.uid
				selectedCreatureId = creature.id
				selectedOnDefense = onDef
				selectedOnIncome = onInc
				selectedOnBattle = onBat
				cardStroke.Color = C.green
				cardStroke.Thickness = 2

				-- Viewport stays on the Broker's contract creature (wantedCreatureId), not the pick list selection.

				-- Update button to "Place"---
				actionState = "place"
				updateActionButton()
			end)
		end
	end

	-- ── Action button click handler ──
	actionBtn.MouseButton1Click:Connect(function()
		if isBusy or isAnimating then return end

		if actionState == "place" and selectedUid then
			-- Player clicked Place → advance to Accept (label reflects base placement)
			actionState = "accept"
			updateActionButton()

		elseif actionState == "accept" and selectedUid then
			-- Player clicked Accept → start recall animation, then fire sacrifice
			isBusy = true
			actionBtn.Text = "Channeling..."
			actionBtn.BackgroundColor3 = C.accent
			actionBtn.BackgroundTransparency = 0.3

			-- Hide the main panel
			if mainFrame then
				mainFrame.Visible = false
			end

			-- Play the 10-second recall animation
			local uidToSacrifice = selectedUid
			playRecallAnimation(uidToSacrifice, function()
				-- Animation complete → fire the sacrifice to the server
				if offerCreatureEvt then
					offerCreatureEvt:FireServer(uidToSacrifice)
				end
				-- The server will validate, remove creature, queue, and teleport.
				-- We keep the overlay for the server's BadlandsRunStart event to handle.
				-- Close the broker UI after a short delay (server will teleport us)
				task.delay(2, function()
					closeBrokerUI()
				end)
			end)
		end
	end)

	-- Initial button state
	updateActionButton()

	-- Mobile: fixed desktop pixel layout overflows short panels — size from AbsoluteSize,
	-- shrink 3D viewport ~20%, let the creature list fill remaining height.
	syncBrokerMobileContent = function()
		if not mainFrame or not mainFrame.Parent then return end
		if not MobileWindowLayout.NpcMenuUsesFullscreenBounds(BROKER_DESIGN_W, BROKER_DESIGN_H) then return end

		local totalH = mainFrame.AbsoluteSize.Y
		local totalW = mainFrame.AbsoluteSize.X
		if totalH < 24 or totalW < 24 then return end

		local margin = 6
		local titleH = 36
		titleBar.Size = UDim2.new(1, 0, 0, titleH)
		titleLabel.TextSize = 16
		closeBtn.Size = UDim2.new(0, 32, 0, 32)
		closeBtn.Position = UDim2.new(1, -36, 0, 2)
		closeBtn.TextSize = 15

		local contentTop = titleH + 2
		local contentH = totalH - contentTop - margin
		local colGap = margin
		local halfW = math.floor((totalW - margin * 2 - colGap) / 2)

		leftCol.Size = UDim2.new(0, halfW, 0, contentH)
		leftCol.Position = UDim2.new(0, margin, 0, contentTop)
		rightCol.Size = UDim2.new(0, halfW, 0, contentH)
		rightCol.Position = UDim2.new(0, margin + halfW + colGap, 0, contentTop)

		-- Left stack: demand frame → viewport
		local demandH = math.clamp(math.floor(contentH * 0.25), 60, 100)
		demandFrame.Size = UDim2.new(1, 0, 0, demandH)
		demandFrame.Position = UDim2.new(0, 0, 0, 0)
		demandLabel.TextSize = 11

		local y = demandH + 4

		local remainingForVp = math.max(0, contentH - y - margin)
		-- ~20% smaller than filling the leftover column (was fixed 200px; cap ~160)
		local vpH = math.floor(remainingForVp * 0.80)
		vpH = math.clamp(vpH, 72, math.min(160, remainingForVp))
		viewportContainer.Position = UDim2.new(0, 0, 0, y)
		viewportContainer.Size = UDim2.new(1, 0, 0, vpH)

		local ph = viewportContainer:FindFirstChildWhichIsA("TextLabel")
		if ph and ph.Name ~= "DemandText" then
			ph.TextSize = 48
		end

		-- Right: header + flexible ScrollingFrame + pinned action button
		local headerH = 20
		listHeader.Size = UDim2.new(1, 0, 0, headerH)
		listHeader.TextSize = 12

		local actionH = 36
		actionBtn.Size = UDim2.new(1, 0, 0, actionH)
		actionBtn.Position = UDim2.new(0, 0, 1, -(actionH + 4))

		local listTop = headerH + 4
		local listPadBottom = actionH + 10
		local listH = contentH - listTop - listPadBottom
		listFrame.Position = UDim2.new(0, 0, 0, listTop)
		listFrame.Size = UDim2.new(1, 0, 0, math.max(72, listH))
		listFrame.ScrollBarThickness = 5

		-- Long "no creatures" copy must scroll, not clip
		for _, child in ipairs(listFrame:GetChildren()) do
			if child:IsA("TextLabel") then
				child.Size = UDim2.new(1, -8, 0, 0)
				child.AutomaticSize = Enum.AutomaticSize.Y
			end
		end
	end

	applyBrokerWindowLayout()
	if viewportLayoutUnbind then
		viewportLayoutUnbind()
		viewportLayoutUnbind = nil
	end
	viewportLayoutUnbind = MobileWindowLayout.BindViewportUpdate(function()
		applyBrokerWindowLayout()
		if syncBrokerMobileContent then
			task.defer(syncBrokerMobileContent)
		end
	end)
	MobileWindowLayout.NotifyMenuOpened()
	brokerMenuVisible = true

	-- ── Entrance animation: slide+fade desktop, fade mobile ──
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(BROKER_DESIGN_W, BROKER_DESIGN_H) then
		mainFrame.BackgroundTransparency = 1
		TweenService:Create(mainFrame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			BackgroundTransparency = 0.05,
		}):Play()
	else
		mainFrame.Position = UDim2.new(0.5, 0, 0.6, 0)
		mainFrame.BackgroundTransparency = 1
		local entranceTween = TweenService:Create(mainFrame, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0.5, 0),
			BackgroundTransparency = 0.05,
		})
		entranceTween:Play()
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- EVENT LISTENERS
-- ═══════════════════════════════════════════════════════════════════════════════

-- BadlandsContractData: Server sends contract info when player presses E on Broker
contractDataEvt.OnClientEvent:Connect(function(data)
	if not data then return end
	showBrokerUI(data)
end)

-- BadlandsQueueReject: Server rejected the sacrifice or queue attempt
if queueRejectEvt then
	queueRejectEvt.OnClientEvent:Connect(function(message)
		if Notify and Notify.Toast then
			Notify.Toast(message or "Rejected by The Broker.", C.red, 4)
		end
		-- If we're in the recall animation, cancel it
		if isAnimating then
			isAnimating = false
		end
		closeBrokerUI()
	end)
end

-- BadlandsRunStart: Server accepted the sacrifice (or run actually started)
if runStartEvt then
	runStartEvt.OnClientEvent:Connect(function(data)
		if not data then return end
		if data.accepted and data.sacrificeMessage then
			-- Sacrifice was accepted — show toast
			if Notify and Notify.Toast then
				Notify.Toast(data.sacrificeMessage, C.accent, 5)
			end
		end
		-- If a full run is starting (has runId), close the UI
		if data.runId then
			closeBrokerUI()
			if Notify and Notify.Toast then
				Notify.Toast("The Badlands await...", C.accent, 3)
			end
		end
	end)
end

print("[BadlandsBrokerClient] Initialized — listening for Broker interactions")
