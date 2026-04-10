-- NotificationManager.lua - ReplicatedStorage.Modules (ModuleScript)
-- Toast, Ticker (top bar), Banner, KillFeed, FloatingText, RewardPopup. GUI restores on respawn.
--
-- TICKER ARCHITECTURE:
-- The ticker is a seamless infinite-scroll marquee at the top of the screen.
-- tickerTrack holds two children laid out horizontally:
--   tickerContent  – the canonical message strip (one copy of all messages)
--   tickerContentCopy – a duplicate strip (tiled N times to fill >= viewport width)
-- The track scrolls left at TICKER_SCROLL_SPEED px/sec. When scrollPos reaches
-- -tickerContentWidth the position wraps back by +tickerContentWidth, landing at
-- the identical start of the copy → seamless loop.
--
-- WIDTH TRACKING: All element widths are pre-computed via TextService:GetTextSize()
-- so tickerContentWidth is always deterministic and synchronous — no deferred
-- measurements, no stale values, no scroll-wrap jumps.
--
-- INCREMENTAL UPDATES: New messages are appended to the right end of tickerContent
-- (and the copy is rebuilt). Old messages are removed from the left end when the
-- queue exceeds TICKER_MAX_MESSAGES. The scroll position is compensated precisely
-- so the visible content never jumps.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local TextService = game:GetService("TextService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NotificationManager = {}

-- Legacy API (no-op) - kept for compatibility
function NotificationManager.GetNotifications() return {} end
function NotificationManager.GetBadgeCount() return 0 end
function NotificationManager.MarkAllRead() end
function NotificationManager.ClearNotifications() end
function NotificationManager.SetCategoryPreference(_, _) end
function NotificationManager.GetCategoryPreference(_) return "toast" end

-- ══════════════════════════════════════
-- SCREEN GUI + TOAST CONTAINER + TICKER
-- ══════════════════════════════════════
local sg = nil
local toastContainer = nil
local toastOrder = 0
local tickerBar = nil
local tickerViewport = nil
local tickerTrack = nil
local tickerContent = nil
local tickerContentCopy = nil
local tickerQueue = {}
local tickerPendingEntries = {}
local tickerScrollPos = 0
local tickerContentWidth = 0
local tickerHeartbeatConn = nil
local tickerViewportSizeConn = nil
local tickerRefreshScheduled = false
local tickerSyncScheduled = false
local tickerMutating = false
local tickerNeedsFullRebuild = false
local TICKER_MAX_MESSAGES = 12
local TICKER_MOBILE_SCALE = 0.5
local TICKER_DESKTOP_TOP_Y = 10
local TICKER_MOBILE_Y_OFFSET = -10
local TICKER_SCROLL_SPEED = 36  -- pixels per second (right-to-left)
local TICKER_IDLE_SILENCE_DELAY = 18
local TICKER_SILENCE_TEXT = "...Silence..."
local tickerSilenceArmed = true
local tickerSilenceTaskToken = 0

-- Gold Tracking Siegelings color scheme
local TICKER_BG = Color3.fromRGB(18, 22, 32)
local TICKER_STROKE = Color3.fromRGB(220, 180, 60)
local TICKER_TEXT = Color3.fromRGB(255, 215, 90)        -- Arena / default gold
local TICKER_COLOR_CONVERSATION = Color3.fromRGB(100, 180, 255)  -- Blue
local TICKER_COLOR_RAID = Color3.fromRGB(255, 80, 80)   -- Red
local TICKER_SEP = Color3.fromRGB(180, 170, 130)

-- Ticker layout constants
local TICKER_PAD = 12            -- UIListLayout.Padding between children (must match contentLayout)
local TICKER_SEP_TEXT = " — "    -- separator between messages
local TICKER_TEXT_SIZE = 12
local TICKER_TEXT_HEIGHT = 18
local TICKER_MIN_COPY_FILL = 2  -- copy fills at least 2x viewport width
local TICKER_DEBUG_VALIDATE = false

local requestTickerSync
local requestTickerRefresh

local function buildNotificationUI()
	if sg and sg.Parent then return sg end

	sg = Instance.new("ScreenGui")
	sg.Name = "NotificationGUI"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 50
	sg.Parent = playerGui
	return sg
end

local function ensureToastContainer()
	buildNotificationUI()
	if toastContainer and toastContainer.Parent then return toastContainer end

	toastContainer = Instance.new("Frame")
	toastContainer.Name = "ToastContainer"
	toastContainer.Size = UDim2.new(0, 560, 0, 220)
	toastContainer.Position = UDim2.new(0.5, -280, 0, 12)
	toastContainer.BackgroundTransparency = 1
	toastContainer.Parent = sg

	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Parent = toastContainer

	return toastContainer
end

local function getToastColorForCategory(category)
	if category == "conversation" then return TICKER_COLOR_CONVERSATION end
	if category == "raid" then return TICKER_COLOR_RAID end
	return TICKER_TEXT
end

local function pushToastLine(text, color, duration, category)
	if not text or text == "" then return end
	local container = ensureToastContainer()
	toastOrder += 1

	local row = Instance.new("TextLabel")
	row.Name = "Toast_" .. tostring(toastOrder)
	row.LayoutOrder = toastOrder
	row.Size = UDim2.new(1, 0, 0, 26)
	row.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	row.BackgroundTransparency = 0.15
	row.BorderSizePixel = 0
	row.Text = text
	row.TextColor3 = color or getToastColorForCategory(category)
	row.Font = Enum.Font.GothamMedium
	row.TextSize = 13
	row.TextXAlignment = Enum.TextXAlignment.Center
	row.TextTruncate = Enum.TextTruncate.AtEnd
	row.Parent = container
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)

	local stroke = Instance.new("UIStroke")
	stroke.Color = color or getToastColorForCategory(category)
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = row

	task.delay(duration or 4, function()
		if row.Parent then
			TweenService:Create(row, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				TextTransparency = 1,
				BackgroundTransparency = 1,
			}):Play()
			task.delay(0.35, function()
				if row.Parent then row:Destroy() end
			end)
		end
	end)

	local visibleRows = {}
	for _, child in ipairs(container:GetChildren()) do
		if child:IsA("TextLabel") then
			table.insert(visibleRows, child)
		end
	end
	if #visibleRows > 6 then
		table.sort(visibleRows, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, #visibleRows - 6 do
			visibleRows[i]:Destroy()
		end
	end
end

-- ══════════════════════════════════════
-- TICKER (continuous horizontal news ticker, right-to-left, seamless loop)
-- ══════════════════════════════════════
local function getColorForCategory(category)
	if category == "conversation" then return TICKER_COLOR_CONVERSATION end
	if category == "raid" then return TICKER_COLOR_RAID end
	return TICKER_TEXT
end

-- Pre-compute pixel width of text using TextService (synchronous, no deferred measurement).
-- @param text  string to measure
-- @param font  Enum.Font
-- @param size  number (text size)
-- @return number (pixel width, rounded up)
local function getTextWidth(text, font, size)
	return math.ceil(TextService:GetTextSize(text or "", size, font, Vector2.new(4096, TICKER_TEXT_HEIGHT)).X)
end

-- Separator width (constant, cached on first call)
local _cachedSepWidth = nil
local function getSepWidth()
	if not _cachedSepWidth then
		_cachedSepWidth = getTextWidth(TICKER_SEP_TEXT, Enum.Font.GothamMedium, TICKER_TEXT_SIZE)
	end
	return _cachedSepWidth
end

-- Pre-compute message element pixel width (icon + gap + text label)
-- @param entry  { text, iconType, category, color }
-- @return number (total pixel width of the TickerItem frame)
local function getMsgWidth(entry)
	local iconW = 0
	if entry.iconType == "progress" then iconW = 6 + 6       -- 6px dot + 6px gap
	elseif entry.iconType == "alert" then iconW = 12 + 6 end  -- 12px ! + 6px gap
	return iconW + getTextWidth(entry.text, Enum.Font.GothamMedium, TICKER_TEXT_SIZE)
end

-- Compute total content width from the queue (deterministic, no UI measurement).
-- Accounts for UIListLayout padding (TICKER_PAD) between every child.
-- Layout pattern: [msg1] [pad] [sep] [pad] [msg2] [pad] [sep] [pad] [msg3]
-- @return number (total pixel width)
local function computeContentWidth()
	if #tickerQueue == 0 then return 0 end
	local total = 0
	local childCount = 0  -- number of UI children (messages + separators)
	for i, entry in ipairs(tickerQueue) do
		if i > 1 then
			total += getSepWidth()
			childCount += 1
		end
		total += getMsgWidth(entry)
		childCount += 1
	end
	-- UIListLayout adds TICKER_PAD between each pair of adjacent children
	if childCount > 1 then
		total += (childCount - 1) * TICKER_PAD
	end
	return total
end

-- Get viewport pixel width (with fallback for first frame before layout computes)
local function getViewportWidth()
	if tickerViewport and tickerViewport.Parent and tickerViewport.AbsoluteSize.X > 0 then
		return tickerViewport.AbsoluteSize.X
	end
	return 600
end

local function normalizeTickerScrollPos()
	if tickerContentWidth <= 0 then
		tickerScrollPos = 0
		return
	end
	tickerScrollPos = -(((-tickerScrollPos) % tickerContentWidth))
	if tickerScrollPos == -0 then
		tickerScrollPos = 0
	end
end

local function updateTickerTrackPosition()
	if tickerTrack and tickerTrack.Parent then
		tickerTrack.Position = UDim2.new(0, math.round(tickerScrollPos), 0, 0)
	end
end

local function validateTickerState(context)
	if not TICKER_DEBUG_VALIDATE then return end
	if #tickerQueue > 0 and tickerContentWidth <= 0 then
		warn("[Ticker] Invalid content width after " .. context)
	end
	if tickerContentWidth > 0 then
		local minPos = -tickerContentWidth
		if tickerScrollPos <= minPos or tickerScrollPos > 0 then
			warn(string.format("[Ticker] Scroll out of range after %s: pos=%.3f width=%.3f", context, tickerScrollPos, tickerContentWidth))
		end
	end
	if tickerTrack and tickerTrack.Parent and #tickerQueue > 0 and tickerTrack.AbsoluteSize.X <= 0 then
		warn("[Ticker] Track width is zero while queue has content after " .. context)
	end
end

-- Create a separator TextLabel (" — ")
-- @param order  LayoutOrder value
-- @return TextLabel
local function makeSep(order)
	local s = Instance.new("TextLabel")
	s.Name = "TickerSeparator"
	s.Size = UDim2.new(0, getSepWidth(), 0, TICKER_TEXT_HEIGHT)
	s.BackgroundTransparency = 1
	s.Text = TICKER_SEP_TEXT
	s.TextColor3 = TICKER_SEP
	s.Font = Enum.Font.GothamMedium
	s.TextSize = TICKER_TEXT_SIZE
	s.LayoutOrder = order
	return s
end

-- Create a message Frame (icon + label, positioned manually for fewer instances).
-- @param entry  { text, iconType, category, color }
-- @return Frame
local function makeMsg(entry)
	local textColor = entry.color or getColorForCategory(entry.category)
	local w = getMsgWidth(entry)
	local row = Instance.new("Frame")
	row.Name = "TickerItem"
	row.BackgroundTransparency = 1
	row.Size = UDim2.new(0, w, 1, 0)
	local lx = 0
	if entry.iconType == "progress" then
		local dot = Instance.new("Frame")
		dot.Size = UDim2.new(0, 6, 0, 6)
		dot.Position = UDim2.new(0, 0, 0.5, -3)
		dot.BackgroundColor3 = Color3.fromRGB(80, 220, 120)
		dot.BorderSizePixel = 0
		dot.Parent = row
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		lx = 12  -- 6px dot + 6px gap
	elseif entry.iconType == "alert" then
		local al = Instance.new("TextLabel")
		al.Size = UDim2.new(0, 12, 0, 12)
		al.Position = UDim2.new(0, 0, 0.5, -6)
		al.BackgroundTransparency = 1
		al.Text = "!"
		al.TextColor3 = TICKER_STROKE
		al.Font = Enum.Font.GothamBlack
		al.TextSize = 10
		al.Parent = row
		lx = 18  -- 12px ! + 6px gap
	end
	local lbl = Instance.new("TextLabel")
	lbl.BackgroundTransparency = 1
	lbl.Text = entry.text
	lbl.TextColor3 = textColor
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = TICKER_TEXT_SIZE
	lbl.TextYAlignment = Enum.TextYAlignment.Center
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Size = UDim2.new(0, math.max(w - lx, 0), 1, 0)
	lbl.Position = UDim2.new(0, lx, 0, 0)
	lbl.Parent = row
	return row
end

-- Clear all non-UIListLayout children from a container frame.
local function clearChildren(container)
	if not container then return end
	for _, c in ipairs(container:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
end

-- Get the highest LayoutOrder among a container's children.
local function getMaxOrder(container)
	local mx = 0
	if not container then return mx end
	for _, c in ipairs(container:GetChildren()) do
		if not c:IsA("UIListLayout") then
			mx = math.max(mx, c.LayoutOrder or 0)
		end
	end
	return mx
end

-- Update the explicit Size of tickerContent and tickerTrack to match tickerContentWidth.
-- Also triggers a copy rebuild so the copy stays in sync and fills the viewport.
local function syncTickerSizes()
	if tickerContent then
		tickerContent.Size = UDim2.new(0, tickerContentWidth, 1, 0)
	end
	-- Rebuild copy atomically: create a new copy frame, then swap.
	if not tickerTrack or not tickerContentCopy then return end
	if #tickerQueue == 0 or tickerContentWidth <= 0 then
		clearChildren(tickerContentCopy)
		tickerContentCopy.Size = UDim2.new(0, 0, 1, 0)
		tickerTrack.Size = UDim2.new(0, 0, 1, 0)
		tickerScrollPos = 0
		updateTickerTrackPosition()
		return
	end
	local newCopy = Instance.new("Frame")
	newCopy.Name = "TickerContentCopy"
	newCopy.LayoutOrder = 2
	newCopy.Size = UDim2.new(0, 0, 1, 0)
	newCopy.BackgroundTransparency = 1
	local copyLayout = Instance.new("UIListLayout")
	copyLayout.FillDirection = Enum.FillDirection.Horizontal
	copyLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	copyLayout.Padding = UDim.new(0, TICKER_PAD)
	copyLayout.Parent = newCopy

	local viewW = getViewportWidth()
	local targetW = math.max(viewW * TICKER_MIN_COPY_FILL, tickerContentWidth + viewW)
	local order = 0
	local copyW = 0
	local copyChildCount = 0
	while copyW < targetW do
		local blockW = 0
		local blockChildren = 0
		-- Leading separator (connects end of previous block / content to start of this block)
		order += 1
		local ls = makeSep(order)
		ls.Parent = newCopy
		blockW += getSepWidth()
		blockChildren += 1
		-- All messages from queue
		for i, entry in ipairs(tickerQueue) do
			if i > 1 then
				order += 1
				local ms = makeSep(order)
				ms.Parent = newCopy
				blockW += getSepWidth()
				blockChildren += 1
			end
			order += 1
			local el = makeMsg(entry)
			el.LayoutOrder = order
			el.Parent = newCopy
			blockW += getMsgWidth(entry)
			blockChildren += 1
		end
		-- Account for UIListLayout padding within this block
		if blockChildren > 0 then
			-- Padding between this block and previous children
			if copyChildCount > 0 then
				blockW += TICKER_PAD  -- padding before the leading separator
			end
			blockW += (blockChildren - 1) * TICKER_PAD  -- padding within block
		end
		copyW += blockW
		copyChildCount += blockChildren
		if blockW <= 0 then break end  -- safety
	end
	newCopy.Size = UDim2.new(0, copyW, 1, 0)
	newCopy.Parent = tickerTrack
	local oldCopy = tickerContentCopy
	tickerContentCopy = newCopy
	if oldCopy and oldCopy.Parent then
		oldCopy:Destroy()
	end
	tickerTrack.Size = UDim2.new(0, tickerContentWidth + copyW, 1, 0)
	normalizeTickerScrollPos()
	updateTickerTrackPosition()
	validateTickerState("syncTickerSizes")
end

-- ── INCREMENTAL OPERATIONS ──
-- These modify tickerContent without destroying existing elements (no jumps).

-- Append one message to the RIGHT end of tickerContent. Called when a new message arrives.
-- @param entry    { text, iconType, category }
-- @param isFirst  boolean (true if this is the only message, skip leading separator)
local function appendToContent(entry, isFirst)
	if not tickerContent then return end
	local order = getMaxOrder(tickerContent)
	if not isFirst then
		order += 1
		local sep = makeSep(order)
		sep.Parent = tickerContent
	end
	order += 1
	local el = makeMsg(entry)
	el.LayoutOrder = order
	el.Parent = tickerContent
	-- Recompute width from queue (deterministic, always accurate)
	tickerContentWidth = computeContentWidth()
end

-- Remove the OLDEST (leftmost) message + its trailing separator from tickerContent.
-- Returns the removed visual width for scroll compensation.
-- Called AFTER the entry has already been removed from tickerQueue.
local function removeOldestFromContent()
	if not tickerContent then return 0 end
	local widthBefore = tickerContentWidth
	-- Find ordered children
	local children = {}
	for _, c in ipairs(tickerContent:GetChildren()) do
		if not c:IsA("UIListLayout") then table.insert(children, c) end
	end
	table.sort(children, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
	if #children == 0 then return 0 end
	-- Destroy the first element (the oldest message)
	children[1]:Destroy()
	-- If the new first element is a separator, destroy it too (it was between msg1 and msg2)
	-- Re-fetch after destroy
	local remaining = {}
	for _, c in ipairs(tickerContent:GetChildren()) do
		if not c:IsA("UIListLayout") then table.insert(remaining, c) end
	end
	table.sort(remaining, function(a, b) return (a.LayoutOrder or 0) < (b.LayoutOrder or 0) end)
	if #remaining > 0 and remaining[1].Name == "TickerSeparator" then
		remaining[1]:Destroy()
	end
	-- Recompute from queue (which was already trimmed)
	tickerContentWidth = computeContentWidth()
	return math.max(0, widthBefore - tickerContentWidth)
end

-- ── FULL REBUILD ──
-- Only used when starting from empty (unavoidable). Sets tickerScrollPos = 0.

local function rebuildTickerContent()
	if not tickerContent or not tickerContentCopy then return end
	clearChildren(tickerContent)
	local order = 0
	for i, entry in ipairs(tickerQueue) do
		if i > 1 then
			order += 1
			local sep = makeSep(order)
			sep.Parent = tickerContent
		end
		order += 1
		local el = makeMsg(entry)
		el.LayoutOrder = order
		el.Parent = tickerContent
	end
	tickerContentWidth = computeContentWidth()
	tickerScrollPos = 0
end

-- ── SCROLL ENGINE ──

local function updateTickerScroll(dt)
	if tickerMutating or not tickerTrack or not tickerTrack.Parent or tickerContentWidth <= 0 then return end
	-- Cap dt to avoid large jumps on frame hitches (e.g. tab switch)
	dt = math.min(dt, 0.1)
	tickerScrollPos = tickerScrollPos - TICKER_SCROLL_SPEED * dt
	normalizeTickerScrollPos()
	updateTickerTrackPosition()
	validateTickerState("updateTickerScroll")
end

local function startTickerScroll()
	if tickerHeartbeatConn then return end
	tickerHeartbeatConn = RunService.RenderStepped:Connect(function(dt)
		updateTickerScroll(dt)
	end)
end

local function stopTickerScroll()
	if tickerHeartbeatConn then
		tickerHeartbeatConn:Disconnect()
		tickerHeartbeatConn = nil
	end
end

local function scheduleSilenceOneShot()
	tickerSilenceTaskToken += 1
	local token = tickerSilenceTaskToken
	task.delay(TICKER_IDLE_SILENCE_DELAY, function()
		if token ~= tickerSilenceTaskToken then return end
		if #tickerQueue > 0 then return end
		if not tickerSilenceArmed then return end
		tickerSilenceArmed = false
		NotificationManager.Ticker(TICKER_SILENCE_TEXT, nil)
	end)
end

-- ── APPLY UPDATE ──
-- Called after every new message. Uses incremental operations (no full rebuild)
-- unless starting from empty.

local function applyTickerUpdate()
	if #tickerQueue == 0 then return end
	buildNotificationUI()
	if tickerBar then tickerBar.Visible = true end

	-- Starting from empty: full rebuild is unavoidable
	if tickerNeedsFullRebuild or tickerContentWidth <= 0 or not tickerHeartbeatConn then
		while #tickerQueue > TICKER_MAX_MESSAGES do
			table.remove(tickerQueue, 1)
		end
		tickerNeedsFullRebuild = false
		tickerMutating = true
		rebuildTickerContent()
		tickerMutating = false
		requestTickerSync()
		table.clear(tickerPendingEntries)
		startTickerScroll()
		return
	end

	if #tickerPendingEntries == 0 then
		startTickerScroll()
		return
	end

	tickerMutating = true
	-- Trim oldest if over max (incremental removal with deterministic scroll compensation)
	while #tickerQueue > TICKER_MAX_MESSAGES do
		table.remove(tickerQueue, 1)
		local oldWidth = tickerContentWidth
		local removedW = removeOldestFromContent()
		local newWidth = tickerContentWidth
		if oldWidth > 0 and newWidth > 0 and removedW > 0 then
			-- Keep the same visual anchor after left-side deletion.
			tickerScrollPos = tickerScrollPos + removedW
		end
	end

	-- Append all pending messages in order (batch update, no skipped entries).
	local contentChildCount = 0
	for _, c in ipairs(tickerContent:GetChildren()) do
		if not c:IsA("UIListLayout") then contentChildCount += 1 end
	end
	local isFirst = (contentChildCount == 0)
	for _, pendingEntry in ipairs(tickerPendingEntries) do
		appendToContent(pendingEntry, isFirst)
		isFirst = false
	end
	table.clear(tickerPendingEntries)
	normalizeTickerScrollPos()
	tickerMutating = false
	requestTickerSync()
	validateTickerState("applyTickerUpdate")
	startTickerScroll()
end

local function refreshTicker()
	if #tickerQueue == 0 then
		if tickerBar then tickerBar.Visible = false end
		table.clear(tickerPendingEntries)
		stopTickerScroll()
		scheduleSilenceOneShot()
		return
	end
	applyTickerUpdate()
end

requestTickerSync = function()
	if tickerSyncScheduled then return end
	tickerSyncScheduled = true
	task.defer(function()
		tickerSyncScheduled = false
		if not tickerTrack or not tickerTrack.Parent then return end
		local wasMutating = tickerMutating
		tickerMutating = true
		syncTickerSizes()
		tickerMutating = wasMutating
	end)
end

requestTickerRefresh = function()
	if tickerRefreshScheduled then return end
	tickerRefreshScheduled = true
	task.defer(function()
		tickerRefreshScheduled = false
		refreshTicker()
	end)
end

-- Push a message to the ticker.
-- @param text      string - message text
-- @param iconType  "progress" (green dot), "alert" (gold !), or nil
-- @param category  "conversation" (blue), "raid" (red), "arena"/nil (gold)
function NotificationManager.Ticker(text, iconType, category)
	if not text or text == "" then return end
	pushToastLine(text, nil, 4, category)
end

-- Restore UI on respawn (PlayerGui is cleared)
player.CharacterAdded:Connect(function()
	task.wait(0.1)
	sg = nil
	toastContainer = nil
	toastOrder = 0
	tickerBar = nil
	tickerViewport = nil
	tickerTrack = nil
	tickerContent = nil
	tickerContentCopy = nil
	tickerQueue = {}
	tickerPendingEntries = {}
	tickerScrollPos = 0
	tickerContentWidth = 0
	tickerNeedsFullRebuild = false
	tickerMutating = false
	tickerRefreshScheduled = false
	tickerSyncScheduled = false
	if tickerViewportSizeConn then
		tickerViewportSizeConn:Disconnect()
		tickerViewportSizeConn = nil
	end
	killFeedContainer = nil
	buildNotificationUI()
end)

-- ══════════════════════════════════════
-- TOAST (redirects to Ticker)
-- ══════════════════════════════════════

local function formatKnightly(text, category)
	category = category or "general"
	if category == "arena" then return "Arena Chronicle: " .. text
	elseif category == "raid" then return "Raid Chronicle: " .. text
	elseif category == "trade" then return "Market Ledger: " .. text
	elseif category == "combat" then return "Battle Report: " .. text
	elseif category == "inventory" then return "Inventory Ledger: " .. text
	elseif category == "shop" then return "Bazaar Note: " .. text
	elseif category == "base" then return "Stronghold Log: " .. text
	elseif category == "capture" then return "Capture Chronicle: " .. text
	elseif category == "pvp" then return "Duel Chronicle: " .. text
	end
	return text
end

function NotificationManager.Toast(text, color, duration, icon, category)
	if not text or text == "" or text == "nil" or text == "false" then return nil end
	local displayText = formatKnightly(text, category)
	local toastCategory = (category == "raid") and "raid" or (category == "arena" or category == "combat" or category == "pvp") and "arena" or category
	pushToastLine(displayText, color, duration or 4, toastCategory)
	return nil
end

-- ══════════════════════════════════════
-- BANNER (top center)
-- ══════════════════════════════════════
local activeBanner = nil
local bannerQueue = {}
local bannerProcessing = false

local function processBannerQueue()
	if bannerProcessing then return end
	bannerProcessing = true
	while #bannerQueue > 0 do
		local item = table.remove(bannerQueue, 1)
		buildNotificationUI()
		if activeBanner and activeBanner.Parent then activeBanner:Destroy() end
		local banner = Instance.new("Frame")
		banner.Name = "Banner"
		banner.Size = UDim2.new(0.5, 0, 0, 44)
		banner.Position = UDim2.new(0.25, 0, 0.08, -50)
		banner.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
		banner.BackgroundTransparency = 0.05
		banner.BorderSizePixel = 0
		banner.Parent = sg
		Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)
		local stroke = Instance.new("UIStroke", banner)
		stroke.Color = item.color or Color3.fromRGB(255, 200, 50)
		stroke.Thickness = 2
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -20, 1, 0)
		lbl.Position = UDim2.new(0, 10, 0, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = item.text
		lbl.TextColor3 = item.color or Color3.fromRGB(255, 200, 50)
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextSize = 15
		lbl.TextWrapped = true
		lbl.Parent = banner
		activeBanner = banner
		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.25, 0, 0.08, 0)
		}):Play()
		task.wait(item.duration or 4)
		if banner.Parent then
			TweenService:Create(banner, TweenInfo.new(0.35), {
				Position = UDim2.new(0.25, 0, 0.08, -55),
				BackgroundTransparency = 1
			}):Play()
			task.wait(0.4)
			if banner.Parent then banner:Destroy() end
		end
		activeBanner = nil
		task.wait(0.25)
	end
	bannerProcessing = false
end

function NotificationManager.Banner(text, color, duration)
	table.insert(bannerQueue, { text = text, color = color, duration = duration or 4 })
	task.spawn(processBannerQueue)
end

-- ══════════════════════════════════════
-- KILL FEED (top right, ephemeral)
-- ══════════════════════════════════════
local killFeedContainer = nil
local killOrder = 0

function NotificationManager.KillFeed(attackerName, defenderName, color)
	buildNotificationUI()
	if not killFeedContainer or not killFeedContainer.Parent then
		killFeedContainer = Instance.new("Frame")
		killFeedContainer.Name = "KillFeed"
		killFeedContainer.Size = UDim2.new(0, 260, 0, 140)
		killFeedContainer.Position = UDim2.new(1, -270, 0, 70)
		killFeedContainer.BackgroundTransparency = 1
		killFeedContainer.Parent = sg
		local layout = Instance.new("UIListLayout")
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Padding = UDim.new(0, 4)
		layout.Parent = killFeedContainer
	end
	killOrder = killOrder + 1
	local order = killOrder
	local entry = Instance.new("TextLabel")
	entry.Name = "Kill_" .. order
	entry.LayoutOrder = order
	entry.Size = UDim2.new(1, 0, 0, 22)
	entry.BackgroundColor3 = Color3.fromRGB(16, 18, 26)
	entry.BackgroundTransparency = 0.3
	entry.BorderSizePixel = 0
	entry.Text = "  " .. (attackerName or "?") .. " KO'd " .. (defenderName or "?")
	entry.TextColor3 = color or Color3.fromRGB(200, 205, 220)
	entry.Font = Enum.Font.GothamBold
	entry.TextSize = 11
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.Parent = killFeedContainer
	Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 6)
	task.delay(5, function()
		if entry.Parent then
			TweenService:Create(entry, TweenInfo.new(0.6), {
				TextTransparency = 1, BackgroundTransparency = 1
			}):Play()
			task.delay(0.65, function()
				if entry.Parent then entry:Destroy() end
			end)
		end
	end)
	local children = {}
	for _, ch in ipairs(killFeedContainer:GetChildren()) do
		if ch:IsA("TextLabel") then table.insert(children, ch) end
	end
	if #children > 6 then
		table.sort(children, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, #children - 6 do children[i]:Destroy() end
	end
end

-- ══════════════════════════════════════
-- FLOATING TEXT (center screen)
-- ══════════════════════════════════════
local floatY = 0

function NotificationManager.FloatingText(text, color)
	buildNotificationUI()
	floatY = floatY + 32
	if floatY > 120 then floatY = 0 end
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 380, 0, 26)
	lbl.Position = UDim2.new(0.5, -190, 0.45, floatY)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color or Color3.new(1, 1, 1)
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 17
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = sg
	TweenService:Create(lbl, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = lbl.Position + UDim2.new(0, 0, 0, -65),
		TextTransparency = 1, TextStrokeTransparency = 1
	}):Play()
	task.delay(2.3, function()
		if lbl.Parent then lbl:Destroy() end
	end)
end

-- ══════════════════════════════════════
-- REWARD POPUP (center overlay)
-- ══════════════════════════════════════
function NotificationManager.RewardPopup(titleText, titleColor, lines, duration)
	if not titleText or titleText == "" then return nil end
	buildNotificationUI()
	duration = duration or 6
	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.55
	overlay.BorderSizePixel = 0
	overlay.Parent = sg
	local yOff = 16
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.fromRGB(26, 29, 42)
	card.BorderSizePixel = 0
	card.Parent = overlay
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = titleColor or Color3.fromRGB(255, 200, 50)
	stroke.Thickness = 2
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 28)
	title.Position = UDim2.new(0, 12, 0, yOff)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = titleColor or Color3.fromRGB(255, 200, 50)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.Parent = card
	yOff = yOff + 34
	local div = Instance.new("Frame")
	div.Size = UDim2.new(0.9, 0, 0, 1)
	div.Position = UDim2.new(0.05, 0, 0, yOff)
	div.BackgroundColor3 = Color3.fromRGB(50, 55, 72)
	div.BorderSizePixel = 0
	div.Parent = card
	yOff = yOff + 10
	for _, line in ipairs(lines or {}) do
		local lineLabel = Instance.new("TextLabel")
		lineLabel.Size = UDim2.new(1, -24, 0, line.size or 18)
		lineLabel.Position = UDim2.new(0, 12, 0, yOff)
		lineLabel.BackgroundTransparency = 1
		lineLabel.Text = line.text
		lineLabel.TextColor3 = line.color or Color3.fromRGB(200, 205, 220)
		lineLabel.Font = line.font or Enum.Font.GothamBold
		lineLabel.TextSize = line.textSize or 14
		lineLabel.TextXAlignment = Enum.TextXAlignment.Left
		lineLabel.TextWrapped = true
		lineLabel.Parent = card
		yOff = yOff + (line.size or 18) + 4
	end
	yOff = yOff + 14
	card.Size = UDim2.new(0, 340, 0, yOff)
	card.Position = UDim2.new(0.5, -170, 0.5, -yOff / 2)
	local targetSize, targetPos = card.Size, card.Position
	card.Size = UDim2.new(0, 0, 0, 0)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = targetSize, Position = targetPos
	}):Play()
	local dismissed = false
	local function dismiss()
		if dismissed then return end
		dismissed = true
		TweenService:Create(overlay, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(card, TweenInfo.new(0.35), {
			Position = targetPos + UDim2.new(0, 0, 0, -25),
			BackgroundTransparency = 1
		}):Play()
		task.delay(0.45, function()
			if overlay.Parent then overlay:Destroy() end
		end)
	end
	task.delay(duration, dismiss)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0)
	btn.BackgroundTransparency = 1
	btn.Text = ""
	btn.Parent = overlay
	btn.MouseButton1Click:Connect(dismiss)
	return overlay
end

-- Initial build (lazy - first Toast/Banner/etc will trigger it)
buildNotificationUI()

print("[NotificationManager] Loaded - Toast, Ticker, Banner, KillFeed, FloatingText, RewardPopup")
return NotificationManager
