--[[
	MountSystem.lua
	ServerScriptService (ModuleScript)

	══════════════════════════════════════════════════════════════════════════
	MOUNT SYSTEM — Server-authoritative creature mounting
	══════════════════════════════════════════════════════════════════════════

	Allows players to ride their favorite creature as a mount.
	Mounting is mutually exclusive with the companion system — when the
	player mounts, the companion is despawned; on dismount it re-summons.

	The mount model is welded to the player's HumanoidRootPart with a
	CFrame offset. The player walks normally with modified WalkSpeed.
	Flying mounts use BodyPosition + BodyGyro for free-flight.

	MOUNT FLOW:
		1. Client fires MountRequest (from inventory "Mount" button)
		2. Server validates (CanMount), creates model, welds, sets speed
		3. Server fires MountStarted to client (creatureId, mountType, speed, bonuses)
		4. Client hides player legs, starts mount animation, enables fly input if needed

	DISMOUNT FLOW:
		1. Client fires DismountRequest -OR- server forces (death, leave, arena)
		2. Server destroys mount model, resets speed, fires MountEnded
		3. Companion re-summons after short delay

	SPEED FORMULA (ground):
		mountSpeed = PlayerWalkSpeed + (creatureSpeed / 10) * MountSpeedMultiplier + mountSpeedBonus
		Capped at MountMaxSpeed. Sprint = mountSpeed * MountSprintMultiplier.

	ELEMENTAL BONUSES (set as attributes on player, checked by other systems):
		MountLavaImmune, MountOxygenBypass, MountIceImmune, MountElectricImmune,
		MountFlight, MountSwimMount, MountGlideBonus

	DEPENDENCIES:
		PlayerDataManager — creature ownership validation, favorite UID
		FavoriteCreatureSystem — recall/resummon companion
		CreatureAI — (optional) not directly used but passed for future expansion
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(ReplicatedStorage.Modules.CreatureAnimation)

local MountSystem = {}

-- ══════════════════════════════════════════════════════════════════════════
-- STATE
-- ══════════════════════════════════════════════════════════════════════════

-- [userId] = { model, creatureId, uid, mountType, speed, bonuses, weld, bodyPos, bodyGyro }
local activeMounts = {}
-- [userId] = tick() of last dismount (cooldown enforcement)
local mountCooldowns = {}
-- [userId] = true if companion was active before mounting (re-summon on dismount)
local hadCompanionBeforeMount = {}

local MOUNT_TAG = "MountCreature"
local MOUNT_FLOOR_OFFSET = 0.3
local MOUNT_GROUND_RAY_HEIGHT = 12
local MOUNT_GROUND_RAY_LENGTH = 200

-- Dependencies (set in Init)
local PlayerDataManager
local FavoriteCreatureSystem
local CreatureAI

local function getMountBoundsY(model)
	local ok, bboxCf, bboxSize = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or not bboxCf or not bboxSize then return nil, nil end

	local half = bboxSize * 0.5
	local minY = math.huge
	local maxY = -math.huge
	for sx = -1, 1, 2 do
		for sy = -1, 1, 2 do
			for sz = -1, 1, 2 do
				local corner = bboxCf:PointToWorldSpace(Vector3.new(sx * half.X, sy * half.Y, sz * half.Z))
				if corner.Y < minY then minY = corner.Y end
				if corner.Y > maxY then maxY = corner.Y end
			end
		end
	end
	return minY, maxY
end

local function getGroundYAt(position, excludes)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludes or {}

	local rayOrigin = Vector3.new(position.X, position.Y + MOUNT_GROUND_RAY_HEIGHT, position.Z)
	local result = workspace:Raycast(rayOrigin, Vector3.new(0, -MOUNT_GROUND_RAY_LENGTH, 0), params)
	if result then
		return result.Position.Y
	end
	return position.Y
end

-- ══════════════════════════════════════════════════════════════════════════
-- SPEED COMPUTATION
-- ══════════════════════════════════════════════════════════════════════════

-- @param creatureId: string creature id
-- @param player Player|nil — when set, mount speed scales with pilot level (WorldStat_LevelMult)
-- @return number: base mount speed in studs/sec (before sprint multiplier)
function MountSystem.ComputeMountSpeed(creatureId, player)
	local info = CreatureData.GetById(creatureId)
	local lm = 1
	if player then
		local x = player:GetAttribute("WorldStat_LevelMult")
		if type(x) == "number" and x > 0 then
			lm = x
		end
	end
	if not info then
		return math.floor((GameConfig.PlayerWalkSpeed or 16) * lm)
	end

	local mountType = CreatureData.GetMountType(creatureId)
	if mountType == "Flying" then
		return math.floor((GameConfig.MountFlySpeed or 40) * lm)
	end
	if mountType == "Swimming" then
		return math.floor((GameConfig.MountSwimSpeed or 30) * lm)
	end

	-- Ground formula: base + (creatureSpeed/10) * multiplier + flat bonus
	local baseSpeed = (GameConfig.PlayerWalkSpeed or 16) * lm
	local creatureSpeed = info.speed or 5
	local multiplier = GameConfig.MountSpeedMultiplier or 20
	local bonus = CreatureData.GetMountSpeedBonus(creatureId)
	local total = baseSpeed + (creatureSpeed / 10) * multiplier + bonus
	local cap = (GameConfig.MountMaxSpeed or 60) * lm
	return math.min(total, cap)
end

-- ══════════════════════════════════════════════════════════════════════════
-- VALIDATION
-- ══════════════════════════════════════════════════════════════════════════

-- @param player: Player
-- @return bool, string (canMount, errorMessage)
function MountSystem.CanMount(player)
	if not GameConfig.MountEnabled then
		return false, "Mounting is disabled"
	end

	local userId = player.UserId

	-- Already mounted?
	if activeMounts[userId] then
		return false, "Already mounted"
	end

	-- Cooldown check
	local cdEnd = mountCooldowns[userId]
	if cdEnd and (tick() - cdEnd) < (GameConfig.MountCooldown or 3) then
		return false, "Mount on cooldown"
	end

	-- Player level check
	local data = PlayerDataManager and PlayerDataManager.GetData(player)
	if not data then return false, "No player data" end
	local minLevel = GameConfig.MountMinPlayerLevel or 10
	if (data.playerLevel or 1) < minLevel then
		return false, "Requires player level " .. minLevel
	end

	-- Must have a favorite creature set
	local favoriteUid = data.favoriteUid
	if not favoriteUid or favoriteUid == "" then
		return false, "No favorite creature set"
	end

	-- Get favorite creature entry from inventory
	local entry = PlayerDataManager.GetCreatureByUid(player, favoriteUid)
	if not entry then
		return false, "Favorite creature not in inventory"
	end

	-- Must be mountable
	if not CreatureData.IsMountable(entry.id) then
		return false, "This creature is not mountable"
	end

	-- Must have character
	local char = player.Character
	if not char then return false, "No character" end
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return false, "No HumanoidRootPart" end
	local hum = char:FindFirstChild("Humanoid")
	if not hum or hum.Health <= 0 then return false, "Player is dead" end

	-- Not in arena
	local arenaBattle = char:GetAttribute("ArenaBattleInProgress")
	if arenaBattle then return false, "Cannot mount during arena battle" end

	return true, nil
end

-- ══════════════════════════════════════════════════════════════════════════
-- MOUNT
-- ══════════════════════════════════════════════════════════════════════════

-- @param player: Player
-- @return bool success
function MountSystem.Mount(player)
	local canMount, err = MountSystem.CanMount(player)
	if not canMount then
		warn("[MountSystem] Cannot mount:", err)
		return false
	end

	local userId = player.UserId
	local data = PlayerDataManager.GetData(player)
	local entry = PlayerDataManager.GetCreatureByUid(player, data.favoriteUid)
	local creatureId = entry.id
	local char = player.Character
	local root = char:FindFirstChild("HumanoidRootPart")
	local hum = char:FindFirstChild("Humanoid")

	-- ── Recall companion ──
	local wasCompanionActive = false
	if FavoriteCreatureSystem and FavoriteCreatureSystem.HasCompanion then
		wasCompanionActive = FavoriteCreatureSystem.HasCompanion(player)
		if wasCompanionActive and FavoriteCreatureSystem.DespawnCompanion then
			FavoriteCreatureSystem.DespawnCompanion(player)
		end
	end
	hadCompanionBeforeMount[userId] = wasCompanionActive

	-- ── Create mount model (same display as companion / favorite) ──
	local info = CreatureData.GetById(creatureId)
	local mountScale = CreatureData.GetMountScale(creatureId)
	-- Companion uses targetSize=3.5; mount scales up from that base
	local mountTargetSize = 3.5 * mountScale

	local mountModel = Instance.new("Model")
	mountModel.Name = "Mount_" .. creatureId .. "_" .. userId

	-- Load using same method as companion (CreatureModelLoader.LoadAndIntegrate)
	local loadOpts = { targetSize = mountTargetSize, creatureId = creatureId }
	local body, core, isCustomModel = CreatureModelLoader.LoadAndIntegrate(
		mountModel, info.modelName, info.displayName, nil, loadOpts
	)

	-- Fallback: placeholder sphere if model load fails
	if not isCustomModel then
		body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(6, 6, 6) * mountScale
		body.BrickColor = BrickColor.new("Bright orange")
		body.Material = Enum.Material.SmoothPlastic
		body.Anchored = false
		body.CanCollide = false
		body.Parent = mountModel
		mountModel.PrimaryPart = body
	end

	-- Configure mount model tags/attributes
	CollectionService:AddTag(mountModel, MOUNT_TAG)
	mountModel:SetAttribute("OwnerUserId", userId)
	mountModel:SetAttribute("CreatureId", creatureId)

	-- Make all parts non-collidable, unanchored, massless (player Humanoid drives movement)
	for _, part in ipairs(mountModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
			part.CanCollide = false
			part.Massless = true
		end
	end

	-- Find mount body (primary part)
	local mountBody = mountModel.PrimaryPart
		or CreatureModelLoader.GetBodyPart(mountModel)
		or mountModel:FindFirstChild("Body")
	if not mountBody then
		for _, p in ipairs(mountModel:GetDescendants()) do
			if p:IsA("BasePart") then mountBody = p; break end
		end
	end
	if not mountBody then
		warn("[MountSystem] No body part found for mount model:", creatureId)
		mountModel:Destroy()
		return false
	end

	-- ── Apply companion rotation (same visual as favorite companion) ──
	-- Uses the exported rotation function from FavoriteCreatureSystem so the
	-- mounted creature faces/orients exactly like the companion does at idle.
	local rotOffset = CFrame.identity
	if FavoriteCreatureSystem and FavoriteCreatureSystem.GetCompanionRotationOffset then
		rotOffset = FavoriteCreatureSystem.GetCompanionRotationOffset(creatureId, false, mountModel)
	end

	-- Align the mount to the rider's current facing so it moves forward with the player.
	local riderFacing = CFrame.lookAt(root.Position, root.Position + root.CFrame.LookVector)
	mountModel:PivotTo(riderFacing * rotOffset)
	mountModel.Parent = workspace

	-- ── Raise player to sit on top of mount ──
	-- Get bounding box to find mount model height, then move player root up
	-- so they sit at the top of the creature.
	local originalHipHeight = hum.HipHeight
	local groundY = getGroundYAt(root.Position, { char, mountModel })
	local mountBottomY, mountTopY = getMountBoundsY(mountModel)
	if mountBottomY then
		local floorLift = (groundY + MOUNT_FLOOR_OFFSET) - mountBottomY
		if math.abs(floorLift) > 0.001 then
			mountModel:PivotTo(mountModel:GetPivot() + Vector3.new(0, floorLift, 0))
			mountBottomY, mountTopY = getMountBoundsY(mountModel)
		end
	end

	local raiseY = 2 -- fallback
	if mountTopY then
		raiseY = math.max(0, mountTopY - root.Position.Y + 0.5)
	end
	root.CFrame = root.CFrame + Vector3.new(0, raiseY, 0)
	hum.HipHeight = math.max(0, originalHipHeight + raiseY)

	-- Create WeldConstraint: player root to mount body (captures current offset)
	local weld = Instance.new("WeldConstraint")
	weld.Name = "MountWeld"
	weld.Part0 = root
	weld.Part1 = mountBody
	weld.Parent = root

	-- ── Compute speed ──
	local mountSpeed = MountSystem.ComputeMountSpeed(creatureId, player)
	local mountType = CreatureData.GetMountType(creatureId)

	-- ── Set player attributes for elemental bonuses ──
	local bonuses = CreatureData.GetMountBonuses(creatureId)
	player:SetAttribute("IsMounted", true)
	player:SetAttribute("MountCreatureId", creatureId)
	player:SetAttribute("MountType", mountType)
	player:SetAttribute("MountSpeed", mountSpeed)

	for _, bonus in ipairs(bonuses) do
		player:SetAttribute("Mount_" .. bonus, true)
	end

	-- ── Apply speed ──
	local bodyPos, bodyGyro = nil, nil
	if mountType == "Flying" then
		-- Flying: use BodyPosition + BodyGyro for flight
		hum.WalkSpeed = mountSpeed
		-- BodyPosition for vertical control (client sends fly input via attribute)
		bodyPos = Instance.new("BodyPosition")
		bodyPos.MaxForce = Vector3.new(0, math.huge, 0)  -- vertical only
		bodyPos.D = 1250
		bodyPos.P = 10000
		bodyPos.Position = root.Position
		bodyPos.Parent = root

		bodyGyro = Instance.new("BodyGyro")
		bodyGyro.MaxTorque = Vector3.new(0, 0, 0)  -- don't restrict rotation
		bodyGyro.Parent = root
	else
		-- Ground/Swimming: just set WalkSpeed
		hum.WalkSpeed = mountSpeed
	end

	-- ── Compute mount shield ──
	-- Shield HP is based on creature's defense stat * multiplier
	local info2 = CreatureData.GetById(creatureId) -- re-use info if needed
	local creatureDefense = (info2 and info2.defense) or 10
	local shieldMultiplier = GameConfig.MountShieldMultiplier or 5
	local shieldMax = creatureDefense * shieldMultiplier
	player:SetAttribute("MountShieldCurrent", shieldMax)
	player:SetAttribute("MountShieldMax", shieldMax)

	-- ── Store state ──
	activeMounts[userId] = {
		model = mountModel,
		creatureId = creatureId,
		uid = data.favoriteUid,
		mountType = mountType,
		speed = mountSpeed,
		bonuses = bonuses,
		weld = weld,
		bodyPos = bodyPos,
		bodyGyro = bodyGyro,
		originalHipHeight = originalHipHeight,
		hipHeightDelta = raiseY,
		-- Shield state
		shieldCurrent = shieldMax,
		shieldMax = shieldMax,
		shieldBrokenAt = nil, -- tick() when shield was depleted (nil = shield active)
	}

	-- ── Setup animation and start Move ──
	-- Mount always plays Move animation while mounted (player is riding)
	CreatureAnimation.Setup(mountModel, creatureId, "Move")

	-- ── Notify client ──
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local mountStarted = eventsFolder:FindFirstChild("MountStarted")
		if mountStarted then
			mountStarted:FireClient(player, creatureId, mountType, mountSpeed, bonuses)
		end
	end

	print("[MountSystem] Player", player.Name, "mounted", creatureId, "(" .. mountType .. ") speed:", mountSpeed)
	return true
end

-- ══════════════════════════════════════════════════════════════════════════
-- DISMOUNT
-- ══════════════════════════════════════════════════════════════════════════

-- @param player: Player
-- @param forced: bool (true = death/leave, skip animation, no cooldown delay)
function MountSystem.Dismount(player, forced)
	local userId = player.UserId
	local mount = activeMounts[userId]
	if not mount then return end

	-- ── Remove weld ──
	if mount.weld and mount.weld.Parent then
		mount.weld:Destroy()
	end

	-- ── Remove flying body movers ──
	if mount.bodyPos and mount.bodyPos.Parent then
		mount.bodyPos:Destroy()
	end
	if mount.bodyGyro and mount.bodyGyro.Parent then
		mount.bodyGyro:Destroy()
	end

	-- ── Safe ground landing for flying mounts ──
	local char = player.Character
	if mount.mountType == "Flying" and char and not forced then
		local root = char:FindFirstChild("HumanoidRootPart")
		if root then
			-- Raycast down to find ground
			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			rayParams.FilterDescendantsInstances = { char, mount.model }
			local rayResult = workspace:Raycast(root.Position, Vector3.new(0, -500, 0), rayParams)
			if rayResult then
				local groundY = rayResult.Position.Y + 5 -- slight offset above ground
				root.CFrame = CFrame.new(root.Position.X, groundY, root.Position.Z)
					* (root.CFrame - root.CFrame.Position)
			end
		end
	end

	-- ── Destroy mount model ──
	if mount.model and mount.model.Parent then
		mount.model:Destroy()
	end
	-- Clean up any stray mount models (safety net)
	local uidStr = tostring(userId)
	for _, model in ipairs(CollectionService:GetTagged(MOUNT_TAG)) do
		if model.Parent and tostring(model:GetAttribute("OwnerUserId") or "") == uidStr then
			model:Destroy()
		end
	end

	-- ── Reset player speed ──
	if char then
		local hum = char:FindFirstChild("Humanoid")
		if hum then
			local scaled = player:GetAttribute("WorldStat_WalkSpeed")
			hum.WalkSpeed = (type(scaled) == "number" and scaled > 0) and scaled or (GameConfig.PlayerWalkSpeed or 16)
			if mount.originalHipHeight ~= nil then
				hum.HipHeight = mount.originalHipHeight
			end
		end
	end

	-- ── Clear elemental bonus attributes ──
	if mount.bonuses then
		for _, bonus in ipairs(mount.bonuses) do
			player:SetAttribute("Mount_" .. bonus, nil)
		end
	end
	player:SetAttribute("IsMounted", nil)
	player:SetAttribute("MountCreatureId", nil)
	player:SetAttribute("MountType", nil)
	player:SetAttribute("MountSpeed", nil)
	player:SetAttribute("MountFlyTargetY", nil)
	player:SetAttribute("MountShieldCurrent", nil)
	player:SetAttribute("MountShieldMax", nil)

	-- ── Clear state ──
	activeMounts[userId] = nil
	mountAnimState[userId] = nil
	mountCooldowns[userId] = tick()

	-- ── Notify client ──
	local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
	if eventsFolder then
		local mountEnded = eventsFolder:FindFirstChild("MountEnded")
		if mountEnded then
			mountEnded:FireClient(player)
		end
	end

	-- ── Re-summon companion ──
	if hadCompanionBeforeMount[userId] and FavoriteCreatureSystem then
		hadCompanionBeforeMount[userId] = nil
		task.delay(1.0, function()
			if not player or not player.Parent then return end
			if activeMounts[userId] then return end -- re-mounted
			local fav = PlayerDataManager and PlayerDataManager.GetFavorite(player)
			if fav and FavoriteCreatureSystem.SpawnCompanion then
				pcall(function() FavoriteCreatureSystem.SpawnCompanion(player) end)
			end
		end)
	else
		hadCompanionBeforeMount[userId] = nil
	end

	print("[MountSystem] Player", player.Name, "dismounted", forced and "(forced)" or "")
end

-- ══════════════════════════════════════════════════════════════════════════
-- QUERIES
-- ══════════════════════════════════════════════════════════════════════════

function MountSystem.IsMounted(player)
	return activeMounts[player.UserId] ~= nil
end

function MountSystem.GetMountModel(player)
	local m = activeMounts[player.UserId]
	return m and m.model
end

function MountSystem.GetMountInfo(player)
	return activeMounts[player.UserId]
end

-- ══════════════════════════════════════════════════════════════════════════
-- MOUNT ANIMATION UPDATE
-- ══════════════════════════════════════════════════════════════════════════
-- Keeps the mount model in Move animation while the player is moving.
-- Switches to Idle only when the player has been stationary for a short time.
-- Uses player HumanoidRootPart velocity to determine movement state.

-- [userId] = { lastAnim = "Move"|"Idle", lastMoveTime = tick() }
local mountAnimState = {}
local MOUNT_IDLE_DELAY = 0.5 -- seconds of no movement before switching to Idle

local function updateMountAnimations()
	for userId, mount in pairs(activeMounts) do
		if not mount.model or not mount.model.Parent then continue end
		local player = Players:GetPlayerByUserId(userId)
		if not player then continue end
		local char = player.Character
		if not char then continue end
		local root = char:FindFirstChild("HumanoidRootPart")
		if not root then continue end

		local state = mountAnimState[userId]
		if not state then
			state = { lastAnim = "Move", lastMoveTime = tick() }
			mountAnimState[userId] = state
		end

		-- Check horizontal velocity to determine if player is moving
		local vel = root.AssemblyLinearVelocity or root.Velocity
		local horizSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude

		if horizSpeed > 0.5 then
			state.lastMoveTime = tick()
		end

		local stationaryTime = tick() - state.lastMoveTime
		local desiredAnim = stationaryTime < MOUNT_IDLE_DELAY and "Move" or "Idle"

		if desiredAnim ~= state.lastAnim then
			state.lastAnim = desiredAnim
			CreatureAnimation.PlayAnimation(mount.model, desiredAnim, mount.creatureId)
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════
-- MOUNT SHIELD RECHARGE
-- ══════════════════════════════════════════════════════════════════════════
-- After shield breaks, waits MountShieldRechargeDelay seconds, then
-- refills over MountShieldRechargeTime seconds. While recharging, the
-- shield does NOT absorb damage (player takes hits normally).

local function updateMountShields(dt)
	local rechargeDelay = GameConfig.MountShieldRechargeDelay or 3
	local rechargeTime = GameConfig.MountShieldRechargeTime or 30

	for userId, mount in pairs(activeMounts) do
		if not mount.shieldBrokenAt then continue end

		local elapsed = tick() - mount.shieldBrokenAt
		if elapsed < rechargeDelay then continue end -- still in delay period

		-- Recharging: fill shield over rechargeTime seconds
		local rechargeElapsed = elapsed - rechargeDelay
		local rechargeRate = mount.shieldMax / rechargeTime
		mount.shieldCurrent = math.min(mount.shieldMax, rechargeRate * rechargeElapsed)

		-- Update client attribute
		local player = Players:GetPlayerByUserId(userId)
		if player then
			player:SetAttribute("MountShieldCurrent", mount.shieldCurrent)
		end

		-- Fully recharged? Clear broken state so shield absorbs again
		if mount.shieldCurrent >= mount.shieldMax then
			mount.shieldCurrent = mount.shieldMax
			mount.shieldBrokenAt = nil
			if player then
				player:SetAttribute("MountShieldCurrent", mount.shieldMax)
			end
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════
-- FLYING MOUNT UPDATE (server-side altitude enforcement)
-- ══════════════════════════════════════════════════════════════════════════

local function updateFlyingMounts()
	for userId, mount in pairs(activeMounts) do
		if mount.mountType == "Flying" and mount.bodyPos then
			local player = Players:GetPlayerByUserId(userId)
			if not player then continue end
			local char = player.Character
			if not char then continue end
			local root = char:FindFirstChild("HumanoidRootPart")
			if not root then continue end

			-- Read desired Y from client attribute
			local targetY = player:GetAttribute("MountFlyTargetY")
			if targetY and type(targetY) == "number" then
				-- Enforce altitude cap
				local maxAlt = GameConfig.MountFlyMaxAltitude or 200
				-- Raycast down to find actual ground height
				local rayParams = RaycastParams.new()
				rayParams.FilterType = Enum.RaycastFilterType.Exclude
				rayParams.FilterDescendantsInstances = { char, mount.model }
				local rayResult = workspace:Raycast(root.Position, Vector3.new(0, -1000, 0), rayParams)
				local groundY = rayResult and rayResult.Position.Y or 0

				-- Clamp: at least 3 studs above ground, at most maxAlt above ground
				local clampedY = math.clamp(targetY, groundY + 3, groundY + maxAlt)
				mount.bodyPos.Position = Vector3.new(root.Position.X, clampedY, root.Position.Z)
			else
				-- Keep at current height when no input
				mount.bodyPos.Position = Vector3.new(root.Position.X, root.Position.Y, root.Position.Z)
			end
		end
	end
end

-- ══════════════════════════════════════════════════════════════════════════
-- INIT
-- ══════════════════════════════════════════════════════════════════════════

function MountSystem.Init(playerDataMgr, favoriteSystem, creatureAIRef)
	PlayerDataManager = playerDataMgr
	FavoriteCreatureSystem = favoriteSystem
	CreatureAI = creatureAIRef

	local eventsFolder = ReplicatedStorage:WaitForChild("Events", 10)
	if not eventsFolder then
		warn("[MountSystem] Events folder not found!")
		return
	end

	-- ── Wire RemoteEvent handlers ──
	local mountRequest = eventsFolder:FindFirstChild("MountRequest")
	local dismountRequest = eventsFolder:FindFirstChild("DismountRequest")
	local mountFlyInput = eventsFolder:FindFirstChild("MountFlyInput")

	if mountRequest then
		mountRequest.OnServerEvent:Connect(function(plr)
			-- Validate and mount (uses favorite creature, no uid needed)
			local ok, err = MountSystem.CanMount(plr)
			if ok then
				MountSystem.Mount(plr)
			else
				-- Optionally send error to client
				local evts = ReplicatedStorage:FindFirstChild("Events")
				if evts then
					local mountEnded = evts:FindFirstChild("MountEnded")
					if mountEnded then
						mountEnded:FireClient(plr, err)
					end
				end
			end
		end)
	end

	if dismountRequest then
		dismountRequest.OnServerEvent:Connect(function(plr)
			MountSystem.Dismount(plr, false)
		end)
	end

	if mountFlyInput then
		mountFlyInput.OnServerEvent:Connect(function(plr, targetY)
			-- Client sends desired Y position for flying mount
			if type(targetY) ~= "number" then return end
			plr:SetAttribute("MountFlyTargetY", targetY)
		end)
	end

	-- ── Auto-dismount on death; shield absorbs damage while mounted ──
	-- Tracks last known health per player for damage detection
	local lastHealthByUser = {} -- [userId] = lastHealth

	-- Helper: wire up Humanoid listeners (death + shield absorption)
	local function wireHumanoidListeners(plr, hum)
		lastHealthByUser[plr.UserId] = hum.Health

		hum.Died:Connect(function()
			if activeMounts[plr.UserId] then
				MountSystem.Dismount(plr, true)
			end
			lastHealthByUser[plr.UserId] = nil
		end)

		-- Mount shield absorbs damage while mounted and shield is active
		hum.HealthChanged:Connect(function(newHealth)
			local prevHealth = lastHealthByUser[plr.UserId]
			lastHealthByUser[plr.UserId] = newHealth
			local mount = activeMounts[plr.UserId]
			if not prevHealth or not mount then return end

			local damageTaken = prevHealth - newHealth
			if damageTaken <= 0 then return end -- healing, not damage

			-- Shield is active (not broken/recharging)
			if mount.shieldCurrent > 0 and not mount.shieldBrokenAt then
				local absorbed = math.min(damageTaken, mount.shieldCurrent)
				mount.shieldCurrent = mount.shieldCurrent - absorbed

				-- Heal back the absorbed damage
				hum.Health = newHealth + absorbed
				lastHealthByUser[plr.UserId] = newHealth + absorbed

				-- Update client attribute
				plr:SetAttribute("MountShieldCurrent", mount.shieldCurrent)

				-- Shield depleted? Start recharge cooldown
				if mount.shieldCurrent <= 0 then
					mount.shieldCurrent = 0
					mount.shieldBrokenAt = tick()
					plr:SetAttribute("MountShieldCurrent", 0)
				end
			end
			-- If shield is broken/recharging, damage passes through normally
		end)
	end

	Players.PlayerAdded:Connect(function(plr)
		plr.CharacterAdded:Connect(function(char)
			-- Character respawn = force dismount (old character died)
			if activeMounts[plr.UserId] then
				MountSystem.Dismount(plr, true)
			end
			local hum = char:WaitForChild("Humanoid", 10)
			if hum then
				wireHumanoidListeners(plr, hum)
			end
		end)
	end)

	-- ── Handle existing players (late Init) ──
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then
			local hum = plr.Character:FindFirstChild("Humanoid")
			if hum then
				wireHumanoidListeners(plr, hum)
			end
		end
		plr.CharacterAdded:Connect(function(char)
			if activeMounts[plr.UserId] then
				MountSystem.Dismount(plr, true)
			end
			local hum = char:WaitForChild("Humanoid", 10)
			if hum then
				wireHumanoidListeners(plr, hum)
			end
		end)
	end

	-- ── Auto-dismount on leave ──
	Players.PlayerRemoving:Connect(function(plr)
		if activeMounts[plr.UserId] then
			MountSystem.Dismount(plr, true)
		end
		hadCompanionBeforeMount[plr.UserId] = nil
		mountCooldowns[plr.UserId] = nil
		mountAnimState[plr.UserId] = nil
		lastHealthByUser[plr.UserId] = nil
	end)

	-- ── Mount update loops (animation + flying altitude + shield recharge) ──
	RunService.Heartbeat:Connect(function(dt)
		updateMountAnimations()
		updateMountShields(dt)
		updateFlyingMounts()
	end)

	print("[MountSystem] Initialized")
end

return MountSystem
