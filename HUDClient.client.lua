-- Last updated: 2026-04-20 16:00
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
local TopRightBadgeTray = require(ReplicatedStorage.Modules:WaitForChild("TopRightBadgeTray"))

-- Build HUD first so top-left UI always appears (even if Events is slow/missing)
-- -- HUD ELEMENTS --
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HUD"; screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 2; screenGui.Parent = playerGui

-- Top HUD: coins, gems, and per-minute in one tight row.
-- Uses AutomaticSize + UIPadding (same pattern as InvStatsBar below) so the
-- frame shrink-wraps text width — no manual re-sizing when numbers change.
local COIN_PAD_H = 12
local COIN_PAD_V = 4

local coinFrame = Instance.new("Frame")
coinFrame.Name = "CoinFrame"
coinFrame.AutomaticSize = Enum.AutomaticSize.XY
coinFrame.Size = UDim2.fromOffset(0, 0)
coinFrame.Position = UDim2.new(0, 12, 0, 10)
coinFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 35)
coinFrame.BackgroundTransparency = 0.25
coinFrame.BorderSizePixel = 0
coinFrame.Parent = screenGui
Instance.new("UICorner", coinFrame).CornerRadius = UDim.new(0, 8)

local coinPad = Instance.new("UIPadding")
coinPad.PaddingLeft = UDim.new(0, COIN_PAD_H)
coinPad.PaddingRight = UDim.new(0, COIN_PAD_H)
coinPad.PaddingTop = UDim.new(0, COIN_PAD_V)
coinPad.PaddingBottom = UDim.new(0, COIN_PAD_V)
coinPad.Parent = coinFrame

-- Single RichText label containing Coins (gold), Gems (cyan), and income/min (green).
-- Parent frame auto-sizes to fit. Updated via setCoinBarText() from refreshData
-- and the CoinsUpdate / GemsUpdate / IncomeReceived remote events.
local coinLabel = Instance.new("TextLabel")
coinLabel.Name = "CoinLabel"
coinLabel.AutomaticSize = Enum.AutomaticSize.XY
coinLabel.Size = UDim2.fromOffset(0, 0)
coinLabel.BackgroundTransparency = 1
coinLabel.RichText = true
-- Initial placeholder; replaced by setCoinBarText() once state is populated.
-- Numbers use formatAbbrev (K/M/B/T) for thousands-and-up compact display.
coinLabel.Text = '<font color="rgb(255,200,50)">Coins: 0</font>  <font color="rgb(90,210,240)">Gems: 0</font>  <font color="rgb(50,220,120)">0/min</font>'
coinLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
coinLabel.Font = Enum.Font.GothamBold
coinLabel.TextSize = 14
coinLabel.TextXAlignment = Enum.TextXAlignment.Left
coinLabel.TextYAlignment = Enum.TextYAlignment.Center
coinLabel.Parent = coinFrame

-- Cached current values so any single remote event (CoinsUpdate/GemsUpdate/
-- IncomeReceived) can update just its own segment without clobbering the others.
local coinBarState = { coins = 0, gems = 0, ipm = 0 }

-- Abbreviate large numbers for HUD display:
--   999 -> "999", 1000 -> "1K", 1450 -> "1.45K", 10550 -> "10.55K",
--   100990 -> "100.99K", 1_000_000 -> "1M", 5_230_000 -> "5.23M", 1e9 -> "1B", 1e12 -> "1T".
-- Uses 2-decimal precision truncated (not rounded) so displayed value never
-- overstates the balance (e.g. 1999 shows "1.99K", not "2K").
local function formatAbbrev(n)
	n = tonumber(n) or 0
	local neg = n < 0
	n = math.abs(n)
	local function trunc2(x)
		return math.floor(x * 100) / 100
	end
	-- Strip trailing zeros after the decimal: "1.00" -> "1", "1.50" -> "1.5", "1.45" -> "1.45"
	local function fmt(x, suffix)
		local v = trunc2(x)
		local s
		if v == math.floor(v) then
			s = tostring(math.floor(v))
		else
			s = string.format("%.2f", v):gsub("0+$", ""):gsub("%.$", "")
		end
		return s .. suffix
	end
	local out
	if n >= 1e12 then      out = fmt(n / 1e12, "T")
	elseif n >= 1e9 then   out = fmt(n / 1e9,  "B")
	elseif n >= 1e6 then   out = fmt(n / 1e6,  "M")
	elseif n >= 1e3 then   out = fmt(n / 1e3,  "K")
	else                    out = tostring(math.floor(n))
	end
	return neg and ("-" .. out) or out
end

local function setCoinBarText()
	coinLabel.Text = string.format(
		'<font color="rgb(255,200,50)">Coins: %s</font>  <font color="rgb(90,210,240)">Gems: %s</font>  <font color="rgb(50,220,120)">%s/min</font>',
		formatAbbrev(coinBarState.coins),
		formatAbbrev(coinBarState.gems),
		formatAbbrev(coinBarState.ipm)
	)
end

-- Back-compat shim: older code paths still assign to coinIncomeLbl.Text.
-- Redirects the write through coinBarState so the combined label stays in sync.
local coinIncomeLbl = setmetatable({}, {
	__newindex = function(_, k, v)
		if k == "Text" then
			local n = tonumber(tostring(v):match("(-?%d+)")) or 0
			coinBarState.ipm = n
			setCoinBarText()
		end
	end,
	__index = function() return "" end,
})

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
dungeonBadge.Parent = TopRightBadgeTray.GetBadgeRow(player)
dungeonBadge.LayoutOrder = TopRightBadgeTray.Order.Dungeon
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
	if not dungeonBadge.Parent then
		return
	end
	local ap = dungeonBadge.AbsolutePosition
	local as = dungeonBadge.AbsoluteSize
	if as.X < 1 or as.Y < 1 then
		return
	end
	dungeonPanel.AnchorPoint = Vector2.new(1, 0)
	dungeonPanel.Position = UDim2.fromOffset(ap.X + as.X, ap.Y + as.Y + 8)
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
	-- Coins / Gems / Income per min — update cached state then refresh the
	-- combined RichText label in one write (avoids mid-frame flicker).
	coinBarState.coins = tonumber(data.coins) or 0
	coinBarState.gems = tonumber(data.gems) or coinBarState.gems or 0
	coinBarState.ipm = computeIncomePerMin(data)
	setCoinBarText()
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
		coinBarState.coins = tonumber(newBalance) or coinBarState.coins
		setCoinBarText()
		Notify.FloatingText("+" .. amount .. " coins", Color3.fromRGB(255, 184, 0))
	end)
end

if CoinsUpdate then
	CoinsUpdate.OnClientEvent:Connect(function(balance)
		coinBarState.coins = tonumber(balance) or 0
		setCoinBarText()
	end)
end

-- GemsUpdate: live gem balance from server (purchase, trade, achievement, etc.)
local GemsUpdate = safeGet("GemsUpdate")
if GemsUpdate then
	GemsUpdate.OnClientEvent:Connect(function(balance)
		coinBarState.gems = tonumber(balance) or 0
		setCoinBarText()
	end)
end

if CaptureSuccess then
	CaptureSuccess.OnClientEvent:Connect(function() task.wait(0.3); refreshData() end)
end

-- CaptureFail toast: CaptureClient also listens and shows a notif + cleans capture UI — avoid duplicate toasts.

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
		-- Break once we've loaded a non-zero balance (RichText now — compare cached state, not label text).
		if coinBarState.coins > 0 or coinBarState.gems > 0 then break end
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
