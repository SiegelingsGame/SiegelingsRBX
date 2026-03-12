-- CombinerRecyclerClient.lua - LocalScript (StarterPlayerScripts)
-- Opens Combine UI when interacting with MCombiner, Recycler UI when interacting with MRecycler.
-- Combine: select 3 same creature + same variant → 1 next variant (Silver/Gold/Legend).
-- Recycler: select 3+ same creature → trade for 1 random creature 1 rarity tier higher.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local LOG = "[CombinerRecyclerClient]"

local Events = ReplicatedStorage:WaitForChild("Events", 15)
if not Events then
	warn(LOG .. " Events folder not found")
	return
end

-- Wait for remotes (server may create them after client loads)
local getInventory = Events:WaitForChild("GetInventory", 15)
if not getInventory then
	warn(LOG .. " GetInventory remote not found")
	return
end

local openCombiner = Events:WaitForChild("OpenCombiner", 15)
local openRecycler = Events:WaitForChild("OpenRecycler", 15)
local combineCreatures = Events:WaitForChild("CombineCreatures", 10)
local combineResult = Events:WaitForChild("CombineResult", 10)
local recycleDuplicates = Events:WaitForChild("RecycleDuplicates", 10)
local recycleResult = Events:WaitForChild("RecycleResult", 10)

local C = {
	bg = Color3.fromRGB(18, 22, 32),
	card = Color3.fromRGB(28, 34, 48),
	coin = Color3.fromRGB(255, 200, 50),
	green = Color3.fromRGB(80, 220, 120),
	red = Color3.fromRGB(255, 70, 60),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
}

local VARIANT_COLORS = CreatureData.VariantColors or {
	Normal = Color3.fromRGB(200, 200, 200),
	Silver = Color3.fromRGB(192, 192, 192),
	Gold  = Color3.fromRGB(255, 215, 0),
	Legend = Color3.fromRGB(255, 100, 255),
}

local W, H = 480, 520
local ROW_H = 44
local SLOT_H = 40
local MAX_COMBINE_SLOTS = 3

local sg = Instance.new("ScreenGui")
sg.Name = "CombinerRecyclerGUI"
sg.ResetOnSpawn = false
sg.DisplayOrder = 100
sg.IgnoreGuiInset = false
sg.Parent = playerGui

-- Helper: can this entry be added given current selection? (duplicate-type rules)
local function canAddToSelection(entry, selected, invData, isCombiner)
	if not invData or not invData.inventory then return false end
	local uidToEntry = {}
	for _, e in ipairs(invData.inventory) do uidToEntry[e.uid] = e end
	if #selected == 0 then return true end
	local first = uidToEntry[selected[1]]
	if not first then return true end
	if isCombiner then
		return entry.id == first.id and (entry.variant or "Normal") == (first.variant or "Normal")
	else
		return entry.id == first.id
	end
end

-- Shared: build a modal panel with slots + full inventory list; tap to add (duplicates only).
local function buildPanel(name, titleText, actionText, onAction, validateSelection, getInvData)
	local isCombiner = (name == "CombinePanel")
	local maxSlots = isCombiner and MAX_COMBINE_SLOTS or 999

	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = UDim2.new(0, W, 0, H)
	frame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
	frame.BackgroundColor3 = C.bg
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Active = true
	frame.Draggable = true
	frame.Parent = sg
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 12)

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -80, 0, 36)
	title.Position = UDim2.new(0, 12, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = titleText
	title.TextColor3 = C.coin
	title.Font = Enum.Font.GothamBold
	title.TextSize = 16
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = frame

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 56, 0, 28)
	closeBtn.Position = UDim2.new(1, -68, 0, 10)
	closeBtn.BackgroundColor3 = Color3.fromRGB(60, 55, 50)
	closeBtn.Text = "X"
	closeBtn.TextColor3 = C.white
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.TextSize = 14
	closeBtn.Parent = frame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
	closeBtn.MouseButton1Click:Connect(function() frame.Visible = false end)

	-- Slots row: shows selected creatures (tap to remove)
	local slotsRow = Instance.new("Frame")
	slotsRow.Name = "SlotsRow"
	slotsRow.Size = UDim2.new(1, -24, 0, SLOT_H + 28)
	slotsRow.Position = UDim2.new(0, 12, 0, 44)
	slotsRow.BackgroundTransparency = 1
	slotsRow.Parent = frame

	local slotsLabel = Instance.new("TextLabel")
	slotsLabel.Name = "SlotsLabel"
	slotsLabel.Size = UDim2.new(1, -70, 0, 18)
	slotsLabel.Position = UDim2.new(0, 0, 0, 0)
	slotsLabel.BackgroundTransparency = 1
	slotsLabel.Text = isCombiner and "Select 3 same creature + same variant (tap below to add)" or "Select 3+ same creature (tap below to add)"
	slotsLabel.TextColor3 = C.muted
	slotsLabel.Font = Enum.Font.Gotham
	slotsLabel.TextSize = 11
	slotsLabel.TextXAlignment = Enum.TextXAlignment.Left
	slotsLabel.Parent = slotsRow

	local clearBtn = Instance.new("TextButton")
	clearBtn.Size = UDim2.new(0, 56, 0, 22)
	clearBtn.Position = UDim2.new(1, -58, 0, -2)
	clearBtn.BackgroundColor3 = Color3.fromRGB(60, 55, 50)
	clearBtn.Text = "Clear"
	clearBtn.TextColor3 = C.muted
	clearBtn.Font = Enum.Font.Gotham
	clearBtn.TextSize = 10
	clearBtn.Parent = slotsRow
	Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 4)
	clearBtn.MouseButton1Click:Connect(function()
		selected = {}
		selectedOrder = {}
		updateSlotsAndButton()
		refreshList()
	end)

	local slotsContainer = Instance.new("Frame")
	slotsContainer.Name = "SlotsContainer"
	slotsContainer.Size = UDim2.new(1, 0, 0, SLOT_H)
	slotsContainer.Position = UDim2.new(0, 0, 0, 20)
	slotsContainer.BackgroundTransparency = 1
	slotsContainer.Parent = slotsRow

	local slotsLayout = Instance.new("UIListLayout")
	slotsLayout.FillDirection = Enum.FillDirection.Horizontal
	slotsLayout.Padding = UDim.new(0, 6)
	slotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	slotsLayout.Parent = slotsContainer

	local listScroll = Instance.new("ScrollingFrame")
	listScroll.Name = "ListScroll"
	listScroll.Size = UDim2.new(1, -24, 0, H - 120 - (SLOT_H + 28))
	listScroll.Position = UDim2.new(0, 12, 0, 44 + SLOT_H + 28 + 8)
	listScroll.BackgroundColor3 = C.card
	listScroll.BorderSizePixel = 0
	listScroll.ScrollBarThickness = 6
	listScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	listScroll.Parent = frame
	Instance.new("UICorner", listScroll).CornerRadius = UDim.new(0, 8)

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 4)
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = listScroll

	local actionBtn = Instance.new("TextButton")
	actionBtn.Size = UDim2.new(1, -24, 0, 44)
	actionBtn.Position = UDim2.new(0, 12, 1, -56)
	actionBtn.BackgroundColor3 = Color3.fromRGB(80, 75, 70)
	actionBtn.Text = actionText
	actionBtn.TextColor3 = Color3.new(0.5, 0.5, 0.5)
	actionBtn.Font = Enum.Font.GothamBold
	actionBtn.TextSize = 14
	actionBtn.Parent = frame
	Instance.new("UICorner", actionBtn).CornerRadius = UDim.new(0, 8)

	local selected = {}
	local selectedOrder = {}

	local function updateSlotsAndButton()
		-- Rebuild slot chips from selectedOrder (uid list)
		for _, c in ipairs(slotsContainer:GetChildren()) do
			if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
		end
		local invData = getInvData and getInvData()
		local uidToEntry = {}
		if invData and invData.inventory then
			for _, e in ipairs(invData.inventory) do uidToEntry[e.uid] = e end
		end
		for _, uid in ipairs(selectedOrder) do
			local entry = uidToEntry[uid]
			local cr = entry and CreatureData.GetById(entry.id)
			local label = entry and (cr and (cr.displayName or entry.id) or entry.id) .. (isCombiner and (" · " .. (entry.variant or "Normal")) or "") or "?"
			local chip = Instance.new("TextButton")
			chip.Size = UDim2.new(0, 120, 0, SLOT_H - 4)
			chip.BackgroundColor3 = C.card
			chip.BorderSizePixel = 0
			chip.Text = label
			chip.TextColor3 = C.white
			chip.Font = Enum.Font.GothamMedium
			chip.TextSize = 11
			chip.AutoButtonColor = true
			chip.Parent = slotsContainer
			Instance.new("UICorner", chip).CornerRadius = UDim.new(0, 6)
			chip.MouseButton1Click:Connect(function()
				local idx = table.find(selectedOrder, uid)
				if idx then
					table.remove(selectedOrder, idx)
					selected[uid] = nil
					updateSlotsAndButton()
					refreshList()
				end
			end)
		end
		local ok, err = validateSelection and validateSelection(selectedOrder, invData)
		actionBtn.BackgroundColor3 = ok and C.green or Color3.fromRGB(80, 75, 70)
		actionBtn.TextColor3 = ok and Color3.new(0.2, 0.2, 0.2) or Color3.new(0.5, 0.5, 0.5)
	end

	local function addStatusRow(text, isRetryButton)
		local row = Instance.new(isRetryButton and "TextButton" or "Frame")
		row.Size = UDim2.new(1, -8, 0, ROW_H)
		row.BackgroundColor3 = Color3.fromRGB(35, 40, 55)
		row.BorderSizePixel = 0
		row.LayoutOrder = 0
		row.Parent = listScroll
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, -12, 1, -8)
		lbl.Position = UDim2.new(0, 6, 0, 4)
		lbl.BackgroundTransparency = 1
		lbl.Text = text
		lbl.TextColor3 = C.muted
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 12
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.TextWrapped = true
		lbl.Parent = row
		if isRetryButton and row:IsA("TextButton") then
			row.MouseButton1Click:Connect(function() refreshList() end)
		end
	end

	local function refreshList()
		for _, c in ipairs(listScroll:GetChildren()) do
			if c:IsA("Frame") or c:IsA("TextButton") then c:Destroy() end
		end
		local invData
		local ok, err = pcall(function()
			invData = getInvData and getInvData()
		end)
		if not ok or not invData then
			print(LOG .. " refreshList: getInvData failed ok=" .. tostring(ok) .. " invData=" .. tostring(invData) .. (err and (" err=" .. tostring(err)) or ""))
			addStatusRow("Could not load inventory. Tap to retry.", true)
			task.defer(function() listScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 4) end)
			updateSlotsAndButton()
			return
		end
		local list = type(invData.inventory) == "table" and invData.inventory or {}
		print(LOG .. " refreshList: inventory count=" .. #list)
		if #list == 0 then
			addStatusRow("No creatures in your inventory.", false)
			task.defer(function() listScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 4) end)
			updateSlotsAndButton()
			return
		end
		for i, entry in ipairs(list) do
			local cr = CreatureData.GetById(entry.id)
			if not cr then continue end
			local variant = entry.variant or "Normal"
			local variantColor = VARIANT_COLORS[variant] or C.muted
			local canAdd = canAddToSelection(entry, selectedOrder, invData, isCombiner)
			local atCapacity = #selectedOrder >= maxSlots
			local isSelected = selected[entry.uid]
			local enabled = (canAdd and not atCapacity) or isSelected

			local line = Instance.new("TextButton")
			line.Size = UDim2.new(1, -8, 0, ROW_H)
			line.BackgroundColor3 = enabled and Color3.fromRGB(35, 40, 55) or Color3.fromRGB(28, 28, 35)
			line.BorderSizePixel = 0
			line.Text = ""
			line.LayoutOrder = i
			line.Active = enabled
			line.AutoButtonColor = enabled
			line.Parent = listScroll
			Instance.new("UICorner", line).CornerRadius = UDim.new(0, 6)

			local colorBar = Instance.new("Frame")
			colorBar.Size = UDim2.new(0, 4, 1, -8)
			colorBar.Position = UDim2.new(0, 4, 0, 4)
			colorBar.BackgroundColor3 = variantColor
			colorBar.BorderSizePixel = 0
			colorBar.Parent = line
			Instance.new("UICorner", colorBar).CornerRadius = UDim.new(1, 0)

			local nameLbl = Instance.new("TextLabel")
			nameLbl.Size = UDim2.new(0.65, -16, 1, -4)
			nameLbl.Position = UDim2.new(0, 14, 0, 2)
			nameLbl.BackgroundTransparency = 1
			nameLbl.Text = (cr.displayName or entry.id) .. (isCombiner and (" · " .. variant) or "")
			nameLbl.TextColor3 = enabled and C.white or C.muted
			nameLbl.Font = Enum.Font.GothamMedium
			nameLbl.TextSize = 12
			nameLbl.TextXAlignment = Enum.TextXAlignment.Left
			nameLbl.Parent = line

			local hintText = "Tap to add"
			if isSelected then hintText = "✓ In slot"
			elseif not canAdd and #selectedOrder > 0 then hintText = "Different type"
			elseif atCapacity and not isSelected then hintText = "Full"
			end
			local hintLbl = Instance.new("TextLabel")
			hintLbl.Size = UDim2.new(0.3, -8, 1, -4)
			hintLbl.Position = UDim2.new(0.7, 0, 0, 2)
			hintLbl.BackgroundTransparency = 1
			hintLbl.Text = hintText
			hintLbl.TextColor3 = isSelected and C.green or (not canAdd and #selectedOrder > 0) and C.red or C.muted
			hintLbl.Font = Enum.Font.Gotham
			hintLbl.TextSize = 10
			hintLbl.Parent = line

			line.MouseButton1Click:Connect(function()
				if not enabled then return end
				if isSelected then
					local idx = table.find(selectedOrder, entry.uid)
					if idx then
						table.remove(selectedOrder, idx)
						selected[entry.uid] = nil
					end
				else
					if #selectedOrder >= maxSlots then return end
					if not canAdd then return end
					table.insert(selectedOrder, entry.uid)
					selected[entry.uid] = true
				end
				updateSlotsAndButton()
				refreshList()
			end)
		end
		task.defer(function()
			listScroll.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 4)
		end)
		updateSlotsAndButton()
	end

	actionBtn.MouseButton1Click:Connect(function()
		local invData = getInvData and getInvData()
		if not invData then
			print(LOG .. " action click: getInvData returned nil")
			return
		end
		local ok, err = validateSelection and validateSelection(selectedOrder, invData)
		if not ok then
			print(LOG .. " action click: validation failed " .. tostring(err))
			Notify.Toast(err or "Invalid selection", C.red, 3)
			return
		end
		print(LOG .. " action click: sending uids count=" .. #selectedOrder .. " uids=" .. table.concat(selectedOrder, ","))
		onAction(selectedOrder)
	end)

	-- Don't attach refreshList to frame (Roblox Instances can't store arbitrary functions)
	return frame, refreshList
end

-- Combine panel: 3 same id + same variant
local combinePanel = nil
local combineRefreshList = nil
local recyclePanel = nil
local recycleRefreshList = nil

if openCombiner and combineCreatures and combineResult then
	combinePanel, combineRefreshList = buildPanel(
		"CombinePanel",
		"Combiner — 3 same creature + variant → 1 next tier",
		"Combine (3 selected)",
		function(uids)
			print(LOG .. " FireServer CombineCreatures uids=" .. table.concat(uids or {}, ","))
			combineCreatures:FireServer(uids)
		end,
		function(sel, invData)
			if #sel ~= 3 then return false, "Select exactly 3 creatures" end
			local uidToEntry = {}
			for _, e in ipairs(invData.inventory) do uidToEntry[e.uid] = e end
			local id, variant = nil, nil
			for _, uid in ipairs(sel) do
				local e = uidToEntry[uid]
				if not e then return false, "Creature not found" end
				if id and (e.id ~= id or (e.variant or "Normal") ~= variant) then
					return false, "All 3 must be same creature and same variant (e.g. all Silver)"
				end
				id = e.id
				variant = e.variant or "Normal"
			end
			if variant == "Legend" then return false, "Legend cannot combine further" end
			return true
		end,
		function()
			local ok, r = pcall(function() return getInventory:InvokeServer() end)
			return ok and r
		end
	)
	openCombiner.OnClientEvent:Connect(function()
		print(LOG .. " OpenCombiner received")
		if combinePanel and combineRefreshList then
			combinePanel.Visible = true
			combineRefreshList()
			task.delay(0.6, function()
				if combinePanel and combinePanel.Visible and combineRefreshList then
					combineRefreshList()
				end
			end)
		else
			warn(LOG .. " OpenCombiner received but combinePanel or combineRefreshList is nil")
		end
	end)
	combineResult.OnClientEvent:Connect(function(success, payload)
		print(LOG .. " CombineResult received success=" .. tostring(success) .. " payload=" .. tostring(payload))
		if combinePanel then combinePanel.Visible = false end
		if success then
			Notify.Toast("Combined! New variant creature added.", C.green, 3)
		else
			Notify.Toast(payload or "Combine failed", C.red, 3)
		end
	end)
end

-- Recycler panel: 3+ same creature → 1 tier higher
if openRecycler and recycleDuplicates and recycleResult then
	local minRecycle = GameConfig.RecyclerDuplicateCount or 3
	recyclePanel, recycleRefreshList = buildPanel(
		"RecyclerPanel",
		"Recycler — " .. minRecycle .. "+ same creature → 1 rarity tier higher",
		"Recycle for higher-tier creature",
		function(uids)
			print(LOG .. " FireServer RecycleDuplicates uids=" .. table.concat(uids or {}, ","))
			recycleDuplicates:FireServer(uids)
		end,
		function(sel, invData)
			if #sel < minRecycle then return false, "Select at least " .. tostring(minRecycle) .. " of the same creature" end
			local uidToEntry = {}
			for _, e in ipairs(invData.inventory) do uidToEntry[e.uid] = e end
			local id = nil
			for _, uid in ipairs(sel) do
				local e = uidToEntry[uid]
				if not e then return false, "Creature not found" end
				if id and e.id ~= id then return false, "All must be the same creature" end
				id = e.id
			end
			local cr = CreatureData.GetById(id)
			if not cr then return false, "Invalid creature" end
			local nextR = CreatureData.GetNextRarity(cr.rarity)
			if not nextR then return false, "Legendary cannot be recycled" end
			return true
		end,
		function()
			local ok, r = pcall(function() return getInventory:InvokeServer() end)
			return ok and r
		end
	)
	openRecycler.OnClientEvent:Connect(function()
		print(LOG .. " OpenRecycler received")
		if recyclePanel and recycleRefreshList then
			recyclePanel.Visible = true
			recycleRefreshList()
			task.delay(0.6, function()
				if recyclePanel and recyclePanel.Visible and recycleRefreshList then
					recycleRefreshList()
				end
			end)
		else
			warn(LOG .. " OpenRecycler received but recyclePanel or recycleRefreshList is nil")
		end
	end)
	recycleResult.OnClientEvent:Connect(function(success, payload)
		print(LOG .. " RecycleResult received success=" .. tostring(success) .. " payload=" .. tostring(payload))
		if recyclePanel then recyclePanel.Visible = false end
		if success then
			Notify.Toast("Egg received! Place on a point to hatch (no income/defense until hatched).", C.green, 4)
		else
			Notify.Toast(payload or "Recycle failed", C.red, 3)
		end
	end)
end

print("[CombinerRecyclerClient] Loaded (MCombiner / MRecycler UI)")
