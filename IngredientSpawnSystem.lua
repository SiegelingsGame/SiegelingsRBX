-- IngredientSpawnSystem.lua - ServerScriptService ModuleScript
-- World ingredient pickups, CookNPC hub chef (crafting), crafting validation.
-- Last updated: 2026-04-18 22:15

local HttpService = game:GetService("HttpService")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local NpcSpawnMarkers = require(ReplicatedStorage.Modules.NpcSpawnMarkers)
local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local BiomeZone = require(ReplicatedStorage.Modules.BiomeZone)
local IngredientData = require(ReplicatedStorage.Modules.IngredientData)

local IngredientSpawnSystem = {}

local TAG_PICKUP = "WorldIngredientPickup"
local TAG_COOK_NPC = "CookNPC"
-- Legacy tag still applied alongside CookNPC so older tooling keeps working.
local TAG_CAMPFIRE_LEGACY = "ArenaCampfire"
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

local function parsePlayerCraftingMix(player)
	local cook = getCook()
	local maxMix = tonumber(cook.MaxMixIngredients) or 4
	local raw = PlayerDataManager.GetCraftingMix(player)
	return IngredientData.ParseCraftingMixRaw(raw, maxMix)
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

local function getCookNpcConfig()
	local cook = getCook()
	return cook.CookNPC or {}
end

local function resolveArenaAnchor()
	local arena = Workspace:FindFirstChild("Arena")
	if not arena then
		return nil
	end
	local center = arena:FindFirstChild("ArenaCenter", true)
	if center and center:IsA("BasePart") then
		return center.Position
	end
	local blueTeam = arena:FindFirstChild("BlueTeam", true)
	if blueTeam then
		local bp = blueTeam:FindFirstChild("BattlePoint1", true)
		if bp and bp:IsA("BasePart") then
			return bp.Position
		end
	end
	return nil
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

local function buildCookNPCSpawnCFrame()
	local placement = NpcSpawnMarkers.ResolvePlacementRelativeToHubSpawn("CookSpawn")
	if placement then
		local cfg = getCookNpcConfig()
		local wxz = placement.worldPosition
		local rayOrigin = Vector3.new(wxz.X, wxz.Y + 70, wxz.Z)
		local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -260, 0))
		local groundY = rayResult and rayResult.Position.Y or wxz.Y
		local groundOfs = tonumber(cfg.GroundOffsetStuds) or 2.5
		local pos = Vector3.new(wxz.X, groundY + groundOfs, wxz.Z)
		local flat = placement.flatLookWorld
		local baseCF = CFrame.lookAt(pos, pos + flat)
		local extraRot = cfg.ExtraRotationDegrees or { pitch = 90, yaw = 0, roll = 0 }
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

	local cookMarker = NpcSpawnMarkers.FindNamedPart("CookSpawn")
	if cookMarker then
		local cfg = getCookNpcConfig()
		local rayOrigin = Vector3.new(cookMarker.Position.X, cookMarker.Position.Y + 70, cookMarker.Position.Z)
		local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -260, 0))
		local groundY = rayResult and rayResult.Position.Y or cookMarker.Position.Y
		local groundOfs = tonumber(cfg.GroundOffsetStuds) or 2.5
		local pos = Vector3.new(cookMarker.Position.X, groundY + groundOfs, cookMarker.Position.Z)
		local lv = cookMarker.CFrame.LookVector
		local flat = Vector3.new(lv.X, 0, lv.Z)
		local baseCF
		if flat.Magnitude > 1e-3 then
			baseCF = CFrame.lookAt(pos, pos + flat.Unit)
		else
			baseCF = CFrame.new(pos)
		end
		local extraRot = cfg.ExtraRotationDegrees or { pitch = 90, yaw = 0, roll = 0 }
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

	local cookRoot = getCook()
	local cfg = getCookNpcConfig()
	local offsetFromBroker = cfg.OffsetFromBrokerStuds or Vector3.new(0, 0, 22)
	local fallbackSpawn = cfg.FallbackOffsetFromSpawnStuds or Vector3.new(0, 0, 22)
	local arenaFallback = cfg.OffsetFromArenaCenterStuds or Vector3.new(0, 0, 8)

	local hub = Workspace:FindFirstChild("HubArea")
	local spawnRef = hub and hub:FindFirstChild("SpawnLocation")
	local brokerPos, brokerCF = findBrokerPositionAndCFrame()

	local baseXZ
	if brokerPos then
		baseXZ = brokerPos + Vector3.new(offsetFromBroker.X, 0, offsetFromBroker.Z)
	elseif spawnRef and spawnRef:IsA("BasePart") then
		baseXZ = spawnRef.Position + Vector3.new(fallbackSpawn.X, 0, fallbackSpawn.Z)
	else
		local arenaPos = resolveArenaAnchor()
		if arenaPos then
			baseXZ = arenaPos + Vector3.new(arenaFallback.X, 0, arenaFallback.Z)
		else
			return nil
		end
	end

	local rayY = (spawnRef and spawnRef:IsA("BasePart") and spawnRef.Position.Y) or baseXZ.Y
	local rayOrigin = Vector3.new(baseXZ.X, rayY + 70, baseXZ.Z)
	local rayResult = Workspace:Raycast(rayOrigin, Vector3.new(0, -260, 0))
	local groundY = rayResult and rayResult.Position.Y or baseXZ.Y
	local groundOfs = tonumber(cfg.GroundOffsetStuds) or 2.5
	local pos = Vector3.new(baseXZ.X, groundY + groundOfs, baseXZ.Z)

	local baseCF = CFrame.new(pos)
	if brokerCF then
		baseCF = CFrame.new(pos) * (brokerCF - brokerCF.Position)
	end
	local extraRot = cfg.ExtraRotationDegrees or { pitch = 90, yaw = 0, roll = 0 }
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

local function ensureCookNPCPromptAndTags(npc, cookRoot, cfg)
	local attach = npc:IsA("BasePart") and npc or npc:FindFirstChildWhichIsA("BasePart", true)
	if not attach then
		return
	end
	local prompt = attach:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		prompt = Instance.new("ProximityPrompt")
		prompt.Name = "CookNPCPrompt"
		prompt.Parent = attach
	end
	prompt.ActionText = "Cook"
	prompt.ObjectText = cfg.PromptObjectText or "Campfire Chef"
	prompt.MaxActivationDistance = tonumber(cookRoot.CampfireProximity) or 22
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E

	local adorneeForTag = attach
	if npc:IsA("Model") and npc.PrimaryPart then
		adorneeForTag = npc.PrimaryPart
	end
	if not npc:FindFirstChild("CookNPCNameTag", true) then
		local bb = Instance.new("BillboardGui")
		bb.Name = "CookNPCNameTag"
		bb.Adornee = adorneeForTag
		bb.Size = UDim2.new(0, 240, 0, 56)
		bb.StudsOffset = Vector3.new(0, 4.4, 0)
		bb.AlwaysOnTop = false
		bb.MaxDistance = 60
		bb.LightInfluence = 1
		bb.Parent = npc

		local titleLabel = Instance.new("TextLabel")
		titleLabel.Name = "Title"
		titleLabel.Size = UDim2.new(1, 0, 0.52, 0)
		titleLabel.Position = UDim2.new(0, 0, 0, 0)
		titleLabel.BackgroundTransparency = 1
		titleLabel.Text = cfg.PromptObjectText or "Campfire Chef"
		titleLabel.TextColor3 = Color3.fromRGB(100, 220, 210)
		titleLabel.Font = Enum.Font.GothamBlack
		titleLabel.TextScaled = true
		titleLabel.Parent = bb

		local subLabel = Instance.new("TextLabel")
		subLabel.Name = "Subtitle"
		subLabel.Size = UDim2.new(1, 0, 0.42, 0)
		subLabel.Position = UDim2.new(0, 0, 0.56, 0)
		subLabel.BackgroundTransparency = 1
		subLabel.Text = (type(cfg.OverheadSubtitle) == "string" and cfg.OverheadSubtitle) or "Cooking & recipes"
		subLabel.TextColor3 = Color3.fromRGB(150, 165, 180)
		subLabel.Font = Enum.Font.GothamMedium
		subLabel.TextScaled = true
		subLabel.Parent = bb
	end

	if npc:IsA("Model") then
		CollectionService:AddTag(npc, TAG_COOK_NPC)
		CollectionService:AddTag(npc, TAG_CAMPFIRE_LEGACY)
	else
		CollectionService:AddTag(npc, TAG_COOK_NPC)
		CollectionService:AddTag(npc, TAG_CAMPFIRE_LEGACY)
	end

	if not npc:FindFirstChild("CookNPCHighlight", true) then
		local highlight = Instance.new("Highlight")
		highlight.Name = "CookNPCHighlight"
		highlight.FillColor = Color3.fromRGB(40, 210, 95)
		highlight.FillTransparency = 0.55
		highlight.OutlineColor = Color3.fromRGB(120, 255, 160)
		highlight.OutlineTransparency = 0.12
		highlight.Parent = npc
	end
end

function IngredientSpawnSystem.EnsureCookNPC()
	local cookRoot = getCook()
	if cookRoot.Enabled == false then
		return true
	end
	local cfg = getCookNpcConfig()
	local templateName = cfg.TemplateName or "CookNPC"
	local instanceName = cfg.InstanceName or "CookNPC"

	local npc = nil
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc.Name == instanceName and (desc:IsA("Model") or desc:IsA("BasePart")) then
			npc = desc
			break
		end
	end

	local spawnCF = buildCookNPCSpawnCFrame()
	if not spawnCF then
		return false
	end

	if not npc then
		local template = ReplicatedStorage:FindFirstChild(templateName)
		if not template or not (template:IsA("Model") or template:IsA("BasePart")) then
			warn(("[IngredientSpawn] CookNPC template '%s' not found in ReplicatedStorage (Model or BasePart)"):format(templateName))
			return true
		end
		npc = template:Clone()
		npc.Name = instanceName
		npc.Parent = Workspace
	end

	if npc:IsA("Model") then
		local pp = npc.PrimaryPart or npc:FindFirstChildWhichIsA("BasePart", true)
		if pp then
			if not npc.PrimaryPart then
				npc.PrimaryPart = pp
			end
			npc:PivotTo(spawnCF)
		end
		for _, d in ipairs(npc:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	elseif npc:IsA("BasePart") then
		npc.Anchored = true
		npc.CFrame = spawnCF * CFrame.new(0, npc.Size.Y * 0.5, 0)
	end

	ensureCookNPCPromptAndTags(npc, cookRoot, cfg)
	return true
end

-- Back-compat name (same as EnsureCookNPC).
IngredientSpawnSystem.EnsureCampfire = IngredientSpawnSystem.EnsureCookNPC

local function isNearCampfire(player)
	local cook = getCook()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	local maxDist = tonumber(cook.CampfireProximity) or 22
	for _, inst in ipairs(CollectionService:GetTagged(TAG_COOK_NPC)) do
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
		return false, "Stand near the cook."
	end
	local cook = getCook()
	local mini = cook.Minigame or {}
	local flat, slots = parsePlayerCraftingMix(player)
	local craftResult, err = IngredientData.ComputeCraft(flat, cook, slots)
	if not craftResult then
		return false, err or "Invalid mix"
	end
	local maxMix = tonumber(cook.MaxMixIngredients) or 4
	local slotMask = IngredientData.SlotOccupancyMask(slots, maxMix)
	local seed = tostring(player.UserId)
		.. ":"
		.. tostring(math.floor(os.clock() * 1000))
		.. ":m"
		.. tostring(slotMask)
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
	local worldPos = rec.part.Position
	local ingId = rec.ingredientId
	local ingDef = IngredientData.GetById(ingId)
	local displayName = ingDef and ingDef.displayName or ingId
	removePickup(pickupUid)
	pushBankUpdate(player)
	local ev = ReplicatedStorage:FindFirstChild("Events")
	local pickupFx = ev and ev:FindFirstChild("IngredientPickupCollected")
	if pickupFx then
		pickupFx:FireClient(player, worldPos, ingId, displayName)
	end
	return true
end

function IngredientSpawnSystem.ServerCraft(player)
	local cook = getCook()
	if not isNearCampfire(player) then
		return false, nil, nil, "Stand near the cook."
	end
	local uid = player.UserId
	local now = os.clock()
	local cd = tonumber(cook.CraftCooldownSeconds) or 2
	if lastCraftTick[uid] and (now - lastCraftTick[uid]) < cd then
		return false, nil, nil, "Wait a moment."
	end
	local flat, slots = parsePlayerCraftingMix(player)
	local result, err = IngredientData.ComputeCraft(flat, cook, slots)
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
		local msg = IngredientData.FormatCookingNotification(result, nil)
		n:FireClient(player, msg, "info", "cooking")
	end
	return true, result.displayName, result.buffId, nil
end

function IngredientSpawnSystem.ServerCraftWithQuality(player, payload)
	payload = type(payload) == "table" and payload or {}
	local cook = getCook()
	local mini = cook.Minigame or {}
	if not isNearCampfire(player) then
		return false, nil, nil, "Stand near the cook."
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

	local flat, slots = parsePlayerCraftingMix(player)
	local result, err = IngredientData.ComputeCraft(flat, cook, slots)
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
		local msg = IngredientData.FormatCookingNotification(result, grade)
		n:FireClient(player, msg, "info", "cooking")
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

	task.spawn(function()
		local t0 = os.clock()
		while cookEnabled and os.clock() - t0 < 60 do
			if IngredientSpawnSystem.EnsureCookNPC() then
				break
			end
			task.wait(0.35)
		end
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
