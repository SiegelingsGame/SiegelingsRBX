-- ArenaRewardsUI.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Shows reward popup after arena battles. Kill feed and banners
-- are now handled by InventoryUIManager + HUDClient via NotificationManager.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local ArenaReward = Events:WaitForChild("ArenaReward", 10)
local GymArenaReward = Events:FindFirstChild("GymArenaReward")
local GymReject = Events:FindFirstChild("GymReject")

-- Colors
local GOLD   = Color3.fromRGB(255, 200, 50)
local RED    = Color3.fromRGB(255, 70, 60)
local GREEN  = Color3.fromRGB(80, 255, 120)
local PURPLE = Color3.fromRGB(180, 80, 255)
local MUTED  = Color3.fromRGB(130, 135, 150)

local function showRewardPopup(data)
	local isGym = data.gym == true
	local isMe = (data.winner == player.Name)
	local isLoser = (data.loser == player.Name)

	if not isMe and not isLoser then
		-- Spectator toast
		if isGym then
			Notify.Toast(data.winner .. " won the Water Gym!", GOLD, 4)
		else
			Notify.Toast(data.winner .. " wins! (Streak: " .. (data.streak or 1) .. ")", GOLD, 4)
		end
		return
	end

	local myReward = isMe and data.winnerReward or data.loserReward
	local titleText = isGym and (isMe and "WATER GYM VICTORY!" or "GYM DEFEATED") or (isMe and "?? VICTORY!" or "DEFEATED")
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
		Notify.Toast(message or "Cannot challenge the Gym.", RED, 4)
	end)
end

print("[ArenaRewardsUI] Loaded - unified notification system")