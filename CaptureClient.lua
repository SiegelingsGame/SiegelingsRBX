-- CaptureClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Click fainted creatures to capture (costs gold).
-- Press E to target world creatures. Select target from bar to attack (player + companion).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")


local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local mouse = player:GetMouse()

-- Use existing event if InventoryUIManager created it first; otherwise create (so animation works regardless of script load order)
local PLAY_FAV_ANIM_NAME = "PlayFavoriteCardAnimation"
local playFavoriteCardEvt = playerGui:FindFirstChild(PLAY_FAV_ANIM_NAME)
if not playFavoriteCardEvt or not playFavoriteCardEvt:IsA("BindableEvent") then
	playFavoriteCardEvt = Instance.new("BindableEvent")
	playFavoriteCardEvt.Name = PLAY_FAV_ANIM_NAME
	playFavoriteCardEvt.Parent = playerGui
end

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
if not eventsFolder then return end

local captureRequest = eventsFolder:WaitForChild("CaptureRequest", 8)
local captureStart = eventsFolder:WaitForChild("CaptureStart", 8)
local captureSuccess = eventsFolder:WaitForChild("CaptureSuccess", 8)
local captureCancel = eventsFolder:WaitForChild("CaptureCancel", 8)
local captureFail = eventsFolder:WaitForChild("CaptureFail", 8)
local captureOutOfRange = eventsFolder:WaitForChild("CaptureOutOfRange", 8)
local setCompanionTarget = eventsFolder:WaitForChild("SetCompanionTarget", 8)
local clearCompanionTarget = eventsFolder:WaitForChild("ClearCompanionTarget", 8)
local companionFainted = eventsFolder:FindFirstChild("CompanionFainted")
local companionRecalled = eventsFolder:WaitForChild("CompanionRecalled", 8)
local stealInteractRequest = eventsFolder:FindFirstChild("StealInteractRequest")
local homeRecallStart = eventsFolder:FindFirstChild("HomeRecallStart")
local homeRecallEnd = eventsFolder:FindFirstChild("HomeRecallEnd")
local homeRecallCancel = eventsFolder:FindFirstChild("HomeRecallCancel")

-- -- GUI --
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "CaptureGUI"
screenGui.ResetOnSpawn = false
screenGui.DisplayOrder = 5
screenGui.Parent = playerGui

-- Progress bar
local progressFrame = Instance.new("Frame")
progressFrame.Size = UDim2.new(0, 300, 0, 36)
progressFrame.Position = UDim2.new(0.5, -150, 0.78, 0)
progressFrame.BackgroundColor3 = Color3.fromRGB(20, 22, 35)
progressFrame.BorderSizePixel = 0
progressFrame.Visible = false
progressFrame.Parent = screenGui
Instance.new("UICorner", progressFrame).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", progressFrame).Color = Color3.fromRGB(255, 200, 0)

local progressBar = Instance.new("Frame")
progressBar.Size = UDim2.new(0, 0, 1, 0)
progressBar.BackgroundColor3 = Color3.fromRGB(255, 200, 0)
progressBar.BorderSizePixel = 0
progressBar.Parent = progressFrame
Instance.new("UICorner", progressBar).CornerRadius = UDim.new(0, 10)

local progressLabel = Instance.new("TextLabel")
progressLabel.Size = UDim2.new(1, 0, 1, 0)
progressLabel.BackgroundTransparency = 1
progressLabel.Text = "Capturing..."
progressLabel.TextColor3 = Color3.new(1,1,1)
progressLabel.Font = Enum.Font.GothamBold
progressLabel.TextSize = 14
progressLabel.Parent = progressFrame

-- Home Recall progress bar (similar to capture, shows countdown timer)
local recallFrame = Instance.new("Frame")
recallFrame.Size = UDim2.new(0, 300, 0, 36)
recallFrame.Position = UDim2.new(0.5, -150, 0.72, 0)
recallFrame.BackgroundColor3 = Color3.fromRGB(20, 25, 45)
recallFrame.BorderSizePixel = 0
recallFrame.Visible = false
recallFrame.Parent = screenGui
Instance.new("UICorner", recallFrame).CornerRadius = UDim.new(0, 10)
Instance.new("UIStroke", recallFrame).Color = Color3.fromRGB(100, 180, 255)

local recallBar = Instance.new("Frame")
recallBar.Size = UDim2.new(0, 0, 1, 0)
recallBar.BackgroundColor3 = Color3.fromRGB(100, 180, 255)
recallBar.BorderSizePixel = 0
recallBar.Parent = recallFrame
Instance.new("UICorner", recallBar).CornerRadius = UDim.new(0, 10)

local recallLabel = Instance.new("TextLabel")
recallLabel.Size = UDim2.new(1, 0, 1, 0)
recallLabel.BackgroundTransparency = 1
recallLabel.Text = "Recalling..."
recallLabel.TextColor3 = Color3.new(1,1,1)
recallLabel.Font = Enum.Font.GothamBold
recallLabel.TextSize = 14
recallLabel.Parent = recallFrame

-- Target Selection Bar (fixed width for up to 5 icons; larger cells for easier tap/click)
local TARGET_BAR_ICON_CELL_W = 64  -- cell width (ICON_SIZE + padding); larger for easier selection
local TARGET_BAR_WIDTH = 12 + 5 * TARGET_BAR_ICON_CELL_W + 4 * 8 + 12  -- left pad + 5 cells + 4 gaps + right pad
local TARGET_BAR_HEIGHT = 72  -- taller bar for larger clickable area
local targetBarFrame = Instance.new("Frame")
targetBarFrame.Name = "TargetSelectionBar"
targetBarFrame.Size = UDim2.new(0, TARGET_BAR_WIDTH, 0, TARGET_BAR_HEIGHT)
targetBarFrame.Position = UDim2.new(0.5, 0, 1, -70)  -- above HUD bar (HUD bar height reduced to give space)
targetBarFrame.AnchorPoint = Vector2.new(0.5, 1)
targetBarFrame.BackgroundColor3 = Color3.fromRGB(18, 22, 32)
targetBarFrame.BorderSizePixel = 0
targetBarFrame.Visible = false
targetBarFrame.Parent = screenGui
Instance.new("UICorner", targetBarFrame).CornerRadius = UDim.new(0, 8)
local targetBarStroke = Instance.new("UIStroke", targetBarFrame)
targetBarStroke.Color = Color3.fromRGB(220, 180, 60)
targetBarStroke.Thickness = 2

local targetBarList = Instance.new("Frame")
targetBarList.Name = "IconList"
targetBarList.Size = UDim2.new(1, -24, 1, -8)
targetBarList.Position = UDim2.new(0, 12, 0, 4)
targetBarList.BackgroundTransparency = 1
targetBarList.Parent = targetBarFrame

local targetBarLayout = Instance.new("UIListLayout", targetBarList)
targetBarLayout.FillDirection = Enum.FillDirection.Horizontal
targetBarLayout.HorizontalAlignment = Enum.HorizontalAlignment.Left
targetBarLayout.VerticalAlignment = Enum.VerticalAlignment.Center
targetBarLayout.Padding = UDim.new(0, 8)

local targetBarEmptyLabel = Instance.new("TextLabel")
targetBarEmptyLabel.Name = "EmptyLabel"
targetBarEmptyLabel.Size = UDim2.new(1, 0, 1, 0)
targetBarEmptyLabel.Position = UDim2.new(0, 0, 0, 0)
targetBarEmptyLabel.BackgroundTransparency = 1
targetBarEmptyLabel.Text = "No targets in range"
targetBarEmptyLabel.TextColor3 = Color3.fromRGB(120, 120, 140)
targetBarEmptyLabel.Font = Enum.Font.GothamMedium
targetBarEmptyLabel.TextSize = 10
targetBarEmptyLabel.Visible = false
targetBarEmptyLabel.Parent = targetBarList

local selectedTargetModel = nil   -- tracks which creature we've targeted (for UI highlight + world highlight)
local selectedTargetUniqueId = nil -- when set, we target by UniqueId and get the rest of the data from the model

-- Shared target store for PlayerCombatClient (attack only when target selected)
local function ensureTargetStore()
	local store = playerGui:FindFirstChild("CurrentCombatTargetId")
	if not store or not store:IsA("StringValue") then
		store = Instance.new("StringValue")
		store.Name = "CurrentCombatTargetId"
		store.Value = ""
		store.Parent = playerGui
	end
	return store
end

local function updateCombatTargetStore(uniqueId)
	local store = ensureTargetStore()
	store.Value = uniqueId and tostring(uniqueId) or ""
end

-- Tooltip (shows on hover over creatures)
local tooltip = Instance.new("Frame")
tooltip.Size = UDim2.new(0, 200, 0, 60)
tooltip.BackgroundColor3 = Color3.fromRGB(14, 16, 24)
tooltip.BackgroundTransparency = 0.1
tooltip.BorderSizePixel = 0
tooltip.Visible = false
tooltip.Parent = screenGui
Instance.new("UICorner", tooltip).CornerRadius = UDim.new(0, 8)
Instance.new("UIStroke", tooltip).Color = Color3.fromRGB(60, 62, 80)

local tipName = Instance.new("TextLabel")
tipName.Size = UDim2.new(1, -10, 0, 18)
tipName.Position = UDim2.new(0, 5, 0, 4)
tipName.BackgroundTransparency = 1
tipName.TextColor3 = Color3.new(1,1,1)
tipName.Font = Enum.Font.GothamBold
tipName.TextSize = 12
tipName.TextXAlignment = Enum.TextXAlignment.Left
tipName.Parent = tooltip

local tipInfo = Instance.new("TextLabel")
tipInfo.Size = UDim2.new(1, -10, 0, 14)
tipInfo.Position = UDim2.new(0, 5, 0, 22)
tipInfo.BackgroundTransparency = 1
tipInfo.TextColor3 = Color3.fromRGB(150, 155, 170)
tipInfo.Font = Enum.Font.GothamMedium
tipInfo.TextSize = 10
tipInfo.TextXAlignment = Enum.TextXAlignment.Left
tipInfo.Parent = tooltip

local tipAction = Instance.new("TextLabel")
tipAction.Size = UDim2.new(1, -10, 0, 14)
tipAction.Position = UDim2.new(0, 5, 0, 40)
tipAction.BackgroundTransparency = 1
tipAction.TextColor3 = Color3.fromRGB(255, 200, 0)
tipAction.Font = Enum.Font.GothamBold
tipAction.TextSize = 10
tipAction.TextXAlignment = Enum.TextXAlignment.Left
tipAction.Parent = tooltip

-- Notification (delegate to shared system)
local function showNotif(text, color, duration)
	Notify.Toast(text, color or Color3.fromRGB(200, 200, 210), duration or 3)
end

-- -- Hover tooltip --
task.spawn(function()
	while true do
		task.wait(0.1)
		local target = mouse.Target
		if target then
			local model = target:FindFirstAncestorWhichIsA("Model")
			if model and model:GetAttribute("CreatureId") then
				local cid = model:GetAttribute("CreatureId")
				local info = CreatureData.GetById(cid)
				local isFainted = model:GetAttribute("Fainted")

				if info then
					tipName.Text = info.displayName .. " (" .. info.rarity .. ")"
					tipName.TextColor3 = CreatureData.Rarities[info.rarity] and CreatureData.Rarities[info.rarity].color or Color3.new(1,1,1)
					tipInfo.Text = info.element .. " " .. info.class .. " | " .. (info.behavior or "?")

					if isFainted then
						local cost = CreatureData.GetCaptureCost(cid)
						tipAction.Text = "FAINTED - Click to capture (" .. cost .. " gold)"
						tipAction.TextColor3 = Color3.fromRGB(255, 200, 0)
					else
						tipAction.Text = "[E] to target | Must faint to capture"
						tipAction.TextColor3 = Color3.fromRGB(150, 155, 170)
					end

					tooltip.Position = UDim2.new(0, mouse.X + 15, 0, mouse.Y - 30)
					tooltip.Visible = true
				else
					tooltip.Visible = false
				end
			else
				tooltip.Visible = false
			end
		else
			tooltip.Visible = false
		end
	end
end)

-- Distance from a point to the closest point on the model's bounding box (so tall creatures can be captured from underneath).
local function getDistanceToModel(point, creatureModel)
	local cf, size = creatureModel:GetBoundingBox()
	local half = size * 0.5
	local localP = cf:PointToObjectSpace(point)
	local closestLocal = Vector3.new(
		math.clamp(localP.X, -half.X, half.X),
		math.clamp(localP.Y, -half.Y, half.Y),
		math.clamp(localP.Z, -half.Z, half.Z)
	)
	local closestWorld = cf:PointToWorldSpace(closestLocal)
	return (point - closestWorld).Magnitude
end

local function isPlayerInCaptureRange(rootPos, creatureModel)
	return getDistanceToModel(rootPos, creatureModel) <= GameConfig.CaptureRange
end

-- Helper: find the nearest fainted creature to a world position (within clickRadius)
local function findNearestFainted(worldPos, maxDist)
	local best, bestDist = nil, maxDist
	for _, model in ipairs(CollectionService:GetTagged("WorldCreature")) do
		if model.Parent and model:GetAttribute("Fainted") then
			-- Use distance to model bbox so tall creatures are selectable when clicking near them
			local d = getDistanceToModel(worldPos, model)
			if d < bestDist then
				bestDist = d
				best = model
			end
		end
	end
	return best
end

-- -- Left click: capture fainted creatures --
mouse.Button1Down:Connect(function()
	local target = mouse.Target
	if not target then return end

	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then return end
	local rootPos = character.HumanoidRootPart.Position

	local creatureModel = target:FindFirstAncestorWhichIsA("Model")

	-- If we clicked a creature model, check if it's fainted
	if creatureModel and creatureModel:GetAttribute("CreatureId") then
		if creatureModel:GetAttribute("Fainted") then
			-- Direct hit on fainted creature — use bbox so tall creatures can be captured from underneath
			if isPlayerInCaptureRange(rootPos, creatureModel) then
				if captureRequest then captureRequest:FireServer(creatureModel) end
				return
			else
				showNotif("Too far away!", Color3.fromRGB(255, 100, 80), 1.5)
				return
			end
		end

		-- Clicked a live creature — check if a fainted creature is nearby/behind it
		-- (creatures overlap in packs, so the click may have been intended for the fainted one)
		local body = creatureModel.PrimaryPart or creatureModel:FindFirstChild("Body")
		if body then
			local fainted = findNearestFainted(body.Position, 12)
			if fainted then
				if isPlayerInCaptureRange(rootPos, fainted) then
					if captureRequest then captureRequest:FireServer(fainted) end
					return
				end
			end
		end

		-- No nearby fainted creature — show hint (use bbox for range so tall creatures show hint when close)
		if isPlayerInCaptureRange(rootPos, creatureModel) then
			showNotif("Creature must be fainted first! Attack it or use your companion.", Color3.fromRGB(255, 180, 80), 2.5)
		end
		return
	end

	-- Clicked terrain/other — check if a fainted creature is near the click point
	if mouse.Hit then
		local fainted = findNearestFainted(mouse.Hit.Position, 8)
		if fainted then
			if isPlayerInCaptureRange(rootPos, fainted) then
				if captureRequest then captureRequest:FireServer(fainted) end
			else
				showNotif("Too far away!", Color3.fromRGB(255, 100, 80), 1.5)
			end
		end
	end
end)

-- -- E key: target nearest creature (or creature near crosshair) --
local currentTargetHighlight = nil
local arenaCenter = nil -- cached

local function getArenaCenter()
	if arenaCenter then return arenaCenter end
	local arenaFolder = workspace:FindFirstChild("Arena")
	if arenaFolder then
		local center = arenaFolder:FindFirstChild("ArenaCenter")
		if center then
			if center:IsA("BasePart") then
				arenaCenter = center.Position
			elseif center:IsA("Model") then
				local inner = center:FindFirstChildWhichIsA("BasePart")
				arenaCenter = inner and inner.Position or center:GetPivot().Position
			end
		end
		if not arenaCenter then
			arenaCenter = arenaFolder:GetPivot().Position
		end
	end
	return arenaCenter
end

local function isNearArena(position)
	local ac = getArenaCenter()
	if not ac then return false end
	local flatDist = (Vector3.new(position.X, 0, position.Z) - Vector3.new(ac.X, 0, ac.Z)).Magnitude
	return flatDist < (GameConfig.ArenaExclusionRadius or 80)
end

local function isValidTarget(model)
	if not model or not model.Parent then return false end
	if model:GetAttribute("Fainted") then return false end
	if CollectionService:HasTag(model, "ArenaCreature") then return false end
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if body and isNearArena(body.Position) then return false end
	return true
end

local function clearTargetHighlight()
	if currentTargetHighlight and currentTargetHighlight.Parent then
		currentTargetHighlight:Destroy()
	end
	currentTargetHighlight = nil
end

local function highlightTarget(model)
	clearTargetHighlight()
	if not model or not model.Parent then return end
	local hl = Instance.new("Highlight")
	hl.Name = "TargetHL"
	hl.FillColor = Color3.fromRGB(255, 200, 50)
	hl.FillTransparency = 0.7
	hl.OutlineColor = Color3.fromRGB(255, 220, 80)
	hl.OutlineTransparency = 0
	hl.Parent = model
	currentTargetHighlight = hl
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.E then
		local character = player.Character
		if not character or not character:FindFirstChild("HumanoidRootPart") then return end
		local rootPos = character.HumanoidRootPart.Position
		local stealRange = GameConfig.StealInteractRange or 12
		local mouseTarget = mouse.Target

		-- First: try to interact with a fainted base creature (steal) - must not own it
		if mouseTarget then
			local hoverModel = mouseTarget:FindFirstAncestorWhichIsA("Model")
			if hoverModel and hoverModel:GetAttribute("CreatureId") and hoverModel:GetAttribute("Fainted") then
				local ownerId = hoverModel:GetAttribute("OwnerUserId")
				if ownerId and ownerId ~= player.UserId and CollectionService:HasTag(hoverModel, "FaintedBaseCreature") then
					if getDistanceToModel(rootPos, hoverModel) <= stealRange then
						if stealInteractRequest then stealInteractRequest:FireServer(hoverModel) end
						showNotif("Picking up... Return to your base to claim it!", Color3.fromRGB(255, 220, 100), 2)
						return
					end
				end
			end
		end
		local nearestSteal, nearestStealDist = nil, stealRange
		for _, tagged in ipairs(CollectionService:GetTagged("FaintedBaseCreature")) do
			if tagged.Parent then
				local ownerId = tagged:GetAttribute("OwnerUserId")
				if ownerId and ownerId ~= player.UserId then
					local d = getDistanceToModel(rootPos, tagged)
					if d < nearestStealDist then nearestStealDist = d; nearestSteal = tagged end
				end
			end
		end
		if nearestSteal then
			if stealInteractRequest then stealInteractRequest:FireServer(nearestSteal) end
			showNotif("Picking up... Return to your base to claim it!", Color3.fromRGB(255, 220, 100), 2)
			return
		end

		-- E = target for companion (live creatures); send UniqueId when present so server resolves and we get data from there
		if mouseTarget then
			local hoverModel = mouseTarget:FindFirstAncestorWhichIsA("Model")
			if hoverModel and hoverModel:GetAttribute("CreatureId") and isValidTarget(hoverModel) then
				if getDistanceToModel(rootPos, hoverModel) <= GameConfig.TargetScanRange then
					local uid = hoverModel:GetAttribute("UniqueId") or hoverModel:GetAttribute("UID")
					if setCompanionTarget then setCompanionTarget:FireServer(uid or hoverModel) end
					selectedTargetModel = hoverModel
					selectedTargetUniqueId = uid
					updateCombatTargetStore(uid)
					local cid = hoverModel:GetAttribute("CreatureId")
					local info = cid and CreatureData.GetById(cid)
					showNotif(">> Targeting: " .. (info and info.displayName or "creature"), Color3.fromRGB(255, 200, 50), 2)
					highlightTarget(hoverModel)
					return
				end
			end
		end

		-- No hover target – find nearest creature (exclude arena zone); target by UniqueId then get rest from model
		local nearest, nearDist = nil, GameConfig.TargetScanRange
		for _, tagged in ipairs(CollectionService:GetTagged("WorldCreature")) do
			if isValidTarget(tagged) then
				local d = getDistanceToModel(rootPos, tagged)
				if d < nearDist then nearDist = d; nearest = tagged end
			end
		end

		if nearest then
			local uid = nearest:GetAttribute("UniqueId") or nearest:GetAttribute("UID")
			if setCompanionTarget then setCompanionTarget:FireServer(uid or nearest) end
			selectedTargetModel = nearest
			selectedTargetUniqueId = uid
			updateCombatTargetStore(uid)
			local cid = nearest:GetAttribute("CreatureId")
			local info = cid and CreatureData.GetById(cid)
			showNotif(">> Targeting: " .. (info and info.displayName or "creature"), Color3.fromRGB(255, 200, 50), 2)
			highlightTarget(nearest)
		else
			-- No creature in range: clear target
			if clearCompanionTarget then clearCompanionTarget:FireServer() end
			selectedTargetModel = nil
			selectedTargetUniqueId = nil
			updateCombatTargetStore(nil)
			clearTargetHighlight()
			showNotif("No target in range", Color3.fromRGB(120, 120, 140), 1.5)
		end
	end
end)

-- -- Dynamic Target Selection Bar (updates each tick, click to select attack target) --
local lastInRangeModels = {}
local lastSelectedTargetModel = nil
local ICON_SIZE = 56  -- larger icons for easier tap/click (especially on mobile)
local MAX_TARGET_ICONS = 5  -- show closest 5 creatures

-- Match PlayerCombatClient: only exclude Fainted (no ArenaCreature filter so all attackable creatures show).
local function isTargetBarValid(model)
	if not model or not model.Parent then return false end
	if model:GetAttribute("Fainted") then return false end
	return true
end

-- Get distance to model (use Body/PrimaryPart, else bounding box center).
local function getDistToCreature(rootPos, model)
	local body = model.PrimaryPart or model:FindFirstChild("Body")
	if body then
		return (rootPos - body.Position).Magnitude
	end
	local cf, size = model:GetBoundingBox()
	return (rootPos - cf.Position).Magnitude
end

local function collectInRangeCreatures(rootPos)
	-- One entry per creature MODEL (instance), even if multiple have the same CreatureId.
	-- We still cap the bar to the closest MAX_TARGET_ICONS creatures after sorting.
	local list = {}
	local seen = {} -- avoid duplicates if the same model is discovered via multiple paths
	local scanRange = GameConfig.TargetScanRange or 50

	local function addModel(model)
		if not model or not model.Parent then return end
		if seen[model] then return end
		if not isTargetBarValid(model) then return end
		if CollectionService:HasTag(model, "FavoriteCreature") then return end
		-- Exclude player-owned base creatures (income, defense, battle)
		for _, baseTag in ipairs({ "BaseDefenseCreature", "BaseIncomeCreature", "BaseBattleCreature" }) do
			if CollectionService:HasTag(model, baseTag) then
				local ownerId = model:GetAttribute("OwnerUserId")
				if ownerId and (ownerId == player.UserId or tostring(ownerId) == tostring(player.UserId)) then
					return
				end
				break -- only one base tag per model
			end
		end

		local cid = model:GetAttribute("CreatureId")
		if not cid then return end

		local d = getDistToCreature(rootPos, model)
		if d > scanRange then return end

		-- Use UniqueId (world) or UID (base) so we target by id and get the rest of the data from the model
		local uniqueId = model:GetAttribute("UniqueId") or model:GetAttribute("UID")
		seen[model] = true
		table.insert(list, { model = model, dist = d, creatureId = cid, uniqueId = uniqueId })
	end

	-- World creatures (same source as PlayerCombatClient)
	for _, tagged in ipairs(CollectionService:GetTagged("WorldCreature")) do
		addModel(tagged)
	end

	-- Base creatures (enemy defense/income) – only enemies (OwnerUserId ~= local player)
	for _, tag in ipairs({ "BaseDefenseCreature", "BaseIncomeCreature" }) do
		for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
			local ownerId = tagged:GetAttribute("OwnerUserId")
			if not ownerId or ownerId ~= player.UserId then
				addModel(tagged)
			end
		end
	end

	-- Always run fallback scan so we never miss creatures (e.g. tag replication, pack spawns).
	-- Tags may not return all instances; GetDescendants catches everything in workspace.
	for _, obj in ipairs(workspace:GetDescendants()) do
		if obj:IsA("Model") then
			addModel(obj)
		end
	end

	-- Sort by distance (closest first); refreshTargetBar will take up to MAX_TARGET_ICONS.
	table.sort(list, function(a, b)
		return a.dist < b.dist
	end)

	return list
end

local function refreshTargetBar()
	local character = player.Character
	if not character or not character:FindFirstChild("HumanoidRootPart") then
		targetBarFrame.Visible = false
		return
	end
	local rootPos = character.HumanoidRootPart.Position
	local inRange = collectInRangeCreatures(rootPos)

	-- Clear selected if no longer valid (match by model or by uniqueId)
	if selectedTargetModel and (not selectedTargetModel.Parent or selectedTargetModel:GetAttribute("Fainted")) then
		if clearCompanionTarget then clearCompanionTarget:FireServer() end
		selectedTargetModel = nil
		selectedTargetUniqueId = nil
		updateCombatTargetStore(nil)
		clearTargetHighlight()
	end
	local stillInRange = false
	if selectedTargetModel or selectedTargetUniqueId then
		for _, entry in ipairs(inRange) do
			if entry.model == selectedTargetModel or (selectedTargetUniqueId and entry.uniqueId == selectedTargetUniqueId) then
				stillInRange = true
				selectedTargetModel = entry.model
				selectedTargetUniqueId = entry.uniqueId
				break
			end
		end
		if not stillInRange then
			if clearCompanionTarget then clearCompanionTarget:FireServer() end
			selectedTargetModel = nil
			selectedTargetUniqueId = nil
			updateCombatTargetStore(nil)
			clearTargetHighlight()
		end
	end

	if #inRange == 0 then
		targetBarFrame.Visible = true
		-- Reparent EmptyLabel back into list (it was unparented when we had targets)
		if targetBarEmptyLabel.Parent ~= targetBarList then
			targetBarEmptyLabel.Parent = targetBarList
		end
		targetBarEmptyLabel.Visible = true
		targetBarEmptyLabel.Size = UDim2.new(1, 0, 1, 0)
		-- Clear icon cells only (keep UIListLayout and EmptyLabel)
		for _, child in ipairs(targetBarList:GetChildren()) do
			if child:IsA("Frame") then child:Destroy() end
		end
		lastInRangeModels = {}
		lastSelectedTargetModel = selectedTargetModel
		return
	end
	-- Unparent EmptyLabel so it doesn't block icon layout (icons need full control of targetBarList)
	targetBarEmptyLabel.Parent = nil
	targetBarEmptyLabel.Visible = false

	-- Take closest MAX_TARGET_ICONS unique creatures for the bar (always rebuild so bar expands when count goes 1→3+).
	local displayList = {}
	for i = 1, math.min(#inRange, MAX_TARGET_ICONS) do displayList[i] = inRange[i] end

	lastInRangeModels = {}
	for i, entry in ipairs(displayList) do lastInRangeModels[i] = entry.model end
	lastSelectedTargetModel = selectedTargetModel

	-- Rebuild icons (bar has fixed width; UIListLayout orders them left to right).
	-- Only destroy icon Frames – do NOT destroy UIListLayout or layout breaks and icons stack
	for _, child in ipairs(targetBarList:GetChildren()) do
		if child:IsA("Frame") then child:Destroy() end
	end
	for i, entry in ipairs(displayList) do
		local m = entry.model
		local cid = m:GetAttribute("CreatureId")
		local info = cid and CreatureData.GetById(cid)
		local displayName = info and info.displayName or "?"
		local elemInfo = info and CreatureData.Elements[info.element]
		local color = (elemInfo and elemInfo.color) or (info and CreatureData.Rarities[info.rarity] and CreatureData.Rarities[info.rarity].color) or Color3.fromRGB(120, 120, 140)

		local cell = Instance.new("Frame")
		cell.Size = UDim2.new(0, TARGET_BAR_ICON_CELL_W, 0, TARGET_BAR_HEIGHT - 12)  -- full cell = clickable area
		cell.BackgroundTransparency = 1
		cell.LayoutOrder = i
		cell.Parent = targetBarList

		local btn = Instance.new("TextButton")
		-- Button fills cell for maximum clickable/tappable area (especially on mobile)
		btn.Size = UDim2.new(1, 0, 1, 0)
		btn.Position = UDim2.new(0, 0, 0, 0)
		btn.BackgroundColor3 = color
		btn.BorderSizePixel = 0
		btn.Text = string.sub(displayName, 1, 1):upper()
		btn.TextColor3 = Color3.new(1, 1, 1)
		btn.Font = Enum.Font.GothamBlack
		btn.TextSize = 14
		btn.Parent = cell
		local corner = Instance.new("UICorner", btn)
		corner.CornerRadius = UDim.new(1, 0)
		local stroke = Instance.new("UIStroke", btn)
		stroke.Color = Color3.fromRGB(80, 80, 100)
		stroke.Thickness = 2

		local isSelected = (m == selectedTargetModel)
		if isSelected then
			stroke.Color = Color3.fromRGB(255, 220, 80)
			stroke.Thickness = 4
		end

		if isSelected then
			local arrow = Instance.new("TextLabel")
			arrow.Size = UDim2.new(0, 8, 0, 6)
			arrow.Position = UDim2.new(0.5, -4, 1, -6)
			arrow.BackgroundTransparency = 1
			arrow.Text = "▲"
			arrow.TextColor3 = Color3.fromRGB(255, 220, 80)
			arrow.Font = Enum.Font.GothamBold
			arrow.TextSize = 6
			arrow.Parent = cell
		end

		local captureEntry = entry
		local captureDisplayName = displayName
		btn.MouseButton1Click:Connect(function()
			-- Send UniqueId when present so server picks target by id and gets the rest of the data from the model
			local uid = captureEntry.uniqueId
			local targetModel = captureEntry.model
			if setCompanionTarget then setCompanionTarget:FireServer(uid or targetModel) end
			selectedTargetModel = targetModel
			selectedTargetUniqueId = uid
			updateCombatTargetStore(uid)
			highlightTarget(targetModel)
			showNotif(">> Targeting: " .. captureDisplayName, Color3.fromRGB(255, 200, 50), 1)
			lastInRangeModels = {}
			refreshTargetBar()
		end)
	end
	targetBarFrame.Visible = true
end

-- Throttle updates to ~5x/sec instead of 60x/sec to avoid performance impact
local targetBarLastUpdate = 0
local TARGET_BAR_UPDATE_INTERVAL = 0.2
RunService.Heartbeat:Connect(function()
	local now = tick()
	if now - targetBarLastUpdate >= TARGET_BAR_UPDATE_INTERVAL then
		targetBarLastUpdate = now
		refreshTargetBar()
	end
end)

-- -- Catching animation --
-- Store model + original sizes so we can restore if capture fails (e.g. moved out of range)
local captureRestoreData = nil
local captureCancelled = false

local graceAreaFolder = nil  -- Dome + card during grace period (client-only, parented to Camera)
local currentCaptureFolder = nil
local currentCaptureCard = nil
-- Multiple captures: each card keyed by server-provided sessionId so success animates the correct card
local pendingCaptureCards = {}  -- [captureSessionId] = { folder = Folder, card = Part }

local function restoreCreatureModel()
	if captureRestoreData and captureRestoreData.model and captureRestoreData.model.Parent then
		for part, origSize in pairs(captureRestoreData.sizes or {}) do
			if part and part.Parent then
				part.Size = origSize
			end
		end
		if captureRestoreData.pivot then
			captureRestoreData.model:PivotTo(captureRestoreData.pivot)
		end
	end
	captureRestoreData = nil
	captureCancelled = false
	-- Remove any in-progress capture cards (single ref + all pending for multiple captures)
	if currentCaptureFolder then
		currentCaptureFolder:Destroy()
		currentCaptureFolder = nil
		currentCaptureCard = nil
	end
	for _, data in pairs(pendingCaptureCards) do
		if data and data.folder and data.folder.Parent then data.folder:Destroy() end
	end
	pendingCaptureCards = {}
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "CaptureAnimation" and child:IsA("Folder") then
			child:Destroy()
		end
	end
	-- Remove grace area dome + card (client-only, in Camera)
	if graceAreaFolder then
		graceAreaFolder:Destroy()
		graceAreaFolder = nil
	end
end

local function ensureGraceArea(creatureModel)
	if graceAreaFolder then return end
	if not creatureModel or not creatureModel.Parent then return end

	local bboxCf, bboxSize = creatureModel:GetBoundingBox()
	local center = bboxCf.Position
	local creatureTop = center.Y + bboxSize.Y * 0.5
	local radius = math.max(bboxSize.X, bboxSize.Z, bboxSize.Y) * 0.5 + GameConfig.CaptureRange
	local cardWidth = math.max(bboxSize.X, bboxSize.Z, 4)
	local cardHeight = cardWidth * 1.4
	local cardPos = Vector3.new(center.X, creatureTop + 2, center.Z)

	-- Parent to CurrentCamera so only this player sees it
	graceAreaFolder = Instance.new("Folder")
	graceAreaFolder.Name = "CaptureGraceArea"
	graceAreaFolder.Parent = workspace.CurrentCamera

	-- Dome: sphere over capture area (covers CaptureRange around creature)
	local dome = Instance.new("Part")
	dome.Name = "CaptureDome"
	dome.Shape = Enum.PartType.Ball
	dome.Size = Vector3.new(radius * 2, radius * 2, radius * 2)
	dome.Position = center
	dome.Transparency = 0.85
	dome.Color = Color3.fromRGB(255, 220, 100)
	dome.Material = Enum.Material.ForceField
	dome.Anchored = true
	dome.CanCollide = false
	dome.CanQuery = false
	dome.CanTouch = false
	dome.CastShadow = false
	dome.Parent = graceAreaFolder

	-- Card above creature (same style as capture animation)
	local card = Instance.new("Part")
	card.Name = "GraceCard"
	card.Size = Vector3.new(cardWidth, cardHeight, 0.2)
	card.CFrame = CFrame.new(cardPos) * CFrame.Angles(math.rad(90), 0, 0)
	card.Anchored = true
	card.CanCollide = false
	card.CanQuery = false
	card.CanTouch = false
	card.CastShadow = false
	card.Material = Enum.Material.Neon
	card.Color = Color3.fromRGB(255, 220, 100)
	card.Parent = graceAreaFolder

	local spot = Instance.new("SpotLight")
	spot.Brightness = 2
	spot.Range = bboxSize.Y + 6
	spot.Angle = 60
	spot.Color = Color3.fromRGB(255, 248, 200)
	spot.Parent = card

	addCardParticles(card)
end

local function addCardParticles(card)
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "CardGlow"
	pe.Texture = "rbxassetid://5860841663"
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 210, 230), Color3.fromRGB(160, 180, 220))
	pe.Transparency = NumberSequence.new(0.5, 1)
	pe.Size = NumberSequence.new(0.3, 0.8)
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Rate = 25
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.LightEmission = 0.8
	pe.LightInfluence = 0
	pe.Parent = card
end

local function createVortexEffect(cardPos, creatureCenter, vortexHeight, trailWidth, parentFolder)
	local vortexCenter = (cardPos + creatureCenter) / 2
	local dir = (cardPos - creatureCenter).Unit
	local right = dir.Y < 0.99 and dir:Cross(Vector3.new(0, 1, 0)).Unit or Vector3.new(1, 0, 0)
	local tangent = right:Cross(dir).Unit
	local vortexPart = Instance.new("Part")
	vortexPart.Name = "CaptureVortex"
	vortexPart.Shape = Enum.PartType.Cylinder
	vortexPart.Size = Vector3.new(trailWidth, vortexHeight, trailWidth)  -- diameter = card face width, height = trail length
	vortexPart.CFrame = CFrame.fromMatrix(vortexCenter, right, dir)
	vortexPart.Transparency = 1
	vortexPart.Anchored = true
	vortexPart.CanCollide = false
	vortexPart.CanQuery = false
	vortexPart.CanTouch = false
	vortexPart.CastShadow = false
	vortexPart.Parent = parentFolder

	local attachBot = Instance.new("Attachment")
	attachBot.Position = Vector3.new(0, -vortexHeight/2, 0)
	attachBot.Parent = vortexPart

	local pe = Instance.new("ParticleEmitter")
	pe.Name = "VortexParticles"
	pe.Texture = "rbxassetid://5860841663"
	pe.Color = ColorSequence.new(
		Color3.fromRGB(255, 230, 150),
		Color3.fromRGB(255, 180, 80),
		Color3.fromRGB(200, 150, 50)
	)
	pe.Transparency = NumberSequence.new(0.3, 0.8, 1)
	pe.Size = NumberSequence.new(0.5, 1.5, 0.2)
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Rate = 80
	pe.Speed = NumberRange.new(2, 5)
	pe.SpreadAngle = Vector2.new(25, 25)
	pe.Acceleration = dir * 50  -- particles flow upward from creature toward card
	pe.LightEmission = 0.6
	pe.LightInfluence = 0
	pe.Parent = attachBot

	local attachTop = Instance.new("Attachment")
	attachTop.Position = Vector3.new(0, vortexHeight/2, 0)
	attachTop.Parent = vortexPart

	for i = 0, 3 do
		local angle = (i / 4) * math.pi * 2
		local radialOffset = trailWidth * 0.4
		local offset = right * math.cos(angle) * radialOffset + tangent * math.sin(angle) * radialOffset
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, -vortexHeight/2, 0) + offset
		a0.Parent = vortexPart
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, vortexHeight/2, 0) + offset * 0.3
		a1.Parent = vortexPart
		local beam = Instance.new("Beam")
		beam.Attachment0 = a0
		beam.Attachment1 = a1
		beam.Color = ColorSequence.new(
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 80)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 180, 100)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 220, 120))
		)
		beam.Transparency = NumberSequence.new(0.6, 0.85)
		beam.LightEmission = 0.5
		beam.LightInfluence = 0
		beam.Width0 = trailWidth * 0.3
		beam.Width1 = 0.05
		beam.Parent = vortexPart
	end

	return vortexPart
end

-- Card throw, grows to monster width, floats above head with light, monster warps into card
-- captureSessionId: server-provided id so CaptureSuccess can animate this card when multiple captures overlap
local function runCaptureAnimation(creatureModel, holdTime, captureSessionId)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not creatureModel or not creatureModel.Parent then return end

	local body = creatureModel.PrimaryPart or creatureModel:FindFirstChild("Body")
	if not body then return end

	local bboxCf, bboxSize = creatureModel:GetBoundingBox()
	local creatureTop = bboxCf.Position.Y + bboxSize.Y * 0.5
	local cardWidth = math.max(bboxSize.X, bboxSize.Z, 4)
	local cardHeight = cardWidth * 1.4
	local cardRaiseOffset = 3.25  -- card sits above the top of the effect trail (~30% higher than 2.5)
	local cardTargetPos = Vector3.new(bboxCf.Position.X, creatureTop + 2 + cardRaiseOffset, bboxCf.Position.Z)

	local throwStart = root.Position + root.CFrame.LookVector * 2 + Vector3.new(0, 1, 0)
	local cardFolder = Instance.new("Folder")
	cardFolder.Name = "CaptureAnimation"
	cardFolder.Parent = workspace

	local card = Instance.new("Part")
	card.Name = "CaptureCard"
	card.Size = Vector3.new(2, 2.8, 0.15)
	card.Position = throwStart
	card.Anchored = true
	card.CanCollide = false
	card.CanQuery = false
	card.CanTouch = false
	card.CastShadow = false
	card.Material = Enum.Material.Neon
	card.Color = Color3.fromRGB(255, 220, 100)
	card.Parent = cardFolder

	-- Store by sessionId so CaptureSuccess(sessionId) animates this card (handles multiple captures)
	if captureSessionId then
		pendingCaptureCards[captureSessionId] = { folder = cardFolder, card = card }
	end

	local function cleanup()
		if captureSessionId then pendingCaptureCards[captureSessionId] = nil end
		cardFolder:Destroy()
	end

	local tweenInfo = TweenInfo.new
	local easeOut = Enum.EasingStyle.Quad
	local easeIn = Enum.EasingStyle.Back

	-- Phase 1: Card flies from player to above creature (0.5s)
	local flyTween = TweenService:Create(card, tweenInfo(0.5, easeOut, Enum.EasingDirection.Out), {
		Position = cardTargetPos
	})
	flyTween:Play()
	flyTween.Completed:Wait()

	if not creatureModel or not creatureModel.Parent then cleanup(); return end

	-- Phase 2: Card grows to monster width (0.35s)
	local growTween = TweenService:Create(card, tweenInfo(0.35, easeIn, Enum.EasingDirection.Out), {
		Size = Vector3.new(cardWidth, cardHeight, 0.2)
	})
	growTween:Play()
	growTween.Completed:Wait()

	if not creatureModel or not creatureModel.Parent then cleanup(); return end

	-- Phase 3: Add spotlight shining down
	local spot = Instance.new("SpotLight")
	spot.Brightness = 3
	spot.Range = bboxSize.Y + 6
	spot.Angle = 60
	spot.Color = Color3.fromRGB(255, 248, 200)
	spot.Parent = card

	-- Orient card flat above creature, light pointing down
	card.CFrame = CFrame.new(cardTargetPos) * CFrame.Angles(math.rad(90), 0, 0)

	addCardParticles(card)

	-- Vortex: absorbing effect between creature and card during warp (trail ends just below card)
	local creatureTopPos = Vector3.new(bboxCf.Position.X, creatureTop, bboxCf.Position.Z)
	local trailTop = cardTargetPos - Vector3.new(0, cardRaiseOffset, 0)  -- trail ends below card
	local vortexHeight = (trailTop - creatureTopPos).Magnitude
	local vortexPart = createVortexEffect(trailTop, creatureTopPos, math.max(4, vortexHeight), cardWidth, cardFolder)
	local vortexBaseCF = vortexPart.CFrame

	-- Phase 4: Monster warps into card (0.8s) - shrink and move up through vortex/particles to meet card
	local partsToScale = {}
	for _, desc in ipairs(creatureModel:GetDescendants()) do
		if desc:IsA("BasePart") then
			partsToScale[desc] = desc.Size
		end
	end
	local modelPivot = creatureModel:GetPivot()
	captureRestoreData = { model = creatureModel, sizes = partsToScale, pivot = modelPivot }

	local warpStartPos = modelPivot.Position
	local warpEndPos = cardTargetPos  -- creature travels through particles to meet the card
	local warpRotation = modelPivot - modelPivot.Position  -- preserve orientation

	local warpDuration = 0.8
	local warpStart = tick()
	while tick() - warpStart < warpDuration do
		if captureCancelled or not creatureModel or not creatureModel.Parent then break end
		local t = (tick() - warpStart) / warpDuration
		local easeT = 1 - (1 - t) ^ 2
		-- Spin vortex around its axis (absorbs toward card)
		if vortexPart and vortexPart.Parent then
			vortexPart.CFrame = vortexBaseCF * CFrame.Angles(0, t * math.pi * 4, 0)
		end
		-- Shrink parts
		for part, origSize in pairs(partsToScale) do
			if part and part.Parent then
				local s = 1 - easeT
				part.Size = origSize * math.max(0.01, s)
			end
		end
		-- Move model toward card (travels through particles to meet it)
		local newPos = warpStartPos:Lerp(warpEndPos, easeT)
		creatureModel:PivotTo(CFrame.new(newPos) * warpRotation)
		RunService.Heartbeat:Wait()
	end

	-- Phase 5: Card flash (keep visible — CaptureSuccess will shrink and move into character)
	if card and card.Parent then
		card.Color = Color3.fromRGB(255, 255, 255)
		TweenService:Create(card, tweenInfo(0.2, Enum.EasingStyle.Linear), {
			Color = Color3.fromRGB(255, 220, 100)
		}):Play()
	end
	-- Don't cleanup here — CaptureSuccess will animate card into character, CaptureFail will cleanup
end

-- Companion faint: creature turns into card at position, card flies to player
local function runCompanionFaintCardAnimation(creaturePos, creatureId)
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end

	local info = CreatureData.GetById(creatureId)
	local cardColor = info and CreatureData.Rarities[info.rarity] and CreatureData.Rarities[info.rarity].color or Color3.fromRGB(255, 220, 100)

	local cardWidth = 4
	local cardHeight = cardWidth * 1.4
	local flatRot = CFrame.Angles(math.rad(90), 0, 0)
	local cardStartPos = creaturePos + Vector3.new(0, 2, 0)
	local targetPos = root.Position + Vector3.new(0, 1.5, 0)

	local folder = Instance.new("Folder")
	folder.Name = "CompanionFaintCard"
	folder.Parent = workspace

	local card = Instance.new("Part")
	card.Name = "CompanionFaintCard"
	card.Size = Vector3.new(cardWidth, cardHeight, 0.2)
	card.CFrame = CFrame.new(cardStartPos) * flatRot
	card.Anchored = true
	card.CanCollide = false
	card.CanQuery = false
	card.CanTouch = false
	card.Material = Enum.Material.Neon
	card.Color = cardColor
	card.Parent = folder
	addCardParticles(card)

	local tweenInfo = TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	TweenService:Create(card, tweenInfo, {
		Size = Vector3.new(0.2, 0.28, 0.02),
		CFrame = CFrame.new(targetPos) * flatRot,
		Transparency = 1
	}):Play()
	task.delay(0.65, function()
		if folder and folder.Parent then folder:Destroy() end
	end)
end

-- Animate a specific capture card into the character (used so each success animates its own card)
local function animateCardIntoCharacter(card, folder)
	if not card or not card.Parent or not folder or not folder.Parent then return end
	local character = player.Character
	if not character then
		folder:Destroy()
		return
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then
		folder:Destroy()
		return
	end

	local targetPos = root.Position + Vector3.new(0, 1.5, 0)
	local targetSize = Vector3.new(0.2, 0.28, 0.02)

	-- Remove vortex so only card shrinks
	for _, child in ipairs(folder:GetChildren()) do
		if child ~= card then child:Destroy() end
	end

	-- Stop particle emitters
	for _, pe in ipairs(card:GetDescendants()) do
		if pe:IsA("ParticleEmitter") then
			pe.Rate = 0
		end
	end

	-- Shrink and move into character (0.5s)
	local tweenInfo = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	TweenService:Create(card, tweenInfo, {
		Size = targetSize,
		Position = targetPos,
		Transparency = 1
	}):Play()
	task.wait(0.55)
	if folder and folder.Parent then folder:Destroy() end
end

-- Reverse of capture: card starts small at body, grows leaving your body with effects; used when setting favorite
local runFavoriteCardAnimation = nil
runFavoriteCardAnimation = function()
	local folder = nil
	local spinConn = nil

	local function cleanup()
		if spinConn then pcall(function() spinConn:Disconnect() end); spinConn = nil end
		if folder and folder.Parent then folder:Destroy() end
	end

	-- Remove any stuck animation from a previous run
	for _, child in ipairs(workspace:GetChildren()) do
		if child.Name == "FavoriteCardAnimation" and child:IsA("Folder") then
			child:Destroy()
			break
		end
	end

	task.delay(2.5, cleanup)  -- safety: always cleanup after 2.5s max

	local ok, err = pcall(function()
		local character = player.Character
		if not character then return end
		local root = character:FindFirstChild("HumanoidRootPart")
		if not root then return end

		local bodyPos = root.Position + Vector3.new(0, 1.5, 0)
		local cardEndPos = root.Position + root.CFrame.LookVector * 4 + Vector3.new(0, 4, 0)
		local cardWidth = 4
		local cardHeight = cardWidth * 1.4

		folder = Instance.new("Folder")
		folder.Name = "FavoriteCardAnimation"
		folder.Parent = workspace

		local flatRot = CFrame.Angles(math.rad(90), 0, 0)
		local card = Instance.new("Part")
		card.Name = "FavoriteCard"
		card.Size = Vector3.new(0.2, 0.28, 0.02)
		card.CFrame = CFrame.new(bodyPos) * flatRot
		card.Anchored = true
		card.CanCollide = false
		card.CanQuery = false
		card.CanTouch = false
		card.Material = Enum.Material.Neon
		card.Color = Color3.fromRGB(200, 210, 230)
		card.Parent = folder

		addCardParticles(card)
		local vortexHeight = (cardEndPos - bodyPos).Magnitude
		local vortexPart = createVortexEffect(cardEndPos, bodyPos, math.max(4, vortexHeight), cardWidth, folder)
		local vortexBaseCF = vortexPart.CFrame

		local tweenInfo = TweenInfo.new
		local easeIn = Enum.EasingStyle.Back

		local growDuration = 0.5
		local growStart = tick()
		spinConn = RunService.Heartbeat:Connect(function()
			if not folder or not folder.Parent or not vortexPart.Parent then
				if spinConn then spinConn:Disconnect() end
				return
			end
			local t = (tick() - growStart) / growDuration
			if t >= 1 then
				if spinConn then spinConn:Disconnect() end
				return
			end
			vortexPart.CFrame = vortexBaseCF * CFrame.Angles(0, t * math.pi * 3, 0)
		end)

		local endCF = CFrame.new(cardEndPos) * flatRot
		local growTween = TweenService:Create(card, tweenInfo(growDuration, easeIn, Enum.EasingDirection.Out), {
			Size = Vector3.new(cardWidth, cardHeight, 0.2),
			CFrame = endCF
		})
		growTween:Play()
		growTween.Completed:Wait()
		if spinConn then spinConn:Disconnect(); spinConn = nil end

		task.wait(0.4)
	end)

	cleanup()
	if not ok then warn("[CaptureClient] FavoriteCardAnimation error:", err) end
end

-- Connect favorite animation event after function is defined
playFavoriteCardEvt.Event:Connect(function()
	if runFavoriteCardAnimation then task.spawn(runFavoriteCardAnimation) end
end)

-- Companion spawn: CompanionSpawned event kept for future grow effect (currently companion appears at full size)

-- Companion faint: creature turns into card, flies to player (triggers respawn cooldown on server)
if companionFainted then
	companionFainted.OnClientEvent:Connect(function(creaturePos, creatureId)
		task.spawn(function()
			runCompanionFaintCardAnimation(creaturePos, creatureId)
		end)
	end)
end

-- Companion recall: non-water creature in water → turn into card, card flies to player; favorite is carded (no cooldown, respawns when player exits water)
if companionRecalled then
	companionRecalled.OnClientEvent:Connect(function(creaturePos, creatureId)
		task.spawn(function()
			-- Hide companion model immediately so it doesn't appear frozen; card animation shows it turning into a card
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
				local myPos = root.Position
				for _, model in ipairs(CollectionService:GetTagged("FavoriteCreature")) do
					if model and model.Parent then
						local p = model:GetPivot().Position
						if (p - myPos).Magnitude <= 80 then
							model:Destroy()
							break
						end
					end
				end
			end
			runCompanionFaintCardAnimation(creaturePos, creatureId)
		end)
	end)
end

-- -- Server events --
if captureStart then
	captureStart.OnClientEvent:Connect(function(creatureModel, holdTime, captureSessionId)
		captureCancelled = false
		progressFrame.Visible = true
		progressBar.Size = UDim2.new(0, 0, 1, 0)
		progressLabel.Text = "Capturing..."
		TweenService:Create(progressBar, TweenInfo.new(holdTime, Enum.EasingStyle.Linear), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()

		if holdTime > 0 and creatureModel and creatureModel.Parent then
			task.spawn(function()
				runCaptureAnimation(creatureModel, holdTime, captureSessionId)
			end)
		end
	end)
end

local assignCaptured = eventsFolder:WaitForChild("AssignCaptured", 30)

-- Assignment prompt after capture
local function showAssignPrompt(creatureId, uid, slotInfo)
	local info = CreatureData.GetById(creatureId)
	if not info then return end
	local rc = info and CreatureData.Rarities[info.rarity]
	local rarityColor = rc and rc.color or Color3.fromRGB(180, 180, 180)

	local canIncome = slotInfo and slotInfo.canIncome
	local canDefense = slotInfo and slotInfo.canDefense

	-- If both full, just notify storage
	if not canIncome and not canDefense then
		showNotif("Captured " .. info.displayName .. "! Added to storage (all slots full)", rarityColor, 3)
		return
	end

	-- If only one option, auto-assign
	if canIncome and not canDefense then
		showNotif("Captured " .. info.displayName .. "! ? Income (defense full)", rarityColor, 2.5)
		if assignCaptured then assignCaptured:FireServer(uid, "income") end
		return
	end
	if canDefense and not canIncome then
		showNotif("Captured " .. info.displayName .. "! ? Defense (income full)", rarityColor, 2.5)
		if assignCaptured then assignCaptured:FireServer(uid, "defense") end
		return
	end

	-- Both available: show choice prompt
	local promptFrame = Instance.new("Frame")
	promptFrame.Size = UDim2.new(0, 320, 0, 140)
	promptFrame.Position = UDim2.new(0.5, -160, 0.35, 0)
	promptFrame.BackgroundColor3 = Color3.fromRGB(18, 20, 32)
	promptFrame.BorderSizePixel = 0
	promptFrame.Parent = screenGui
	Instance.new("UICorner", promptFrame).CornerRadius = UDim.new(0, 14)
	local stroke = Instance.new("UIStroke", promptFrame)
	stroke.Color = rarityColor; stroke.Thickness = 2

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, -16, 0, 22)
	titleLbl.Position = UDim2.new(0, 8, 0, 8)
	titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "Captured " .. info.displayName .. "!"
	titleLbl.TextColor3 = rarityColor
	titleLbl.Font = Enum.Font.GothamBold; titleLbl.TextSize = 14
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left; titleLbl.Parent = promptFrame

	local subLbl = Instance.new("TextLabel")
	subLbl.Size = UDim2.new(1, -16, 0, 16)
	subLbl.Position = UDim2.new(0, 8, 0, 32)
	subLbl.BackgroundTransparency = 1
	subLbl.Text = "Assign to a role:"
	subLbl.TextColor3 = Color3.fromRGB(160, 165, 180)
	subLbl.Font = Enum.Font.GothamMedium; subLbl.TextSize = 11
	subLbl.TextXAlignment = Enum.TextXAlignment.Left; subLbl.Parent = promptFrame

	local incSlots = slotInfo and (slotInfo.incomeSlots .. "/" .. slotInfo.incomeMax) or "?"
	local defSlots = slotInfo and (slotInfo.defenseSlots .. "/" .. slotInfo.defenseMax) or "?"

	local dismissed = false
	local function dismiss()
		if dismissed then return end; dismissed = true
		promptFrame:Destroy()
	end

	-- Income button
	local incBtn = Instance.new("TextButton")
	incBtn.Size = UDim2.new(0, 135, 0, 38)
	incBtn.Position = UDim2.new(0, 16, 0, 58)
	incBtn.BackgroundColor3 = Color3.fromRGB(30, 140, 70)
	incBtn.BorderSizePixel = 0
	incBtn.Text = "Income (" .. incSlots .. ")"
	incBtn.TextColor3 = Color3.new(1, 1, 1)
	incBtn.Font = Enum.Font.GothamBold; incBtn.TextSize = 13
	incBtn.Parent = promptFrame
	Instance.new("UICorner", incBtn).CornerRadius = UDim.new(0, 8)
	incBtn.MouseButton1Click:Connect(function()
		if assignCaptured then assignCaptured:FireServer(uid, "income") end
		showNotif(info.displayName .. " ? Income", Color3.fromRGB(50, 220, 120), 2)
		dismiss()
	end)

	-- Defense button
	local defBtn = Instance.new("TextButton")
	defBtn.Size = UDim2.new(0, 135, 0, 38)
	defBtn.Position = UDim2.new(0, 167, 0, 58)
	defBtn.BackgroundColor3 = Color3.fromRGB(180, 50, 60)
	defBtn.BorderSizePixel = 0
	defBtn.Text = "Defense (" .. defSlots .. ")"
	defBtn.TextColor3 = Color3.new(1, 1, 1)
	defBtn.Font = Enum.Font.GothamBold; defBtn.TextSize = 13
	defBtn.Parent = promptFrame
	Instance.new("UICorner", defBtn).CornerRadius = UDim.new(0, 8)
	defBtn.MouseButton1Click:Connect(function()
		if assignCaptured then assignCaptured:FireServer(uid, "defense") end
		showNotif(info.displayName .. " ? Defense", Color3.fromRGB(220, 60, 70), 2)
		dismiss()
	end)

	-- Storage button (skip)
	local skipBtn = Instance.new("TextButton")
	skipBtn.Size = UDim2.new(0, 286, 0, 26)
	skipBtn.Position = UDim2.new(0, 16, 0, 104)
	skipBtn.BackgroundColor3 = Color3.fromRGB(50, 52, 65)
	skipBtn.BorderSizePixel = 0
	skipBtn.Text = "Keep in Storage"
	skipBtn.TextColor3 = Color3.fromRGB(160, 165, 180)
	skipBtn.Font = Enum.Font.GothamMedium; skipBtn.TextSize = 11
	skipBtn.Parent = promptFrame
	Instance.new("UICorner", skipBtn).CornerRadius = UDim.new(0, 6)
	skipBtn.MouseButton1Click:Connect(function()
		showNotif(info.displayName .. " ? Storage", Color3.fromRGB(140, 145, 160), 2)
		dismiss()
	end)

	-- Auto-dismiss after 10 seconds
	task.delay(10, dismiss)
end

if captureSuccess then
	captureSuccess.OnClientEvent:Connect(function(creatureId, uid, cost, slotInfo, captureSessionId)
		captureCancelled = true
		captureRestoreData = nil
		if graceAreaFolder then
			graceAreaFolder:Destroy()
			graceAreaFolder = nil
		end
		progressFrame.Visible = false
		-- Animate the card for this capture (sessionId matches the card we created for this creature)
		local pending = captureSessionId and pendingCaptureCards[captureSessionId]
		if pending and pending.card and pending.folder then
			pendingCaptureCards[captureSessionId] = nil
			task.spawn(animateCardIntoCharacter, pending.card, pending.folder)
		end
		showAssignPrompt(creatureId, uid, slotInfo)
	end)
end

if captureCancel then
	captureCancel.OnClientEvent:Connect(function()
		captureCancelled = true
		restoreCreatureModel()
		progressFrame.Visible = false
	end)
end

if captureOutOfRange then
	captureOutOfRange.OnClientEvent:Connect(function(secondsLeft, creatureModel)
		ensureGraceArea(creatureModel)
		progressLabel.Text = "Return to capture area! " .. secondsLeft .. "..."
		progressLabel.TextColor3 = Color3.fromRGB(255, 180, 60)
		showNotif("Return to capture area! " .. secondsLeft, Color3.fromRGB(255, 180, 60), 1)
	end)
end

if captureFail then
	captureFail.OnClientEvent:Connect(function(message)
		captureCancelled = true
		restoreCreatureModel()
		progressFrame.Visible = false
		showNotif(message or "Capture failed!", Color3.fromRGB(60, 25, 25), 3)
	end)
end

-- Home Recall timer (similar to capture - show countdown ticking down)
if homeRecallStart then
	homeRecallStart.OnClientEvent:Connect(function(channelTime)
		recallFrame.Visible = true
		recallBar.Size = UDim2.new(0, 0, 1, 0)
		recallLabel.Text = "Recalling..."
		local startT = tick()
		TweenService:Create(recallBar, TweenInfo.new(channelTime, Enum.EasingStyle.Linear), {
			Size = UDim2.new(1, 0, 1, 0)
		}):Play()
		task.spawn(function()
			while tick() - startT < channelTime and recallFrame.Visible do
				local remaining = math.ceil(channelTime - (tick() - startT))
				recallLabel.Text = "Recalling... " .. remaining .. "s"
				task.wait(0.5)
			end
		end)
	end)
end
if homeRecallEnd then
	homeRecallEnd.OnClientEvent:Connect(function()
		recallFrame.Visible = false
		showNotif("Recall complete!", Color3.fromRGB(100, 180, 255), 2)
	end)
end
if homeRecallCancel then
	homeRecallCancel.OnClientEvent:Connect(function()
		recallFrame.Visible = false
		showNotif("Recall interrupted!", Color3.fromRGB(255, 120, 80), 2)
	end)
end
