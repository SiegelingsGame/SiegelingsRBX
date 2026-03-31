-- FavoriteCreatureSystem.lua - ServerScriptService (ModuleScript)
-- UPDATED: FIX #15 crawling orientation + FIX #15b drift guard (2025)
-- Companion creature that follows player, attacks world creatures.
-- Features: HP system, manual targeting, attack toggle, stat-based damage.
-- Companion faints at 0 HP ? 30s cooldown ? auto-respawn.
-- Steal mechanic: player walks up to a fainted base creature (not their own), presses E to pick up,
--   carries it to their base to claim it. If the player dies while carrying, the creature drops
--   and walks back to the owner's base. Companion can still faint base creatures; no auto-pickup.
-- Does NOT listen for SetFavorite events - MainServer handles that.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(ReplicatedStorage.Modules.CreatureAnimation)

local PlayerDataManager
local CreatureSpawner
local CreatureAI
local BasePlacementSystem

local ServerScriptService = game:GetService("ServerScriptService")
local WorldCreatureHP = nil -- loaded lazily in Init or on first damage call
local HttpService = game:GetService("HttpService")

local FavoriteCreatureSystem = {}

local FAVORITE_TAG = "FavoriteCreature"
local WORLD_CREATURE_TAG = "WorldCreature"
local BASE_DEFENSE_TAG = "BaseDefenseCreature"
local BASE_INCOME_TAG = "BaseIncomeCreature"
local FAINTED_BASE_TAG = "FaintedBaseCreature"

local activeCompanions = {}  -- [userId] = { model, creatureId, uid, attackMode, targetModel, hp, maxHp, alive, carrying }
-- World creature selected in target menu (blocks auto-despawn; tracked even when companion is not out)
local worldCombatTargetByUserId = {}
-- Player carry (steal): [userId] = { creatureId, level, xp, victimUserId, victimPlotId, uid, visualModel }
local playerCarryingSteal = {}
-- Companion recalled due to water (non-water creature returned when player swims); respawn when player exits water
local companionRecalledDueToWater = {}
local respawnCooldowns = {}  -- [userId] = tick() when fainted
local faintedCompanionModels = {}  -- unused: companion destroyed immediately on faint (card flies to player)
local pvpFaintedPlayers = {} -- [userId] = true when creature fainted in PvP (must revive with coins/gems)
local spawnLocks = {}  -- [userId] = true while SpawnCompanion is running (prevents double spawn / leftover models)

-- Distance from a point to the closest point on the model's bounding box (so tall creatures can be targeted/attacked from underneath).
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

-- True if position is inside any Part tagged as water block (GameConfig.WaterBlockTag). Used to card non-water favorites when player is in water.
local function isPositionInWaterBlock(worldPos)
	local tag = GameConfig.WaterBlockTag
	if not tag or tag == "" then return false end
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part and part:IsA("BasePart") and part.Parent then
			local localPos = part.CFrame:PointToObjectSpace(worldPos)
			local h = part.Size * 0.5
			if math.abs(localPos.X) <= h.X and math.abs(localPos.Y) <= h.Y and math.abs(localPos.Z) <= h.Z then
				return true
			end
		end
	end
	return false
end

-- FIX #20 Water companion vertical swimming: Returns the WaterBlock part containing worldPos, or nil.
-- Used to get bounds for 3D companion follow inside WaterBlocks (not just Ocean).
local function getWaterBlockContaining(worldPos)
	-- Prefer CreatureAI's version if available (shared logic)
	if CreatureAI and CreatureAI.GetWaterBlockContaining then
		return CreatureAI.GetWaterBlockContaining(worldPos)
	end
	local tag = GameConfig.WaterBlockTag
	if not tag or tag == "" then return nil end
	for _, part in ipairs(CollectionService:GetTagged(tag)) do
		if part and part:IsA("BasePart") and part.Parent then
			local localPos = part.CFrame:PointToObjectSpace(worldPos)
			local h = part.Size * 0.5
			if math.abs(localPos.X) <= h.X and math.abs(localPos.Y) <= h.Y and math.abs(localPos.Z) <= h.Z then
				return part
			end
		end
	end
	return nil
end

-- True if player is in water (position inside a Water Block Part or Humanoid Swimming state). Used to card non-water favorites and respawn when they exit.
local function isPlayerInWater(player)
	local character = player.Character
	if not character then return false end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	if isPositionInWaterBlock(root.Position) then
		return true
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid:GetState() == Enum.HumanoidStateType.Swimming then
		return true
	end
	return false
end

-- Card companion and return it (turn into card, fly to player). Used for water recall and distance recall.
-- If reason is "water", sets companionRecalledDueToWater for auto-respawn when player exits water.
-- If reason is "distance", no auto-respawn; player must manually resummon.
local function doRecall(player, reason)
	local comp = activeCompanions[player.UserId]
	if not comp or not comp.alive then return false end
	if reason == "water" and CreatureData.IsWaterType(comp.creatureId) then return false end
	if comp._waterRecallConn then
		comp._waterRecallConn:Disconnect()
		comp._waterRecallConn = nil
	end
	local bodyForPos = comp.model and (CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body"))
	local creaturePos = bodyForPos and bodyForPos.Position or comp.model:GetPivot().Position
	local evt = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("CompanionRecalled")
	if evt then evt:FireClient(player, creaturePos, comp.creatureId, reason) end
	if comp.model and comp.model.Parent then comp.model:Destroy() end
	activeCompanions[player.UserId] = nil
	if reason == "water" then
		companionRecalledDueToWater[player.UserId] = true
	elseif reason == "distance" then
		local notif = getNotifEvent()
		if notif then
			local cInfo = CreatureData.GetById(comp.creatureId)
			local cName = cInfo and cInfo.displayName or comp.creatureId
			notif:FireClient(player, cName .. " wandered too far and returned to its card. Resummon when ready.")
		end
	end
	return true
end

-- Card non-water companion when player enters water/swimming.
local function doWaterRecall(player)
	return doRecall(player, "water")
end

-- Raycast down from origin to find ground Y (same surface as player would stand on).d
-- FIX: Exclude ALL creature models (WorldCreature, BaseDefense, BaseIncome, FavoriteCreature) and player
-- characters. When a stolen creature is dropped near the companion, raycasts were hitting each other
-- instead of ground, causing both to fly up and oscillate (fly up → respawn → repeat).
local RAYCAST_LENGTH = 50
local function getCreatureExcludeList(baseExcludes)
	local list = {}
	local seen = {}
	for _, v in ipairs(baseExcludes or {}) do
		if v and not seen[v] then seen[v] = true; list[#list + 1] = v end
	end
	for _, tag in ipairs({ WORLD_CREATURE_TAG, BASE_DEFENSE_TAG, BASE_INCOME_TAG, FAVORITE_TAG }) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			if m.Parent and not seen[m] then seen[m] = true; list[#list + 1] = m end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and not seen[p.Character] then seen[p.Character] = true; list[#list + 1] = p.Character end
	end
	return list
end
local function getGroundY(origin, baseExcludes)
	local excludeList = getCreatureExcludeList(baseExcludes)
	local rayOrigin = Vector3.new(origin.X, origin.Y + 2, origin.Z)
	local rayDir = Vector3.new(0, -RAYCAST_LENGTH, 0)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludeList
	local hit = Workspace:Raycast(rayOrigin, rayDir, params)
	if hit then
		return hit.Position.Y
	end
	-- FIX: When ray hits nothing (e.g. over void/gap), returning origin.Y caused runaway inflation:
	-- origin.Y = pos.Y+2, so targetY = origin.Y+height kept adding 2 each frame → companion flew up.
	-- Use origin.Y - 2 to stay at input height (no inflation).
	return origin.Y - 2
end

-- Vertical offset from body position to the lowest point of the model (bbox corners). Extra offset so creature sits ON surface, not in it.
local FLOOR_OFFSET = 0.3
local function getBodyHeightAboveBboxBottom(creatureModel, bodyPart)
	local cf, size = creatureModel:GetBoundingBox()
	local half = size * 0.5
	local minY = math.huge
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local corner = cf:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
				if corner.Y < minY then minY = corner.Y end
			end
		end
	end
	local bodyY = bodyPart and bodyPart.Position.Y or cf.Position.Y
	return (bodyY - minY) + FLOOR_OFFSET
end

-- -- COMPANION MODEL --
-- Use CreatureData.GetModelRotationOffset for per-creature rotation (crawling, modelStandUpAngles, modelRotationY).
-- Fallback: default stand-up + face-player for rigs that export horizontal (legacy placeholder orbs).
--
-- ══════════════════════════════════════════════════════════════════════════════
-- ORIENTATION CONVENTIONS (FIX #15 documentation):
--
-- World creatures (CreatureAI / BasePlacementSystem):
--   - Default orientation: models are spawned as-is (no rotation). CFrame.lookAt() faces movement direction.
--   - Crawling: during Move, GetModelRotationOffset returns -90° X-axis pitch → belly-down.
--              during Idle/Attack, returns CFrame.identity → upright standing.
--   - Rotation applied via: body.CFrame = CFrame.lookAt(pos, target) * rotOffset
--   - CreatureAI resets orientation on Move→non-Move transition (state._lastAnimType tracking).
--
-- Companion creatures (FavoriteCreatureSystem):
--   - Rotation applied via: model:PivotTo(CFrame.new(pos) * (lookCf * rotOffset))
--   - FIX #15b: drift guard re-PivotTo's if body drifts >3 studs on rotation transitions.
--
-- WORKING LAYOUT (do not change without testing):
--   Full Model types (TemplateType="Model"): need 180° X facing correction. Mesh types: no facing correction.
--   COMPANION_STAND_UP_ANGLES: per-creature overrides for horizontal exports (e.g. cacty = {-90,0,0}).
--   Crawling (Sundile, Abysscrawler): isWalking=true → belly-down crawl (COMPANION_ROTATION_DEFAULT only);
--     isWalking=false (Attack/Idle) → upright (with CRAWL_UPRIGHT_CORRECTION to cancel default pitch).
--   FIX #17: Stand-up overrides (sundile/raydile/solgator) now add -90° X pitch during Move for crawl.
--
-- IMPORTANT: Crawling rotation for world vs companion is handled SEPARATELY:
--   - World: CreatureData.GetModelRotationOffset (context="world", isWalking) → -90° pitch on walk
--   - Companion: getCompanionRotationOffset (local to this file) → manages crawl via default ± correction
--   - CreatureData.GetModelRotationOffset SKIPS crawl for context="companion" (PivotTo over-rotates).
--   - NEVER apply world crawl logic to companions or vice versa.
--
-- COMPANION_ROTATION_DEFAULT: For horizontal-export models (placeholder orbs, rigs that export lying down).
-- COMPANION_UPRIGHT_DEFAULT: For upright-export models (Breezee, etc.) – stand-up + facing.
-- COMPANION_STAND_UP_ANGLES: Companion-only overrides for creatures that export horizontal/on-side.
-- COMPANION_FACING_CORRECTION: Full Model types (rigged) need 180° X; legacy Mesh types do snot.sds
-- World spawnfs use CreatureData; companion rotation is FavoriteCreaturedSystem only.x
-- ══════════════════════════════════════════════════════════════════════════════
local COMPANION_FACING_CORRECTION = CFrame.Angles(math.rad(180), 0, 0)  -- full Model types only
local COMPANION_ROTATION_DEFAULT = CFrame.Angles(math.rad(90), 0, math.rad(180)) * CFrame.Angles(0, math.rad(180), 0)
local COMPANION_STAND_UP_ANGLES = {
	ceeponee = {-180, 90, 0},
	ceehorcee = {0,90, -180},
	ceesteed = {-180, 0, 0},
	chilldoe = {-180, 0, -0},
	spoutyl = {-180, 0, 0},
	frostag = {-180, 0, 0},
	droxyl = {-180, 0, 0},
	hydroxyl = {-180, 0, 0},
	cacty = {-90, 0, 0},
	jackedty = {-180, 0, 0},
	cactyjackedty = {-180, 180, 0},
	sundile = {-180, 0, 0},
	raydile = {-180, 0, 0},
	solgator = {-180, 0, 0},
	breezee = {-90, 0, 0},
	gagglestand = {-90, 0, 0},
	hurricrane = {-90, 0, 0},
	pylook = {0, 90, -180},
	pyleer = {0, 180, -180},
	pylme = {-180, 0, 0},
	squirebuddy = {-180, 0, 0},
	generoot = {-180, 0, 0},
	floraknight = {-180, 0, 0},
	pursula = {-180, 0, 0},
	purseus = {-180, 0, 0},
	pursepursula = {-180, 0, 0},
	skydon = {-180, 0, 0},
	applehead = {-90, 0, 0},
	emberfin = {-90, 0, 0},
	cozycub = {-90, 0, 0},
	lumina = {-180, 0, 0},
	squirtle = {-90, 0, 0},
}

local function needsFacingCorrection(model)
	return model and model:GetAttribute("TemplateType") == "Model"
end

-- Crawling: COMPANION_ROTATION_DEFAULT0.0 = base; CRAWL_UPRIGHT_CORRECTION. = -90° X to stand upright.cc
-- Ground stand-up: for non-flying, non-crawling companions – models that export horizonbtal/on-back need this to stand upright..
local COMPANION_CRAWL_UPRIGHT_CORRECTION = CFrame.Angles(math.rad(-90), 0, 0)
local COMPANION_GROUND_UPRIGHT = COMPANION_CRAWL_UPRIGHT_CORRECTION
local function getCompanionRotationOffset(creatureId, isWalking, model)
	local facing = needsFacingCorrection(model) and COMPANION_FACING_CORRECTION or CFrame.identity
	-- Companion-only stand-up for creatures that export horizontal (world spawns unchanged)
	local companionStandUp = creatureId and COMPANION_STAND_UP_ANGLES[creatureId]
	if companionStandUp and #companionStandUp >= 3 then
		local standUp = CFrame.Angles(
			math.rad(companionStandUp[1]),
			math.rad(companionStandUp[2]),
			math.rad(companionStandUp[3])
		)
		-- FIX #17: Crawling creatures with stand-up overrides (sundile, raydile, solgator):
		-- The stand-up angles give the correct IDLE (upright) pose. During Move, add -90° X
		-- pitch to produce belly-crawl orientation. Without this, these creatures used the
		-- static stand-up angle for ALL states and never crawled as companions.
		if isWalking and creatureId and CreatureData.IsCrawling(creatureId) then
			return standUp * CFrame.Angles(math.rad(-90), 0, 0) * facing
		end
		return standUp * facing
	end

	local info = creatureId and CreatureData.GetById(creatureId)
	local fromData = creatureId and CreatureData.GetModelRotationOffset(creatureId, "companion", isWalking)
	if fromData and fromData ~= CFrame.identity then
		return fromData * facing
	end
	-- Upright-export models (no modelStandUpAngles)
	local useUprightDefault = info and not info.modelStandUpAngles
	if useUprightDefault and not (creatureId and CreatureData.IsCrawling(creatureId)) then
		-- Non-flying, non-crawling: models may export horizontal/on-back; stand them upright for all animations
		if not (creatureId and CreatureData.IsFlying(creatureId)) then
			return COMPANION_GROUND_UPRIGHT * facing
		end
		return facing
	end
	-- Crawling creatures without stand-up overrides (e.g. abysscrawler):
	-- FIX #17: Branches were swapped — Move was upright, Idle was belly-down (wrong).
	-- Correct: Move = belly-down (COMPANION_ROTATION_DEFAULT's 90° pitch = crawl naturally).
	--          Idle/Attack = upright (CRAWL_UPRIGHT_CORRECTION cancels the default's 90° pitch).
	if creatureId and CreatureData.IsCrawling(creatureId) then
		if isWalking then
			return COMPANION_ROTATION_DEFAULT * facing  -- belly-down crawl (default 90° pitch provides this)
		else
			return COMPANION_ROTATION_DEFAULT * COMPANION_CRAWL_UPRIGHT_CORRECTION * facing  -- upright (correction cancels 90° pitch)
		end
	end
	return COMPANION_ROTATION_DEFAULT * facing
end

local function createCompanionModel(creatureId, player, entry)
	entry = entry or {}
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end
	local rarityInfo = CreatureData.Rarities[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(180, 180, 180)
	local variant = entry.variant and entry.variant ~= "Normal" and entry.variant or nil

	local model = Instance.new("Model")
	model.Name = "Companion_" .. player.Name

	-- CreatureModelLoader: prefers Model type, then legacy mesh. Scale to match companion mesh.
	local options = { targetSize = 3.5, creatureId = creatureId }
	local body, core, isCustomModel = CreatureModelLoader.LoadAndIntegrate(model, info.modelName, info.displayName, nil, options)
	if isCustomModel then
		core = core or model:FindFirstChild("Core")
	else
		-- === PLACEHOLDER ORB (original code) ===
		body = Instance.new("Part")
		body.Name = "Body"; body.Shape = Enum.PartType.Ball; body.Size = Vector3.new(3.5, 3.5, 3.5)
		body.Color = info.primaryColor; body.Material = Enum.Material.Neon
		body.Anchored = true; body.CanCollide = true; body.CastShadow = true; body.Parent = model

		core = Instance.new("Part")
		core.Name = "Core"; core.Shape = Enum.PartType.Ball; core.Size = Vector3.new(1.8, 1.8, 1.8)
		core.Color = rarityColor; core.Material = Enum.Material.Neon; core.Transparency = 0.2
		core.Anchored = true; core.CanCollide = false; core.Parent = model

		local ring = Instance.new("Part")
		ring.Name = "Ring"; ring.Shape = Enum.PartType.Cylinder; ring.Size = Vector3.new(0.3, 5, 5)
		ring.Color = rarityColor; ring.Material = Enum.Material.Neon; ring.Transparency = 0.5
		ring.Anchored = true; ring.CanCollide = false; ring.Parent = model

		Instance.new("PointLight", body).Color = info.primaryColor
		body:FindFirstChildOfClass("PointLight").Brightness = 2
		body:FindFirstChildOfClass("PointLight").Range = 15

		local hl = Instance.new("Highlight")
		hl.FillColor = info.primaryColor; hl.FillTransparency = 0.6
		hl.OutlineColor = rarityColor; hl.OutlineTransparency = 0; hl.Parent = model
	end

	-- Billboard: name + mode + HP bar (offset to top of bounding box so name isn't blocked)
	local bb = Instance.new("BillboardGui")
	bb.Name = "CompanionTag"; bb.Size = UDim2.new(0, 160, 0, 55)
	bb.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0); bb.AlwaysOnTop = false; bb.MaxDistance = 50
	bb.Adornee = body; bb.Parent = model

	local nameLbl = Instance.new("TextLabel")
	nameLbl.Size = UDim2.new(1, 0, 0, 18); nameLbl.BackgroundTransparency = 1
	local variantSuffix = variant and (" · " .. variant .. " ") or " "
	local companionName = (entry and type(entry.nickname) == "string" and entry.nickname ~= "")
		and (entry.nickname .. " (" .. info.displayName .. ")")
		or info.displayName
	nameLbl.Text = companionName .. variantSuffix .. "(Companion)"
	nameLbl.TextColor3 = Color3.new(1,1,1); nameLbl.TextScaled = true
	nameLbl.Font = Enum.Font.GothamBold; nameLbl.Parent = bb

	local modeLbl = Instance.new("TextLabel")
	modeLbl.Name = "ModeLbl"; modeLbl.Size = UDim2.new(1, 0, 0, 14)
	modeLbl.Position = UDim2.new(0, 0, 0, 18); modeLbl.BackgroundTransparency = 1
	modeLbl.Text = "ATTACK MODE"; modeLbl.TextColor3 = Color3.fromRGB(255, 100, 60)
	modeLbl.TextScaled = true; modeLbl.Font = Enum.Font.GothamMedium; modeLbl.Parent = bb

	local hpBg = Instance.new("Frame")
	hpBg.Name = "HPBar"; hpBg.Size = UDim2.new(0.8, 0, 0, 6)
	hpBg.Position = UDim2.new(0.1, 0, 0, 36); hpBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBg.BorderSizePixel = 0; hpBg.Parent = bb
	Instance.new("UICorner", hpBg).CornerRadius = UDim.new(0, 3)

	local hpFill = Instance.new("Frame")
	hpFill.Name = "Fill"; hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(80, 255, 120); hpFill.BorderSizePixel = 0; hpFill.Parent = hpBg
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 3)

	local hpLbl = Instance.new("TextLabel")
	hpLbl.Name = "HPLbl"; hpLbl.Size = UDim2.new(1, 0, 0, 10)
	hpLbl.Position = UDim2.new(0, 0, 0, 44); hpLbl.BackgroundTransparency = 1
	hpLbl.TextColor3 = Color3.fromRGB(180, 185, 200); hpLbl.Font = Enum.Font.GothamMedium
	hpLbl.TextSize = 9; hpLbl.Parent = bb

	CollectionService:AddTag(model, FAVORITE_TAG)
	model:SetAttribute("OwnerUserId", player.UserId)
	model.PrimaryPart = body; model.Parent = workspace

	-- Apply companion rotation (initial spawn = Idle, no crawl; crawl only during Move)
	model:PivotTo(model:GetPivot() * getCompanionRotationOffset(creatureId, false, model))

	CreatureAnimation.Setup(model, creatureId, "Idle")
	return model
end

-- -- EFFECTS --

local function createAttackEffect(fromPos, toPos, color)
	task.spawn(function()
		local bolt = Instance.new("Part")
		bolt.Size = Vector3.new(1.5, 1.5, 1.5); bolt.Shape = Enum.PartType.Ball
		bolt.Color = color; bolt.Material = Enum.Material.Neon
		bolt.Anchored = true; bolt.CanCollide = false; bolt.CastShadow = false; bolt.Parent = workspace
		local dur = 0.2; local s = tick()
		while tick() - s < dur do
			bolt.Position = fromPos:Lerp(toPos, (tick() - s) / dur); RunService.Heartbeat:Wait()
		end
		bolt.Size = Vector3.new(2.5, 2.5, 2.5); bolt.Transparency = 0.3
		task.wait(0.1); bolt:Destroy()
	end)
end

-- Only show damage number to the relevant player (companion owner), not all players in open world
local function fireDamageNumberToPlayer(player, position, damage, color)
	if not player or not player.Parent or not position then return end
	local evt = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("ShowDamageNumber")
	if evt and evt:IsA("RemoteEvent") then
		evt:FireClient(player, position, damage, color)
	end
end

-- -- HP BAR --

local function updateCompanionHPBar(comp)
	if not comp or not comp.model or not comp.model.Parent then return end
	local bb = comp.model:FindFirstChild("CompanionTag")
	if not bb then return end
	local hpBar = bb:FindFirstChild("HPBar")
	local hpLbl = bb:FindFirstChild("HPLbl")
	if hpBar then
		local fill = hpBar:FindFirstChild("Fill")
		if fill and comp.maxHp > 0 then
			local ratio = math.clamp(comp.hp / comp.maxHp, 0, 1)
			fill.Size = UDim2.new(ratio, 0, 1, 0)
			if ratio > 0.5 then fill.BackgroundColor3 = Color3.fromRGB(80, 255, 120)
			elseif ratio > 0.25 then fill.BackgroundColor3 = Color3.fromRGB(255, 200, 50)
			else fill.BackgroundColor3 = Color3.fromRGB(255, 60, 40) end
		end
	end
	if hpLbl then hpLbl.Text = math.max(0, math.floor(comp.hp)) .. " / " .. comp.maxHp end

	-- Update XP bar if present
	if comp.uid then
		local xpBar = bb:FindFirstChild("XPBar")
		local xpLbl = bb:FindFirstChild("XPLbl")
		-- Find owner player to get latest XP
		local ownerId = comp.model:GetAttribute("OwnerUserId")
		local owner = ownerId and Players:GetPlayerByUserId(ownerId)
		if owner and xpBar and xpLbl then
			local entry = PlayerDataManager.GetCreatureByUid(owner, comp.uid)
			if entry then
				local lvl = entry.level or 1
				local xp = entry.xp or 0
				local maxLvl = CreatureData.GetMaxCreatureLevel and CreatureData.GetMaxCreatureLevel(entry.id) or (GameConfig.MaxCreatureLevel or 10)
				local xpNeeded = PlayerDataManager.XPForLevel(lvl + 1)
				local xpPct = (lvl >= maxLvl) and 1 or (xpNeeded > 0 and math.min(1, xp / xpNeeded) or 0)
				local fill2 = xpBar:FindFirstChild("Fill")
				if fill2 then fill2.Size = UDim2.new(xpPct, 0, 1, 0) end
				xpLbl.Text = (lvl >= maxLvl) and "MAX LEVEL" or ("XP: " .. xp .. "/" .. xpNeeded)

				-- Update name with current level and variant
				local nameLbl = bb:FindFirstChildWhichIsA("TextLabel")
				if nameLbl then
					local info = CreatureData.GetById(comp.creatureId)
					if info then
						local lvlText = lvl >= maxLvl and " [MAX]" or (" Lv." .. lvl)
						local variantSuffix = (comp.variant and comp.variant ~= "Normal") and (" · " .. comp.variant) or ""
						local displayName = (entry.nickname and entry.nickname ~= "")
							and (entry.nickname .. " (" .. info.displayName .. ")")
							or info.displayName
						nameLbl.Text = displayName .. variantSuffix .. lvlText
					end
				end
			end
		end
	end
end

-- -- STEAL HELPERS (player carry to base; walk back on death) --

local PLOTS_FOLDER = nil
local function getPlotsFolder()
	if not PLOTS_FOLDER then PLOTS_FOLDER = Workspace:FindFirstChild("BasePlots") end
	return PLOTS_FOLDER
end

local function getPlotCenterPosition(plotId)
	local folder = getPlotsFolder()
	if not folder or not plotId then return nil end
	local plotModel = folder:FindFirstChild("Plot" .. plotId) or folder:FindFirstChild("Part" .. plotId)
	if not plotModel then return nil end
	local pc = plotModel:FindFirstChild("PlotCenter", true)
	if not pc then return nil end
	if pc:IsA("BasePart") then return pc.Position end
	if pc:IsA("Model") then return pc:GetPivot().Position end
	return nil
end

-- Get plotId from a model that lives inside a plot (e.g. base creature model)
local function getPlotIdFromDescendant(model)
	if not model or not model.Parent then return nil end
	local folder = getPlotsFolder()
	if not folder then return nil end
	local current = model
	while current and current ~= Workspace do
		if current.Parent == folder then
			local id = current.Name:match("^Plot(%d+)$") or current.Name:match("^Part(%d+)$")
			if id then return tonumber(id) end
		end
		current = current.Parent
	end
	return nil
end

local function getNotifEvent()
	local events = ReplicatedStorage:FindFirstChild("Events")
	return events and events:FindFirstChild("CaptureFail")
end

local function getStolenEvent()
	local events = ReplicatedStorage:FindFirstChild("Events")
	return events and events:FindFirstChild("CreatureStolen")
end

local function getCompanionSpawnedEvent()
	local events = ReplicatedStorage:FindFirstChild("Events")
	return events and events:FindFirstChild("CompanionSpawned")
end

-- Drop the carried creature as a wild spawn at the given position
local function dropStolenCreature(player, comp)
	if not comp or not comp.carrying then return end
	local carry = comp.carrying

	-- Destroy carry visual
	if carry.visualModel and carry.visualModel.Parent then
		carry.visualModel:Destroy()
	end

	-- Spawn as wild creature at drop position
	local dropPos = nil
	local body = comp.model and (CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body"))
	if body then dropPos = body.Position end
	if not dropPos then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		dropPos = root and root.Position or Vector3.new(0, 10, 0)
	end

	if CreatureSpawner and CreatureSpawner.SpawnSpecificCreature then
		local wildModel = CreatureSpawner.SpawnSpecificCreature(carry.creatureId, dropPos)
		if wildModel then
			wildModel:SetAttribute("CreatureLevel", carry.level or 1)
		end
	end

	local notif = getNotifEvent()
	if notif then
		local cInfo = CreatureData.GetById(carry.creatureId)
		local cName = cInfo and cInfo.displayName or carry.creatureId
		notif:FireClient(player, cName .. " was dropped! It escaped into the wild.")
	end

	comp.carrying = nil
end

-- Deliver the stolen creature to the player's inventory
local function deliverStolenCreature(player, comp)
	if not comp or not comp.carrying then return end
	local carry = comp.carrying

	-- Destroy carry visual
	if carry.visualModel and carry.visualModel.Parent then
		carry.visualModel:Destroy()
	end

	-- Add creature to player's inventory
	local newUid = PlayerDataManager.AddCreature(player, carry.creatureId, carry.level, carry.xp, nil, nil, { source = "raid" })

	local cInfo = CreatureData.GetById(carry.creatureId)
	local cName = cInfo and cInfo.displayName or carry.creatureId

	local notif = getNotifEvent()
	if newUid then
		if notif then
			notif:FireClient(player, "You stole " .. cName .. "! Added to inventory.")
		end
	else
		-- Inventory full ? drop as wild (offset from player to avoid overlap with companion)
		if notif then
			notif:FireClient(player, "Inventory full! " .. cName .. " escaped.")
		end
		if CreatureSpawner and CreatureSpawner.SpawnSpecificCreature then
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart")
			local basePos = root and root.Position or Vector3.new(0, 10, 0)
			-- Spawn 6 studs to the right of player to avoid companion overlap (companion follows behind)
			local rightVec = root and (root.CFrame.RightVector * 6) or Vector3.new(6, 0, 0)
			local dropPos = basePos + rightVec
			CreatureSpawner.SpawnSpecificCreature(carry.creatureId, dropPos)
		end
	end

	comp.carrying = nil
	-- Force position reset on next behavior tick to prevent floating/stuck state after delivery
	comp._needsPositionReset = true
end

-- Deliver stolen creature when player (carrier) reaches their own base
local function deliverStolenCreatureForPlayer(player)
	local carry = playerCarryingSteal[player.UserId]
	if not carry then return end
	if carry.visualModel and carry.visualModel.Parent then carry.visualModel:Destroy() end
	local newUid = PlayerDataManager.AddCreature(player, carry.creatureId, carry.level, carry.xp, nil, nil, { source = "raid" })
	local cInfo = CreatureData.GetById(carry.creatureId)
	local cName = cInfo and cInfo.displayName or carry.creatureId
	local notif = getNotifEvent()
	if newUid then
		if notif then notif:FireClient(player, "You stole " .. cName .. "! Added to inventory.") end
	else
		if notif then notif:FireClient(player, "Inventory full! " .. cName .. " escaped.") end
		if CreatureSpawner and CreatureSpawner.SpawnSpecificCreature then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			local basePos = root and root.Position or Vector3.new(0, 10, 0)
			local rightVec = root and (root.CFrame.RightVector * 6) or Vector3.new(6, 0, 0)
			CreatureSpawner.SpawnSpecificCreature(carry.creatureId, basePos + rightVec)
		end
	end
	playerCarryingSteal[player.UserId] = nil
end

-- Drop carried creature on player death: creature walks back to owner's base; on arrival, restore to owner
local function dropPlayerCarryAndWalkBack(player)
	local carry = playerCarryingSteal[player.UserId]
	if not carry then return end
	if carry.visualModel and carry.visualModel.Parent then carry.visualModel:Destroy() end
	playerCarryingSteal[player.UserId] = nil

	local dropPos = Vector3.new(0, 10, 0)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
	if root then dropPos = root.Position end

	local victimUserId = carry.victimUserId
	local victimPlotId = carry.victimPlotId
	local creatureId = carry.creatureId
	local level = carry.level or 1
	local xp = carry.xp or 0
	local cInfo = CreatureData.GetById(creatureId)
	local cName = cInfo and cInfo.displayName or creatureId

	local notif = getNotifEvent()
	if notif then notif:FireClient(player, cName .. " was dropped! It's walking back to its owner's base.") end

	-- Spawn a visual model that walks back to owner's plot
	if not CreatureSpawner or not CreatureSpawner.SpawnSpecificCreature then return end
	local walkModel = CreatureSpawner.SpawnSpecificCreature(creatureId, dropPos)
	if not walkModel then return end
	walkModel:SetAttribute("CreatureLevel", level)
	walkModel:SetAttribute("WalkingBackToOwner", true)
	CollectionService:RemoveTag(walkModel, WORLD_CREATURE_TAG)
	CollectionService:AddTag(walkModel, "WalkingBackToOwner")
	if CreatureAI and CreatureAI.UnregisterCreature then CreatureAI.UnregisterCreature(walkModel) end
	local body = CreatureModelLoader.GetBodyPart(walkModel) or walkModel:FindFirstChild("Body")
	if not body then walkModel:Destroy(); return end
	body.Anchored = false

	local walkSpeed = GameConfig.StealWalkBackSpeed or 14
	local homeRadius = GameConfig.StealHomeRadius or 30

	task.spawn(function()
		local dt = 0
		while walkModel.Parent and body.Parent do
			dt = RunService.Heartbeat:Wait()
			local targetPos = getPlotCenterPosition(victimPlotId)
			if not targetPos then break end
			local pos = body.Position
			local toTarget = targetPos - pos
			local flat = Vector3.new(toTarget.X, 0, toTarget.Z)
			local dist = flat.Magnitude
			if dist <= homeRadius then
				-- Arrived at owner's base: restore creature to owner
				walkModel:Destroy()
				local victimPlayer = Players:GetPlayerByUserId(victimUserId)
				if victimPlayer then
					PlayerDataManager.AddCreature(victimPlayer, creatureId, level, xp, nil, nil, { source = "recovered" })
					if notif then notif:FireClient(victimPlayer, cName .. " returned to your base!") end
				end
				return
			end
			local step = math.min(walkSpeed * dt, dist)
			local newPos = pos + flat.Unit * step
			body.CFrame = CFrame.lookAt(newPos, newPos + flat)
		end
		if walkModel.Parent then walkModel:Destroy() end
	end)
end

-- Player picks up a fainted base creature (E interact); creature is carried by player, not companion
local function playerPickUpSteal(player, baseModel)
	if playerCarryingSteal[player.UserId] then return false, "Already carrying a creature." end
	if not baseModel or not baseModel.Parent then return false, "Invalid creature." end
	if not baseModel:GetAttribute("Fainted") or not CollectionService:HasTag(baseModel, FAINTED_BASE_TAG) then
		return false, "Creature must be fainted first."
	end
	local ownerUserId = baseModel:GetAttribute("OwnerUserId")
	if not ownerUserId or ownerUserId == player.UserId then return false, "You can't steal your own creature." end

	local creatureId = baseModel:GetAttribute("CreatureId")
	local creatureLevel = baseModel:GetAttribute("CreatureLevel") or 1
	local uid = baseModel:GetAttribute("UID")
	local victimUserId = baseModel:GetAttribute("OwnerUserId")
	local victimPlotId = getPlotIdFromDescendant(baseModel)
	local slotType = baseModel:GetAttribute("SlotType")
	local slotIndex = baseModel:GetAttribute("SlotIndex")

	-- Remove from victim's data and clear the slot (frees the point and removes the model)
	local victimPlayer = Players:GetPlayerByUserId(victimUserId)
	if victimPlayer and uid then
		PlayerDataManager.RemoveCreature(victimPlayer, uid)
	end
	if victimPlayer and slotType and slotIndex and (slotType == "defense" or slotType == "income") and BasePlacementSystem and BasePlacementSystem.ClearCreatureAtSlot then
		BasePlacementSystem.ClearCreatureAtSlot(victimPlayer, slotType, slotIndex)
	else
		if CreatureAI and CreatureAI.UnregisterCreature then CreatureAI.UnregisterCreature(baseModel) end
		baseModel:Destroy()
	end
	local cInfo = CreatureData.GetById(creatureId)
	local cName = cInfo and cInfo.displayName or creatureId
	if victimPlayer then
		local n = getNotifEvent()
		if n then n:FireClient(victimPlayer, cName .. " was picked up by " .. player.Name .. "! Defeat them before they reach their base to get it back.") end
	end

	local carryVisual = Instance.new("Part")
	carryVisual.Name = "CarryOrb"
	carryVisual.Shape = Enum.PartType.Ball
	carryVisual.Size = Vector3.new(2, 2, 2)
	carryVisual.Color = cInfo and cInfo.primaryColor or Color3.fromRGB(255, 200, 100)
	carryVisual.Material = Enum.Material.Neon
	carryVisual.Transparency = 0.2
	carryVisual.Anchored = true
	carryVisual.CanCollide = false
	carryVisual.CastShadow = false
	carryVisual.Parent = workspace
	local carryHL = Instance.new("Highlight")
	carryHL.FillColor = Color3.fromRGB(255, 255, 100)
	carryHL.FillTransparency = 0.5
	carryHL.OutlineColor = Color3.fromRGB(255, 200, 0)
	carryHL.OutlineTransparency = 0.2
	carryHL.Parent = carryVisual

	playerCarryingSteal[player.UserId] = {
		creatureId = creatureId,
		level = creatureLevel,
		xp = 0,
		uid = uid,
		victimUserId = victimUserId,
		victimPlotId = victimPlotId,
		visualModel = carryVisual,
	}
	local n = getNotifEvent()
	if n then n:FireClient(player, "Picked up " .. cName .. "! Return to your base to claim it.") end
	return true
end

-- Pick up a fainted base creature (COMPANION - no longer used for steal; kept for reference/removal)
local function pickUpBaseCreature(player, comp, baseModel)
	if not comp or comp.carrying then return end -- already carrying

	local creatureId = baseModel:GetAttribute("CreatureId")
	local creatureLevel = baseModel:GetAttribute("CreatureLevel") or 1
	local uid = baseModel:GetAttribute("UID")
	local victimUserId = baseModel:GetAttribute("OwnerUserId")
	if not creatureId or not victimUserId then return end

	-- Remove from victim's data
	local victimPlayer = Players:GetPlayerByUserId(victimUserId)
	if victimPlayer and uid then
		PlayerDataManager.RemoveCreature(victimPlayer, uid)
	end

	-- Notify victim
	local notif = getNotifEvent()
	local cInfo = CreatureData.GetById(creatureId)
	local cName = cInfo and cInfo.displayName or creatureId
	if victimPlayer and notif then
		notif:FireClient(victimPlayer, cName .. " was stolen by " .. player.Name .. "!")
	end

	-- Unregister from CreatureAI before destroying
	if CreatureAI and CreatureAI.UnregisterCreature then
		CreatureAI.UnregisterCreature(baseModel)
	end

	-- Destroy the original base creature model
	baseModel:Destroy()

	-- Incremental: stolen creature's slot is cleared in victim data; model already destroyed
	-- No full refresh needed

	--Create carry visual ? small orb trailing the companion
	local carryVisual = Instance.new("Part")
	carryVisual.Name = "CarryOrb"
	carryVisual.Shape = Enum.PartType.Ball
	carryVisual.Size = Vector3.new(2, 2, 2)
	carryVisual.Color = cInfo and cInfo.primaryColor or Color3.fromRGB(255, 200, 100)
	carryVisual.Material = Enum.Material.Neon
	carryVisual.Transparency = 0.2
	carryVisual.Anchored = true
	carryVisual.CanCollide = false
	carryVisual.CastShadow = false
	carryVisual.Parent = workspace

	local carryHL = Instance.new("Highlight")
	carryHL.FillColor = Color3.fromRGB(255, 255, 100)
	carryHL.FillTransparency = 0.5
	carryHL.OutlineColor = Color3.fromRGB(255, 200, 0)
	carryHL.OutlineTransparency = 0.2
	carryHL.Parent = carryVisual

	-- Store carry data
	comp.carrying = {
		creatureId = creatureId,
		level = creatureLevel,
		xp = 0,
		uid = uid,
		victimUserId = victimUserId,
		visualModel = carryVisual,
	}

	if notif then
		notif:FireClient(player, "Picked up " .. cName .. "! Return to your base to claim it.")
	end
end

-- -- DAMAGE / FAINT --

function FavoriteCreatureSystem.DamageCompanion(player, damage, attackerModel)
	local comp = activeCompanions[player.UserId]
	if not comp or not comp.alive then return end
	-- Elemental weakness: attacker vs defender (companion)
	local defenderInfo = CreatureData.GetById(comp.creatureId)
	local attackerCid = attackerModel and attackerModel:GetAttribute("CreatureId")
	local attackerInfo = attackerCid and CreatureData.GetById(attackerCid)
	local elemMult = CreatureData.GetElementalDamageMultiplier(attackerInfo and attackerInfo.element, defenderInfo and defenderInfo.element)
	if elemMult > 1 then
		damage = damage * (GameConfig.ElementalAdvantageMultiplier or elemMult)
	elseif elemMult < 1 then
		damage = damage * (GameConfig.ElementalDisadvantageMultiplier or elemMult)
	end
	damage = math.floor(math.max(1, damage))
	comp.hp = comp.hp - damage
	updateCompanionHPBar(comp)
	local body = comp.model and (CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body"))
	if body then
		fireDamageNumberToPlayer(player, body.Position, damage, Color3.fromRGB(255, 120, 80))
		task.spawn(function()
			local oc = body.Color; body.Color = Color3.fromRGB(255, 50, 50)
			task.wait(0.12); if body.Parent then body.Color = oc end
		end)
	end
	if comp.hp <= 0 then FavoriteCreatureSystem.FaintCompanion(player, attackerModel) end
end

-- Optional: set in Init. Fired when companion faints: (player, killerModel). Used for defense kill XP.
FavoriteCreatureSystem.OnCompanionFainted = nil

function FavoriteCreatureSystem.FaintCompanion(player, killerModel)
	local comp = activeCompanions[player.UserId]
	if not comp then return end
	if comp._waterRecallConn then
		comp._waterRecallConn:Disconnect()
		comp._waterRecallConn = nil
	end

	-- Notify so defense turret can get XP for this kill
	if FavoriteCreatureSystem.OnCompanionFainted then
		task.spawn(function()
			FavoriteCreatureSystem.OnCompanionFainted:Fire(player, killerModel)
		end)
	end

	-- Drop stolen creature if carrying
	if comp.carrying then
		dropStolenCreature(player, comp)
	end

	comp.alive = false

	if comp.model and comp.model.Parent then
		-- Get position for client card animation before destroying
		local body = CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body")
		local creaturePos = body and body.Position or comp.model:GetPivot().Position
		-- Fire client: creature turns into card, flies to player
		local evt = ReplicatedStorage:FindFirstChild("Events") and ReplicatedStorage.Events:FindFirstChild("CompanionFainted")
		if evt then evt:FireClient(player, creaturePos, comp.creatureId) end
		comp.model:Destroy()
	end

	respawnCooldowns[player.UserId] = tick()
	activeCompanions[player.UserId] = nil

	local notifEvent = getNotifEvent()
	if notifEvent then
		notifEvent:FireClient(player, "Companion fainted! Respawning in " .. GameConfig.CompanionRespawnCD .. " seconds...")
	end

	task.spawn(function()
		task.wait(GameConfig.CompanionRespawnCD)
		if not player.Parent then return end
		respawnCooldowns[player.UserId] = nil
		local entry = PlayerDataManager.GetFavorite(player)
		if entry then
			FavoriteCreatureSystem.SpawnCompanion(player)
			if notifEvent then notifEvent:FireClient(player, "Companion respawned!") end
		end
	end)
end

function FavoriteCreatureSystem.GetCompanionForModel(model)
	local ownerId = model:GetAttribute("OwnerUserId")
	if ownerId then
		local player = Players:GetPlayerByUserId(ownerId)
		if player then return player, activeCompanions[ownerId] end
	end
	return nil, nil
end

-- -- COMPANION BEHAVIOR --

local function startCompanionBehavior(player, model, creatureId)
	local info = CreatureData.GetById(creatureId)
	local rarityInfo = CreatureData.Rarities[info.rarity]
	local attackColor = rarityInfo and rarityInfo.color or Color3.fromRGB(255, 200, 60)
	-- Scale damage by level and variant (Silver/Gold/Legend)
	local entry = PlayerDataManager.GetFavorite(player)
	local lvl = entry and entry.level or 1
	local variant = entry and (entry.variant or "Normal") or "Normal"
	local stats = PlayerDataManager.GetEffectiveStats(creatureId, lvl, variant, player)
	local attackStat = stats and stats.attack or (info.attack * (1 + GameConfig.StatGainPerLevel * (lvl - 1)))
	local baseDamage = math.max(5, math.floor(attackStat * GameConfig.CompanionBaseDamage / 10))
	local body = CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
	local core = model:FindFirstChild("Core")
	local ring = model:FindFirstChild("Ring")
	if not body then return end
	-- When character starts swimming, card non-water companion immediately (StateChanged fires the moment swimming begins)
	local comp = activeCompanions[player.UserId]
	if comp and not CreatureData.IsWaterType(creatureId) then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			comp._waterRecallConn = hum.StateChanged:Connect(function(_, newState)
				if newState == Enum.HumanoidStateType.Swimming then
					doWaterRecall(player)
				end
			end)
		end
	end
	local lastAttackTime = 0; local t = 0

	task.spawn(function()
		local frameCount = 0
		-- Use while true + explicit checks so we don't exit just because the closure 'body' was removed/replaced (e.g. during combat/effects)
		while true do
			if not model.Parent then break end
			local dt = RunService.Heartbeat:Wait(); t = t + dt
			frameCount = frameCount + 1
			local comp = activeCompanions[player.UserId]
			if not comp or not comp.alive then
				break
			end
			-- In passive mode always clear target so we never use a stale combat target (fixes stagnant companion)
			if not comp.attackMode then
				comp.targetModel = nil
			else
				-- In attack mode: clear target when it's dead/destroyed so companion resumes following after combat
				if comp.targetModel and (not comp.targetModel.Parent or comp.targetModel:GetAttribute("Fainted")) then
					comp.targetModel = nil
					-- Reset stationary tracking so companion immediately shows Move and resumes follow (fixes follow breaking after combat exit)
					comp.lastAnimPos = nil
					comp.lastAnimPosTime = nil
				end
			end
			local character = player.Character
			if not character then continue end
			local root = character:FindFirstChild("HumanoidRootPart")
			if not root then continue end

			-- Water recall: when player is in water, non-water favorites must be carded (card animation at creature pos, flies to player)
			local isPlayerInWaterNow = isPlayerInWater(player)
			if isPlayerInWaterNow and not CreatureData.IsWaterType(creatureId) then
				doWaterRecall(player)
				break
			end

			-- Distance recall: if companion gets too far from player, auto-card and force resummon
			local bodyPartForDist = comp.model and (CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body"))
			if bodyPartForDist then
				local maxDist = GameConfig.CompanionAutoRecallDistance or 150
				local distToPlayer = (root.Position - bodyPartForDist.Position).Magnitude
				if distToPlayer > maxDist then
					doRecall(player, "distance")
					break
				end
			end

			-- Resolve body from current comp model each frame (avoids stale reference if model was replaced)
			local bodyPart = comp.model and (CreatureModelLoader.GetBodyPart(comp.model) or comp.model:FindFirstChild("Body"))
			if not bodyPart then break end

			-- Stun (e.g. ElectricBiome ElectroBall): skip movement while StunnedUntil > tick()
			local su = comp.model:GetAttribute("StunnedUntil")
			if su and type(su) == "number" and tick() < su then
				continue
			end

			-- FIX #20 + FIX #26: Follow target behind player. Water creature follows in 3D when player is in any water.
			-- FIX #26: Also detect Roblox terrain water (Humanoid Swimming state) as valid water,
			-- not just tagged WaterBlock/Ocean parts. Previously water creatures couldn't follow in terrain water.
			local isPlayerInOcean = CreatureAI and CreatureAI.IsPositionInOcean and CreatureAI.IsPositionInOcean(root.Position)
			local isPlayerInWaterBlock = isPositionInWaterBlock(root.Position)
			local humanoidSwimming = false
			local playerHumanoid = character:FindFirstChildOfClass("Humanoid")
			if playerHumanoid and playerHumanoid:GetState() == Enum.HumanoidStateType.Swimming then
				humanoidSwimming = true
			end
			local isWaterFollowing = (isPlayerInOcean or isPlayerInWaterBlock or humanoidSwimming) and CreatureData.IsWaterType(creatureId)
			-- Cache the water volume part for Y-clamping (Ocean part or WaterBlock part)
			local waterVolumePart = nil
			if isWaterFollowing then
				if isPlayerInOcean then
					waterVolumePart = CreatureAI and CreatureAI.GetOceanPart and CreatureAI.GetOceanPart()
				end
				if not waterVolumePart and isPlayerInWaterBlock then
					waterVolumePart = getWaterBlockContaining(root.Position)
				end
			end
			local targetPos
			if isWaterFollowing then
				-- Clamp companion Y to water volume bounds so they stay within the water volume
				local behind = root.Position - root.CFrame.LookVector * GameConfig.CompanionFollowDist
				local maxY = root.Position.Y + (GameConfig.WaterCompanionMaxSurfaceOffset or 1.5)
				if waterVolumePart then
					local topY = waterVolumePart.Position.Y + waterVolumePart.Size.Y * 0.5
					local bottomY = waterVolumePart.Position.Y - waterVolumePart.Size.Y * 0.5
					maxY = math.min(maxY, topY)
					behind = Vector3.new(behind.X, math.clamp(behind.Y, bottomY, topY), behind.Z)
				end
				targetPos = Vector3.new(behind.X, math.min(behind.Y, maxY), behind.Z)
			else
				local followXZ = root.Position + root.CFrame.LookVector * -GameConfig.CompanionFollowDist
				local groundYAtTarget = getGroundY(Vector3.new(followXZ.X, root.Position.Y, followXZ.Z), { character })
				local desiredY = CreatureData.IsFlying(creatureId)
					and (groundYAtTarget + (GameConfig.FlyingHoverHeight or 5))
					or (groundYAtTarget + getBodyHeightAboveBboxBottom(model, bodyPart))
				targetPos = Vector3.new(followXZ.X, desiredY, followXZ.Z)
			end

			local currentPos = bodyPart.Position
			local toTarget = targetPos - currentPos
			local dist = toTarget.Magnitude
			local newPos = currentPos

			-- Follow speed: match player speed so companion keeps default distance; blend to catch-up speed when far (smooth, no choppy jump)
			local playerSpeed = (humanoid and humanoid.WalkSpeed) or 16
			local catchUpSpeed = GameConfig.CompanionFollowSpeed or 28
			local catchUpDist = GameConfig.CompanionFollowCatchUpDist or (GameConfig.CompanionFollowDist * 2)
			local blendRange = 10  -- studs over which we blend from player speed to catch-up speed
			local targetSpeed = playerSpeed
			if dist > catchUpDist then
				local t = math.clamp((dist - catchUpDist) / blendRange, 0, 1)
				targetSpeed = playerSpeed + (catchUpSpeed - playerSpeed) * t
			end
			if comp.carrying then
				targetSpeed = targetSpeed * (GameConfig.StealCarrySpeed or 0.8)
			end
			-- Lerp applied speed toward target so it never jumps frame-to-frame (removes choppy catch-up)
			local smoothRate = (GameConfig.CompanionFollowSpeedSmooth or 10) * dt
			comp._followSpeed = comp._followSpeed or playerSpeed
			comp._followSpeed = comp._followSpeed + (targetSpeed - comp._followSpeed) * math.min(1, smoothRate)
			local followSpeed = comp._followSpeed

			-- After delivering a stolen creature, snap to correct position to fix floating/stuck
			if comp._needsPositionReset then
				newPos = targetPos
				comp._needsPositionReset = nil
			elseif dist > 1 then
				-- Safeguard: NaN or invalid dist can leave companion stuck after combat; snap to player to recover
				if dist ~= dist or dist < 0 then
					newPos = targetPos
				elseif dist > 35 then
					-- Use high speed to close gap smoothly instead of teleport (avoids visible snap)
					local step = toTarget.Unit * math.min(math.max(followSpeed, 45) * dt, dist)
					newPos = currentPos + step
				else
					local step = toTarget.Unit * math.min(followSpeed * dt, dist)
					if step.Magnitude ~= step.Magnitude then
						newPos = targetPos
					else
						newPos = currentPos + step
					end
				end
			end
			-- Keep companion at correct height: water (swimming) keeps 3D but clamped below surface; ground on surface; flying at hover
			if not isWaterFollowing then
				local groundYHere = getGroundY(Vector3.new(newPos.X, newPos.Y + 2, newPos.Z), { character, comp.model })
				local heightHere = CreatureData.IsFlying(creatureId)
					and (GameConfig.FlyingHoverHeight or 5)
					or getBodyHeightAboveBboxBottom(model, bodyPart)
				local targetY = groundYHere + heightHere
				-- FIX: When carrying, ground AND flying creatures use smoothed Y to prevent fly-up/oscillation from unstable raycasts over bases
				if comp.carrying then
					comp._carryFlyingY = comp._carryFlyingY or targetY
					local smoothSpeed = math.min(1, dt * 4)
					comp._carryFlyingY = comp._carryFlyingY + (targetY - comp._carryFlyingY) * smoothSpeed
					targetY = comp._carryFlyingY
				else
					comp._carryFlyingY = nil
				end
				newPos = Vector3.new(newPos.X, targetY, newPos.Z)
			else
				-- FIX #20: Water companion: clamp Y within water volume bounds (Ocean or WaterBlock)
				comp._carryFlyingY = nil
				local maxY = root.Position.Y + (GameConfig.WaterCompanionMaxSurfaceOffset or 1.5)
				if waterVolumePart then
					local topY = waterVolumePart.Position.Y + waterVolumePart.Size.Y * 0.5
					local bottomY = waterVolumePart.Position.Y - waterVolumePart.Size.Y * 0.5
					maxY = math.min(maxY, topY)
					newPos = Vector3.new(newPos.X, math.clamp(newPos.Y, bottomY, maxY), newPos.Z)
				elseif newPos.Y > maxY then
					newPos = Vector3.new(newPos.X, maxY, newPos.Z)
				end
			end
			-- Check for attack targets in range FIRST. Attack whenever in range, even when moving (cooldown only affects damage).
			local hasAttackTargetInRange = false
			if comp.attackMode and not comp.carrying then
				if comp.targetModel and comp.targetModel.Parent and not comp.targetModel:GetAttribute("Fainted") then
					if getDistanceToModel(bodyPart.Position, comp.targetModel) <= GameConfig.CompanionAttackRange then
						hasAttackTargetInRange = true
					end
				end
				if not hasAttackTargetInRange then
					for _, tagged in ipairs(CollectionService:GetTagged(WORLD_CREATURE_TAG)) do
						if tagged.Parent and not tagged:GetAttribute("Fainted") and not CollectionService:HasTag(tagged, "ArenaCreature") then
							if getDistanceToModel(bodyPart.Position, tagged) <= GameConfig.CompanionAttackRange then
								hasAttackTargetInRange = true; break
							end
						end
					end
				end
				if not hasAttackTargetInRange then
					for _, tag in ipairs({BASE_DEFENSE_TAG, BASE_INCOME_TAG}) do
						for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
							if tagged.Parent and not tagged:GetAttribute("Fainted") then
								local ownerId = tagged:GetAttribute("OwnerUserId")
								if ownerId and ownerId ~= player.UserId and getDistanceToModel(bodyPart.Position, tagged) <= GameConfig.CompanionAttackRange then
									hasAttackTargetInRange = true; break
								end
							end
						end
						if hasAttackTargetInRange then break end
					end
				end
			end

			-- Idle delay: if model hasn't moved for 2 seconds, prefer Idle over Move
			local posDelta = (bodyPart.Position - (comp.lastAnimPos or bodyPart.Position)).Magnitude
			if posDelta > 0.3 then
				comp.lastAnimPos = bodyPart.Position
				comp.lastAnimPosTime = tick()
			end
			local idleDelay = 2
			local stationaryFor2s = (tick() - (comp.lastAnimPosTime or tick())) >= idleDelay

			local prevAnim = comp.lastAnimType or "Idle"
			local animType
			if hasAttackTargetInRange then
				animType = "Attack"
			elseif dist > 1 and not stationaryFor2s then
				animType = "Move"
			elseif dist < 0.6 or stationaryFor2s then
				animType = "Idle"
			else
				animType = prevAnim
			end
			-- FIX #20: Water types: use Swimming when moving in any water volume (Ocean or WaterBlock), Move when on land
			if isWaterFollowing and animType == "Move" then
				animType = "Swimming"
			end
			comp.lastAnimType = animType
			if animType == "Attack" then
				local attackSpeed = (stats and stats.speed) and math.clamp(stats.speed / 10, 0.5, 2) or 1
				CreatureAnimation.PlayAnimation(model, animType, creatureId, { speed = attackSpeed })
			else
				CreatureAnimation.PlayAnimation(model, animType, creatureId)
			end

			-- Face toward target: attack target if in range, else player
			local faceToward = root.Position
			if comp.attackMode and not comp.carrying then
				local attackTarget = nil
				if comp.targetModel and comp.targetModel.Parent and not comp.targetModel:GetAttribute("Fainted") then
					local ok, distResult = pcall(function() return getDistanceToModel(newPos, comp.targetModel) end)
					if not ok then
						comp.targetModel = nil
					elseif distResult <= GameConfig.CompanionAttackRange * 1.2 then
						attackTarget = comp.targetModel
					end
				end
				if not attackTarget then
					local nearDist = GameConfig.CompanionAttackRange * 1.2
					for _, tagged in ipairs(CollectionService:GetTagged(WORLD_CREATURE_TAG)) do
						if tagged.Parent and not tagged:GetAttribute("Fainted") and not CollectionService:HasTag(tagged, "ArenaCreature") then
							local d2 = getDistanceToModel(newPos, tagged)
							if d2 < nearDist then nearDist = d2; attackTarget = tagged end
						end
					end
					if not attackTarget then
						for _, tag in ipairs({BASE_DEFENSE_TAG, BASE_INCOME_TAG}) do
							for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
								if tagged.Parent and not tagged:GetAttribute("Fainted") then
									local ownerId = tagged:GetAttribute("OwnerUserId")
									if ownerId and ownerId ~= player.UserId then
										local d2 = getDistanceToModel(newPos, tagged)
										if d2 < nearDist then nearDist = d2; attackTarget = tagged end
									end
								end
							end
							if attackTarget then break end
						end
					end
				end
				if attackTarget then
					local tp = attackTarget.PrimaryPart or CreatureModelLoader.GetBodyPart(attackTarget) or attackTarget:FindFirstChild("Body") or attackTarget:FindFirstChild("HumanoidRootPart")
					if tp then faceToward = tp.Position end
				end
			end
			-- Block movement through walls: raycast path; if blocked, stop at obstruction
			local toNew = newPos - currentPos
			local moveDist = toNew.Magnitude
			if moveDist > 0.01 then
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = getCreatureExcludeList({ character, comp.model })
				local rayDir = toNew.Unit
				local bodyRadius = math.max(bodyPart.Size.X, bodyPart.Size.Y, bodyPart.Size.Z) * 0.5
				local hit = Workspace:Raycast(currentPos, rayDir * (moveDist + bodyRadius * 0.5), rayParams)
				if hit and hit.Distance < moveDist + 0.1 then
					newPos = hit.Position - hit.Normal * (bodyRadius + 0.2)
					if not isWaterFollowing then
						local groundYHere = getGroundY(Vector3.new(newPos.X, newPos.Y + 2, newPos.Z), { character, comp.model })
						local heightHere = CreatureData.IsFlying(creatureId) and (GameConfig.FlyingHoverHeight or 5) or getBodyHeightAboveBboxBottom(model, bodyPart)
						newPos = Vector3.new(newPos.X, groundYHere + heightHere, newPos.Z)
					end
				end
			end
			-- Move entire model with PivotTo first (so body ends up at newPos; core/ring stay in sync). Water swimming: face in 3D.
			local rotOffset = getCompanionRotationOffset(comp.creatureId, animType == "Move" or animType == "Swimming", comp.model)
			local pivot = model:GetPivot()
			local bodyOffsetInPivot = pivot:PointToObjectSpace(bodyPart.Position)
			local lookAtPos = isWaterFollowing and faceToward or Vector3.new(faceToward.X, newPos.Y, faceToward.Z)
			local dir = lookAtPos - newPos
			if not isWaterFollowing then dir = dir * Vector3.new(1, 0, 1) end
			local rotCf = (dir.Magnitude > 0.5)
				and (CFrame.lookAt(newPos, lookAtPos) * rotOffset)
				or (CFrame.new(newPos) * rotOffset)
			local pivotPos = newPos - rotCf:VectorToWorldSpace(bodyOffsetInPivot)
			model:PivotTo(CFrame.new(pivotPos) * (rotCf - rotCf.Position))

			-- FIX #15b: Guard against PivotTo position drift on rotation transitions (crawl ↔ upright).
			-- When rotOffset changes between frames (e.g. Idle→Move for crawling creatures), the
			-- bodyOffsetInPivot was computed from the OLD rotation but transformed with the NEW rotation,
			-- which can displace the body far from newPos. Detect drift and re-PivotTo using the
			-- NOW-correct pivot relationship (post-rotation offset matches the applied rotation).
			local postPivotPos = bodyPart.Position
			local pivotDrift = (postPivotPos - newPos).Magnitude
			if pivotDrift > 3 then
				-- Re-derive offset from the already-rotated model (pivot and body are now consistent)
				local freshPivot = model:GetPivot()
				local freshOffset = freshPivot:PointToObjectSpace(postPivotPos)
				local correctedPivotPos = newPos - (rotCf - rotCf.Position):VectorToWorldSpace(freshOffset)
				model:PivotTo(CFrame.new(correctedPivotPos) * (rotCf - rotCf.Position))
			end

			-- Visual flair after PivotTo (use bodyPart position so core/ring don't double-move)
			local pos = bodyPart.Position
			if core and core.Parent then core.Position = pos; core.Transparency = 0.2 + math.sin(t * 3) * 0.1 end
			if ring and ring.Parent then ring.CFrame = CFrame.new(pos) * CFrame.Angles(math.sin(t) * 0.3, t * 1.5, math.cos(t) * 0.3) end
			if comp.carrying and comp.carrying.visualModel and comp.carrying.visualModel.Parent then
				comp.carrying.visualModel.Position = pos + Vector3.new(0, -2.5, 0)
			end

			-- "Arrived home" check ? if carrying and near own plot center, deliver
			if comp.carrying then
				local d = PlayerDataManager.GetData(player)
				if d and d.plotId and d.plotId > 0 then
					local plotsFolder = workspace:FindFirstChild("BasePlots")
					if plotsFolder then
						local plotModel = plotsFolder:FindFirstChild("Plot" .. d.plotId) or plotsFolder:FindFirstChild("Part" .. d.plotId)
						local plotCenter = plotModel and plotModel:FindFirstChild("PlotCenter")
						if plotCenter then
							local homeDist = (root.Position - plotCenter.Position).Magnitude
							if homeDist < (GameConfig.StealHomeRadius or 30) then
								deliverStolenCreature(player, comp)
							end
						end
					end
				end
			end

			updateCompanionHPBar(comp)

			-- Check for player death while carrying
			if comp.carrying then
				local hum = character:FindFirstChild("Humanoid")
				if hum and hum.Health <= 0 then
					dropStolenCreature(player, comp)
				end
			end

			if comp.attackMode and not comp.carrying and tick() - lastAttackTime >= GameConfig.CompanionAttackCD then
				local targetCreature = nil
				if comp.targetModel and comp.targetModel.Parent and not comp.targetModel:GetAttribute("Fainted") then
					if getDistanceToModel(bodyPart.Position, comp.targetModel) <= GameConfig.CompanionAttackRange then
						targetCreature = comp.targetModel
					end
				end
				if not targetCreature then
					local nearest, nearDist = nil, GameConfig.CompanionAttackRange
					-- Scan world creatures (use bbox so tall creatures are in range when companion is underneath)
					for _, tagged in ipairs(CollectionService:GetTagged(WORLD_CREATURE_TAG)) do
						if tagged.Parent and not tagged:GetAttribute("Fainted")
							and not CollectionService:HasTag(tagged, "ArenaCreature") then
							local d2 = getDistanceToModel(bodyPart.Position, tagged)
							if d2 < nearDist then nearDist = d2; nearest = tagged end
						end
					end
					-- Also scan other players' base creatures (defense + income)
					if not nearest then
						for _, tag in ipairs({BASE_DEFENSE_TAG, BASE_INCOME_TAG}) do
							for _, tagged in ipairs(CollectionService:GetTagged(tag)) do
								if tagged.Parent and not tagged:GetAttribute("Fainted") then
									local ownerId = tagged:GetAttribute("OwnerUserId")
									-- Don't attack your own base creatures
									if ownerId and ownerId ~= player.UserId then
										local d2 = getDistanceToModel(bodyPart.Position, tagged)
										if d2 < nearDist then nearDist = d2; nearest = tagged end
									end
								end
							end
							if nearest then break end
						end
					end
					targetCreature = nearest
				end
				if targetCreature then
					local tp = targetCreature.PrimaryPart or CreatureModelLoader.GetBodyPart(targetCreature) or targetCreature:FindFirstChild("Body")
					if tp then
						lastAttackTime = tick()
						-- Attack animation already set in animation section above (hasAttackTargetInRange)
						-- Elemental weakness: companion (attacker) vs target (defender)
						local defenderCid = targetCreature:GetAttribute("CreatureId")
						local defenderInfo = defenderCid and CreatureData.GetById(defenderCid)
						local elemMult = CreatureData.GetElementalDamageMultiplier(info.element, defenderInfo and defenderInfo.element)
						if elemMult > 1 then
							elemMult = GameConfig.ElementalAdvantageMultiplier or elemMult
						elseif elemMult < 1 then
							elemMult = GameConfig.ElementalDisadvantageMultiplier or elemMult
						end
						local finalDamage = math.floor(math.max(1, baseDamage * elemMult))
						createAttackEffect(bodyPart.Position, tp.Position, attackColor)
						fireDamageNumberToPlayer(player, tp.Position, finalDamage)
						-- Route through CreatureAI first (authoritative HP system)
						if CreatureAI and CreatureAI.DamageCreature then
							CreatureAI.DamageCreature(targetCreature, finalDamage, model)
						elseif WorldCreatureHP then
							WorldCreatureHP.DamageCreature(targetCreature, finalDamage, model)
						end
						-- Steal: player must walk up and press E to pick up fainted base creature (no companion auto-pickup)
					end
				end
			end

			local bbGui = model:FindFirstChild("CompanionTag")
			if bbGui then
				local ml = bbGui:FindFirstChild("ModeLbl")
				if ml then
					if comp.carrying then
						local cInfo = CreatureData.GetById(comp.carrying.creatureId)
						ml.Text = "CARRYING " .. (cInfo and cInfo.displayName or "creature")
						ml.TextColor3 = Color3.fromRGB(255, 255, 100)
					elseif comp.attackMode then
						ml.Text = "ATTACK MODE"; ml.TextColor3 = Color3.fromRGB(255, 100, 60)
					else
						ml.Text = "PASSIVE MODE"; ml.TextColor3 = Color3.fromRGB(100, 200, 255)
					end
					if not comp.carrying and comp.targetModel and comp.targetModel.Parent then
						local tid = comp.targetModel:GetAttribute("CreatureId")
						local tinfo = tid and CreatureData.GetById(tid)
						ml.Text = ml.Text .. " > " .. (tinfo and tinfo.displayName or "target")
					end
				end
			end
		end
	end)
end

-- -- PUBLIC API --

function FavoriteCreatureSystem.IsPvPFainted(player)
	return pvpFaintedPlayers[player.UserId] == true
end

function FavoriteCreatureSystem.SetPvPFainted(player, value)
	if value then
		pvpFaintedPlayers[player.UserId] = true
	else
		pvpFaintedPlayers[player.UserId] = nil
	end
end

function FavoriteCreatureSystem.SpawnCompanion(player)
	local userId = player.UserId
	if player:GetAttribute("InBadlands") then return end
	-- Don't spawn companion while player is mounted (mount and companion are mutually exclusive)
	if player:GetAttribute("IsMounted") == true then return end
	if spawnLocks[userId] then return end -- prevent double spawn (e.g. SetFavorite + CharacterAdded)
	spawnLocks[userId] = true
	FavoriteCreatureSystem.DespawnCompanion(player)
	-- Clean up any stale fainted companion reference (legacy; companion now destroyed on faint)
	local fainted = faintedCompanionModels[userId]
	if fainted and fainted.Parent then
		fainted:Destroy()
	end
	faintedCompanionModels[userId] = nil
	if pvpFaintedPlayers[userId] then spawnLocks[userId] = nil; return end -- PvP fainted: must revive via prompt
	local cd = respawnCooldowns[userId]
	if cd and (tick() - cd) < GameConfig.CompanionRespawnCD then spawnLocks[userId] = nil; return end
	respawnCooldowns[userId] = nil

	local entry = PlayerDataManager.GetFavorite(player)
	if not entry then spawnLocks[userId] = nil; return end
	local character = player.Character
	if not character then character = player.CharacterAdded:Wait(); task.wait(1) end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then spawnLocks[userId] = nil; return end
	local info = CreatureData.GetById(entry.id)
	if not info then spawnLocks[userId] = nil; return end

	-- Don't spawn non-water companion if player is in water (e.g. respawned in water or swimming)
	if isPlayerInWater(player) and not CreatureData.IsWaterType(entry.id) then
		companionRecalledDueToWater[userId] = true
		spawnLocks[userId] = nil
		return
	end

	-- FIX #20 + FIX #26: Check Ocean, WaterBlock, AND Roblox terrain swimming for water companion spawn
	local isPlayerInOceanSpawn = CreatureAI and CreatureAI.IsPositionInOcean and CreatureAI.IsPositionInOcean(root.Position)
	local isPlayerInWaterBlockSpawn = isPositionInWaterBlock(root.Position)
	-- FIX #26: Also detect terrain water via Humanoid Swimming state
	local spawnHumanoid = character:FindFirstChildOfClass("Humanoid")
	if not isPlayerInOceanSpawn and not isPlayerInWaterBlockSpawn and spawnHumanoid
		and spawnHumanoid:GetState() == Enum.HumanoidStateType.Swimming then
		isPlayerInWaterBlockSpawn = true  -- treat terrain water as WaterBlock for spawn logic
	end
	local model = createCompanionModel(entry.id, player, entry)
	if not model then spawnLocks[userId] = nil; return end
	-- Spawn behind player. Water + in water volume: 3D behind, clamped to volume bounds; else ground/flying height
	local bodyPart = model.PrimaryPart or CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
	local spawnPos
	if (isPlayerInOceanSpawn or isPlayerInWaterBlockSpawn) and CreatureData.IsWaterType(entry.id) then
		local behind = root.Position - root.CFrame.LookVector * GameConfig.CompanionFollowDist
		local maxY = root.Position.Y + (GameConfig.WaterCompanionMaxSurfaceOffset or 1.5)
		-- Get the water volume part (Ocean or WaterBlock) for Y-clamping
		local waterPart = nil
		if isPlayerInOceanSpawn then
			waterPart = CreatureAI and CreatureAI.GetOceanPart and CreatureAI.GetOceanPart()
		end
		if not waterPart and isPlayerInWaterBlockSpawn then
			waterPart = getWaterBlockContaining(root.Position)
		end
		if waterPart then
			local topY = waterPart.Position.Y + waterPart.Size.Y * 0.5
			local bottomY = waterPart.Position.Y - waterPart.Size.Y * 0.5
			maxY = math.min(maxY, topY)
			behind = Vector3.new(behind.X, math.clamp(behind.Y, bottomY, topY), behind.Z)
		end
		spawnPos = Vector3.new(behind.X, math.min(behind.Y, maxY), behind.Z)
	else
		local followXZ = root.Position + root.CFrame.LookVector * -GameConfig.CompanionFollowDist
		local groundY = getGroundY(Vector3.new(followXZ.X, root.Position.Y, followXZ.Z), { character })
		local desiredY = CreatureData.IsFlying(entry.id)
			and (groundY + (GameConfig.FlyingHoverHeight or 5))
			or (groundY + (bodyPart and getBodyHeightAboveBboxBottom(model, bodyPart) or 1.75))
		spawnPos = Vector3.new(followXZ.X, desiredY, followXZ.Z)
	end
	-- Use PivotTo for initial position (same as behavior loop) so model pivot and body stay in sync from frame 1
	local pivot = model:GetPivot()
	local bodyOffsetInPivot = pivot:PointToObjectSpace((bodyPart or model.PrimaryPart).Position)
	local rotOffset = getCompanionRotationOffset(entry.id, false, model)
	local targetFlat = Vector3.new(root.Position.X, spawnPos.Y, root.Position.Z)
	local dir = (targetFlat - spawnPos) * Vector3.new(1, 0, 1)
	local rotCf = (dir.Magnitude > 0.5)
		and (CFrame.lookAt(spawnPos, targetFlat) * rotOffset)
		or (CFrame.new(spawnPos) * rotOffset)
	local pivotPos = spawnPos - rotCf:VectorToWorldSpace(bodyOffsetInPivot)
	model:PivotTo(CFrame.new(pivotPos) * (rotCf - rotCf.Position))

	-- Level- and variant-scaled HP (Silver/Gold/Legend get higher stats)
	local lvl = entry.level or 1
	local xp = entry.xp or 0
	local variant = entry.variant or "Normal"
	local stats = PlayerDataManager.GetEffectiveStats(entry.id, lvl, variant, player)
	local scaledHP = stats and stats.health or math.floor(info.health * (1 + GameConfig.StatGainPerLevel * (lvl - 1)))

	-- Update billboard to show level and XP
	local bb = model:FindFirstChild("CompanionTag")
	if bb then
		local maxLvl = CreatureData.GetMaxCreatureLevel and CreatureData.GetMaxCreatureLevel(entry.id) or (GameConfig.MaxCreatureLevel or 10)
		local nameLbl = bb:FindFirstChildWhichIsA("TextLabel")
		if nameLbl then
			local lvlText = lvl >= maxLvl and " [MAX]" or (" Lv." .. lvl)
			local variantSuffix = variant ~= "Normal" and (variant and (" · " .. variant) or "") or ""
			nameLbl.Text = info.displayName .. variantSuffix .. lvlText
		end

		-- Add XP bar below HP bar
		local xpBg = Instance.new("Frame")
		xpBg.Name = "XPBar"; xpBg.Size = UDim2.new(0.8, 0, 0, 4)
		xpBg.Position = UDim2.new(0.1, 0, 0, 56); xpBg.BackgroundColor3 = Color3.fromRGB(20, 20, 50)
		xpBg.BorderSizePixel = 0; xpBg.Parent = bb
		Instance.new("UICorner", xpBg).CornerRadius = UDim.new(0, 2)

		local xpFill = Instance.new("Frame")
		xpFill.Name = "Fill"
		local xpNeeded = PlayerDataManager.XPForLevel(lvl + 1)
		local xpPct = (lvl >= maxLvl) and 1 or (xpNeeded > 0 and math.min(1, xp / xpNeeded) or 0)
		xpFill.Size = UDim2.new(xpPct, 0, 1, 0)
		xpFill.BackgroundColor3 = Color3.fromRGB(80, 160, 255); xpFill.BorderSizePixel = 0
		xpFill.Parent = xpBg
		Instance.new("UICorner", xpFill).CornerRadius = UDim.new(0, 2)

		local xpLbl = Instance.new("TextLabel")
		xpLbl.Name = "XPLbl"; xpLbl.Size = UDim2.new(1, 0, 0, 9)
		xpLbl.Position = UDim2.new(0, 0, 0, 61); xpLbl.BackgroundTransparency = 1
		xpLbl.Text = (lvl >= maxLvl) and "MAX LEVEL" or ("XP: " .. xp .. "/" .. xpNeeded)
		xpLbl.TextColor3 = Color3.fromRGB(120, 160, 220)
		xpLbl.Font = Enum.Font.GothamMedium; xpLbl.TextSize = 8; xpLbl.Parent = bb

		-- Expand billboard to fit XP bar
		bb.Size = UDim2.new(0, 160, 0, 72)
	end

	activeCompanions[player.UserId] = {
		model = model, creatureId = entry.id, uid = entry.uid,
		variant = entry.variant,
		attackMode = false, targetModel = nil,  -- passive by default; attack only when target selected
		hp = scaledHP, maxHp = scaledHP, alive = true,
		carrying = nil,
		lastAnimPos = spawnPos,
		lastAnimPosTime = tick(),
	}
	startCompanionBehavior(player, model, entry.id)

	local evt = getCompanionSpawnedEvent()
	if evt then evt:FireClient(player, model) end
	spawnLocks[userId] = nil
end

function FavoriteCreatureSystem.DespawnCompanion(player)
	local userId = player.UserId
	local c = activeCompanions[userId]
	if c then
		if c._waterRecallConn then
			c._waterRecallConn:Disconnect()
			c._waterRecallConn = nil
		end
		-- Drop stolen creature if carrying
		if c.carrying then
			dropStolenCreature(player, c)
		end
		if c.model and c.model.Parent then c.model:Destroy() end
		activeCompanions[userId] = nil
	end
	-- Destroy ALL FavoriteCreature models for this player (fixes leftover/duplicate models when carding or double spawn)
	local uidStr = tostring(userId)
	for _, model in ipairs(CollectionService:GetTagged(FAVORITE_TAG)) do
		if model.Parent and tostring(model:GetAttribute("OwnerUserId") or "") == uidStr then
			model:Destroy()
		end
	end
end

function FavoriteCreatureSystem.HasCompanion(player)
	local c = activeCompanions[player.UserId]; return c ~= nil and c.alive
end

-- Returns companion position (for evolution effects etc.) or nil if no companion
function FavoriteCreatureSystem.GetCompanionPosition(player)
	local c = activeCompanions[player.UserId]
	if not c or not c.alive or not c.model or not c.model.Parent then return nil end
	local body = CreatureModelLoader.GetBodyPart(c.model) or c.model:FindFirstChild("Body") or c.model.PrimaryPart
	if body then return body.Position end
	return c.model:GetPivot().Position
end

-- Teleport companion to behind the player at their current position (used when player recalls home)
function FavoriteCreatureSystem.TeleportCompanionWithPlayer(player)
	local c = activeCompanions[player.UserId]
	if not c or not c.alive or not c.model or not c.model.Parent then return end
	local character = player.Character
	if not character then return end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local entry = PlayerDataManager.GetFavorite(player)
	if not entry then return end
	local isPlayerInOceanTeleport = CreatureAI and CreatureAI.IsPositionInOcean and CreatureAI.IsPositionInOcean(root.Position)
	local bodyPart = c.model.PrimaryPart or CreatureModelLoader.GetBodyPart(c.model) or c.model:FindFirstChild("Body")
	local spawnPos
	if isPlayerInOceanTeleport and CreatureData.IsWaterType(entry.id) then
		local behind = root.Position - root.CFrame.LookVector * GameConfig.CompanionFollowDist
		local maxY = root.Position.Y + (GameConfig.WaterCompanionMaxSurfaceOffset or 1.5)
		local ocean = CreatureAI and CreatureAI.GetOceanPart and CreatureAI.GetOceanPart()
		if ocean then
			local topY = ocean.Position.Y + ocean.Size.Y * 0.5
			local bottomY = ocean.Position.Y - ocean.Size.Y * 0.5
			maxY = math.min(maxY, topY)
			behind = Vector3.new(behind.X, math.clamp(behind.Y, bottomY, topY), behind.Z)
		end
		spawnPos = Vector3.new(behind.X, math.min(behind.Y, maxY), behind.Z)
	else
		local followXZ = root.Position + root.CFrame.LookVector * -GameConfig.CompanionFollowDist
		local groundY = getGroundY(Vector3.new(followXZ.X, root.Position.Y, followXZ.Z), { character })
		local desiredY = CreatureData.IsFlying(entry.id)
			and (groundY + (GameConfig.FlyingHoverHeight or 5))
			or (groundY + (bodyPart and getBodyHeightAboveBboxBottom(c.model, bodyPart) or 1.75))
		spawnPos = Vector3.new(followXZ.X, desiredY, followXZ.Z)
	end
	local pivot = c.model:GetPivot()
	local bodyOffsetInPivot = pivot:PointToObjectSpace((bodyPart or c.model.PrimaryPart).Position)
	local rotOffset = getCompanionRotationOffset(entry.id, false, c.model)
	local lookTarget = (isPlayerInOceanTeleport and CreatureData.IsWaterType(entry.id)) and root.Position or Vector3.new(root.Position.X, spawnPos.Y, root.Position.Z)
	local dir = lookTarget - spawnPos
	if not (isPlayerInOceanTeleport and CreatureData.IsWaterType(entry.id)) then dir = dir * Vector3.new(1, 0, 1) end
	local rotCf = (dir.Magnitude > 0.5)
		and (CFrame.lookAt(spawnPos, lookTarget) * rotOffset)
		or (CFrame.new(spawnPos) * rotOffset)
	local pivotPos = spawnPos - rotCf:VectorToWorldSpace(bodyOffsetInPivot)
	c.model:PivotTo(CFrame.new(pivotPos) * (rotCf - rotCf.Position))
	c.lastAnimPos = spawnPos
	c.lastAnimPosTime = tick()
end

-- Used by CreatureAI: returns true only if model is a companion and its owner has it alive
function FavoriteCreatureSystem.IsCompanionAlive(model)
	if not model or not model.Parent then return false end
	local ownerId = model:GetAttribute("OwnerUserId")
	if not ownerId then return false end
	local comp = activeCompanions[ownerId]
	return comp and comp.alive and comp.model == model
end

function FavoriteCreatureSystem.IsOnCooldown(player)
	local cd = respawnCooldowns[player.UserId]
	return cd and (tick() - cd) < GameConfig.CompanionRespawnCD
end

function FavoriteCreatureSystem.ToggleAttackMode(player)
	local c = activeCompanions[player.UserId]
	if c then
		c.attackMode = not c.attackMode
		-- When switching to passive, clear target so companion resumes following instead of staying stuck
		if not c.attackMode then
			c.targetModel = nil
			c.lastAnimPos = nil
			c.lastAnimPosTime = nil
		end
		return c.attackMode
	end
	-- No companion: if player has favorite and can spawn, respawn so T acts as reset
	if not pvpFaintedPlayers[player.UserId] then
		local cd = respawnCooldowns[player.UserId]
		if not cd or (tick() - cd) >= GameConfig.CompanionRespawnCD then
			local entry = PlayerDataManager.GetFavorite(player)
			if entry then
				FavoriteCreatureSystem.SpawnCompanion(player)
				return true
			end
		end
	end
	return false
end

function FavoriteCreatureSystem.SetTarget(player, creatureModel)
	local uid = player.UserId
	-- Track world combat target for despawn protection (PlayerCombatClient + target menu)
	if creatureModel and creatureModel.Parent and CollectionService:HasTag(creatureModel, WORLD_CREATURE_TAG) then
		worldCombatTargetByUserId[uid] = creatureModel
	else
		worldCombatTargetByUserId[uid] = nil
	end

	local c = activeCompanions[uid]
	if c and creatureModel and creatureModel.Parent then
		-- Allow targeting world creatures OR base creatures (for stealing)
		local isWorld = CollectionService:HasTag(creatureModel, WORLD_CREATURE_TAG)
		local isBase = CollectionService:HasTag(creatureModel, BASE_DEFENSE_TAG)
			or CollectionService:HasTag(creatureModel, BASE_INCOME_TAG)
		if isWorld or isBase then
			c.targetModel = creatureModel
			c.attackMode = true  -- enable attack when target is set
			return true
		end
	end
	if c then c.targetModel = nil; c.attackMode = false end
	return false
end

function FavoriteCreatureSystem.IsWorldCreatureCombatTargeted(creatureModel)
	if not creatureModel or not creatureModel.Parent then return false end
	for uid, m in pairs(worldCombatTargetByUserId) do
		if not m or not m.Parent then
			worldCombatTargetByUserId[uid] = nil
		elseif m == creatureModel then
			return true
		end
	end
	for _, comp in pairs(activeCompanions) do
		local tm = comp.targetModel
		if tm and tm.Parent and tm == creatureModel then return true end
	end
	return false
end

function FavoriteCreatureSystem.ClearTarget(player)
	worldCombatTargetByUserId[player.UserId] = nil
	local c = activeCompanions[player.UserId]
	if c then
		c.targetModel = nil
		c.attackMode = false  -- passive when no target
		c.lastAnimPos = nil
		c.lastAnimPosTime = nil
	end
end

-- -- INIT --

function FavoriteCreatureSystem.Init(playerDataMgr, creatureSpawnerRef, creatureAIRef)
	PlayerDataManager = playerDataMgr; CreatureSpawner = creatureSpawnerRef; CreatureAI = creatureAIRef
	FavoriteCreatureSystem.OnCompanionFainted = Instance.new("BindableEvent")

	-- Load BasePlacementSystem for steal mechanic (refresh victim's base)
	pcall(function() BasePlacementSystem = require(ServerScriptService.BasePlacementSystem) end)
	if BasePlacementSystem and BasePlacementSystem.RegisterCompanionFaintForDefenseXP then
		BasePlacementSystem.RegisterCompanionFaintForDefenseXP(FavoriteCreatureSystem)
	end

	-- Load WorldCreatureHP now (MainServer has already required it)
	pcall(function() WorldCreatureHP = require(ServerScriptService.WorldCreatureHP) end)
	if not WorldCreatureHP then
		warn("[FavoriteCreatureSystem] WorldCreatureHP not found - companion attacks won't damage creatures!")
	end

	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function()
			task.wait(2)
			if activeCompanions[player.UserId] then
				FavoriteCreatureSystem.SpawnCompanion(player)
			else
				local entry = PlayerDataManager.GetFavorite(player)
				if entry and not FavoriteCreatureSystem.IsOnCooldown(player) then
					FavoriteCreatureSystem.SpawnCompanion(player)
				end
			end
		end)
	end)

	-- Players already in game when Init runs: spawn companion once if they already have a character.
	-- (CharacterAdded handles spawn when character loads; avoid duplicate spawn from old 3s-delay loop.)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			task.defer(function()
				local entry = PlayerDataManager.GetFavorite(p)
				if entry and not FavoriteCreatureSystem.IsOnCooldown(p) then
					FavoriteCreatureSystem.SpawnCompanion(p)
				end
			end)
		end
	end

	Players.PlayerRemoving:Connect(function(player)
		-- Drop player carry (steal): creature walks back to owner
		if playerCarryingSteal[player.UserId] then
			dropPlayerCarryAndWalkBack(player)
		end
		local c = activeCompanions[player.UserId]
		if c and c.carrying then
			dropStolenCreature(player, c)
		end
		FavoriteCreatureSystem.DespawnCompanion(player)
		respawnCooldowns[player.UserId] = nil
		playerCarryingSteal[player.UserId] = nil
		companionRecalledDueToWater[player.UserId] = nil
		spawnLocks[player.UserId] = nil
		worldCombatTargetByUserId[player.UserId] = nil
	end)

	-- E-interact to pick up fainted base creature (steal)
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local stealInteract = eventsFolder:FindFirstChild("StealInteractRequest")
		if not stealInteract or not stealInteract:IsA("RemoteEvent") then
			stealInteract = Instance.new("RemoteEvent")
			stealInteract.Name = "StealInteractRequest"
			stealInteract.Parent = eventsFolder
		end
		stealInteract.OnServerEvent:Connect(function(player, creatureModel)
			if not player or not creatureModel then return end
			local ok, msg = playerPickUpSteal(player, creatureModel)
			if not ok and msg then
				local n = getNotifEvent()
				if n then n:FireClient(player, msg) end
			end
		end)
	end

	-- PERFORMANCE: Single Heartbeat for companion respawn + carry visual (was 2 separate loops)
	RunService.Heartbeat:Connect(function()
		-- Respawn companion when player exits water (was recalled due to non-water type in water)
		for userId, _ in pairs(companionRecalledDueToWater) do
			local player = Players:GetPlayerByUserId(userId)
			if not player then
				companionRecalledDueToWater[userId] = nil
			else
				local inWater = isPlayerInWater(player)
				if not inWater then
					companionRecalledDueToWater[userId] = nil
					local entry = PlayerDataManager.GetFavorite(player)
					if entry and not FavoriteCreatureSystem.IsOnCooldown(player) then
						FavoriteCreatureSystem.SpawnCompanion(player)
					end
				end
			end
		end
		-- Update player carry visual, deliver at base, drop on death
		for userId, carry in pairs(playerCarryingSteal) do
			local player = Players:GetPlayerByUserId(userId)
			if not player then playerCarryingSteal[userId] = nil else
			local character = player.Character
			local root = character and character:FindFirstChild("HumanoidRootPart")
			if root then
			-- Update carry visual to follow player
			if carry.visualModel and carry.visualModel.Parent then
				carry.visualModel.Position = root.Position + Vector3.new(0, -2.5, 0)
			end
			-- Deliver at own base
			local d = PlayerDataManager.GetData(player)
			if d and d.plotId and d.plotId > 0 then
				local plotPos = getPlotCenterPosition(d.plotId)
				if plotPos and (root.Position - plotPos).Magnitude < (GameConfig.StealHomeRadius or 30) then
					deliverStolenCreatureForPlayer(player)
					break
				end
			end
			-- Drop on player death (walk back to owner)
			local hum = character:FindFirstChild("Humanoid")
			if hum and hum.Health <= 0 then
				dropPlayerCarryAndWalkBack(player)
				break
			end
			end
			end
		end
	end)

end

-- Exported so MountSystem can apply the same rotation to mounted creatures
FavoriteCreatureSystem.GetCompanionRotationOffset = getCompanionRotationOffset

return FavoriteCreatureSystem
