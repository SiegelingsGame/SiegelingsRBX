-- IngredientsMenuClient.client.lua - StarterPlayerScripts
-- Ingredient bank UI, campfire mix/craft, world pickup prompts + sparkle FX.
-- Last updated: 2026-03-28 19:00

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local IngredientData = require(ReplicatedStorage.Modules.IngredientData)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

local Events = ReplicatedStorage:FindFirstChild("Events")
if not Events then return end

local getIngredientBank = Events:FindFirstChild("GetIngredientBank")
local getCraftingMix = Events:FindFirstChild("GetCraftingMix")
local getCampfireRecipePattern = Events:FindFirstChild("GetCampfireRecipePattern")
local ingredientBankChanged = Events:FindFirstChild("IngredientBankChanged")
local collectIngredient = Events:FindFirstChild("CollectIngredient")
local craftAtCampfire = Events:FindFirstChild("CraftAtCampfire")
local craftAtCampfireWithQuality = Events:FindFirstChild("CraftAtCampfireWithQuality")
local ingredientDestroy = Events:FindFirstChild("IngredientDestroy")
local craftingMixAdd = Events:FindFirstChild("CraftingMixAdd")
local craftingMixRemoveSlot = Events:FindFirstChild("CraftingMixRemoveSlot")
local craftingMixClear = Events:FindFirstChild("CraftingMixClear")
local craftingMixPlaceAt = Events:FindFirstChild("CraftingMixPlaceAt")

if not getIngredientBank or not collectIngredient then return end

local cookCfg = GameConfig.Cooking or {}
if cookCfg.Enabled == false then return end

local C = {
	bg = Color3.fromRGB(18, 22, 28),
	card = Color3.fromRGB(26, 32, 42),
	muted = Color3.fromRGB(120, 132, 148),
	white = Color3.new(1, 1, 1),
	accent = Color3.fromRGB(220, 180, 90),
	teal = Color3.fromRGB(72, 168, 168),
	tealGlow = Color3.fromRGB(100, 220, 210),
	gold = Color3.fromRGB(230, 150, 55),
	goldDeep = Color3.fromRGB(180, 95, 35),
	cyan = Color3.fromRGB(120, 235, 255),
	pad = Color3.fromRGB(195, 200, 210),
}

local bank = {}
local mix = {}
local selectedId = nil
local cookMode = false
local gui = nil
local mainFrame = nil
local bankList = nil
local mixList = nil
local craftBtn = nil
local titleLbl = nil
local panelScale = nil
local qualityLabel = nil
local recipeFrame = nil
local recipeSeqLabel = nil
local recipeTimerLabel = nil
local recipeStatusLabel = nil
local recipeSubmitBtn = nil
local recipeToken = nil
local expectedSequence = {}
local enteredSequence = {}
local recipeStartClock = 0
local recipeTimeLimit = 12
local recipeTimerConn = nil
local closeRecipeFrame
local unbindViewportUpdate = nil

local layoutIngredients = nil
local layoutChef = nil
local ingLeftHost = nil
local chefLeftHost = nil
local craftPad = nil
local slotsHost = nil
local combineHubBtn = nil
local recipeLogList = nil
local combinePulseConn = nil
local bodyFrame = nil
local headerAccent = nil
local bankScroll = nil

local PICKUP_TAG = "WorldIngredientPickup"
local COOK_NPC_TAG = "CookNPC"
local COOK_NPC_TAG_LEGACY = "ArenaCampfire"

local function rarityColor(r)
	local rr = CreatureData.Rarities and CreatureData.Rarities[r]
	return (rr and rr.color) or C.muted
end

local function syncBank()
	local ok, data = pcall(function()
		return getIngredientBank:InvokeServer()
	end)
	if ok and type(data) == "table" then
		bank = data
	end
end

local function syncMix()
	if not getCraftingMix then return end
	local ok, data = pcall(function()
		return getCraftingMix:InvokeServer()
	end)
	if ok and type(data) == "table" then
		assignMixFromServer(data)
	end
end

local function clearChildren(f)
	for _, c in ipairs(f:GetChildren()) do
		c:Destroy()
	end
end

local function mixSlotEntryValid(e)
	return type(e) == "table" and e.id and e.id ~= "" and (tonumber(e.qty) or 0) > 0
end

local function chefMaxSlots()
	return math.min(tonumber(cookCfg.MaxMixIngredients) or CHEF_SLOT_COUNT, CHEF_SLOT_COUNT)
end

--- Dense 1..N mix array (handles sparse / string-key payloads from remotes).
local function assignMixFromServer(data)
	if type(data) ~= "table" then return end
	local maxMix = chefMaxSlots()
	local out = {}
	for i = 1, maxMix do
		local e = data[i]
		if type(e) ~= "table" then
			e = data[tostring(i)]
		end
		if mixSlotEntryValid(e) then
			out[i] = { id = tostring(e.id), qty = math.floor(tonumber(e.qty) or 0) }
		else
			out[i] = { id = "", qty = 0 }
		end
	end
	mix = out
end

local function mixTotal()
	local t = 0
	for _, e in ipairs(mix) do
		if mixSlotEntryValid(e) then
			t = t + (tonumber(e.qty) or 0)
		end
	end
	return t
end

local function qtyInMixForIngredient(ingredientId)
	if not ingredientId or ingredientId == "" then
		return 0
	end
	local t = 0
	for _, e in ipairs(mix) do
		if mixSlotEntryValid(e) and e.id == ingredientId then
			t = t + (tonumber(e.qty) or 0)
		end
	end
	return t
end

--- In cook mode, bank rows show how many of each id are still free to place (bank total minus qty already in the mix).
local function bankCountShownForRow(id, rawBankN)
	local n = tonumber(rawBankN) or 0
	if not cookMode then
		return n
	end
	return math.max(0, n - qtyInMixForIngredient(id))
end

local function rebuildBankList()
	if not bankList then return end
	clearChildren(bankList)
	local order = {}
	for id, n in pairs(bank) do
		if (tonumber(n) or 0) > 0 then
			table.insert(order, { id = id, n = n })
		end
	end
	table.sort(order, function(a, b)
		local da, db = IngredientData.GetById(a.id), IngredientData.GetById(b.id)
		local ra = (da and da.region) or ""
		local rb = (db and db.region) or ""
		if ra ~= rb then return ra < rb end
		local oa = da and CreatureData.RarityOrder and CreatureData.RarityOrder[da.rarity] or 0
		local ob = db and CreatureData.RarityOrder and CreatureData.RarityOrder[db.rarity] or 0
		if oa ~= ob then return oa < ob end
		return a.id < b.id
	end)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bankList

	for idx, row in ipairs(order) do
		local def = IngredientData.GetById(row.id)
		local shownN = bankCountShownForRow(row.id, row.n)
		local btn = Instance.new("TextButton")
		btn.Name = row.id
		local rowH = cookMode and 56 or 36
		btn.Size = UDim2.new(1, -8, 0, rowH)
		btn.BackgroundColor3 = (selectedId == row.id) and Color3.fromRGB(34, 42, 56) or C.card
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = not cookMode
		btn.Text = ""
		btn.LayoutOrder = idx
		btn.Parent = bankList
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, cookMode and 10 or 6)
		c.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.Color = (selectedId == row.id) and C.gold or rarityColor(def and def.rarity)
		stroke.Thickness = (selectedId == row.id and cookMode) and 2.5 or 2
		stroke.Transparency = 0.15
		stroke.Parent = btn

		if cookMode then
			local icon = Instance.new("Frame")
			icon.Name = "Icon"
			icon.Size = UDim2.fromOffset(44, 44)
			icon.Position = UDim2.new(0, 6, 0.5, -22)
			icon.BackgroundColor3 = Color3.fromRGB(32, 38, 50)
			icon.BorderSizePixel = 0
			icon.Parent = btn
			Instance.new("UICorner", icon).CornerRadius = UDim.new(0, 8)
			local iconStroke = Instance.new("UIStroke")
			iconStroke.Color = rarityColor(def and def.rarity)
			iconStroke.Thickness = 2
			iconStroke.Parent = icon
			local glyph = Instance.new("TextLabel")
			glyph.BackgroundTransparency = 1
			glyph.Size = UDim2.new(1, 0, 1, 0)
			glyph.Font = Enum.Font.GothamBlack
			glyph.TextSize = 20
			glyph.TextColor3 = C.white
			local nm = (def and def.displayName) or row.id
			glyph.Text = string.upper(string.sub(nm, 1, 1))
			glyph.Parent = icon
			local badge = Instance.new("TextLabel")
			badge.Name = "QtyBadge"
			badge.BackgroundColor3 = Color3.fromRGB(40, 48, 62)
			badge.Size = UDim2.fromOffset(28, 18)
			badge.Position = UDim2.new(1, -30, 0, 2)
			badge.Font = Enum.Font.GothamBold
			badge.TextSize = 11
			badge.TextColor3 = C.cyan
			badge.Text = "x" .. tostring(shownN)
			badge.Parent = icon
			Instance.new("UICorner", badge).CornerRadius = UDim.new(0, 4)
			local tl = Instance.new("TextLabel")
			tl.BackgroundTransparency = 1
			tl.Position = UDim2.new(0, 56, 0, 8)
			tl.Size = UDim2.new(1, -120, 0, 22)
			tl.Font = Enum.Font.GothamBold
			tl.TextSize = 15
			tl.TextColor3 = C.white
			tl.TextXAlignment = Enum.TextXAlignment.Left
			tl.Text = nm
			tl.Parent = btn
			local tr = Instance.new("TextLabel")
			tr.BackgroundTransparency = 1
			tr.Position = UDim2.new(1, -56, 0, 8)
			tr.Size = UDim2.fromOffset(48, 20)
			tr.Font = Enum.Font.GothamBold
			tr.TextSize = 13
			tr.TextColor3 = C.accent
			tr.TextXAlignment = Enum.TextXAlignment.Right
			tr.Text = "x" .. tostring(shownN)
			tr.Parent = btn
		else
			local tl = Instance.new("TextLabel")
			tl.BackgroundTransparency = 1
			tl.Position = UDim2.new(0, 10, 0, 0)
			tl.Size = UDim2.new(0.65, -10, 1, 0)
			tl.Font = Enum.Font.GothamMedium
			tl.TextSize = 14
			tl.TextColor3 = C.white
			tl.TextXAlignment = Enum.TextXAlignment.Left
			tl.Text = (def and def.displayName) or row.id
			tl.Parent = btn
			local tr = Instance.new("TextLabel")
			tr.BackgroundTransparency = 1
			tr.Position = UDim2.new(0.65, 0, 0, 0)
			tr.Size = UDim2.new(0.35, -10, 1, 0)
			tr.Font = Enum.Font.GothamBold
			tr.TextSize = 15
			tr.TextColor3 = C.accent
			tr.Text = "x" .. tostring(shownN)
			tr.Parent = btn
		end

		btn.MouseButton1Click:Connect(function()
			selectedId = row.id
			rebuildBankList()
		end)
	end
end

local function mixAnyFilled()
	for _, e in ipairs(mix) do
		if mixSlotEntryValid(e) then
			return true
		end
	end
	return false
end

local SLOT_UI_POS = {
	UDim2.new(0.5, 0, 0.11, 0),
	UDim2.new(0.87, 0, 0.5, 0),
	UDim2.new(0.5, 0, 0.89, 0),
	UDim2.new(0.13, 0, 0.5, 0),
}
local CHEF_SLOT_COUNT = 4

local function rebuildRecipeLog()
	if not recipeLogList then return end
	clearChildren(recipeLogList)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = recipeLogList
	if not mixAnyFilled() then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, 0, 0, 18)
		empty.Font = Enum.Font.Gotham
		empty.TextSize = 12
		empty.TextColor3 = C.muted
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Text = "Add ingredients from the bank — valid mixes follow campfire recipes."
		empty.TextWrapped = true
		empty.Parent = recipeLogList
		return
	end
	for i, e in ipairs(mix) do
		if not mixSlotEntryValid(e) then
			continue
		end
		local def = IngredientData.GetById(e.id)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = Color3.fromRGB(32, 40, 52)
		row.Size = UDim2.new(1, -4, 0, 26)
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.Parent = recipeLogList
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 6)
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(8, 8)
		dot.Position = UDim2.new(0, 8, 0.5, -4)
		dot.BackgroundColor3 = C.tealGlow
		dot.BorderSizePixel = 0
		dot.Parent = row
		Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Position = UDim2.new(0, 22, 0, 0)
		lbl.Size = UDim2.new(1, -28, 1, 0)
		lbl.Font = Enum.Font.GothamMedium
		lbl.TextSize = 12
		lbl.TextColor3 = C.white
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = string.format("%s ×%s", (def and def.displayName) or e.id, tostring(e.qty))
		lbl.Parent = row
	end
end

local function tryPlaceIngredientInSlot(si)
	if not craftingMixPlaceAt then
		Notify.Toast("Cooking service unavailable", Color3.fromRGB(255, 100, 80), 2)
		return
	end
	local callOk, ok, payload = pcall(function()
		return craftingMixPlaceAt:InvokeServer(si, selectedId, 1)
	end)
	if not callOk then
		Notify.Toast("Could not reach server", Color3.fromRGB(255, 100, 80), 2)
		syncMix()
	elseif not ok then
		Notify.Toast(tostring(payload) or "Cannot add to slot", Color3.fromRGB(255, 100, 80), 2)
		syncMix()
	elseif type(payload) == "table" then
		assignMixFromServer(payload)
	else
		syncMix()
	end
	rebuildMixList()
	rebuildBankList()
end

local function rebuildCraftingSlots()
	if not slotsHost or not craftingMixRemoveSlot then return end
	clearChildren(slotsHost)
	local maxMix = math.min(tonumber(cookCfg.MaxMixIngredients) or CHEF_SLOT_COUNT, CHEF_SLOT_COUNT)
	for si = 1, maxMix do
		local e = mix[si]
		local has = mixSlotEntryValid(e)
		local slot = Instance.new("TextButton")
		slot.Name = "Slot" .. si
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.Position = SLOT_UI_POS[si] or UDim2.new(0.5, 0, 0.5, 0)
		slot.Size = UDim2.fromOffset(62, 62)
		slot.BackgroundColor3 = has and Color3.fromRGB(44, 52, 68) or Color3.fromRGB(36, 42, 54)
		slot.BorderSizePixel = 0
		slot.AutoButtonColor = false
		slot.Text = ""
		slot.ZIndex = 2
		slot.Parent = slotsHost
		Instance.new("UICorner", slot).CornerRadius = UDim.new(1, 0)
		local sStroke = Instance.new("UIStroke")
		sStroke.Color = has and C.tealGlow or C.muted
		sStroke.Thickness = has and 2.5 or 1.5
		sStroke.Transparency = has and 0.2 or 0.5
		sStroke.Parent = slot
		if has then
			local def = IngredientData.GetById(e.id)
			local g = Instance.new("TextLabel")
			g.BackgroundTransparency = 1
			g.Size = UDim2.new(1, -4, 0.55, 0)
			g.Position = UDim2.new(0, 2, 0.08, 0)
			g.Font = Enum.Font.GothamBlack
			g.TextSize = 18
			g.TextColor3 = C.white
			g.Text = string.upper(string.sub((def and def.displayName) or e.id, 1, 1))
			g.Parent = slot
			local q = Instance.new("TextLabel")
			q.BackgroundTransparency = 1
			q.Size = UDim2.new(1, 0, 0.4, 0)
			q.Position = UDim2.new(0, 0, 0.55, 0)
			q.Font = Enum.Font.GothamBold
			q.TextSize = 11
			q.TextColor3 = C.cyan
			q.Text = "×" .. tostring(e.qty)
			q.Parent = slot
			slot.MouseButton1Click:Connect(function()
				if cookMode and selectedId and craftingMixPlaceAt then
					tryPlaceIngredientInSlot(si)
				else
					local rOk, removed, mixData = pcall(function()
						return craftingMixRemoveSlot:InvokeServer(si)
					end)
					if rOk and removed and type(mixData) == "table" then
						assignMixFromServer(mixData)
					else
						syncMix()
					end
					rebuildMixList()
					rebuildBankList()
				end
			end)
		else
			local lab = Instance.new("TextLabel")
			lab.BackgroundTransparency = 1
			lab.Size = UDim2.new(1, -4, 1, -4)
			lab.Font = Enum.Font.GothamBold
			lab.TextSize = 10
			lab.TextColor3 = C.muted
			lab.Text = "SLOT\n" .. si
			lab.TextWrapped = true
			lab.Parent = slot
			slot.MouseButton1Click:Connect(function()
				if not cookMode then
					return
				end
				if not selectedId then
					Notify.Toast("Select an ingredient, then tap a slot", Color3.fromRGB(255, 200, 100), 2.5)
					return
				end
				tryPlaceIngredientInSlot(si)
			end)
		end
	end
end

local function rebuildMixList()
	if cookMode and slotsHost then
		rebuildCraftingSlots()
		rebuildRecipeLog()
		return
	end
	if not mixList then return end
	clearChildren(mixList)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = mixList
	local maxSlots = tonumber(cookCfg.MaxMixIngredients) or CHEF_SLOT_COUNT
	for i = 1, maxSlots do
		local e = mix[i]
		if not mixSlotEntryValid(e) then
			continue
		end
		local def = IngredientData.GetById(e.id)
		local row = Instance.new("Frame")
		row.BackgroundColor3 = C.card
		row.Size = UDim2.new(1, -8, 0, 32)
		row.BorderSizePixel = 0
		row.Parent = mixList
		Instance.new("UICorner", row).CornerRadius = UDim.new(0, 4)
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.new(0.55, 0, 1, 0)
		lbl.Position = UDim2.new(0, 8, 0, 0)
		lbl.Font = Enum.Font.Gotham
		lbl.TextSize = 13
		lbl.TextColor3 = C.white
		lbl.TextXAlignment = Enum.TextXAlignment.Left
		lbl.Text = (def and def.displayName or e.id) .. " ×" .. tostring(e.qty)
		lbl.Parent = row
		local rm = Instance.new("TextButton")
		rm.Size = UDim2.new(0, 70, 0, 24)
		rm.Position = UDim2.new(1, -78, 0.5, -12)
		rm.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
		rm.TextColor3 = C.white
		rm.Text = "Remove"
		rm.Font = Enum.Font.GothamBold
		rm.TextSize = 12
		rm.Parent = row
		Instance.new("UICorner", rm).CornerRadius = UDim.new(0, 4)
		local slotIndex = i
		rm.MouseButton1Click:Connect(function()
			local rOk, removed, mixData = pcall(function()
				return craftingMixRemoveSlot:InvokeServer(slotIndex)
			end)
			if rOk and removed and type(mixData) == "table" then
				assignMixFromServer(mixData)
			else
				syncMix()
			end
			rebuildMixList()
			rebuildBankList()
		end)
	end
end

local function applyIngredientsMenuLayout()
	if not mainFrame then return end
	if MobileWindowLayout.IsMobile() then
		local bounds = MobileWindowLayout.GetBounds({
			leftInset = 12,
			rightInset = 12,
			topInset = 10,
			bottomInset = 14,
			bottomMobileExtra = 18,
		})
		local maxW = cookMode and 740 or 520
		local maxH = cookMode and 560 or 420
		local width = math.min(maxW, math.floor(bounds.width))
		local height = math.min(maxH, math.floor(bounds.height))
		mainFrame.Size = UDim2.fromOffset(width, height)
	else
		if cookMode then
			mainFrame.Size = UDim2.fromOffset(720, 540)
		else
			mainFrame.Size = UDim2.fromOffset(520, 420)
		end
	end
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
end

local function setVisible(v)
	if gui then
		gui.Enabled = v
	end
	if not v then
		closeRecipeFrame()
	end
	if v then
		if mainFrame then
			mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		end
		if panelScale then
			panelScale.Scale = 1
		end
		if layoutIngredients and layoutChef and ingLeftHost and chefLeftHost and bankScroll then
			layoutIngredients.Visible = not cookMode
			layoutChef.Visible = cookMode
			if cookMode then
				bankScroll.Parent = chefLeftHost
				bankScroll.Position = UDim2.new(0, 0, 0, 0)
				bankScroll.Size = UDim2.new(1, 0, 1, 0)
			else
				bankScroll.Parent = ingLeftHost
				bankScroll.Position = UDim2.new(0, 0, 0, 0)
				bankScroll.Size = UDim2.new(1, 0, 1, 0)
			end
		end
		if headerAccent then
			headerAccent.BackgroundColor3 = cookMode and C.teal or Color3.fromRGB(45, 52, 68)
		end
		local mfStroke = mainFrame and mainFrame:FindFirstChild("PanelStroke")
		if mfStroke and mfStroke:IsA("UIStroke") then
			mfStroke.Color = cookMode and C.tealGlow or Color3.fromRGB(50, 55, 75)
			mfStroke.Thickness = cookMode and 1.5 or 1
		end
		applyIngredientsMenuLayout()
		syncBank()
		syncMix()
		rebuildBankList()
		rebuildMixList()
		if titleLbl then
			titleLbl.Text = cookMode and "MASTER CHEF CRAFTING" or "Ingredients"
		end
		if craftBtn then
			craftBtn.Visible = false
		end
		if combineHubBtn then
			combineHubBtn.Visible = cookMode and craftAtCampfire ~= nil
		end
		if qualityLabel then
			if cookMode then
				qualityLabel.Text = "Quality tiers: Poor ×0.9 · Good ×1.0 · Great ×1.12 · Perfect ×1.25 (potency)"
			else
				qualityLabel.Text = ""
			end
		end
	end
end

local function stopRecipeTimer()
	if recipeTimerConn then
		recipeTimerConn:Disconnect()
		recipeTimerConn = nil
	end
end

closeRecipeFrame = function()
	stopRecipeTimer()
	if recipeFrame then
		recipeFrame.Visible = false
	end
	recipeToken = nil
	expectedSequence = {}
	enteredSequence = {}
end

local function updateRecipeStatus()
	if not recipeStatusLabel then return end
	local exp = table.concat(expectedSequence, "  ")
	local got = table.concat(enteredSequence, "  ")
	recipeStatusLabel.Text = "Pattern: " .. exp .. "\nYour input: " .. (got ~= "" and got or "(none)")
end

local function openRecipeFrame(recipeData)
	if not recipeFrame or type(recipeData) ~= "table" then return end
	recipeToken = tostring(recipeData.token or "")
	expectedSequence = type(recipeData.sequence) == "table" and recipeData.sequence or {}
	enteredSequence = {}
	recipeTimeLimit = tonumber(recipeData.timeLimit) or 12
	recipeStartClock = os.clock()
	recipeFrame.Visible = true
	if recipeSeqLabel then
		recipeSeqLabel.Text = "Enter recipe: " .. table.concat(expectedSequence, "  ")
	end
	updateRecipeStatus()
	if recipeTimerLabel then
		recipeTimerLabel.Text = string.format("Time: %.1fs", recipeTimeLimit)
	end
	stopRecipeTimer()
	recipeTimerConn = RunService.Heartbeat:Connect(function()
		if not recipeFrame.Visible then return end
		local left = recipeTimeLimit - (os.clock() - recipeStartClock)
		if recipeTimerLabel then
			recipeTimerLabel.Text = string.format("Time: %.1fs", math.max(0, left))
		end
		if left <= 0 then
			stopRecipeTimer()
		end
	end)
end

local function submitRecipeMinigame()
	if not recipeToken or recipeToken == "" then
		Notify.Toast("No active recipe", Color3.fromRGB(255, 120, 90), 2)
		return
	end
	local elapsedMs = math.floor((os.clock() - recipeStartClock) * 1000)
	local accuracyCount = 0
	for i = 1, #expectedSequence do
		if tostring(expectedSequence[i]) == tostring(enteredSequence[i] or "") then
			accuracyCount += 1
		end
	end
	local accuracy = (#expectedSequence > 0) and (accuracyCount / #expectedSequence) or 0
	local speed = math.clamp(1 - (elapsedMs / math.max(1, recipeTimeLimit * 1000)), 0, 1)
	local localScore = accuracy * 0.8 + speed * 0.2
	local invoke = craftAtCampfireWithQuality or craftAtCampfire
	if not invoke then
		Notify.Toast("Cooking service unavailable", Color3.fromRGB(255, 120, 90), 2)
		return
	end
	local ok, crafted, foodName, buffId, errMsg, extra = pcall(function()
		if invoke == craftAtCampfireWithQuality then
			return invoke:InvokeServer({
				token = recipeToken,
				enteredSequence = enteredSequence,
				elapsedMs = elapsedMs,
				localScore = localScore,
			})
		end
		return invoke:InvokeServer()
	end)
	if not ok then
		Notify.Toast("Craft failed (network)", Color3.fromRGB(255, 80, 80), 2)
		return
	end
	if not crafted then
		Notify.Toast(tostring(errMsg) or "Cannot cook", Color3.fromRGB(255, 120, 100), 3)
		return
	end
	local grade = extra and extra.qualityGrade
	if qualityLabel then
		if grade then
			qualityLabel.Text = ("Last quality: %s (x%.2f potency, %ss)"):format(
				tostring(grade),
				tonumber(extra.potencyMult) or 1,
				tostring(extra.durationSeconds or "?")
			)
		else
			qualityLabel.Text = "Cooked successfully."
		end
	end
	syncBank()
	syncMix()
	rebuildBankList()
	rebuildMixList()
	closeRecipeFrame()
end

local function buildGui()
	if gui then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "IngredientsMenu"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = playerGui

	mainFrame = Instance.new("Frame")
	mainFrame.Name = "Panel"
	mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	mainFrame.Size = UDim2.new(0, 520, 0, 420)
	mainFrame.BackgroundColor3 = C.bg
	mainFrame.BorderSizePixel = 0
	mainFrame.Parent = gui
	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 12)
	local panelStroke = Instance.new("UIStroke")
	panelStroke.Name = "PanelStroke"
	panelStroke.Color = Color3.fromRGB(50, 55, 75)
	panelStroke.Thickness = 1
	panelStroke.Parent = mainFrame
	panelScale = Instance.new("UIScale")
	panelScale.Scale = 1
	panelScale.Parent = mainFrame

	mainFrame.Active = true
	mainFrame.Draggable = true

	applyIngredientsMenuLayout()
	if unbindViewportUpdate then
		unbindViewportUpdate()
	end
	unbindViewportUpdate = MobileWindowLayout.BindViewportUpdate(applyIngredientsMenuLayout)

	titleLbl = Instance.new("TextLabel")
	titleLbl.BackgroundTransparency = 1
	titleLbl.Size = UDim2.new(1, -80, 0, 36)
	titleLbl.Position = UDim2.new(0, 16, 0, 8)
	titleLbl.Font = Enum.Font.GothamBlack
	titleLbl.TextSize = 20
	titleLbl.TextColor3 = C.white
	titleLbl.TextXAlignment = Enum.TextXAlignment.Left
	titleLbl.Text = "Ingredients"
	titleLbl.Parent = mainFrame

	qualityLabel = Instance.new("TextLabel")
	qualityLabel.BackgroundTransparency = 1
	qualityLabel.Size = UDim2.new(1, -160, 0, 18)
	qualityLabel.Position = UDim2.new(0, 16, 0, 34)
	qualityLabel.Font = Enum.Font.Gotham
	qualityLabel.TextSize = 12
	qualityLabel.TextColor3 = C.accent
	qualityLabel.TextXAlignment = Enum.TextXAlignment.Left
	qualityLabel.Text = ""
	qualityLabel.Parent = mainFrame

	headerAccent = Instance.new("Frame")
	headerAccent.BackgroundColor3 = Color3.fromRGB(45, 52, 68)
	headerAccent.BorderSizePixel = 0
	headerAccent.Size = UDim2.new(0.55, 0, 0, 3)
	headerAccent.Position = UDim2.new(0, 16, 0, 40)
	headerAccent.Parent = mainFrame

	local closeBtn = Instance.new("TextButton")
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.Position = UDim2.new(1, -44, 0, 8)
	closeBtn.BackgroundColor3 = Color3.fromRGB(60, 40, 40)
	closeBtn.TextColor3 = C.white
	closeBtn.Text = "X"
	closeBtn.Font = Enum.Font.GothamBold
	closeBtn.Parent = mainFrame
	Instance.new("UICorner", closeBtn).CornerRadius = UDim.new(0, 6)
	closeBtn.MouseButton1Click:Connect(function()
		cookMode = false
		closeRecipeFrame()
		setVisible(false)
	end)

	bodyFrame = Instance.new("Frame")
	bodyFrame.BackgroundTransparency = 1
	bodyFrame.ClipsDescendants = false
	bodyFrame.Position = UDim2.new(0, 0, 0, 52)
	bodyFrame.Size = UDim2.new(1, 0, 1, -104)
	bodyFrame.Parent = mainFrame

	layoutIngredients = Instance.new("Frame")
	layoutIngredients.BackgroundTransparency = 1
	layoutIngredients.Size = UDim2.new(1, 0, 1, 0)
	layoutIngredients.Parent = bodyFrame

	ingLeftHost = Instance.new("Frame")
	ingLeftHost.BackgroundTransparency = 1
	ingLeftHost.Position = UDim2.new(0, 8, 0, 4)
	ingLeftHost.Size = UDim2.new(0.48, -12, 1, -8)
	ingLeftHost.Parent = layoutIngredients

	local ingRightHost = Instance.new("Frame")
	ingRightHost.BackgroundTransparency = 1
	ingRightHost.Position = UDim2.new(0.52, 4, 0, 4)
	ingRightHost.Size = UDim2.new(0.48, -14, 1, -8)
	ingRightHost.Parent = layoutIngredients

	bankScroll = Instance.new("ScrollingFrame")
	bankScroll.Name = "Bank"
	bankScroll.Position = UDim2.new(0, 0, 0, 0)
	bankScroll.Size = UDim2.new(1, 0, 1, 0)
	bankScroll.BackgroundColor3 = C.card
	bankScroll.BorderSizePixel = 0
	bankScroll.ScrollBarThickness = 6
	bankScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	bankScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bankScroll.Parent = ingLeftHost
	Instance.new("UICorner", bankScroll).CornerRadius = UDim.new(0, 10)
	local bankStroke = Instance.new("UIStroke")
	bankStroke.Color = Color3.fromRGB(55, 65, 82)
	bankStroke.Transparency = 0.4
	bankStroke.Parent = bankScroll

	bankList = Instance.new("Frame")
	bankList.BackgroundTransparency = 1
	bankList.Size = UDim2.new(1, -12, 0, 0)
	bankList.AutomaticSize = Enum.AutomaticSize.Y
	bankList.Position = UDim2.new(0, 6, 0, 8)
	bankList.Parent = bankScroll

	local mixScroll = Instance.new("ScrollingFrame")
	mixScroll.Name = "Mix"
	mixScroll.Position = UDim2.new(0, 0, 0, 0)
	mixScroll.Size = UDim2.new(1, 0, 1, 0)
	mixScroll.BackgroundColor3 = C.card
	mixScroll.BorderSizePixel = 0
	mixScroll.ScrollBarThickness = 6
	mixScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mixScroll.Parent = ingRightHost
	Instance.new("UICorner", mixScroll).CornerRadius = UDim.new(0, 10)

	mixList = Instance.new("Frame")
	mixList.BackgroundTransparency = 1
	mixList.Size = UDim2.new(1, -12, 0, 0)
	mixList.AutomaticSize = Enum.AutomaticSize.Y
	mixList.Position = UDim2.new(0, 6, 0, 30)
	mixList.Parent = mixScroll

	local mixHeader = Instance.new("TextLabel")
	mixHeader.BackgroundTransparency = 1
	mixHeader.Size = UDim2.new(1, 0, 0, 22)
	mixHeader.Position = UDim2.new(0, 6, 0, 4)
	mixHeader.Font = Enum.Font.GothamBold
	mixHeader.TextSize = 14
	mixHeader.TextColor3 = C.muted
	mixHeader.TextXAlignment = Enum.TextXAlignment.Left
	mixHeader.Text = "Mix (3–4 items)"
	mixHeader.Parent = mixScroll

	layoutChef = Instance.new("Frame")
	layoutChef.Name = "ChefLayout"
	layoutChef.Visible = false
	layoutChef.BackgroundTransparency = 1
	layoutChef.Size = UDim2.new(1, 0, 1, 0)
	layoutChef.Parent = bodyFrame

	chefLeftHost = Instance.new("Frame")
	chefLeftHost.BackgroundTransparency = 1
	chefLeftHost.Position = UDim2.new(0, 8, 0, 4)
	chefLeftHost.Size = UDim2.new(0.30, -8, 1, -8)
	chefLeftHost.Parent = layoutChef

	local chefRightHost = Instance.new("Frame")
	chefRightHost.BackgroundTransparency = 1
	chefRightHost.Position = UDim2.new(0.30, 8, 0, 4)
	chefRightHost.Size = UDim2.new(0.70, -16, 1, -8)
	chefRightHost.Parent = layoutChef

	craftPad = Instance.new("Frame")
	craftPad.Name = "CraftPad"
	craftPad.BackgroundColor3 = C.pad
	craftPad.BackgroundTransparency = 0.08
	craftPad.Position = UDim2.new(0, 0, 0, 0)
	craftPad.Size = UDim2.new(1, -6, 1, -124)
	craftPad.BorderSizePixel = 0
	craftPad.ClipsDescendants = true
	craftPad.Parent = chefRightHost
	Instance.new("UICorner", craftPad).CornerRadius = UDim.new(0, 18)
	local padStroke = Instance.new("UIStroke")
	padStroke.Color = C.teal
	padStroke.Thickness = 1.2
	padStroke.Transparency = 0.45
	padStroke.Parent = craftPad

	slotsHost = Instance.new("Frame")
	slotsHost.Name = "Slots"
	slotsHost.BackgroundTransparency = 1
	slotsHost.Size = UDim2.new(1, -16, 1, -16)
	slotsHost.Position = UDim2.new(0, 8, 0, 8)
	slotsHost.Parent = craftPad

	combineHubBtn = Instance.new("TextButton")
	combineHubBtn.Name = "CombineHub"
	combineHubBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	combineHubBtn.Position = UDim2.new(0.5, 0, 0.5, 0)
	combineHubBtn.Size = UDim2.fromOffset(94, 94)
	combineHubBtn.BackgroundColor3 = Color3.fromRGB(48, 56, 72)
	combineHubBtn.BorderSizePixel = 0
	combineHubBtn.Text = ""
	combineHubBtn.ZIndex = 5
	combineHubBtn.AutoButtonColor = false
	combineHubBtn.Visible = false
	combineHubBtn.Parent = craftPad
	Instance.new("UICorner", combineHubBtn).CornerRadius = UDim.new(1, 0)
	local hubStroke = Instance.new("UIStroke")
	hubStroke.Color = C.gold
	hubStroke.Thickness = 4
	hubStroke.Parent = combineHubBtn
	local vortex = Instance.new("Frame")
	vortex.BackgroundColor3 = Color3.fromRGB(40, 120, 140)
	vortex.BackgroundTransparency = 0.35
	vortex.BorderSizePixel = 0
	vortex.Size = UDim2.new(1, -12, 1, -12)
	vortex.Position = UDim2.new(0, 6, 0, 6)
	vortex.ZIndex = combineHubBtn.ZIndex
	vortex.Active = false
	vortex.Parent = combineHubBtn
	Instance.new("UICorner", vortex).CornerRadius = UDim.new(1, 0)
	local vg = Instance.new("UIGradient")
	vg.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(70, 210, 230)),
		ColorSequenceKeypoint.new(0.45, Color3.fromRGB(140, 250, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(50, 140, 180)),
	})
	vg.Rotation = 0
	vg.Parent = vortex
	if combinePulseConn then
		combinePulseConn:Disconnect()
	end
	combinePulseConn = RunService.Heartbeat:Connect(function(dt)
		if not vortex.Parent then
			return
		end
		vg.Rotation = (vg.Rotation + 50 * dt) % 360
	end)
	local hubLbl = Instance.new("TextLabel")
	hubLbl.BackgroundTransparency = 1
	hubLbl.Size = UDim2.new(1, -4, 1, -4)
	hubLbl.ZIndex = combineHubBtn.ZIndex + 1
	hubLbl.Font = Enum.Font.GothamBlack
	hubLbl.TextSize = 11
	hubLbl.TextColor3 = C.white
	hubLbl.TextWrapped = true
	hubLbl.Text = "COMBINE\nRESULTS"
	hubLbl.Active = false
	hubLbl.Parent = combineHubBtn

	local recipeLogFrame = Instance.new("Frame")
	recipeLogFrame.Name = "RecipeLog"
	recipeLogFrame.AnchorPoint = Vector2.new(0, 1)
	recipeLogFrame.Position = UDim2.new(0, 0, 1, -2)
	recipeLogFrame.Size = UDim2.new(0.58, 0, 0, 116)
	recipeLogFrame.BackgroundColor3 = Color3.fromRGB(22, 28, 36)
	recipeLogFrame.BorderSizePixel = 0
	recipeLogFrame.ZIndex = 5
	recipeLogFrame.Parent = chefRightHost
	Instance.new("UICorner", recipeLogFrame).CornerRadius = UDim.new(0, 12)
	local logStroke = Instance.new("UIStroke")
	logStroke.Color = C.tealGlow
	logStroke.Thickness = 1
	logStroke.Transparency = 0.55
	logStroke.Parent = recipeLogFrame

	local logHeader = Instance.new("TextLabel")
	logHeader.BackgroundTransparency = 1
	logHeader.Size = UDim2.new(1, -12, 0, 22)
	logHeader.Position = UDim2.new(0, 8, 0, 4)
	logHeader.Font = Enum.Font.GothamBlack
	logHeader.TextSize = 11
	logHeader.TextColor3 = C.white
	logHeader.TextXAlignment = Enum.TextXAlignment.Left
	logHeader.Text = "RECIPE LOG & PREVIEW"
	logHeader.Parent = recipeLogFrame

	local logScroll = Instance.new("ScrollingFrame")
	logScroll.BackgroundTransparency = 1
	logScroll.Position = UDim2.new(0, 6, 0, 28)
	logScroll.Size = UDim2.new(1, -12, 1, -34)
	logScroll.ScrollBarThickness = 4
	logScroll.ScrollBarImageColor3 = C.teal
	logScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	logScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	logScroll.Parent = recipeLogFrame

	recipeLogList = Instance.new("Frame")
	recipeLogList.BackgroundTransparency = 1
	recipeLogList.Size = UDim2.new(1, -4, 0, 0)
	recipeLogList.AutomaticSize = Enum.AutomaticSize.Y
	recipeLogList.Parent = logScroll

	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.Position = UDim2.new(0, 12, 1, -52)
	btnRow.Size = UDim2.new(1, -24, 0, 44)
	btnRow.Parent = mainFrame

	local function mkBtn(text, xScale, color)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(xScale, -6, 1, 0)
		b.BackgroundColor3 = color or Color3.fromRGB(45, 90, 140)
		b.TextColor3 = C.white
		b.Font = Enum.Font.GothamBold
		b.TextSize = 13
		b.Text = text
		b.BorderSizePixel = 0
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		return b
	end

	local add1 = mkBtn("+1 to mix", 0.18, Color3.fromRGB(45, 90, 140))
	add1.Position = UDim2.new(0, 0, 0, 0)
	add1.Parent = btnRow
	add1.MouseButton1Click:Connect(function()
		if not selectedId then
			Notify.Toast("Select an ingredient", Color3.fromRGB(255, 180, 80), 2)
			return
		end
		local callOk, addOk, payload = pcall(function()
			return craftingMixAdd:InvokeServer(selectedId, 1)
		end)
		if not callOk then
			Notify.Toast("Could not reach server", Color3.fromRGB(255, 100, 80), 2)
			syncMix()
		elseif not addOk then
			Notify.Toast(tostring(payload) or "Cannot add", Color3.fromRGB(255, 100, 80), 2)
			syncMix()
		elseif type(payload) == "table" then
			assignMixFromServer(payload)
		else
			syncMix()
		end
		rebuildMixList()
		rebuildBankList()
	end)

	local add5 = mkBtn("+5", 0.12, Color3.fromRGB(45, 90, 140))
	add5.Position = UDim2.new(0.18, 6, 0, 0)
	add5.Parent = btnRow
	add5.MouseButton1Click:Connect(function()
		if not selectedId then return end
		local maxMix = tonumber(cookCfg.MaxMixIngredients) or CHEF_SLOT_COUNT
		local room = maxMix - mixTotal()
		local q = math.min(5, math.max(0, room))
		if q <= 0 then return end
		local callOk, addOk, payload = pcall(function()
			return craftingMixAdd:InvokeServer(selectedId, q)
		end)
		if not callOk then
			syncMix()
		elseif not addOk then
			Notify.Toast(tostring(payload) or "Cannot add", Color3.fromRGB(255, 100, 80), 2)
			syncMix()
		elseif type(payload) == "table" then
			assignMixFromServer(payload)
		else
			syncMix()
		end
		rebuildMixList()
		rebuildBankList()
	end)

	local clr = mkBtn("Clear mix", 0.18, Color3.fromRGB(70, 55, 45))
	clr.Position = UDim2.new(0.32, 12, 0, 0)
	clr.Parent = btnRow
	clr.MouseButton1Click:Connect(function()
		local cOk, mixData = pcall(function()
			return craftingMixClear:InvokeServer()
		end)
		if cOk and type(mixData) == "table" then
			assignMixFromServer(mixData)
		else
			syncMix()
		end
		rebuildMixList()
		rebuildBankList()
	end)

	local destroyB = mkBtn("Destroy 1", 0.18, Color3.fromRGB(90, 40, 40))
	destroyB.Position = UDim2.new(0.52, 18, 0, 0)
	destroyB.Parent = btnRow
	destroyB.MouseButton1Click:Connect(function()
		if not selectedId then return end
		local callOk, destroyed = pcall(function()
			return ingredientDestroy:InvokeServer(selectedId, 1)
		end)
		if callOk and destroyed then
			syncBank()
			rebuildBankList()
		elseif callOk and not destroyed then
			Notify.Toast("Cannot destroy", Color3.fromRGB(255, 100, 80), 2)
		end
	end)

	local function startCampfireCookFlow()
		if not getCampfireRecipePattern then
			submitRecipeMinigame()
			return
		end
		local ok, patternOk, dataOrMsg = pcall(function()
			return getCampfireRecipePattern:InvokeServer()
		end)
		if not ok then
			Notify.Toast("Could not start recipe", Color3.fromRGB(255, 100, 80), 2)
			return
		end
		if not patternOk then
			Notify.Toast(tostring(dataOrMsg) or "Cannot start recipe", Color3.fromRGB(255, 120, 100), 3)
			return
		end
		openRecipeFrame(dataOrMsg)
	end

	craftBtn = mkBtn("Cook!", 0.22, Color3.fromRGB(50, 120, 70))
	craftBtn.Position = UDim2.new(0.72, 24, 0, 0)
	craftBtn.Visible = false
	craftBtn.Parent = btnRow
	craftBtn.MouseButton1Click:Connect(startCampfireCookFlow)
	combineHubBtn.MouseButton1Click:Connect(startCampfireCookFlow)

	recipeFrame = Instance.new("Frame")
	recipeFrame.Name = "RecipeStage"
	recipeFrame.Visible = false
	recipeFrame.ZIndex = 15
	recipeFrame.BackgroundColor3 = Color3.fromRGB(10, 13, 20)
	recipeFrame.BorderSizePixel = 0
	recipeFrame.Size = UDim2.new(1, -24, 1, -96)
	recipeFrame.Position = UDim2.new(0, 12, 0, 52)
	recipeFrame.Parent = mainFrame
	Instance.new("UICorner", recipeFrame).CornerRadius = UDim.new(0, 8)
	local rfStroke = Instance.new("UIStroke")
	rfStroke.Color = Color3.fromRGB(70, 90, 120)
	rfStroke.Parent = recipeFrame

	recipeSeqLabel = Instance.new("TextLabel")
	recipeSeqLabel.BackgroundTransparency = 1
	recipeSeqLabel.Size = UDim2.new(1, -20, 0, 30)
	recipeSeqLabel.Position = UDim2.new(0, 10, 0, 10)
	recipeSeqLabel.Font = Enum.Font.GothamBold
	recipeSeqLabel.TextSize = 14
	recipeSeqLabel.TextColor3 = C.white
	recipeSeqLabel.TextXAlignment = Enum.TextXAlignment.Left
	recipeSeqLabel.Text = "Enter recipe:"
	recipeSeqLabel.Parent = recipeFrame

	recipeTimerLabel = Instance.new("TextLabel")
	recipeTimerLabel.BackgroundTransparency = 1
	recipeTimerLabel.Size = UDim2.new(1, -20, 0, 22)
	recipeTimerLabel.Position = UDim2.new(0, 10, 0, 42)
	recipeTimerLabel.Font = Enum.Font.GothamMedium
	recipeTimerLabel.TextSize = 13
	recipeTimerLabel.TextColor3 = Color3.fromRGB(255, 220, 130)
	recipeTimerLabel.TextXAlignment = Enum.TextXAlignment.Left
	recipeTimerLabel.Text = "Time: 12.0s"
	recipeTimerLabel.Parent = recipeFrame

	recipeStatusLabel = Instance.new("TextLabel")
	recipeStatusLabel.BackgroundTransparency = 1
	recipeStatusLabel.Size = UDim2.new(1, -20, 0, 80)
	recipeStatusLabel.Position = UDim2.new(0, 10, 0, 68)
	recipeStatusLabel.Font = Enum.Font.Gotham
	recipeStatusLabel.TextSize = 12
	recipeStatusLabel.TextColor3 = C.muted
	recipeStatusLabel.TextXAlignment = Enum.TextXAlignment.Left
	recipeStatusLabel.TextYAlignment = Enum.TextYAlignment.Top
	recipeStatusLabel.TextWrapped = true
	recipeStatusLabel.Text = ""
	recipeStatusLabel.Parent = recipeFrame

	local function addInputButton(token, x, y)
		local b = Instance.new("TextButton")
		b.Size = UDim2.new(0, 76, 0, 46)
		b.Position = UDim2.new(0, x, 0, y)
		b.BackgroundColor3 = Color3.fromRGB(35, 60, 90)
		b.BorderSizePixel = 0
		b.TextColor3 = C.white
		b.Font = Enum.Font.GothamBold
		b.TextSize = 14
		b.Text = token
		b.Parent = recipeFrame
		Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
		b.MouseButton1Click:Connect(function()
			if not recipeFrame.Visible then return end
			if #enteredSequence < #expectedSequence then
				table.insert(enteredSequence, token)
				updateRecipeStatus()
			end
		end)
	end
	addInputButton("Up", 110, 164)
	addInputButton("Left", 24, 216)
	addInputButton("Down", 110, 216)
	addInputButton("Right", 196, 216)

	recipeSubmitBtn = Instance.new("TextButton")
	recipeSubmitBtn.Size = UDim2.new(0, 120, 0, 36)
	recipeSubmitBtn.Position = UDim2.new(1, -130, 1, -44)
	recipeSubmitBtn.BackgroundColor3 = Color3.fromRGB(55, 120, 70)
	recipeSubmitBtn.BorderSizePixel = 0
	recipeSubmitBtn.TextColor3 = C.white
	recipeSubmitBtn.Font = Enum.Font.GothamBold
	recipeSubmitBtn.TextSize = 14
	recipeSubmitBtn.Text = "Finish Cook"
	recipeSubmitBtn.Parent = recipeFrame
	Instance.new("UICorner", recipeSubmitBtn).CornerRadius = UDim.new(0, 6)
	recipeSubmitBtn.MouseButton1Click:Connect(submitRecipeMinigame)

	local recipeCancelBtn = Instance.new("TextButton")
	recipeCancelBtn.Size = UDim2.new(0, 80, 0, 30)
	recipeCancelBtn.Position = UDim2.new(1, -220, 1, -41)
	recipeCancelBtn.BackgroundColor3 = Color3.fromRGB(80, 50, 50)
	recipeCancelBtn.BorderSizePixel = 0
	recipeCancelBtn.TextColor3 = C.white
	recipeCancelBtn.Font = Enum.Font.GothamBold
	recipeCancelBtn.TextSize = 12
	recipeCancelBtn.Text = "Cancel"
	recipeCancelBtn.Parent = recipeFrame
	Instance.new("UICorner", recipeCancelBtn).CornerRadius = UDim.new(0, 6)
	recipeCancelBtn.MouseButton1Click:Connect(function()
		closeRecipeFrame()
	end)
end

local function openBank()
	buildGui()
	cookMode = false
	setVisible(true)
end

local function openCooking()
	buildGui()
	cookMode = true
	setVisible(true)
end

UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.KeyCode == Enum.KeyCode.I then
		if gui and gui.Enabled then
			cookMode = false
			setVisible(false)
		else
			openBank()
		end
	end
end)

if ingredientBankChanged then
	ingredientBankChanged.OnClientEvent:Connect(function(newBank)
		if type(newBank) == "table" then
			bank = newBank
			if gui and gui.Enabled then
				rebuildBankList()
			end
		end
	end)
end

local function addPickupFx(part)
	if part:FindFirstChild("IngFX") then return end
	local att = Instance.new("Attachment")
	att.Name = "IngFX"
	att.Parent = part
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Rate = 3
	pe.Lifetime = NumberRange.new(0.4, 0.9)
	pe.Speed = NumberRange.new(0.5, 2)
	pe.SpreadAngle = Vector2.new(30, 30)
	pe.Size = NumberSequence.new(0.08, 0.02)
	pe.Transparency = NumberSequence.new(0.3, 1)
	pe.LightEmission = 0.8
	local def = IngredientData.GetById(part:GetAttribute("IngredientId"))
	if def and CreatureData.Rarities and CreatureData.Rarities[def.rarity] then
		pe.Color = ColorSequence.new(CreatureData.Rarities[def.rarity].color)
	end
	pe.Parent = att
end

local function hookPickup(part)
	if not part:IsA("BasePart") then return end
	addPickupFx(part)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	prompt.Triggered:Connect(function()
		local uid = part:GetAttribute("PickupUid")
		if uid then
			collectIngredient:FireServer(uid)
		end
	end)
end

CollectionService:GetInstanceAddedSignal(PICKUP_TAG):Connect(hookPickup)
for _, p in ipairs(CollectionService:GetTagged(PICKUP_TAG)) do
	hookPickup(p)
end

local function hasCookTag(inst)
	return CollectionService:HasTag(inst, COOK_NPC_TAG) or CollectionService:HasTag(inst, COOK_NPC_TAG_LEGACY)
end

local function hookCookNPC(inst)
	local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	prompt.Triggered:Connect(function()
		openCooking()
	end)
end

local function hookCookIfTagged(inst)
	if hasCookTag(inst) then
		hookCookNPC(inst)
	end
end

CollectionService:GetInstanceAddedSignal(COOK_NPC_TAG):Connect(hookCookIfTagged)
CollectionService:GetInstanceAddedSignal(COOK_NPC_TAG_LEGACY):Connect(hookCookIfTagged)
for _, inst in ipairs(CollectionService:GetTagged(COOK_NPC_TAG)) do
	hookCookNPC(inst)
end
for _, inst in ipairs(CollectionService:GetTagged(COOK_NPC_TAG_LEGACY)) do
	if not CollectionService:HasTag(inst, COOK_NPC_TAG) then
		hookCookNPC(inst)
	end
end

local function isCookNPCPrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end
	local parent = prompt.Parent
	if not parent or not parent:IsA("Instance") then
		return false
	end
	if hasCookTag(parent) then
		return true
	end
	local modelAncestor = parent:FindFirstAncestorOfClass("Model")
	if modelAncestor and hasCookTag(modelAncestor) then
		return true
	end
	return false
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggerPlayer)
	if triggerPlayer ~= player then
		return
	end
	if isCookNPCPrompt(prompt) then
		openCooking()
	end
end)
