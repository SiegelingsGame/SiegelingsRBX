-- HUDClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Coin display, inventory count, and event routing through NotificationManager.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

-- Build HUD first so top-left UI always appears (even if Events is slow/missing)
-- -- HUD ELEMENTS --
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HUD"; screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 2; screenGui.Parent = playerGui

-- Top HUD: slightly smaller; coins and per-minute in one tight row (width cut to end at "0/min")
local coinFrame = Instance.new("Frame")
coinFrame.Size = UDim2.new(0, 174, 0, 30)
coinFrame.Position = UDim2.new(0, 12, 0, 10)
coinFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 35)
coinFrame.BackgroundTransparency = 0.25
coinFrame.BorderSizePixel = 0; coinFrame.Parent = screenGui
Instance.new("UICorner", coinFrame).CornerRadius = UDim.new(0, 8)

local coinLabel = Instance.new("TextLabel")
coinLabel.Name = "CoinLabel"
coinLabel.Size = UDim2.new(0, 105, 1, 0)
coinLabel.Position = UDim2.new(0, 8, 0, 0)
coinLabel.BackgroundTransparency = 1; coinLabel.Text = "Coins: 0"
coinLabel.TextColor3 = Color3.fromRGB(255, 200, 50)
coinLabel.Font = Enum.Font.GothamBold; coinLabel.TextSize = 14
coinLabel.TextXAlignment = Enum.TextXAlignment.Left; coinLabel.Parent = coinFrame

-- Per-minute right next to coins (small gap)
local coinIncomeLbl = Instance.new("TextLabel")
coinIncomeLbl.Name = "CoinIncomeLabel"
coinIncomeLbl.Size = UDim2.new(0, 50, 1, 0)
coinIncomeLbl.Position = UDim2.new(0, 116, 0, 0)
coinIncomeLbl.BackgroundTransparency = 1; coinIncomeLbl.Text = "0/min"
coinIncomeLbl.TextColor3 = Color3.fromRGB(50, 220, 120)
coinIncomeLbl.Font = Enum.Font.GothamMedium; coinIncomeLbl.TextSize = 12
coinIncomeLbl.TextXAlignment = Enum.TextXAlignment.Left; coinIncomeLbl.Parent = coinFrame

-- One label; frame shrink-wraps text width + padding (updates when numbers change)
local INV_STATS_PAD_H = 12
local INV_STATS_PAD_V = 4

local invFrame = Instance.new("Frame")
invFrame.Name = "InvStatsBar"
invFrame.AutomaticSize = Enum.AutomaticSize.XY
invFrame.Size = UDim2.fromOffset(0, 0)
invFrame.Position = UDim2.new(0, 12, 0, 44)
invFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 35)
invFrame.BackgroundTransparency = 0.25
invFrame.BorderSizePixel = 0
invFrame.Parent = screenGui
Instance.new("UICorner", invFrame).CornerRadius = UDim.new(0, 8)

local invStatsPad = Instance.new("UIPadding")
invStatsPad.PaddingLeft = UDim.new(0, INV_STATS_PAD_H)
invStatsPad.PaddingRight = UDim.new(0, INV_STATS_PAD_H)
invStatsPad.PaddingTop = UDim.new(0, INV_STATS_PAD_V)
invStatsPad.PaddingBottom = UDim.new(0, INV_STATS_PAD_V)
invStatsPad.Parent = invFrame

local invStatsLbl = Instance.new("TextLabel")
invStatsLbl.Name = "InvStatsLabel"
invStatsLbl.AutomaticSize = Enum.AutomaticSize.XY
invStatsLbl.Size = UDim2.fromOffset(0, 0)
invStatsLbl.BackgroundTransparency = 1
invStatsLbl.Text = "Siegelings: 0/" .. GameConfig.MaxInventorySize .. " | Income: 0/6 | Defense: 0/6 | Battle: 0/5"
invStatsLbl.TextColor3 = Color3.fromRGB(190, 195, 210)
invStatsLbl.Font = Enum.Font.GothamMedium
invStatsLbl.TextSize = 10
invStatsLbl.TextXAlignment = Enum.TextXAlignment.Left
invStatsLbl.TextYAlignment = Enum.TextYAlignment.Center
invStatsLbl.Parent = invFrame

-- Legendary dungeon badge + toggle panel
local DUNGEON_BADGE_WIDTH = 36
local DUNGEON_BADGE_HEIGHT = 42
local DUNGEON_BADGE_GAP = 8
local DUNGEON_BADGE_SLOT = 2 -- arena badge=0, home/base badge=1, dungeon badge=2

local dungeonState = {
	active = false,
	endAt = 0,
	count = 0,
	pos = nil,
}

-- Dedicated ScreenGui for dungeon badge (matches Arena/Base badge layout; same coord system)
local dungeonBadgeGui = Instance.new("ScreenGui")
dungeonBadgeGui.Name = "DungeonCrestBadge"
dungeonBadgeGui.DisplayOrder = 53
dungeonBadgeGui.ResetOnSpawn = false
dungeonBadgeGui.IgnoreGuiInset = true
dungeonBadgeGui.Parent = playerGui

local dungeonBadge = Instance.new("TextButton")
dungeonBadge.Name = "LegendaryDungeonBadge"
dungeonBadge.Size = UDim2.new(0, DUNGEON_BADGE_WIDTH, 0, DUNGEON_BADGE_HEIGHT)
dungeonBadge.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
dungeonBadge.BackgroundTransparency = 0.15
dungeonBadge.BorderSizePixel = 0
dungeonBadge.Text = "\226\152\160"
dungeonBadge.TextColor3 = Color3.fromRGB(255, 184, 0)
dungeonBadge.Font = Enum.Font.GothamBlack
dungeonBadge.TextSize = 16
dungeonBadge.Visible = false
dungeonBadge.Parent = dungeonBadgeGui
Instance.new("UICorner", dungeonBadge).CornerRadius = UDim.new(0, 6)
local dungeonBadgeStroke = Instance.new("UIStroke")
dungeonBadgeStroke.Color = Color3.fromRGB(255, 184, 0)
dungeonBadgeStroke.Thickness = 2
dungeonBadgeStroke.Parent = dungeonBadge

local dungeonShieldPoint = Instance.new("Frame")
dungeonShieldPoint.Name = "ShieldPoint"
dungeonShieldPoint.Size = UDim2.new(0, 16, 0, 10)
dungeonShieldPoint.Position = UDim2.new(0.5, 0, 1, -4)
dungeonShieldPoint.AnchorPoint = Vector2.new(0.5, 0)
dungeonShieldPoint.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
dungeonShieldPoint.BackgroundTransparency = 0.15
dungeonShieldPoint.BorderSizePixel = 0
dungeonShieldPoint.Rotation = 45
dungeonShieldPoint.ZIndex = 1
dungeonShieldPoint.Parent = dungeonBadge

local dungeonPanel = Instance.new("Frame")
dungeonPanel.Name = "LegendaryDungeonPanel"
dungeonPanel.Size = UDim2.new(0, 320, 0, 108)
dungeonPanel.Position = UDim2.new(1, -336, 0, 72)
dungeonPanel.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
dungeonPanel.BackgroundTransparency = 0.1
dungeonPanel.BorderSizePixel = 0
dungeonPanel.Visible = false
dungeonPanel.Parent = dungeonBadgeGui
Instance.new("UICorner", dungeonPanel).CornerRadius = UDim.new(0, 10)
local dungeonPanelStroke = Instance.new("UIStroke")
dungeonPanelStroke.Color = Color3.fromRGB(255, 184, 0)
dungeonPanelStroke.Thickness = 2
dungeonPanelStroke.Parent = dungeonPanel

local dungeonTitle = Instance.new("TextLabel")
dungeonTitle.Size = UDim2.new(1, -14, 0, 24)
dungeonTitle.Position = UDim2.new(0, 7, 0, 6)
dungeonTitle.BackgroundTransparency = 1
dungeonTitle.Text = "LEGENDARY DUNGEON"
dungeonTitle.TextColor3 = Color3.fromRGB(255, 184, 0)
dungeonTitle.Font = Enum.Font.GothamBlack
dungeonTitle.TextSize = 14
dungeonTitle.TextXAlignment = Enum.TextXAlignment.Left
dungeonTitle.Parent = dungeonPanel

local dungeonInfo = Instance.new("TextLabel")
dungeonInfo.Size = UDim2.new(1, -14, 0, 30)
dungeonInfo.Position = UDim2.new(0, 7, 0, 34)
dungeonInfo.BackgroundTransparency = 1
dungeonInfo.Text = "A legendary dungeon is active."
dungeonInfo.TextColor3 = Color3.fromRGB(220, 224, 236)
dungeonInfo.Font = Enum.Font.GothamMedium
dungeonInfo.TextSize = 12
dungeonInfo.TextWrapped = true
dungeonInfo.TextXAlignment = Enum.TextXAlignment.Left
dungeonInfo.TextYAlignment = Enum.TextYAlignment.Top
dungeonInfo.Parent = dungeonPanel

local dungeonTime = Instance.new("TextLabel")
dungeonTime.Size = UDim2.new(1, -14, 0, 20)
dungeonTime.Position = UDim2.new(0, 7, 1, -26)
dungeonTime.BackgroundTransparency = 1
dungeonTime.Text = "Closing in: --:--"
dungeonTime.TextColor3 = Color3.fromRGB(255, 210, 120)
dungeonTime.Font = Enum.Font.GothamBold
dungeonTime.TextSize = 12
dungeonTime.TextXAlignment = Enum.TextXAlignment.Left
dungeonTime.Parent = dungeonPanel

local function positionDungeonBadge()
	local notifGui = playerGui:FindFirstChild("NotificationGUI")
	local tickerBar = notifGui and notifGui:FindFirstChild("TickerBar")
	local arenaBadgeGui = playerGui:FindFirstChild("ArenaCrestBadge")
	local arenaBadgeButton = arenaBadgeGui and arenaBadgeGui:FindFirstChild("CrestButton")
	local baseBadgeGui = playerGui:FindFirstChild("BaseCrestBadge")
	local baseBadgeButton = baseBadgeGui and baseBadgeGui:FindFirstChild("BaseCrestButton")

	-- If arena/base crest badges exist, align to their exact row first.
	if arenaBadgeButton and arenaBadgeButton:IsA("GuiObject") and arenaBadgeButton.Visible then
		local ap = arenaBadgeButton.AbsolutePosition
		local as = arenaBadgeButton.AbsoluteSize
		local xOffset = ap.X + DUNGEON_BADGE_SLOT * (DUNGEON_BADGE_WIDTH + DUNGEON_BADGE_GAP)
		local yCenter = ap.Y + as.Y / 2
		dungeonBadge.Position = UDim2.new(0, xOffset, 0, yCenter)
		dungeonBadge.AnchorPoint = Vector2.new(0, 0.5)
		dungeonPanel.Position = UDim2.new(0, math.max(8, xOffset - 286), 0, ap.Y + as.Y + 8)
		return
	end
	if baseBadgeButton and baseBadgeButton:IsA("GuiObject") and baseBadgeButton.Visible then
		local ap = baseBadgeButton.AbsolutePosition
		local as = baseBadgeButton.AbsoluteSize
		local xOffset = ap.X + (DUNGEON_BADGE_WIDTH + DUNGEON_BADGE_GAP)
		local yCenter = ap.Y + as.Y / 2
		dungeonBadge.Position = UDim2.new(0, xOffset, 0, yCenter)
		dungeonBadge.AnchorPoint = Vector2.new(0, 0.5)
		dungeonPanel.Position = UDim2.new(0, math.max(8, xOffset - 286), 0, ap.Y + as.Y + 8)
		return
	end

	if tickerBar and tickerBar:IsA("GuiObject") then
		local ap = tickerBar.AbsolutePosition
		local as = tickerBar.AbsoluteSize
		local xOffset = ap.X + as.X + DUNGEON_BADGE_GAP + DUNGEON_BADGE_SLOT * (DUNGEON_BADGE_WIDTH + DUNGEON_BADGE_GAP)
		dungeonBadge.Position = UDim2.new(0, xOffset, 0, ap.Y + as.Y / 2)
		dungeonBadge.AnchorPoint = Vector2.new(0, 0.5)
		dungeonPanel.Position = UDim2.new(0, math.max(8, xOffset - 286), 0, ap.Y + as.Y + 8)
	else
		-- Fallback: same slot formula as Arena/Base badges (TickerBar removed)
		local fallbackX = 0.86 + (DUNGEON_BADGE_SLOT * 0.04)
		dungeonBadge.Position = UDim2.new(fallbackX, 0, 0, 18)
		dungeonBadge.AnchorPoint = Vector2.new(0.5, 0)
		dungeonPanel.Position = UDim2.new(1, -336, 0, 72)
	end
end

positionDungeonBadge()
RunService.RenderStepped:Connect(function()
	if dungeonBadge.Visible or dungeonPanel.Visible then
		positionDungeonBadge()
	end
end)

local function formatTimeRemaining(seconds)
	seconds = math.max(0, math.floor(seconds))
	local m = math.floor(seconds / 60)
	local s = seconds % 60
	return string.format("%02d:%02d", m, s)
end

local function refreshDungeonPanelText()
	if not dungeonState.active then
		dungeonInfo.Text = "No active legendary dungeon."
		dungeonTime.Text = "Closing in: --:--"
		return
	end
	local countText = tostring(dungeonState.count or "?")
	dungeonInfo.Text = "Creatures: " .. countText .. "  |  Tap badge to hide/show."
	if dungeonState.endAt and dungeonState.endAt > 0 then
		dungeonTime.Text = "Closing in: " .. formatTimeRemaining(dungeonState.endAt - tick())
	else
		dungeonTime.Text = "Closing in: --:--"
	end
end

dungeonBadge.MouseButton1Click:Connect(function()
	if not dungeonState.active then return end
	dungeonPanel.Visible = not dungeonPanel.Visible
end)

task.spawn(function()
	while true do
		task.wait(1)
		if dungeonState.active then
			refreshDungeonPanelText()
		end
	end
end)

-- Wait for Events after HUD is visible (no early return so UI never disappears)
local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[HUDClient] Events not ready; HUD visible but live updates may be delayed.") end
local function safeGet(name) return Events and (Events:FindFirstChild(name) or Events:WaitForChild(name, 5)) or nil end

local GetInventory   = safeGet("GetInventory")
local IncomeReceived = safeGet("IncomeReceived")
local CoinsUpdate    = safeGet("CoinsUpdate")
local CaptureSuccess = safeGet("CaptureSuccess")
local RaidEnd        = safeGet("RaidEnd")
local AIRaidAlert    = safeGet("AIRaidAlert")
local DungeonSpawned = safeGet("DungeonSpawned")
local DungeonDespawned = safeGet("DungeonDespawned")
local CaptureFail    = safeGet("CaptureFail")
local BaseDefenseTargeted = safeGet("BaseDefenseTargeted")
local ShowNotification = safeGet("ShowNotification")

local function computeIncomePerMin(data)
	if not data or not data.baseSlots or not data.inventory then return 0 end
	local tickSec = GameConfig.IncomeTickSeconds or 10
	local ipt = 0
	local eggUids = {}
	for _, egg in ipairs(data.eggs or {}) do
		if egg and egg.uid then eggUids[tostring(egg.uid)] = true end
	end
	for _, uid in ipairs(data.baseSlots or {}) do
		if not uid or uid == "" then continue end
		if not eggUids[tostring(uid)] then
			for _, e in ipairs(data.inventory) do
				if e.uid and tostring(e.uid) == tostring(uid) then
					local c = CreatureData.GetById(e.id)
					if c then ipt = ipt + (c.baseIncome or 0) end
					break
				end
			end
		end
	end
	return math.floor(ipt * (60 / tickSec))
end

local BATTLE_TEAM_DISPLAY_MAX = 5  -- show "Battle: X/5" in HUDsdfs

local function refreshData()
	local gi = GetInventory or (Events and Events:FindFirstChild("GetInventory"))
	if not gi and Events then
		gi = Events:WaitForChild("GetInventory", 5)
	end
	if not gi then return end
	local ok, data = pcall(function() return gi:InvokeServer() end)
	if not ok or not data then return end
	-- Coins (defensive: data.coins can be nil)
	coinLabel.Text = "Coins: " .. tostring(data.coins or 0)
	-- Income per min
	local ipm = computeIncomePerMin(data)
	coinIncomeLbl.Text = tostring(ipm) .. "/min"
	-- Creature count (defensive: data.inventory can be nil)
	local invCount = data.inventory and #data.inventory or 0
	local invMax = GameConfig.MaxInventorySize or 50
	local inc = data.filledBaseCount or 0
	local incMax = data.incomeMax or 6
	local def = data.filledDefenseCount or 0
	local defMax = data.defenseMax or 6
	local bat = data.battleFilled or 0
	invStatsLbl.Text = ("Siegelings: %d/%d | Income: %d/%d | Defense: %d/%d | Battle: %d/%d"):format(
		invCount,
		invMax,
		inc,
		incMax,
		def,
		defMax,
		bat,
		BATTLE_TEAM_DISPLAY_MAX
	)
end

-- -- EVENTS --

if IncomeReceived then
	IncomeReceived.OnClientEvent:Connect(function(amount, newBalance)
		coinLabel.Text = "Coins: " .. tostring(newBalance)
		Notify.FloatingText("+" .. amount .. " coins", Color3.fromRGB(255, 184, 0))
	end)
end

if CoinsUpdate then
	CoinsUpdate.OnClientEvent:Connect(function(balance) coinLabel.Text = "Coins: " .. tostring(balance) end)
end

if CaptureSuccess then
	CaptureSuccess.OnClientEvent:Connect(function() task.wait(0.3); refreshData() end)
end

if CaptureFail then
	CaptureFail.OnClientEvent:Connect(function(msg)
		Notify.Toast(msg or "Action failed", Color3.fromRGB(255, 80, 60), 4)
	end)
end

-- PvP raid toasts removed; base tab still updates via InventoryUIManager (RaidStart/RaidEnd).
if RaidEnd then
	RaidEnd.OnClientEvent:Connect(function()
		task.wait(1); refreshData()
	end)
end

if AIRaidAlert then
	AIRaidAlert.OnClientEvent:Connect(function(targetName, packSize, phase)
		if phase == "end" and targetName == player.Name then
			task.wait(0.5); refreshData()
		end
	end)
end

if DungeonSpawned then
	DungeonSpawned.OnClientEvent:Connect(function(pos, count, dur)
		if not GameConfig.LegendaryDungeonsEnabled then return end
		dungeonState.active = true
		dungeonState.count = tonumber(count) or 0
		dungeonState.pos = pos
		dungeonState.endAt = tick() + (tonumber(dur) or 0)
		dungeonBadge.Visible = true
		dungeonPanel.Visible = false -- badge appears first; user toggles panel open
		refreshDungeonPanelText()
	end)
end

if DungeonDespawned then
	DungeonDespawned.OnClientEvent:Connect(function()
		dungeonState.active = false
		dungeonState.endAt = 0
		dungeonState.count = 0
		dungeonState.pos = nil
		dungeonPanel.Visible = false
		dungeonBadge.Visible = false
		refreshDungeonPanelText()
	end)
end

if BaseDefenseTargeted then
	BaseDefenseTargeted.OnClientEvent:Connect(function(ownerName)
		Notify.Toast("You are being targeted by " .. (ownerName or "a player") .. "'s base defenses!", Color3.fromRGB(255, 100, 80), 5)
	end)
end

if ShowNotification then
	ShowNotification.OnClientEvent:Connect(function(message, level, category)
		if not message or message == "" then return end
		local duration = 4
		if level == "error" then
			duration = 5
		elseif level == "warning" then
			duration = 4.5
		elseif level == "info" then
			duration = 3.5
		end
		if category == "cooking" then
			duration = math.max(duration, 5.2)
		end
		Notify.Toast(message, nil, duration, nil, category)
	end)
end

-- Must not use OnClientEvent:Wait() alone: if the server fired LoadingCriticalReady before this
-- script subscribed, Wait() never returns and refreshData() never runs (HUD stuck at zeros).
-- Match LaunchScreen: listen + timeout so we always proceed.
local function waitForStartupReady()
	local events = ReplicatedStorage:FindFirstChild("Events") or ReplicatedStorage:WaitForChild("Events", 15)
	if not events then return end
	local criticalReady = events:FindFirstChild("LoadingCriticalReady")
	local worldReady = events:FindFirstChild("LoadingReady")
	if criticalReady then
		local signaled = false
		local conn
		conn = criticalReady.OnClientEvent:Connect(function()
			signaled = true
			if conn then conn:Disconnect() end
		end)
		local deadline = tick() + (GameConfig.LoadingCriticalMaxWait or 18) + 3
		while not signaled and tick() < deadline do
			task.wait(0.1)
		end
		if conn then conn:Disconnect() end
	elseif worldReady then
		local signaled = false
		local conn
		conn = worldReady.OnClientEvent:Connect(function()
			signaled = true
			if conn then conn:Disconnect() end
		end)
		local deadline = tick() + ((GameConfig.LoadingMaxWait or 25) + 8)
		while not signaled and tick() < deadline do
			task.wait(0.15)
		end
		if conn then conn:Disconnect() end
	end
end

-- Initial load + periodic refresh are deferred until startup gate clears.
task.spawn(function()
	waitForStartupReady()
	for i = 1, 10 do
		task.wait(1)
		refreshData()
		if coinLabel.Text and coinLabel.Text ~= "Coins: 0" then break end
	end
end)
task.spawn(function()
	waitForStartupReady()
	task.wait(5)
	while true do
		task.wait(15)
		refreshData()
	end
end)

print("[HUDClient] Initialized - unified notifications")
