-- IngredientSpawnSystem.lua - ServerScriptService ModuleScript
-- World ingredient pickups, arena campfire, crafting validation.

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local BiomeZone = require(ReplicatedStorage.Modules.BiomeZone)
local IngredientData = require(ReplicatedStorage.Modules.IngredientData)

local IngredientSpawnSystem = {}

local TAG_PICKUP = "WorldIngredientPickup"
local TAG_CAMPFIRE = "ArenaCampfire"
local PICKUP_FOLDER_NAME = "IngredientPickupsLive"

local PlayerDataManager
local BuffShopSystem

local pickupsFolder
local activePickups = {}
local regionPickupCount = {}
local lastCraftTick = {}
local pendingRecipeByUserId = {}
local cookEnabled = true

local function getCook()
	return GameConfig.Cooking or {}
end

local function pushBankUpdate(player)
	local events = ReplicatedStorage:FindFirstChild("Events")
	local ev = events and events:FindFirstChild("IngredientBankChanged")
	if ev then
		ev:FireClient(player, PlayerDataManager.GetIngredientBankSnapshot(player))
	end
end

local function adjustRegionCount(region, delta)
	regionPickupCount[region] = math.max(0, (regionPickupCount[region] or 0) + delta)
end

local function removePickup(uid)
	local rec = activePickups[uid]
	if not rec then return end
	activePickups[uid] = nil
	adjustRegionCount(rec.region, -1)
	if rec.part and rec.part.Parent then
		rec.part:Destroy()
	end
end

local function colorPickupPart(part, ingredientId)
	local def = IngredientData.GetById(ingredientId)
	if not def then return end
	local r = CreatureData.Rarities and CreatureData.Rarities[def.rarity]
	if r and r.color then
		part.Color = r.color
	end
end

function IngredientSpawnSystem.TrySpawnOneInRegion(region)
	local cook = getCook()
	if cook.Enabled == false then return end
	local maxPer = tonumber(cook.MaxPickupsPerRegion) or 10
	if (regionPickupCount[region] or 0) >= maxPer then return end

	local pos = BiomeZone.GetRandomSurfacePositionForRegion(region)
	if not pos then return end

	local ingredientId = IngredientData.GetRandomIngredientIdForRegion(region)
	if not ingredientId then return end

	local p = Instance.new("Part")
	p.Name = "IngredientPickup"
	p.Anchored = true
	p.CanCollide = false
	p.Size = Vector3.new(1.2, 1.2, 1.2)
	p.Shape = Enum.PartType.Ball
	p.Material = Enum.Material.Neon
	p.Transparency = 0.15
	p.Position = pos
	colorPickupPart(p, ingredientId)

	local def = IngredientData.GetById(ingredientId)
	p:SetAttribute("IngredientId", ingredientId)
	p:SetAttribute("Region", region)
	local uid = HttpService:GenerateGUID(false)
	p:SetAttribute("PickupUid", uid)

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "CollectPrompt"
	prompt.ActionText = "Collect"
	prompt.ObjectText = def and def.displayName or "Ingredient"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = tonumber(cook.PickupCollectRange) or 18
	prompt.RequiresLineOfSight = false
	prompt.Parent = p

	CollectionService:AddTag(p, TAG_PICKUP)
	p.Parent = pickupsFolder

	local lifetime = tonumber(cook.PickupLifetimeSeconds) or 180
	activePickups[uid] = {
		part = p,
		region = region,
		ingredientId = ingredientId,
		spawnAt = os.clock(),
		lifetime = lifetime,
	}
	adjustRegionCount(region, 1)
end

function IngredientSpawnSystem.EnsureCampfire()
	local cook = getCook()
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then return nil end

	local name = cook.CampfirePartName or "Campfire"
	local existing = arena:FindFirstChild(name, true)
	if existing then
		local attachPart = existing:IsA("BasePart") and existing
			or existing:FindFirstChildWhichIsA("BasePart", true)
		if attachPart and not attachPart:FindFirstChildOfClass("ProximityPrompt") then
			local prompt = Instance.new("ProximityPrompt")
			prompt.ActionText = "Cook"
			prompt.ObjectText = "Campfire"
			prompt.MaxActivationDistance = tonumber(cook.CampfireProximity) or 22
			prompt.HoldDuration = 0
			prompt.RequiresLineOfSight = false
			prompt.Parent = attachPart
		end
		if existing:IsA("Model") then
			CollectionService:AddTag(existing, TAG_CAMPFIRE)
		elseif attachPart then
			CollectionService:AddTag(attachPart, TAG_CAMPFIRE)
		end
		return attachPart
	end

	local model = Instance.new("Model")
	model.Name = name
	local logs = Instance.new("Part")
	logs.Name = "Logs"
	logs.Anchored = true
	logs.Size = Vector3.new(4, 0.8, 2.5)
	logs.Material = Enum.Material.Wood
	logs.Color = Color3.fromRGB(90, 55, 35)
	logs.Parent = model
	local anchor = arena:FindFirstChild("ArenaCenter", true)
	if anchor and anchor:IsA("BasePart") then
		model:PivotTo(anchor.CFrame * CFrame.new(0, 1, 0))
	else
		model:PivotTo(CFrame.new(0, 8, 0))
	end
	model.PrimaryPart = logs
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Cook"
	prompt.ObjectText = "Campfire"
	prompt.MaxActivationDistance = tonumber(cook.CampfireProximity) or 22
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = logs
	model.Parent = arena
	CollectionService:AddTag(model, TAG_CAMPFIRE)
	return logs
end

local function isNearCampfire(player)
	local cook = getCook()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local maxDist = tonumber(cook.CampfireProximity) or 22
	for _, inst in ipairs(CollectionService:GetTagged(TAG_CAMPFIRE)) do
		local part = inst:IsA("BasePart") and inst or inst:FindFirstChildWhichIsA("BasePart", true)
		if part and (root.Position - part.Position).Magnitude <= maxDist then
			return true
		end
	end
	return false
end

local function getQualityPotencyMult(grade)
	local tbl = getCook().QualityPotencyMult or {}
	return tonumber(tbl[grade]) or 1
end

local function getQualityDurationMult(grade)
	local tbl = getCook().QualityDurationMult or {}
	return tonumber(tbl[grade]) or 1
end

local function gradeFromScore(score, mini)
	mini = mini or {}
	local t = mini.QualityThresholds or {}
	local perfect = tonumber(t.Perfect) or 0.90
	local great = tonumber(t.Great) or 0.75
	local good = tonumber(t.Good) or 0.55
	if score >= perfect then return "Perfect" end
	if score >= great then return "Great" end
	if score >= good then return "Good" end
	return "Poor"
end

function IngredientSpawnSystem.GetRecipePattern(player)
	if not isNearCampfire(player) then
		return false, "Stand by the campfire."
	end
	local cook = getCook()
	local mini = cook.Minigame or {}
	local mix = IngredientData.NormalizeMix(PlayerDataManager.GetCraftingMix(player))
	local craftResult, err = IngredientData.ComputeCraft(mix, cook)
	if not craftResult then
		return false, err or "Invalid mix"
	end
	local seed = tostring(player.UserId) .. ":" .. tostring(math.floor(os.clock() * 1000))
	local pattern = IngredientData.GetPatternForResult(craftResult, seed)
	if not pattern then
		return false, "No recipe pattern configured"
	end
	local token = HttpService:GenerateGUID(false)
	pendingRecipeByUserId[player.UserId] = {
		token = token,
		seed = seed,
		createdAt = os.clock(),
		craftPreview = craftResult,
		patternId = pattern.id,
		expectedSequence = pattern.seq,
	}
	return true, {
		token = token,
		patternId = pattern.id,
		sequence = pattern.seq,
		timeLimit = tonumber(mini.PatternTimeLimit) or 12,
	}
end

function IngredientSpawnSystem.ServerCollectPickup(player, pickupUid)
	if type(pickupUid) ~= "string" then return false, "Bad request" end
	local rec = activePickups[pickupUid]
	if not rec or not rec.part or not rec.part.Parent then
		activePickups[pickupUid] = nil
		return false, "Gone"
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false, "No character" end
	local cook = getCook()
	local maxDist = (tonumber(cook.PickupCollectRange) or 22) + 8
	if (root.Position - rec.part.Position).Magnitude > maxDist then
		return false, "Too far"
	end
	local ok, err = PlayerDataManager.AddIngredient(player, rec.ingredientId, 1)
	if not ok then return false, err or "Full" end
	removePickup(pickupUid)
	pushBankUpdate(player)
	return true
end

function IngredientSpawnSystem.ServerCraft(player)
	local cook = getCook()
	if not isNearCampfire(player) then
		return false, nil, nil, "Stand by the campfire."
	end
	local uid = player.UserId
	local now = os.clock()
	local cd = tonumber(cook.CraftCooldownSeconds) or 2
	if lastCraftTick[uid] and (now - lastCraftTick[uid]) < cd then
		return false, nil, nil, "Wait a moment."
	end
	local mix = IngredientData.NormalizeMix(PlayerDataManager.GetCraftingMix(player))
	local result, err = IngredientData.ComputeCraft(mix, cook)
	if not result then
		return false, nil, nil, err or "Invalid mix"
	end
	if not PlayerDataManager.TryConsumeIngredients(player, result.consume) then
		return false, nil, nil, "Missing ingredients"
	end
	local grade = "Good"
	local qualityScore = 0.6
	local potencyMult = getQualityPotencyMult(grade)
	local durationMult = getQualityDurationMult(grade)
	local baseDur = (cook.BuffDurationByRarity or {})[result.outputRarity] or 90
	local dur = math.max(1, math.floor(baseDur * durationMult))
	result.meta.qualityGrade = grade
	result.meta.qualityScore = qualityScore
	result.meta.qualityPotencyMult = potencyMult
	result.meta.qualityDurationMult = durationMult
	lastCraftTick[uid] = now
	PlayerDataManager.ActivateBuff(player, result.buffId, dur, result.meta)
	if BuffShopSystem and BuffShopSystem.ApplyBuffEffectForPlayer then
		BuffShopSystem.ApplyBuffEffectForPlayer(player, result.buffId, dur, result.meta)
	end
	pushBankUpdate(player)
	PlayerDataManager.CraftingMixClear(player)
	local ev = ReplicatedStorage:FindFirstChild("Events")
	local n = ev and ev:FindFirstChild("ShowNotification")
	if n then
		n:FireClient(player, "Cooked: " .. tostring(result.displayName), "info", "cooking")
	end
	return true, result.displayName, result.buffId, nil
end

function IngredientSpawnSystem.ServerCraftWithQuality(player, payload)
	payload = type(payload) == "table" and payload or {}
	local cook = getCook()
	local mini = cook.Minigame or {}
	if not isNearCampfire(player) then
		return false, nil, nil, "Stand by the campfire."
	end
	local uid = player.UserId
	local now = os.clock()
	local cd = tonumber(cook.CraftCooldownSeconds) or 2
	if lastCraftTick[uid] and (now - lastCraftTick[uid]) < cd then
		return false, nil, nil, "Wait a moment."
	end
	local pending = pendingRecipeByUserId[uid]
	if not pending or pending.token ~= tostring(payload.token or "") then
		return false, nil, nil, "No active recipe pattern. Start cooking again."
	end
	local timeoutSec = tonumber(mini.PatternSessionTimeout) or 30
	if (now - pending.createdAt) > timeoutSec then
		pendingRecipeByUserId[uid] = nil
		return false, nil, nil, "Recipe expired. Start again."
	end

	local mix = IngredientData.NormalizeMix(PlayerDataManager.GetCraftingMix(player))
	local result, err = IngredientData.ComputeCraft(mix, cook)
	if not result then
		return false, nil, nil, err or "Invalid mix"
	end
	local pattern = IngredientData.GetPatternForResult(result, pending.seed)
	if not pattern or pattern.id ~= pending.patternId then
		pendingRecipeByUserId[uid] = nil
		return false, nil, nil, "Mix changed. Start recipe again."
	end

	local entered = type(payload.enteredSequence) == "table" and payload.enteredSequence or {}
	if #entered > (#pattern.seq + 2) then
		return false, nil, nil, "Invalid pattern input."
	end
	local allowedTokens = { Up = true, Down = true, Left = true, Right = true }
	for _, token in ipairs(entered) do
		local s = tostring(token or "")
		if not allowedTokens[s] then
			return false, nil, nil, "Invalid pattern token."
		end
	end
	local elapsedMs = tonumber(payload.elapsedMs) or 0
	if elapsedMs < 0 then elapsedMs = 0 end
	local hardMaxMs = (tonumber(mini.PatternTimeLimit) or 12) * 1000 * 3
	elapsedMs = math.clamp(elapsedMs, 0, hardMaxMs)
	local _, qualityScore, accuracy = IngredientData.ComputePatternQuality(
		pattern.seq,
		entered,
		elapsedMs,
		tonumber(mini.PatternTimeLimit) or 12
	)
	local grade = gradeFromScore(qualityScore, mini)
	if mini.RequirePerfectMatch == true and accuracy < 1 then
		return false, nil, nil, "Recipe failed. Pattern mismatch."
	end

	if not PlayerDataManager.TryConsumeIngredients(player, result.consume) then
		return false, nil, nil, "Missing ingredients"
	end

	local potencyMult = getQualityPotencyMult(grade)
	local durationMult = getQualityDurationMult(grade)
	local baseDur = (cook.BuffDurationByRarity or {})[result.outputRarity] or 90
	local dur = math.max(1, math.floor(baseDur * durationMult))
	result.meta.qualityGrade = grade
	result.meta.qualityScore = qualityScore
	result.meta.qualityPotencyMult = potencyMult
	result.meta.qualityDurationMult = durationMult

	lastCraftTick[uid] = now
	PlayerDataManager.ActivateBuff(player, result.buffId, dur, result.meta)
	if BuffShopSystem and BuffShopSystem.ApplyBuffEffectForPlayer then
		BuffShopSystem.ApplyBuffEffectForPlayer(player, result.buffId, dur, result.meta)
	end

	pushBankUpdate(player)
	PlayerDataManager.CraftingMixClear(player)
	pendingRecipeByUserId[uid] = nil

	local ev = ReplicatedStorage:FindFirstChild("Events")
	local n = ev and ev:FindFirstChild("ShowNotification")
	if n then
		n:FireClient(player, ("Cooked: %s [%s]"):format(tostring(result.displayName), tostring(grade)), "info", "cooking")
	end
	return true, result.displayName, result.buffId, nil, {
		qualityGrade = grade,
		qualityScore = qualityScore,
		potencyMult = potencyMult,
		durationSeconds = dur,
	}
end

function IngredientSpawnSystem.Init(pdm, buffShop)
	PlayerDataManager = pdm
	BuffShopSystem = buffShop

	local cook = getCook()
	cookEnabled = cook.Enabled ~= false
	if not cookEnabled then
		return
	end

	pickupsFolder = Workspace:FindFirstChild(PICKUP_FOLDER_NAME)
	if not pickupsFolder then
		pickupsFolder = Instance.new("Folder")
		pickupsFolder.Name = PICKUP_FOLDER_NAME
		pickupsFolder.Parent = Workspace
	end

	task.defer(function()
		IngredientSpawnSystem.EnsureCampfire()
	end)

	local interval = math.max(2, tonumber(cook.SpawnIntervalSeconds) or 5)

	task.spawn(function()
		while true do
			task.wait(3)
			if not cookEnabled then continue end
			local now = os.clock()
			for pickupUid, rec in pairs(activePickups) do
				if not rec.part or not rec.part.Parent then
					activePickups[pickupUid] = nil
				elseif rec.lifetime and (now - rec.spawnAt) > rec.lifetime then
					removePickup(pickupUid)
				end
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(interval)
			if not cookEnabled then continue end
			for _, region in ipairs(IngredientData.GetAllRegions()) do
				IngredientSpawnSystem.TrySpawnOneInRegion(region)
			end
		end
	end)
end

return IngredientSpawnSystem
