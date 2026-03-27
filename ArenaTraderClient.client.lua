-- ArenaTraderClient — Arena Hub "Curator" codex-style shop UI.
-- Server opens this by firing ArenaTraderStock when the player activates TraderPrompt.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local Modules = ReplicatedStorage:WaitForChild("Modules")
local MobileWindowLayout = require(Modules:WaitForChild("MobileWindowLayout"))

local CodexModelViewer = nil
do
	local modScript = Modules:FindFirstChild("CodexModelViewer")
	if modScript then
		local ok, result = pcall(require, modScript)
		if ok then
			CodexModelViewer = result
		end
	end
end

local Notify = nil
do
	local n = Modules:FindFirstChild("NotificationManager")
	if n then
		local ok, result = pcall(require, n)
		if ok then
			Notify = result
		end
	end
end

local eventsFolder = ReplicatedStorage:WaitForChild("Events", 20)
if not eventsFolder then
	return
end

local stockEvt = eventsFolder:WaitForChild("ArenaTraderStock", 15)
local buyFn = eventsFolder:WaitForChild("BuyArenaTraderCreature", 15)
if not stockEvt or not buyFn then
	return
end

local C = {
	bg = Color3.fromRGB(12, 14, 22),
	card = Color3.fromRGB(22, 24, 34),
	accent = Color3.fromRGB(220, 190, 120),
	muted = Color3.fromRGB(120, 128, 145),
	white = Color3.fromRGB(240, 242, 248),
	coin = Color3.fromRGB(255, 200, 70),
	gem = Color3.fromRGB(160, 120, 255),
	green = Color3.fromRGB(70, 190, 110),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(170, 170, 170),
	Uncommon = Color3.fromRGB(75, 200, 95),
	Rare = Color3.fromRGB(60, 140, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 180, 40),
}

local screenGui
local mainFrame
local stockUISession = 0
local viewers = {}
local busy = false
local currentPayload

local function destroyViewers()
	for _, v in ipairs(viewers) do
		if v and v.Destroy then
			pcall(function()
				v:Destroy()
			end)
		end
	end
	viewers = {}
end

local function closeUI()
	countdownAbort = true
	destroyViewers()
	if screenGui then
		screenGui:Destroy()
		screenGui = nil
	end
	mainFrame = nil
	currentPayload = nil
	if MobileWindowLayout and MobileWindowLayout.NotifyMenuClosed then
		MobileWindowLayout.NotifyMenuClosed()
	end
	busy = false
end

local function formatTimeLeft(endsAt)
	local t = (endsAt or 0) - os.time()
	if t < 0 then
		t = 0
	end
	local h = math.floor(t / 3600)
	local m = math.floor((t % 3600) / 60)
	local s = t % 60
	if h > 0 then
		return string.format("%dh %dm", h, m)
	end
	if m > 0 then
		return string.format("%dm %ds", m, s)
	end
	return string.format("%ds", s)
end

local function applyLayout()
	if not mainFrame then
		return
	end
	if MobileWindowLayout.IsMobile() then
		MobileWindowLayout.ApplyWindow(mainFrame, {
			leftInset = 12,
			rightInset = 12,
			topInset = 8,
			bottomInset = 14,
			bottomMobileExtra = 18,
			mobileDraggable = true,
		})
		mainFrame.AnchorPoint = Vector2.new(0, 0)
		return
	end
	mainFrame.Size = UDim2.new(0, 560, 0, 520)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	MobileWindowLayout.RestoreDesktopWindow(mainFrame, { draggable = true })
end

local function makeButton(parent, text, bg, pos, size)
	local b = Instance.new("TextButton")
	b.Size = size
	b.Position = pos
	b.BackgroundColor3 = bg
	b.BackgroundTransparency = 0.08
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = C.white
	b.Font = Enum.Font.GothamBold
	b.TextSize = 13
	b.AutoButtonColor = true
	b.Parent = parent
	local c = Instance.new("UICorner", b)
	c.CornerRadius = UDim.new(0, 6)
	return b
end

local function showTraderUI(payload)
	closeUI()
	local session = stockUISession
	currentPayload = payload

	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "ArenaTraderUI"
	screenGui.ResetOnSpawn = false
	screenGui.DisplayOrder = 46
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "TraderPanel"
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BackgroundTransparency = 0.04
	mainFrame.BorderSizePixel = 0
	mainFrame.Active = true
	mainFrame.Draggable = true
	mainFrame.Parent = screenGui
	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
	local stroke = Instance.new("UIStroke", mainFrame)
	stroke.Color = C.accent
	stroke.Thickness = 1.2
	stroke.Transparency = 0.35

	applyLayout()

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, -24, 0, 28)
	title.Position = UDim2.new(0, 12, 0, 10)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 22
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.TextColor3 = C.accent
	title.Text = "Codex Exchange"
	title.Parent = mainFrame

	local sub = Instance.new("TextLabel")
	sub.Name = "Subtitle"
	sub.Size = UDim2.new(1, -24, 0, 18)
	sub.Position = UDim2.new(0, 12, 0, 38)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamMedium
	sub.TextSize = 14
	sub.TextXAlignment = Enum.TextXAlignment.Left
	sub.TextColor3 = C.muted
	sub.Text = "The Curator — Common through Legendary (incl. Epic), Silver/Gold variants — rotation refreshes periodically"
	sub.Parent = mainFrame

	local countdown = Instance.new("TextLabel")
	countdown.Name = "Countdown"
	countdown.Size = UDim2.new(1, -24, 0, 18)
	countdown.Position = UDim2.new(0, 12, 0, 56)
	countdown.BackgroundTransparency = 1
	countdown.Font = Enum.Font.Gotham
	countdown.TextSize = 13
	countdown.TextXAlignment = Enum.TextXAlignment.Left
	countdown.TextColor3 = Color3.fromRGB(180, 185, 200)
	countdown.Text = "Next rotation: " .. formatTimeLeft(payload.rotationEndsAt)
	countdown.Parent = mainFrame

	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "List"
	scroll.Size = UDim2.new(1, -24, 1, -118)
	scroll.Position = UDim2.new(0, 12, 0, 84)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = mainFrame

	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 10)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = scroll

	local slots = payload.slots or {}
	for _, slot in ipairs(slots) do
		local card = Instance.new("Frame")
		card.Name = "Slot" .. tostring(slot.slotIndex)
		card.Size = UDim2.new(1, 0, 0, 112)
		card.BackgroundColor3 = C.card
		card.BorderSizePixel = 0
		card.Parent = scroll
		Instance.new("UICorner", card).CornerRadius = UDim.new(0, 8)

		local rStroke = Instance.new("UIStroke", card)
		rStroke.Color = RARITY_COLORS[slot.rarity] or C.muted
		rStroke.Transparency = 0.5
		rStroke.Thickness = 1

		local vpHolder = Instance.new("Frame")
		vpHolder.Size = UDim2.new(0, 100, 0, 100)
		vpHolder.Position = UDim2.new(0, 6, 0, 6)
		vpHolder.BackgroundColor3 = Color3.fromRGB(18, 20, 28)
		vpHolder.BorderSizePixel = 0
		vpHolder.Parent = card
		Instance.new("UICorner", vpHolder).CornerRadius = UDim.new(0, 6)

		if CodexModelViewer and slot.creatureId then
			local viewer = CodexModelViewer.new(vpHolder, {
				size = UDim2.new(1, 0, 1, 0),
				autoRotate = true,
				interactable = true,
			})
			viewer:SetCreature(slot.creatureId)
			if viewer.SetAutoRotate then
				viewer:SetAutoRotate(true)
			end
			table.insert(viewers, viewer)
		end

		local nameLbl = Instance.new("TextLabel")
		nameLbl.Size = UDim2.new(1, -230, 0, 22)
		nameLbl.Position = UDim2.new(0, 114, 0, 8)
		nameLbl.BackgroundTransparency = 1
		nameLbl.Font = Enum.Font.GothamBold
		nameLbl.TextSize = 17
		nameLbl.TextXAlignment = Enum.TextXAlignment.Left
		nameLbl.TextColor3 = C.white
		local variant = (slot.variant == "Silver" or slot.variant == "Gold") and slot.variant or nil
		local variantSuffix = variant and (" · " .. variant) or ""
		nameLbl.Text = (slot.displayName or slot.creatureId or "?") .. variantSuffix
		nameLbl.Parent = card

		local meta = Instance.new("TextLabel")
		meta.Size = UDim2.new(1, -230, 0, 40)
		meta.Position = UDim2.new(0, 114, 0, 32)
		meta.BackgroundTransparency = 1
		meta.Font = Enum.Font.Gotham
		meta.TextSize = 13
		meta.TextXAlignment = Enum.TextXAlignment.Left
		meta.TextYAlignment = Enum.TextYAlignment.Top
		meta.TextColor3 = C.muted
		meta.TextWrapped = true
		local el = slot.element or ""
		meta.Text = (slot.rarity or "") .. (el ~= "" and (" · " .. el) or "") .. (variant and (" · Variant: " .. variant) or "")
		meta.Parent = card

		local coinBtn = makeButton(
			card,
			tostring(slot.coinCost) .. " coins",
			Color3.fromRGB(55, 48, 28),
			UDim2.new(1, -8, 0, 8),
			UDim2.new(0, 112, 0, 34)
		)
		coinBtn.AnchorPoint = Vector2.new(1, 0)
		coinBtn.TextColor3 = C.coin

		local gemBtn = makeButton(
			card,
			tostring(slot.gemCost) .. " diamonds",
			Color3.fromRGB(40, 32, 58),
			UDim2.new(1, -8, 0, 48),
			UDim2.new(0, 112, 0, 34)
		)
		gemBtn.AnchorPoint = Vector2.new(1, 0)
		gemBtn.TextColor3 = C.gem

		local function doBuy(paymentType)
			if busy then
				return
			end
			busy = true
			local ok, msg = buyFn:InvokeServer(slot.slotIndex, paymentType, slot.creatureId, payload.stockId)
			busy = false
			if ok then
				if Notify and Notify.Toast then
					Notify.Toast(msg or "Purchased!", C.green, 2.5)
				end
				closeUI()
			else
				if Notify and Notify.Toast then
					Notify.Toast(msg or "Purchase failed", Color3.fromRGB(255, 90, 80), 3)
				end
			end
		end

		coinBtn.MouseButton1Click:Connect(function()
			doBuy("coins")
		end)
		gemBtn.MouseButton1Click:Connect(function()
			doBuy("gems")
		end)
	end

	local closeBtn = makeButton(mainFrame, "Close", Color3.fromRGB(55, 58, 72), UDim2.new(1, -100, 0, 12), UDim2.new(0, 88, 0, 30))
	closeBtn.MouseButton1Click:Connect(closeUI)

	task.spawn(function()
		while session == stockUISession do
			if not countdown or not countdown.Parent then
				break
			end
			countdown.Text = "Next rotation: " .. formatTimeLeft(payload.rotationEndsAt)
			task.wait(1)
		end
	end)

	if MobileWindowLayout and MobileWindowLayout.NotifyMenuOpened then
		MobileWindowLayout.NotifyMenuOpened()
	end
end

stockEvt.OnClientEvent:Connect(function(payload)
	if type(payload) ~= "table" then
		return
	end
	showTraderUI(payload)
end)
