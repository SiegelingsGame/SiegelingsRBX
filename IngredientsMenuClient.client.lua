-- IngredientsMenuClient.client.lua - StarterPlayerScripts
-- Ingredient bank UI, campfire mix/craft, world pickup prompts + sparkle FX.

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

if not getIngredientBank or not collectIngredient then return end

local cookCfg = GameConfig.Cooking or {}
if cookCfg.Enabled == false then return end

local C = {
	bg = Color3.fromRGB(14, 16, 24),
	card = Color3.fromRGB(22, 26, 38),
	muted = Color3.fromRGB(120, 125, 140),
	white = Color3.new(1, 1, 1),
	accent = Color3.fromRGB(220, 180, 90),
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

local PICKUP_TAG = "WorldIngredientPickup"
local CAMPFIRE_TAG = "ArenaCampfire"

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
		mix = data
	end
end

local function clearChildren(f)
	for _, c in ipairs(f:GetChildren()) do
		c:Destroy()
	end
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
		local btn = Instance.new("TextButton")
		btn.Name = row.id
		btn.Size = UDim2.new(1, -8, 0, 36)
		btn.BackgroundColor3 = (selectedId == row.id) and Color3.fromRGB(40, 48, 70) or C.card
		btn.BorderSizePixel = 0
		btn.AutoButtonColor = true
		btn.Text = ""
		btn.LayoutOrder = idx
		btn.Parent = bankList
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = btn
		local stroke = Instance.new("UIStroke")
		stroke.Color = rarityColor(def and def.rarity)
		stroke.Thickness = 2
		stroke.Parent = btn
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
		tr.Text = "x" .. tostring(row.n)
		tr.Parent = btn
		btn.MouseButton1Click:Connect(function()
			selectedId = row.id
			rebuildBankList()
		end)
	end
end

local function mixTotal()
	local t = 0
	for _, e in ipairs(mix) do
		t = t + (tonumber(e.qty) or 0)
	end
	return t
end

local function rebuildMixList()
	if not mixList then return end
	clearChildren(mixList)
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = mixList
	for i, e in ipairs(mix) do
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
		rm.MouseButton1Click:Connect(function()
			pcall(function()
				craftingMixRemoveSlot:InvokeServer(i)
			end)
			syncMix()
			rebuildMixList()
		end)
	end
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
			panelScale.Scale = cookMode and 0.5 or 1
		end
		syncBank()
		syncMix()
		rebuildBankList()
		rebuildMixList()
		if titleLbl then
			titleLbl.Text = cookMode and "Campfire Cooking" or "Ingredients"
		end
		if craftBtn then
			craftBtn.Visible = cookMode and craftAtCampfire ~= nil
		end
		if qualityLabel then
			if cookMode then
				qualityLabel.Text = "Projected quality: Poor x0.9 / Good x1.0 / Great x1.12 / Perfect x1.25 (potency)"
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
	Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 10)
	Instance.new("UIStroke", mainFrame).Color = Color3.fromRGB(50, 55, 75)
	panelScale = Instance.new("UIScale")
	panelScale.Scale = 1
	panelScale.Parent = mainFrame

	mainFrame.Active = true
	mainFrame.Draggable = true

	local function applyResponsiveWindowLayout()
		if not mainFrame then return end
		if MobileWindowLayout.IsMobile() then
			local bounds = MobileWindowLayout.GetBounds({
				leftInset = 12,
				rightInset = 12,
				topInset = 10,
				bottomInset = 14,
				bottomMobileExtra = 18,
			})
			local width = math.min(520, math.floor(bounds.width))
			local height = math.min(420, math.floor(bounds.height))
			mainFrame.Size = UDim2.fromOffset(width, height)
		else
			mainFrame.Size = UDim2.fromOffset(520, 420)
		end
		mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
	end
	applyResponsiveWindowLayout()
	if unbindViewportUpdate then
		unbindViewportUpdate()
	end
	unbindViewportUpdate = MobileWindowLayout.BindViewportUpdate(applyResponsiveWindowLayout)

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

	local bankScroll = Instance.new("ScrollingFrame")
	bankScroll.Name = "Bank"
	bankScroll.Position = UDim2.new(0, 12, 0, 52)
	bankScroll.Size = UDim2.new(0.48, -8, 1, -120)
	bankScroll.BackgroundColor3 = C.card
	bankScroll.BorderSizePixel = 0
	bankScroll.ScrollBarThickness = 6
	bankScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	bankScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bankScroll.Parent = mainFrame
	Instance.new("UICorner", bankScroll).CornerRadius = UDim.new(0, 8)

	bankList = Instance.new("Frame")
	bankList.BackgroundTransparency = 1
	bankList.Size = UDim2.new(1, -12, 0, 0)
	bankList.AutomaticSize = Enum.AutomaticSize.Y
	bankList.Position = UDim2.new(0, 6, 0, 8)
	bankList.Parent = bankScroll

	local mixScroll = Instance.new("ScrollingFrame")
	mixScroll.Name = "Mix"
	mixScroll.Position = UDim2.new(0.52, 0, 0, 52)
	mixScroll.Size = UDim2.new(0.48, -20, 1, -120)
	mixScroll.BackgroundColor3 = C.card
	mixScroll.BorderSizePixel = 0
	mixScroll.ScrollBarThickness = 6
	mixScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	mixScroll.Parent = mainFrame
	Instance.new("UICorner", mixScroll).CornerRadius = UDim.new(0, 8)

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
	mixHeader.Text = "Mix (3–5 items)"
	mixHeader.Parent = mixScroll

	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.Position = UDim2.new(0, 12, 1, -56)
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
		local callOk, addOk, errMsg = pcall(function()
			return craftingMixAdd:InvokeServer(selectedId, 1)
		end)
		if not callOk then
			Notify.Toast("Could not reach server", Color3.fromRGB(255, 100, 80), 2)
		elseif not addOk then
			Notify.Toast(tostring(errMsg) or "Cannot add", Color3.fromRGB(255, 100, 80), 2)
		end
		syncMix()
		rebuildMixList()
	end)

	local add5 = mkBtn("+5", 0.12, Color3.fromRGB(45, 90, 140))
	add5.Position = UDim2.new(0.18, 6, 0, 0)
	add5.Parent = btnRow
	add5.MouseButton1Click:Connect(function()
		if not selectedId then return end
		local maxMix = tonumber(cookCfg.MaxMixIngredients) or 5
		local room = maxMix - mixTotal()
		local q = math.min(5, math.max(0, room))
		if q <= 0 then return end
		local callOk, addOk, errMsg = pcall(function()
			return craftingMixAdd:InvokeServer(selectedId, q)
		end)
		if callOk and not addOk then
			Notify.Toast(tostring(errMsg) or "Cannot add", Color3.fromRGB(255, 100, 80), 2)
		end
		syncMix()
		rebuildMixList()
	end)

	local clr = mkBtn("Clear mix", 0.18, Color3.fromRGB(70, 55, 45))
	clr.Position = UDim2.new(0.32, 12, 0, 0)
	clr.Parent = btnRow
	clr.MouseButton1Click:Connect(function()
		pcall(function()
			craftingMixClear:InvokeServer()
		end)
		syncMix()
		rebuildMixList()
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

	craftBtn = mkBtn("Cook!", 0.22, Color3.fromRGB(50, 120, 70))
	craftBtn.Position = UDim2.new(0.72, 24, 0, 0)
	craftBtn.Visible = false
	craftBtn.Parent = btnRow
	craftBtn.MouseButton1Click:Connect(function()
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
	end)

	recipeFrame = Instance.new("Frame")
	recipeFrame.Name = "RecipeStage"
	recipeFrame.Visible = false
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

local function hookCampfire(inst)
	local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
	if not part then return end
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then return end
	prompt.Triggered:Connect(function()
		openCooking()
	end)
end

CollectionService:GetInstanceAddedSignal(CAMPFIRE_TAG):Connect(hookCampfire)
for _, inst in ipairs(CollectionService:GetTagged(CAMPFIRE_TAG)) do
	hookCampfire(inst)
end

local function isCampfirePrompt(prompt)
	if not prompt or not prompt:IsA("ProximityPrompt") then
		return false
	end
	local parent = prompt.Parent
	if not parent or not parent:IsA("Instance") then
		return false
	end
	if CollectionService:HasTag(parent, CAMPFIRE_TAG) then
		return true
	end
	local modelAncestor = parent:FindFirstAncestorOfClass("Model")
	if modelAncestor and CollectionService:HasTag(modelAncestor, CAMPFIRE_TAG) then
		return true
	end
	return false
end

ProximityPromptService.PromptTriggered:Connect(function(prompt, triggerPlayer)
	if triggerPlayer ~= player then
		return
	end
	if isCampfirePrompt(prompt) then
		openCooking()
	end
end)
