-- FriendsListClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Press J to manage base friends list (who can pass through laser doors).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")


local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local addFriend = Events:WaitForChild("AddBaseFriend", 8)
local removeFriend = Events:WaitForChild("RemoveBaseFriend", 8)
local getFriendsList = Events:WaitForChild("GetFriendsList", 8)

-- Trading
local getPublicProfile = Events:WaitForChild("GetPublicProfile", 8)
local tradeRequest = Events:WaitForChild("TradeRequest", 8)
local tradeInvite = Events:WaitForChild("TradeInvite", 8)
local tradeResponse = Events:WaitForChild("TradeResponse", 8)
local tradeUpdateOffer = Events:WaitForChild("TradeUpdateOffer", 8)
local tradeAccept = Events:WaitForChild("TradeAccept", 8)
local tradeCancel = Events:WaitForChild("TradeCancel", 8)
local tradeState = Events:WaitForChild("TradeState", 8)
local getInventory = Events:WaitForChild("GetInventory", 8)
-- PvP (RequestPvPBattle = challenge from profile or when near; server starts battle if in range or fires PvPBattleReject)
local requestPvPBattle = Events:FindFirstChild("RequestPvPBattle") or Events:WaitForChild("RequestPvPBattle", 8)
local pvpChallengeInvite = Events:FindFirstChild("PvPChallengeInvite") or Events:WaitForChild("PvPChallengeInvite", 5)
local pvpAcceptChallenge = Events:FindFirstChild("PvPAcceptChallenge")
local pvpDeclineChallenge = Events:FindFirstChild("PvPDeclineChallenge")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)

-- ── COLORS ──
local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(22, 26, 38),
	blue = Color3.fromRGB(60, 140, 255),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(255, 70, 60),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
	favorite = Color3.fromRGB(255, 200, 50),  -- match InventoryUIManager favorite highlight
}

-- ScreenGui for Friends / Base Allow panel only (profile has its own so they move separately)
local sg = Instance.new("ScreenGui")
sg.Name = "FriendsListGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 200
sg.ZIndexBehavior = Enum.ZIndexBehavior.Global
sg.Parent = playerGui

-- ========= PROFILE POPUP in its own ScreenGui (independent movement from base allow list) =========
local profileSg = Instance.new("ScreenGui")
profileSg.Name = "ProfilePopupGUI"
profileSg.ResetOnSpawn = false
profileSg.DisplayOrder = 200
profileSg.ZIndexBehavior = Enum.ZIndexBehavior.Global
profileSg.Parent = playerGui

local profilePopup = Instance.new("Frame")
profilePopup.Size = UDim2.new(0, 360, 0, 440)
profilePopup.Position = UDim2.new(0.5, -180, 0.5, -220)
profilePopup.BackgroundColor3 = C.bg
profilePopup.BackgroundTransparency = 0.03
profilePopup.BorderSizePixel = 0
profilePopup.Visible = false
profilePopup.Active = true
profilePopup.Draggable = true
profilePopup.Parent = profileSg
Instance.new("UICorner", profilePopup).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", profilePopup).Color = C.blue

local ppTitle = Instance.new("TextLabel")
ppTitle.Size = UDim2.new(1, -44, 0, 32)
ppTitle.Position = UDim2.new(0, 12, 0, 6)
ppTitle.BackgroundTransparency = 1
ppTitle.Text = "PLAYER"
ppTitle.TextColor3 = C.white
ppTitle.Font = Enum.Font.GothamBlack
ppTitle.TextSize = 14
ppTitle.TextXAlignment = Enum.TextXAlignment.Left
ppTitle.Parent = profilePopup
local applyFriendsProfileTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(ppTitle, {
	Position = UDim2.new(0, 12, 0, 6),
	Size = UDim2.new(1, -44, 0, 32),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local ppClose = Instance.new("TextButton")
ppClose.Size = UDim2.new(0, 28, 0, 28)
ppClose.Position = UDim2.new(1, -34, 0, 6)
ppClose.BackgroundColor3 = C.red
ppClose.BackgroundTransparency = 0.5
ppClose.Text = GameConfig.UICloseGlyph or "X"
ppClose.TextColor3 = C.white
ppClose.Font = Enum.Font.GothamBold
ppClose.TextSize = 12
ppClose.Parent = profilePopup
Instance.new("UICorner", ppClose).CornerRadius = UDim.new(0, 6)
ppClose.MouseButton1Click:Connect(function() profilePopup.Visible = false end)

local profileScroll = Instance.new("ScrollingFrame")
profileScroll.Size = UDim2.new(1, -20, 1, -98)
profileScroll.Position = UDim2.new(0, 10, 0, 42)
profileScroll.BackgroundTransparency = 1
profileScroll.BorderSizePixel = 0
profileScroll.ScrollBarThickness = 4
profileScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
profileScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
profileScroll.ZIndex = 1
profileScroll.Parent = profilePopup
local profileLayout = Instance.new("UIListLayout")
profileLayout.Padding = UDim.new(0, 6)
profileLayout.SortOrder = Enum.SortOrder.LayoutOrder
profileLayout.Parent = profileScroll

-- Fixed footer: Trade and PvP (ensure it's on top of scroll for input)
local profileFooter = Instance.new("Frame")
profileFooter.Size = UDim2.new(1, -20, 0, 52)
profileFooter.Position = UDim2.new(0, 10, 1, -56)
profileFooter.BackgroundTransparency = 1
profileFooter.Active = true
profileFooter.ZIndex = 10
profileFooter.Parent = profilePopup

local tradeBtn = Instance.new("TextButton")
tradeBtn.Size = UDim2.new(0.5, -4, 0, 36)
tradeBtn.Position = UDim2.new(0, 0, 0, 8)
tradeBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
tradeBtn.Text = "TRADE"
tradeBtn.TextColor3 = C.green
tradeBtn.Font = Enum.Font.GothamBlack
tradeBtn.TextSize = 11
tradeBtn.BorderSizePixel = 0
tradeBtn.ZIndex = 11
tradeBtn.Parent = profileFooter
Instance.new("UICorner", tradeBtn).CornerRadius = UDim.new(0, 10)
tradeBtn.MouseButton1Click:Connect(function()
	local uid = profilePopup:GetAttribute("ProfileUserId")
	if not uid or type(uid) ~= "number" then
		Notify.Toast("Try again", C.muted, 2)
		return
	end
	local tr = Events:FindFirstChild("TradeRequest") or Events:WaitForChild("TradeRequest", 2)
	if not tr then
		Notify.Toast("Trade unavailable", C.muted, 2)
		return
	end
	tr:FireServer(uid)
	Notify.Toast("Trade request sent", C.green, 2)
end)

local battleBtn = Instance.new("TextButton")
battleBtn.Size = UDim2.new(0.5, -4, 0, 36)
battleBtn.Position = UDim2.new(0.5, 2, 0, 8)
battleBtn.BackgroundColor3 = Color3.fromRGB(70, 30, 30)
battleBtn.Text = "PvP 1v1"
battleBtn.TextColor3 = Color3.fromRGB(255, 100, 80)
battleBtn.Font = Enum.Font.GothamBlack
battleBtn.TextSize = 11
battleBtn.BorderSizePixel = 0
battleBtn.ZIndex = 11
battleBtn.Parent = profileFooter
Instance.new("UICorner", battleBtn).CornerRadius = UDim.new(0, 10)
battleBtn.MouseButton1Click:Connect(function()
	local uid = profilePopup:GetAttribute("ProfileUserId")
	if not uid or type(uid) ~= "number" then
		Notify.Toast("Try again", C.muted, 2)
		return
	end
	local pvp = Events:FindFirstChild("RequestPvPBattle") or Events:WaitForChild("RequestPvPBattle", 2)
	if not pvp then
		Notify.Toast("PvP unavailable", C.muted, 2)
		return
	end
	pvp:FireServer(uid)
	Notify.Toast("PvP challenge sent (must be within 30 studs)", Color3.fromRGB(255, 130, 80), 2)
end)

local currentProfileUserId = nil

local function mkProfileLabel(text, color, order)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, 18)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = color or C.white
	l.Font = Enum.Font.GothamBold
	l.TextSize = 11
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	l.LayoutOrder = order
	l.Parent = profileScroll
	return l
end

local function openProfileForUserId(userId)
	currentProfileUserId = userId
	profilePopup:SetAttribute("ProfileUserId", userId)
	MobileWindowLayout.RestoreDesktopWindow(profilePopup, { draggable = true })
	profilePopup.Visible = true
	for _, ch in ipairs(profileScroll:GetChildren()) do
		if not ch:IsA("UIListLayout") then ch:Destroy() end
	end

	ppTitle.Text = "Loading..."

	if not getPublicProfile then
		ppTitle.Text = "Unavailable"
		return
	end
	local ok, prof = pcall(function() return getPublicProfile:InvokeServer(userId) end)
	if not ok or not prof then
		ppTitle.Text = "Unavailable"
		mkProfileLabel("Could not load profile.", C.muted, 0)
		return
	end

	ppTitle.Text = (prof.name or "PLAYER") .. "  (Lv." .. tostring(prof.playerLevel or 1) .. ")"

	local order = 0
	-- Favorite
	mkProfileLabel("FAVORITE", C.muted, order) order = order + 1
	local favRow = Instance.new("Frame")
	favRow.Size = UDim2.new(1, 0, 0, 52)
	favRow.BackgroundColor3 = C.card
	favRow.BorderSizePixel = 0
	favRow.LayoutOrder = order
	favRow.Parent = profileScroll
	Instance.new("UICorner", favRow).CornerRadius = UDim.new(0, 8)
	order = order + 1

	local favOrb = Instance.new("Frame")
	favOrb.Size = UDim2.new(0, 40, 0, 40)
	favOrb.Position = UDim2.new(0, 8, 0, 6)
	favOrb.BackgroundColor3 = Color3.fromRGB(80, 80, 90)
	favOrb.BorderSizePixel = 0
	favOrb.Parent = favRow
	Instance.new("UICorner", favOrb).CornerRadius = UDim.new(1, 0)
	local favOrbStroke = Instance.new("UIStroke", favOrb)
	favOrbStroke.Color = C.muted
	favOrbStroke.Transparency = 0.3

	-- Click favorite image to open Codex entry
	local favOrbBtn = Instance.new("TextButton")
	favOrbBtn.Size = UDim2.new(0, 40, 0, 40)
	favOrbBtn.Position = UDim2.new(0, 8, 0, 6)
	favOrbBtn.BackgroundTransparency = 1
	favOrbBtn.Text = ""
	favOrbBtn.BorderSizePixel = 0
	favOrbBtn.Parent = favRow
	if prof.favorite and prof.favorite.id then
		local creatureId = prof.favorite.id
		favOrbBtn.MouseButton1Click:Connect(function()
			local openCodex = playerGui:FindFirstChild("OpenCodex")
			if openCodex and openCodex:IsA("BindableEvent") then
				openCodex:Fire(creatureId)
			end
		end)
	end

	local favName = Instance.new("TextLabel")
	favName.Size = UDim2.new(1, -60, 0, 18)
	favName.Position = UDim2.new(0, 54, 0, 6)
	favName.BackgroundTransparency = 1
	favName.Text = "(No favorite set)"
	favName.TextColor3 = C.white
	favName.Font = Enum.Font.GothamBlack
	favName.TextSize = 12
	favName.TextXAlignment = Enum.TextXAlignment.Left
	favName.Parent = favRow

	if prof.favorite then
		favName.Text = (prof.favorite.displayName or "Favorite") .. " Lv." .. tostring(prof.favorite.level or 1)
		local pc = prof.favorite.primaryColor
		if type(pc) == "table" then
			favOrb.BackgroundColor3 = Color3.new(pc[1] or 0.5, pc[2] or 0.5, pc[3] or 0.5)
		end
		local rar = prof.favorite.rarity
		if rar == "Legendary" then favOrbStroke.Color = Color3.fromRGB(255, 184, 0)
		elseif rar == "Mythic" or rar == "Epic" then favOrbStroke.Color = Color3.fromRGB(180, 80, 255)
		elseif rar == "Rare" then favOrbStroke.Color = Color3.fromRGB(60, 130, 255)
		elseif rar == "Uncommon" then favOrbStroke.Color = Color3.fromRGB(75, 200, 75)
		else favOrbStroke.Color = Color3.fromRGB(180, 180, 180) end
		-- Favorite stats
		local hp, atk, def, spd = prof.favorite.health, prof.favorite.attack, prof.favorite.defense, prof.favorite.speed
		if hp or atk or def or spd then
			local statText = Instance.new("TextLabel")
			statText.Size = UDim2.new(1, -54, 0, 14)
			statText.Position = UDim2.new(0, 54, 0, 26)
			statText.BackgroundTransparency = 1
			statText.Text = string.format("HP %s  ATK %s  DEF %s  SPD %s", tostring(hp or "-"), tostring(atk or "-"), tostring(def or "-"), tostring(spd or "-"))
			statText.TextColor3 = C.muted
			statText.Font = Enum.Font.GothamMedium
			statText.TextSize = 10
			statText.TextXAlignment = Enum.TextXAlignment.Left
			statText.Parent = favRow
		end
	end

	-- Leaderboard stats
	mkProfileLabel("STATS", C.muted, order) order = order + 1
	local st = prof.stats or {}
	local statRow = Instance.new("TextLabel")
	statRow.Size = UDim2.new(1, -8, 0, 0)
	statRow.AutomaticSize = Enum.AutomaticSize.Y
	statRow.BackgroundColor3 = C.card
	statRow.BorderSizePixel = 0
	statRow.Text = string.format(
		"Wins: %s  Losses: %s  Best Streak: %s\nCaptured: %s  Income: %s  Raids: %s",
		tostring(st.arenaWins or 0), tostring(st.arenaLosses or 0), tostring(st.arenaMaxStreak or 0),
		tostring(st.totalCaptured or 0), tostring(st.totalIncome or 0), tostring(st.totalRaids or 0)
	)
	statRow.TextColor3 = C.white
	statRow.Font = Enum.Font.GothamMedium
	statRow.TextSize = 11
	statRow.TextXAlignment = Enum.TextXAlignment.Left
	statRow.TextYAlignment = Enum.TextYAlignment.Top
	statRow.TextWrapped = true
	statRow.LayoutOrder = order
	statRow.Parent = profileScroll
	Instance.new("UICorner", statRow).CornerRadius = UDim.new(0, 8)
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft = UDim.new(0, 8)
		pad.PaddingRight = UDim.new(0, 8)
		pad.PaddingTop = UDim.new(0, 6)
		pad.PaddingBottom = UDim.new(0, 6)
		pad.Parent = statRow
	end
	order = order + 1

	-- Battle team
	mkProfileLabel("BATTLE TEAM", C.muted, order) order = order + 1
	local bt = prof.battleTeam or {}
	if #bt == 0 then
		local noBT = Instance.new("TextLabel")
		noBT.Size = UDim2.new(1, -8, 0, 0)
		noBT.AutomaticSize = Enum.AutomaticSize.Y
		noBT.BackgroundColor3 = C.card
		noBT.Padding = UDim.new(0, 10)
		noBT.Text = "They don't have a battle team set up yet."
		noBT.TextColor3 = C.muted
		noBT.Font = Enum.Font.GothamMedium
		noBT.TextSize = 11
		noBT.TextWrapped = true
		noBT.LayoutOrder = order
		noBT.Parent = profileScroll
		Instance.new("UICorner", noBT).CornerRadius = UDim.new(0, 8)
	else
		local grid = Instance.new("Frame")
		grid.Size = UDim2.new(1, 0, 0, 88)
		grid.BackgroundColor3 = C.card
		grid.BorderSizePixel = 0
		grid.LayoutOrder = order
		grid.Parent = profileScroll
		Instance.new("UICorner", grid).CornerRadius = UDim.new(0, 8)
		for i, slot in ipairs(bt) do
			local row = math.floor((slot.slotIndex - 1) / 3)
			local col = (slot.slotIndex - 1) % 3
			local cell = Instance.new("TextLabel")
			cell.Size = UDim2.new(0, 105, 0, 26)
			cell.Position = UDim2.new(0, 8 + col * 110, 0, 8 + row * 30)
			cell.BackgroundColor3 = Color3.fromRGB(35, 38, 50)
			cell.BorderSizePixel = 0
			cell.Text = slot.displayName or "?"
			cell.TextColor3 = C.white
			cell.Font = Enum.Font.GothamMedium
			cell.TextSize = 10
			cell.TextTruncate = Enum.TextTruncate.AtEnd
			cell.Parent = grid
			Instance.new("UICorner", cell).CornerRadius = UDim.new(0, 4)
		end
	end
	order = order + 1
end

ppClose.MouseButton1Click:Connect(function() profilePopup.Visible = false end)

-- Allow other scripts (e.g. E near player) to open a player's profile
local openProfileEvent = Instance.new("BindableEvent")
openProfileEvent.Name = "OpenPlayerProfile"
openProfileEvent.Parent = playerGui
openProfileEvent.Event:Connect(function(userId)
	if type(userId) == "number" then openProfileForUserId(userId) end
end)

-- ========= TRADE WINDOW (own ScreenGui so it draws on top) =========
local tradeSg = Instance.new("ScreenGui")
tradeSg.Name = "TradeGUI"
tradeSg.ResetOnSpawn = false
tradeSg.DisplayOrder = 200
tradeSg.ZIndexBehavior = Enum.ZIndexBehavior.Global
tradeSg.Parent = playerGui

local tradeUI = Instance.new("Frame")
tradeUI.Size = UDim2.new(0, 560, 0, 400)
tradeUI.Position = UDim2.new(0.5, -280, 0.5, -200)
tradeUI.BackgroundColor3 = C.bg
tradeUI.BackgroundTransparency = 0.03
tradeUI.BorderSizePixel = 0
tradeUI.Visible = false
tradeUI.Active = true
tradeUI.Draggable = true
tradeUI.Parent = tradeSg
Instance.new("UICorner", tradeUI).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", tradeUI).Color = C.blue

local tradeTitle = Instance.new("TextLabel")
tradeTitle.Size = UDim2.new(1, -40, 0, 32)
tradeTitle.Position = UDim2.new(0, 12, 0, 6)
tradeTitle.BackgroundTransparency = 1
tradeTitle.Text = "TRADE"
tradeTitle.TextColor3 = C.white
tradeTitle.Font = Enum.Font.GothamBlack
tradeTitle.TextSize = 14
tradeTitle.TextXAlignment = Enum.TextXAlignment.Left
tradeTitle.Parent = tradeUI
local applyFriendsTradeTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(tradeTitle, {
	Position = UDim2.new(0, 12, 0, 6),
	Size = UDim2.new(1, -40, 0, 32),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local tradeClose = Instance.new("TextButton")
tradeClose.Size = UDim2.new(0, 28, 0, 28)
tradeClose.Position = UDim2.new(1, -34, 0, 6)
tradeClose.BackgroundColor3 = C.red
tradeClose.BackgroundTransparency = 0.5
tradeClose.Text = GameConfig.UICloseGlyph or "X"
tradeClose.TextColor3 = C.white
tradeClose.Font = Enum.Font.GothamBold
tradeClose.TextSize = 12
tradeClose.Parent = tradeUI
Instance.new("UICorner", tradeClose).CornerRadius = UDim.new(0, 6)

local tradeIdActive = nil
local myOffered = {} -- [uid]=true
local lastState = nil
local myFavoriteUid = nil  -- current favorite (from getInventory), used to highlight in trade "Your Offer"

-- Inventory strip at top (click to add/remove from your offer)
local invLabel = Instance.new("TextLabel")
invLabel.Size = UDim2.new(1, -24, 0, 16)
invLabel.Position = UDim2.new(0, 12, 0, 40)
invLabel.BackgroundTransparency = 1
invLabel.Text = "Your inventory (click to add/remove from your offer)"
invLabel.TextColor3 = C.muted
invLabel.Font = Enum.Font.GothamMedium
invLabel.TextSize = 10
invLabel.TextXAlignment = Enum.TextXAlignment.Left
invLabel.Parent = tradeUI

local invScroll = Instance.new("ScrollingFrame")
invScroll.Size = UDim2.new(1, -24, 0, 68)
invScroll.Position = UDim2.new(0, 12, 0, 58)
invScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
invScroll.BorderSizePixel = 0
invScroll.ScrollBarThickness = 3
invScroll.Parent = tradeUI
Instance.new("UICorner", invScroll).CornerRadius = UDim.new(0, 10)
local invLayout = Instance.new("UIListLayout")
invLayout.Padding = UDim.new(0, 2)
invLayout.Parent = invScroll

-- Left column: Your Offer (fills top to bottom)
local myOfferFrame = Instance.new("Frame")
-- FIX: Use scale-based height so the offer columns fill the available space
-- between the inventory strip (y=132) and the accept/cancel buttons (46px from bottom).
-- Old hardcoded 238px caused the buttons to overflow off-screen on mobile.
myOfferFrame.Size = UDim2.new(0.5, -14, 1, -178)
myOfferFrame.Position = UDim2.new(0, 12, 0, 132)
myOfferFrame.BackgroundTransparency = 1
myOfferFrame.Parent = tradeUI

local myOfferLabel = Instance.new("TextLabel")
myOfferLabel.Size = UDim2.new(1, -8, 0, 20)
myOfferLabel.BackgroundTransparency = 1
myOfferLabel.Text = "Your Offer"
myOfferLabel.TextColor3 = C.green
myOfferLabel.Font = Enum.Font.GothamBold
myOfferLabel.TextSize = 12
myOfferLabel.TextXAlignment = Enum.TextXAlignment.Left
myOfferLabel.Parent = myOfferFrame

local myOfferScroll = Instance.new("ScrollingFrame")
myOfferScroll.Size = UDim2.new(1, 0, 1, -24)
myOfferScroll.Position = UDim2.new(0, 0, 0, 22)
myOfferScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
myOfferScroll.BorderSizePixel = 0
myOfferScroll.ScrollBarThickness = 3
myOfferScroll.Parent = myOfferFrame
Instance.new("UICorner", myOfferScroll).CornerRadius = UDim.new(0, 10)
local myOfferLayout = Instance.new("UIListLayout")
myOfferLayout.Padding = UDim.new(0, 2)
myOfferLayout.Parent = myOfferScroll

-- Right column: Their Offer (fills top to bottom)
local theirOfferFrame = Instance.new("Frame")
-- FIX: Same scale-based height as myOfferFrame — fills from inventory to buttons
theirOfferFrame.Size = UDim2.new(0.5, -14, 1, -178)
theirOfferFrame.Position = UDim2.new(0.5, 2, 0, 132)
theirOfferFrame.BackgroundTransparency = 1
theirOfferFrame.Parent = tradeUI

local theirOfferLabel = Instance.new("TextLabel")
theirOfferLabel.Size = UDim2.new(1, -8, 0, 20)
theirOfferLabel.BackgroundTransparency = 1
theirOfferLabel.Text = "Their Offer"
theirOfferLabel.TextColor3 = C.blue
theirOfferLabel.Font = Enum.Font.GothamBold
theirOfferLabel.TextSize = 12
theirOfferLabel.TextXAlignment = Enum.TextXAlignment.Left
theirOfferLabel.Parent = theirOfferFrame

local theirOfferScroll = Instance.new("ScrollingFrame")
theirOfferScroll.Size = UDim2.new(1, 0, 1, -24)
theirOfferScroll.Position = UDim2.new(0, 0, 0, 22)
theirOfferScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
theirOfferScroll.BorderSizePixel = 0
theirOfferScroll.ScrollBarThickness = 3
theirOfferScroll.Parent = theirOfferFrame
Instance.new("UICorner", theirOfferScroll).CornerRadius = UDim.new(0, 10)
local theirOfferLayout = Instance.new("UIListLayout")
theirOfferLayout.Padding = UDim.new(0, 2)
theirOfferLayout.Parent = theirOfferScroll

local acceptBtn = Instance.new("TextButton")
acceptBtn.Size = UDim2.new(0.5, -14, 0, 34)
acceptBtn.Position = UDim2.new(0, 12, 1, -40)
acceptBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
acceptBtn.Text = "ACCEPT"
acceptBtn.TextColor3 = C.green
acceptBtn.Font = Enum.Font.GothamBlack
acceptBtn.TextSize = 12
acceptBtn.BorderSizePixel = 0
acceptBtn.Parent = tradeUI
Instance.new("UICorner", acceptBtn).CornerRadius = UDim.new(0, 10)

local cancelBtn = Instance.new("TextButton")
cancelBtn.Size = UDim2.new(0.5, -14, 0, 34)
cancelBtn.Position = UDim2.new(0.5, 2, 1, -40)
cancelBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
cancelBtn.Text = "CANCEL"
cancelBtn.TextColor3 = C.red
cancelBtn.Font = Enum.Font.GothamBlack
cancelBtn.TextSize = 12
cancelBtn.BorderSizePixel = 0
cancelBtn.Parent = tradeUI
Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 10)

-- ── TRADE WINDOW MOBILE LAYOUT ──────────────────────────────────────────────
-- FIX: On mobile the hardcoded 560×400 trade window exceeds screen width and
-- pushes the accept/cancel buttons off the bottom edge. Apply MobileWindowLayout
-- so the trade window fills the safe area, same as every other menu panel.
local TRADE_DESIGN_W = 560
local TRADE_DESIGN_H = 400

local function applyTradeLayout()
	MobileWindowLayout.SyncNpcMenuScreenGui(sg, TRADE_DESIGN_W, TRADE_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(TRADE_DESIGN_W, TRADE_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(
			tradeUI,
			MobileWindowLayout.GetNpcFullscreenBoundsConfig(TRADE_DESIGN_W, TRADE_DESIGN_H, { mobileDraggable = true })
		)
		tradeUI.Draggable = true
		-- Slightly reduce text sizes and shrink inventory strip on mobile for better fit
		tradeTitle.TextSize = 13
		invLabel.TextSize = 9
		acceptBtn.TextSize = 11
		cancelBtn.TextSize = 11
		-- Compact the inventory strip on mobile to reclaim vertical space
		invScroll.Size = UDim2.new(1, -24, 0, 52)
		myOfferFrame.Position = UDim2.new(0, 12, 0, 116)
		myOfferFrame.Size = UDim2.new(0.5, -14, 1, -162)
		theirOfferFrame.Position = UDim2.new(0.5, 2, 0, 116)
		theirOfferFrame.Size = UDim2.new(0.5, -14, 1, -162)
	else
		sg.IgnoreGuiInset = false
		-- Desktop: restore original fixed-size layout
		tradeUI.AnchorPoint = Vector2.new(0, 0)
		tradeUI.Size = UDim2.new(0, TRADE_DESIGN_W, 0, TRADE_DESIGN_H)
		tradeUI.Position = UDim2.new(0.5, -TRADE_DESIGN_W / 2, 0.5, -TRADE_DESIGN_H / 2)
		tradeTitle.TextSize = 14
		invLabel.TextSize = 10
		acceptBtn.TextSize = 12
		cancelBtn.TextSize = 12
		-- Restore desktop inventory strip and offer column sizes
		invScroll.Size = UDim2.new(1, -24, 0, 68)
		myOfferFrame.Position = UDim2.new(0, 12, 0, 132)
		myOfferFrame.Size = UDim2.new(0.5, -14, 1, -178)
		theirOfferFrame.Position = UDim2.new(0.5, 2, 0, 132)
		theirOfferFrame.Size = UDim2.new(0.5, -14, 1, -178)
		MobileWindowLayout.RestoreDesktopWindow(tradeUI, { draggable = true })
	end
	applyFriendsTradeTitleLayout()
end

local function setTradeVisible(v)
	tradeUI.Visible = v
	if v then
		applyTradeLayout()
	end
	if not v then
		tradeIdActive = nil
		myOffered = {}
		lastState = nil
		if panel.Visible then
			MobileWindowLayout.SyncNpcMenuScreenGui(sg, PANEL_DESIGN_W, PANEL_DESIGN_H)
		else
			sg.IgnoreGuiInset = false
		end
	end
end

tradeClose.MouseButton1Click:Connect(function()
	if tradeIdActive and tradeCancel then tradeCancel:FireServer(tradeIdActive) end
	setTradeVisible(false)
end)
cancelBtn.MouseButton1Click:Connect(function()
	if tradeIdActive and tradeCancel then tradeCancel:FireServer(tradeIdActive) end
	setTradeVisible(false)
end)

local function rebuildInventoryList()
	for _, ch in ipairs(invScroll:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextButton") then ch:Destroy() end
	end
	if not getInventory then return end
	local ok, data = pcall(function() return getInventory:InvokeServer() end)
	if not ok or not data or not data.inventory then return end
	myFavoriteUid = data.favoriteUid

	for _, e in ipairs(data.inventory) do
		local cr = CreatureData.GetById(e.id)
		if cr then
			local btn = Instance.new("TextButton")
			btn.Size = UDim2.new(1, -6, 0, 26)
			btn.BackgroundColor3 = myOffered[e.uid] and Color3.fromRGB(25, 45, 30) or C.card
			btn.BorderSizePixel = 0
			btn.Text = ""
			btn.Parent = invScroll
			Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

			local orb = Instance.new("Frame")
			orb.Size = UDim2.new(0, 18, 0, 18)
			orb.Position = UDim2.new(0, 6, 0.5, -9)
			orb.BackgroundColor3 = cr.primaryColor
			orb.BorderSizePixel = 0
			orb.Parent = btn
			Instance.new("UICorner", orb).CornerRadius = UDim.new(1, 0)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(1, -32, 1, 0)
			nameLbl.Position = UDim2.new(0, 28, 0, 0)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = (cr.displayName or e.id) .. " (Lv." .. tostring(e.level or 1) .. ")"
			nameLbl.TextColor3 = C.white
			nameLbl.Font = Enum.Font.GothamBold
			nameLbl.TextSize = 11
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Parent = btn

			btn.MouseButton1Click:Connect(function()
				myOffered[e.uid] = not myOffered[e.uid]
				rebuildInventoryList()
				if tradeIdActive and tradeUpdateOffer then
					local arr = {}
					for uid, v in pairs(myOffered) do if v then table.insert(arr, uid) end end
					tradeUpdateOffer:FireServer(tradeIdActive, arr)
				end
			end)
		end
	end
	invLayout:ApplyLayout()
	invScroll.CanvasSize = UDim2.new(0, 0, 0, invLayout.AbsoluteContentSize.Y + 4)
end

local function addOfferLine(parent, txt, clr)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, -8, 0, 20)
	l.BackgroundTransparency = 1
	l.Text = txt
	l.TextColor3 = clr or C.white
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 10
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.Parent = parent
	return l
end

local function rebuildOfferView(state)
	for _, ch in ipairs(myOfferScroll:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end
	end
	for _, ch in ipairs(theirOfferScroll:GetChildren()) do
		if ch:IsA("Frame") or ch:IsA("TextLabel") then ch:Destroy() end
	end
	if not state then return end
	local myKey = tostring(player.UserId)
	local otherKey = (tostring(state.aId) == myKey) and tostring(state.bId) or tostring(state.aId)
	local mine = state.offers and state.offers[myKey] or {}
	local theirs = state.offers and state.offers[otherKey] or {}
	local accepted = state.accepted or {}

	-- Headers with accepted icon (✓) when that player has accepted
	myOfferLabel.Text = "Your Offer (" .. tostring(#mine) .. ")" .. (accepted[myKey] and " ✓" or "")
	theirOfferLabel.Text = "Their Offer (" .. tostring(#theirs) .. ")" .. (accepted[otherKey] and " ✓" or "")
	-- If the other player has accepted, show CONFIRM so clicking finalizes the trade
	acceptBtn.Text = (accepted[otherKey] and "CONFIRM" or "ACCEPT")

	local detailsMine = state.offerDetails and state.offerDetails[myKey] or {}
	local detailsTheirs = state.offerDetails and state.offerDetails[otherKey] or {}

	-- Left column: your offer list (fills top to bottom)
	for i, uid in ipairs(mine) do
		local d = detailsMine[i]
		local lineText = "• " .. (d and (d.displayName .. " Lv." .. tostring(d.level)) or uid)
		local clr = (uid == myFavoriteUid) and C.favorite or C.muted
		if uid == myFavoriteUid then lineText = lineText .. " ★" end
		addOfferLine(myOfferScroll, lineText, clr)
	end

	-- Right column: their offer list (fills top to bottom)
	for i, uid in ipairs(theirs) do
		local d = detailsTheirs[i]
		local lineText = "• " .. (d and (d.displayName .. " Lv." .. tostring(d.level)) or uid)
		addOfferLine(theirOfferScroll, lineText, C.muted)
	end

	myOfferLayout:ApplyLayout()
	myOfferScroll.CanvasSize = UDim2.new(0, 0, 0, myOfferLayout.AbsoluteContentSize.Y + 4)
	theirOfferLayout:ApplyLayout()
	theirOfferScroll.CanvasSize = UDim2.new(0, 0, 0, theirOfferLayout.AbsoluteContentSize.Y + 4)
end

acceptBtn.MouseButton1Click:Connect(function()
	if tradeIdActive and tradeAccept then tradeAccept:FireServer(tradeIdActive) end
end)

if tradeInvite then
	tradeInvite.OnClientEvent:Connect(function(payload)
		if type(payload) ~= "table" then return end
		local fromName = payload.fromName or "Player"
		local tid = payload.tradeId
		Notify.Toast(fromName .. " wants to trade (open Friends to accept)", C.blue, 4, nil, "trade")
		-- Simple auto-accept UI: show popup prompt
		-- FIX: Use AnchorPoint for centering instead of manual pixel offset,
		-- and cap width to 90% on mobile so it fits small screens.
		local prompt = Instance.new("Frame")
		local isMobile = MobileWindowLayout.NpcMenuUsesFullscreenBounds(340, 380)
		prompt.Size = isMobile and UDim2.new(0.9, 0, 0, 120) or UDim2.new(0, 320, 0, 120)
		prompt.AnchorPoint = Vector2.new(0.5, 0.5)
		prompt.Position = UDim2.new(0.5, 0, 0.5, 0)
		prompt.BackgroundColor3 = C.bg
		prompt.BackgroundTransparency = 0.03
		prompt.BorderSizePixel = 0
		prompt.Parent = sg
		prompt.ZIndex = 100
		Instance.new("UICorner", prompt).CornerRadius = UDim.new(0, 14)
		Instance.new("UIStroke", prompt).Color = C.blue

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, -24, 0, 50)
		txt.Position = UDim2.new(0, 12, 0, 10)
		txt.BackgroundTransparency = 1
		txt.Text = fromName .. " wants to trade"
		txt.TextColor3 = C.white
		txt.Font = Enum.Font.GothamBlack
		txt.TextSize = 14
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.Parent = prompt

		local accept = Instance.new("TextButton")
		accept.Size = UDim2.new(0.5, -18, 0, 34)
		accept.Position = UDim2.new(0, 12, 1, -46)
		accept.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
		accept.Text = "ACCEPT"
		accept.TextColor3 = C.green
		accept.Font = Enum.Font.GothamBlack
		accept.TextSize = 12
		accept.BorderSizePixel = 0
		accept.Parent = prompt
		Instance.new("UICorner", accept).CornerRadius = UDim.new(0, 10)

		local decline = Instance.new("TextButton")
		decline.Size = UDim2.new(0.5, -18, 0, 34)
		decline.Position = UDim2.new(0.5, 6, 1, -46)
		decline.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
		decline.Text = "DECLINE"
		decline.TextColor3 = C.red
		decline.Font = Enum.Font.GothamBlack
		decline.TextSize = 12
		decline.BorderSizePixel = 0
		decline.Parent = prompt
		Instance.new("UICorner", decline).CornerRadius = UDim.new(0, 10)

		accept.MouseButton1Click:Connect(function()
			if tradeResponse then tradeResponse:FireServer(tid, true) end
			prompt:Destroy()
		end)
		decline.MouseButton1Click:Connect(function()
			if tradeResponse then tradeResponse:FireServer(tid, false) end
			prompt:Destroy()
		end)
	end)
end

-- Show server rejection when PvP challenge fails (e.g. too far, no favorite)
task.defer(function()
	local reject = Events:FindFirstChild("PvPBattleReject") or Events:WaitForChild("PvPBattleReject", 5)
	if reject then
		reject.OnClientEvent:Connect(function(message)
			Notify.Toast(message or "PvP challenge failed.", Color3.fromRGB(255, 100, 80), 4)
		end)
	end
end)

if pvpChallengeInvite then
	pvpChallengeInvite.OnClientEvent:Connect(function(fromUserId, fromName)
		fromName = fromName or ("User#" .. tostring(fromUserId))
		Notify.Toast(fromName .. " wants to battle you!", Color3.fromRGB(255, 130, 80), 4, nil, "pvp")
		-- FIX: Use AnchorPoint for centering; cap width to 90% on mobile
		local prompt = Instance.new("Frame")
		local isMobilePvP = MobileWindowLayout.NpcMenuUsesFullscreenBounds(340, 380)
		prompt.Size = isMobilePvP and UDim2.new(0.9, 0, 0, 120) or UDim2.new(0, 320, 0, 120)
		prompt.AnchorPoint = Vector2.new(0.5, 0.5)
		prompt.Position = UDim2.new(0.5, 0, 0.5, 0)
		prompt.BackgroundColor3 = C.bg
		prompt.BackgroundTransparency = 0.03
		prompt.BorderSizePixel = 0
		prompt.Parent = sg
		prompt.ZIndex = 100
		Instance.new("UICorner", prompt).CornerRadius = UDim.new(0, 14)
		Instance.new("UIStroke", prompt).Color = Color3.fromRGB(255, 100, 80)

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, -24, 0, 50)
		txt.Position = UDim2.new(0, 12, 0, 10)
		txt.BackgroundTransparency = 1
		txt.Text = fromName .. " wants to battle (1v1 favorite vs favorite)"
		txt.TextColor3 = C.white
		txt.Font = Enum.Font.GothamBlack
		txt.TextSize = 13
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextWrapped = true
		txt.Parent = prompt

		local accept = Instance.new("TextButton")
		accept.Size = UDim2.new(0.5, -18, 0, 34)
		accept.Position = UDim2.new(0, 12, 1, -46)
		accept.BackgroundColor3 = Color3.fromRGB(50, 70, 30)
		accept.Text = "ACCEPT"
		accept.TextColor3 = C.green
		accept.Font = Enum.Font.GothamBlack
		accept.TextSize = 12
		accept.BorderSizePixel = 0
		accept.Parent = prompt
		Instance.new("UICorner", accept).CornerRadius = UDim.new(0, 10)

		local decline = Instance.new("TextButton")
		decline.Size = UDim2.new(0.5, -18, 0, 34)
		decline.Position = UDim2.new(0.5, 6, 1, -46)
		decline.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
		decline.Text = "DECLINE"
		decline.TextColor3 = C.red
		decline.Font = Enum.Font.GothamBlack
		decline.TextSize = 12
		decline.BorderSizePixel = 0
		decline.Parent = prompt
		Instance.new("UICorner", decline).CornerRadius = UDim.new(0, 10)

		accept.MouseButton1Click:Connect(function()
			if pvpAcceptChallenge then pvpAcceptChallenge:FireServer(fromUserId) end
			prompt:Destroy()
		end)
		decline.MouseButton1Click:Connect(function()
			if pvpDeclineChallenge then pvpDeclineChallenge:FireServer(fromUserId) end
			prompt:Destroy()
		end)
	end)
end

if tradeState then
	tradeState.OnClientEvent:Connect(function(state)
		if type(state) ~= "table" then return end
		lastState = state
		tradeIdActive = state.tradeId
		if state.status == "pending" then
			-- requester sees pending; keep UI hidden until active
			return
		end
		if state.status == "active" then
			setTradeVisible(true)
			tradeTitle.Text = "TRADE (" .. tostring(state.tradeId) .. ")"
			rebuildInventoryList()  -- first so myFavoriteUid is set for favorite indicator in offer view
			rebuildOfferView(state)
		elseif state.status == "completed" then
			Notify.Toast("Trade completed!", C.green, 3)
			setTradeVisible(false)
		elseif state.status == "declined" then
			Notify.Toast("Trade declined", C.red, 3)
			setTradeVisible(false)
		elseif state.status == "cancelled" or state.status == "player_left" or state.status == "inventory_full" or state.status == "invalid_offer" then
			Notify.Toast("Trade ended (" .. tostring(state.status) .. ")", C.red, 3)
			setTradeVisible(false)
		end
	end)
end

-- Panel scales with viewport
local PANEL_DESIGN_W = 340
local PANEL_DESIGN_H = 380
local PANEL_SCALE_MIN = 0.52
local PANEL_SCALE_MAX = 1

local function getPanelScale()
	local camera = workspace.CurrentCamera
	local vp = (camera and camera.ViewportSize) or Vector2.new(PANEL_DESIGN_W, PANEL_DESIGN_H)
	local scale = math.min(vp.X / PANEL_DESIGN_W, vp.Y / PANEL_DESIGN_H)
	return math.clamp(scale, PANEL_SCALE_MIN, PANEL_SCALE_MAX)
end

local applyFriendsListTitleLayout

local function applyPanelScale(pnl)
	MobileWindowLayout.SyncNpcMenuScreenGui(sg, PANEL_DESIGN_W, PANEL_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(
			pnl,
			MobileWindowLayout.GetNpcFullscreenBoundsConfig(PANEL_DESIGN_W, PANEL_DESIGN_H, { mobileDraggable = true })
		)
		pnl.Draggable = true
	else
		local scale = getPanelScale()
		local w, h = PANEL_DESIGN_W * scale, PANEL_DESIGN_H * scale
		pnl.Size = UDim2.new(0, w, 0, h)
		pnl.Position = UDim2.new(0.5, -w/2, 0.5, -h/2)
		sg.IgnoreGuiInset = false
		MobileWindowLayout.RestoreDesktopWindow(pnl, { draggable = true })
	end
	if applyFriendsListTitleLayout then
		applyFriendsListTitleLayout()
	end
end

-- ── FRIENDS PANEL (same sg as profile popup) ──
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, PANEL_DESIGN_W, 0, PANEL_DESIGN_H)
panel.Position = UDim2.new(0.5, -PANEL_DESIGN_W/2, 0.5, -PANEL_DESIGN_H/2)
panel.BackgroundColor3 = C.bg; panel.BackgroundTransparency = 0.05
panel.BorderSizePixel = 0; panel.Visible = false; panel.Active = true; panel.Draggable = true; panel.Parent = sg
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", panel).Color = Color3.fromRGB(60, 140, 255)

-- Title
local titleLbl = Instance.new("TextLabel")
titleLbl.Size = UDim2.new(1, -50, 0, 38); titleLbl.Position = UDim2.new(0, 15, 0, 0)
titleLbl.BackgroundTransparency = 1; titleLbl.Text = " Base Access List"
titleLbl.TextColor3 = C.blue; titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextSize = 16
titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = panel
applyFriendsListTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(titleLbl, {
	Position = UDim2.new(0, 15, 0, 0),
	Size = UDim2.new(1, -50, 0, 38),
	TextXAlignment = Enum.TextXAlignment.Left,
})

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 30, 0, 30); closeBtn.Position = UDim2.new(1, -36, 0, 4)
closeBtn.BackgroundColor3 = C.red; closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = GameConfig.UICloseGlyph or "X"; closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold; closeBtn.TextSize = 12; closeBtn.Parent = panel
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
closeBtn.MouseButton1Click:Connect(function()
	panel.Visible = false
	if tradeUI.Visible then
		MobileWindowLayout.SyncNpcMenuScreenGui(sg, TRADE_DESIGN_W, TRADE_DESIGN_H)
	else
		sg.IgnoreGuiInset = false
	end
	MobileWindowLayout.NotifyMenuClosed()
end)

-- Info
local infoLbl = Instance.new("TextLabel")
infoLbl.Size = UDim2.new(1, -20, 0, 16); infoLbl.Position = UDim2.new(0, 10, 0, 40)
infoLbl.BackgroundTransparency = 1
infoLbl.Text = "Friends on this list can enter your base through laser doors"
infoLbl.TextColor3 = C.muted; infoLbl.Font = Enum.Font.GothamMedium; infoLbl.TextSize = 10
infoLbl.Parent = panel

-- ── ADD PLAYER SECTION ──
local addFrame = Instance.new("Frame")
addFrame.Size = UDim2.new(1, -20, 0, 34); addFrame.Position = UDim2.new(0, 10, 0, 62)
addFrame.BackgroundTransparency = 1; addFrame.Parent = panel

-- Show online players as buttons
local onlineScroll = Instance.new("ScrollingFrame")
onlineScroll.Size = UDim2.new(1, 0, 0, 90); onlineScroll.Position = UDim2.new(0, 0, 0, 0)
onlineScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
onlineScroll.BorderSizePixel = 0; onlineScroll.ScrollBarThickness = 3
onlineScroll.Parent = addFrame
Instance.new("UICorner", onlineScroll).CornerRadius = UDim.new(0, 8)

local onlineLayout = Instance.new("UIListLayout")
onlineLayout.Padding = UDim.new(0, 2); onlineLayout.Parent = onlineScroll

-- ── FRIENDS LIST ──
local listTitle = Instance.new("TextLabel")
listTitle.Size = UDim2.new(1, -20, 0, 22); listTitle.Position = UDim2.new(0, 10, 0, 160)
listTitle.BackgroundTransparency = 1; listTitle.Text = "Current Friends:"
listTitle.TextColor3 = C.white; listTitle.Font = Enum.Font.GothamBold; listTitle.TextSize = 12
listTitle.TextXAlignment = Enum.TextXAlignment.Left; listTitle.Parent = panel

local friendScroll = Instance.new("ScrollingFrame")
friendScroll.Size = UDim2.new(1, -20, 0, 170); friendScroll.Position = UDim2.new(0, 10, 0, 185)
friendScroll.BackgroundColor3 = Color3.fromRGB(18, 20, 30)
friendScroll.BorderSizePixel = 0; friendScroll.ScrollBarThickness = 3
friendScroll.Parent = panel
Instance.new("UICorner", friendScroll).CornerRadius = UDim.new(0, 8)

local friendLayout = Instance.new("UIListLayout")
friendLayout.Padding = UDim.new(0, 2); friendLayout.Parent = friendScroll

local function applyResponsiveContentLayout()
	local mobile = MobileWindowLayout.NpcMenuUsesFullscreenBounds(PANEL_DESIGN_W, PANEL_DESIGN_H)
	addFrame.Size = mobile and UDim2.new(1, -16, 0, 132) or UDim2.new(1, -20, 0, 34)
	addFrame.Position = mobile and UDim2.new(0, 8, 0, 62) or UDim2.new(0, 10, 0, 62)
	onlineScroll.Size = mobile and UDim2.new(1, 0, 1, 0) or UDim2.new(1, 0, 0, 90)
	listTitle.Position = mobile and UDim2.new(0, 10, 0, 200) or UDim2.new(0, 10, 0, 160)
	friendScroll.Position = mobile and UDim2.new(0, 10, 0, 224) or UDim2.new(0, 10, 0, 185)
	friendScroll.Size = mobile and UDim2.new(1, -20, 1, -236) or UDim2.new(1, -20, 0, 170)
	closeBtn.Size = mobile and UDim2.new(0, 38, 0, 38) or UDim2.new(0, 30, 0, 30)
	closeBtn.Position = mobile and UDim2.new(1, -46, 0, 4) or UDim2.new(1, -36, 0, 4)
	closeBtn.TextSize = mobile and 16 or 12
end

-- ── REFRESH FUNCTIONS ──

local currentFriends = {} -- {userId, ...}

local function refreshFriendsList()
	if not getFriendsList then return end
	local ok, list = pcall(function() return getFriendsList:InvokeServer() end)
	if ok and list then currentFriends = list end

	-- Clear old entries
	for _, ch in ipairs(friendScroll:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end

	for _, friendId in ipairs(currentFriends) do
		local friendPlayer = Players:GetPlayerByUserId(friendId)
		local friendName = friendPlayer and friendPlayer.Name or ("User#" .. friendId)

		local entry = Instance.new("Frame")
		entry.Size = UDim2.new(1, -6, 0, 28); entry.BackgroundColor3 = C.card
		entry.BorderSizePixel = 0; entry.Parent = friendScroll
		Instance.new("UICorner", entry).CornerRadius = UDim.new(0, 6)

		-- Click row to open profile (except Remove button)
		local rowBtn = Instance.new("TextButton")
		rowBtn.Size = UDim2.new(1, -70, 1, 0); rowBtn.Position = UDim2.new(0, 0, 0, 0)
		rowBtn.BackgroundTransparency = 1; rowBtn.Text = ""; rowBtn.Parent = entry
		rowBtn.MouseButton1Click:Connect(function() openProfileForUserId(friendId) end)

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(0.65, 0, 1, 0); nameLbl.Position = UDim2.new(0, 8, 0, 0)
		nameLbl.BackgroundTransparency = 1; nameLbl.Text = friendName
		nameLbl.TextColor3 = C.white; nameLbl.Font = Enum.Font.GothamBold; nameLbl.TextSize = 11
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left; nameLbl.Parent = entry

		local statusLbl = Instance.new("TextLabel")
		statusLbl.Size = UDim2.new(0.15, 0, 1, 0); statusLbl.Position = UDim2.new(0.55, 0, 0, 0)
		statusLbl.BackgroundTransparency = 1
		statusLbl.Text = friendPlayer and "●" or "○"
		statusLbl.TextColor3 = friendPlayer and C.green or C.muted
		statusLbl.Font = Enum.Font.GothamBold; statusLbl.TextSize = 12; statusLbl.Parent = entry

		local removeBtn = Instance.new("TextButton")
		removeBtn.Size = UDim2.new(0, 60, 0, 22); removeBtn.Position = UDim2.new(1, -65, 0.5, -11)
		removeBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
		removeBtn.Text = "Remove"; removeBtn.TextColor3 = C.red
		removeBtn.Font = Enum.Font.GothamBold; removeBtn.TextSize = 9; removeBtn.Parent = entry
		Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 4)

		removeBtn.MouseButton1Click:Connect(function()
			if removeFriend then
				removeFriend:FireServer(friendId)
				Notify.Toast("Removed " .. friendName, C.red, 2)
				task.wait(0.3); refreshFriendsList()
			end
		end)
	end

	friendLayout:ApplyLayout()
	friendScroll.CanvasSize = UDim2.new(0, 0, 0, friendLayout.AbsoluteContentSize.Y + 4)
end

local function refreshOnlinePlayers()
	for _, ch in ipairs(onlineScroll:GetChildren()) do
		if ch:IsA("TextButton") then ch:Destroy() end
	end

	for _, p in ipairs(Players:GetPlayers()) do
		if p == player then continue end

		-- Check if already a friend
		local isFriend = false
		for _, fid in ipairs(currentFriends) do
			if fid == p.UserId then isFriend = true; break end
		end

		local btn = Instance.new("TextButton")
		btn.Size = UDim2.new(1, -6, 0, 26); btn.BackgroundColor3 = isFriend and C.card or Color3.fromRGB(20, 35, 45)
		btn.BorderSizePixel = 0
		btn.Text = (isFriend and "  ✅ " or "  ➕ ") .. p.Name
		btn.TextColor3 = isFriend and C.muted or C.blue
		btn.Font = Enum.Font.GothamBold; btn.TextSize = 11
		btn.TextXAlignment = Enum.TextXAlignment.Left; btn.Parent = onlineScroll
		Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)

			btn.MouseButton1Click:Connect(function()
			if isFriend then
				openProfileForUserId(p.UserId)
			else
				if addFriend then
					addFriend:FireServer(p.UserId)
					Notify.Toast("Added " .. p.Name .. " to base access list", C.green, 2)
					task.wait(0.2)
					refreshFriendsList()
					refreshOnlinePlayers()
				end
				end
			end)
	end

	onlineLayout:ApplyLayout()
	onlineScroll.CanvasSize = UDim2.new(0, 0, 0, onlineLayout.AbsoluteContentSize.Y + 4)
end

-- Toggle from HUD only (key V and [V] Friends button both fire HUDToggleMenu from HUDButtonBar)
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
	if menuName == "FriendsListGUI" then
		if not panel.Visible then applyPanelScale(panel) end
		applyResponsiveContentLayout()
		panel.Visible = not panel.Visible
		if panel.Visible then
			MobileWindowLayout.NotifyMenuOpened()
		else
			if tradeUI.Visible then
				MobileWindowLayout.SyncNpcMenuScreenGui(sg, TRADE_DESIGN_W, TRADE_DESIGN_H)
			else
				sg.IgnoreGuiInset = false
			end
			MobileWindowLayout.NotifyMenuClosed()
		end
		if panel.Visible then refreshFriendsList(); refreshOnlinePlayers() end
	end
end
getHUDToggle().Event:Connect(onHUDToggle)
playerGui.ChildAdded:Connect(function(child)
	if child.Name == "HUDToggleMenu" and child:IsA("BindableEvent") then child.Event:Connect(onHUDToggle) end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if tradeUI.Visible then
		applyTradeLayout()
	elseif panel.Visible then
		applyPanelScale(panel)
		applyResponsiveContentLayout()
	else
		sg.IgnoreGuiInset = false
	end
	if profilePopup.Visible then
		MobileWindowLayout.RestoreDesktopWindow(profilePopup, { draggable = true })
		applyFriendsProfileTitleLayout()
	end
end)

-- FIX #18: Removed fallback V key handler — HUDButtonBar is the sole keyboard handler.
-- Having both caused double-toggle (open then immediately close).

print("[FriendsListClient] Loaded - press V or click [V] Friends on HUD to open")
