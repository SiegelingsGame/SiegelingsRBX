-- HUDClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Coin display, inventory count, and event routing through NotificationManager.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

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

local invFrame = Instance.new("Frame")
invFrame.Size = UDim2.new(0, 250, 0, 24)
invFrame.Position = UDim2.new(0, 12, 0, 44)
invFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 35)
invFrame.BackgroundTransparency = 0.25
invFrame.BorderSizePixel = 0; invFrame.Parent = screenGui
Instance.new("UICorner", invFrame).CornerRadius = UDim.new(0, 8)

-- Creature count: smaller text and narrower so it doesn't overlap Income/Defense/Battle
local invLabel = Instance.new("TextLabel")
invLabel.Name = "InvLabel"
invLabel.Size = UDim2.new(0.35, -10, 1, 0)
invLabel.Position = UDim2.new(0, 10, 0, 0)
invLabel.BackgroundTransparency = 1
invLabel.Text = "0/" .. GameConfig.MaxInventorySize
invLabel.TextColor3 = Color3.fromRGB(200, 200, 210)
invLabel.Font = Enum.Font.GothamMedium; invLabel.TextSize = 9
invLabel.TextXAlignment = Enum.TextXAlignment.Left; invLabel.Parent = invFrame

-- Income / Defense / Battle active counts (right side of row)
local invSlotsLbl = Instance.new("TextLabel")
invSlotsLbl.Name = "InvSlotsLabel"
invSlotsLbl.Size = UDim2.new(0.62, -10, 1, 0)
invSlotsLbl.Position = UDim2.new(0.35, 0, 0, 0)
invSlotsLbl.BackgroundTransparency = 1
invSlotsLbl.Text = "Income: 0/6  Defense: 0/6  Battle: 0/5"
invSlotsLbl.TextColor3 = Color3.fromRGB(160, 170, 190)
invSlotsLbl.Font = Enum.Font.GothamMedium; invSlotsLbl.TextSize = 10
invSlotsLbl.TextXAlignment = Enum.TextXAlignment.Right; invSlotsLbl.Parent = invFrame

-- Wait for Events after HUD is visible (no early return so UI never disappears)
local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[HUDClient] Events not ready; HUD visible but live updates may be delayed.") end
local function safeGet(name) return Events and (Events:FindFirstChild(name) or Events:WaitForChild(name, 5)) or nil end

local GetInventory   = safeGet("GetInventory")
local IncomeReceived = safeGet("IncomeReceived")
local CoinsUpdate    = safeGet("CoinsUpdate")
local CaptureSuccess = safeGet("CaptureSuccess")
local RaidStart      = safeGet("RaidStart")
local RaidEnd        = safeGet("RaidEnd")
local CreatureStolen = safeGet("CreatureStolen")
local AIRaidAlert    = safeGet("AIRaidAlert")
local DungeonSpawned = safeGet("DungeonSpawned")
local DungeonDespawned = safeGet("DungeonDespawned")
local CaptureFail    = safeGet("CaptureFail")
local BaseDefenseTargeted = safeGet("BaseDefenseTargeted")
local CreatureFreedByRaid  = safeGet("CreatureFreedByRaid")

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

local BATTLE_TEAM_DISPLAY_MAX = 5  -- show "Battle: X/5" in HUD

local function refreshData()
	local gi = GetInventory or (Events and Events:FindFirstChild("GetInventory"))
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
	invLabel.Text = invCount .. "/" .. invMax
	-- Income points: filled/available, Defense: filled/available, Battle: filled/5
	local inc = data.filledBaseCount or 0
	local incMax = data.incomeMax or 6
	local def = data.filledDefenseCount or 0
	local defMax = data.defenseMax or 6
	local bat = data.battleFilled or 0
	invSlotsLbl.Text = ("Income: %d/%d  Defense: %d/%d  Battle: %d/%d"):format(inc, incMax, def, defMax, bat, BATTLE_TEAM_DISPLAY_MAX)
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

if RaidStart then
	RaidStart.OnClientEvent:Connect(function(name, dur)
		Notify.Toast("RAID: " .. (name or "?"), Color3.fromRGB(255, 60, 40), dur or 5, nil, "raid")
	end)
end

if RaidEnd then
	RaidEnd.OnClientEvent:Connect(function(stolenCount)
		if stolenCount > 0 then
			Notify.Toast("Raid complete ? " .. stolenCount .. " stolen!", Color3.fromRGB(255, 140, 0), 5)
		else
			Notify.Toast("Raid complete ? nothing stolen", Color3.fromRGB(100, 200, 100), 3)
		end
		task.wait(1); refreshData()
	end)
end

if CreatureStolen then
	CreatureStolen.OnClientEvent:Connect(function(creatureName, youStoleIt)
		if youStoleIt then
			Notify.Toast("Stole " .. creatureName .. "!", Color3.fromRGB(0, 229, 195), 4, nil, "raid")
		else
			Notify.Toast(creatureName .. " was stolen!", Color3.fromRGB(255, 80, 80), 4, nil, "raid")
		end
	end)
end

if AIRaidAlert then
	AIRaidAlert.OnClientEvent:Connect(function(targetName, packSize, phase)
		if phase == "start" then
			if targetName == player.Name then
				Notify.Toast("WILD CREATURES RAIDING YOUR BASE! (" .. (packSize or "?") .. " raiders)", Color3.fromRGB(255, 50, 40), 6)
			else
				Notify.Toast(targetName .. "'s base under AI raid!", Color3.fromRGB(255, 140, 60), 4)
			end
		elseif phase == "end" and targetName == player.Name then
			Notify.Toast("Wild raid on your base ended", Color3.fromRGB(180, 180, 200), 3)
			task.wait(0.5); refreshData()
		end
	end)
end

if CreatureFreedByRaid then
	CreatureFreedByRaid.OnClientEvent:Connect(function(creatureName, level)
		local nameStr = creatureName or "A creature"
		local lvlStr = (level and level > 1) and (" Lv." .. level) or ""
		Notify.Banner(nameStr .. lvlStr .. " was freed by wild sieglings! Recapture it!", Color3.fromRGB(255, 80, 50), 5)
	end)
end

if DungeonSpawned then
	DungeonSpawned.OnClientEvent:Connect(function(pos, count, dur)
		Notify.Toast("LEGENDARY DUNGEON appeared! " .. (count or "?") .. " creatures (" .. (dur or "?") .. "s)", Color3.fromRGB(255, 184, 0), 6)
	end)
end

if DungeonDespawned then
	DungeonDespawned.OnClientEvent:Connect(function()
		Notify.Toast("Dungeon vanished...", Color3.fromRGB(150, 120, 80), 3)
	end)
end

if BaseDefenseTargeted then
	BaseDefenseTargeted.OnClientEvent:Connect(function(ownerName)
		Notify.Toast("You are being targeted by " .. (ownerName or "a player") .. "'s base defenses!", Color3.fromRGB(255, 100, 80), 5)
	end)
end

-- Initial load: retry until we get data (in case Events/GetInventory appear late)
task.spawn(function()
	for i = 1, 15 do
		task.wait(1)
		refreshData()
		if coinLabel.Text and coinLabel.Text ~= "Coins: 0" then break end
	end
end)
task.spawn(function()
	while true do
		task.wait(15)
		refreshData()
	end
end)

print("[HUDClient] Initialized - unified notifications")