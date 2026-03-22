-- PvPBattleClient.lua - StarterPlayerScripts or StarterCharacterScripts (LocalScript)
-- When close to another player, shows "Press E" / "Tap to open [Name]'s profile" (Trade/Battle from there).
-- On mobile the prompt is tap-responsive; on desktop E key or clicking the prompt opens the menu.
-- Listens for PvP reject/start/end and shows toasts.

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local NotificationManager = require(ReplicatedStorage.Modules.NotificationManager)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
local INTERACTION_RANGE = GameConfig.PvPInteractionRange or 20

local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
local PVP_LOG = true
local function pvpLog(msg)
	if PVP_LOG then
		print("[PvP Client] " .. msg)
	end
end

local nearestTarget = nil
local promptGui = nil
local promptLabel = nil

-- FIX #20: Forward-declare onEKey so the tapButton.Activated closure inside
-- updatePrompt() can reference it. Previously onEKey was defined as a
-- `local function` AFTER updatePrompt, making it invisible to earlier code.
-- The closure captured a nil global, so tapping the prompt on mobile did nothing.
local onEKey

local function getRoot(p)
	local char = p and p.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function findNearestOtherPlayer()
	local myRoot = getRoot(player)
	if not myRoot then return nil, math.huge end

	local nearest = nil
	local nearestDist = INTERACTION_RANGE + 1

	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player and other.Character then
			local r = getRoot(other)
			if r then
				local d = (myRoot.Position - r.Position).Magnitude
				if d < nearestDist then
					nearestDist = d
					nearest = other
				end
			end
		end
	end

	return nearest, nearestDist
end

local function updatePrompt()
	local target, dist = findNearestOtherPlayer()
	if target and dist <= INTERACTION_RANGE then
		if nearestTarget ~= target then
			nearestTarget = target
		end
		if not promptGui then
			-- Create prompt (above hotbar area, centered on screen)
			local sg = player:FindFirstChild("PlayerGui") and player.PlayerGui:FindFirstChild("NotificationGUI")
			if not sg then sg = player:WaitForChild("PlayerGui"):FindFirstChild("NotificationGUI") or player.PlayerGui:GetChildren()[1] end
			if not sg then return end

			promptGui = Instance.new("Frame")
			promptGui.Name = "PvPPrompt"
			-- FIX: Use scale-based width so the prompt fits on mobile screens.
			-- Old code used (0,320) width with AnchorPoint(0.5,0) + offset(-160), which
			-- double-offset on mobile, pushing the prompt off the left edge of the screen.
			local isTouch = UserInputService.TouchEnabled
			if isTouch then
				-- Mobile: 90% of screen width, capped at 320px via ClipDescendants
				promptGui.Size = UDim2.new(0.9, 0, 0, 44)
			else
				promptGui.Size = UDim2.new(0, 320, 0, 44)
			end
			promptGui.Position = UDim2.new(0.5, 0, 0.75, 0)
			promptGui.AnchorPoint = Vector2.new(0.5, 0)
			promptGui.BackgroundColor3 = Color3.fromRGB(25, 28, 45)
			promptGui.BackgroundTransparency = 0.2
			promptGui.BorderSizePixel = 0
			promptGui.Parent = sg
			Instance.new("UICorner", promptGui).CornerRadius = UDim.new(0, 10)

			promptLabel = Instance.new("TextLabel")
			promptLabel.Size = UDim2.new(1, -16, 1, -8)
			promptLabel.Position = UDim2.new(0, 8, 0, 4)
			promptLabel.BackgroundTransparency = 1
			promptLabel.Text = ""
			promptLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
			promptLabel.Font = Enum.Font.GothamBold
			promptLabel.TextSize = 16
			promptLabel.TextWrapped = true
			promptLabel.Parent = promptGui

			-- Tap/click button so mobile can open profile (Activated = mouse click or touch tap)
			-- ZIndex ensures the invisible button sits above the label to receive input
			local tapButton = Instance.new("TextButton")
			tapButton.Name = "TapButton"
			tapButton.Size = UDim2.new(1, 0, 1, 0)
			tapButton.Position = UDim2.new(0, 0, 0, 0)
			tapButton.BackgroundTransparency = 1
			tapButton.Text = ""
			tapButton.ZIndex = 2
			tapButton.Parent = promptGui
			tapButton.Activated:Connect(function()
				onEKey()
			end)
		end
		if promptLabel then
			local isTouch = UserInputService.TouchEnabled
			promptLabel.Text = isTouch and ("Tap to open " .. target.Name .. "'s profile") or ("[E] Open " .. target.Name .. "'s profile")
		end
		if promptGui then promptGui.Visible = true end
		return
	end

	nearestTarget = nil
	if promptGui and promptGui.Parent then
		promptGui.Visible = false
	end
end

-- FIX #20: Assignment (not `local function`) so the forward declaration above is used.
onEKey = function()
	if not nearestTarget then return end
	local _, dist = findNearestOtherPlayer()
	if dist > INTERACTION_RANGE then return end
	local openProfileEvt = playerGui:FindFirstChild("OpenPlayerProfile")
	if openProfileEvt and openProfileEvt:IsA("BindableEvent") then
		openProfileEvt:Fire(nearestTarget.UserId)
	end
	if promptGui then promptGui.Visible = false end
	nearestTarget = nil
end

-- Build UI under NotificationGUI if it exists so it draws with other UI
task.defer(function()
	local gui = player:WaitForChild("PlayerGui", 5):FindFirstChild("NotificationGUI")
	if not gui then
		gui = player.PlayerGui:GetChildren()[1]
	end
	if gui then
		updatePrompt()
	end
end)

-- PERFORMANCE: Throttle updatePrompt to ~15 Hz (no need for every-frame updates)
local lastPvPPromptUpdate = 0
local PVP_PROMPT_UPDATE_INTERVAL = 0.066
RunService.Heartbeat:Connect(function()
	if not player.Character then
		nearestTarget = nil
		if promptGui then promptGui.Visible = false end
		return
	end
	local now = tick()
	if now - lastPvPPromptUpdate >= PVP_PROMPT_UPDATE_INTERVAL then
		lastPvPPromptUpdate = now
		updatePrompt()
	end
end)

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.E then
		onEKey()
	end
end)

-- Connect to PvP events (use WaitForChild so we get them even if server creates them after client load)
task.defer(function()
	if not eventsFolder then return end
	local reject = eventsFolder:FindFirstChild("PvPBattleReject") or eventsFolder:WaitForChild("PvPBattleReject", 8)
	if reject then
		reject.OnClientEvent:Connect(function(message)
			pvpLog("received PvPBattleReject: " .. tostring(message))
			NotificationManager.Toast(message or "PvP challenge failed.", Color3.fromRGB(255, 100, 80), 4)
		end)
		pvpLog("listening for PvPBattleReject")
	end

	local startEvt = eventsFolder:FindFirstChild("PvPBattleStart") or eventsFolder:WaitForChild("PvPBattleStart", 8)
	if startEvt then
		startEvt.OnClientEvent:Connect(function(blueName, redName)
			pvpLog("received PvPBattleStart: " .. tostring(blueName) .. " vs " .. tostring(redName))
			NotificationManager.Toast(blueName .. " vs " .. redName .. " - PvP Battle!", Color3.fromRGB(100, 180, 255), 3)
		end)
		pvpLog("listening for PvPBattleStart")
	end

	local noticeEvt = eventsFolder:FindFirstChild("PvPChallengeNotice") or eventsFolder:WaitForChild("PvPChallengeNotice", 5)
	if noticeEvt then
		noticeEvt.OnClientEvent:Connect(function(challengerName)
			pvpLog("received PvPChallengeNotice: " .. tostring(challengerName) .. " is challenging you")
			NotificationManager.Toast(challengerName .. " is challenging you to PvP! Battle starting...", Color3.fromRGB(255, 180, 80), 4)
		end)
		pvpLog("listening for PvPChallengeNotice")
	end

	local endEvt = eventsFolder:FindFirstChild("PvPBattleEnd") or eventsFolder:WaitForChild("PvPBattleEnd", 8)
	if endEvt then
		endEvt.OnClientEvent:Connect(function(winnerName, isMeWinner, winGold, loserGoldLoss)
			pvpLog("received PvPBattleEnd: winner=" .. tostring(winnerName) .. " isMeWinner=" .. tostring(isMeWinner))
			local msg = winnerName .. " wins!"
			local color = isMeWinner and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 100, 80)
			if isMeWinner then
				msg = "You win! +" .. (winGold or 0) .. " gold"
			else
				msg = "You lost. -" .. (loserGoldLoss or 0) .. " gold"
			end
			NotificationManager.Toast(msg, color, 5)
		end)
		pvpLog("listening for PvPBattleEnd")
	end

	-- PvP revive prompt: loser's creature fainted, show instant-revive for coins or Robux (gems)
	local revivePromptEvt = eventsFolder:FindFirstChild("PvPRevivePrompt") or eventsFolder:WaitForChild("PvPRevivePrompt", 5)
	local reviveWithEvt = eventsFolder:FindFirstChild("PvPReviveWith") or eventsFolder:WaitForChild("PvPReviveWith", 3)
	if revivePromptEvt then
		revivePromptEvt.OnClientEvent:Connect(function(creatureName, coinCost, gemCost)
			pvpLog("received PvPRevivePrompt: " .. tostring(creatureName) .. " coins=" .. tostring(coinCost) .. " gems=" .. tostring(gemCost))
			creatureName = creatureName or "Creature"
			coinCost = coinCost or 25
			gemCost = gemCost or 2

			local sg = playerGui:FindFirstChild("NotificationGUI") or playerGui:GetChildren()[1]
			if not sg then return end

			local popup = Instance.new("Frame")
			popup.Name = "PvPRevivePopup"
			popup.Size = UDim2.new(0, 340, 0, 200)
			popup.Position = UDim2.new(0.5, -170, 0.5, -100)
			popup.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
			popup.BackgroundTransparency = 0.05
			popup.BorderSizePixel = 0
			popup.ZIndex = 100
			popup.Parent = sg
			Instance.new("UICorner", popup).CornerRadius = UDim.new(0, 14)
			local stroke = Instance.new("UIStroke", popup)
			stroke.Color = Color3.fromRGB(255, 100, 80)
			stroke.Thickness = 2

			local title = Instance.new("TextLabel")
			title.Size = UDim2.new(1, -24, 0, 28)
			title.Position = UDim2.new(0, 12, 0, 14)
			title.BackgroundTransparency = 1
			title.Text = "Your " .. creatureName .. " fainted!"
			title.TextColor3 = Color3.fromRGB(255, 220, 200)
			title.Font = Enum.Font.GothamBlack
			title.TextSize = 16
			title.TextXAlignment = Enum.TextXAlignment.Left
			title.ZIndex = 101
			title.Parent = popup

			local sub = Instance.new("TextLabel")
			sub.Size = UDim2.new(1, -24, 0, 40)
			sub.Position = UDim2.new(0, 12, 0, 44)
			sub.BackgroundTransparency = 1
			sub.Text = "Instant revive now?"
			sub.TextColor3 = Color3.fromRGB(180, 180, 200)
			sub.Font = Enum.Font.GothamMedium
			sub.TextSize = 13
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextWrapped = true
			sub.ZIndex = 101
			sub.Parent = popup

			local function closePopup()
				if popup and popup.Parent then popup:Destroy() end
			end

			local coinBtn = Instance.new("TextButton")
			coinBtn.Size = UDim2.new(0.5, -18, 0, 44)
			coinBtn.Position = UDim2.new(0, 12, 1, -62)
			coinBtn.BackgroundColor3 = Color3.fromRGB(50, 90, 50)
			coinBtn.Text = "Revive — " .. tostring(coinCost) .. " coins"
			coinBtn.TextColor3 = Color3.fromRGB(255, 220, 100)
			coinBtn.Font = Enum.Font.GothamBold
			coinBtn.TextSize = 13
			coinBtn.ZIndex = 101
			coinBtn.Parent = popup
			Instance.new("UICorner", coinBtn).CornerRadius = UDim.new(0, 10)
			coinBtn.MouseButton1Click:Connect(function()
				if reviveWithEvt then reviveWithEvt:FireServer("coins") end
				closePopup()
			end)

			local gemBtn = Instance.new("TextButton")
			gemBtn.Size = UDim2.new(0.5, -18, 0, 44)
			gemBtn.Position = UDim2.new(0.5, 6, 1, -62)
			gemBtn.BackgroundColor3 = Color3.fromRGB(80, 40, 100)
			gemBtn.Text = "Revive — " .. tostring(gemCost) .. " R$"
			gemBtn.TextColor3 = Color3.fromRGB(255, 200, 255)
			gemBtn.Font = Enum.Font.GothamBold
			gemBtn.TextSize = 13
			gemBtn.ZIndex = 101
			gemBtn.Parent = popup
			Instance.new("UICorner", gemBtn).CornerRadius = UDim.new(0, 10)
			gemBtn.MouseButton1Click:Connect(function()
				if reviveWithEvt then reviveWithEvt:FireServer("gems") end
				closePopup()
			end)
		end)
		pvpLog("listening for PvPRevivePrompt")
	end

	local reviveSuccessEvt = eventsFolder:FindFirstChild("PvPReviveSuccess") or eventsFolder:WaitForChild("PvPReviveSuccess", 3)
	if reviveSuccessEvt then
		reviveSuccessEvt.OnClientEvent:Connect(function()
			NotificationManager.Toast("Creature revived!", Color3.fromRGB(80, 255, 120), 3)
		end)
	end
end)

print("[PvP Client] Loaded - get close to a player, press E or tap the prompt to open their profile (Trade/Battle from there). Set PVP_LOG=false to hide PvP debug logs.")
