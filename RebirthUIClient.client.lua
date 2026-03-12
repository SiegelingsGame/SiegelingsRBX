-- RebirthUIClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Pilot Rebirth UI: requirements, what you lose/keep, double verification.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then warn("[RebirthUI] Events missing") return end

local getRebirthInfo = Events:FindFirstChild("GetRebirthInfo")
local requestRebirth = Events:FindFirstChild("RequestRebirth")
local rebirthSuccess = Events:FindFirstChild("RebirthSuccess")
local rebirthFailed = Events:FindFirstChild("RebirthFailed")

-- Colors
local C = {
	bg = Color3.fromRGB(14, 15, 22),
	bgLight = Color3.fromRGB(22, 24, 35),
	card = Color3.fromRGB(28, 30, 42),
	accent = Color3.fromRGB(200, 180, 255),
	rebirthAccent = Color3.fromRGB(255, 180, 80),
	text = Color3.fromRGB(240, 240, 245),
	textSec = Color3.fromRGB(140, 145, 160),
	textMut = Color3.fromRGB(80, 85, 100),
	gold = Color3.fromRGB(255, 200, 50),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(220, 60, 70),
	blue = Color3.fromRGB(60, 160, 255),
	divider = Color3.fromRGB(40, 42, 55),
	rarityCommon = Color3.fromRGB(180, 180, 180),
	rarityUncommon = Color3.fromRGB(75, 200, 75),
	rarityRare = Color3.fromRGB(60, 130, 255),
	rarityEpic = Color3.fromRGB(180, 80, 255),
	rarityLegendary = Color3.fromRGB(255, 184, 0),
}

local RARITY_COLORS = {
	Common = C.rarityCommon,
	Uncommon = C.rarityUncommon,
	Rare = C.rarityRare,
	Epic = C.rarityEpic,
	Legendary = C.rarityLegendary,
}

-- Screen GUI
local sg = Instance.new("ScreenGui")
sg.Name = "RebirthUI"
sg.ResetOnSpawn = false
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.DisplayOrder = 16
sg.Parent = playerGui

-- Main panel
local main = Instance.new("Frame")
main.Size = UDim2.new(0, 440, 0, 560)
main.Position = UDim2.new(0.5, -220, 0.5, -280)
main.BackgroundColor3 = C.bg
main.BorderSizePixel = 0
main.Visible = false
main.Active = true
main.Draggable = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 16)
Instance.new("UIStroke", main).Color = C.divider

-- Header
local hdr = Instance.new("Frame")
hdr.Size = UDim2.new(1, 0, 0, 48)
hdr.BackgroundColor3 = C.bgLight
hdr.BorderSizePixel = 0
hdr.Parent = main
Instance.new("UICorner", hdr).CornerRadius = UDim.new(0, 16)
local hdrFix = Instance.new("Frame")
hdrFix.Size = UDim2.new(1, 0, 0, 14)
hdrFix.Position = UDim2.new(0, 0, 1, -14)
hdrFix.BackgroundColor3 = C.bgLight
hdrFix.BorderSizePixel = 0
hdrFix.Parent = hdr

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -50, 1, 0)
title.Position = UDim2.new(0, 18, 0, 0)
title.BackgroundTransparency = 1
title.Text = "PILOT REBIRTH"
title.TextColor3 = C.rebirthAccent
title.Font = Enum.Font.GothamBlack
title.TextSize = 17
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = hdr

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30)
closeBtn.Position = UDim2.new(1, -38, 0, 9)
closeBtn.BackgroundColor3 = C.card
closeBtn.Text = "X"
closeBtn.TextColor3 = C.textSec
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 13
closeBtn.BorderSizePixel = 0
closeBtn.Parent = hdr
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)

-- Content scroll
local content = Instance.new("ScrollingFrame")
content.Size = UDim2.new(1, -28, 1, -120)
content.Position = UDim2.new(0, 14, 0, 56)
content.BackgroundTransparency = 1
content.BorderSizePixel = 0
content.ScrollBarThickness = 4
content.ScrollBarImageColor3 = C.divider
content.ScrollingDirection = Enum.ScrollingDirection.Y
content.AutomaticCanvasSize = Enum.AutomaticSize.Y
content.CanvasSize = UDim2.new(0, 0, 0, 0)
content.Parent = main

local layout = Instance.new("UIListLayout")
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Padding = UDim.new(0, 8)
layout.Parent = content

-- Confirmation overlay (double verification)
local overlay = Instance.new("Frame")
overlay.Size = UDim2.new(1, 0, 1, 0)
overlay.Position = UDim2.new(0, 0, 0, 0)
overlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
overlay.BackgroundTransparency = 0.5
overlay.Visible = false
overlay.Parent = main

local confirmBox = Instance.new("Frame")
confirmBox.Size = UDim2.new(0, 320, 0, 200)
confirmBox.Position = UDim2.new(0.5, -160, 0.5, -100)
confirmBox.BackgroundColor3 = C.card
confirmBox.BorderSizePixel = 0
confirmBox.Parent = overlay
Instance.new("UICorner", confirmBox).CornerRadius = UDim.new(0, 12)
Instance.new("UIStroke", confirmBox).Color = C.red

local confirmTitle = Instance.new("TextLabel")
confirmTitle.Size = UDim2.new(1, -24, 0, 32)
confirmTitle.Position = UDim2.new(0, 12, 0, 8)
confirmTitle.BackgroundTransparency = 1
confirmTitle.Text = "FINAL CONFIRMATION"
confirmTitle.TextColor3 = C.red
confirmTitle.Font = Enum.Font.GothamBlack
confirmTitle.TextSize = 14
confirmTitle.TextXAlignment = Enum.TextXAlignment.Left
confirmTitle.Parent = confirmBox

local confirmBody = Instance.new("TextLabel")
confirmBody.Size = UDim2.new(1, -24, 0, 70)
confirmBody.Position = UDim2.new(0, 12, 0, 42)
confirmBody.BackgroundTransparency = 1
confirmBody.Text = "You will lose ALL creatures except your equipped favorite. Base and Battle Team will be cleared. This cannot be undone."
confirmBody.TextColor3 = C.text
confirmBody.Font = Enum.Font.GothamMedium
confirmBody.TextSize = 11
confirmBody.TextWrapped = true
confirmBody.TextXAlignment = Enum.TextXAlignment.Left
confirmBody.TextYAlignment = Enum.TextYAlignment.Top
confirmBody.Parent = confirmBox

local confirmYesBtn = Instance.new("TextButton")
confirmYesBtn.Size = UDim2.new(0, 120, 0, 36)
confirmYesBtn.Position = UDim2.new(0.5, -130, 1, -52)
confirmYesBtn.BackgroundColor3 = C.green
confirmYesBtn.Text = "YES, REBIRTH"
confirmYesBtn.TextColor3 = Color3.new(1, 1, 1)
confirmYesBtn.Font = Enum.Font.GothamBold
confirmYesBtn.TextSize = 12
confirmYesBtn.BorderSizePixel = 0
confirmYesBtn.Parent = confirmBox
Instance.new("UICorner", confirmYesBtn).CornerRadius = UDim.new(0, 8)

local confirmNoBtn = Instance.new("TextButton")
confirmNoBtn.Size = UDim2.new(0, 120, 0, 36)
confirmNoBtn.Position = UDim2.new(0.5, 10, 1, -52)
confirmNoBtn.BackgroundColor3 = C.divider
confirmNoBtn.Text = "CANCEL"
confirmNoBtn.TextColor3 = C.textSec
confirmNoBtn.Font = Enum.Font.GothamBold
confirmNoBtn.TextSize = 12
confirmNoBtn.BorderSizePixel = 0
confirmNoBtn.Parent = confirmBox
Instance.new("UICorner", confirmNoBtn).CornerRadius = UDim.new(0, 8)

-- Bottom bar with Rebirth button
local bottomBar = Instance.new("Frame")
bottomBar.Size = UDim2.new(1, -28, 0, 52)
bottomBar.Position = UDim2.new(0, 14, 1, -58)
bottomBar.BackgroundTransparency = 1
bottomBar.Parent = main

local rebirthBtn = Instance.new("TextButton")
rebirthBtn.Size = UDim2.new(1, 0, 0, 40)
rebirthBtn.Position = UDim2.new(0, 0, 0, 0)
rebirthBtn.BackgroundColor3 = C.rebirthAccent
rebirthBtn.Text = "REBIRTH"
rebirthBtn.TextColor3 = Color3.new(0.2, 0.15, 0.1)
rebirthBtn.Font = Enum.Font.GothamBlack
rebirthBtn.TextSize = 14
rebirthBtn.BorderSizePixel = 0
rebirthBtn.Parent = bottomBar
Instance.new("UICorner", rebirthBtn).CornerRadius = UDim.new(0, 10)

-- Helpers
local function mkSection(text, order)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 0, 22)
	lbl.BackgroundTransparency = 1
	lbl.Text = text
	lbl.TextColor3 = C.accent
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.LayoutOrder = order
	lbl.Parent = content
	return lbl
end

local function mkRow(label, value, color, order)
	local row = Instance.new("Frame")
	row.Size = UDim2.new(1, 0, 0, 24)
	row.BackgroundColor3 = C.card
	row.BorderSizePixel = 0
	row.LayoutOrder = order
	row.Parent = content
	Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(0.6, 0, 1, 0)
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = label
	lbl.TextColor3 = C.textSec
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 11
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = row
	local val = Instance.new("TextLabel")
	val.Size = UDim2.new(0.4, -12, 1, 0)
	val.Position = UDim2.new(0.6, 0, 0, 0)
	val.BackgroundTransparency = 1
	val.Text = tostring(value)
	val.TextColor3 = color or C.text
	val.Font = Enum.Font.GothamBold
	val.TextSize = 12
	val.TextXAlignment = Enum.TextXAlignment.Right
	val.Parent = row
	return row
end

local currentData = nil

local function refreshUI()
	for _, ch in ipairs(content:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	if not getRebirthInfo or not getRebirthInfo:IsA("RemoteFunction") then
		mkSection("Could not load rebirth data", 0)
		return
	end

	local ok, data = pcall(function() return getRebirthInfo:InvokeServer() end)
	if not ok or not data then
		mkSection("Loading...", 0)
		return
	end
	currentData = data

	local rebirthLevel = data.rebirthLevel or 0
	local nextReq = data.nextRequirements
	local canRebirth = data.canRebirth
	local errMsg = data.errorMessage or ""
	local counts = data.creatureCountsByRarity or {}
	local teamProgress = data.teamProgress or {}
	local keepFavorite = data.keepFavorite
	local loseCount = data.loseCreaturesCount or 0
	local bonuses = data.bonuses or {}
	local nextBonuses = data.nextBonuses or {}

	-- Current rebirth level
	mkSection("CURRENT REBIRTH", 0)
	mkRow("Rebirth Level", rebirthLevel, C.rebirthAccent, 1)
	if bonuses.passiveGold and bonuses.passiveGold > 0 then
		mkRow("Passive gold/tick", "+" .. tostring(bonuses.passiveGold), C.gold, 2)
	end
	if bonuses.healthBonus and bonuses.healthBonus > 0 then
		mkRow("Bonus max health", "+" .. tostring(bonuses.healthBonus), C.green, 3)
	end
	if bonuses.damageMultiplier and bonuses.damageMultiplier > 1 then
		mkRow("World damage", string.format("%.0f%%", (bonuses.damageMultiplier - 1) * 100), C.blue, 4)
	end

	-- Next rebirth requirements (team of 5 at max level, or legacy rarity counts)
	mkSection("REQUIREMENTS FOR NEXT REBIRTH", 10)
	if not nextReq then
		mkRow("Status", "Max rebirth level reached", C.textMut, 11)
	else
		mkRow("Gold needed", (nextReq.gold or 0) .. " (you have " .. tostring((data.coins or 0)) .. ")", (data.coins or 0) >= (nextReq.gold or 0) and C.green or C.red, 11)
		local reqOrder = 12
		if nextReq.team and type(nextReq.team) == "table" and #nextReq.team > 0 and #teamProgress > 0 then
			for i, slot in ipairs(teamProgress) do
				local status = slot.haveAtMaxLevel and "✓ Max" or "✗ Need max"
				local color = slot.haveAtMaxLevel and C.green or C.red
				mkRow("Slot " .. i .. ": " .. (slot.displayName or slot.creatureId), status, color, reqOrder)
				reqOrder = reqOrder + 1
			end
		else
			for _, rarity in ipairs({"Common", "Uncommon", "Rare", "Epic", "Legendary"}) do
				local need = (nextReq.creatures or {})[rarity]
				if need and need > 0 then
					local have = counts[rarity] or 0
					local met = have >= need
					mkRow(rarity .. " creatures", have .. " / " .. need, met and (RARITY_COLORS[rarity] or C.text) or C.red, reqOrder)
					reqOrder = reqOrder + 1
				end
			end
		end
	end

	-- What you KEEP
	mkSection("YOU KEEP", 20)
	if keepFavorite then
		local rc = RARITY_COLORS[keepFavorite.rarity] or C.text
		mkRow("Favorite (equipped)", keepFavorite.name or "?", rc, 21)
	else
		mkRow("Favorite (equipped)", "None", C.textMut, 21)
	end

	-- What you LOSE
	mkSection("YOU LOSE", 30)
	mkRow("Creatures removed", loseCount, C.red, 31)
	if (data.loseBaseCount or 0) > 0 then
		mkRow("From base (income)", data.loseBaseCount, C.textSec, 32)
	end
	if (data.loseDefenseCount or 0) > 0 then
		mkRow("From base (defense)", data.loseDefenseCount, C.textSec, 33)
	end
	if (data.loseBattleCount or 0) > 0 then
		mkRow("From battle team", data.loseBattleCount, C.textSec, 34)
	end

	-- Rewards after next rebirth
	if nextBonuses and nextBonuses.passiveGold then
		mkSection("REWARDS AFTER REBIRTH", 40)
		mkRow("Passive gold/tick", "+" .. tostring(nextBonuses.passiveGold), C.gold, 41)
		if nextBonuses.healthBonus and nextBonuses.healthBonus > 0 then
			mkRow("Bonus max health", "+" .. tostring(nextBonuses.healthBonus), C.green, 42)
		end
		if nextBonuses.damageMultiplier and nextBonuses.damageMultiplier > 1 then
			mkRow("World damage", string.format("%.0f%%", (nextBonuses.damageMultiplier - 1) * 100), C.blue, 43)
		end
	end

	-- Button state
	rebirthBtn.Visible = nextReq ~= nil
	if rebirthBtn.Visible then
		rebirthBtn.BackgroundColor3 = canRebirth and C.rebirthAccent or C.divider
		rebirthBtn.Text = canRebirth and "REBIRTH" or "REBIRTH (requirements not met)"
		rebirthBtn.TextColor3 = canRebirth and Color3.new(0.2, 0.15, 0.1) or C.textMut
	end
end

-- Show/hide
local function openUI()
	main.Visible = true
	overlay.Visible = false
	refreshUI()
end

local function closeUI()
	main.Visible = false
	overlay.Visible = false
end

closeBtn.MouseButton1Click:Connect(closeUI)

rebirthBtn.MouseButton1Click:Connect(function()
	if not currentData then return end
	if not currentData.canRebirth then
		Notify.Toast(currentData.errorMessage or "Requirements not met", C.red, 3)
		return
	end
	-- First step: show confirmation overlay
	overlay.Visible = true
end)

confirmNoBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
end)

confirmYesBtn.MouseButton1Click:Connect(function()
	overlay.Visible = false
	if not requestRebirth or not requestRebirth:IsA("RemoteEvent") then return end
	requestRebirth:FireServer()
	closeUI()
end)

-- Events
if rebirthSuccess then
	rebirthSuccess.OnClientEvent:Connect(function(newLevel, bonuses)
		Notify.Toast("Rebirth " .. tostring(newLevel) .. "! Passive gold, damage & health increased.", C.green, 4)
	end)
end
if rebirthFailed then
	rebirthFailed.OnClientEvent:Connect(function(msg)
		Notify.Toast(msg or "Rebirth failed", C.red, 3)
	end)
end

-- Toggle from HUD (reconnect when HUDToggleMenu is re-added, e.g. after respawn)
local function getHUDToggle()
	local evt = playerGui:FindFirstChild("HUDToggleMenu")
	if not evt or not evt:IsA("BindableEvent") then
		evt = Instance.new("BindableEvent")
		evt.Name = "HUDToggleMenu"
		evt.Parent = playerGui
	end
	return evt
end
local function onHUDToggle(menuName)
	if menuName == "RebirthUI" then
		if main.Visible then closeUI() else openUI() end
	end
end
getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then child.Event:Connect(onHUDToggle) end
end)

-- Keyboard Z for Rebirth (fallback; HUDButtonBar also fires HUDToggleMenu)
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.Z then
		if main.Visible then closeUI() else openUI() end
	end
end)

