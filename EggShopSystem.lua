-- EggShopSystem.lua - ServerScriptService (ModuleScript)
-- Handles egg purchases (coins or Robux via Developer Products) and random creature hatching.
-- 5 tiers: Common, Rare, Mythic, Legendary, God. Pool percentages in GameConfig.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)

local EggShopSystem = {}

local PlayerDataManager

-- Lookup egg config by id
local function getEggConfig(eggId)
	for _, item in ipairs(GameConfig.EggShopItems) do
		if item.id == eggId then return item end
	end
	return nil
end

-- Lookup egg config by Developer Product ID (for ProcessReceipt)
local function getEggConfigByProductId(productId)
	if not productId or productId == 0 then return nil end
	for _, item in ipairs(GameConfig.EggShopItems) do
		if item.productId == productId then return item end
	end
	return nil
end

-- Build creature pools grouped by rarity (cached once). Mythic uses Epic creature list.
local creaturesByRarity = {}
local function buildRarityPools()
	if next(creaturesByRarity) then return end
	for _, c in ipairs(CreatureData.Creatures) do
		local r = c.rarity
		if not creaturesByRarity[r] then creaturesByRarity[r] = {} end
		table.insert(creaturesByRarity[r], c.id)
	end
	-- Egg shop "Mythic" = Epic creatures (display name stays "Mythic")
	if not creaturesByRarity["Mythic"] and creaturesByRarity["Epic"] then
		creaturesByRarity["Mythic"] = creaturesByRarity["Epic"]
	end
end

-- Roll a random creature from an egg's rarity pool. Pool rarities: Common, Uncommon, Rare, Mythic, Legendary.
local function rollCreature(eggConfig)
	buildRarityPools()

	local totalWeight = 0
	for _, entry in ipairs(eggConfig.pool) do
		totalWeight = totalWeight + entry.weight
	end
	if totalWeight <= 0 then return nil, nil end

	local roll = math.random() * totalWeight
	local cumulative = 0
	local chosenRarity = "Common"

	for _, entry in ipairs(eggConfig.pool) do
		cumulative = cumulative + entry.weight
		if roll <= cumulative then
			chosenRarity = entry.rarity
			break
		end
	end

	-- Mythic -> Epic for lookup if Mythic pool missing
	local lookupRarity = (chosenRarity == "Mythic" and not creaturesByRarity["Mythic"]) and "Epic" or chosenRarity
	local pool = creaturesByRarity[lookupRarity]
	if not pool or #pool == 0 then
		pool = creaturesByRarity["Common"] or {}
		chosenRarity = "Common"
	end
	if #pool == 0 then return nil, nil end

	return pool[math.random(#pool)], chosenRarity
end

-- Hatch egg (after payment)
local function hatchEgg(player, eggConfig)
	local data = PlayerDataManager.GetData(player)
	if not data then return false, "No data", nil end

	if #data.inventory >= GameConfig.MaxInventorySize then
		return false, "Inventory full!", nil
	end

	local creatureId, rarity = rollCreature(eggConfig)
	if not creatureId then return false, "No creatures available", nil end

	local uid = PlayerDataManager.AddCreature(player, creatureId, 1, 0)
	if not uid then return false, "Failed to add creature", nil end

	local info = CreatureData.GetById(creatureId)
	-- Mythic uses Epic color (CreatureData has Epic, not Mythic)
	local rarityForColor = (rarity == "Mythic") and "Epic" or rarity
	local rarityInfo = CreatureData.Rarities[rarityForColor]

	return true, "Hatched!", {
		creatureId = creatureId,
		uid = uid,
		rarity = rarity,
		displayName = info and info.displayName or creatureId,
		rarityColor = rarityInfo and {
			math.floor(rarityInfo.color.R * 255),
			math.floor(rarityInfo.color.G * 255),
			math.floor(rarityInfo.color.B * 255),
		} or {180, 180, 180},
	}
end

function EggShopSystem.Init(pdm)
	PlayerDataManager = pdm

	local events = ReplicatedStorage:WaitForChild("Events", 30)
	if not events then warn("[EggShopSystem] Events folder not found!"); return end

	local buyEgg = events:WaitForChild("BuyEgg", 15)
	local eggResult = events:FindFirstChild("EggResult")

	if buyEgg then
		buyEgg.OnServerInvoke = function(player, eggId, paymentType)
			paymentType = (paymentType == "robux" and "robux") or "coins"
			local config = getEggConfig(eggId)
			if not config then return false, "Invalid egg", nil end

			if paymentType == "coins" then
				if not config.coinCost or config.coinCost <= 0 then
					return false, "This egg cannot be bought with coins", nil
				end
				local data = PlayerDataManager.GetData(player)
				if not data or data.coins < config.coinCost then
					return false, "Not enough coins! Need " .. config.coinCost, nil
				end
				PlayerDataManager.SpendCoins(player, config.coinCost)
				local coinsEvt = events:FindFirstChild("CoinsUpdate")
				if coinsEvt then
					coinsEvt:FireClient(player, PlayerDataManager.GetCoins(player))
				end
			else
				return false, "Use the R$ button to purchase with Robux", nil
			end

			local ok, msg, result = hatchEgg(player, config)
			if ok then
				print("[EggShop] " .. player.Name .. " hatched " .. result.displayName .. " (" .. result.rarity .. ") from " .. eggId)
				if eggResult then
					eggResult:FireClient(player, result)
				end
			end
			return ok, msg, result
		end
	else
		warn("[EggShopSystem] BuyEgg event not found!")
	end

	-- Robux: Developer Product purchase completes via ProcessReceipt (callback receives receiptInfo only)
	local processedReceipts = {} -- [PurchaseId] = true to avoid double-grant on retries
	local function onProcessReceipt(receiptInfo)
		local purchaseId = receiptInfo.PurchaseId
		if processedReceipts[purchaseId] then
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		local productId = receiptInfo.ProductId
		local config = getEggConfigByProductId(productId)
		if not config then return Enum.ProductPurchaseDecision.NotProcessedYet end
		local playerObj = Players:GetPlayerByUserId(receiptInfo.PlayerId)
		if not playerObj then return Enum.ProductPurchaseDecision.NotProcessedYet end

		local ok, msg, result = hatchEgg(playerObj, config)
		if ok and eggResult then
			processedReceipts[purchaseId] = true
			eggResult:FireClient(playerObj, result)
			print("[EggShop] " .. playerObj.Name .. " hatched " .. result.displayName .. " (" .. result.rarity .. ") via Robux (" .. config.id .. ")")
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	pcall(function()
		MarketplaceService.ProcessReceipt = onProcessReceipt
	end)

	print("[EggShopSystem] Initialized - " .. #GameConfig.EggShopItems .. " egg types")
end

return EggShopSystem
