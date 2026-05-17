-- ArenaTraderSystem.lua — ServerScriptService (ModuleScript)
-- Last updated: 2026-04-18 22:15
-- Arena Hub NPC: sells six rotating Siegelings (2 Common, 1 Uncommon, 1 Rare, 1 Epic, 1 Legendary).
-- Placement: CuratorSpawn resolved vs. HubArea.SpawnLocation when possible; else raw marker; else offset from Broker / SpawnLocation.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local NpcSpawnMarkers = require(ReplicatedStorage.Modules.NpcSpawnMarkers)

local ArenaTraderSystem = {}

local PlayerDataManager
local eventsFolder
local traderNPC

local stockState = {
	stockId = 0,
	rotationEndsAt = 0,
	slots = {},
}

local buyCooldown = {}

local function getTraderConfig()
	return GameConfig.ArenaTrader or {}
end

local function isEnabled()
	if GameConfig.ArenaTraderEnabled == false then
		return false
	end
	return true
end

local function pickCreatureForRarity(rarity)
	local list = CreatureData.GetCreaturesByRarity(rarity)
	if not list or #list == 0 then
		return nil
	end
	local pool = {}
	for _, c in ipairs(list) do
		if not string.find(c.id, "standin")
			and c.modelName
			and c.modelName ~= "Egg"
			and CreatureData.CreatureHasModel(c) then
			table.insert(pool, c)
		end
	end
	if #pool == 0 then
		for _, c in ipairs(list) do
			if not string.find(c.id, "standin") then
				table.insert(pool, c)
			end
		end
		pool = list
	end
	if #pool == 0 then
		return nil
	end
	return pool[math.random(#pool)].id
end

local function pickTwoDistinctCommons()
	local a = pickCreatureForRarity("Common")
	local b = pickCreatureForRarity("Common")
	local tries = 0
	while a and b and a == b and tries < 48 do
		b = pickCreatureForRarity("Common")
		tries = tries + 1
	end
	return a, b
end

local function priceForRarity(rarity)
	local cfg = getTraderConfig()
	local coinP = cfg.CoinPrice or {}
	local gemP = cfg.GemPrice or {}
	local c = coinP[rarity] or 50000
	local g = gemP[rarity] or 500
	return c, g
end

local function isTraderVariantAllowed(variant)
	return variant == "Silver" or variant == "Gold"
end

local function rollTraderVariant()
	local cfg = getTraderConfig()
	local weights = cfg.VariantWeights
	if type(weights) == "table" then
		local silverW = math.max(0, tonumber(weights.Silver) or 0)
		local goldW = math.max(0, tonumber(weights.Gold) or 0)
		local total = silverW + goldW
		if total > 0 then
			local r = math.random() * total
			return (r <= silverW) and "Silver" or "Gold"
		end
	end
	return (math.random() < 0.5) and "Silver" or "Gold"
end

local function rollStock()
	local cfg = getTraderConfig()
	local refresh = tonumber(cfg.StockRefreshSeconds) or (6 * 3600)
	local c1, c2 = pickTwoDistinctCommons()
	local u = pickCreatureForRarity("Uncommon")
	local r = pickCreatureForRarity("Rare")
	local e = pickCreatureForRarity("Epic")
	local l = pickCreatureForRarity("Legendary")

	local slots = {}
	local order = {
		{ rarity = "Common", id = c1 },
		{ rarity = "Common", id = c2 },
		{ rarity = "Uncommon", id = u },
		{ rarity = "Rare", id = r },
		{ rarity = "Epic", id = e },
		{ rarity = "Legendary", id = l },
	}
	for _, row in ipairs(order) do
		local coinCost, gemCost = priceForRarity(row.rarity)
		table.insert(slots, {
			rarity = row.rarity,
			creatureId = row.id,
			variant = rollTraderVariant(),
			coinCost = coinCost,
			gemCost = gemCost,
		})
	end

	stockState.stockId = stockState.stockId + 1
	stockState.rotationEndsAt = os.time() + refresh
	stockState.slots = slots
	-- Do not push UI to all players — only send stock when they use the ProximityPrompt.
end

-- Replace one slot after a purchase (same rarity / prices; new creature + variant). StockId unchanged.
local function refillPurchasedSlot(slotIndex)
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > #stockState.slots then
		return
	end
	local prev = stockState.slots[slotIndex]
	if not prev or not prev.rarity then
		return
	end
	local rarity = prev.rarity
	local newId

	if rarity == "Common" then
		local otherCommonId
		for i, s in ipairs(stockState.slots) do
			if i ~= slotIndex and s.rarity == "Common" then
				otherCommonId = s.creatureId
				break
			end
		end
		local tries = 0
		repeat
			newId = pickCreatureForRarity("Common")
			tries = tries + 1
		until not newId
				or (newId ~= otherCommonId and newId ~= prev.creatureId)
				or tries >= 64
	else
		local tries = 0
		repeat
			newId = pickCreatureForRarity(rarity)
			tries = tries + 1
		until not newId or newId ~= prev.creatureId or tries >= 48
	end

	if not newId then
		newId = prev.creatureId
	end

	local coinCost, gemCost = priceForRarity(rarity)
	stockState.slots[slotIndex] = {
		rarity = rarity,
		creatureId = newId,
		variant = rollTraderVariant(),
		coinCost = coinCost,
		gemCost = gemCost,
	}
end

local function findBrokerPositionAndCFrame()
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "BrokerNPC" and (desc:IsA("Model") or desc:IsA("BasePart")) then
			if desc:IsA("Model") then
				local pp = desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart", true)
				if pp then
					return pp.Position, pp.CFrame
				end
			else
				return desc.Position, desc.CFrame
			end
		end
	end
	return nil, nil
end

local function buildSpawnCFrame()
	local curatorPlacement = NpcSpawnMarkers.ResolvePlacementRelativeToHubSpawn("CuratorSpawn")
	if curatorPlacement then
		local cfg = getTraderConfig()
		local m = curatorPlacement.marker
		local markerTopY = m.Position.Y + m.Size.Y * 0.5
		local riseStuds = tonumber(cfg.CuratorSpawnRiseStuds) or 8
		local wxz = curatorPlacement.worldPosition
		local pos = Vector3.new(wxz.X, markerTopY + riseStuds, wxz.Z)
		local flat = curatorPlacement.flatLookWorld
		local baseCF = CFrame.lookAt(pos, pos + flat)
		local extraRot = cfg.ExtraRotationDegrees
		if type(extraRot) == "table" then
			local pitch = tonumber(extraRot.pitch) or 0
			local yaw = tonumber(extraRot.yaw) or 0
			local roll = tonumber(extraRot.roll) or 0
			if pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
				baseCF = baseCF * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
			end
		end
		return baseCF
	end

	local curatorMarker = NpcSpawnMarkers.FindNamedPart("CuratorSpawn")
	if curatorMarker then
		local cfg = getTraderConfig()
		local markerTopY = curatorMarker.Position.Y + curatorMarker.Size.Y * 0.5
		local riseStuds = tonumber(cfg.CuratorSpawnRiseStuds) or 8
		local pos = Vector3.new(curatorMarker.Position.X, markerTopY + riseStuds, curatorMarker.Position.Z)
		local lv = curatorMarker.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
		local baseCF = (flat.Magnitude > 1e-3) and CFrame.lookAt(pos, pos + flat.Unit) or CFrame.new(pos)
		local extraRot = cfg.ExtraRotationDegrees
		if type(extraRot) == "table" then
			local pitch = tonumber(extraRot.pitch) or 0
			local yaw = tonumber(extraRot.yaw) or 0
			local roll = tonumber(extraRot.roll) or 0
			if pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
				baseCF = baseCF * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
			end
		end
		return baseCF
	end

	local cfg = getTraderConfig()
	local offset = cfg.OffsetFromBrokerStuds or Vector3.new(-26, 0, 16)
	local fallbackOfs = cfg.FallbackOffsetFromSpawnStuds or offset
	local extraRot = cfg.ExtraRotationDegrees

	local hub = Workspace:FindFirstChild("HubArea")
	local spawnRef = hub and hub:FindFirstChild("SpawnLocation")
	local brokerPos, brokerCF = findBrokerPositionAndCFrame()

	local baseXZ

	if brokerPos then
		baseXZ = brokerPos + Vector3.new(offset.X, 0, offset.Z)
	elseif spawnRef and spawnRef:IsA("BasePart") then
		baseXZ = spawnRef.Position + Vector3.new(fallbackOfs.X, 0, fallbackOfs.Z)
	else
		return nil
	end

	local rayOrigin = Vector3.new(baseXZ.X, (spawnRef and spawnRef:IsA("BasePart") and spawnRef.Position.Y or baseXZ.Y) + 60, baseXZ.Z)
	local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -220, 0))
	local groundY = rayResult and rayResult.Position.Y or baseXZ.Y
	local groundOfs = tonumber(cfg.GroundOffsetStuds) or 2.5
	local pos = Vector3.new(baseXZ.X, groundY + groundOfs, baseXZ.Z)

	local baseCF = CFrame.new(pos)
	-- Match Broker rotation exactly when Broker exists (no custom trader look-at rotation).
	if brokerCF then
		baseCF = CFrame.new(pos) * (brokerCF - brokerCF.Position)
	end
	if type(extraRot) == "table" then
		local pitch = tonumber(extraRot.pitch) or 0
		local yaw = tonumber(extraRot.yaw) or 0
		local roll = tonumber(extraRot.roll) or 0
		if pitch ~= 0 or yaw ~= 0 or roll ~= 0 then
			baseCF = baseCF * CFrame.Angles(math.rad(pitch), math.rad(yaw), math.rad(roll))
		end
	end
	return baseCF
end

local function createTraderNPC()
	if traderNPC and traderNPC.Parent then
		return traderNPC
	end

	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == "TraderNPC" and (desc:IsA("Model") or desc:IsA("BasePart")) then
			traderNPC = desc
			break
		end
	end

	local hub = Workspace:FindFirstChild("HubArea")
	local parentFolder = hub or Workspace

	if not traderNPC then
		local spawnCF = buildSpawnCFrame()
		if not spawnCF then
			warn("[ArenaTrader] Could not resolve hub spawn — Trader NPC not placed")
			return nil
		end

		-- Prefer a prebuilt TraderNPC model in ReplicatedStorage.
		local template = ReplicatedStorage:FindFirstChild("TraderNPC")
		if template and (template:IsA("Model") or template:IsA("BasePart")) then
			local npc = template:Clone()
			npc.Name = "TraderNPC"
			npc.Parent = parentFolder
			if npc:IsA("Model") then
				if not npc.PrimaryPart then
					local pp = npc:FindFirstChildWhichIsA("BasePart", true)
					if pp then
						npc.PrimaryPart = pp
					end
				end
				if npc.PrimaryPart then
					npc:PivotTo(spawnCF)
				else
					warn("[ArenaTrader] TraderNPC model has no BasePart — cannot PivotTo")
				end
			else
				npc.CFrame = spawnCF * CFrame.new(0, npc.Size.Y / 2, 0)
			end
			traderNPC = npc
		else
			local part = Instance.new("Part")
			part.Name = "TraderNPC"
			part.Size = Vector3.new(3, 5, 3)
			part.Anchored = true
			part.CanCollide = true
			part.Color = Color3.fromRGB(35, 42, 58)
			part.Material = Enum.Material.Slate
			part.CFrame = spawnCF * CFrame.new(0, part.Size.Y / 2, 0)
			part.Parent = parentFolder
			traderNPC = part
		end
	end

	if traderNPC:IsA("Model") then
		local pp = traderNPC.PrimaryPart or traderNPC:FindFirstChildWhichIsA("BasePart", true)
		if not pp then
			warn("[ArenaTrader] Trader model has no BasePart")
			return traderNPC
		end
		if not traderNPC.PrimaryPart then
			traderNPC.PrimaryPart = pp
		end
		for _, p in ipairs(traderNPC:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
			end
		end
	else
		traderNPC.Anchored = true
	end

	local adornee = (traderNPC:IsA("Model") and traderNPC.PrimaryPart) or traderNPC
	if adornee and not traderNPC:FindFirstChild("TraderTag", true) then
		local bb = Instance.new("BillboardGui")
		bb.Name = "TraderTag"
		bb.Adornee = adornee
		bb.Size = UDim2.new(0, 260, 0, 64)
		bb.StudsOffset = Vector3.new(0, 4.2, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 70
		bb.Parent = traderNPC

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, 0, 0.48, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = "The Curator"
		titleLabel.TextColor3 = Color3.fromRGB(220, 200, 120)
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.TextScaled = true
		titleLabel.Parent = bb

		local sub = Instance.new("TextLabel")
		sub.Name = "Subtitle"
		sub.Size = UDim2.new(1, 0, 0.42, 0)
		sub.Position = UDim2.new(0, 0, 0.52, 0)
		sub.BackgroundTransparency = 1
		sub.Text = "Codex Exchange"
		sub.TextColor3 = Color3.fromRGB(140, 150, 170)
		sub.Font = Enum.Font.GothamMedium
		sub.TextScaled = true
		sub.Parent = bb
	end

	local promptParent = (traderNPC:IsA("Model") and traderNPC.PrimaryPart) or traderNPC
	if promptParent and not traderNPC:FindFirstChild("TraderPrompt", true) then
		local prompt = Instance.new("ProximityPrompt")
		prompt.Name = "TraderPrompt"
		prompt.ObjectText = "The Curator"
		prompt.ActionText = "Browse"
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = 12
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = promptParent
	end

	if not traderNPC:FindFirstChild("TraderAura", true) and adornee then
		local glow = Instance.new("PointLight")
		glow.Name = "TraderAura"
		glow.Color = Color3.fromRGB(255, 210, 120)
		glow.Brightness = 1.6
		glow.Range = 14
		glow.Parent = adornee
	end

	-- Bronze outline (matches Broker having a distinct purple outline).
	if not traderNPC:FindFirstChild("Highlight") and not traderNPC:FindFirstChildWhichIsA("Highlight") then
		local highlight = Instance.new("Highlight")
		highlight.FillColor = Color3.fromRGB(120, 78, 36)
		highlight.FillTransparency = 0.62
		highlight.OutlineColor = Color3.fromRGB(205, 140, 70)
		highlight.OutlineTransparency = 0.15
		highlight.Parent = traderNPC
	end

	return traderNPC
end

local function wirePrompt()
	local npc = traderNPC
	if not npc then
		return
	end
	local prompt = npc:FindFirstChild("TraderPrompt", true)
	local stockEvt = eventsFolder and eventsFolder:FindFirstChild("ArenaTraderStock")
	if not prompt or not stockEvt then
		return
	end
	prompt.Triggered:Connect(function(player)
		stockEvt:FireClient(player, ArenaTraderSystem.GetStockPayload())
	end)
end

local function tryPurchase(player, slotIndex, paymentType, creatureId, stockId)
	if not PlayerDataManager then
		return false, "Server not ready"
	end
	paymentType = (paymentType == "gems" and "gems") or "coins"

	local now = os.clock()
	if (buyCooldown[player.UserId] or 0) > now then
		return false, "Please wait"
	end
	buyCooldown[player.UserId] = now + 0.4

	if stockId ~= stockState.stockId then
		return false, "This rotation has ended — open again for new stock."
	end
	if type(slotIndex) ~= "number" or slotIndex < 1 or slotIndex > #stockState.slots then
		return false, "Invalid offer"
	end
	local slot = stockState.slots[slotIndex]
	if not slot or not slot.creatureId then
		return false, "Offer unavailable"
	end
	if creatureId and creatureId ~= slot.creatureId then
		return false, "That creature is no longer in this slot."
	end

	local cost = (paymentType == "gems") and slot.gemCost or slot.coinCost
	if cost <= 0 then
		return false, "Invalid price"
	end

	if paymentType == "gems" then
		if not PlayerDataManager.SpendGems(player, cost) then
			return false, "Not enough diamonds (need " .. tostring(cost) .. ")"
		end
		local gemsEvt = eventsFolder and eventsFolder:FindFirstChild("GemsUpdate")
		if gemsEvt then
			gemsEvt:FireClient(player, PlayerDataManager.GetGems(player))
		end
	else
		if not PlayerDataManager.SpendCoins(player, cost) then
			return false, "Not enough coins (need " .. tostring(cost) .. ")"
		end
		local coinsEvt = eventsFolder and eventsFolder:FindFirstChild("CoinsUpdate")
		if coinsEvt then
			coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player))
		end
	end

	local variant = isTraderVariantAllowed(slot.variant) and slot.variant or rollTraderVariant()
	local uid = PlayerDataManager.AddCreature(player, slot.creatureId, 1, 0, variant, nil, { source = "arena_trader" })
	if not uid then
		-- Refund
		if paymentType == "gems" then
			PlayerDataManager.AddGems(player, cost)
			local gemsEvt = eventsFolder and eventsFolder:FindFirstChild("GemsUpdate")
			if gemsEvt then
				gemsEvt:FireClient(player, PlayerDataManager.GetGems(player))
			end
		else
			PlayerDataManager.AddCoins(player, cost)
			local coinsEvt = eventsFolder and eventsFolder:FindFirstChild("CoinsUpdate")
			if coinsEvt then
				coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player))
			end
		end
		return false, "Inventory full — purchase refunded."
	end

	local notif = eventsFolder and eventsFolder:FindFirstChild("ShowNotification")
	if notif then
		local info = CreatureData.GetById(slot.creatureId)
		local nm = (info and info.displayName) or slot.creatureId
		notif:FireClient(player, "Acquired " .. nm .. "!", "info")
	end

	refillPurchasedSlot(slotIndex)

	return true, "Purchased", ArenaTraderSystem.GetStockPayload()
end

function ArenaTraderSystem.GetStockPayload()
	local slotsOut = {}
	for i, s in ipairs(stockState.slots) do
		local info = s.creatureId and CreatureData.GetById(s.creatureId)
		table.insert(slotsOut, {
			slotIndex = i,
			rarity = s.rarity,
			creatureId = s.creatureId,
			variant = isTraderVariantAllowed(s.variant) and s.variant or "Silver",
			displayName = info and info.displayName or (s.creatureId or "?"),
			element = info and info.element or "",
			coinCost = s.coinCost,
			gemCost = s.gemCost,
		})
	end
	return {
		stockId = stockState.stockId,
		rotationEndsAt = stockState.rotationEndsAt,
		slots = slotsOut,
	}
end

function ArenaTraderSystem.Init(pdm)
	PlayerDataManager = pdm
	eventsFolder = ReplicatedStorage:FindFirstChild("Events")

	if not isEnabled() then
		print("[ArenaTrader] Disabled via GameConfig.ArenaTraderEnabled")
		return
	end

	rollStock()

	task.spawn(function()
		local cfg = getTraderConfig()
		local refresh = tonumber(cfg.StockRefreshSeconds) or (6 * 3600)
		while true do
			task.wait(1)
			if os.time() >= stockState.rotationEndsAt then
				rollStock()
			end
		end
	end)

	local npc = createTraderNPC()
	wirePrompt()

	local buyFn = eventsFolder and eventsFolder:FindFirstChild("BuyArenaTraderCreature")
	if buyFn and buyFn:IsA("RemoteFunction") then
		buyFn.OnServerInvoke = function(player, slotIndex, paymentType, creatureId, stockId)
			-- FIX: Must return the fresh stock payload (3rd return from tryPurchase). Dropping it
			-- caused the client to close the UI instead of re-rendering with the refilled slot,
			-- so the Curator appeared to "forget" about restocking after a purchase.
			local ok, msg, newStock = tryPurchase(player, slotIndex, paymentType, creatureId, stockId)
			return ok, msg, newStock
		end
	end

	local sec = tonumber(getTraderConfig().StockRefreshSeconds) or (6 * 3600)
	print("[ArenaTrader] Initialized — stock rotates every " .. tostring(sec) .. "s")
end

return ArenaTraderSystem
