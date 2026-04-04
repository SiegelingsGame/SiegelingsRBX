-- DecorClient.client.lua — Furnish base: Furniture / Statues / Other on DecorPoints (any floor).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)
if not playerGui then return end

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local FurnitureCatalog = require(ReplicatedStorage.Modules.FurnitureCatalog)
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local placeFurnish = Events:WaitForChild("PlaceFurnish", 8)
local removeFurnish = Events:WaitForChild("RemoveFurnish", 8)
local getDecorSlots = Events:WaitForChild("GetDecorSlots", 8)

local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(22, 26, 38),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(255, 70, 60),
	gold = Color3.fromRGB(255, 200, 50),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
	tabOn = Color3.fromRGB(40, 48, 70),
	tabOff = Color3.fromRGB(28, 32, 44),
}

local RARITY_COLORS = {
	Common = Color3.fromRGB(180, 180, 180),
	Uncommon = Color3.fromRGB(80, 220, 120),
	Rare = Color3.fromRGB(60, 140, 255),
	Epic = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 200, 50),
}

local sg = Instance.new("ScreenGui")
sg.Name = "FurnishGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 35
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

local DECOR_DESIGN_W = 420
local DECOR_DESIGN_H = 520

local main = Instance.new("Frame")
main.Name = "FurnishPanel"
main.Size = UDim2.new(0, DECOR_DESIGN_W, 0, DECOR_DESIGN_H)
main.Position = UDim2.new(0.5, -DECOR_DESIGN_W / 2, 0.5, -DECOR_DESIGN_H / 2)
main.BackgroundColor3 = C.bg
main.BackgroundTransparency = 0.03
main.BorderSizePixel = 0
main.Visible = false
main.Active = true
main.Draggable = true
main.Parent = sg
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", main).Color = C.gold

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -80, 0, 28)
title.Position = UDim2.new(0, 12, 0, 6)
title.BackgroundTransparency = 1
title.Text = "FURNISH BASE"
title.TextColor3 = C.gold
title.Font = Enum.Font.GothamBlack
title.TextSize = 15
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = main

local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 6)
closeBtn.BackgroundColor3 = C.red
closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = "✕"
closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = main
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

local slotLabel = Instance.new("TextLabel")
slotLabel.Size = UDim2.new(1, -24, 0, 18)
slotLabel.Position = UDim2.new(0, 12, 0, 34)
slotLabel.BackgroundTransparency = 1
slotLabel.Text = "Slot: —"
slotLabel.TextColor3 = C.muted
slotLabel.Font = Enum.Font.GothamMedium
slotLabel.TextSize = 11
slotLabel.TextXAlignment = Enum.TextXAlignment.Left
slotLabel.Parent = main

local currentLabel = Instance.new("TextLabel")
currentLabel.Size = UDim2.new(1, -100, 0, 20)
currentLabel.Position = UDim2.new(0, 12, 0, 52)
currentLabel.BackgroundTransparency = 1
currentLabel.Text = "Current: Empty"
currentLabel.TextColor3 = C.muted
currentLabel.Font = Enum.Font.GothamMedium
currentLabel.TextSize = 11
currentLabel.TextXAlignment = Enum.TextXAlignment.Left
currentLabel.Parent = main

local removeBtn = Instance.new("TextButton")
removeBtn.Name = "RemoveBtn"
removeBtn.Size = UDim2.new(0, 80, 0, 22)
removeBtn.Position = UDim2.new(1, -92, 0, 52)
removeBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
removeBtn.Text = "REMOVE"
removeBtn.TextColor3 = C.red
removeBtn.Font = Enum.Font.GothamBold
removeBtn.TextSize = 10
removeBtn.BorderSizePixel = 0
removeBtn.Visible = false
removeBtn.Parent = main
Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 5)

local tabBar = Instance.new("Frame")
tabBar.Size = UDim2.new(1, -24, 0, 32)
tabBar.Position = UDim2.new(0, 12, 0, 78)
tabBar.BackgroundTransparency = 1
tabBar.Parent = main
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabBar

local function makeTabButton(text)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(0, 120, 1, 0)
	b.BackgroundColor3 = C.tabOff
	b.Text = text
	b.TextColor3 = C.white
	b.Font = Enum.Font.GothamBold
	b.TextSize = 11
	b.BorderSizePixel = 0
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
	b.Parent = tabBar
	return b
end

local tabFurniture = makeTabButton("Furniture")
local tabStatues = makeTabButton("Statues")
local tabOther = makeTabButton("Other")

local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -24, 1, -118)
scroll.Position = UDim2.new(0, 12, 0, 114)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = main
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 6)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

local activeSlotKey = nil
local activeTab = "Furniture"

local function applyLayout()
	MobileWindowLayout.SyncNpcMenuScreenGui(sg, DECOR_DESIGN_W, DECOR_DESIGN_H)
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(DECOR_DESIGN_W, DECOR_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(main, MobileWindowLayout.GetNpcFullscreenBoundsConfig(DECOR_DESIGN_W, DECOR_DESIGN_H))
	else
		main.AnchorPoint = Vector2.new(0.5, 0.5)
		main.Size = UDim2.new(0, DECOR_DESIGN_W, 0, DECOR_DESIGN_H)
		main.Position = UDim2.new(0.5, 0, 0.5, 0)
		MobileWindowLayout.RestoreDesktopWindow(main, { draggable = true })
	end
end

local function setTabVisual()
	tabFurniture.BackgroundColor3 = activeTab == "Furniture" and C.tabOn or C.tabOff
	tabStatues.BackgroundColor3 = activeTab == "Statues" and C.tabOn or C.tabOff
	tabOther.BackgroundColor3 = activeTab == "Other" and C.tabOn or C.tabOff
end

local function clearScroll()
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("GuiObject") then ch:Destroy() end
	end
end

local function getSlots()
	local t = {}
	if getDecorSlots then
		local ok, r = pcall(function() return getDecorSlots:InvokeServer() end)
		if ok and r then t = r end
	end
	return t
end

local function refreshHeader()
	if not activeSlotKey then return end
	slotLabel.Text = "Slot: " .. activeSlotKey:gsub("_", " · point ")
	local slots = getSlots()
	local data = slots[activeSlotKey]
	removeBtn.Visible = data ~= nil
	if not data then
		currentLabel.Text = "Current: Empty"
		currentLabel.TextColor3 = C.muted
		return
	end
	if data.kind == "statue" and data.creatureId then
		local info = CreatureData.GetById(data.creatureId)
		currentLabel.Text = "Current: Statue — " .. (info and info.displayName or data.creatureId)
		currentLabel.TextColor3 = C.green
	elseif data.kind == "furniture" and data.furnitureId then
		local fe = FurnitureCatalog.GetById(data.furnitureId)
		currentLabel.Text = "Current: " .. (fe and fe.displayName or data.furnitureId)
		currentLabel.TextColor3 = C.green
	else
		currentLabel.Text = "Current: (unknown)"
		currentLabel.TextColor3 = C.muted
	end
end

local function buildStatuesList()
	clearScroll()
	local costTable = GameConfig.DecorCostByRarity or {}
	local creatures = CreatureData.GetAll() or {}
	local rarityOrder = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
	table.sort(creatures, function(a, b)
		local oa = rarityOrder[a.rarity] or 0
		local ob = rarityOrder[b.rarity] or 0
		if oa ~= ob then return oa < ob end
		return (a.displayName or a.id or "") < (b.displayName or b.id or "")
	end)
	local layoutOrder = 0
	for _, creature in ipairs(creatures) do
		local id = creature.id
		if not id then continue end
		local rarity = creature.rarity or "Common"
		local cost = costTable[rarity] or 1000
		local rarityColor = RARITY_COLORS[rarity] or C.muted
		layoutOrder += 1

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 44)
		row.BackgroundColor3 = C.card
		row.BorderSizePixel = 0
		row.LayoutOrder = layoutOrder
		row.Parent = scroll
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.55, -8, 0, 18)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = creature.displayName or id
		nameLabel.TextColor3 = C.white
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 11
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		local infoLabel = Instance.new("TextLabel")
		infoLabel.Size = UDim2.new(0.55, -8, 0, 16)
		infoLabel.Position = UDim2.new(0, 8, 0, 24)
		infoLabel.BackgroundTransparency = 1
		infoLabel.Text = rarity .. " — " .. tostring(cost) .. " gold"
		infoLabel.TextColor3 = rarityColor
		infoLabel.Font = Enum.Font.GothamMedium
		infoLabel.TextSize = 9
		infoLabel.TextXAlignment = Enum.TextXAlignment.Left
		infoLabel.Parent = row

		local placeBtn = Instance.new("TextButton")
		placeBtn.Size = UDim2.new(0, 72, 0, 30)
		placeBtn.Position = UDim2.new(1, -80, 0.5, -15)
		placeBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
		placeBtn.Text = "PLACE"
		placeBtn.TextColor3 = C.green
		placeBtn.Font = Enum.Font.GothamBold
		placeBtn.TextSize = 10
		placeBtn.BorderSizePixel = 0
		placeBtn.Parent = row
		Instance.new("UICorner", placeBtn).CornerRadius = UDim.new(0, 6)

		placeBtn.MouseButton1Click:Connect(function()
			if activeSlotKey and placeFurnish then
				placeFurnish:FireServer(activeSlotKey, "statue", id)
				task.wait(0.25)
				refreshHeader()
			end
		end)
	end
end

local function addFurnitureRows(categories)
	local layoutOrder = 0
	for _, cat in ipairs(categories) do
		local header = Instance.new("TextLabel")
		header.Size = UDim2.new(1, 0, 0, 22)
		header.BackgroundTransparency = 1
		header.Text = cat
		header.TextColor3 = C.gold
		header.Font = Enum.Font.GothamBold
		header.TextSize = 12
		header.TextXAlignment = Enum.TextXAlignment.Left
		layoutOrder += 1
		header.LayoutOrder = layoutOrder
		header.Parent = scroll

		for _, entry in ipairs(FurnitureCatalog.GetByCategory(cat)) do
			layoutOrder += 1
			local row = Instance.new("Frame")
			row.Size = UDim2.new(1, 0, 0, 40)
			row.BackgroundColor3 = C.card
			row.BorderSizePixel = 0
			row.LayoutOrder = layoutOrder
			row.Parent = scroll
			Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

			local nl = Instance.new("TextLabel")
			nl.Size = UDim2.new(0.55, -8, 1, -8)
			nl.Position = UDim2.new(0, 8, 0, 4)
			nl.BackgroundTransparency = 1
			nl.Text = entry.displayName .. " — " .. tostring(entry.coinCost) .. " gold"
			nl.TextColor3 = C.white
			nl.Font = Enum.Font.GothamMedium
			nl.TextSize = 11
			nl.TextXAlignment = Enum.TextXAlignment.Left
			nl.Parent = row

			local buyBtn = Instance.new("TextButton")
			buyBtn.Size = UDim2.new(0, 88, 0, 28)
			buyBtn.Position = UDim2.new(1, -96, 0.5, -14)
			buyBtn.BackgroundColor3 = Color3.fromRGB(35, 55, 90)
			buyBtn.Text = "BUY"
			buyBtn.TextColor3 = C.gold
			buyBtn.Font = Enum.Font.GothamBold
			buyBtn.TextSize = 10
			buyBtn.BorderSizePixel = 0
			buyBtn.Parent = row
			Instance.new("UICorner", buyBtn).CornerRadius = UDim.new(0, 6)

			buyBtn.MouseButton1Click:Connect(function()
				if activeSlotKey and placeFurnish then
					placeFurnish:FireServer(activeSlotKey, "furniture", entry.id)
					task.wait(0.25)
					refreshHeader()
				end
			end)
		end
	end
end

local function buildFurnitureMain()
	clearScroll()
	local cats = { "Chair", "Bed", "Lamp", "Table", "Dresser", "Drawer", "Appliance" }
	addFurnitureRows(cats)
end

local function buildOtherTab()
	clearScroll()
	addFurnitureRows({ "Other" })
end

local function refreshContent()
	if activeTab == "Furniture" then
		buildFurnitureMain()
	elseif activeTab == "Statues" then
		buildStatuesList()
	else
		buildOtherTab()
	end
end

local function openAtSlot(slotKey)
	activeSlotKey = slotKey
	main.Visible = true
	applyLayout()
	MobileWindowLayout.NotifyMenuOpened()
	setTabVisual()
	refreshHeader()
	refreshContent()
end

closeBtn.MouseButton1Click:Connect(function()
	main.Visible = false
	sg.IgnoreGuiInset = false
	MobileWindowLayout.NotifyMenuClosed()
end)

removeBtn.MouseButton1Click:Connect(function()
	if activeSlotKey and removeFurnish then
		removeFurnish:FireServer(activeSlotKey)
		task.wait(0.25)
		refreshHeader()
	end
end)

tabFurniture.MouseButton1Click:Connect(function()
	activeTab = "Furniture"
	setTabVisual()
	refreshContent()
end)
tabStatues.MouseButton1Click:Connect(function()
	activeTab = "Statues"
	setTabVisual()
	refreshContent()
end)
tabOther.MouseButton1Click:Connect(function()
	activeTab = "Other"
	setTabVisual()
	refreshContent()
end)

local openFurnishEvt = Instance.new("BindableEvent")
openFurnishEvt.Name = "OpenFurnishUI"
openFurnishEvt.Parent = playerGui
openFurnishEvt.Event:Connect(function(slotKey)
	if type(slotKey) == "string" and slotKey:match("^%d+_%d+$") then
		openAtSlot(slotKey)
	elseif type(slotKey) == "number" then
		openAtSlot("4_" .. tostring(math.floor(slotKey)))
	end
end)

local openDecorLegacy = Instance.new("BindableEvent")
openDecorLegacy.Name = "OpenDecorUI"
openDecorLegacy.Parent = playerGui
openDecorLegacy.Event:Connect(function(slotIndex)
	if type(slotIndex) == "number" then
		openAtSlot("4_" .. tostring(math.floor(slotIndex)))
	end
end)

local function findOwnPlot()
	local plotsFolder = workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return nil end
	for _, pm in ipairs(plotsFolder:GetChildren()) do
		if pm:GetAttribute("OwnerUserId") == player.UserId then
			return pm
		end
	end
	return nil
end

local function floorFromAncestors(part)
	local p = part.Parent
	while p and p ~= workspace do
		local n = p.Name
		local f = string.match(n, "^Floor(%d+)$")
		if f then return tonumber(f) or 1 end
		p = p.Parent
	end
	return 1
end

local attached = {} -- [BasePart] = true

local function attachPrompt(part, slotKey)
	if attached[part] or part:FindFirstChild("DecorFurnishPrompt") then return end
	attached[part] = true
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "DecorFurnishPrompt"
	prompt.ActionText = "Furnish"
	prompt.ObjectText = "Decor " .. slotKey:gsub("_", " · ")
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = GameConfig.BaseInteractionRange or 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function()
		openFurnishEvt:Fire(slotKey)
	end)
end

local function scanPlot(plot: Instance)
	for _, desc in ipairs(plot:GetDescendants()) do
		if desc:IsA("BasePart") then
			local idx = string.match(desc.Name, "^DecorPoint(%d+)$")
			if idx then
				local floorNum = floorFromAncestors(desc)
				local slotKey = tostring(floorNum) .. "_" .. idx
				attachPrompt(desc, slotKey)
			end
		end
	end
end

local function setupPlot(plot: Instance)
	scanPlot(plot)
	plot.DescendantAdded:Connect(function(inst)
		if inst:IsA("BasePart") then
			task.defer(function()
				local idx = string.match(inst.Name, "^DecorPoint(%d+)$")
				if idx and inst.Parent then
					local floorNum = floorFromAncestors(inst)
					attachPrompt(inst, tostring(floorNum) .. "_" .. idx)
				end
			end)
		end
	end)
end

task.defer(function()
	local plot = findOwnPlot()
	if plot then
		setupPlot(plot)
	else
		local plotsFolder = workspace:WaitForChild("BasePlots", 60)
		if plotsFolder then
			local tries = 0
			while tries < 120 do
				tries += 1
				plot = findOwnPlot()
				if plot then break end
				task.wait(0.5)
			end
			if plot then
				setupPlot(plot)
			end
		end
	end
end)

MobileWindowLayout.BindViewportUpdate(function()
	if main.Visible then
		applyLayout()
	else
		sg.IgnoreGuiInset = false
	end
end)

print("[DecorClient] Furnish UI — use DecorPoints on your base (any floor)")
