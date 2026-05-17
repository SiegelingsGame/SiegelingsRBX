-- EleminionClient.lua - StarterPlayerScripts
-- Opens the Eleminion affinity UI and handles reward claims.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CreatureData = require(Modules:WaitForChild("CreatureData"))
local MobileWindowLayout = require(Modules:WaitForChild("MobileWindowLayout"))

local Notify = nil
do
	local modScript = Modules:FindFirstChild("NotificationManager")
	if modScript then
		local ok, result = pcall(require, modScript)
		if ok then
			Notify = result
		end
	end
end

local eventsFolder = ReplicatedStorage:WaitForChild("Events", 20)
if not eventsFolder then
	return
end

local openUiEvent = eventsFolder:WaitForChild("OpenEleminionUI", 15)
local statusUpdatedEvent = eventsFolder:WaitForChild("EleminionStatusUpdated", 15)
local getStatusFn = eventsFolder:WaitForChild("GetEleminionStatus", 15)
local claimRewardFn = eventsFolder:WaitForChild("ClaimEleminionQuestReward", 15)
if not openUiEvent or not statusUpdatedEvent or not getStatusFn or not claimRewardFn then
	return
end

local C = {
	bg = Color3.fromRGB(13, 16, 25),
	panel = Color3.fromRGB(22, 26, 37),
	card = Color3.fromRGB(29, 34, 48),
	cardMuted = Color3.fromRGB(19, 22, 32),
	white = Color3.fromRGB(242, 244, 248),
	muted = Color3.fromRGB(145, 152, 170),
	green = Color3.fromRGB(86, 196, 122),
	red = Color3.fromRGB(220, 90, 90),
	gold = Color3.fromRGB(240, 200, 104),
}

local DESIGN_W = 660
local DESIGN_H = 560

local screenGui
local mainFrame
local titleLabel
local subtitleLabel
local affinityLabel
local progressLabel
local rewardLabel
local affinityBar
local affinityFill
local questList
local emptyLabel
local claimButton
local claimButtonStroke
local claimButtonText
local applyTitleLayout
local applySubtitleLayout
local applyAffinityLayout
local applyProgressLayout
local applyRewardLayout

local currentElement = nil
local currentPayload = nil
local statusCache = {}
local busy = false

local function getElementColor(element)
	local info = CreatureData.Elements[element]
	return (info and info.color) or C.gold
end

local function toast(message, color, duration)
	if Notify and Notify.Toast then
		Notify.Toast(message, color, duration or 3)
	end
end

local function closeUi()
	currentElement = nil
	currentPayload = nil
	busy = false
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	mainFrame = nil
	titleLabel = nil
	subtitleLabel = nil
	affinityLabel = nil
	progressLabel = nil
	rewardLabel = nil
	affinityBar = nil
	affinityFill = nil
	questList = nil
	emptyLabel = nil
	claimButton = nil
	claimButtonStroke = nil
	claimButtonText = nil
	applyTitleLayout = nil
	applySubtitleLayout = nil
	applyAffinityLayout = nil
	applyProgressLayout = nil
	applyRewardLayout = nil
	if MobileWindowLayout and MobileWindowLayout.NotifyMenuClosed then
		MobileWindowLayout.NotifyMenuClosed()
	end
end

local function makeTextLabel(parent, props)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	label.Position = props.Position or UDim2.new()
	label.Size = props.Size or UDim2.new(1, 0, 0, 20)
	label.AutomaticSize = props.AutomaticSize or Enum.AutomaticSize.None
	label.Text = props.Text or ""
	label.TextColor3 = props.TextColor3 or C.white
	label.Font = props.Font or Enum.Font.Gotham
	label.TextSize = props.TextSize or 14
	label.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	label.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	label.TextWrapped = props.TextWrapped == true
	label.Parent = parent
	return label
end

local function applyLayout()
	if not screenGui or not mainFrame then
		return
	end

	MobileWindowLayout.SyncNpcMenuScreenGui(screenGui, DESIGN_W, DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(DESIGN_W, DESIGN_H) then
		MobileWindowLayout.ApplyWindow(
			mainFrame,
			MobileWindowLayout.GetNpcFullscreenBoundsConfig(DESIGN_W, DESIGN_H, {
				mobileDraggable = true,
			})
		)
	else
		screenGui.IgnoreGuiInset = false
		mainFrame.Size = UDim2.new(0, DESIGN_W, 0, DESIGN_H)
		mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		MobileWindowLayout.RestoreDesktopWindow(mainFrame, { draggable = true })
	end

	if applyTitleLayout then
		applyTitleLayout()
	end
	if applySubtitleLayout then
		applySubtitleLayout()
	end
	if applyAffinityLayout then
		applyAffinityLayout()
	end
	if applyProgressLayout then
		applyProgressLayout()
	end
	if applyRewardLayout then
		applyRewardLayout()
	end
end

local function setClaimButtonState(enabled, text, accent)
	if not claimButton or not claimButtonText or not claimButtonStroke then
		return
	end
	claimButton.Active = enabled
	claimButton.AutoButtonColor = enabled
	claimButton.BackgroundColor3 = enabled and Color3.fromRGB(50, 78, 56) or Color3.fromRGB(41, 45, 58)
	claimButtonText.Text = text or "Claim Reward"
	claimButtonText.TextColor3 = enabled and C.white or C.muted
	claimButtonStroke.Color = accent or (enabled and C.green or Color3.fromRGB(92, 96, 110))
	claimButtonStroke.Transparency = enabled and 0.08 or 0.35
end

local function clearQuestCards()
	if not questList then
		return
	end
	for _, child in ipairs(questList:GetChildren()) do
		if child ~= emptyLabel and not child:IsA("UIListLayout") and not child:IsA("UIPadding") then
			child:Destroy()
		end
	end
end

local function renderQuestCard(payload, questPayload, accent)
	local card = Instance.new("Frame")
	card.Name = "Quest" .. tostring(questPayload.index)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.Size = UDim2.new(1, -4, 0, 0)
	card.BackgroundColor3 = (questPayload.status == "locked") and C.cardMuted or C.card
	card.BorderSizePixel = 0
	card.Parent = questList
	Instance.new("UICorner", card).CornerRadius = UDim.new(0, 10)

	local stroke = Instance.new("UIStroke")
	stroke.Thickness = (payload.currentQuestIndex == questPayload.index and not payload.allClaimed) and 1.8 or 1
	stroke.Color = (questPayload.status == "claimed" and C.green)
		or ((payload.currentQuestIndex == questPayload.index and not payload.allClaimed) and accent or Color3.fromRGB(72, 78, 96))
	stroke.Transparency = (questPayload.status == "locked") and 0.55 or 0.2
	stroke.Parent = card

	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 12)
	padding.PaddingRight = UDim.new(0, 12)
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.Parent = card

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = card

	local topRow = Instance.new("Frame")
	topRow.BackgroundTransparency = 1
	topRow.Size = UDim2.new(1, 0, 0, 24)
	topRow.Parent = card

	makeTextLabel(topRow, {
		Size = UDim2.new(1, -110, 1, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Text = string.format("Quest %d - %s", questPayload.index, questPayload.title or ""),
	})

	local statusChip = Instance.new("TextLabel")
	statusChip.AnchorPoint = Vector2.new(1, 0)
	statusChip.Position = UDim2.new(1, 0, 0, 0)
	statusChip.Size = UDim2.new(0, 96, 1, 0)
	statusChip.BackgroundColor3 = (questPayload.status == "claimed" and Color3.fromRGB(42, 95, 60))
		or (questPayload.status == "complete" and Color3.fromRGB(90, 72, 36))
		or (questPayload.status == "active" and Color3.fromRGB(46, 58, 96))
		or Color3.fromRGB(42, 45, 58)
	statusChip.BorderSizePixel = 0
	statusChip.Font = Enum.Font.GothamBold
	statusChip.TextSize = 12
	statusChip.TextColor3 = C.white
	statusChip.Text = (questPayload.status == "claimed" and "Claimed")
		or (questPayload.status == "complete" and "Claimable")
		or (questPayload.status == "active" and "Active")
		or "Locked"
	statusChip.Parent = topRow
	Instance.new("UICorner", statusChip).CornerRadius = UDim.new(0, 7)

	if questPayload.status == "locked" then
		makeTextLabel(card, {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = C.muted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = "Finish the previous quest to reveal this Eleminion trial.",
		})
	else
		makeTextLabel(card, {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			Font = Enum.Font.Gotham,
			TextSize = 13,
			TextColor3 = C.muted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = questPayload.description or "",
		})

		makeTextLabel(card, {
			AutomaticSize = Enum.AutomaticSize.Y,
			Size = UDim2.new(1, 0, 0, 0),
			Font = Enum.Font.GothamMedium,
			TextSize = 12,
			TextColor3 = C.gold,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Text = questPayload.rewardsText or "",
		})

		for _, objective in ipairs(questPayload.objectives or {}) do
			local objectiveRow = Instance.new("Frame")
			objectiveRow.BackgroundTransparency = 1
			objectiveRow.Size = UDim2.new(1, 0, 0, 20)
			objectiveRow.Parent = card

			makeTextLabel(objectiveRow, {
				Size = UDim2.new(1, -88, 1, 0),
				Font = Enum.Font.GothamMedium,
				TextSize = 12,
				TextColor3 = objective.complete and C.green or C.white,
				Text = (objective.complete and "[Done] " or "[ ] ") .. (objective.label or ""),
			})

			makeTextLabel(objectiveRow, {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.new(1, 0, 0, 0),
				Size = UDim2.new(0, 82, 1, 0),
				Font = Enum.Font.GothamBold,
				TextSize = 12,
				TextColor3 = objective.complete and C.green or C.muted,
				TextXAlignment = Enum.TextXAlignment.Right,
				Text = objective.progressText or "",
			})
		end
	end
end

local function renderPayload(payload)
	if not payload then
		return
	end
	currentPayload = payload
	statusCache[payload.element] = payload

	if not screenGui or not mainFrame then
		return
	end

	local accent = getElementColor(payload.element)
	titleLabel.Text = payload.title or (tostring(payload.element) .. " Eleminion")
	titleLabel.TextColor3 = accent
	subtitleLabel.Text = payload.subtitle or ""
	affinityLabel.Text = string.format("Affinity %d / %d", payload.affinity or 0, payload.maxAffinity or 0)
	progressLabel.Text = payload.allClaimed and "Affinity path complete."
		or string.format("Current quest %d of %d", payload.currentQuestIndex or 1, payload.totalQuests or 0)
	rewardLabel.Text = "Main reward: " .. tostring(payload.finalRewardLabel or "Legendary Egg")
	affinityFill.BackgroundColor3 = accent
	affinityFill.Size = UDim2.new(payload.affinityPercent or 0, 0, 1, 0)

	clearQuestCards()
	questList.CanvasPosition = Vector2.new(0, 0)
	for _, questPayload in ipairs(payload.quests or {}) do
		renderQuestCard(payload, questPayload, accent)
	end

	if #(payload.quests or {}) == 0 then
		emptyLabel.Visible = true
		emptyLabel.Size = UDim2.new(1, -10, 0, 24)
		emptyLabel.Text = "No Eleminion quests are configured for this path yet."
	else
		emptyLabel.Visible = false
		emptyLabel.Size = UDim2.new(1, -10, 0, 0)
	end

	if payload.allClaimed then
		setClaimButtonState(false, "Affinity Complete", accent)
	elseif payload.canClaimCurrent then
		setClaimButtonState(true, "Claim Current Reward", accent)
	else
		setClaimButtonState(false, "Quest In Progress", accent)
	end
end

local function ensureUi()
	if screenGui and screenGui.Parent then
		return
	end

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "EleminionUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 47
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "Panel"
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BackgroundTransparency = 0.04
	mainFrame.BorderSizePixel = 0
	mainFrame.Active = true
	mainFrame.Draggable = true
	mainFrame.Parent = screenGui
	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 14)

	local frameStroke = Instance.new("UIStroke")
	frameStroke.Color = Color3.fromRGB(86, 94, 118)
	frameStroke.Thickness = 1.2
	frameStroke.Transparency = 0.2
	frameStroke.Parent = mainFrame

	titleLabel = makeTextLabel(mainFrame, {
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -28, 0, 28),
		Font = Enum.Font.GothamBlack,
		TextSize = 22,
		Text = "Eleminion",
	})

	subtitleLabel = makeTextLabel(mainFrame, {
		Position = UDim2.new(0, 14, 0, 40),
		Size = UDim2.new(1, -28, 0, 36),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = C.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Text = "",
	})

	local closeButton = Instance.new("TextButton")
	closeButton.AnchorPoint = Vector2.new(1, 0)
	closeButton.Position = UDim2.new(1, -12, 0, 10)
	closeButton.Size = UDim2.new(0, 34, 0, 30)
	closeButton.BackgroundColor3 = Color3.fromRGB(72, 46, 50)
	closeButton.BorderSizePixel = 0
	closeButton.Font = Enum.Font.GothamBold
	closeButton.TextSize = 15
	closeButton.TextColor3 = C.white
	closeButton.Text = "X"
	closeButton.Parent = mainFrame
	Instance.new("UICorner", closeButton).CornerRadius = UDim.new(0, 8)
	closeButton.MouseButton1Click:Connect(closeUi)

	local affinityCard = Instance.new("Frame")
	affinityCard.Position = UDim2.new(0, 14, 0, 86)
	affinityCard.Size = UDim2.new(1, -28, 0, 106)
	affinityCard.BackgroundColor3 = C.panel
	affinityCard.BorderSizePixel = 0
	affinityCard.Parent = mainFrame
	Instance.new("UICorner", affinityCard).CornerRadius = UDim.new(0, 10)

	affinityLabel = makeTextLabel(affinityCard, {
		Position = UDim2.new(0, 12, 0, 10),
		Size = UDim2.new(1, -24, 0, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
		Text = "Affinity 0 / 0",
	})

	progressLabel = makeTextLabel(affinityCard, {
		Position = UDim2.new(0, 12, 0, 32),
		Size = UDim2.new(1, -24, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = C.muted,
		Text = "",
	})

	affinityBar = Instance.new("Frame")
	affinityBar.Position = UDim2.new(0, 12, 0, 58)
	affinityBar.Size = UDim2.new(1, -24, 0, 14)
	affinityBar.BackgroundColor3 = Color3.fromRGB(28, 30, 44)
	affinityBar.BorderSizePixel = 0
	affinityBar.Parent = affinityCard
	Instance.new("UICorner", affinityBar).CornerRadius = UDim.new(0, 999)

	affinityFill = Instance.new("Frame")
	affinityFill.Size = UDim2.new(0, 0, 1, 0)
	affinityFill.BackgroundColor3 = C.gold
	affinityFill.BorderSizePixel = 0
	affinityFill.Parent = affinityBar
	Instance.new("UICorner", affinityFill).CornerRadius = UDim.new(0, 999)

	rewardLabel = makeTextLabel(affinityCard, {
		Position = UDim2.new(0, 12, 0, 78),
		Size = UDim2.new(1, -24, 0, 18),
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = C.gold,
		Text = "",
	})

	questList = Instance.new("ScrollingFrame")
	questList.Name = "QuestList"
	questList.Position = UDim2.new(0, 14, 0, 204)
	questList.Size = UDim2.new(1, -28, 1, -270)
	questList.BackgroundTransparency = 1
	questList.BorderSizePixel = 0
	questList.ScrollBarThickness = 6
	questList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	questList.CanvasSize = UDim2.new()
	questList.Parent = mainFrame

	local questPadding = Instance.new("UIPadding")
	questPadding.PaddingTop = UDim.new(0, 2)
	questPadding.PaddingBottom = UDim.new(0, 2)
	questPadding.Parent = questList

	local questLayout = Instance.new("UIListLayout")
	questLayout.SortOrder = Enum.SortOrder.LayoutOrder
	questLayout.Padding = UDim.new(0, 10)
	questLayout.Parent = questList

	emptyLabel = makeTextLabel(questList, {
		Size = UDim2.new(1, -10, 0, 24),
		Font = Enum.Font.GothamMedium,
		TextSize = 13,
		TextColor3 = C.muted,
		TextWrapped = true,
		Text = "",
	})
	emptyLabel.Visible = false

	claimButton = Instance.new("TextButton")
	claimButton.AnchorPoint = Vector2.new(0.5, 1)
	claimButton.Position = UDim2.new(0.5, 0, 1, -14)
	claimButton.Size = UDim2.new(1, -28, 0, 42)
	claimButton.BackgroundColor3 = Color3.fromRGB(41, 45, 58)
	claimButton.BorderSizePixel = 0
	claimButton.Text = ""
	claimButton.Parent = mainFrame
	Instance.new("UICorner", claimButton).CornerRadius = UDim.new(0, 10)

	claimButtonStroke = Instance.new("UIStroke")
	claimButtonStroke.Color = Color3.fromRGB(92, 96, 110)
	claimButtonStroke.Thickness = 1.1
	claimButtonStroke.Transparency = 0.35
	claimButtonStroke.Parent = claimButton

	claimButtonText = makeTextLabel(claimButton, {
		Position = UDim2.new(0, 5, 0, 0),
		Size = UDim2.new(1, -10, 1, 0),
		Font = Enum.Font.GothamBold,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Center,
		Text = "Quest In Progress",
	})

	claimButton.MouseButton1Click:Connect(function()
		if busy or not currentElement or not currentPayload or not currentPayload.canClaimCurrent then
			return
		end

		busy = true
		setClaimButtonState(false, "Claiming...", getElementColor(currentElement))
		local ok, success, message, payload = pcall(function()
			return claimRewardFn:InvokeServer(currentElement)
		end)
		busy = false

		if not ok then
			toast("Claim failed. Please try again.", C.red, 3)
			renderPayload(currentPayload)
			return
		end

		if success then
			toast(message or "Reward claimed!", C.green, 3)
		else
			toast(message or "Reward unavailable.", C.red, 3)
		end

		if type(payload) == "table" then
			renderPayload(payload)
		else
			renderPayload(currentPayload)
		end
	end)

	applyTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(titleLabel, {
		Position = UDim2.new(0, 14, 0, 10),
		Size = UDim2.new(1, -28, 0, 28),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	applySubtitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(subtitleLabel, {
		Position = UDim2.new(0, 14, 0, 40),
		Size = UDim2.new(1, -28, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
		mobileLeftGutter = 40,
		mobileRightGutter = 40,
	})
	applyAffinityLayout = MobileWindowLayout.MenuHeaderTitleLayout(affinityLabel, {
		Position = UDim2.new(0, 12, 0, 10),
		Size = UDim2.new(1, -24, 0, 20),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	applyProgressLayout = MobileWindowLayout.MenuHeaderTitleLayout(progressLabel, {
		Position = UDim2.new(0, 12, 0, 32),
		Size = UDim2.new(1, -24, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
	})
	applyRewardLayout = MobileWindowLayout.MenuHeaderTitleLayout(rewardLabel, {
		Position = UDim2.new(0, 12, 0, 78),
		Size = UDim2.new(1, -24, 0, 18),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	setClaimButtonState(false, "Quest In Progress", C.gold)
	applyLayout()
	if MobileWindowLayout and MobileWindowLayout.NotifyMenuOpened then
		MobileWindowLayout.NotifyMenuOpened()
	end
end

local function requestStatus(element)
	if type(element) ~= "string" or element == "" then
		return nil
	end
	local ok, payload = pcall(function()
		return getStatusFn:InvokeServer(element)
	end)
	if ok and type(payload) == "table" then
		statusCache[element] = payload
		return payload
	end
	return nil
end

local function openForElement(element)
	if type(element) ~= "string" or element == "" then
		return
	end

	currentElement = element
	ensureUi()

	local cached = statusCache[element]
	if cached then
		renderPayload(cached)
	else
		titleLabel.Text = element .. " Eleminion"
		titleLabel.TextColor3 = getElementColor(element)
		subtitleLabel.Text = "Loading affinity path..."
		affinityLabel.Text = "Affinity 0 / 0"
		progressLabel.Text = "Fetching quest progress..."
		rewardLabel.Text = ""
		clearQuestCards()
		emptyLabel.Visible = true
		emptyLabel.Size = UDim2.new(1, -10, 0, 24)
		emptyLabel.Text = "Loading..."
		setClaimButtonState(false, "Loading...", getElementColor(element))
	end

	local payload = requestStatus(element)
	if payload then
		renderPayload(payload)
	else
		toast("Unable to load Eleminion status.", C.red, 3)
	end
end

openUiEvent.OnClientEvent:Connect(function(element)
	openForElement(element)
end)

statusUpdatedEvent.OnClientEvent:Connect(function(element, payload)
	if type(element) ~= "string" or type(payload) ~= "table" then
		return
	end
	statusCache[element] = payload
	if screenGui and currentElement == element then
		renderPayload(payload)
	end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if screenGui and mainFrame then
		applyLayout()
	end
end)
