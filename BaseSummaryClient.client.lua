-- ══════════════════════════════════════════════════════════════════════════════
-- BaseSummaryClient.client.lua
-- ══════════════════════════════════════════════════════════════════════════════
-- Shows a condensed "far distance" summary BillboardGui on each base when the
-- player is too far to see individual creature billboards. Replaces the visual
-- clutter of many floating names/HP bars with a single compact card per base.
--
-- ARCHITECTURE:
--   Server (BasePlacementSystem) sets MaxDistance on creature billboards so
--   they auto-hide beyond ~80 studs. This client script creates a summary
--   billboard per plot that fades in at ~60 studs (overlapping briefly with
--   individual tags for a smooth handoff) and fades out when close or too far.
--
--   Creature data is read via CollectionService tags set by the server:
--     • "BaseIncomeCreature"  (set in BasePlacementSystem.lua, line 68)
--     • "BaseDefenseCreature" (set in BasePlacementSystem.lua, line 67)
--     • "BaseBattleCreature"  (set in BasePlacementSystem.lua, line 69)
--
-- STYLING:
--   Glassmorphism card matching HUDButtonBar (dark bg, rounded corners, stroke)
-- ══════════════════════════════════════════════════════════════════════════════

local Players            = game:GetService("Players")
local RunService         = game:GetService("RunService")
local TweenService       = game:GetService("TweenService")
local CollectionService  = game:GetService("CollectionService")
local ReplicatedStorage  = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ══════════════════════════════════════════════════════════════════════════════
-- CONFIGURATION
-- ══════════════════════════════════════════════════════════════════════════════

--- Load shared config for distance thresholds
local GameConfig = require(ReplicatedStorage:WaitForChild("Modules"):WaitForChild("GameConfig"))

--- Distance (studs) at which the summary billboard fades IN.
--- Set slightly below BaseBillboardMaxDistance for overlap during transition.
local SUMMARY_SHOW_DIST = GameConfig.BaseSummaryShowDistance or 60

--- Distance (studs) at which the summary billboard fades OUT (too far to matter).
local SUMMARY_MAX_DIST  = GameConfig.BaseSummaryMaxDistance or 300

--- Hysteresis gap (studs) below SUMMARY_SHOW_DIST before hiding when approaching.
--- Prevents flickering at the boundary.
local SUMMARY_HIDE_CLOSE = SUMMARY_SHOW_DIST - 5

--- How often (seconds) to check distances and update summaries.
local SCAN_INTERVAL = 0.5

--- Duration (seconds) for fade in/out transitions.
local FADE_DURATION = 0.3

--- Billboard vertical offset above PlotCenter (studs).
local BILLBOARD_Y_OFFSET = 25

-- ══════════════════════════════════════════════════════════════════════════════
-- STYLE CONSTANTS (matching HUDButtonBar glassmorphism)
-- ══════════════════════════════════════════════════════════════════════════════

local CARD_BG_COLOR       = Color3.fromRGB(14, 16, 24)
local CARD_BG_TRANSPARENCY = 0.15
local CARD_CORNER_RADIUS  = UDim.new(0, 10)
local CARD_STROKE_COLOR   = Color3.fromRGB(60, 60, 80)
local CARD_STROKE_WIDTH   = 1.5

local TITLE_COLOR   = Color3.fromRGB(240, 240, 245)
local INCOME_COLOR  = Color3.fromRGB(50, 220, 120)   -- green  (matches base ring)
local DEFENSE_COLOR = Color3.fromRGB(220, 60, 70)    -- red    (matches base ring)
local BATTLE_COLOR  = Color3.fromRGB(130, 100, 255)  -- purple (matches base ring)
local POWER_COLOR   = Color3.fromRGB(255, 200, 50)   -- gold

-- FIX #33: Crest badge toggle (mirrors arena badge system)
-- Badge sits to the right of the ticker, SECOND slot (arena badge is first).
local BADGE_WIDTH       = 36
local BADGE_HEIGHT      = 42
local BADGE_GAP         = 8     -- gap between badges / from ticker
local BADGE_SLOT        = 1     -- 0 = arena badge, 1 = base badge (second position)
local BADGE_BG          = Color3.fromRGB(18, 22, 32)
local BADGE_GOLD        = Color3.fromRGB(220, 180, 60)
local BADGE_DISPLAY_ORD = 52    -- above arena badge (51) and NotificationGUI (50)

-- Tags (must match BasePlacementSystem server-side tags)
local INCOME_TAG  = "BaseIncomeCreature"
local DEFENSE_TAG = "BaseDefenseCreature"
local BATTLE_TAG  = "BaseBattleCreature"

-- ══════════════════════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════════════════════

--- @type { [Model]: SummaryEntry }
--- Maps each plot model to its summary GUI state.
local summaryGuis = {}

--- @type { [number]: string }
--- Caches userId → display name to avoid repeated async calls.
local nameCache = {}

--- Accumulated time since last scan.
local timeSinceLastScan = 0

--- One-time debug flag: print distance info on first successful scan
local hasLoggedFirstScan = false
--- One-shot logs for early exits (hasLoggedFirstScan is only set after a full plot pass)
local loggedNilRootOnce = false
local loggedMissingBasePlotsOnce = false

-- FIX #33: Badge toggle state — summary hidden by default, badge toggles it
local badge = {
	gui       = nil,  -- ScreenGui
	button    = nil,  -- TextButton (shield shape)
	glow      = nil,  -- UIStroke for pulse animation
	visible   = false,
	pulseConn = nil,  -- RenderStepped connection
}
local manualToggle = false  -- true = player toggled summary ON via badge
--- Whether the player is currently in range for the base summary to be relevant.
--- Badge only shows when inRange is true.
local inRange = false

-- ══════════════════════════════════════════════════════════════════════════════
-- HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

--- Returns the player's HumanoidRootPart, or nil if not available.
--- @return BasePart|nil
local function getRoot()
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart")
end

--- Resolves a PlotCenter instance to a BasePart.
--- PlotCenter may be a BasePart directly, or a Model containing parts.
--- @param plotCenter Instance — the PlotCenter found via FindFirstChild
--- @return BasePart|nil — the part to use for position/adornee, or nil
local function resolvePlotCenterPart(plotCenter)
	if plotCenter:IsA("BasePart") then
		return plotCenter
	end
	if plotCenter:IsA("Model") then
		-- Try PrimaryPart first, then any BasePart child
		if plotCenter.PrimaryPart then
			return plotCenter.PrimaryPart
		end
		return plotCenter:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

--- Resolves a userId to a display name. Cached after first lookup.
--- Runs the async call in a pcall to avoid yielding errors.
--- @param userId number
--- @return string
local function getOwnerName(userId)
	if not userId or userId == 0 then
		return "Unclaimed"
	end
	if nameCache[userId] then
		return nameCache[userId]
	end
	-- Attempt async resolve (yields, but only once per userId)
	local ok, name = pcall(Players.GetNameFromUserIdAsync, Players, userId)
	if ok and name then
		nameCache[userId] = name
		return name
	end
	-- Fallback if lookup fails
	local fallback = "Player " .. tostring(userId)
	nameCache[userId] = fallback
	return fallback
end

--- Counts creatures on a specific plot, grouped by slot type.
--- Uses CollectionService tags + IsDescendantOf filter.
--- @param plotModel Model — the plot to scan
--- @return number incomeCount
--- @return number defenseCount
--- @return number battleCount
--- @return number totalLevel — sum of all creature levels on this plot
local function countCreatures(plotModel)
	local income, defense, battle = 0, 0, 0
	local totalLevel = 0

	for _, model in ipairs(CollectionService:GetTagged(INCOME_TAG)) do
		if model:IsDescendantOf(plotModel) then
			income = income + 1
			totalLevel = totalLevel + (model:GetAttribute("CreatureLevel") or 1)
		end
	end

	for _, model in ipairs(CollectionService:GetTagged(DEFENSE_TAG)) do
		if model:IsDescendantOf(plotModel) then
			defense = defense + 1
			totalLevel = totalLevel + (model:GetAttribute("CreatureLevel") or 1)
		end
	end

	for _, model in ipairs(CollectionService:GetTagged(BATTLE_TAG)) do
		if model:IsDescendantOf(plotModel) then
			battle = battle + 1
			totalLevel = totalLevel + (model:GetAttribute("CreatureLevel") or 1)
		end
	end

	return income, defense, battle, totalLevel
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SUMMARY GUI CONSTRUCTION
-- ══════════════════════════════════════════════════════════════════════════════

--- Creates a single stat line label inside the card.
--- @param parent CanvasGroup — the card container
--- @param color Color3 — text color for the stat
--- @param yOffset number — vertical pixel offset within the card
--- @param name string — Instance name for the label
--- @return TextLabel
local function createStatLabel(parent, color, yOffset, name)
	local label = Instance.new("TextLabel")
	label.Name = name
	label.Size = UDim2.new(1, -16, 0, 16)
	label.Position = UDim2.new(0, 8, 0, yOffset)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamMedium
	label.TextSize = 13
	label.TextColor3 = color
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Text = ""
	label.Parent = parent
	return label
end

--- Builds the summary BillboardGui for a single plot.
--- Attached to PlotCenter and starts fully transparent (fades in when needed).
--- @param plotModel Model — the plot to attach to
--- @return SummaryEntry|nil — the state table, or nil if PlotCenter is missing
local function createSummaryBillboard(plotModel)
	local plotCenterRaw = plotModel:FindFirstChild("PlotCenter", true)
	if not plotCenterRaw then
		warn("[BaseSummary] Plot '" .. plotModel.Name .. "' has no PlotCenter — skipping")
		return nil
	end

	-- Resolve to a BasePart (PlotCenter may be a Model with children)
	local plotCenterPart = resolvePlotCenterPart(plotCenterRaw)
	if not plotCenterPart then
		warn("[BaseSummary] Plot '" .. plotModel.Name .. "' PlotCenter is " .. plotCenterRaw.ClassName .. " with no BasePart child — skipping")
		return nil
	end

	-- Billboard container
	local billboard = Instance.new("BillboardGui")
	billboard.Name = "BaseSummary"
	billboard.Adornee = plotCenterPart
	billboard.Size = UDim2.new(0, 180, 0, 115)
	billboard.StudsOffset = Vector3.new(0, BILLBOARD_Y_OFFSET, 0)
	billboard.AlwaysOnTop = true   -- must render above base building models at distance
	billboard.MaxDistance = SUMMARY_MAX_DIST
	billboard.Parent = plotCenterPart

	-- Card background (Frame — CanvasGroup doesn't work inside BillboardGui)
	local card = Instance.new("Frame")
	card.Name = "Card"
	card.Size = UDim2.new(1, 0, 1, 0)
	card.BackgroundColor3 = CARD_BG_COLOR
	card.BackgroundTransparency = 1  -- starts invisible (faded in later)
	card.BorderSizePixel = 0
	card.Parent = billboard

	-- Rounded corners
	local corner = Instance.new("UICorner")
	corner.CornerRadius = CARD_CORNER_RADIUS
	corner.Parent = card

	-- Border stroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = CARD_STROKE_COLOR
	stroke.Thickness = CARD_STROKE_WIDTH
	stroke.Transparency = 1  -- starts invisible
	stroke.Parent = card

	-- Owner name (title row)
	local ownerLabel = Instance.new("TextLabel")
	ownerLabel.Name = "OwnerLabel"
	ownerLabel.Size = UDim2.new(1, -16, 0, 20)
	ownerLabel.Position = UDim2.new(0, 8, 0, 6)
	ownerLabel.BackgroundTransparency = 1
	ownerLabel.Font = Enum.Font.GothamBold
	ownerLabel.TextSize = 14
	ownerLabel.TextColor3 = TITLE_COLOR
	ownerLabel.TextXAlignment = Enum.TextXAlignment.Left
	ownerLabel.TextTransparency = 1  -- starts invisible
	ownerLabel.Text = "Loading..."
	ownerLabel.Parent = card

	-- Divider line below title
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, -16, 0, 1)
	divider.Position = UDim2.new(0, 8, 0, 28)
	divider.BackgroundColor3 = CARD_STROKE_COLOR
	divider.BackgroundTransparency = 1  -- starts invisible
	divider.BorderSizePixel = 0
	divider.Parent = card

	-- Stat rows
	local incomeLabel  = createStatLabel(card, INCOME_COLOR,  34, "IncomeLabel")
	local defenseLabel = createStatLabel(card, DEFENSE_COLOR, 52, "DefenseLabel")
	local battleLabel  = createStatLabel(card, BATTLE_COLOR,  70, "BattleLabel")
	local powerLabel   = createStatLabel(card, POWER_COLOR,   90, "PowerLabel")

	-- All text labels start invisible
	for _, lbl in ipairs({incomeLabel, defenseLabel, battleLabel, powerLabel}) do
		lbl.TextTransparency = 1
	end

	-- Billboard starts disabled (enabled on fade-in)
	billboard.Enabled = false

	return {
		billboard    = billboard,
		card         = card,
		stroke       = stroke,
		divider      = divider,
		ownerLabel   = ownerLabel,
		incomeLabel  = incomeLabel,
		defenseLabel = defenseLabel,
		battleLabel  = battleLabel,
		powerLabel   = powerLabel,
		visible      = false,   -- current visibility state (for hysteresis)
		tweens       = {},      -- active tweens (cancelled on state change)
	}
end

-- ══════════════════════════════════════════════════════════════════════════════
-- TWEEN HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

--- Cancels all active tweens on an entry.
--- @param entry SummaryEntry
local function cancelTweens(entry)
	for _, tw in ipairs(entry.tweens) do
		tw:Cancel()
	end
	entry.tweens = {}
end

--- Creates a tween and adds it to the entry's tween list.
--- @param entry SummaryEntry
--- @param instance Instance
--- @param info TweenInfo
--- @param props table
local function addTween(entry, instance, info, props)
	local tw = TweenService:Create(instance, info, props)
	table.insert(entry.tweens, tw)
	tw:Play()
end

--- Fades the summary card IN — tweens each element's transparency individually.
--- @param entry SummaryEntry
local function fadeIn(entry)
	cancelTweens(entry)
	entry.visible = true
	entry.billboard.Enabled = true

	local info = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	-- Card background fades to semi-transparent
	addTween(entry, entry.card, info, { BackgroundTransparency = CARD_BG_TRANSPARENCY })
	-- Stroke fades in
	addTween(entry, entry.stroke, info, { Transparency = 0 })
	-- Divider fades in
	addTween(entry, entry.divider, info, { BackgroundTransparency = 0.5 })
	-- All text labels fade in
	for _, lbl in ipairs({entry.ownerLabel, entry.incomeLabel, entry.defenseLabel, entry.battleLabel, entry.powerLabel}) do
		addTween(entry, lbl, info, { TextTransparency = 0 })
	end
end

--- Fades the summary card OUT — tweens each element's transparency to invisible.
--- Disables the billboard after the fade completes.
--- @param entry SummaryEntry
local function fadeOut(entry)
	cancelTweens(entry)
	entry.visible = false

	local info = TweenInfo.new(FADE_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	-- Card background fades out
	addTween(entry, entry.card, info, { BackgroundTransparency = 1 })
	-- Stroke fades out
	addTween(entry, entry.stroke, info, { Transparency = 1 })
	-- Divider fades out
	addTween(entry, entry.divider, info, { BackgroundTransparency = 1 })
	-- All text labels fade out
	for _, lbl in ipairs({entry.ownerLabel, entry.incomeLabel, entry.defenseLabel, entry.battleLabel, entry.powerLabel}) do
		addTween(entry, lbl, info, { TextTransparency = 1 })
	end

	-- Disable billboard after fade completes to save rendering
	task.delay(FADE_DURATION + 0.05, function()
		if not entry.visible then
			entry.billboard.Enabled = false
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- FIX #33: Base crest badge — toggle button for base summary
-- ══════════════════════════════════════════════════════════════════════════════
-- Appears to the right of the arena badge (slot 1) when the player is within
-- base summary range. Clicking toggles the billboard summary on/off.
-- Matches the arena badge style: dark glass, gold stroke, shield shape.
-- ══════════════════════════════════════════════════════════════════════════════

--- Start the gold pulse animation on the badge stroke.
local function startBadgePulse()
	if badge.pulseConn or not badge.glow then return end
	local elapsed = 0
	badge.pulseConn = RunService.RenderStepped:Connect(function(dt)
		elapsed += dt
		local t = (math.sin(elapsed * 4 * math.pi) + 1) / 2
		if badge.glow then
			badge.glow.Thickness = 2 + t * 2
			badge.glow.Transparency = t * 0.3
		end
	end)
end

--- Stop the pulse animation and reset stroke to static.
local function stopBadgePulse()
	if badge.pulseConn then badge.pulseConn:Disconnect(); badge.pulseConn = nil end
	if badge.glow then badge.glow.Thickness = 2; badge.glow.Transparency = 0 end
end

--- Create the base crest badge ScreenGui. Idempotent.
--- Positioned in BADGE_SLOT (1) — right of the arena badge (slot 0).
local function createBaseBadge()
	if badge.gui and badge.gui.Parent then return end

	local sg = Instance.new("ScreenGui")
	sg.Name = "BaseCrestBadge"
	sg.DisplayOrder = BADGE_DISPLAY_ORD
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.Parent = playerGui

	-- Position relative to ticker, in the correct badge slot
	local notifGui  = playerGui:FindFirstChild("NotificationGUI")
	local tickerBar = notifGui and notifGui:FindFirstChild("TickerBar")

	local btn = Instance.new("TextButton")
	btn.Name = "BaseCrestButton"
	btn.Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)

	if tickerBar then
		local ap = tickerBar.AbsolutePosition
		local as = tickerBar.AbsoluteSize
		-- Slot formula: tickerRight + gap + slotIndex * (badgeWidth + gap)
		local xOffset = ap.X + as.X + BADGE_GAP + BADGE_SLOT * (BADGE_WIDTH + BADGE_GAP)
		btn.Position    = UDim2.new(0, xOffset, 0, ap.Y + as.Y / 2)
		btn.AnchorPoint = Vector2.new(0, 0.5)
	else
		-- Fallback: offset from 0.86 by one badge width
		local fallbackX = 0.86 + (BADGE_SLOT * 0.04)
		btn.Position    = UDim2.new(fallbackX, 0, 0, 18)
		btn.AnchorPoint = Vector2.new(0.5, 0)
	end

	btn.BackgroundColor3       = BADGE_BG
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel        = 0
	btn.Text                   = "\240\159\143\176"  -- 🏰 castle emoji
	btn.TextColor3             = BADGE_GOLD
	btn.Font                   = Enum.Font.GothamBold
	btn.TextSize               = 16
	btn.AutoButtonColor        = false
	btn.ZIndex                 = 100
	btn.Parent                 = sg

	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

	-- Shield point (bottom triangle)
	local point = Instance.new("Frame")
	point.Name                 = "ShieldPoint"
	point.Size                 = UDim2.new(0, 16, 0, 10)
	point.Position             = UDim2.new(0.5, 0, 1, -4)
	point.AnchorPoint          = Vector2.new(0.5, 0)
	point.BackgroundColor3     = BADGE_BG
	point.BackgroundTransparency = 0.15
	point.BorderSizePixel      = 0
	point.Rotation             = 45
	point.ZIndex               = 1
	point.Parent               = btn

	-- Gold UIStroke (pulse target)
	local stroke = Instance.new("UIStroke")
	stroke.Color     = BADGE_GOLD
	stroke.Thickness = 2
	stroke.Parent    = btn

	-- Click: toggle base summary billboard
	btn.MouseButton1Click:Connect(function()
		manualToggle = not manualToggle

		-- Toggle all owned base summaries
		for _, entry in pairs(summaryGuis) do
			if manualToggle and not entry.visible then
				fadeIn(entry)
			elseif not manualToggle and entry.visible then
				fadeOut(entry)
			end
		end

		stopBadgePulse()

		-- Scale bounce feedback
		TweenService:Create(btn, TweenInfo.new(0.1, Enum.EasingStyle.Back), {
			Size = UDim2.new(0, BADGE_WIDTH + 6, 0, BADGE_HEIGHT + 6)
		}):Play()
		task.delay(0.12, function()
			if btn and btn.Parent then
				TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
					Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)
				}):Play()
			end
		end)

		print("[BaseSummary] Badge toggled — manualToggle=", manualToggle)
	end)

	badge.gui    = sg
	badge.button = btn
	badge.glow   = stroke
	btn.Visible  = false  -- hidden until player enters range
end

--- Show or hide the base badge based on whether any owned plot is in range.
--- @param shouldShow boolean
local function updateBaseBadgeVisibility(shouldShow)
	if shouldShow and not badge.visible then
		createBaseBadge()
		if not badge.button then return end
		badge.visible = true
		badge.button.Visible = true

		-- Pop-in animation
		badge.button.Size = UDim2.new(0, 0, 0, 0)
		TweenService:Create(badge.button, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = UDim2.new(0, BADGE_WIDTH, 0, BADGE_HEIGHT)
		}):Play()

		startBadgePulse()
		manualToggle = false
		print("[BaseSummary] Badge shown (entered range)")

	elseif not shouldShow and badge.visible then
		stopBadgePulse()
		badge.visible  = false
		manualToggle   = false

		if badge.button and badge.button.Parent then
			TweenService:Create(badge.button, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.new(0, 0, 0, 0)
			}):Play()
			task.delay(0.3, function()
				if badge.button then badge.button.Visible = false end
			end)
		end

		print("[BaseSummary] Badge hidden (left range)")
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- UPDATE LOOP
-- ══════════════════════════════════════════════════════════════════════════════

--- Finds the owner UserId for a plot by checking OwnerUserId on any creature
--- model that is a descendant of the plot. Falls back to checking if a Player's
--- character is near the PlotCenter. Server sets OwnerUserId on each creature
--- model (BasePlacementSystem.lua line 570), NOT on the plot model itself.
--- @param plotModel Model
--- @return number|nil — the owner's UserId, or nil if unclaimed/empty
local function findPlotOwner(plotModel)
	-- Strategy 1: Check the plot model itself (in case future code sets it)
	local directAttr = plotModel:GetAttribute("OwnerUserId")
	if directAttr and directAttr ~= 0 then
		return directAttr
	end

	-- Strategy 2: Read OwnerUserId from any creature on this plot
	-- (all creature orbs have this attribute set by the server)
	for _, desc in ipairs(plotModel:GetDescendants()) do
		if desc:IsA("Model") then
			local ownerId = desc:GetAttribute("OwnerUserId")
			if ownerId and ownerId ~= 0 then
				return ownerId
			end
		end
	end

	return nil
end

--- Updates a single summary entry's text labels with current creature data.
--- Only called when the summary is visible (or becoming visible).
--- @param entry SummaryEntry
--- @param plotModel Model
local function updateSummaryData(entry, plotModel)
	-- Owner name (derived from creature OwnerUserId attributes)
	local ownerId = findPlotOwner(plotModel)
	local ownerName = getOwnerName(ownerId)
	entry.ownerLabel.Text = ownerName .. "'s Base"

	-- Creature counts
	local inc, def, bat, totalLvl = countCreatures(plotModel)
	entry.incomeLabel.Text  = "Income:  " .. inc
	entry.defenseLabel.Text = "Defense: " .. def
	entry.battleLabel.Text  = "Battle:  " .. bat
	entry.powerLabel.Text   = "Power:   " .. totalLvl
end

--- Main Heartbeat handler. Throttled to run every SCAN_INTERVAL seconds.
--- FIX #33: Billboard is hidden by default. Badge appears when in range.
--- Clicking badge toggles billboard visibility. Billboard auto-hides when
--- player leaves range entirely.
RunService.Heartbeat:Connect(function(dt)
	timeSinceLastScan = timeSinceLastScan + dt
	if timeSinceLastScan < SCAN_INTERVAL then
		return
	end
	timeSinceLastScan = 0

	local root = getRoot()
	if not root then
		if not loggedNilRootOnce then
			loggedNilRootOnce = true
			warn("[BaseSummary] No HumanoidRootPart yet (character not spawned or still loading). "
				.. "Distance scans paused. If this never resolves, check server spawn, "
				.. "StarterPlayer, and Output for errors — LoadingGate can still release after a 30s character wait timeout.")
		end
		return
	end
	local playerPos = root.Position

	-- Find the BasePlots folder (same search order as BasePlacementSystem)
	local basePlots = workspace:FindFirstChild("BasePlots")
		or workspace:FindFirstChild("Plots")
	if not basePlots then
		if not loggedMissingBasePlotsOnce then
			loggedMissingBasePlotsOnce = true
			warn("[BaseSummary] workspace.BasePlots / Plots not found — summary UI idle until folder exists")
		end
		updateBaseBadgeVisibility(false)
		return
	end

	-- Track whether ANY owned plot is in badge range this frame
	local anyInRange = false

	for _, plotModel in ipairs(basePlots:GetChildren()) do
		local plotCenterRaw = plotModel:FindFirstChild("PlotCenter", true)
		if not plotCenterRaw then
			continue
		end
		local plotCenterPart = resolvePlotCenterPart(plotCenterRaw)
		if not plotCenterPart then
			continue
		end

		-- Only show summary for the local player's OWN base
		local plotOwner = plotModel:GetAttribute("OwnerUserId")
		if plotOwner and tonumber(plotOwner) ~= player.UserId then
			local existingEntry = summaryGuis[plotModel]
			if existingEntry and existingEntry.visible then
				fadeOut(existingEntry)
			end
			continue
		end
		if not plotOwner then
			continue
		end

		-- XZ distance (ignore vertical)
		local dx = playerPos.X - plotCenterPart.Position.X
		local dz = playerPos.Z - plotCenterPart.Position.Z
		local dist = math.sqrt(dx * dx + dz * dz)

		if not hasLoggedFirstScan then
			print(string.format("[BaseSummary] LOOP: %s dist=%.0f (show=%d, max=%d) plotCenter=%s at (%.0f,%.0f,%.0f)",
				plotModel.Name, dist, SUMMARY_SHOW_DIST, SUMMARY_MAX_DIST,
				plotCenterPart.Name, plotCenterPart.Position.X, plotCenterPart.Position.Y, plotCenterPart.Position.Z))
		end

		-- Lazy-create summary billboard on first encounter
		if not summaryGuis[plotModel] then
			summaryGuis[plotModel] = createSummaryBillboard(plotModel)
		end
		local entry = summaryGuis[plotModel]
		if not entry then
			continue
		end

		-- FIX #33: Determine if player is in the badge-relevant range.
		-- Badge range = SUMMARY_SHOW_DIST to SUMMARY_MAX_DIST (same as old show range).
		-- Use hysteresis on the close edge: show badge at SUMMARY_SHOW_DIST,
		-- hide badge at SUMMARY_HIDE_CLOSE.
		local inDistRange
		if inRange then
			inDistRange = (dist >= SUMMARY_HIDE_CLOSE) and (dist <= SUMMARY_MAX_DIST)
		else
			inDistRange = (dist >= SUMMARY_SHOW_DIST) and (dist <= SUMMARY_MAX_DIST)
		end

		if inDistRange then
			anyInRange = true
		end

		-- FIX #33: Billboard visibility controlled by manualToggle, NOT distance.
		-- Show billboard only when: in range AND player has toggled badge ON.
		local shouldShow = inDistRange and manualToggle

		if shouldShow and not entry.visible then
			fadeIn(entry)
		elseif not shouldShow and entry.visible then
			fadeOut(entry)
		end

		-- Update text data while visible (keeps counts fresh)
		if entry.visible then
			updateSummaryData(entry, plotModel)
		end
	end

	-- FIX #33: Update badge visibility based on whether any owned plot is in range.
	-- When player leaves range, also reset manualToggle so billboard hides.
	inRange = anyInRange
	updateBaseBadgeVisibility(anyInRange)

	if not anyInRange and manualToggle then
		manualToggle = false
	end

	if not hasLoggedFirstScan then
		hasLoggedFirstScan = true
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- CLEANUP
-- ══════════════════════════════════════════════════════════════════════════════
-- If a plot is removed (player leaves, etc.), destroy the summary billboard
-- to prevent orphaned GUI instances.

local function onPlotRemoved(plotModel)
	local entry = summaryGuis[plotModel]
	if entry then
		if entry.tween then
			entry.tween:Cancel()
		end
		if entry.billboard then
			entry.billboard:Destroy()
		end
		summaryGuis[plotModel] = nil
	end
end

-- Connect cleanup to the BasePlots folder (deferred until folder exists)
task.spawn(function()
	local basePlots = workspace:WaitForChild("BasePlots", 30)
		or workspace:WaitForChild("Plots", 10)
	if basePlots then
		basePlots.ChildRemoved:Connect(onPlotRemoved)
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- DEBUG STARTUP — log what we found so issues are easy to diagnose
-- Delayed by 5 seconds to allow streaming/replication to finish loading plots
-- ══════════════════════════════════════════════════════════════════════════════
task.spawn(function()
	task.wait(5)  -- wait for plots to stream in
	local basePlots = workspace:FindFirstChild("BasePlots")
		or workspace:FindFirstChild("Plots")
	if basePlots then
		local plotCount = 0
		for _, child in ipairs(basePlots:GetChildren()) do
			local pc = child:FindFirstChild("PlotCenter", true)
			if pc then
				plotCount = plotCount + 1
				-- PlotCenter may be a Model (with PrimaryPart) or a Part
				local pos
				if pc:IsA("BasePart") then
					pos = pc.Position
				elseif pc:IsA("Model") and pc.PrimaryPart then
					pos = pc.PrimaryPart.Position
				elseif pc:IsA("Model") then
					-- Try to find any BasePart child to get position
					local anyPart = pc:FindFirstChildWhichIsA("BasePart", true)
					pos = anyPart and anyPart.Position
				end
				if pos then
					print(string.format("[BaseSummary] Found %s — PlotCenter at (%.0f, %.0f, %.0f)",
						child.Name, pos.X, pos.Y, pos.Z))
				else
					print(string.format("[BaseSummary] Found %s — PlotCenter exists but is %s (no position)",
						child.Name, pc.ClassName))
				end
			else
				-- Debug: list what children the plot DOES have
				local names = {}
				for _, c in ipairs(child:GetChildren()) do
					table.insert(names, c.Name .. "(" .. c.ClassName .. ")")
				end
				print(string.format("[BaseSummary] %s has NO PlotCenter. Children: %s",
					child.Name, table.concat(names, ", ")))
			end
		end
		print(string.format("[BaseSummary] %d plots with PlotCenter found. ShowDist=%d, MaxDist=%d",
			plotCount, SUMMARY_SHOW_DIST, SUMMARY_MAX_DIST))
	else
		warn("[BaseSummary] Could not find BasePlots or Plots folder in workspace!")
	end
end)

print("[BaseSummary] Initialized — far-distance base summaries active")
