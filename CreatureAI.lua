-- CreatureAI.lua - ServerScriptService (ModuleScript)
-- UPDATED: FIX #15 crawling upright reset on Move->Idle transition (2025)
-- Manages world creature behaviors: wander, aggro, pack, flee, fight, faint.
-- Fainted creatures become capturable for a gold cost.

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local CreatureData = require(game.ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(game.ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(game.ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(game.ReplicatedStorage.Modules.CreatureAnimation)

local CreatureAI = {}

local CREATURE_TAG = "WorldCreature"
local FAINTED_TAG = "FaintedCreature"
local COMPANION_TAG = "FavoriteCreature"
local BASE_DEFENSE_TAG = "BaseDefenseCreature"
local BASE_INCOME_TAG = "BaseIncomeCreature"

-- State for each creature model
local creatureStates = {} -- [model] = { id, hp, maxHp, behavior, state, spawnPos, target, lastAttack, packId, faintTime }

-- States: "idle", "wander", "chase", "attack", "flee", "faint"

-- ------ HELPERS ------

local function getBody(model)
	if not model then return nil end
	return CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
end

-- Raycast down to get ground Y at (x,z). Exclude ALL creature models (WorldCreature, BaseDefense,
-- BaseIncome, FavoriteCreature) and player characters so we hit actual ground, not other creatures.
-- Prevents fly-up/oscillation when dropped stolen creature and companion are near each other.
-- PERFORMANCE: getCreatureExcludeList builds list once per frame via getCachedExcludeList().
local _cachedExcludeList = nil
local _cachedExcludeTick = -1
local function getCachedExcludeList()
	local now = tick()
	if _cachedExcludeList and _cachedExcludeTick == now then
		return _cachedExcludeList
	end
	_cachedExcludeTick = now
	local list = {}
	local seen = {}
	for _, tag in ipairs({ CREATURE_TAG, BASE_DEFENSE_TAG, BASE_INCOME_TAG, COMPANION_TAG }) do
		for _, m in ipairs(CollectionService:GetTagged(tag)) do
			if m.Parent and not seen[m] then seen[m] = true; list[#list + 1] = m end
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character and not seen[p.Character] then seen[p.Character] = true; list[#list + 1] = p.Character end
	end
	_cachedExcludeList = list
	return list
end
local _groundRaycastParams = nil
local function getGroundY(x, z, fromY, excludeModel)
	if not _groundRaycastParams then
		_groundRaycastParams = RaycastParams.new()
		_groundRaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	end
	_groundRaycastParams.FilterDescendantsInstances = getCachedExcludeList()
	local origin = Vector3.new(x, fromY + 2, z)
	local hit = Workspace:Raycast(origin, Vector3.new(0, -50, 0), _groundRaycastParams)
	if hit then return hit.Position.Y end
	return fromY
end

-- Get desired body Y: ground creatures on surface, flying creatures at hover height
local FLOOR_OFFSET = 0.3
local function getDesiredBodyY(body, model, creatureId, posX, posZ)
	local fromY = body and body.Position.Y or 0
	local groundY = getGroundY(posX, posZ, fromY, model)
	if CreatureData.IsFlying(creatureId) then
		return groundY + (GameConfig.FlyingHoverHeight or 5)
	end
	local cf, size = model:GetBoundingBox()
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
	return groundY + (body.Position.Y - minY) + FLOOR_OFFSET
end

local function distBetween(a, b)
	if not a or not b then return 999 end
	return (a.Position - b.Position).Magnitude
end

-- Line of sight: raycast from fromModel to toModel; if anything blocks (e.g. base walls), return false.
-- Used so attacks cannot hit through walls — creatures must have clear line of sight to deal damage.
local function hasLineOfSight(fromModel, toModel)
	local fromBody = getBody(fromModel)
	local toBody = nil
	if toModel then
		toBody = CreatureModelLoader.GetBodyPart(toModel) or toModel:FindFirstChild("Body") or (toModel:FindFirstChild("HumanoidRootPart") and toModel.HumanoidRootPart)
	end
	if not fromBody or not toBody then return false end
	local fromPos = fromBody.Position
	local toPos = toBody.Position
	local dir = (toPos - fromPos).Unit
	local dist = (toPos - fromPos).Magnitude
	if dist < 0.5 then return true end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclude = { fromModel, toModel }
	params.FilterDescendantsInstances = exclude
	local result = Workspace:Raycast(fromPos, dir * dist, params)
	return result == nil
end

local LaserDoorSystem = nil -- Set in Init

local function moveTowards(body, target, speed, dt, creatureId)
	local dir = (target - body.Position) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.5 then return end
	local newPos = body.Position + dir.Unit * math.min(speed * dt, dir.Magnitude)

	-- Ground/flying: set Y so ground creatures sit on surface, flying hover at player height
	local model = body and body.Parent and body.Parent:IsA("Model") and body.Parent
	if model and creatureId then
		newPos = Vector3.new(newPos.X, getDesiredBodyY(body, model, creatureId, newPos.X, newPos.Z), newPos.Z)
	end

	-- Face movement direction (horizontal only). Apply model rotation offset (crawl only when walking).
	local pos = body.Position
	local targetFlat = Vector3.new(target.X, newPos.Y, target.Z)
	local rotOffset = creatureId and CreatureData.GetModelRotationOffset(creatureId, "world", true) or CFrame.identity
	body.CFrame = CFrame.lookAt(pos, targetFlat) * rotOffset

	-- Block movement into active dome shields
	if LaserDoorSystem and LaserDoorSystem.IsInsideActiveShield then
		local inside, shieldCenter, shieldRadius = LaserDoorSystem.IsInsideActiveShield(newPos)
		if inside then
			-- Push position to just outside the shield
			local awayDir = (newPos - shieldCenter) * Vector3.new(1, 0, 1)
			if awayDir.Magnitude < 0.5 then awayDir = Vector3.new(1, 0, 0) end
			local pushPos = shieldCenter + awayDir.Unit * (shieldRadius + 1)
			pushPos = Vector3.new(pushPos.X, getDesiredBodyY(body, model, creatureId, pushPos.X, pushPos.Z), pushPos.Z)
			body.Position = pushPos
			return
		end
	end

	body.Position = newPos
end

local function getRandomWanderPoint(center, radius)
	local angle = math.random() * math.pi * 2
	local dist = math.random() * radius
	return center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
end

local function findNearestCompanion(pos, range)
	local nearest, nearDist = nil, range
	for _, tagged in ipairs(CollectionService:GetTagged(COMPANION_TAG)) do
		if tagged.Parent then
			-- Only target alive companions (avoids attacking fainted companions that won't take damage)
			if CreatureAI._FavoriteSystem and CreatureAI._FavoriteSystem.IsCompanionAlive and not CreatureAI._FavoriteSystem.IsCompanionAlive(tagged) then
				continue
			end
			local b = getBody(tagged)
			if b then
				local d = (pos - b.Position).Magnitude
				if d < nearDist then nearDist = d; nearest = tagged end
			end
		end
	end
	return nearest, nearDist
end

local function findNearestPlayer(pos, range)
	local nearest, nearDist = nil, range
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if char then
			local root = char:FindFirstChild("HumanoidRootPart")
			if root then
				local d = (pos - root.Position).Magnitude
				if d < nearDist then nearDist = d; nearest = char end
			end
		end
	end
	return nearest, nearDist
end

local function findNearestCreature(pos, range, excludeModel, behaviorFilter)
	local nearest, nearDist = nil, range
	for model, state in pairs(creatureStates) do
		if model ~= excludeModel and model.Parent and state.state ~= "faint" then
			if not behaviorFilter or state.behavior ~= behaviorFilter then
				local b = getBody(model)
				if b then
					local d = (pos - b.Position).Magnitude
					if d < nearDist then nearDist = d; nearest = model end
				end
			end
		end
	end
	return nearest, nearDist
end

-- Find nearest base creature (defense first, then income) near a plot center
local DEFENSE_TAG = "BaseDefenseCreature"
local INCOME_TAG = "BaseIncomeCreature"

local function findNearestBaseCreature(pos, range, plotCenter, plotRadius)
	local nearest, nearDist = nil, range
	-- Search defense creatures first (priority targets)
	for _, tagged in ipairs(CollectionService:GetTagged(DEFENSE_TAG)) do
		if tagged.Parent and not tagged:GetAttribute("Fainted") then
			local b = CreatureModelLoader.GetBodyPart(tagged) or tagged:FindFirstChild("Body")
			if b then
				-- Must be near the target plot
				local toPlot = (b.Position - plotCenter).Magnitude
				if toPlot < (plotRadius or 60) then
					local d = (pos - b.Position).Magnitude
					if d < nearDist then nearDist = d; nearest = tagged end
				end
			end
		end
	end
	if nearest then return nearest, nearDist end
	-- Fallback: income creatures
	for _, tagged in ipairs(CollectionService:GetTagged(INCOME_TAG)) do
		if tagged.Parent and not tagged:GetAttribute("Fainted") then
			local b = CreatureModelLoader.GetBodyPart(tagged) or tagged:FindFirstChild("Body")
			if b then
				local toPlot = (b.Position - plotCenter).Magnitude
				if toPlot < (plotRadius or 60) then
					local d = (pos - b.Position).Magnitude
					if d < nearDist then nearDist = d; nearest = tagged end
				end
			end
		end
	end
	return nearest, nearDist
end

-- Fire a projectile from creature toward target; on hit, run the provided callback
local function fireCreatureProjectile(fromPos, toPos, color, onHit)
	task.spawn(function()
		local speed = GameConfig.AI_CreatureProjectileSpeed or 80
		local dist = (toPos - fromPos).Magnitude
		local dur = math.clamp(dist / speed, 0.1, 0.8)

		local bolt = Instance.new("Part")
		bolt.Shape = Enum.PartType.Ball
		bolt.Size = Vector3.new(1.2, 1.2, 1.2)
		bolt.Color = color
		bolt.Material = Enum.Material.Neon
		bolt.Anchored = true
		bolt.CanCollide = false
		bolt.CastShadow = false
		bolt.Position = fromPos
		bolt.Parent = Workspace

		local light = Instance.new("PointLight")
		light.Color = color
		light.Brightness = 2
		light.Range = 8
		light.Parent = bolt

		local startT = tick()
		while tick() - startT < dur do
			if not bolt.Parent then return end
			local t = (tick() - startT) / dur
			bolt.Position = fromPos:Lerp(toPos, t)
			RunService.Heartbeat:Wait()
		end

		bolt:Destroy()
		if onHit then pcall(onHit) end
	end)
end

-- Pack alerting: when one pack member is attacked, alert nearby pack members
local function alertPack(attackedModel, attacker)
	local state = creatureStates[attackedModel]
	if not state or state.behavior ~= "pack" or not state.packId then return end

	for model, s in pairs(creatureStates) do
		if model ~= attackedModel and model.Parent and s.packId == state.packId and s.state ~= "faint" then
			local b1 = getBody(attackedModel)
			local b2 = getBody(model)
			if b1 and b2 and distBetween(b1, b2) < GameConfig.AI_PackCallRange then
				s.target = attacker
				s.state = "chase"
			end
		end
	end
end

-- ------ DAMAGE / FAINT ------

local function showWorldDamage(pos, damage)
	local att = Instance.new("Part")
	att.Size = Vector3.new(0.1, 0.1, 0.1); att.Position = pos + Vector3.new(math.random(-1,1), 2, math.random(-1,1))
	att.Anchored = true; att.CanCollide = false; att.Transparency = 1; att.Parent = workspace

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 60, 0, 24); bb.StudsOffset = Vector3.new(0, 2, 0)
	bb.AlwaysOnTop = true; bb.Adornee = att; bb.Parent = att

	local lbl = Instance.new("TextLabel")
	lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
	lbl.Text = "-" .. math.floor(damage); lbl.TextColor3 = Color3.fromRGB(255, 100, 60)
	lbl.Font = Enum.Font.GothamBlack; lbl.TextSize = 16
	lbl.TextStrokeColor3 = Color3.new(0, 0, 0); lbl.TextStrokeTransparency = 0.3
	lbl.Parent = bb

	task.spawn(function()
		for i = 1, 15 do
			att.Position = att.Position + Vector3.new(0, 0.1, 0)
			lbl.TextTransparency = i / 15; lbl.TextStrokeTransparency = 0.3 + (i / 15) * 0.7
			RunService.Heartbeat:Wait()
		end
		att:Destroy()
	end)
end

local WorldCreatureHP = nil
local function getWorldCreatureHP()
	if WorldCreatureHP == nil then
		local ok, mod = pcall(require, game:GetService("ServerScriptService"):FindFirstChild("WorldCreatureHP"))
		WorldCreatureHP = ok and mod or false
	end
	return WorldCreatureHP and WorldCreatureHP or nil
end

function CreatureAI.DamageCreature(model, damage, attackerModel)
	local state = creatureStates[model]
	if not state then
		-- Creature not in AI state (e.g. spawn race, or not yet registered) — fall back to WorldCreatureHP
		local wchp = getWorldCreatureHP()
		if wchp and wchp.DamageCreature then
			wchp.DamageCreature(model, damage, attackerModel)
		end
		return
	end
	if state.state == "faint" then return end

	state.hp = state.hp - damage

	-- Sync HP to model attribute for external systems (AIRaidSystem HP bars)
	model:SetAttribute("HP", state.hp)
	model:SetAttribute("MaxHP", state.maxHp)

	local body = getBody(model)
	if body then
		showWorldDamage(body.Position, damage)
		-- Flash red
		task.spawn(function()
			local oc = body.Color; body.Color = Color3.fromRGB(255, 50, 50)
			task.wait(0.12); if body.Parent then body.Color = oc end
		end)
	end

	-- Alert pack (skip for raiders - they have their own targeting)
	if attackerModel and state.behavior ~= "raider" then
		alertPack(model, attackerModel)
	end

	-- Engage attacker: set target so creature chases/flees the player who hit it
	-- Raiders keep their own targeting (base creatures), don't redirect
	if attackerModel and state.behavior ~= "raider" then
		if state.behavior == "skittish" then
			state.target = attackerModel; state.state = "flee"
		elseif state.behavior == "gentle" or state.behavior == "aggressive" or state.behavior == "pack" or state.behavior == "lone" then
			state.target = attackerModel; state.state = "chase"
		end
	end

	if state.hp <= 0 then
		CreatureAI.FaintCreature(model, attackerModel)
	end
end

-- Optional killer model (e.g. defense turret or world creature). Fired so defense can award XP on kill.
CreatureAI.OnCreatureFainted = nil -- set in Init to Instance.new("BindableEvent")

function CreatureAI.FaintCreature(model, killerModel)
	local state = creatureStates[model]
	if not state then return end

	state.state = "faint"
	state.faintTime = tick()
	state.target = nil

	-- Check if this is a base creature (defense / income / battle)
	local isBaseCreature = CollectionService:HasTag(model, DEFENSE_TAG)
		or CollectionService:HasTag(model, INCOME_TAG)

	-- Visual: darken but keep clickable size
	local body = getBody(model)
	if body then
		body.Color = Color3.fromRGB(80, 80, 80)
		body.Material = Enum.Material.SmoothPlastic
		body.Transparency = 0.15
	end

	local core = model:FindFirstChild("Core")
	if core then core:Destroy() end

	-- Remove highlight, add faint highlight
	local hl = model:FindFirstChildOfClass("Highlight")
	if hl then hl:Destroy() end
	local faintHL = Instance.new("Highlight")
	faintHL.FillColor = Color3.fromRGB(100, 100, 100)
	faintHL.FillTransparency = 0.5
	faintHL.OutlineColor = isBaseCreature and Color3.fromRGB(255, 100, 100) or Color3.fromRGB(255, 200, 0)
	faintHL.OutlineTransparency = 0.3
	faintHL.Parent = model

	-- Set fainted attribute
	model:SetAttribute("Fainted", true)
	model:SetAttribute("FaintTime", tick())

	-- Faint animation: play once and freeze on final frame (model stays until despawn/capture)
	CreatureAnimation.PlayAnimation(model, "Faint", state.id)

	if isBaseCreature then
		-- Base creature: add steal tag instead of capture tag, no despawn timer
		CollectionService:AddTag(model, "FaintedBaseCreature")
	else
		-- World creature: normal capture flow
		-- Update billboard
		local bb = model:FindFirstChild("NameTag")
		if bb then
			local rarityLbl = bb:FindFirstChild("RarityLabel")
			if rarityLbl then
				rarityLbl.Text = "FAINTED - Click to Capture!"
				rarityLbl.TextColor3 = Color3.fromRGB(255, 200, 50)
			end
		end

		-- Add fainted tag for capture system
		CollectionService:AddTag(model, FAINTED_TAG)
	end

	-- Notify listeners (e.g. defense turret gets XP for this kill)
	if CreatureAI.OnCreatureFainted then
		task.spawn(function()
			CreatureAI.OnCreatureFainted:Fire(model, killerModel)
		end)
	end
end

-- ------ AI UPDATE ------

local function updateCreature(model, state, dt)
	if state.state == "faint" then
		-- Despawn after FaintDuration (skip for base creatures - they stay until stolen or refreshed)
		if state.behavior ~= "stationary" then
			if tick() - (state.faintTime or 0) > GameConfig.FaintDuration then
				if model.Parent then model:Destroy() end
			end
		end
		return
	end

	local body = getBody(model)
	if not body then return end
	local pos = body.Position

	local info = CreatureData.GetById(state.id)
	if not info then return end

	local speedMult = info.speed / 10

	-- Idle delay: if model hasn't moved for 2 seconds, prefer Idle over Move
	local posDelta = (pos - (state.lastAnimPos or pos)).Magnitude
	if posDelta > 0.3 then
		state.lastAnimPos = pos
		state.lastAnimPosTime = tick()
	end
	local idleDelay = 2
	local stationaryFor2s = (tick() - (state.lastAnimPosTime or tick())) >= idleDelay

	-- Animation: Attack when attacking, Move when chasing/wandering (unless stationary 2s), Income on income slots, Idle otherwise
	local animType
	if state.state == "attack" then animType = "Attack"
	elseif (state.state == "chase" or state.state == "wander") and not stationaryFor2s then animType = "Move"
	elseif state.behavior == "stationary" and model:GetAttribute("SlotType") == "income" then animType = "Income"
	else animType = "Idle"
	end
	local prevAnimType = state._lastAnimType or ""
	-- PERFORMANCE: Only call PlayAnimation when anim type changes (skip redundant per-frame calls)
	if animType ~= prevAnimType then
		state._lastAnimType = animType
		local opts = (animType == "Attack") and { speed = math.clamp(speedMult, 0.5, 2) } or nil
		CreatureAnimation.PlayAnimation(model, animType, state.id, opts)
	end

	-- FIX #15 Crawling orientation reset: when a crawling creature stops moving (Idle/Attack/Income),
	-- reset its rotation to the upright (non-crawling) offset. Without this, the -90° pitch from
	-- moveTowards() persists and the creature stays belly-down permanently after walking.
	-- We track the previous animation state so we only apply the reset on the transition frame
	-- (Move → non-Move), avoiding redundant CFrame writes every tick.
	-- Use prevAnimType (before we may have updated _lastAnimType) for wasMoving check
	if CreatureData.IsCrawling(state.id) then
		local wasMoving = prevAnimType == "Move"
		local isMoving = animType == "Move"
		if wasMoving and not isMoving then
			-- Transition from Move → non-Move: reset to upright orientation (isWalking=false)
			local uprightRot = CreatureData.GetModelRotationOffset(state.id, "world", false)
			local lookTarget = state.target and typeof(state.target) == "Instance" and state.target.Parent
				and (CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart"))
			if lookTarget then
				-- Face attack/chase target while standing upright
				local targetFlat = Vector3.new(lookTarget.Position.X, pos.Y, lookTarget.Position.Z)
				body.CFrame = CFrame.lookAt(pos, targetFlat) * uprightRot
			else
				-- No target: keep current facing direction but reset pitch to upright
				local currentLook = body.CFrame.LookVector * Vector3.new(1, 0, 1)
				if currentLook.Magnitude > 0.1 then
					local forwardPos = pos + currentLook.Unit
					body.CFrame = CFrame.lookAt(pos, forwardPos) * uprightRot
				else
					body.CFrame = CFrame.new(pos) * uprightRot
				end
			end
		end
		state._lastAnimType = animType
	end

	-- Behavior-specific AI
	if state.behavior == "aggressive" then
		-- Look for targets: companions first, then player (if no companion out), then other creatures
		if state.state == "idle" or state.state == "wander" then
			local comp, compDist = findNearestCompanion(pos, GameConfig.AI_AggroRange)
			if comp then
				state.target = comp; state.state = "chase"
			else
				-- No companion in range - target player only if they have NO companion out (fainted/Y-swapped)
				local plr, plrDist = findNearestPlayer(pos, GameConfig.AI_AggroRange)
				if plr then
					local playerObj = Players:GetPlayerFromCharacter(plr)
					if playerObj and CreatureAI._FavoriteSystem and CreatureAI._FavoriteSystem.HasCompanion(playerObj) then
						plr = nil  -- Player has companion out - don't target player, companion will be found when in range
					end
				end
				if plr then
					state.target = plr; state.state = "chase"
				else
				local prey, preyDist = findNearestCreature(pos, GameConfig.AI_AggroRange * 0.7, model, "aggressive")
				if prey then
					state.target = prey; state.state = "chase"
				else
					-- Wander
					if state.state ~= "wander" or not state.wanderTarget then
						state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius)
						state.state = "wander"
					end
					moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult, dt, state.id)
					if (body.Position - state.wanderTarget).Magnitude < 3 then
						state.state = "idle"; state.wanderTarget = nil
						state.idleUntil = tick() + math.random(2, 5)
					end
				end
				end
			end
		end

	elseif state.behavior == "pack" then
		-- Similar to aggressive but only engages when provoked or a packmate calls
		if state.state == "idle" or state.state == "wander" then
			if state.state ~= "wander" or not state.wanderTarget then
				state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.6)
				state.state = "wander"
			end
			moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 0.8, dt, state.id)
			if (body.Position - state.wanderTarget).Magnitude < 3 then
				state.state = "idle"; state.wanderTarget = nil
				state.idleUntil = tick() + math.random(3, 8)
			end
		end

	elseif state.behavior == "gentle" then
		-- Peaceful wander, only fights back
		if state.state == "idle" or state.state == "wander" then
			if state.state ~= "wander" or not state.wanderTarget then
				state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.4)
				state.state = "wander"
			end
			moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 0.5, dt, state.id)
			if (body.Position - state.wanderTarget).Magnitude < 3 then
				state.state = "idle"; state.wanderTarget = nil
				state.idleUntil = tick() + math.random(5, 12)
			end
		end

	elseif state.behavior == "lone" then
		-- Patrols territory, attacks if you enter range
		if state.state == "idle" or state.state == "wander" then
			local comp, compDist = findNearestCompanion(pos, GameConfig.AI_AggroRange * 0.6)
			if comp then
				state.target = comp; state.state = "chase"
			else
				-- No companion in range - target player only if they have NO companion out
				local plr, plrDist = findNearestPlayer(pos, GameConfig.AI_AggroRange * 0.6)
				if plr then
					local playerObj = Players:GetPlayerFromCharacter(plr)
					if playerObj and CreatureAI._FavoriteSystem and CreatureAI._FavoriteSystem.HasCompanion(playerObj) then
						plr = nil
					end
				end
				if plr then
					state.target = plr; state.state = "chase"
				else
				if state.state ~= "wander" or not state.wanderTarget then
					state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.5)
					state.state = "wander"
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 0.7, dt, state.id)
				if (body.Position - state.wanderTarget).Magnitude < 3 then
					state.state = "idle"; state.wanderTarget = nil
					state.idleUntil = tick() + math.random(3, 7)
				end
				end
			end
		end

	elseif state.behavior == "skittish" then
		-- Flee when anything gets close
		if state.state == "idle" or state.state == "wander" then
			local comp, compDist = findNearestCompanion(pos, GameConfig.AI_AggroRange * 0.8)
			local plr, plrDist = findNearestPlayer(pos, GameConfig.AI_AggroRange * 0.5)
			if comp or plr then
				state.target = comp or plr; state.state = "flee"
			else
				if state.state ~= "wander" or not state.wanderTarget then
					state.wanderTarget = getRandomWanderPoint(state.spawnPos, GameConfig.AI_WanderRadius * 0.8)
					state.state = "wander"
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult, dt, state.id)
				if (body.Position - state.wanderTarget).Magnitude < 3 then
					state.state = "idle"; state.wanderTarget = nil
					state.idleUntil = tick() + math.random(2, 4)
				end
			end
		end
	elseif state.behavior == "stationary" then
		-- Base creatures don't move, just stay at their position
		-- They only take damage; no wandering, no chasing
		state.state = "idle"
		return

	elseif state.behavior == "raider" then
		-- Raid behavior: target base defense/income creatures on the assigned plot
		if state.state == "idle" or state.state == "wander" then
			local raidCenter = state.raidCenter or state.spawnPos
			local target, tDist = findNearestBaseCreature(pos, 80, raidCenter, 60)
			if target then
				state.target = target; state.state = "chase"
			else
				-- No targets left, wander toward plot center
				if state.state ~= "wander" or not state.wanderTarget then
					state.wanderTarget = getRandomWanderPoint(raidCenter, 15)
					state.state = "wander"
				end
				moveTowards(body, state.wanderTarget, GameConfig.AI_WanderSpeed * speedMult * 1.2, dt, state.id)
				if (body.Position - state.wanderTarget).Magnitude < 3 then
					state.state = "idle"; state.wanderTarget = nil
					state.idleUntil = tick() + math.random(1, 3)
				end
			end
		end
	end

	-- Handle idle timer (if no idleUntil set, give a short one to prevent permanent idle)
	if state.state == "idle" then
		-- Flying creatures: enforce hover height every tick (they don't move, so we don't call moveTowards)
		if CreatureData.IsFlying(state.id) then
			local desiredY = getDesiredBodyY(body, model, state.id, pos.X, pos.Z)
			if math.abs(body.Position.Y - desiredY) > 0.1 then
				body.Position = Vector3.new(body.Position.X, desiredY, body.Position.Z)
			end
		end
		if not state.idleUntil then
			state.idleUntil = tick() + math.random(1, 3)
		elseif tick() > state.idleUntil then
			state.state = "wander"; state.wanderTarget = nil
		end
	end

	-- -- CHASE --
	if state.state == "chase" and state.target then
		-- Don't chase fainted targets (world creatures shouldn't attack monsters that are already fainted)
		if typeof(state.target) == "Instance" and state.target:GetAttribute("Fainted") then
			state.state = "wander"; state.target = nil; state.wanderTarget = nil; return
		end
		local targetBody = nil
		if typeof(state.target) == "Instance" and state.target.Parent then
			targetBody = CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart")
		end
		if not targetBody then
			-- Target lost — return to wander (not bare idle which can get stuck)
			state.state = "wander"; state.target = nil; state.wanderTarget = nil; return
		end

		local tdist = (pos - targetBody.Position).Magnitude
		local maxChaseRange = state.behavior == "raider" and 200 or (GameConfig.AI_AggroRange * 1.5)
		if tdist > maxChaseRange then
			-- Lost target, return
			state.state = "wander"; state.target = nil; state.wanderTarget = nil
		elseif tdist > GameConfig.AI_AttackRange then
			-- Raiders: waypoint sequence — door → plot center (up ramp) → then chase target (or path to door if no LOS)
			local moveTarget = targetBody.Position
			if state.behavior == "raider" and state.raidCenter and state.raidDoor then
				local doorReach = tonumber(GameConfig.AIRaidDoorReachRadius) or 10
				local centerReach = tonumber(GameConfig.AIRaidCenterReachRadius) or 14
				local toCenter = (pos - state.raidCenter) * Vector3.new(1, 0, 1)
				local toDoor = (pos - state.raidDoor) * Vector3.new(1, 0, 1)
				local atDoor = toDoor.Magnitude <= doorReach
				local atCenter = toCenter.Magnitude <= centerReach
				if not atDoor then
					-- Phase 1: path to the door
					moveTarget = state.raidDoor
				elseif not atCenter then
					-- Phase 2: at door — path to plot center (up the ramp to PlotCenter)
					moveTarget = state.raidCenter
				else
					-- Phase 3: at center — may path to target (or to door if no LOS)
					local noLOS = not hasLineOfSight(model, state.target)
					if noLOS then
						moveTarget = state.raidDoor
					end
				end
			end
			moveTowards(body, moveTarget, GameConfig.AI_WanderSpeed * speedMult * 1.5, dt, state.id)
		else
			-- Raiders: only enter attack after reaching plot center (door → center waypoint done) and have LOS
			local centerReach = tonumber(GameConfig.AIRaidCenterReachRadius) or 14
			if state.behavior == "raider" and state.raidCenter and state.raidDoor then
				local toCenter = (pos - state.raidCenter) * Vector3.new(1, 0, 1)
				local atCenter = toCenter.Magnitude <= centerReach
				local noLOS = not hasLineOfSight(model, state.target)
				if not atCenter then
					-- Not at center yet — keep pathing to center (or door if not at door)
					local doorReach = tonumber(GameConfig.AIRaidDoorReachRadius) or 10
					local toDoor = (pos - state.raidDoor) * Vector3.new(1, 0, 1)
					local dest = (toDoor.Magnitude > doorReach) and state.raidDoor or state.raidCenter
					moveTowards(body, dest, GameConfig.AI_WanderSpeed * speedMult * 1.5, dt, state.id)
				elseif noLOS then
					moveTowards(body, state.raidDoor, GameConfig.AI_WanderSpeed * speedMult * 1.5, dt, state.id)
				else
					state.state = "attack"
				end
			else
				state.state = "attack"
			end
		end
	end

	-- -- ATTACK --
	if state.state == "attack" and state.target then
		-- Don't attack fainted targets (world creatures shouldn't attack monsters that are already fainted)
		if typeof(state.target) == "Instance" and state.target:GetAttribute("Fainted") then
			state.state = "wander"; state.target = nil; state.wanderTarget = nil; return
		end
		local targetBody = nil
		if typeof(state.target) == "Instance" and state.target.Parent then
			targetBody = CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart")
		end
		if not targetBody then
			state.state = "wander"; state.target = nil; state.wanderTarget = nil; return
		end

		-- Face target while attacking (apply model rotation offset for crawling/facing)
		local targetFlat = Vector3.new(targetBody.Position.X, pos.Y, targetBody.Position.Z)
		local rotOffset = state.id and CreatureData.GetModelRotationOffset(state.id) or CFrame.identity
		body.CFrame = CFrame.lookAt(pos, targetFlat) * rotOffset

		local tdist = (pos - targetBody.Position).Magnitude
		if tdist > GameConfig.AI_AttackRange * 1.5 then
			state.state = "chase"; return
		end
		-- Raiders: lose LOS (e.g. target behind wall) — drop to chase so they path to door
		if state.behavior == "raider" and not hasLineOfSight(model, state.target) then
			state.state = "chase"; return
		end
		-- Raiders must stay inside base to attack; if pushed out, chase again
		if state.behavior == "raider" and state.raidCenter then
			local insideRadius = tonumber(GameConfig.AIRaidAttackInsideRadius) or 55
			local toCenter = (pos - state.raidCenter) * Vector3.new(1, 0, 1)
			if toCenter.Magnitude > insideRadius then
				state.state = "chase"; return
			end
		end

		if tick() - (state.lastAttack or 0) >= GameConfig.AI_AttackCooldown then
			state.lastAttack = tick()
			local damage = math.max(1, math.floor(info.attack * 0.4))

			-- Elemental weakness: world creature (attacker) vs target (defender)
			local defenderElement = nil
			local targetState = creatureStates[state.target]
			if targetState then
				local dinfo = CreatureData.GetById(targetState.id)
				defenderElement = dinfo and dinfo.element
			else
				local ownerId = state.target:GetAttribute("OwnerUserId")
				local ownerPlayer = ownerId and Players:GetPlayerByUserId(ownerId)
				if ownerPlayer and CreatureAI._FavoriteSystem then
					local _, comp = CreatureAI._FavoriteSystem.GetCompanionForModel(state.target)
					if comp then
						local dinfo = CreatureData.GetById(comp.creatureId)
						defenderElement = dinfo and dinfo.element
					end
				end
			end
			local elemMult = CreatureData.GetElementalDamageMultiplier(info.element, defenderElement)
			if elemMult > 1 then
				elemMult = GameConfig.ElementalAdvantageMultiplier or elemMult
			elseif elemMult < 1 then
				elemMult = GameConfig.ElementalDisadvantageMultiplier or elemMult
			end
			damage = math.floor(math.max(1, damage * elemMult))

			-- Projectile color from element or body
			local projColor = (info.element and CreatureData.Elements and CreatureData.Elements[info.element] and CreatureData.Elements[info.element].color) or body.Color

			local fromPos = body.Position + (targetBody.Position - body.Position).Unit * 1.5
			local toPos = targetBody.Position
			local targetModel = state.target
			local capturedTargetState = targetState

			-- Fire projectile; apply damage when it hits (only if line of sight — walls block attacks)
			fireCreatureProjectile(fromPos, toPos, projColor, function()
				local target = targetModel
				if not target or not target.Parent then return end
				if not hasLineOfSight(model, target) then return end
				local hitBody = CreatureModelLoader.GetBodyPart(target) or target:FindFirstChild("Body") or target:FindFirstChild("HumanoidRootPart")
				local hitPos = hitBody and hitBody.Position or toPos

				if capturedTargetState then
					CreatureAI.DamageCreature(target, damage, model)
				else
					local ownerId = target:GetAttribute("OwnerUserId")
					local ownerPlayer = ownerId and Players:GetPlayerByUserId(ownerId)
					if ownerPlayer then
						if CreatureAI._FavoriteSystem then
							CreatureAI._FavoriteSystem.DamageCompanion(ownerPlayer, damage, model)
						else
							showWorldDamage(hitPos, damage)
						end
					else
						local player = Players:GetPlayerFromCharacter(target)
						if player then
							local hum = target:FindFirstChild("Humanoid")
							if hum and hum.Health > 0 then
								hum:TakeDamage(damage)
								showWorldDamage(hitPos, damage)
							end
						else
							showWorldDamage(hitPos, damage)
						end
					end
				end

				if state.onAttackHit then
					pcall(state.onAttackHit, model, target, damage)
				end
			end)
		end
	end

	-- -- FLEE --
	if state.state == "flee" then
		local fleeFrom = nil
		if state.target and typeof(state.target) == "Instance" and state.target.Parent then
			fleeFrom = CreatureModelLoader.GetBodyPart(state.target) or state.target:FindFirstChild("Body") or state.target:FindFirstChild("HumanoidRootPart")
		end
		if fleeFrom then
			local away = (pos - fleeFrom.Position) * Vector3.new(1, 0, 1)
			if away.Magnitude > 0.1 then
				local newPos = body.Position + away.Unit * GameConfig.AI_FleeSpeed * speedMult * dt
				newPos = Vector3.new(newPos.X, getDesiredBodyY(body, model, state.id, newPos.X, newPos.Z), newPos.Z)
				body.Position = newPos
			end
			if away.Magnitude > GameConfig.AI_FleeRange then
				state.state = "wander"; state.target = nil; state.wanderTarget = nil
			end
		else
			state.state = "wander"; state.target = nil; state.wanderTarget = nil
		end
	end
end

-- ------ PUBLIC API ------

local nextPackId = 0
function CreatureAI.RegisterCreature(model, creatureId, spawnPos, packId)
	local info = CreatureData.GetById(creatureId)
	if not info then return end

	creatureStates[model] = {
		id = creatureId,
		hp = info.health,
		maxHp = info.health,
		behavior = info.behavior or "gentle",
		state = "idle",
		spawnPos = spawnPos,
		target = nil,
		lastAttack = 0,
		packId = packId,
		faintTime = nil,
		idleUntil = tick() + math.random(1, 4),
		wanderTarget = nil,
	}
end

function CreatureAI.UnregisterCreature(model)
	creatureStates[model] = nil
end

function CreatureAI.GetState(model)
	return creatureStates[model]
end

function CreatureAI.IsFainted(model)
	local s = creatureStates[model]
	return s and s.state == "faint"
end

-- Walls block attacks: attackers need clear line of sight to deal damage (used by defense turrets too).
function CreatureAI.HasLineOfSight(fromModel, toModel)
	return hasLineOfSight(fromModel, toModel)
end

function CreatureAI.GetHP(model)
	local s = creatureStates[model]
	if s then return s.hp, s.maxHp end
	-- Fallback: creature may use WorldCreatureHP (e.g. damage applied before AI registration)
	local wchp = getWorldCreatureHP()
	if wchp and wchp.GetHP then
		return wchp.GetHP(model)
	end
	return 0, 0
end

function CreatureAI.GeneratePackId()
	nextPackId = nextPackId + 1
	return "pack_" .. nextPackId
end

CreatureAI._FavoriteSystem = nil  -- Set by MainServer after init

function CreatureAI.SetFavoriteSystem(favSys)
	CreatureAI._FavoriteSystem = favSys
end

-- ------ INIT ------

function CreatureAI.Init(laserDoorRef)
	if laserDoorRef then LaserDoorSystem = laserDoorRef end
	CreatureAI.OnCreatureFainted = Instance.new("BindableEvent")
	-- Main AI loop: run every frame for fluid movement (was task.wait tick rate - caused jumpy motion)
	-- IMPORTANT: Never modify creatureStates during pairs() iteration.
	-- Collect removals in a separate list, then apply after iteration.
	local lastTick = tick()
	RunService.Heartbeat:Connect(function()
		local now = tick()
		local dt = math.min(now - lastTick, 1/15) -- clamp dt to avoid huge jumps after lag
		lastTick = now

		local toRemove = {}
		for model, state in pairs(creatureStates) do
			if model.Parent then
				local ok, err = pcall(updateCreature, model, state, dt)
				if not ok then warn("[CreatureAI] Error: " .. tostring(err)) end
			else
				table.insert(toRemove, model)
			end
		end

		-- Clean up destroyed models outside of iteration
		for _, model in ipairs(toRemove) do
			creatureStates[model] = nil
		end
	end)

end

return CreatureAI