-- DecorClient.client.lua - StarterPlayerScripts (LocalScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Floor 4 Creature Statue Decoration UI
--
-- When the player interacts with a DecorPoint on their own Floor 4, this script
-- shows a selection UI listing all creatures in their inventory. Selecting one
-- places it as a statue (gold sink) via the PlaceDecor remote event.
--
-- The UI shows:
--   - Creature name + rarity
--   - Gold cost (from GameConfig.DecorCostByRarity)
--   - Place / Remove buttons
--
-- Uses ProximityPrompts on DecorPoint parts. Only the base owner can interact
-- (other players see the statues but can't modify them).
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui", 10)

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then return end

local placeDecor = Events:WaitForChild("PlaceDecor", 8)
local removeDecor = Events:WaitForChild("RemoveDecor", 8)
local getDecorSlots = Events:WaitForChild("GetDecorSlots", 8)
local getInventory = Events:WaitForChild("GetInventory", 8)

-- ═══════════════════════════════════════════════════════════════════════════════
-- COLORS
-- ═══════════════════════════════════════════════════════════════════════════════
local C = {
	bg      = Color3.fromRGB(14, 16, 24),
	card    = Color3.fromRGB(22, 26, 38),
	green   = Color3.fromRGB(80, 220, 120),
	red     = Color3.fromRGB(255, 70, 60),
	gold    = Color3.fromRGB(255, 200, 50),
	muted   = Color3.fromRGB(120, 125, 140),
	white   = Color3.new(1, 1, 1),
	divider = Color3.fromRGB(40, 44, 55),
}

-- Rarity colors for labels
local RARITY_COLORS = {
	Common    = Color3.fromRGB(180, 180, 180),
	Uncommon  = Color3.fromRGB(80, 220, 120),
	Rare      = Color3.fromRGB(60, 140, 255),
	Epic      = Color3.fromRGB(180, 80, 255),
	Legendary = Color3.fromRGB(255, 200, 50),
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- SCREEN GUI
-- ═══════════════════════════════════════════════════════════════════════════════
local sg = Instance.new("ScreenGui")
sg.Name = "DecorGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 35
sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
sg.Parent = playerGui

local decorUI = Instance.new("Frame")
decorUI.Name = "DecorPanel"
decorUI.Size = UDim2.new(0, 380, 0, 460)
decorUI.Position = UDim2.new(0.5, -190, 0.5, -230)
decorUI.BackgroundColor3 = C.bg
decorUI.BackgroundTransparency = 0.03
decorUI.BorderSizePixel = 0
decorUI.Visible = false
decorUI.Active = true
decorUI.Draggable = true
decorUI.Parent = sg
Instance.new("UICorner", decorUI).CornerRadius = UDim.new(0, 14)
Instance.new("UIStroke", decorUI).Color = C.gold

-- Title
local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -44, 0, 32)
title.Position = UDim2.new(0, 12, 0, 6)
title.BackgroundTransparency = 1
title.Text = "PLACE STATUE"
title.TextColor3 = C.gold
title.Font = Enum.Font.GothamBlack
title.TextSize = 14
title.TextXAlignment = Enum.TextXAlignment.Left
title.Parent = decorUI

-- Close button
local closeBtn = Instance.new("TextButton")
closeBtn.Size = UDim2.new(0, 28, 0, 28)
closeBtn.Position = UDim2.new(1, -34, 0, 6)
closeBtn.BackgroundColor3 = C.red
closeBtn.BackgroundTransparency = 0.5
closeBtn.Text = "✕"
closeBtn.TextColor3 = C.white
closeBtn.Font = Enum.Font.GothamBold
closeBtn.TextSize = 12
closeBtn.Parent = decorUI
Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)

-- Current statue info
local currentLabel = Instance.new("TextLabel")
currentLabel.Size = UDim2.new(1, -24, 0, 20)
currentLabel.Position = UDim2.new(0, 12, 0, 40)
currentLabel.BackgroundTransparency = 1
currentLabel.Text = "Current: Empty"
currentLabel.TextColor3 = C.muted
currentLabel.Font = Enum.Font.GothamMedium
currentLabel.TextSize = 11
currentLabel.TextXAlignment = Enum.TextXAlignment.Left
currentLabel.Parent = decorUI

-- Remove button (only visible when a statue is placed)
local removeBtn = Instance.new("TextButton")
removeBtn.Name = "RemoveBtn"
removeBtn.Size = UDim2.new(0, 80, 0, 22)
removeBtn.Position = UDim2.new(1, -92, 0, 40)
removeBtn.BackgroundColor3 = Color3.fromRGB(60, 25, 25)
removeBtn.Text = "REMOVE"
removeBtn.TextColor3 = C.red
removeBtn.Font = Enum.Font.GothamBold
removeBtn.TextSize = 10
removeBtn.BorderSizePixel = 0
removeBtn.Visible = false
removeBtn.Parent = decorUI
Instance.new("UICorner", removeBtn).CornerRadius = UDim.new(0, 5)

-- Scrolling creature list
local scroll = Instance.new("ScrollingFrame")
scroll.Size = UDim2.new(1, -24, 1, -72)
scroll.Position = UDim2.new(0, 12, 0, 64)
scroll.BackgroundTransparency = 1
scroll.BorderSizePixel = 0
scroll.ScrollBarThickness = 4
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.Parent = decorUI
local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 4)
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Parent = scroll

-- ═══════════════════════════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════════════════════════
local activeSlotIndex = nil  -- which DecorPoint is being edited

-- ═══════════════════════════════════════════════════════════════════════════════
-- Mobile layout
-- ═══════════════════════════════════════════════════════════════════════════════
local function applyLayout()
	if MobileWindowLayout.IsMobile() then
		MobileWindowLayout.ApplyWindow(decorUI, {
			leftInset = 10, rightInset = 10,
			topInset = 10, bottomInset = 10,
			bottomMobileExtra = 40,
		})
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- refreshList(slotIndex)
-- Rebuilds the creature list from the player's inventory, showing each unique
-- creature with its rarity and placement cost.
-- ═══════════════════════════════════════════════════════════════════════════════
local function refreshList(slotIndex)
	activeSlotIndex = slotIndex

	-- Clear old entries
	for _, ch in ipairs(scroll:GetChildren()) do
		if ch:IsA("Frame") then ch:Destroy() end
	end

	-- Get current decor state
	local currentDecor = {}
	if getDecorSlots then
		local ok, result = pcall(function() return getDecorSlots:InvokeServer() end)
		if ok and result then currentDecor = result end
	end

	-- Show current statue for this slot
	local currentSlotData = currentDecor[slotIndex] or currentDecor[tostring(slotIndex)]
	if currentSlotData and currentSlotData.creatureId then
		local info = CreatureData.GetById(currentSlotData.creatureId)
		currentLabel.Text = "Current: " .. (info and info.displayName or currentSlotData.creatureId)
		currentLabel.TextColor3 = C.green
		removeBtn.Visible = true
	else
		currentLabel.Text = "Current: Empty"
		currentLabel.TextColor3 = C.muted
		removeBtn.Visible = false
	end

	-- Get inventory (unique creatures)
	-- getInventory returns the full data table {coins, gems, inventory, ...}
	-- The creature list is in the .inventory field
	local inventory = {}
	if getInventory then
		local ok, result = pcall(function() return getInventory:InvokeServer() end)
		if ok and result then
			inventory = result.inventory or result
		end
	end

	-- Build unique creature list from inventory
	local seen = {}
	local uniqueCreatures = {}
	for _, entry in ipairs(inventory) do
		if entry.id and not seen[entry.id] then
			seen[entry.id] = true
			local info = CreatureData.GetById(entry.id)
			if info then
				table.insert(uniqueCreatures, {
					id = entry.id,
					displayName = info.displayName or entry.id,
					rarity = info.rarity or "Common",
				})
			end
		end
	end

	-- Sort by rarity then name
	local rarityOrder = { Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5 }
	table.sort(uniqueCreatures, function(a, b)
		local ra = rarityOrder[a.rarity] or 0
		local rb = rarityOrder[b.rarity] or 0
		if ra ~= rb then return ra < rb end
		return a.displayName < b.displayName
	end)

	-- Render creature rows
	local costTable = GameConfig.DecorCostByRarity or {}

	for i, creature in ipairs(uniqueCreatures) do
		local cost = costTable[creature.rarity] or 1000
		local rarityColor = RARITY_COLORS[creature.rarity] or C.muted

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3 = C.card
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = scroll
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 7)

		-- Creature name
		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(0.5, -4, 0, 16)
		nameLabel.Position = UDim2.new(0, 8, 0, 4)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Text = creature.displayName
		nameLabel.TextColor3 = C.white
		nameLabel.Font = Enum.Font.GothamBold
		nameLabel.TextSize = 11
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.Parent = row

		-- Rarity + cost
		local infoLabel = Instance.new("TextLabel")
		infoLabel.Size = UDim2.new(0.5, -4, 0, 14)
		infoLabel.Position = UDim2.new(0, 8, 0, 22)
		infoLabel.BackgroundTransparency = 1
		infoLabel.Text = creature.rarity .. " — " .. tostring(cost) .. " gold"
		infoLabel.TextColor3 = rarityColor
		infoLabel.Font = Enum.Font.GothamMedium
		infoLabel.TextSize = 9
		infoLabel.TextXAlignment = Enum.TextXAlignment.Left
		infoLabel.Parent = row

		-- Place button
		local placeBtn = Instance.new("TextButton")
		placeBtn.Size = UDim2.new(0, 70, 0, 28)
		placeBtn.Position = UDim2.new(1, -78, 0.5, -14)
		placeBtn.BackgroundColor3 = Color3.fromRGB(30, 70, 45)
		placeBtn.Text = "PLACE"
		placeBtn.TextColor3 = C.green
		placeBtn.Font = Enum.Font.GothamBold
		placeBtn.TextSize = 10
		placeBtn.BorderSizePixel = 0
		placeBtn.Parent = row
		Instance.new("UICorner", placeBtn).CornerRadius = UDim.new(0, 6)

		placeBtn.MouseButton1Click:Connect(function()
			if placeDecor then
				placeDecor:FireServer(slotIndex, creature.id)
				task.wait(0.3)
				refreshList(slotIndex)
			end
		end)
	end

	if #uniqueCreatures == 0 then
		local emptyLabel = Instance.new("TextLabel")
		emptyLabel.Size = UDim2.new(1, 0, 0, 40)
		emptyLabel.BackgroundTransparency = 1
		emptyLabel.Text = "No creatures in inventory"
		emptyLabel.TextColor3 = C.muted
		emptyLabel.Font = Enum.Font.GothamMedium
		emptyLabel.TextSize = 11
		emptyLabel.Parent = scroll
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- EVENT HANDLERS
-- ═══════════════════════════════════════════════════════════════════════════════

closeBtn.MouseButton1Click:Connect(function()
	decorUI.Visible = false
	MobileWindowLayout.NotifyMenuClosed()
end)

removeBtn.MouseButton1Click:Connect(function()
	if activeSlotIndex and removeDecor then
		removeDecor:FireServer(activeSlotIndex)
		task.wait(0.3)
		refreshList(activeSlotIndex)
	end
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- BINDABLE EVENT: OpenDecorUI
-- Other scripts (e.g. ProximityPrompt handler) can fire this to open the decor
-- panel for a specific slot. A BindableEvent is created in PlayerGui for this.
-- ═══════════════════════════════════════════════════════════════════════════════
local openDecorEvt = Instance.new("BindableEvent")
openDecorEvt.Name = "OpenDecorUI"
openDecorEvt.Parent = playerGui

openDecorEvt.Event:Connect(function(slotIndex)
	if type(slotIndex) ~= "number" then return end
	decorUI.Visible = true
	applyLayout()
	MobileWindowLayout.NotifyMenuOpened()
	refreshList(slotIndex)
end)

-- ═══════════════════════════════════════════════════════════════════════════════
-- PROXIMITY PROMPT SETUP
-- Listens for DecorPoint parts that get ProximityPrompts (created by server or
-- already in workspace). When the player triggers one on THEIR OWN plot, opens
-- the decor UI for that slot index.
-- ═══════════════════════════════════════════════════════════════════════════════

-- Find the player's own plot
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

-- Scan for DecorPoints and create client-side ProximityPrompts
task.defer(function()
	-- Wait for plot assignment
	task.wait(5)

	local plot = findOwnPlot()
	if not plot then return end

	local floor4 = plot:FindFirstChild("Floor4")
	if not floor4 then
		-- Watch for Floor4 to appear (after purchase)
		plot.ChildAdded:Connect(function(child)
			if child.Name == "Floor4" then
				task.wait(1)
				-- Re-scan
				for _, desc in ipairs(child:GetDescendants()) do
					if desc:IsA("BasePart") and desc.Name:match("^DecorPoint%d+$") then
						local idx = tonumber(desc.Name:match("(%d+)$"))
						if idx and not desc:FindFirstChildOfClass("ProximityPrompt") then
							local prompt = Instance.new("ProximityPrompt")
							prompt.Name = "DecorPrompt"
							prompt.ActionText = "Decorate"
							prompt.ObjectText = "Statue Pedestal " .. idx
							prompt.HoldDuration = 0
							prompt.MaxActivationDistance = 8
							prompt.RequiresLineOfSight = false
							prompt.Parent = desc
							prompt.Triggered:Connect(function()
								openDecorEvt:Fire(idx)
							end)
						end
					end
				end
			end
		end)
		return
	end

	-- Floor4 exists — set up prompts on DecorPoints
	for _, desc in ipairs(floor4:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:match("^DecorPoint%d+$") then
			local idx = tonumber(desc.Name:match("(%d+)$"))
			if idx and not desc:FindFirstChildOfClass("ProximityPrompt") then
				local prompt = Instance.new("ProximityPrompt")
				prompt.Name = "DecorPrompt"
				prompt.ActionText = "Decorate"
				prompt.ObjectText = "Statue Pedestal " .. idx
				prompt.HoldDuration = 0
				prompt.MaxActivationDistance = 8
				prompt.RequiresLineOfSight = false
				prompt.Parent = desc
				prompt.Triggered:Connect(function()
					openDecorEvt:Fire(idx)
				end)
			end
		end
	end
end)

print("[DecorClient] Loaded — interact with DecorPoints on your Floor 4 to place creature statues")
