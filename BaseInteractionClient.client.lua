-- BaseInteractionClient.lua - StarterPlayer.StarterPlayerScripts (LocalScript)
-- Walk-up base creature management: pick up, move, swap, sell.
-- Uses ProximityPrompts on own income/defense orbs for [E] interaction.
-- State machine: IDLE → CONTEXT_MENU → HOLDING → (place/swap/sell) → IDLE

-- ══════════════════════════════════════════════════════════════════════════════
-- SERVICES
-- ══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)

local eventsFolder = ReplicatedStorage:WaitForChild("Events", 15)
if not eventsFolder then return end

-- ══════════════════════════════════════════════════════════════════════════════
-- REMOTES
-- ══════════════════════════════════════════════════════════════════════════════

local function safeGet(name)
	return eventsFolder:FindFirstChild(name) or eventsFolder:WaitForChild(name, 5)
end

local moveCreatureSlot = safeGet("MoveCreatureSlot")
local swapCreatureSlots = safeGet("SwapCreatureSlots")
local assignToBattle = safeGet("AssignToBattle")
local sellCreature = safeGet("SellCreature")
local inspectEgg = safeGet("InspectEgg")

-- ══════════════════════════════════════════════════════════════════════════════
-- CONSTANTS & STATE
-- ══════════════════════════════════════════════════════════════════════════════

local INCOME_TAG = "BaseIncomeCreature"
local DEFENSE_TAG = "BaseDefenseCreature"
local BATTLE_TAG = "BaseBattleCreature"

-- State machine
local STATE_IDLE = "idle"
local STATE_CONTEXT = "context"
local STATE_HOLDING = "holding"
local STATE_SELL_CONFIRM = "sell_confirm"
local STATE_SWAP_MENU = "swap_menu"

local state = STATE_IDLE
local busy = false -- prevents concurrent server calls

-- Held creature data (populated during HOLDING state)
local heldData = nil -- { uid, creatureId, slotType, slotIndex, level, model, pointIndex }
local ghostModel = nil
local holdingBanner = nil

-- Menu references (for cleanup)
local activeMenuGui = nil

-- Forward declarations for functions defined later but called from resetState / pickup
local clearPointPrompts  -- removes temporary [E] prompts from base points (HOLDING state)
local attachPointPrompts -- attaches [E] prompts to matching-type base points (HOLDING state)
local isOwnCreature      -- checks if a creature model belongs to this player (FIX: forward ref)

-- Orb prompt tracking (must be declared before resetState which references it)
local attachedPrompts = {} -- [model] = ProximityPrompt (to avoid duplicates on creature orbs)

-- ScreenGui for all interaction UI
local screenGui = Instance.new("ScreenGui")
screenGui.Name = "BaseInteractionUI"
screenGui.ResetOnSpawn = false
-- Interaction prompts should stay below menus.
screenGui.DisplayOrder = 60
screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
screenGui.Parent = playerGui

-- ══════════════════════════════════════════════════════════════════════════════
-- UI HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

local UI_BG = Color3.fromRGB(14, 16, 24)
local UI_BLUE = Color3.fromRGB(60, 160, 255)
local UI_RED = Color3.fromRGB(200, 60, 60)
local UI_GOLD = Color3.fromRGB(255, 200, 50)
local UI_GREEN = Color3.fromRGB(80, 200, 100)
local UI_GREY = Color3.fromRGB(80, 85, 100)
local UI_WHITE = Color3.fromRGB(255, 255, 255)

local keyboardNavSelectedButton = nil
local keyboardNavStroke = nil

local function clearKeyboardSelection()
	if keyboardNavStroke then
		keyboardNavStroke:Destroy()
		keyboardNavStroke = nil
	end
	keyboardNavSelectedButton = nil
end

local function isButtonNavigable(btn)
	if not btn or not btn.Parent or not btn:IsA("GuiButton") then return false end
	if not btn.Active or not btn.Visible then return false end
	local size = btn.AbsoluteSize
	if size.X <= 0 or size.Y <= 0 then return false end

	local cursor = btn
	while cursor and cursor ~= playerGui do
		if cursor:IsA("GuiObject") and not cursor.Visible then
			return false
		end
		if cursor:IsA("ScreenGui") and not cursor.Enabled then
			return false
		end
		cursor = cursor.Parent
	end

	return btn:IsDescendantOf(playerGui)
end

local function getNavigableButtons()
	local buttons = {}
	for _, desc in ipairs(playerGui:GetDescendants()) do
		if desc:IsA("GuiButton") and isButtonNavigable(desc) then
			table.insert(buttons, desc)
		end
	end
	table.sort(buttons, function(a, b)
		local aPos, bPos = a.AbsolutePosition, b.AbsolutePosition
		if math.abs(aPos.Y - bPos.Y) <= 6 then
			return aPos.X < bPos.X
		end
		return aPos.Y < bPos.Y
	end)
	return buttons
end

local function setKeyboardSelection(btn)
	if not isButtonNavigable(btn) then
		clearKeyboardSelection()
		return false
	end

	if keyboardNavStroke then
		keyboardNavStroke:Destroy()
		keyboardNavStroke = nil
	end

	keyboardNavSelectedButton = btn
	local stroke = Instance.new("UIStroke")
	stroke.Name = "KeyboardNavStroke"
	stroke.Color = UI_WHITE
	stroke.Thickness = 2
	stroke.Transparency = 0.15
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = btn
	keyboardNavStroke = stroke
	return true
end

local function stepKeyboardSelection(delta)
	local buttons = getNavigableButtons()
	if #buttons == 0 then
		clearKeyboardSelection()
		return false
	end

	local currentIndex = table.find(buttons, keyboardNavSelectedButton) or 0
	local nextIndex
	if currentIndex == 0 then
		nextIndex = (delta >= 0) and 1 or #buttons
	else
		nextIndex = ((currentIndex - 1 + delta) % #buttons) + 1
	end
	return setKeyboardSelection(buttons[nextIndex])
end

local function activateKeyboardSelection()
	if not isButtonNavigable(keyboardNavSelectedButton) then
		clearKeyboardSelection()
		return false
	end
	keyboardNavSelectedButton:Activate()
	return true
end

local function isFirstPersonCameraActive()
	if player.CameraMode == Enum.CameraMode.LockFirstPerson then
		return true
	end

	local camera = workspace.CurrentCamera
	if not camera then
		return false
	end

	local camPos = camera.CFrame.Position
	local focusPos = camera.Focus.Position
	-- In Roblox first-person, camera sits essentially at focus.
	return (camPos - focusPos).Magnitude <= 1
end

local function clearMenu()
	if activeMenuGui then
		activeMenuGui:Destroy()
		activeMenuGui = nil
	end
	clearKeyboardSelection()
end

local function clearGhost()
	if ghostModel then
		ghostModel:Destroy()
		ghostModel = nil
	end
	if holdingBanner then
		holdingBanner:Destroy()
		holdingBanner = nil
	end
end

local function resetState()
	clearMenu()
	clearGhost()
	clearPointPrompts() -- Remove temporary [E] prompts from base points
	-- Restore visibility of the original model if it was hidden during pick-up
	if heldData and heldData.hiddenParts and heldData.model and heldData.model.Parent then
		for inst, original in pairs(heldData.hiddenParts) do
			if inst and inst.Parent then
				if inst:IsA("BasePart") then
					inst.Transparency = original
				elseif inst:IsA("BillboardGui") or inst:IsA("Highlight") or inst:IsA("PointLight") then
					inst.Enabled = original
				end
			end
		end
		-- Re-enable the ProximityPrompt
		local prompt = attachedPrompts[heldData.model]
		if prompt then
			prompt.Enabled = true
		end
	end
	heldData = nil
	state = STATE_IDLE
	busy = false
end

--- Create a styled button.
-- @param parent GuiObject
-- @param text string
-- @param color Color3
-- @param size UDim2
-- @param position UDim2
-- @return TextButton
local function makeButton(parent, text, color, size, position)
	local btn = Instance.new("TextButton")
	btn.Size = size
	btn.Position = position
	btn.BackgroundColor3 = color
	btn.BackgroundTransparency = 0.15
	btn.BorderSizePixel = 0
	btn.Text = text
	btn.TextColor3 = UI_WHITE
	btn.Font = Enum.Font.GothamBold
	btn.TextSize = 13
	btn.AutoButtonColor = true
	btn.Parent = parent
	Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 6)
	return btn
end

--- Create a styled panel frame.
-- @param size UDim2
-- @param position UDim2
-- @param accentColor Color3|nil
-- @return Frame
local function makePanel(size, position, accentColor)
	local frame = Instance.new("Frame")
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.BackgroundColor3 = UI_BG
	frame.BackgroundTransparency = 0.1
	frame.BorderSizePixel = 0
	frame.Parent = screenGui
	Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", frame)
	stroke.Color = accentColor or UI_BLUE
	stroke.Thickness = 1.5
	return frame
end

--- Get sell price for a creature by looking up rarity captureCost * level.
-- @param creatureId string
-- @param level number
-- @return number
local function getSellPrice(creatureId, level)
	local info = CreatureData.GetById(creatureId)
	if not info then return 0 end
	local rarityInfo = CreatureData.Rarities and CreatureData.Rarities[info.rarity]
	local baseCost = (rarityInfo and rarityInfo.captureCost) or (info.baseIncome and info.baseIncome * 5) or 50
	return math.floor(baseCost * (level or 1))
end

--- Get display name for a creature.
-- @param creatureId string
-- @return string
local function getDisplayName(creatureId)
	local info = CreatureData.GetById(creatureId)
	return info and info.displayName or creatureId
end

local function getModelDisplayName(model, creatureId)
	if model and model:GetAttribute("IsEgg") == true and model:GetAttribute("EggInspected") ~= true then
		return "Unknown Egg"
	end
	return getDisplayName(creatureId)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- GHOST MODEL (floating visual while holding a creature)
-- ══════════════════════════════════════════════════════════════════════════════

local function createGhost(originalModel)
	local ghost = originalModel:Clone()
	ghost.Name = "GhostCreature"
	-- Make semi-transparent, non-collidable; remove prompts so "E" goes to Place Here, not Manage
	for _, desc in ipairs(ghost:GetDescendants()) do
		if desc:IsA("BasePart") then
			desc.Transparency = math.max(desc.Transparency, 0.6)
			desc.CanCollide = false
			desc.CanQuery = false  -- FIX: prevent ghost from intercepting mouse raycasts / cursor
			desc.Anchored = true
		elseif desc:IsA("BillboardGui") or desc:IsA("PointLight") or desc:IsA("Highlight") then
			desc:Destroy()
		elseif desc:IsA("ProximityPrompt") then
			desc:Destroy()
		end
	end
	-- Remove tags so ghost isn't treated as a real creature
	CollectionService:RemoveTag(ghost, INCOME_TAG)
	CollectionService:RemoveTag(ghost, DEFENSE_TAG)
	CollectionService:RemoveTag(ghost, BATTLE_TAG)
	-- Add blue highlight
	local hl = Instance.new("Highlight")
	hl.FillColor = UI_BLUE
	hl.FillTransparency = 0.5
	hl.OutlineColor = UI_BLUE
	hl.OutlineTransparency = 0.3
	hl.Parent = ghost
	ghost.Parent = workspace
	return ghost
end

local function createHoldingBanner(creatureName, level)
	local banner = Instance.new("Frame")
	banner.Name = "HoldingBanner"
	banner.Size = UDim2.new(0, 500, 0, 36)
	banner.Position = UDim2.new(0.5, 0, 0, 10)
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.BackgroundColor3 = UI_BG
	banner.BackgroundTransparency = 0.15
	banner.BorderSizePixel = 0
	banner.Parent = screenGui
	Instance.new("UICorner", banner).CornerRadius = UDim.new(0, 8)
	local stroke = Instance.new("UIStroke", banner)
	stroke.Color = UI_BLUE; stroke.Thickness = 1.5

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, -50, 1, 0)
	lbl.Position = UDim2.new(0, 12, 0, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "Holding: " .. creatureName .. " Lv." .. level .. "  |  Walk to a point & hold [E]"
	lbl.TextColor3 = UI_WHITE
	lbl.Font = Enum.Font.GothamMedium
	lbl.TextSize = 14
	lbl.TextXAlignment = Enum.TextXAlignment.Left
	lbl.Parent = banner

	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Size = UDim2.new(0, 36, 0, 24)
	cancelBtn.Position = UDim2.new(1, -42, 0.5, 0)
	cancelBtn.AnchorPoint = Vector2.new(0, 0.5)
	cancelBtn.BackgroundColor3 = UI_RED
	cancelBtn.BackgroundTransparency = 0.2
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Text = "X"
	cancelBtn.TextColor3 = UI_WHITE
	cancelBtn.Font = Enum.Font.GothamBold
	cancelBtn.TextSize = 14
	cancelBtn.Parent = banner
	Instance.new("UICorner", cancelBtn).CornerRadius = UDim.new(0, 6)
	cancelBtn.MouseButton1Click:Connect(function()
		resetState()
		Notify.Toast("Cancelled", UI_GREY, 1.5)
	end)

	return banner
end

-- ══════════════════════════════════════════════════════════════════════════════
-- CONTEXT MENU (on E press — pick up / sell / cancel)
-- ══════════════════════════════════════════════════════════════════════════════

local function showContextMenu(model)
	clearMenu()
	state = STATE_CONTEXT

	local uid = model:GetAttribute("UID")
	local creatureId = model:GetAttribute("CreatureId")
	local slotType = model:GetAttribute("SlotType")
	local slotIndex = model:GetAttribute("SlotIndex")
	local level = model:GetAttribute("CreatureLevel") or 1
	local isEgg = model:GetAttribute("IsEgg") == true
	local eggInspected = model:GetAttribute("EggInspected") == true
	local displayName = getModelDisplayName(model, creatureId)
	local sellPrice = getSellPrice(creatureId, level)
	local accentColor = (slotType == "defense") and UI_RED or ((slotType == "battle") and Color3.fromRGB(130, 100, 255) or UI_GREEN)

	local panel = makePanel(UDim2.new(0, 260, 0, isEgg and 166 or 130), UDim2.new(0.5, 0, 0.5, 0), accentColor)
	activeMenuGui = panel

	-- Title
	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = displayName .. " Lv." .. level .. " (" .. slotType .. ")"
	title.TextColor3 = UI_WHITE
	title.Font = Enum.Font.GothamBold; title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel

	-- Separator
	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -16, 0, 1)
	sep.Position = UDim2.new(0, 8, 0, 34)
	sep.BackgroundColor3 = UI_GREY; sep.BorderSizePixel = 0; sep.Parent = panel

	-- Pick Up button
	local pickUpBtn = makeButton(panel, "Pick Up", UI_BLUE, UDim2.new(0.45, 0, 0, 30), UDim2.new(0.025, 0, 0, 44))
	local sellBtn = nil
	local inspectBtn = nil
	if not isEgg then
		-- Sell button (creatures only)
		sellBtn = makeButton(panel, "Sell: " .. sellPrice .. "g", UI_RED, UDim2.new(0.45, 0, 0, 30), UDim2.new(0.525, 0, 0, 44))
	else
		local inspectCost = tonumber(GameConfig.EggInspectGemCost) or 5
		local inspectText = eggInspected and "Inspected" or ("Inspect: " .. inspectCost .. " diamonds")
		inspectBtn = makeButton(panel, inspectText, eggInspected and UI_GREY or UI_GOLD, UDim2.new(0.95, 0, 0, 30), UDim2.new(0.025, 0, 0, 80))
		inspectBtn.Active = not eggInspected
		if eggInspected then
			inspectBtn.TextColor3 = Color3.fromRGB(210, 210, 210)
		end
	end
	-- Cancel button
	local cancelBtn = makeButton(panel, "Cancel", UI_GREY, UDim2.new(0.95, 0, 0, 28), UDim2.new(0.025, 0, 0, isEgg and 124 or 84))

	-- Determine the point index from the model's position context
	-- We need to find which point part this creature is sitting on
	local pointIndex = nil
	local character = player.Character
	if character then
		local plotsFolder = workspace:FindFirstChild("BasePlots")
		if plotsFolder then
			for _, plot in ipairs(plotsFolder:GetChildren()) do
				if tostring(plot:GetAttribute("OwnerUserId") or "") == tostring(player.UserId) then
					local prefix = (slotType == "income") and "IncomePoint" or ((slotType == "battle") and "BattlePoint" or "DefensePoint")
					for _, desc in ipairs(plot:GetDescendants()) do
						if desc:IsA("BasePart") and desc.Name:match("^" .. prefix .. "%d+$") then
							local num = tonumber(desc.Name:match("%d+$"))
							-- Check if the model's body is near this point
							local body = model.PrimaryPart or model:FindFirstChild("Body")
							if body and num and (body.Position - desc.Position).Magnitude < 8 then
								pointIndex = num
								break
							end
						end
					end
					break
				end
			end
		end
	end

	pickUpBtn.MouseButton1Click:Connect(function()
		clearMenu()
		state = STATE_HOLDING
		heldData = {
			uid = uid,
			creatureId = creatureId,
			slotType = slotType,
			slotIndex = slotIndex,
			level = level,
			model = model,
			pointIndex = pointIndex,
		}
		ghostModel = createGhost(model)
		holdingBanner = createHoldingBanner(displayName, level)
		-- FIX: Hide the original orb from the point so only the ghost is visible.
		-- We store the parts' original transparency so we can restore them if the
		-- pick-up is cancelled (player presses X or Cancel).
		heldData.hiddenParts = {}
		if model and model.Parent then
			for _, desc in ipairs(model:GetDescendants()) do
				if desc:IsA("BasePart") then
					heldData.hiddenParts[desc] = desc.Transparency
					desc.Transparency = 1
				elseif desc:IsA("BillboardGui") then
					heldData.hiddenParts[desc] = desc.Enabled
					desc.Enabled = false
				elseif desc:IsA("Highlight") then
					heldData.hiddenParts[desc] = desc.Enabled
					desc.Enabled = false
				elseif desc:IsA("PointLight") then
					heldData.hiddenParts[desc] = desc.Enabled
					desc.Enabled = false
				end
			end
			-- Also hide the ProximityPrompt so [E] doesn't show on the invisible orb
			local prompt = attachedPrompts[model]
			if prompt then
				prompt.Enabled = false
			end
		end
		-- Listen for original model being destroyed (e.g., raid kills it)
		if model and model.Parent then
			local conn
			conn = model.AncestryChanged:Connect(function()
				if not model.Parent then
					conn:Disconnect()
					if state == STATE_HOLDING and heldData and heldData.uid == uid then
						resetState()
						Notify.Toast("Creature was destroyed!", UI_RED, 3)
					end
				end
			end)
		end
		-- Attach [E] prompts to all matching-type base points so the player
		-- can walk to any point and press E to place / swap. Works on mobile too.
		attachPointPrompts()
		Notify.Toast("Picked up " .. displayName .. "! Walk to a point & hold [E] to place.", UI_BLUE, 2.5)
	end)

	if sellBtn then
		sellBtn.MouseButton1Click:Connect(function()
			clearMenu()
			showSellConfirm(uid, creatureId, level, slotType)
		end)
	end

	if inspectBtn then
		inspectBtn.MouseButton1Click:Connect(function()
			if busy or not inspectEgg then return end
			busy = true
			local ok, success, msg, revealedId = pcall(function()
				return inspectEgg:InvokeServer(uid)
			end)
			busy = false
			if not ok then
				Notify.Toast("Inspect failed", UI_RED, 2)
				return
			end
			if success then
				model:SetAttribute("EggInspected", true)
				if type(revealedId) == "string" and revealedId ~= "" then
					model:SetAttribute("CreatureId", revealedId)
					creatureId = revealedId
				end
				displayName = getModelDisplayName(model, creatureId)
				title.Text = displayName .. " Lv." .. level .. " (" .. slotType .. ")"
				if attachedPrompts[model] then
					attachedPrompts[model].ObjectText = displayName .. " Lv." .. level
				end
				inspectBtn.Text = "Inspected"
				inspectBtn.BackgroundColor3 = UI_GREY
				inspectBtn.TextColor3 = Color3.fromRGB(210, 210, 210)
				inspectBtn.Active = false
				local revealMsg = "Inside: " .. displayName
				if msg and msg ~= "" and msg ~= "Inspected!" then
					revealMsg = msg .. " | " .. revealMsg
				end
				Notify.Toast(revealMsg, UI_GOLD, 2.5)
			else
				Notify.Toast(msg or "Not enough diamonds", UI_RED, 2.5)
			end
		end)
	end

	cancelBtn.MouseButton1Click:Connect(function()
		resetState()
	end)

	-- Auto-dismiss if player walks too far
	task.spawn(function()
		while activeMenuGui == panel and panel.Parent do
			task.wait(0.3)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local body = model and model.Parent and (model.PrimaryPart or model:FindFirstChild("Body"))
			if not root or not body then resetState(); return end
			if (root.Position - body.Position).Magnitude > (GameConfig.BaseInteractionRange or 12) + 5 then
				resetState()
				Notify.Toast("Too far away", UI_GREY, 1.5)
				return
			end
		end
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SELL CONFIRMATION
-- ══════════════════════════════════════════════════════════════════════════════

function showSellConfirm(uid, creatureId, level, slotType)
	clearMenu()
	state = STATE_SELL_CONFIRM

	local displayName = getDisplayName(creatureId)
	local sellPrice = getSellPrice(creatureId, level)

	local panel = makePanel(UDim2.new(0, 280, 0, 120), UDim2.new(0.5, 0, 0.5, 0), UI_GOLD)
	activeMenuGui = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = "Sell " .. displayName .. " Lv." .. level .. "?"
	title.TextColor3 = UI_WHITE
	title.Font = Enum.Font.GothamBold; title.TextSize = 14
	title.TextXAlignment = Enum.TextXAlignment.Left; title.Parent = panel

	local priceLbl = Instance.new("TextLabel")
	priceLbl.Size = UDim2.new(1, -16, 0, 18)
	priceLbl.Position = UDim2.new(0, 8, 0, 32)
	priceLbl.BackgroundTransparency = 1
	priceLbl.Text = "You'll receive: " .. sellPrice .. " coins"
	priceLbl.TextColor3 = UI_GOLD
	priceLbl.Font = Enum.Font.GothamMedium; priceLbl.TextSize = 13
	priceLbl.TextXAlignment = Enum.TextXAlignment.Left; priceLbl.Parent = panel

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -16, 0, 1)
	sep.Position = UDim2.new(0, 8, 0, 56)
	sep.BackgroundColor3 = UI_GREY; sep.BorderSizePixel = 0; sep.Parent = panel

	local confirmBtn = makeButton(panel, "Confirm", UI_GOLD, UDim2.new(0.45, 0, 0, 30), UDim2.new(0.025, 0, 0, 66))
	local cancelBtn = makeButton(panel, "Cancel", UI_GREY, UDim2.new(0.45, 0, 0, 30), UDim2.new(0.525, 0, 0, 66))

	confirmBtn.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		clearMenu()
		state = STATE_IDLE
		if sellCreature then
			local ok, coins = sellCreature:InvokeServer(uid)
			if ok then
				Notify.Toast("Sold for " .. coins .. " coins!", UI_GOLD, 3)
				Notify.FloatingText("+" .. coins .. " coins", UI_GOLD)
			else
				Notify.Toast("Failed to sell", UI_RED, 2)
			end
		end
		busy = false
	end)

	cancelBtn.MouseButton1Click:Connect(function()
		resetState()
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- SWAP MENU (placing held creature at an occupied point)
-- ══════════════════════════════════════════════════════════════════════════════

--- Find a creature model by UID in the player's base (income/defense/battle tags).
local function findModelByUid(uid, slotType)
	local tag = (slotType == "defense") and DEFENSE_TAG or ((slotType == "battle") and BATTLE_TAG or INCOME_TAG)
	for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
		if tagged.Parent and isOwnCreature(tagged) and tagged:GetAttribute("UID") == uid then
			return tagged
		end
	end
	return nil
end

local function showSwapMenu(targetModel)
	clearMenu()
	clearPointPrompts() -- Hide point [E] prompts while swap menu is open
	state = STATE_SWAP_MENU

	local targetUid = targetModel:GetAttribute("UID")
	local targetCreatureId = targetModel:GetAttribute("CreatureId")
	local targetLevel = targetModel:GetAttribute("CreatureLevel") or 1
	local targetSlotIndex = targetModel:GetAttribute("SlotIndex")
	local targetPointIndex = findPointIndexNearPos(targetModel, heldData.slotType)

	local heldName = getDisplayName(heldData.creatureId)
	local targetName = getDisplayName(targetCreatureId)
	local heldSellPrice = getSellPrice(heldData.creatureId, heldData.level)
	local targetSellPrice = getSellPrice(targetCreatureId, targetLevel)

	local panel = makePanel(UDim2.new(0, 320, 0, 242), UDim2.new(0.5, 0, 0.5, 0), UI_BLUE)
	activeMenuGui = panel

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, -16, 0, 22)
	title.Position = UDim2.new(0, 8, 0, 8)
	title.BackgroundTransparency = 1
	title.Text = heldName .. " Lv." .. heldData.level .. " -> " .. targetName .. " Lv." .. targetLevel .. "'s spot"
	title.TextColor3 = UI_WHITE
	title.Font = Enum.Font.GothamBold; title.TextSize = 13
	title.TextXAlignment = Enum.TextXAlignment.Left; title.TextScaled = true
	title.Parent = panel
	local constraint = Instance.new("UITextSizeConstraint", title)
	constraint.MaxTextSize = 13; constraint.MinTextSize = 9

	local sep = Instance.new("Frame")
	sep.Size = UDim2.new(1, -16, 0, 1)
	sep.Position = UDim2.new(0, 8, 0, 34)
	sep.BackgroundColor3 = UI_GREY; sep.BorderSizePixel = 0; sep.Parent = panel

	local btnWidth = UDim2.new(0.92, 0, 0, 30)
	local btnX = 0.04

	-- Pick up the monster at this point (swap then hold that one)
	local pickUpThisBtn = makeButton(panel, "Pick up " .. targetName, UI_GREEN, btnWidth, UDim2.new(btnX, 0, 0, 44))
	local swapBtn = makeButton(panel, "Swap Positions", UI_BLUE, btnWidth, UDim2.new(btnX, 0, 0, 80))
	local sellHeldBtn = makeButton(panel, "Sell " .. heldName .. " (" .. heldSellPrice .. "g)", Color3.fromRGB(200, 100, 60), btnWidth, UDim2.new(btnX, 0, 0, 116))
	local sellPlacedBtn = makeButton(panel, "Sell " .. targetName .. " (" .. targetSellPrice .. "g)", Color3.fromRGB(200, 100, 60), btnWidth, UDim2.new(btnX, 0, 0, 152))
	local cancelBtn = makeButton(panel, "Cancel", UI_GREY, btnWidth, UDim2.new(btnX, 0, 0, 188))

	pickUpThisBtn.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		clearMenu()
		clearGhost()
		local swapOk = false
		local swapMsg = nil
		if heldData.slotType == "battle" and assignToBattle then
			assignToBattle:FireServer(heldData.uid, targetSlotIndex)  -- Swap
			swapOk = true
		elseif swapCreatureSlots then
			local ok, msg = swapCreatureSlots:InvokeServer(heldData.slotType, heldData.uid, targetUid)
			swapOk = ok
			swapMsg = msg
		end
		if swapOk then
			-- After swap, the creature that was at this point is now at our old slot.
			-- Transition to holding that one.
			local oldSlotIndex, oldPointIndex = heldData.slotIndex, heldData.pointIndex
			task.wait(0.25) -- allow server to replicate new models
			local newModel = findModelByUid(targetUid, heldData.slotType)
			if newModel and newModel.Parent then
				state = STATE_HOLDING
				heldData = {
					uid = targetUid,
					creatureId = targetCreatureId,
					slotType = heldData.slotType,
					slotIndex = oldSlotIndex,
					level = targetLevel,
					model = newModel,
					pointIndex = oldPointIndex,
				}
				ghostModel = createGhost(newModel)
				holdingBanner = createHoldingBanner(targetName, targetLevel)
				heldData.hiddenParts = {}
				for _, desc in ipairs(newModel:GetDescendants()) do
					if desc:IsA("BasePart") then
						heldData.hiddenParts[desc] = desc.Transparency
						desc.Transparency = 1
					elseif desc:IsA("BillboardGui") or desc:IsA("Highlight") or desc:IsA("PointLight") then
						heldData.hiddenParts[desc] = desc.Enabled
						desc.Enabled = false
					end
				end
				local prompt = attachedPrompts[newModel]
				if prompt then prompt.Enabled = false end
				attachPointPrompts()
				Notify.Toast("Now holding " .. targetName .. " — walk to a point & press [E]", UI_GREEN, 2.5)
			else
				-- Swap succeeded on server but model not found client-side yet
				heldData = nil
				state = STATE_IDLE
				Notify.Toast("Swapped! (Could not pick up here)", UI_BLUE, 2)
			end
		else
			Notify.Toast("Swap failed: " .. (swapMsg or ""), UI_RED, 2)
			resetState()
		end
		busy = false
	end)

	swapBtn.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		clearMenu()
		clearGhost()
		if heldData.slotType == "battle" and assignToBattle then
			-- Battle: AssignToBattle(uid, slotIndex) swaps when target occupied
			assignToBattle:FireServer(heldData.uid, targetSlotIndex)
			Notify.Toast("Swapped positions!", UI_BLUE, 2.5)
			heldData = nil
			state = STATE_IDLE
		elseif swapCreatureSlots then
			local ok, msg = swapCreatureSlots:InvokeServer(heldData.slotType, heldData.uid, targetUid)
			if ok then
				Notify.Toast("Swapped positions!", UI_BLUE, 2.5)
				heldData = nil; state = STATE_IDLE
			else
				Notify.Toast("Swap failed: " .. (msg or ""), UI_RED, 2)
				resetState()
			end
		else
			resetState()
		end
		busy = false
	end)

	sellHeldBtn.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		clearMenu()
		clearGhost()
		if sellCreature then
			local ok, coins = sellCreature:InvokeServer(heldData.uid)
			if ok then
				Notify.Toast("Sold " .. heldName .. " for " .. coins .. " coins!", UI_GOLD, 3)
				Notify.FloatingText("+" .. coins .. " coins", UI_GOLD)
				heldData = nil; state = STATE_IDLE
			else
				Notify.Toast("Failed to sell", UI_RED, 2)
				resetState()
			end
		else
			resetState()
		end
		busy = false
	end)

	sellPlacedBtn.MouseButton1Click:Connect(function()
		if busy then return end
		busy = true
		clearMenu()
		clearGhost()
		-- Sell the placed creature, then move held to its spot
		if sellCreature then
			local ok, coins = sellCreature:InvokeServer(targetUid)
			if ok then
				Notify.Toast("Sold " .. targetName .. " for " .. coins .. " coins!", UI_GOLD, 3)
				Notify.FloatingText("+" .. coins .. " coins", UI_GOLD)
				-- Now the point is empty — find its point index and move held creature there
				local targetPointIndex = findPointIndexNearPos(targetModel, heldData.slotType)
				if targetPointIndex then
					task.wait(0.2) -- brief wait for server to clear the sold creature
					if heldData.slotType == "battle" and assignToBattle then
						assignToBattle:FireServer(heldData.uid, targetPointIndex)
						Notify.Toast("Placed " .. heldName .. "!", UI_GREEN, 2)
					elseif moveCreatureSlot then
						local moveOk, moveMsg = moveCreatureSlot:InvokeServer(heldData.slotType, heldData.uid, targetPointIndex)
						if moveOk then
							Notify.Toast("Placed " .. heldName .. "!", UI_GREEN, 2)
						end
					end
				end
				heldData = nil; state = STATE_IDLE
			else
				Notify.Toast("Failed to sell", UI_RED, 2)
				resetState()
			end
		else
			resetState()
		end
		busy = false
	end)

	cancelBtn.MouseButton1Click:Connect(function()
		-- Return to holding state — re-attach point prompts so player can pick another point
		clearMenu()
		state = STATE_HOLDING
		attachPointPrompts()
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- POINT DETECTION HELPERS
-- ══════════════════════════════════════════════════════════════════════════════

--- True if part is inside a folder with the given name (e.g. "IncomePoints", "DefensePoints").
local function isPartInFolderNamed(part, folderName)
	local current = part.Parent
	while current do
		if current.Name == folderName then return true end
		current = current.Parent
	end
	return false
end

--- Find the player's own plot model.
-- @return Model|nil
local function findOwnPlot()
	local plotsFolder = workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return nil end
	for _, plot in ipairs(plotsFolder:GetChildren()) do
		if tostring(plot:GetAttribute("OwnerUserId") or "") == tostring(player.UserId) then
			return plot
		end
	end
	return nil
end

--- Find point index from a model's body position (used when we need the point
--- number for a creature that's sitting on a point).
-- @param model Model the creature model
-- @param slotType string "income", "defense", or "battle"
-- @return number|nil point index from the part name
function findPointIndexNearPos(model, slotType)
	local body = model and (model.PrimaryPart or model:FindFirstChild("Body"))
	if not body then return nil end
	local plot = findOwnPlot()
	if not plot then return nil end
	local prefix = (slotType == "income") and "IncomePoint" or ((slotType == "battle") and "BattlePoint" or "DefensePoint")
	local bestDist, bestIdx = 8, nil
	for _, desc in ipairs(plot:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:match("^" .. prefix .. "%d+$") then
			local num = tonumber(desc.Name:match("%d+$"))
			local dist = (body.Position - desc.Position).Magnitude
			if num and dist < bestDist then
				bestDist = dist
				bestIdx = num
			end
		end
	end
	return bestIdx
end

--- Find if there's a creature orb sitting on/near a point.
-- @param pointPart BasePart the point part
-- @param slotType string "income", "defense", or "battle"
-- @return Model|nil the creature orb model, or nil if point is empty
local function findCreatureAtPoint(pointPart, slotType)
	local tag = (slotType == "defense") and DEFENSE_TAG or ((slotType == "battle") and BATTLE_TAG or INCOME_TAG)
	for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
		if tagged.Parent and isOwnCreature(tagged) then
			local body = tagged.PrimaryPart or tagged:FindFirstChild("Body")
			if body and (body.Position - pointPart.Position).Magnitude < 8 then
				return tagged
			end
		end
	end
	return nil
end

-- ══════════════════════════════════════════════════════════════════════════════
-- POINT PROXIMITY PROMPTS (shown on base points while HOLDING a creature)
-- Replaces click-to-place: player walks to a point and presses [E] to place.
-- Works on desktop AND mobile (ProximityPrompts have native touch support).
-- ══════════════════════════════════════════════════════════════════════════════

local activePointPrompts = {} -- [BasePart pointPart] = ProximityPrompt

--- Remove all temporary point ProximityPrompts (called on cancel/complete/state reset).
--- Also re-enables creature "Manage" prompts that were disabled during HOLDING.
-- (Forward-declared near top of file so resetState can call it.)
clearPointPrompts = function()
	for pointPart, prompt in pairs(activePointPrompts) do
		if prompt and prompt.Parent then
			prompt:Destroy()
		end
	end
	activePointPrompts = {}
	-- Re-enable creature "Manage" prompts that were disabled during HOLDING
	for model, prompt in pairs(attachedPrompts) do
		if not prompt then
			attachedPrompts[model] = nil
		elseif not prompt.Parent then
			attachedPrompts[model] = nil
		else
			prompt.Enabled = true
		end
	end
end

--- Attach temporary ProximityPrompts to all matching-type base points while holding
--- a creature. Empty points get "[E] Place Here", occupied points get "[E] Swap".
--- The held creature's own original point is skipped (same-position cancel is pointless).
-- (Forward-declared near top of file so pickup handler can call it.)
attachPointPrompts = function()
	clearPointPrompts() -- safety: remove any leftover
	if not heldData then
		print("[BaseInteraction] attachPointPrompts: no heldData, skipping")
		return
	end

	local plot = findOwnPlot()
	local usedFallback = false
	-- Fallback: get plot from held creature's hierarchy (in case OwnerUserId hasn't replicated to client)
	if not plot and heldData.model and heldData.model.Parent then
		local plotsFolder = workspace:FindFirstChild("BasePlots")
		if plotsFolder then
			local p = heldData.model.Parent
			while p and p ~= workspace do
				if p.Parent == plotsFolder then plot = p usedFallback = true break end
				p = p.Parent
			end
		end
	end
	if not plot then
		print("[BaseInteraction] attachPointPrompts: no plot found (findOwnPlot + hierarchy fallback)")
		return
	end
	print("[BaseInteraction] attachPointPrompts: plot=" .. tostring(plot.Name) .. (usedFallback and " (via fallback)" or " (OwnerUserId)"))

	local prefix = (heldData.slotType == "income") and "IncomePoint" or ((heldData.slotType == "battle") and "BattlePoint" or "DefensePoint")
	-- Use slightly larger range for placement so standing on defense platform can reach adjacent empty points
	local promptRange = GameConfig.BasePlacementPromptRange or GameConfig.BaseInteractionRange or 12

	-- Disable ALL creature "Manage" prompts during HOLDING to prevent conflict
	-- with the temporary point prompts. Both use [E] key and can interfere.
	-- They'll be re-enabled in clearPointPrompts().
	for model, prompt in pairs(attachedPrompts) do
		if prompt and prompt.Parent then
			prompt.Enabled = false
		end
	end

	local wantFolder = (heldData.slotType == "income") and "IncomePoints" or ((heldData.slotType == "battle") and "BattleTeam" or "DefensePoints")

	local function addPromptForPoint(desc, pointIndex)
		-- Include the point we picked up from so standing on any Floor 1 point shows [E] (Place Here / Put Back) like walking up to a model
		local occupant = findCreatureAtPoint(desc, heldData.slotType)
		local isOccupied = occupant ~= nil and occupant:GetAttribute("UID") ~= heldData.uid

		local prompt = Instance.new("ProximityPrompt")
		prompt.MaxActivationDistance = promptRange
		prompt.RequiresLineOfSight = false
		prompt.HoldDuration = tonumber(GameConfig.BasePlacementHoldDuration) or 0.08
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Exclusivity = Enum.ProximityPromptExclusivity.AlwaysShow

		if isOccupied then
			local occupantName = getDisplayName(occupant:GetAttribute("CreatureId"))
			local occupantLevel = occupant:GetAttribute("CreatureLevel") or 1
			prompt.ActionText = "Swap"
			prompt.ObjectText = occupantName .. " Lv." .. occupantLevel
		else
			prompt.ActionText = "Place Here"
			prompt.ObjectText = desc.Name
		end

		prompt.Parent = desc

		prompt.Triggered:Connect(function(playerWhoTriggered)
			print("[BaseInteraction] Place prompt Triggered on " .. tostring(desc.Name) .. " by " .. tostring(playerWhoTriggered and playerWhoTriggered.Name))
			if playerWhoTriggered ~= player then print("[BaseInteraction]   -> ignore: wrong player") return end
			if state ~= STATE_HOLDING then print("[BaseInteraction]   -> ignore: state=" .. tostring(state)) return end
			if busy then print("[BaseInteraction]   -> ignore: busy") return end
			if not heldData then print("[BaseInteraction]   -> ignore: no heldData, resetting") resetState() return end

			if isOccupied and occupant and occupant.Parent then
				showSwapMenu(occupant)
			else
				busy = true
				clearMenu()
				clearPointPrompts()
				-- Ensure the holding UI always disappears immediately on a successful place.
				-- We intentionally do NOT call resetState() here because it would restore the hidden original
				-- orb parts; the server will replicate the moved orb shortly after.
				local function finalizeSuccessfulPlace()
					clearGhost() -- destroys ghostModel + holdingBanner
					heldData = nil
					state = STATE_IDLE
				end
				local targetPointIndex = pointIndex
				if type(targetPointIndex) ~= "number" then
					Notify.Toast("Invalid point", UI_RED, 2)
					resetState()
					busy = false
					return
				end
				if heldData.slotType == "battle" then
					-- Battle uses AssignToBattle (move = reassign to new slot)
					if assignToBattle then
						assignToBattle:FireServer(heldData.uid, targetPointIndex)
						Notify.Toast("Moved " .. getDisplayName(heldData.creatureId) .. "!", UI_GREEN, 2.5)
						finalizeSuccessfulPlace()
					else
						Notify.Toast("Cannot place (battle not available). Try rejoining.", UI_RED, 3)
						resetState()
					end
				elseif moveCreatureSlot then
					print("[BaseInteraction] InvokeServer MoveCreatureSlot " .. tostring(heldData.slotType) .. " uid=" .. tostring(heldData.uid) .. " pointIndex=" .. tostring(targetPointIndex))
					local ok, msg = moveCreatureSlot:InvokeServer(
						heldData.slotType, heldData.uid, targetPointIndex
					)
					print("[BaseInteraction] MoveCreatureSlot result: ok=" .. tostring(ok) .. " msg=" .. tostring(msg))
					if ok then
						Notify.Toast(
							"Moved " .. getDisplayName(heldData.creatureId) .. "!",
							UI_GREEN, 2.5
						)
						finalizeSuccessfulPlace()
					else
						Notify.Toast("Move failed: " .. (tostring(msg or "unknown")), UI_RED, 2)
						resetState()
					end
				else
					print("[BaseInteraction] MoveCreatureSlot remote is nil - cannot place")
					Notify.Toast("Cannot place (move not available). Try rejoining.", UI_RED, 3)
					resetState()
				end
				busy = false
			end
		end)

		activePointPrompts[desc] = prompt
	end

	-- First pass: points in the correct folder (IncomePoints/DefensePoints)
	for _, desc in ipairs(plot:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Name:match("^" .. prefix .. "%d+$") then
			if not isPartInFolderNamed(desc, wantFolder) then continue end
			local pointIndex = tonumber(desc.Name:match("%d+$"))
			if pointIndex then addPromptForPoint(desc, pointIndex) end
		end
	end

	-- Fallback: if no prompts added (e.g. folder name differs), add for any point-named part in plot
	if next(activePointPrompts) == nil then
		for _, desc in ipairs(plot:GetDescendants()) do
			if desc:IsA("BasePart") and desc.Name:match("^" .. prefix .. "%d+$") then
				local pointIndex = tonumber(desc.Name:match("%d+$"))
				if pointIndex then addPromptForPoint(desc, pointIndex) end
			end
		end
	end
	local n = 0
	for _ in pairs(activePointPrompts) do n = n + 1 end
	print("[BaseInteraction] attachPointPrompts: added " .. n .. " [E] prompts for " .. prefix)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- PROXIMITY PROMPT MANAGEMENT
-- ══════════════════════════════════════════════════════════════════════════════

-- (attachedPrompts declared at top of file, near other forward declarations)

-- FIX: Assign to forward-declared local (not `local function`) so findModelByUid
-- and findCreatureAtPoint can reference it before this line is reached at load time.
isOwnCreature = function(model)
	local ownerId = model:GetAttribute("OwnerUserId")
	if ownerId == nil then return false end
	return tostring(ownerId) == tostring(player.UserId)
end

--- Get the part to attach the ProximityPrompt to. Replication can delay PrimaryPart; fallback to any BasePart.
local function getOrbBodyPart(model)
	if not model then return nil end
	local body = model.PrimaryPart or model:FindFirstChild("Body") or model:FindFirstChild("HumanoidRootPart")
	if body and body:IsA("BasePart") then return body end
	for _, desc in ipairs(model:GetDescendants()) do
		if desc:IsA("BasePart") then return desc end
	end
	return nil
end

local function attachPromptToOrb(model)
	if not model or not model.Parent then return end
	if attachedPrompts[model] then return end
	if not isOwnCreature(model) then return end
	local slotType = model:GetAttribute("SlotType")
	if slotType ~= "income" and slotType ~= "defense" and slotType ~= "battle" then return end

	local body = getOrbBodyPart(model)
	if not body then return end

	local creatureId = model:GetAttribute("CreatureId")
	local displayName = getModelDisplayName(model, creatureId)
	local level = model:GetAttribute("CreatureLevel") or 1

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Manage"
	prompt.ObjectText = displayName .. " Lv." .. level
	prompt.MaxActivationDistance = GameConfig.BaseInteractionRange or 12
	prompt.RequiresLineOfSight = false
	prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = body

	prompt.Triggered:Connect(function(playerWhoTriggered)
		print("[BaseInteraction] Manage prompt Triggered on " .. tostring(displayName) .. " by " .. tostring(playerWhoTriggered and playerWhoTriggered.Name))
		if playerWhoTriggered ~= player then return end
		if busy then return end
		if state == STATE_IDLE then
			-- Normal interaction: show context menu
			showContextMenu(model)
		elseif state == STATE_HOLDING and heldData then
			-- Holding a creature: pressing E on another creature triggers swap/place
			local orbSlotType = model:GetAttribute("SlotType")
			local orbUid = model:GetAttribute("UID")
			if orbUid == heldData.uid then return end -- pressed E on the same creature
			if orbSlotType == heldData.slotType then
				showSwapMenu(model)
			else
				Notify.Toast("Can only move within same type!", UI_RED, 2)
			end
		end
		-- Ignore E during CONTEXT, SELL_CONFIRM, SWAP_MENU states (menu already open)
	end)

	attachedPrompts[model] = prompt

	-- Cleanup when model is destroyed
	model.AncestryChanged:Connect(function()
		if not model.Parent then
			attachedPrompts[model] = nil
		end
	end)
end

local function scanAndAttachPrompts()
	for _, tag in ipairs({INCOME_TAG, DEFENSE_TAG, BATTLE_TAG}) do
		for _, model in ipairs(CollectionService:GetTagged(tag)) do
			attachPromptToOrb(model)
		end
	end
end

-- Wait for OwnerUserId/attributes to replicate, then attach; retry a few times so defense/income orbs always get [E].
local MAX_ATTACH_RETRIES = 4
local ATTACH_RETRY_DELAY = 0.8

local function tryAttachWithRetry(model)
	for attempt = 1, MAX_ATTACH_RETRIES do
		task.wait(ATTACH_RETRY_DELAY)
		if not model or not model.Parent then return end
		if attachedPrompts[model] then return end
		-- Retry until OwnerUserId replicates (often delayed for defense/income orbs)
		if isOwnCreature(model) then
			attachPromptToOrb(model)
			return
		end
	end
end

-- Auto-attach prompts when new orbs spawn (e.g. defense creatures placed by BasePlacementSystem)
for _, tag in ipairs({INCOME_TAG, DEFENSE_TAG, BATTLE_TAG}) do
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(model)
		task.spawn(function()
			tryAttachWithRetry(model)
		end)
	end)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- GHOST POSITION UPDATE (every frame while holding)
-- ══════════════════════════════════════════════════════════════════════════════

RunService.RenderStepped:Connect(function()
	if state ~= STATE_HOLDING or not ghostModel then return end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local pos = root.Position + root.CFrame.LookVector * 4 + Vector3.new(0, 3, 0)
	ghostModel:PivotTo(CFrame.new(pos))
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- KEYBOARD SHORTCUT: X to cancel holding
-- ══════════════════════════════════════════════════════════════════════════════

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if UserInputService:GetFocusedTextBox() then return end
	if input.UserInputType ~= Enum.UserInputType.Keyboard then return end

	if isFirstPersonCameraActive() then
		if input.KeyCode == Enum.KeyCode.Up or input.KeyCode == Enum.KeyCode.Left then
			if stepKeyboardSelection(-1) then return end
		elseif input.KeyCode == Enum.KeyCode.Down or input.KeyCode == Enum.KeyCode.Right then
			if stepKeyboardSelection(1) then return end
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			if activateKeyboardSelection() then return end
		end
	else
		clearKeyboardSelection()
	end

	if gameProcessed then return end
	if input.KeyCode == Enum.KeyCode.X then
		if state == STATE_HOLDING or state == STATE_SWAP_MENU or state == STATE_CONTEXT or state == STATE_SELL_CONFIRM then
			resetState()
			Notify.Toast("Cancelled", UI_GREY, 1.5)
		end
	end
end)

-- ══════════════════════════════════════════════════════════════════════════════
-- INITIALIZATION
-- ══════════════════════════════════════════════════════════════════════════════

-- Attach prompts to existing orbs after a brief delay (let BasePlacementSystem finish spawning)
task.spawn(function()
	task.wait(3)
	scanAndAttachPrompts()
	-- Re-scan so defense/income orbs that spawn after 3s (e.g. late PlaceCreatures) still get [E]
	task.wait(5)
	scanAndAttachPrompts()
	task.wait(7)
	scanAndAttachPrompts()
end)

-- Re-scan when character respawns (prompts may need re-attachment)
player.CharacterAdded:Connect(function()
	task.wait(2)
	resetState()
	scanAndAttachPrompts()
end)

print("[BaseInteractionClient] Loaded — walk-up base creature management ready")
