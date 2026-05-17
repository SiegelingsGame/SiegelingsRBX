-- IngredientsMenuClient.client.lua - StarterPlayerScripts
-- Ingredient bank UI, campfire mix/craft, world pickup prompts + sparkle FX.
-- Layout: bankColumn | rightNormal (mix) OR rightChef (craft) — non-overlapping columns, no reparent hacks.
-- Rojo: default.project.json → StarterPlayer.StarterPlayerScripts.IngredientsMenuClient (this file). Run `rojo serve` from repo root, connect the Rojo plugin in Studio.
-- If the build stamp (top-right of the panel) does not match ING_UI_BUILD, Studio is not using this file — paste/sync from this repo into StarterPlayer > StarterPlayerScripts.

local ING_UI_BUILD = "2026-04-11 v15"

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local IngredientData = require(ReplicatedStorage.Modules.IngredientData)
local Notify = require(ReplicatedStorage.Modules.NotificationManager)
local MobileWindowLayout = require(ReplicatedStorage.Modules:WaitForChild("MobileWindowLayout"))

-- Same as Inventory UI: wait for Events/remotes. FindFirstChild at script start often runs before replication
-- finishes, so GetIngredientBank was nil → whole script exited, or InvokeServer targeted a bad ref → empty bank.
local Events = ReplicatedStorage:WaitForChild("Events", 30)
if not Events then
	warn("[IngredientsMenu] ReplicatedStorage.Events not found")
	return
end

local getIngredientBank = Events:WaitForChild("GetIngredientBank", 30)
local collectIngredient = Events:WaitForChild("CollectIngredient", 30)
-- Wait for mix/craft remotes — FindFirstChild at startup often runs before replication finishes,
-- leaving nil forever and breaking chef slots + sync (blank craft pad, empty mix).
local getCraftingMix = Events:WaitForChild("GetCraftingMix", 30)
local getCampfireRecipePattern = Events:WaitForChild("GetCampfireRecipePattern", 30)
local ingredientBankChanged = Events:FindFirstChild("IngredientBankChanged")
local ingredientPickupCollected = Events:FindFirstChild("IngredientPickupCollected")
	or Events:WaitForChild("IngredientPickupCollected", 25)
local craftAtCampfire = Events:WaitForChild("CraftAtCampfire", 30)
local craftAtCampfireWithQuality = Events:WaitForChild("CraftAtCampfireWithQuality", 30)
local craftingMixAdd = Events:WaitForChild("CraftingMixAdd", 30)
local craftingMixRemoveSlot = Events:WaitForChild("CraftingMixRemoveSlot", 30)
local craftingMixClear = Events:WaitForChild("CraftingMixClear", 30)
local craftingMixPlaceAt = Events:WaitForChild("CraftingMixPlaceAt", 30)

if not getIngredientBank or not collectIngredient then
	warn("[IngredientsMenu] GetIngredientBank or CollectIngredient missing")
	return
end

local cookCfg = GameConfig.Cooking or {}
if cookCfg.Enabled == false then
	warn(
		"[IngredientsMenu] GameConfig.Cooking.Enabled is false — this script exits. Bag/inventory can still show ingredients via GetIngredientBank; cooking UI and pickups from this LocalScript are disabled."
	)
	return
end

local function canStartCampfireCook()
	return (craftAtCampfire ~= nil) or (craftAtCampfireWithQuality ~= nil)
end

-- Nominal desktop sizes (cook mode is largest; used for fullscreen / compact detection)
local ING_DESIGN_W = 720
local ING_DESIGN_H = 540

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
local bankSyncGeneration = 0
local selectedId = nil
local cookMode = false
local gui = nil
local mainFrame = nil
local bankList = nil
local mixList = nil
local craftBtn = nil
local titleLbl = nil
local applyIngredientsTitleLayout = nil
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
local recipeSubmitInFlight = false
local closeRecipeFrame
local unbindViewportUpdate = nil
-- Use sentinel so first open is never blocked (now - 0 < 0.3 would skip the first ~0.3s of session time).
local lastCookOpenClock = -1

local bankColumn = nil
local rightNormal = nil
local rightChef = nil
local craftPad = nil
local slotsHost = nil
local combineHubBtn = nil
local recipeLogFrame = nil
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

-- Mirrors PlayerDataManager.normalizeIngredientBank; also accepts array-shaped payloads from replication quirks.
local function normalizeIngredientBankClient(raw)
	local fixed = {}
	if type(raw) ~= "table" then
		return fixed
	end
	for k, v in pairs(raw) do
		if type(v) == "table" and v.id then
			local id = tostring(v.id)
			local n = math.floor(tonumber(v.qty or v.count or v.n) or 0)
			if id ~= "" and n > 0 then
				fixed[id] = (fixed[id] or 0) + n
			end
		else
			local id = tostring(k)
			local n = math.floor(tonumber(v) or 0)
			if id ~= "" and n > 0 then
				fixed[id] = n
			end
		end
	end
	if next(fixed) == nil then
		for _, e in ipairs(raw) do
			if type(e) == "table" and e.id then
				local id = tostring(e.id)
				local n = math.floor(tonumber(e.qty or e.count or e.n) or 0)
				if id ~= "" and n > 0 then
					fixed[id] = (fixed[id] or 0) + n
				end
			end
		end
	end
	return fixed
end

local function syncBank()
	local rf = getIngredientBank
	if not rf or not rf:IsA("RemoteFunction") then
		return
	end
	bankSyncGeneration += 1
	local myGen = bankSyncGeneration
	local ok, data = pcall(function()
		return rf:InvokeServer()
	end)
	if not ok then
		if GameConfig.DebugClientInvokeWarnings then
			warn("[IngredientsMenu] GetIngredientBank InvokeServer failed:", data)
		end
		return
	end
	-- Server returns nil until PlayerDataManager has loaded this player (same moment Bag would also fail).
	if data == nil then
		bank = {}
		task.spawn(function()
			for attempt = 1, 14 do
				task.wait(0.15 + attempt * 0.05)
				if myGen ~= bankSyncGeneration then
					return
				end
				if not rf.Parent then
					return
				end
				local ok2, data2 = pcall(function()
					return rf:InvokeServer()
				end)
				if ok2 and data2 ~= nil and type(data2) == "table" then
					bank = normalizeIngredientBankClient(data2)
					if gui and gui.Enabled and bankList then
						rebuildBankList()
					end
					return
				end
			end
		end)
		return
	end
	if type(data) ~= "table" then
		return
	end
	bank = normalizeIngredientBankClient(data)
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

local CHEF_SLOT_COUNT = 4

local function chefMaxSlots()
	return math.min(tonumber(cookCfg.MaxMixIngredients) or CHEF_SLOT_COUNT, CHEF_SLOT_COUNT)
end

local function ensureMixDense(maxMix)
	for i = 1, maxMix do
		if mix[i] == nil then
			mix[i] = { id = "", qty = 0 }
		end
	end
end

--- Snapshot for revert; same shape as GetCraftingMix / assignMixFromServer..
local function snapshotMixDense()
	local maxMix = chefMaxSlots()
	local out = {}
	for i = 1, maxMix do
		local e = mix[i]
		if mixSlotEntryValid(e) then
			out[i] = { id = tostring(e.id), qty = math.floor(tonumber(e.qty) or 0) }
		else
			out[i] = { id = "", qty = 0 }
		end
	end
	return out
end

local function applySnapshotMix(snap)
	if type(snap) == "table" then
		assignMixFromServer(snap)
	end
end

--- Sum of qty per ingredient id in current mix must not exceed bank (same rule as server).
local function mixWithinBankTotals()
	local maxMix = chefMaxSlots()
	local counts = {}
	for i = 1, maxMix do
		local e = mix[i]
		if mixSlotEntryValid(e) then
			local id = tostring(e.id)
			counts[id] = (counts[id] or 0) + math.floor(tonumber(e.qty) or 0)
		end
	end
	for id, n in pairs(counts) do
		local have = math.floor(tonumber(bank[id]) or 0)
		if n > have then
			return false
		end
	end
	return true
end

-- While InvokeServer yields, extra clicks used to queue more tryPlace calls and stack bad optimistic state.
local slotPlaceInFlight = false

--- Dense 1..N mix array (handles sparse / string-key payloads from remotes)
local function assignMixFromServer(data)
	if type(data) ~= "table" then return end
	local ok, err = pcall(function()
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
	end)
	if not ok then
		warn("[IngredientsMenu] assignMixFromServer:", err)
	end
end

local function mixTotal()
	local t = 0
	local maxS = chefMaxSlots()
	for i = 1, maxS do
		local e = mix[i]
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
	local maxS = chefMaxSlots()
	for i = 1, maxS do
		local e = mix[i]
		if mixSlotEntryValid(e) and e.id == ingredientId then
			t = t + (tonumber(e.qty) or 0)
		end
	end
	return t
end

--- Bank rows always show the raw bank total, matching the Bag tab in Inventory so both UIs agree on
--- "how many the player has". The qty currently placed in the mix is surfaced separately via the
--- inMixN label on each row. Previously, in cook mode the row subtracted qtyInMix from the shown
--- count — so ingredients already placed in the mix appeared to vanish from the cooking NPC UI
--- while still showing in the Bag (the reported mismatch).
local function bankCountShownForRow(id, rawBankN)
	return tonumber(rawBankN) or 0
end

local function rebuildBankList()
	if not bankList then return end
	clearChildren(bankList)
	local order = {}
	for id, n in pairs(bank) do
		local idStr = tostring(id)
		local qty = math.floor(tonumber(n) or 0)
		if idStr ~= "" and qty > 0 then
			table.insert(order, { id = idStr, n = qty })
		end
	end
	local sortOk, sortErr = pcall(function()
		table.sort(order, function(a, b)
			local da = IngredientData.GetById(a.id) or IngredientData.GetById(tostring(a.id))
			local db = IngredientData.GetById(b.id) or IngredientData.GetById(tostring(b.id))
			local ra = (da and da.region) or ""
			local rb = (db and db.region) or ""
			if ra ~= rb then
				return ra < rb
			end
			local oa = da and CreatureData.RarityOrder and CreatureData.RarityOrder[da.rarity] or 0
			local ob = db and CreatureData.RarityOrder and CreatureData.RarityOrder[db.rarity] or 0
			if oa ~= ob then
				return oa < ob
			end
			return tostring(a.id) < tostring(b.id)
		end)
	end)
	if not sortOk then
		warn("[IngredientsMenu] rebuildBankList sort failed (showing unsorted):", sortErr)
		table.sort(order, function(a, b)
			return tostring(a.id) < tostring(b.id)
		end)
	end
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = bankList

	if #order == 0 then
		local empty = Instance.new("TextLabel")
		empty.BackgroundTransparency = 1
		empty.Size = UDim2.new(1, -8, 0, 0)
		empty.AutomaticSize = Enum.AutomaticSize.Y
		empty.Font = Enum.Font.GothamMedium
		empty.TextSize = 12
		empty.TextColor3 = C.muted
		empty.TextWrapped = true
		empty.TextXAlignment = Enum.TextXAlignment.Left
		empty.Text =
			"No ingredients listed yet. If your Bag shows ingredients, close this and reopen, or wait a moment — your profile may still be loading."
		empty.Parent = bankList
		return
	end

	for idx, row in ipairs(order) do
		local def = IngredientData.GetById(row.id)
		local shownN = bankCountShownForRow(row.id, row.n)
		local inMixN = qtyInMixForIngredient(row.id)
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
			-- Total owned in bank (server); not "remaining" — x0 remaining looked like "you own 0".
			badge.Text = "x" .. tostring(row.n)
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
			tr.Position = UDim2.new(1, -120, 0, 8)
			tr.Size = UDim2.fromOffset(112, 36)
			tr.Font = Enum.Font.GothamBold
			tr.TextSize = 12
			tr.TextColor3 = C.accent
			tr.TextXAlignment = Enum.TextXAlignment.Right
			tr.TextYAlignment = Enum.TextYAlignment.Top
			tr.TextWrapped = true
			if shownN > 0 then
				tr.Text = "+" .. tostring(shownN) .. " free"
			elseif inMixN > 0 then
				tr.Text = "in mix ×" .. tostring(inMixN)
			else
				tr.Text = "—"
			end
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
	local maxS = chefMaxSlots()
	for i = 1, maxS do
		local e = mix[i]
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
	for i = 1, chefMaxSlots() do
		local e = mix[i]
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
	if slotPlaceInFlight then
		return
	end
	local id = selectedId
	if not id or id == "" then
		Notify.Toast("Select an ingredient, then tap a slot", Color3.fromRGB(255, 200, 100), 2.5)
		return
	end
	local maxMix = chefMaxSlots()
	ensureMixDense(maxMix)
	local prev = snapshotMixDense()
	local cur = mix[si]
	if mixSlotEntryValid(cur) and cur.id == id then
		mix[si] = { id = id, qty = math.floor(tonumber(cur.qty) or 0) + 1 }
	else
		mix[si] = { id = id, qty = 1 }
	end
	if not mixWithinBankTotals() then
		applySnapshotMix(prev)
		Notify.Toast("Not enough in bank for that mix", Color3.fromRGB(255, 140, 90), 2.5)
		return
	end
	rebuildMixList()
	rebuildBankList()

	slotPlaceInFlight = true
	local callOk, ok, payload = pcall(function()
		return craftingMixPlaceAt:InvokeServer(si, id, 1)
	end)
	slotPlaceInFlight = false

	if not callOk then
		Notify.Toast("Could not reach server", Color3.fromRGB(255, 100, 80), 2)
		applySnapshotMix(prev)
	elseif not ok then
		Notify.Toast(tostring(payload) or "Cannot add to slot", Color3.fromRGB(255, 100, 80), 2)
		applySnapshotMix(prev)
	elseif type(payload) == "table" then
		assignMixFromServer(payload)
	else
		syncMix()
	end
	rebuildMixList()
	rebuildBankList()
end

local function rebuildCraftingSlots()
	if not slotsHost then
		return
	end
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
			slot.Activated:Connect(function()
				if cookMode and selectedId and craftingMixPlaceAt then
					tryPlaceIngredientInSlot(si)
				elseif craftingMixRemoveSlot then
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
				else
					Notify.Toast("Cooking service unavailable", Color3.fromRGB(255, 100, 80), 2)
					syncMix()
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
			slot.Activated:Connect(function()
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

-- craftPad was UDim2 Y = scale 1 + offset -124. If rightChef height < ~124px (fullscreen/mobile),
-- the pad height becomes <= 0 and the slot ring / combine hub vanish.
local function applyChefMixingPanelLayout()
	if not cookMode or not rightChef or not craftPad then
		return
	end
	local h = rightChef.AbsoluteSize.Y
	if h < 2 then
		return
	end
	local gap = 6
	local logH = math.min(116, math.max(52, math.floor(h * 0.36)))
	local padH = math.max(56, h - logH - gap)
	if padH + logH + gap > h then
		logH = math.max(44, math.floor((h - gap) * 0.34))
		padH = math.max(48, h - logH - gap)
	end
	craftPad.Position = UDim2.new(0, 0, 0, 0)
	craftPad.Size = UDim2.new(1, -6, 0, padH)
	local log = recipeLogFrame
	if log and log.Parent == rightChef then
		log.AnchorPoint = Vector2.new(0, 1)
		log.Position = UDim2.new(0, 0, 1, -2)
		log.Size = UDim2.new(0.58, 0, 0, logH)
	end
end

-- Bottom-bar Cook must stay visible whenever the menu is open (chef or bank). Do not tie to canStartCampfireCook —
-- that hid Cook in chef mode when CraftAtCampfire remotes were still nil after WaitForChild.
local function refreshCookBarVisibility()
	if craftBtn and gui and gui.Enabled then
		craftBtn.Visible = true
	end
end

-- Two-column body: bankColumn | rightNormal (mix) or rightChef (craft). No overlapping full-bleed panels.
local function applyBodyLayout()
	if not bankColumn or not rightNormal or not rightChef or not bankScroll then
		return
	end
	bankScroll.AnchorPoint = Vector2.new(0, 0)
	bankScroll.Position = UDim2.new(0, 0, 0, 0)
	bankScroll.Size = UDim2.new(1, 0, 1, 0)
	bankScroll.Visible = true
	bankScroll.ScrollingDirection = Enum.ScrollingDirection.Y
	bankScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	if cookMode then
		bankColumn.Position = UDim2.new(0, 8, 0, 4)
		bankColumn.Size = UDim2.new(0.30, -8, 1, -8)
		rightNormal.Visible = false
		rightChef.Visible = true
		rightChef.Position = UDim2.new(0.30, 8, 0, 4)
		rightChef.Size = UDim2.new(0.70, -16, 1, -8)
		task.defer(function()
			applyChefMixingPanelLayout()
			task.defer(function()
				applyChefMixingPanelLayout()
				if cookMode then
					rebuildMixList()
				end
			end)
		end)
	else
		bankColumn.Position = UDim2.new(0, 8, 0, 4)
		bankColumn.Size = UDim2.new(0.48, -12, 1, -8)
		rightNormal.Visible = true
		rightChef.Visible = false
		rightNormal.Position = UDim2.new(0.52, 4, 0, 4)
		rightNormal.Size = UDim2.new(0.48, -14, 1, -8)
	end
	refreshCookBarVisibility()
end

local function applyIngredientsMenuLayout()
	if not mainFrame then return end
	if gui then
		if gui.Enabled then
			MobileWindowLayout.SyncNpcMenuScreenGui(gui, ING_DESIGN_W, ING_DESIGN_H)
		else
			gui.IgnoreGuiInset = false
		end
	end
	if MobileWindowLayout.NpcMenuUsesFullscreenBounds(ING_DESIGN_W, ING_DESIGN_H) then
		MobileWindowLayout.ApplyWindow(mainFrame, MobileWindowLayout.GetNpcFullscreenBoundsConfig(ING_DESIGN_W, ING_DESIGN_H))
	else
		if cookMode then
			mainFrame.Size = UDim2.fromOffset(720, 540)
		else
			mainFrame.Size = UDim2.fromOffset(520, 420)
		end
		mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
		mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		MobileWindowLayout.RestoreDesktopWindow(mainFrame, { draggable = true })
	end
	if bodyFrame and bankColumn then
		applyBodyLayout()
	end
	if applyIngredientsTitleLayout then
		applyIngredientsTitleLayout()
	end
end

local function setVisible(v)
	if gui then
		gui.Enabled = v
	end
	if not v then
		closeRecipeFrame()
		if gui then
			gui.IgnoreGuiInset = false
		end
		if craftBtn then
			craftBtn.Visible = false
		end
	end
	if v then
		if mainFrame then
			mainFrame.AnchorPoint = Vector2.new(0.5, 0.5)
			mainFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
		end
		if panelScale then
			panelScale.Scale = 1
		end
		applyBodyLayout()
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
		-- Bank list must not run after syncMix: assignMixFromServer can throw and would skip the list rebuild.
		rebuildBankList()
		syncMix()
		rebuildMixList()
		task.defer(function()
			if not gui or not gui.Enabled or not bankList then
				return
			end
			-- Refresh bank + layout after one frame (chef panel bounds). Do not syncMix here — it races with
			-- CraftingMixPlaceAt responses and can wipe the mix UI until the user clicks again.
			syncBank()
			rebuildBankList()
			applyChefMixingPanelLayout()
			rebuildMixList()
			refreshCookBarVisibility()
		end)
		if titleLbl then
			titleLbl.Text = cookMode and "MASTER CHEF CRAFTING" or "Ingredients"
		end
		refreshCookBarVisibility()
		if combineHubBtn then
			combineHubBtn.Visible = cookMode and canStartCampfireCook()
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
	if recipeSubmitInFlight then
		return
	end
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
	recipeSubmitInFlight = true
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
	recipeSubmitInFlight = false
	if not ok then
		Notify.Toast("Craft failed (network)", Color3.fromRGB(255, 80, 80), 2)
		return
	end
	if not crafted then
		Notify.Toast(tostring(errMsg) or "Cannot cook", Color3.fromRGB(255, 120, 100), 3)
		return
	end
	-- Close the minigame first so a sync/list rebuild error cannot leave the overlay up.
	closeRecipeFrame()
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
	pcall(function()
		syncBank()
		rebuildBankList()
		syncMix()
		rebuildMixList()
	end)
end

local function buildGui()
	if gui then return end
	gui = Instance.new("ScreenGui")
	gui.Name = "IngredientsMenu"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 50
	gui.Enabled = false
	gui.Parent = playerGui
	gui:SetAttribute("IngredientsBuild", ING_UI_BUILD)

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
	applyIngredientsTitleLayout = MobileWindowLayout.MenuHeaderTitleLayout(titleLbl, {
		Position = UDim2.new(0, 16, 0, 8),
		Size = UDim2.new(1, -80, 0, 36),
		TextXAlignment = Enum.TextXAlignment.Left,
	})

	local buildStamp = Instance.new("TextLabel")
	buildStamp.Name = "BuildStamp"
	buildStamp.BackgroundTransparency = 1
	buildStamp.Size = UDim2.new(0, 160, 0, 18)
	buildStamp.Position = UDim2.new(1, -172, 0, 10)
	buildStamp.Font = Enum.Font.Gotham
	buildStamp.TextSize = 10
	buildStamp.TextColor3 = C.muted
	buildStamp.TextXAlignment = Enum.TextXAlignment.Right
	buildStamp.Text = ING_UI_BUILD
	buildStamp.Parent = mainFrame

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

	bankColumn = Instance.new("Frame")
	bankColumn.Name = "BankColumn"
	bankColumn.BackgroundTransparency = 1
	bankColumn.Parent = bodyFrame

	bankScroll = Instance.new("ScrollingFrame")
	bankScroll.Name = "Bank"
	bankScroll.Position = UDim2.new(0, 0, 0, 0)
	bankScroll.Size = UDim2.new(1, 0, 1, 0)
	bankScroll.BackgroundColor3 = C.card
	bankScroll.BorderSizePixel = 0
	bankScroll.ScrollBarThickness = 6
	bankScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	bankScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	bankScroll.Parent = bankColumn
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
	rightNormal = Instance.new("Frame")
	rightNormal.Name = "IngredientsMix"
	rightNormal.BackgroundTransparency = 1
	rightNormal.Parent = bodyFrame
	mixScroll.Parent = rightNormal
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

	rightChef = Instance.new("Frame")
	rightChef.Name = "ChefPanel"
	rightChef.BackgroundTransparency = 1
	rightChef.Visible = false
	rightChef.Parent = bodyFrame

	craftPad = Instance.new("Frame")
	craftPad.Name = "CraftPad"
	craftPad.BackgroundColor3 = C.pad
	craftPad.BackgroundTransparency = 0.08
	craftPad.Position = UDim2.new(0, 0, 0, 0)
	craftPad.Size = UDim2.new(1, -6, 1, -124)
	craftPad.BorderSizePixel = 0
	craftPad.ClipsDescendants = true
	craftPad.Parent = rightChef
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

	recipeLogFrame = Instance.new("Frame")
	recipeLogFrame.Name = "RecipeLog"
	recipeLogFrame.AnchorPoint = Vector2.new(0, 1)
	recipeLogFrame.Position = UDim2.new(0, 0, 1, -2)
	recipeLogFrame.Size = UDim2.new(0.58, 0, 0, 116)
	recipeLogFrame.BackgroundColor3 = Color3.fromRGB(22, 28, 36)
	recipeLogFrame.BorderSizePixel = 0
	recipeLogFrame.ZIndex = 5
	recipeLogFrame.Parent = rightChef
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

	rightChef:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		if cookMode and rightChef.Visible then
			applyChefMixingPanelLayout()
			rebuildMixList()
		end
	end)

	local btnRow = Instance.new("Frame")
	btnRow.BackgroundTransparency = 1
	btnRow.ZIndex = 10
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

	local add4 = mkBtn("+4", 0.12, Color3.fromRGB(45, 90, 140))
	add4.Position = UDim2.new(0.18, 6, 0, 0)
	add4.Parent = btnRow
	add4.MouseButton1Click:Connect(function()
		if not selectedId then return end
		local maxMix = tonumber(cookCfg.MaxMixIngredients) or CHEF_SLOT_COUNT
		local room = maxMix - mixTotal()
		local q = math.min(4, math.max(0, room))
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

	craftBtn = mkBtn("Cook", 0.22, Color3.fromRGB(45, 130, 65))
	craftBtn.Name = "CookBar"
	craftBtn.ZIndex = 11
	craftBtn.AnchorPoint = Vector2.new(1, 0)
	craftBtn.Position = UDim2.new(1, -6, 0, 0)
	craftBtn.Size = UDim2.new(0, 120, 1, 0)
	craftBtn.Visible = false
	craftBtn.Parent = btnRow
	craftBtn.Activated:Connect(startCampfireCookFlow)
	combineHubBtn.Activated:Connect(startCampfireCookFlow)

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
				if #expectedSequence > 0 and #enteredSequence >= #expectedSequence then
					task.defer(submitRecipeMinigame)
				end
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

	applyBodyLayout()
end

local function openBank()
	cookMode = false
	buildGui()
	setVisible(true)
end

local function openCooking()
	-- Debounce: hookCookNPC + ProximityPromptService can both fire for the same prompt.
	local now = os.clock()
	if lastCookOpenClock >= 0 and (now - lastCookOpenClock) < 0.3 then
		return
	end
	lastCookOpenClock = now
	cookMode = true
	buildGui()
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
			bank = normalizeIngredientBankClient(newBank)
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

-- Client-only orb: bob outward, fly to player, +1 label (server confirms via IngredientPickupCollected).
local function playIngredientPickupFx(worldPos, ingredientId)
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	local def = IngredientData.GetById(ingredientId)
	local rarityCol = Color3.fromRGB(200, 205, 215)
	if def and CreatureData.Rarities and CreatureData.Rarities[def.rarity] then
		rarityCol = CreatureData.Rarities[def.rarity].color
	end

	local orb = Instance.new("Part")
	orb.Name = "IngredientPickupFx"
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.new(1.15, 1.15, 1.15)
	orb.Material = Enum.Material.Neon
	orb.Color = rarityCol
	orb.Transparency = 0.12
	orb.Anchored = true
	orb.CanCollide = false
	orb.CastShadow = false
	orb.Position = worldPos
	orb.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Name = "PlusOne"
	bb.AlwaysOnTop = true
	bb.Size = UDim2.new(0, 96, 0, 44)
	bb.StudsOffset = Vector3.new(0, 1.35, 0)
	bb.Parent = orb

	local plus = Instance.new("TextLabel")
	plus.BackgroundTransparency = 1
	plus.Size = UDim2.new(1, 0, 1, 0)
	plus.Text = "+1"
	plus.TextColor3 = Color3.fromRGB(110, 255, 150)
	plus.Font = Enum.Font.GothamBlack
	plus.TextSize = 26
	plus.TextStrokeColor3 = Color3.new(0, 0, 0)
	plus.TextStrokeTransparency = 0.35
	plus.Parent = bb

	local outward = Vector3.new(0, 0, -1)
	if hrp then
		local flat = Vector3.new(worldPos.X - hrp.Position.X, 0, worldPos.Z - hrp.Position.Z)
		if flat.Magnitude > 0.2 then
			outward = flat.Unit
		else
			local look = hrp.CFrame.LookVector * Vector3.new(1, 0, 1)
			if look.Magnitude > 0.08 then
				outward = look.Unit
			end
		end
	end
	local bobTarget = worldPos + outward * 2.8 + Vector3.new(0, 1.1, 0)
	local endPos = (hrp and (hrp.Position + Vector3.new(0, 1.15, 0))) or (worldPos + Vector3.new(0, 2, 0))

	local tiBob = TweenInfo.new(0.26, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	local tiFly = TweenInfo.new(0.48, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

	local twBob = TweenService:Create(orb, tiBob, {
		Position = bobTarget,
		Size = Vector3.new(1.65, 1.65, 1.65),
	})
	local twPlusBob = TweenService:Create(plus, tiBob, { TextSize = 34 })

	twBob:Play()
	twPlusBob:Play()

	task.delay(0.26, function()
		if not orb.Parent then
			return
		end
		TweenService:Create(orb, tiFly, {
			Position = endPos,
			Size = Vector3.new(0.35, 0.35, 0.35),
			Transparency = 1,
		}):Play()
		TweenService:Create(plus, tiFly, {
			TextTransparency = 1,
			TextStrokeTransparency = 1,
			TextSize = 14,
		}):Play()
		task.delay(0.52, function()
			if orb.Parent then
				orb:Destroy()
			end
		end)
	end)
end

if ingredientPickupCollected then
	ingredientPickupCollected.OnClientEvent:Connect(function(worldPos, ingredientId, displayName)
		if typeof(worldPos) ~= "Vector3" then
			return
		end
		if type(ingredientId) ~= "string" then
			return
		end
		local nameStr = (type(displayName) == "string" and displayName ~= "") and displayName or ingredientId
		local def = IngredientData.GetById(ingredientId)
		local toastCol = Color3.fromRGB(200, 205, 215)
		if def and CreatureData.Rarities and CreatureData.Rarities[def.rarity] then
			toastCol = CreatureData.Rarities[def.rarity].color
		end
		Notify.Toast("Collected " .. nameStr .. " (+1)", toastCol, 2.8, nil, nil)
		playIngredientPickupFx(worldPos, ingredientId)
	end)
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
			task.defer(function()
				task.wait(0.15)
				syncBank()
				if gui and gui.Enabled and bankList then
					rebuildBankList()
				end
			end)
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
	-- Prompt may live on any BasePart in the model, not the first part returned by FindFirstChildWhichIsA.
	local prompt = inst:FindFirstChildWhichIsA("ProximityPrompt", true)
	if not prompt then
		return
	end
	if prompt:GetAttribute("_IngMenuHooked") then
		return
	end
	prompt:SetAttribute("_IngMenuHooked", true)
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

print("[IngredientsMenu] Loaded " .. ING_UI_BUILD .. " — panel shows same id top-right; Explorer: ScreenGui attribute IngredientsBuild.")
