-- NotificationManager.lua - ReplicatedStorage.Modules (ModuleScript)
-- Unified notification system. All client scripts should require this
-- instead of creating their own notification labels.
-- Provides: toast queue (right side), banner (top center), kill feed (top right).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local NotificationManager = {}

-- --------------------------------------
-- SCREEN GUI
-- --------------------------------------

local sg = Instance.new("ScreenGui")
sg.Name = "NotificationGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 50
sg.Parent = playerGui

-- --------------------------------------
-- TOAST QUEUE (top right, drop down from top)
-- --------------------------------------

local toastContainer = Instance.new("Frame")
toastContainer.Name = "ToastContainer"
-- Slightly narrower / shorter for better mobile scaling
toastContainer.Size = UDim2.new(0, 260, 1, -20)
toastContainer.Position = UDim2.new(1, -270, 0, 10)
toastContainer.BackgroundTransparency = 1
toastContainer.Parent = sg

local toastLayout = Instance.new("UIListLayout")
toastLayout.SortOrder = Enum.SortOrder.LayoutOrder
toastLayout.VerticalAlignment = Enum.VerticalAlignment.Top
toastLayout.Padding = UDim.new(0, 4)
toastLayout.Parent = toastContainer

local toastOrder = 0
local recentToasts = {} -- dedup: {text = timestamp}

function NotificationManager.Toast(text, color, duration, icon)
	-- Guard: skip empty/nil toasts
	if not text or text == "" or text == "nil" or text == "false" then return nil end

	-- Dedup: ignore identical toast within 1.5 seconds
	local now = tick()
	if recentToasts[text] and (now - recentToasts[text]) < 1.5 then return nil end
	recentToasts[text] = now
	-- Clean old entries periodically
	if toastOrder % 10 == 0 then
		for k, v in pairs(recentToasts) do
			if now - v > 5 then recentToasts[k] = nil end
		end
	end

	toastOrder = toastOrder + 1
	local order = toastOrder
	duration = duration or 4

	local frame = Instance.new("Frame")
	frame.Name = "Toast_" .. order
	frame.LayoutOrder = -order  -- newest at top (lowest LayoutOrder = top when VerticalAlignment.Top)
	frame.Size = UDim2.new(1, 0, 0, 0)
	frame.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
	frame.BackgroundTransparency = 0.5
	frame.BorderSizePixel = 0
	frame.ClipsDescendants = true
	frame.Parent = toastContainer
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)

	-- Color accent bar on left
	local accent = Instance.new("Frame")
	accent.Size = UDim2.new(0, 4, 1, 0)
	accent.BackgroundColor3 = color or Color3.fromRGB(200, 200, 210)
	accent.BorderSizePixel = 0; accent.Parent = frame

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -16, 1, 0)
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = (icon or "") .. (icon and " " or "") .. text
	-- Use bright text: if color is too dark, use white instead
	local textCol = color or Color3.fromRGB(200, 200, 210)
	local brightness = textCol.R * 0.299 + textCol.G * 0.587 + textCol.B * 0.114
	if brightness < 0.35 then
		textCol = Color3.fromRGB(220, 220, 230)
	end
	lbl.TextColor3 = textCol
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.TextTruncate = Enum.TextTruncate.AtEnd
	lbl.Parent = frame

	-- Drop down from top (grow height, fade in) - slightly shorter for mobile
	TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 0.08,
	}):Play()

	-- Auto-dismiss (slide up and fade out)
	task.delay(duration, function()
		if not frame.Parent then return end
		TweenService:Create(frame, TweenInfo.new(0.4), {
			BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0)
		}):Play()
		TweenService:Create(lbl, TweenInfo.new(0.4), {TextTransparency = 1}):Play()
		TweenService:Create(accent, TweenInfo.new(0.4), {BackgroundTransparency = 1}):Play()
		task.delay(0.45, function() if frame.Parent then frame:Destroy() end end)
	end)

	-- Limit visible toasts to 8
	local children = {}
	for _, ch in ipairs(toastContainer:GetChildren()) do
		if ch:IsA("Frame") then table.insert(children, ch) end
	end
	if #children > 8 then
		table.sort(children, function(a, b) return a.LayoutOrder > b.LayoutOrder end)
		for i = 9, #children do children[i]:Destroy() end
	end

	return frame
end

-- --------------------------------------
-- BANNER (top center, one at a time)
-- --------------------------------------

local activeBanner = nil
local bannerQueue = {}
local bannerProcessing = false

local function processBannerQueue()
	if bannerProcessing then return end
	bannerProcessing = true

	while #bannerQueue > 0 do
		local item = table.remove(bannerQueue, 1)
		local text, color, duration = item.text, item.color, item.duration

		-- Dismiss any existing banner
		if activeBanner and activeBanner.Parent then
			activeBanner:Destroy()
		end

		local banner = Instance.new("Frame")
		banner.Name = "Banner"
		banner.Size = UDim2.new(0.55, 0, 0, 48)
		banner.Position = UDim2.new(0.225, 0, 0.1, -55)
		banner.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
		banner.BackgroundTransparency = 0.08
		banner.BorderSizePixel = 0
		banner.Parent = sg
		Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 12)

		local stroke = Instance.new("UIStroke", banner)
		stroke.Color = color or Color3.fromRGB(255, 200, 50)
		stroke.Thickness = 2

		local bannerLbl = Instance.new("TextLabel")
		bannerLbl.Size = UDim2.new(1, -20, 1, 0)
		bannerLbl.Position = UDim2.new(0, 10, 0, 0)
		bannerLbl.BackgroundTransparency = 1
		bannerLbl.Text = text
		bannerLbl.TextColor3 = color or Color3.fromRGB(255, 200, 50)
		bannerLbl.Font = Enum.Font.GothamBlack; bannerLbl.TextSize = 16
		bannerLbl.TextWrapped = true; bannerLbl.Parent = banner

		activeBanner = banner

		-- Slide in
		TweenService:Create(banner, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.225, 0, 0.1, 0)
		}):Play()

		task.wait(duration or 4)

		-- Slide out
		if banner.Parent then
			TweenService:Create(banner, TweenInfo.new(0.4), {
				Position = UDim2.new(0.225, 0, 0.1, -60),
				BackgroundTransparency = 1,
			}):Play()
			TweenService:Create(bannerLbl, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
			TweenService:Create(stroke, TweenInfo.new(0.3), {Transparency = 1}):Play()
			task.wait(0.45)
			if banner.Parent then banner:Destroy() end
		end

		activeBanner = nil
		task.wait(0.3) -- gap between banners
	end

	bannerProcessing = false
end

function NotificationManager.Banner(text, color, duration)
	table.insert(bannerQueue, {text = text, color = color, duration = duration or 4})
	task.spawn(processBannerQueue)
end

-- --------------------------------------
-- KILL FEED (top right, stacking down)
-- --------------------------------------

local killFeedContainer = Instance.new("Frame")
killFeedContainer.Name = "KillFeed"
killFeedContainer.Size = UDim2.new(0, 260, 0, 160)
killFeedContainer.Position = UDim2.new(1, -270, 0, 40)
killFeedContainer.BackgroundTransparency = 1
killFeedContainer.Parent = sg

local killFeedLayout = Instance.new("UIListLayout")
killFeedLayout.SortOrder = Enum.SortOrder.LayoutOrder
killFeedLayout.Padding = UDim.new(0, 2)
killFeedLayout.Parent = killFeedContainer

local killOrder = 0

function NotificationManager.KillFeed(attackerName, defenderName, color)
	killOrder = killOrder + 1
	local order = killOrder

	local entry = Instance.new("TextLabel")
	entry.Name = "Kill_" .. order
	entry.LayoutOrder = order
	entry.Size = UDim2.new(1, 0, 0, 20)
	entry.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
	entry.BackgroundTransparency = 0.25
	entry.BorderSizePixel = 0
	entry.Text = "  " .. attackerName .. " KO'd " .. defenderName
	entry.TextColor3 = color or Color3.fromRGB(200, 200, 210)
	entry.Font = Enum.Font.GothamBold; entry.TextSize = 10
	entry.TextXAlignment = Enum.TextXAlignment.Left
	entry.Parent = killFeedContainer
	Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 5)

	task.delay(5, function()
		if entry.Parent then
			TweenService:Create(entry, TweenInfo.new(0.8), {TextTransparency = 1, BackgroundTransparency = 1}):Play()
			task.delay(0.9, function() if entry.Parent then entry:Destroy() end end)
		end
	end)

	-- Limit feed to 8 items
	local children = {}
	for _, ch in ipairs(killFeedContainer:GetChildren()) do
		if ch:IsA("TextLabel") then table.insert(children, ch) end
	end
	if #children > 8 then
		table.sort(children, function(a, b) return a.LayoutOrder < b.LayoutOrder end)
		for i = 1, #children - 8 do children[i]:Destroy() end
	end
end

-- --------------------------------------
-- FLOATING TEXT (center, ephemeral)
-- --------------------------------------

local floatY = 0

function NotificationManager.FloatingText(text, color)
	floatY = floatY + 35
	if floatY > 140 then floatY = 0 end

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0, 400, 0, 28)
	lbl.Position = UDim2.new(0.5, -200, 0.45, floatY)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = color or Color3.new(1, 1, 1)
	lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 18
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0); lbl.TextStrokeTransparency = 0.4
	lbl.Parent = sg

	TweenService:Create(lbl, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = lbl.Position + UDim2.new(0, 0, 0, -70),
		TextTransparency = 1, TextStrokeTransparency = 1
	}):Play()
	task.delay(2.3, function() if lbl.Parent then lbl:Destroy() end end)
end

-- --------------------------------------
-- REWARD POPUP (center overlay)
-- --------------------------------------

function NotificationManager.RewardPopup(titleText, titleColor, lines, duration)
	-- Guard: skip if no title
	if not titleText or titleText == "" then return nil end
	-- lines = array of {text, color}
	duration = duration or 6

	local overlay = Instance.new("Frame")
	overlay.Size = UDim2.new(1, 0, 1, 0)
	overlay.BackgroundColor3 = Color3.new(0, 0, 0)
	overlay.BackgroundTransparency = 0.6
	overlay.BorderSizePixel = 0; overlay.Parent = sg

	local yOff = 15
	local card = Instance.new("Frame")
	card.BackgroundColor3 = Color3.fromRGB(24, 28, 42)
	card.BorderSizePixel = 0; card.Parent = overlay
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	local stroke = Instance.new("UIStroke", card)
	stroke.Color = titleColor or Color3.fromRGB(255, 200, 50); stroke.Thickness = 2

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -20, 0, 28)
	title.Position = UDim2.new(0, 10, 0, yOff)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = titleColor or Color3.fromRGB(255, 200, 50)
	title.Font = Enum.Font.GothamBlack; title.TextSize = 22; title.Parent = card
	yOff = yOff + 36

	-- Divider
	local div = Instance.new("Frame")
	div.Size = UDim2.new(0.9, 0, 0, 1)
	div.Position = UDim2.new(0.05, 0, 0, yOff)
	div.BackgroundColor3 = Color3.fromRGB(50, 55, 70)
	div.BorderSizePixel = 0; div.Parent = card
	yOff = yOff + 8

	-- Content lines
	for _, line in ipairs(lines or {}) do
		local lineLabel = Instance.new("TextLabel")
		lineLabel.Size = UDim2.new(1, -20, 0, line.size or 18)
		lineLabel.Position = UDim2.new(0, 10, 0, yOff)
		lineLabel.BackgroundTransparency = 1
		lineLabel.Text = line.text
		lineLabel.TextColor3 = line.color or Color3.fromRGB(200, 200, 210)
		lineLabel.Font = line.font or Enum.Font.GothamBold
		lineLabel.TextSize = line.textSize or 14
		lineLabel.TextXAlignment = Enum.TextXAlignment.Left
		lineLabel.Parent = card
		yOff = yOff + (line.size or 18) + 4
	end

	yOff = yOff + 12
	card.Size = UDim2.new(0, 360, 0, yOff)
	card.Position = UDim2.new(0.5, -180, 0.5, -yOff / 2)

	-- Scale-in animation
	local targetSize = card.Size
	local targetPos = card.Position
	card.Size = UDim2.new(0, 0, 0, 0)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	TweenService:Create(card, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = targetSize, Position = targetPos
	}):Play()

	-- Click to dismiss or auto-dismiss
	local dismissed = false
	local function dismiss()
		if dismissed then return end; dismissed = true
		TweenService:Create(overlay, TweenInfo.new(0.5), {BackgroundTransparency = 1}):Play()
		TweenService:Create(card, TweenInfo.new(0.4), {
			Position = targetPos + UDim2.new(0, 0, 0, -30), BackgroundTransparency = 1
		}):Play()
		for _, ch in ipairs(card:GetChildren()) do
			if ch:IsA("TextLabel") then
				TweenService:Create(ch, TweenInfo.new(0.3), {TextTransparency = 1}):Play()
			end
		end
		task.delay(0.55, function() if overlay.Parent then overlay:Destroy() end end)
	end

	task.delay(duration, dismiss)
	local btn = Instance.new("TextButton")
	btn.Size = UDim2.new(1, 0, 1, 0); btn.BackgroundTransparency = 1; btn.Text = ""; btn.Parent = overlay
	btn.MouseButton1Click:Connect(dismiss)

	return overlay
end

print("[NotificationManager] Loaded - Toast, Banner, KillFeed, FloatingText, RewardPopup")
return NotificationManager