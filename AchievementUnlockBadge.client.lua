-- ═══════════════════════════════════════════════════════════════════════════════
-- Last updated: 2026-04-20 16:00
-- AchievementUnlockBadge.client.lua — Top-edge badge: queue achievement unlocks,
-- tap to open the same RewardPopup used by Profile (click-through queue).
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Notify = require(ReplicatedStorage.Modules:WaitForChild("NotificationManager"))
local TopRightBadgeTray = require(ReplicatedStorage.Modules:WaitForChild("TopRightBadgeTray"))

local Events = ReplicatedStorage:WaitForChild("Events", 15)
local achievementUnlocked = Events and Events:FindFirstChild("AchievementUnlocked")

-- Match Profile achievements accent / text colors (NotificationManager RewardPopup).
local ACHIEVE_ACCENT = Color3.fromRGB(255, 215, 90)
local TEXT_MAIN = Color3.fromRGB(240, 240, 245)
local TEXT_SEC = Color3.fromRGB(140, 145, 160)
local BLUE = Color3.fromRGB(60, 160, 255)

local queue = {} -- FIFO { def, ... }
local queuedId = {} -- id -> true (dedupe server double-fires)

local container = Instance.new("Frame")
container.Name = "AchievementUnlockBadge"
container.AnchorPoint = Vector2.new(0, 0)
container.Size = UDim2.fromOffset(48, 48)
container.BackgroundColor3 = Color3.fromRGB(26, 22, 14)
container.BackgroundTransparency = 0.1
container.BorderSizePixel = 0
container.Visible = false
container.LayoutOrder = TopRightBadgeTray.Order.AchievementUnlock
container.Parent = TopRightBadgeTray.GetBadgeRow(player)

Instance.new("UICorner", container).CornerRadius = UDim.new(0, 12)

local stroke = Instance.new("UIStroke")
stroke.Color = ACHIEVE_ACCENT
stroke.Thickness = 2
stroke.Transparency = 0.25
stroke.Parent = container

local btn = Instance.new("TextButton")
btn.Name = "Open"
btn.Size = UDim2.fromScale(1, 1)
btn.BackgroundTransparency = 1
btn.Text = ""
btn.AutoButtonColor = false
btn.Parent = container

local icon = Instance.new("TextLabel")
icon.Name = "Glyph"
icon.AnchorPoint = Vector2.new(0.5, 0.5)
icon.Position = UDim2.fromScale(0.5, 0.5)
icon.Size = UDim2.fromScale(1, 1)
icon.BackgroundTransparency = 1
icon.Font = Enum.Font.GothamBlack
icon.TextScaled = true
icon.TextColor3 = ACHIEVE_ACCENT
icon.Text = "★"
icon.Parent = container

local countBadge = Instance.new("Frame")
countBadge.Name = "Count"
countBadge.AnchorPoint = Vector2.new(1, 0)
countBadge.Position = UDim2.new(1, 6, 0, -6)
countBadge.Size = UDim2.fromOffset(22, 22)
countBadge.BackgroundColor3 = Color3.fromRGB(220, 60, 70)
countBadge.BorderSizePixel = 0
countBadge.Visible = false
countBadge.Parent = container

Instance.new("UICorner", countBadge).CornerRadius = UDim.new(1, 0)

local countLbl = Instance.new("TextLabel")
countLbl.BackgroundTransparency = 1
countLbl.Size = UDim2.fromScale(1, 1)
countLbl.Font = Enum.Font.GothamBold
countLbl.TextSize = 13
countLbl.TextColor3 = Color3.new(1, 1, 1)
countLbl.Text = ""
countLbl.Parent = countBadge

local hint = Instance.new("TextLabel")
hint.Name = "Hint"
hint.AnchorPoint = Vector2.new(0, 0.5)
hint.Position = UDim2.new(1, 10, 0.5, 0)
hint.AutomaticSize = Enum.AutomaticSize.XY
hint.BackgroundColor3 = Color3.fromRGB(14, 15, 22)
hint.BackgroundTransparency = 0.12
hint.BorderSizePixel = 0
hint.Font = Enum.Font.GothamMedium
hint.TextSize = 11
hint.TextColor3 = TEXT_SEC
hint.Text = "Achievement — tap"
hint.Visible = false
hint.Parent = container

Instance.new("UICorner", hint).CornerRadius = UDim.new(0, 6)
local hintPad = Instance.new("UIPadding", hint)
hintPad.PaddingLeft = UDim.new(0, 8)
hintPad.PaddingRight = UDim.new(0, 8)
hintPad.PaddingTop = UDim.new(0, 4)
hintPad.PaddingBottom = UDim.new(0, 4)

local pulseToken = 0

local function refreshQueueVisual()
	local n = #queue
	countBadge.Visible = n > 1
	countLbl.Text = tostring(math.max(n, 0))
	container.Visible = n > 0
	hint.Visible = n > 0
end

local function pulseBadge()
	pulseToken += 1
	local token = pulseToken
	container.Size = UDim2.fromOffset(48, 48)
	local t = TweenService:Create(container, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.fromOffset(54, 54),
	})
	t:Play()
	task.delay(0.14, function()
		if pulseToken ~= token then return end
		TweenService:Create(container, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.fromOffset(48, 48),
		}):Play()
	end)
end

local function buildRewardRows(def)
	local rg = tonumber(def.gems) or 0
	local rx = tonumber(def.xp) or 0
	local rd = type(def.rewardData) == "table" and def.rewardData or nil
	if rg <= 0 and rd then
		rg = tonumber(rd.gems) or 0
	end
	if rx <= 0 and rd then
		rx = tonumber(rd.xp) or 0
	end

	local rows = {
		{ text = def.name or "Badge Earned", color = TEXT_MAIN, font = Enum.Font.GothamBlack, textSize = 16, size = 22 },
		{
			text = def.titleEarned and def.titleEarned ~= "" and ("Title Earned: " .. def.titleEarned) or "New title unlocked",
			color = ACHIEVE_ACCENT,
			font = Enum.Font.GothamBold,
			textSize = 12,
			size = 18,
		},
	}
	if rg > 0 or rx > 0 then
		local parts = {}
		if rg > 0 then
			table.insert(parts, "+" .. tostring(rg) .. " diamonds")
		end
		if rx > 0 then
			table.insert(parts, "+" .. tostring(rx) .. " XP")
		end
		table.insert(rows, { text = table.concat(parts, " · "), color = BLUE, font = Enum.Font.GothamBold, textSize = 12, size = 18 })
	end
	table.insert(rows, { text = def.description or "", color = TEXT_SEC, font = Enum.Font.GothamMedium, textSize = 12, size = 18 })
	return rows
end

local function showNextRewardPopup()
	local def = table.remove(queue, 1)
	if not def then
		refreshQueueVisual()
		return
	end
	refreshQueueVisual()
	local rows = buildRewardRows(def)
	Notify.RewardPopup("ACHIEVEMENT UNLOCKED", ACHIEVE_ACCENT, rows, 5.5)
end

local function enqueueUnlock(def)
	if type(def) ~= "table" or not def.id then return end
	if queuedId[def.id] then return end
	queuedId[def.id] = true
	table.insert(queue, def)
	pulseBadge()
	refreshQueueVisual()
end

btn.MouseButton1Click:Connect(function()
	if #queue == 0 then return end
	showNextRewardPopup()
end)

if achievementUnlocked and achievementUnlocked:IsA("RemoteEvent") then
	achievementUnlocked.OnClientEvent:Connect(enqueueUnlock)
end
