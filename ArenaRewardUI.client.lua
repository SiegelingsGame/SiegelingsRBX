-- ArenaRewardsUI.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Shows reward popup after arena battles and gym battle completion screens.
-- Kill feed and banners handled by InventoryUIManager + HUDClient via NotificationManager

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)
local TopRightBadgeTray = require(ReplicatedStorage.Modules:WaitForChild("TopRightBadgeTray"))

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local ArenaReward = Events:WaitForChild("ArenaReward", 10)
local GymArenaReward = Events:FindFirstChild("GymArenaReward")
local GymReject = Events:FindFirstChild("GymReject")
local BaseGymReject = Events:FindFirstChild("BaseGymReject") or Events:WaitForChild("BaseGymReject", 10)
local BaseGymResult = Events:FindFirstChild("BaseGymResult") or Events:WaitForChild("BaseGymResult", 10)
local BaseGymStart  = Events:FindFirstChild("BaseGymStart") or Events:WaitForChild("BaseGymStart", 10)
local BattleStart   = Events:FindFirstChild("BattleStart") or Events:WaitForChild("BattleStart", 10)
local ArenaWatchPrompt = Events:FindFirstChild("ArenaWatchPrompt") or Events:WaitForChild("ArenaWatchPrompt", 10)
local ArenaWatchTeleportRequest = Events:FindFirstChild("ArenaWatchTeleportRequest") or Events:WaitForChild("ArenaWatchTeleportRequest", 10)

local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local playerGui = player:WaitForChild("PlayerGui")

-- Colors
local GOLD   = Color3.fromRGB(255, 200, 50)
local RED    = Color3.fromRGB(255, 70, 60)
local GREEN  = Color3.fromRGB(80, 255, 120)
local PURPLE = Color3.fromRGB(180, 80, 255)
local MUTED  = Color3.fromRGB(130, 135, 150)

-- Arena watch prompt (badge + click-open modal)
local WATCH_BADGE_WIDTH = 36
local WATCH_BADGE_HEIGHT = 42
local watchPrompt = {
	gui = nil,
	badge = nil,
	stroke = nil,
	modal = nil,
	payload = nil,
	pulseConn = nil,
}
local showArenaWatchModal

local function stopWatchBadgePulse()
	if watchPrompt.pulseConn then
		watchPrompt.pulseConn:Disconnect()
		watchPrompt.pulseConn = nil
	end
	if watchPrompt.stroke then
		watchPrompt.stroke.Thickness = 2
		watchPrompt.stroke.Transparency = 0
	end
end

local function hideArenaWatchPrompt()
	stopWatchBadgePulse()
	if watchPrompt.modal and watchPrompt.modal.Parent then
		watchPrompt.modal:Destroy()
	end
	watchPrompt.modal = nil
	if watchPrompt.gui and watchPrompt.gui.Parent then
		watchPrompt.gui:Destroy()
	end
	watchPrompt.gui = nil
	if watchPrompt.badge and watchPrompt.badge.Parent then
		watchPrompt.badge:Destroy()
	end
	watchPrompt.badge = nil
	watchPrompt.stroke = nil
	watchPrompt.payload = nil
end

local function ensureWatchBadge()
	if watchPrompt.gui and watchPrompt.gui.Parent and watchPrompt.badge then
		return
	end
	local payload = watchPrompt.payload
	hideArenaWatchPrompt()
	watchPrompt.payload = payload

	local sg = Instance.new("ScreenGui")
	sg.Name = "ArenaWatchPromptBadge"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 96
	sg.Parent = playerGui

	local badge = Instance.new("TextButton")
	badge.Name = "WatchBadgeButton"
	badge.Size = UDim2.new(0, 0, 0, 0)
	badge.LayoutOrder = TopRightBadgeTray.Order.ArenaWatch
	badge.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	badge.BackgroundTransparency = 0.15
	badge.BorderSizePixel = 0
	badge.Text = "\226\154\148"
	badge.TextColor3 = GOLD
	badge.Font = Enum.Font.GothamBold
	badge.TextSize = 18
	badge.AutoButtonColor = false
	badge.ZIndex = 20
	badge.Parent = TopRightBadgeTray.GetBadgeRow(player)
	Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 6)

	local point = Instance.new("Frame")
	point.Name = "ShieldPoint"
	point.Size = UDim2.new(0, 16, 0, 10)
	point.Position = UDim2.new(0.5, 0, 1, -4)
	point.AnchorPoint = Vector2.new(0.5, 0)
	point.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
	point.BackgroundTransparency = 0.15
	point.BorderSizePixel = 0
	point.Rotation = 45
	point.ZIndex = 1
	point.Parent = badge

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = badge

	watchPrompt.gui = sg
	watchPrompt.badge = badge
	watchPrompt.stroke = stroke
	badge.MouseButton1Click:Connect(showArenaWatchModal)

	local elapsed = 0
	watchPrompt.pulseConn = RunService.RenderStepped:Connect(function(dt)
		if not (watchPrompt.badge and watchPrompt.badge.Parent) then
			stopWatchBadgePulse()
			return
		end
		elapsed += dt
		local t = (math.sin(elapsed * 4 * math.pi) + 1) / 2
		stroke.Thickness = 2 + t * 2
		stroke.Transparency = t * 0.3
	end)

	TweenService:Create(badge, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, WATCH_BADGE_WIDTH, 0, WATCH_BADGE_HEIGHT),
	}):Play()
end

showArenaWatchModal = function()
	if not watchPrompt.payload then return end
	if watchPrompt.modal and watchPrompt.modal.Parent then return end
	if not watchPrompt.gui or not watchPrompt.gui.Parent then return end

	local backdrop = Instance.new("Frame")
	backdrop.Name = "ArenaWatchBackdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.5
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 30
	backdrop.Parent = watchPrompt.gui

	local card = Instance.new("Frame")
	card.Name = "ArenaWatchCard"
	card.Size = UDim2.new(0, 420, 0, 220)
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	card.BorderSizePixel = 0
	card.ZIndex = 31
	card.Parent = backdrop
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 14)

	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = card

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -24, 0, 36)
	title.Position = UDim2.new(0, 12, 0, 12)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 20
	title.TextColor3 = GOLD
	title.Text = "ARENA BATTLE READY"
	title.ZIndex = 32
	title.Parent = card

	local desc = Instance.new("TextLabel")
	desc.Size = UDim2.new(1, -30, 0, 90)
	desc.Position = UDim2.new(0, 15, 0, 56)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.GothamMedium
	desc.TextSize = 14
	desc.TextWrapped = true
	desc.TextColor3 = Color3.fromRGB(220, 224, 236)
	desc.ZIndex = 32
	desc.Text = string.format(
		"%s vs %s begins in %ds.\nTeleport now to watch at the arena surface and earn the combat bonus.",
		tostring(watchPrompt.payload.kingName or "King"),
		tostring(watchPrompt.payload.challengerName or "Challenger"),
		tonumber(watchPrompt.payload.countdown) or 10
	)
	desc.Parent = card

	local tpBtn = Instance.new("TextButton")
	tpBtn.Size = UDim2.new(0.46, 0, 0, 40)
	tpBtn.Position = UDim2.new(0.04, 0, 1, -54)
	tpBtn.BackgroundColor3 = Color3.fromRGB(60, 170, 255)
	tpBtn.TextColor3 = Color3.new(1, 1, 1)
	tpBtn.Font = Enum.Font.GothamBold
	tpBtn.TextSize = 14
	tpBtn.Text = "Teleport to Arena"
	tpBtn.BorderSizePixel = 0
	tpBtn.ZIndex = 32
	tpBtn.Parent = card
	Instance.new("UICorner", tpBtn).CornerRadius = UDim.new(0, 8)

	local dismissBtn = Instance.new("TextButton")
	dismissBtn.Size = UDim2.new(0.46, 0, 0, 40)
	dismissBtn.Position = UDim2.new(0.5, 0, 1, -54)
	dismissBtn.BackgroundColor3 = Color3.fromRGB(55, 58, 74)
	dismissBtn.TextColor3 = Color3.fromRGB(220, 224, 236)
	dismissBtn.Font = Enum.Font.GothamBold
	dismissBtn.TextSize = 14
	dismissBtn.Text = "Dismiss"
	dismissBtn.BorderSizePixel = 0
	dismissBtn.ZIndex = 32
	dismissBtn.Parent = card
	Instance.new("UICorner", dismissBtn).CornerRadius = UDim.new(0, 8)

	tpBtn.MouseButton1Click:Connect(function()
		if ArenaWatchTeleportRequest then
			ArenaWatchTeleportRequest:FireServer()
		end
		hideArenaWatchPrompt()
	end)
	dismissBtn.MouseButton1Click:Connect(hideArenaWatchPrompt)

	watchPrompt.modal = backdrop
end

local function showRewardPopup(data)
	local isGym = data.gym == true
	local isMe = (data.winner == player.Name)
	local isLoser = (data.loser == player.Name)

	if not isMe and not isLoser then
		-- Spectator toast
		if isGym then
			local gymName = data.gymName or "Water Gym"
			Notify.Toast(data.winner .. " won the " .. gymName .. "!", GOLD, 4)
		else
			Notify.Toast(data.winner .. " wins! (Streak: " .. (data.streak or 1) .. ")", GOLD, 4)
		end
		return
	end

	local myReward = isMe and data.winnerReward or data.loserReward
	local gymName = (data.gymName or "Water Gym"):upper()
	local titleText = isGym and (isMe and (gymName .. " VICTORY!") or "GYM DEFEATED") or (isMe and "?? VICTORY!" or "DEFEATED")
	local titleColor = isMe and GOLD or RED

	-- Badge notification summary for participants
	local opponentName = isMe and (data.loser or "Opponent") or (data.winner or "Opponent")
	if myReward and myReward.coins then
		local resultLabel = isMe and "Arena win vs " or "Arena loss vs "
		local toastText = resultLabel .. opponentName .. " (+" .. tostring(myReward.coins) .. " coins)"
		Notify.Toast(toastText, titleColor, 5, nil, "arena")
	else
		local fallbackText = (isMe and "Arena battle vs " or "Arena battle vs ") .. opponentName
		Notify.Toast(fallbackText, titleColor, 4, nil, "arena")
	end

	local lines = {}

	-- Opponent
	local oppText = isMe and ("Defeated: " .. (data.loser or "AI")) or ("Lost to: " .. (data.winner or "AI"))
	table.insert(lines, {text = oppText, color = MUTED, font = Enum.Font.GothamMedium, textSize = 12, size = 16})

	if myReward then
		-- Coins
		table.insert(lines, {text = "+" .. myReward.coins .. " coins", color = GOLD, textSize = 18, size = 24})

		-- Breakdown for winner (arena only; gym has no streak/bounty)
		if isMe and not isGym and myReward.baseCoins then
			local bd = "Base: " .. myReward.baseCoins .. "  |  Bounty: " .. myReward.bountyCoins .. "  |  Streak x" .. string.format("%.1f", myReward.streakMultiplier)
			table.insert(lines, {text = bd, color = MUTED, font = Enum.Font.GothamMedium, textSize = 10, size = 14})
		end

		-- Streak (arena only)
		if isMe and not isGym and data.streak and data.streak > 1 then
			table.insert(lines, {text = "Win Streak: " .. data.streak, color = Color3.fromRGB(255, 140, 40), textSize = 14, size = 18})
		end

		-- Bonus creature
		if isMe and myReward.bonusCreature then
			local dropInfo = CreatureData.GetById(myReward.bonusCreature)
			local rarityColor = dropInfo and CreatureData.Rarities[dropInfo.rarity] and CreatureData.Rarities[dropInfo.rarity].color or PURPLE
			table.insert(lines, {text = "? BONUS DROP!", color = rarityColor, font = Enum.Font.GothamBlack, textSize = 16, size = 20})
			table.insert(lines, {text = (myReward.bonusName or "?") .. " (" .. (myReward.bonusRarity or "?") .. ")", color = rarityColor, textSize = 13, size = 16})
		end

		-- Consolation note
		if not isMe and myReward.consolation then
			table.insert(lines, {text = "(consolation reward)", color = Color3.fromRGB(100, 105, 120), font = Enum.Font.GothamMedium, textSize = 10, size = 14})
		end
	end

	Notify.RewardPopup(titleText, titleColor, lines, 6)
end

if ArenaReward then
	ArenaReward.OnClientEvent:Connect(function(data)
		task.wait(1.5) -- brief delay after battle end banner
		showRewardPopup(data)
	end)
end
if GymArenaReward then
	GymArenaReward.OnClientEvent:Connect(function(data)
		task.wait(1.5)
		showRewardPopup(data)
	end)
end
if GymReject then
	GymReject.OnClientEvent:Connect(function(message)
		local msg = message or "Cannot challenge the Gym."
		Notify.Toast(msg, RED, 5, nil, "arena")
		local lines = { { text = msg, color = MUTED, font = Enum.Font.GothamMedium, textSize = 12, size = 36 } }
		Notify.RewardPopup("Cannot start gym", RED, lines, 5)
	end)
end

if BaseGymReject then
	BaseGymReject.OnClientEvent:Connect(function(title, message, level)
		local popupTitle = (title and title ~= "") and title or "Siegelord Arena unavailable"
		local msg = (message and message ~= "") and message or "You cannot challenge this base gym right now."
		local isError = level == "error" or level == nil
		local titleColor = isError and RED or GOLD
		Notify.Toast(msg, titleColor, 4, nil, "arena")
		local lines = { { text = msg, color = MUTED, font = Enum.Font.GothamMedium, textSize = 12, size = 36 } }
		Notify.RewardPopup(popupTitle, titleColor, lines, 4)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- GYM BATTLE COMPLETION SCREEN (BaseGymResult)
-- Full-screen overlay showing winner, bounty status, and coin rewards.
-- Displayed for both the gym owner and the challenger after a Floor 4 gym battle.
-- ═══════════════════════════════════════════════════════════════════════════════
local function showGymCompletionScreen(data)
	if not data then return end
	local isMe = (data.winner == player.Name)
	local isLoser = (data.loser == player.Name)
	if not isMe and not isLoser then return end -- spectators don't get the full screen

	local myReward = isMe and data.winnerReward or data.loserReward
	local gymName = data.gymName or "Siegelord Arena"

	-- ── Build the overlay UI ────────────────────────────────────────────────
	local sg = Instance.new("ScreenGui")
	sg.Name = "GymCompletionScreen"
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 50
	sg.Parent = playerGui

	-- Dark backdrop
	local backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = sg
	TweenService:Create(backdrop, TweenInfo.new(0.4), { BackgroundTransparency = 0.45 }):Play()

	-- Center card
	local card = Instance.new("Frame")
	card.Size = UDim2.new(0, 380, 0, 0) -- height animated in
	card.Position = UDim2.new(0.5, 0, 0.5, 0)
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
	card.BorderSizePixel = 0
	card.ClipsDescendants = true
	card.Parent = backdrop
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 16)
	local cardStroke = Instance.new("UIStroke", card)
	cardStroke.Thickness = 3
	cardStroke.Color = isMe and GOLD or RED

	-- Title banner
	local titleBanner = Instance.new("Frame")
	titleBanner.Size = UDim2.new(1, 0, 0, 56)
	titleBanner.BackgroundColor3 = isMe and Color3.fromRGB(50, 42, 10) or Color3.fromRGB(50, 15, 15)
	titleBanner.BorderSizePixel = 0
	titleBanner.Parent = card

	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, -20, 1, 0)
	titleLabel.Position = UDim2.new(0, 10, 0, 0)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = isMe and "VICTORY!" or "DEFEATED"
	titleLabel.TextColor3 = isMe and GOLD or RED
	titleLabel.Font = Enum.Font.GothamBlack
	titleLabel.TextSize = 28
	titleLabel.TextXAlignment = Enum.TextXAlignment.Center
	titleLabel.Parent = titleBanner

	-- Gym name subtitle
	local gymLabel = Instance.new("TextLabel")
	gymLabel.Size = UDim2.new(1, -20, 0, 20)
	gymLabel.Position = UDim2.new(0, 10, 0, 58)
	gymLabel.BackgroundTransparency = 1
	gymLabel.Text = gymName
	gymLabel.TextColor3 = MUTED
	gymLabel.Font = Enum.Font.GothamMedium
	gymLabel.TextSize = 13
	gymLabel.Parent = card

	local yPos = 86 -- current vertical offset for stacking lines

	-- ── Opponent line ───────────────────────────────────────────────────────
	local oppText = isMe and ("Defeated: " .. (data.loser or "?")) or ("Lost to: " .. (data.winner or "?"))
	local oppLabel = Instance.new("TextLabel")
	oppLabel.Size = UDim2.new(1, -30, 0, 18)
	oppLabel.Position = UDim2.new(0, 15, 0, yPos)
	oppLabel.BackgroundTransparency = 1
	oppLabel.Text = oppText
	oppLabel.TextColor3 = Color3.fromRGB(180, 185, 200)
	oppLabel.Font = Enum.Font.GothamMedium
	oppLabel.TextSize = 13
	oppLabel.TextXAlignment = Enum.TextXAlignment.Center
	oppLabel.Parent = card
	yPos += 28

	-- ── Score line ──────────────────────────────────────────────────────────
	local scoreText = (data.ownerName or "Owner") .. "  " .. (data.ownerAlive or 0) .. "  vs  " .. (data.challengerAlive or 0) .. "  " .. (data.challengerName or "Challenger")
	local scoreLabel = Instance.new("TextLabel")
	scoreLabel.Size = UDim2.new(1, -30, 0, 18)
	scoreLabel.Position = UDim2.new(0, 15, 0, yPos)
	scoreLabel.BackgroundTransparency = 1
	scoreLabel.Text = scoreText
	scoreLabel.TextColor3 = MUTED
	scoreLabel.Font = Enum.Font.GothamMedium
	scoreLabel.TextSize = 11
	scoreLabel.TextXAlignment = Enum.TextXAlignment.Center
	scoreLabel.Parent = card
	yPos += 28

	-- ── Divider ─────────────────────────────────────────────────────────────
	local div = Instance.new("Frame")
	div.Size = UDim2.new(1, -40, 0, 1)
	div.Position = UDim2.new(0, 20, 0, yPos)
	div.BackgroundColor3 = Color3.fromRGB(60, 65, 80)
	div.BorderSizePixel = 0
	div.Parent = card
	yPos += 12

	-- ── Coins earned ────────────────────────────────────────────────────────
	if myReward and myReward.coins and myReward.coins > 0 then
		local coinsLabel = Instance.new("TextLabel")
		coinsLabel.Size = UDim2.new(1, -30, 0, 28)
		coinsLabel.Position = UDim2.new(0, 15, 0, yPos)
		coinsLabel.BackgroundTransparency = 1
		coinsLabel.Text = "+" .. tostring(myReward.coins) .. " coins"
		coinsLabel.TextColor3 = GOLD
		coinsLabel.Font = Enum.Font.GothamBlack
		coinsLabel.TextSize = 22
		coinsLabel.TextXAlignment = Enum.TextXAlignment.Center
		coinsLabel.Parent = card
		yPos += 32

		-- Breakdown for winner
		if isMe and myReward.baseCoins then
			local parts = {}
			table.insert(parts, "Base: " .. myReward.baseCoins)
			if myReward.bountyCoins and myReward.bountyCoins > 0 then
				table.insert(parts, "Bounty: " .. myReward.bountyCoins)
			end
			if myReward.defensePay and myReward.defensePay > 0 then
				table.insert(parts, "Defense: " .. myReward.defensePay)
			end
			if #parts > 1 then
				local bdLabel = Instance.new("TextLabel")
				bdLabel.Size = UDim2.new(1, -30, 0, 14)
				bdLabel.Position = UDim2.new(0, 15, 0, yPos)
				bdLabel.BackgroundTransparency = 1
				bdLabel.Text = table.concat(parts, "  |  ")
				bdLabel.TextColor3 = MUTED
				bdLabel.Font = Enum.Font.GothamMedium
				bdLabel.TextSize = 10
				bdLabel.TextXAlignment = Enum.TextXAlignment.Center
				bdLabel.Parent = card
				yPos += 18
			end
		end

		-- Consolation note
		if myReward.consolation then
			local consLabel = Instance.new("TextLabel")
			consLabel.Size = UDim2.new(1, -30, 0, 14)
			consLabel.Position = UDim2.new(0, 15, 0, yPos)
			consLabel.BackgroundTransparency = 1
			consLabel.Text = "(consolation reward)"
			consLabel.TextColor3 = Color3.fromRGB(100, 105, 120)
			consLabel.Font = Enum.Font.GothamMedium
			consLabel.TextSize = 10
			consLabel.TextXAlignment = Enum.TextXAlignment.Center
			consLabel.Parent = card
			yPos += 18
		end
	end

	-- ── Divider 2 ───────────────────────────────────────────────────────────
	local div2 = Instance.new("Frame")
	div2.Size = UDim2.new(1, -40, 0, 1)
	div2.Position = UDim2.new(0, 20, 0, yPos)
	div2.BackgroundColor3 = Color3.fromRGB(60, 65, 80)
	div2.BorderSizePixel = 0
	div2.Parent = card
	yPos += 12

	-- ── Bounty section ──────────────────────────────────────────────────────
	-- FIX #21: Bounty section now shows different text/color for winner vs loser.
	-- Loser (owner whose bounty was claimed) sees red warning + motivational text.
	-- Winner (challenger who claimed) sees green success message.
	local bountyWasClaimed = data.bountyPaid and data.bountyPaid > 0
	local bountyHeaderColor, bountyHeaderText
	if bountyWasClaimed then
		if isMe then
			-- Winner: you claimed the bounty
			bountyHeaderColor = GREEN
			bountyHeaderText = "BOUNTY CLAIMED!"
		else
			-- Loser: your bounty was taken
			bountyHeaderColor = RED
			bountyHeaderText = "YOUR BOUNTY WAS CLAIMED!"
		end
	else
		bountyHeaderColor = GOLD
		bountyHeaderText = "Gym Bounty"
	end

	local bountyHeader = Instance.new("TextLabel")
	bountyHeader.Size = UDim2.new(1, -30, 0, 22)
	bountyHeader.Position = UDim2.new(0, 15, 0, yPos)
	bountyHeader.BackgroundTransparency = 1
	bountyHeader.Text = bountyHeaderText
	bountyHeader.TextColor3 = bountyHeaderColor
	bountyHeader.Font = Enum.Font.GothamBlack
	bountyHeader.TextSize = 16
	bountyHeader.TextXAlignment = Enum.TextXAlignment.Center
	bountyHeader.Parent = card
	yPos += 26

	-- Bounty amount / change
	if bountyWasClaimed then
		if isMe then
			-- Winner sees how much they claimed
			local claimLabel = Instance.new("TextLabel")
			claimLabel.Size = UDim2.new(1, -30, 0, 20)
			claimLabel.Position = UDim2.new(0, 15, 0, yPos)
			claimLabel.BackgroundTransparency = 1
			claimLabel.Text = "Claimed " .. tostring(data.bountyPaid) .. " coins from bounty!"
			claimLabel.TextColor3 = GREEN
			claimLabel.Font = Enum.Font.GothamBold
			claimLabel.TextSize = 14
			claimLabel.TextXAlignment = Enum.TextXAlignment.Center
			claimLabel.Parent = card
			yPos += 24
		else
			-- Loser sees the bounty was taken + motivational message
			local lostLabel = Instance.new("TextLabel")
			lostLabel.Size = UDim2.new(1, -30, 0, 20)
			lostLabel.Position = UDim2.new(0, 15, 0, yPos)
			lostLabel.BackgroundTransparency = 1
			lostLabel.Text = data.winner .. " claimed " .. tostring(data.bountyPaid) .. " coins from your bounty!"
			lostLabel.TextColor3 = RED
			lostLabel.Font = Enum.Font.GothamBold
			lostLabel.TextSize = 14
			lostLabel.TextXAlignment = Enum.TextXAlignment.Center
			lostLabel.Parent = card
			yPos += 24

			local tipLabel = Instance.new("TextLabel")
			tipLabel.Size = UDim2.new(1, -30, 0, 16)
			tipLabel.Position = UDim2.new(0, 15, 0, yPos)
			tipLabel.BackgroundTransparency = 1
			tipLabel.Text = "Increase your team's power to build a streak!"
			tipLabel.TextColor3 = Color3.fromRGB(255, 160, 60)
			tipLabel.Font = Enum.Font.GothamMedium
			tipLabel.TextSize = 12
			tipLabel.TextXAlignment = Enum.TextXAlignment.Center
			tipLabel.Parent = card
			yPos += 20
		end

		local resetLabel = Instance.new("TextLabel")
		resetLabel.Size = UDim2.new(1, -30, 0, 14)
		resetLabel.Position = UDim2.new(0, 15, 0, yPos)
		resetLabel.BackgroundTransparency = 1
		resetLabel.Text = "Bounty reset to " .. tostring(data.bountyAfter or 0) .. " coins"
		resetLabel.TextColor3 = MUTED
		resetLabel.Font = Enum.Font.GothamMedium
		resetLabel.TextSize = 10
		resetLabel.TextXAlignment = Enum.TextXAlignment.Center
		resetLabel.Parent = card
		yPos += 18
	else
		-- Owner defended — bounty grew
		local bountyLine = tostring(data.bountyBefore or 0) .. " -> " .. tostring(data.bountyAfter or 0) .. " coins"
		local bountyLabel = Instance.new("TextLabel")
		bountyLabel.Size = UDim2.new(1, -30, 0, 20)
		bountyLabel.Position = UDim2.new(0, 15, 0, yPos)
		bountyLabel.BackgroundTransparency = 1
		bountyLabel.Text = bountyLine
		bountyLabel.TextColor3 = GOLD
		bountyLabel.Font = Enum.Font.GothamBold
		bountyLabel.TextSize = 14
		bountyLabel.TextXAlignment = Enum.TextXAlignment.Center
		bountyLabel.Parent = card
		yPos += 24

		if data.defenseWins and data.defenseWins > 0 then
			local streakLabel = Instance.new("TextLabel")
			streakLabel.Size = UDim2.new(1, -30, 0, 14)
			streakLabel.Position = UDim2.new(0, 15, 0, yPos)
			streakLabel.BackgroundTransparency = 1
			streakLabel.Text = "Defense streak: " .. tostring(data.defenseWins) .. " wins"
			streakLabel.TextColor3 = Color3.fromRGB(255, 160, 60)
			streakLabel.Font = Enum.Font.GothamMedium
			streakLabel.TextSize = 11
			streakLabel.TextXAlignment = Enum.TextXAlignment.Center
			streakLabel.Parent = card
			yPos += 18
		end
	end

	yPos += 12

	-- ── Close button ────────────────────────────────────────────────────────
	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 120, 0, 34)
	closeBtn.Position = UDim2.new(0.5, 0, 0, yPos)
	closeBtn.AnchorPoint = Vector2.new(0.5, 0)
	closeBtn.BackgroundColor3 = isMe and Color3.fromRGB(60, 50, 15) or Color3.fromRGB(50, 20, 20)
	closeBtn.BorderSizePixel = 0
	closeBtn.Text = "Continue"
	closeBtn.TextColor3 = Color3.new(1, 1, 1)
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.Parent = card
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 8)
	yPos += 50

	-- Animate card open
	local totalHeight = yPos
	card.Size = UDim2.new(0, 380, 0, 0)
	TweenService:Create(card, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Size = UDim2.new(0, 380, 0, totalHeight)
	}):Play()

	-- Close handler
	local function closeScreen()
		TweenService:Create(card, TweenInfo.new(0.2), { Size = UDim2.new(0, 380, 0, 0) }):Play()
		TweenService:Create(backdrop, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		task.delay(0.35, function()
			if sg and sg.Parent then sg:Destroy() end
		end)
	end

	closeBtn.MouseButton1Click:Connect(closeScreen)
	-- Auto-close after 10 seconds
	task.delay(10, function()
		if sg and sg.Parent then closeScreen() end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Battle Start Banner — prominent center-screen announcement for Gym + Arena
-- Shows a wide banner with VS text that slides in, holds, then slides out.
-- ═══════════════════════════════════════════════════════════════════════════════

local CYAN   = Color3.fromRGB(80, 200, 255)
local ORANGE = Color3.fromRGB(255, 160, 40)

local function showBattleStartBanner(battleType, name1, name2, role)
	-- battleType: "gym" or "arena"
	-- name1/name2: the two fighters
	-- role: "defense"/"challenge"/"spectator" (gym) or nil (arena)

	local sg = Instance.new("ScreenGui")
	sg.Name = "BattleStartBanner"
	sg.DisplayOrder = 50
	sg.ResetOnSpawn = false
	sg.Parent = playerGui

	-- Full-width banner background
	local banner = Instance.new("Frame")
	banner.Size = UDim2.new(1, 0, 0, 90)
	banner.Position = UDim2.new(0, 0, 0.35, 0)
	banner.AnchorPoint = Vector2.new(0, 0.5)
	banner.BackgroundColor3 = Color3.fromRGB(10, 12, 25)
	banner.BackgroundTransparency = 0.15
	banner.BorderSizePixel = 0
	banner.ClipsDescendants = true
	banner.Parent = sg

	-- Accent stripe (top)
	local topStripe = Instance.new("Frame")
	topStripe.Size = UDim2.new(1, 0, 0, 3)
	topStripe.Position = UDim2.new(0, 0, 0, 0)
	topStripe.BackgroundColor3 = battleType == "gym" and ORANGE or CYAN
	topStripe.BorderSizePixel = 0
	topStripe.Parent = banner

	-- Accent stripe (bottom)
	local botStripe = Instance.new("Frame")
	botStripe.Size = UDim2.new(1, 0, 0, 3)
	botStripe.Position = UDim2.new(0, 0, 1, -3)
	botStripe.BackgroundColor3 = battleType == "gym" and ORANGE or CYAN
	botStripe.BorderSizePixel = 0
	botStripe.Parent = banner

	-- Title line ("ARENA BATTLE" or "GYM CHALLENGE")
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Size = UDim2.new(1, 0, 0, 24)
	titleLabel.Position = UDim2.new(0, 0, 0, 8)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 16
	titleLabel.TextColor3 = battleType == "gym" and ORANGE or CYAN
	titleLabel.Parent = banner

	if battleType == "gym" then
		if role == "defense" then
			titleLabel.Text = "SIEGELORD GYM — DEFENDING!"
		elseif role == "challenge" then
			titleLabel.Text = "SIEGELORD GYM — CHALLENGING!"
		else
			titleLabel.Text = "SIEGELORD GYM BATTLE"
		end
	else
		titleLabel.Text = "ARENA BATTLE STARTING"
	end

	-- VS line:  "Name1  ⚔  Name2"
	local vsLabel = Instance.new("TextLabel")
	vsLabel.Size = UDim2.new(1, 0, 0, 36)
	vsLabel.Position = UDim2.new(0, 0, 0, 36)
	vsLabel.BackgroundTransparency = 1
	vsLabel.Font = Enum.Font.GothamBlack
	vsLabel.TextSize = 28
	vsLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	vsLabel.RichText = true
	vsLabel.Parent = banner

	local accentHex = battleType == "gym" and "ffa028" or "50c8ff"
	vsLabel.Text = string.format(
		'<font color="#%s">%s</font>  <font color="#ff4444">VS</font>  <font color="#%s">%s</font>',
		accentHex, tostring(name1), accentHex, tostring(name2)
	)

	-- Slide-in animation: start off-screen left, slide to center
	banner.Position = UDim2.new(-1, 0, 0.35, 0)
	local slideIn = TweenService:Create(banner, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0.35, 0)
	})
	slideIn:Play()

	-- Hold for 2.5s, then slide out right and destroy
	task.delay(2.5, function()
		local slideOut = TweenService:Create(banner, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			Position = UDim2.new(1, 0, 0.35, 0)
		})
		slideOut:Play()
		task.delay(0.35, function()
			if sg and sg.Parent then sg:Destroy() end
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Event connections — Battle start banners
-- ═══════════════════════════════════════════════════════════════════════════════

-- Gym battle start: fired to owner + challenger with role info
if BaseGymStart then
	BaseGymStart.OnClientEvent:Connect(function(ownerName, challengerName, role)
		showBattleStartBanner("gym", ownerName, challengerName, role)
	end)
end

-- Arena battle start: fired to ALL players (spectators + participants)
if BattleStart then
	BattleStart.OnClientEvent:Connect(function(kingName, challName)
		hideArenaWatchPrompt()
		showBattleStartBanner("arena", kingName, challName)
	end)
end

if ArenaWatchPrompt then
	ArenaWatchPrompt.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		watchPrompt.payload = payload
		ensureWatchBadge()
		task.delay((tonumber(payload.countdown) or 10) + 8, function()
			if watchPrompt.payload == payload then
				hideArenaWatchPrompt()
			end
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Event connections — Battle completion screens
-- ═══════════════════════════════════════════════════════════════════════════════

if BaseGymResult then
	BaseGymResult.OnClientEvent:Connect(function(data)
		task.wait(1.5) -- brief delay for battle end visual
		showGymCompletionScreen(data)
	end)
end

print("[ArenaRewardsUI] Loaded - unified notification system")
