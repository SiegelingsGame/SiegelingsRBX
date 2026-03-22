-- GymBattleSystem.lua - ServerScriptService (ModuleScript)
-- ═══════════════════════════════════════════════════════════════════════════════
-- Floor 4 Personal Arena ("Siegelord Gym")
--
-- Each player who owns Floor 4 has a personal arena on their base. Visitors
-- can walk up and challenge the owner's Battle Team to a gym battle.
--
-- Workspace structure (inside each Plot's Floor4 folder):
--   Floor4/
--     BaseGym/
--       GymCenter (Part — ProximityPrompt trigger for challengers)
--       BlueTeam/ (owner's team spawns here)
--         BattlePoint1..9
--       RedTeam/  (challenger's team spawns here)
--         BattlePoint1..9
--
-- Battle flow:
--   1. Visitor triggers ProximityPrompt on GymCenter
--   2. System validates both players have battle teams
--   3. Spawns owner's team on RedTeam points, challenger on BlueTeam points
--   4. Runs auto-battle ticks (same speed-based turn system as main arena)
--   5. Winner gets GymBattleWinGold reward
--   6. Cooldown prevents immediate re-challenge
--
-- Architecture:
--   - Does NOT use ArenaSystem.StartGymBattle (that swaps global arena state)
--   - Runs its own isolated battle loop per plot, so multiple gym battles
--     can happen simultaneously on different plots
--   - Reuses CreatureModelLoader, CreatureData, CreatureAnimation for spawning
--   - Sets "GymBattleInProgress" attribute on the plot during battle
--
-- FIX #20 Gym battle parity with Arena:
--   - Added BillboardGui (name label, HP bar, focus bar) to spawned creatures
--   - Added attack visuals (projectiles, damage numbers), special attack visuals
--     (element-based particles), and death visuals (shrink + fade)
--   - Battle loop now runs per-creature turns sorted by speed (matching arena)
--     with animations, elemental effects, burn/freeze/earth debuffs, and focus
--   - Formation spawning: creatures placed on BattlePoint matching their
--     battleTeam slot index, not sequentially (1,2,3...)
--   - getPlayerBattleTeam now uses PlayerDataManager.GetEffectiveStats for
--     proper level+variant stat scaling, and includes element/uid/variant data
--   - State broadcasting to clients via GymBattleStateUpdate event
-- ═══════════════════════════════════════════════════════════════════════════════

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(ReplicatedStorage.Modules.CreatureAnimation)

local GymBattleSystem = {}

-- ═══════════════════════════════════════════════════════════════════════════════
-- Dependencies (set in Init)
-- ═══════════════════════════════════════════════════════════════════════════════
local PlayerDataManager
local BasePlacementSystem

-- ═══════════════════════════════════════════════════════════════════════════════
-- Config
-- ═══════════════════════════════════════════════════════════════════════════════
local TICK_SPEED      = GameConfig.GymBattleTickSpeed    or 1.2
local WIN_GOLD        = GameConfig.GymBattleWinGold      or 200
local COOLDOWN        = GameConfig.GymBattleCooldown     or 60
local GYM_TAG         = "GymBattleCreature"
local FACING_X_CORRECTION = math.rad(0)
local MAX_BATTLE_TEAM_SIZE = 9

-- Bounty config
local BOUNTY_BASE         = GameConfig.GymBountyBase         or 100
local BOUNTY_GROWTH       = GameConfig.GymBountyGrowth       or 50
local BOUNTY_MAX          = GameConfig.GymBountyMax          or 5000
local OWNER_DEFENSE_PAY   = GameConfig.GymOwnerDefenseIncome or 75
local CHALLENGER_LOSE_PAY = GameConfig.GymChallengerLosePay  or 25

-- State broadcast throttle
local STATE_BROADCAST_MIN_INTERVAL = 0.10

-- ═══════════════════════════════════════════════════════════════════════════════
-- Element colors (matches ArenaSystem)
-- ═══════════════════════════════════════════════════════════════════════════════
local ELEMENT_COLORS = {
	Fire = Color3.fromRGB(255, 100, 30),
	Ice = Color3.fromRGB(100, 200, 255),
	Earth = Color3.fromRGB(180, 140, 80),
	Wind = Color3.fromRGB(150, 255, 180),
	Shadow = Color3.fromRGB(120, 50, 180),
	Light = Color3.fromRGB(255, 250, 200),
	Lightning = Color3.fromRGB(255, 230, 60),
	Water = Color3.fromRGB(50, 150, 255),
	Psychic = Color3.fromRGB(200, 150, 255),
	Metal = Color3.fromRGB(160, 170, 180),
	Poison = Color3.fromRGB(120, 220, 80),
	Undead = Color3.fromRGB(140, 120, 160),
}

-- ═══════════════════════════════════════════════════════════════════════════════
-- State
-- ═══════════════════════════════════════════════════════════════════════════════

-- Per-plot active battle: plotName → true (prevents overlapping battles on same plot)
local activeBattles = {}

-- Per-player active gym: userId → plotName (tracks which players are fighting in a gym)
-- Used by ArenaSystem to delay arena rounds until gym battles involving those players finish
local activeGymPlayers = {}

-- Cooldown tracker: challengerUserId_plotName → tick() of last battle end
local cooldowns = {}

-- Per-plot bounty: plotName → { amount = number, defenseWins = number }
-- Bounty grows each time the owner successfully defends. Resets when a challenger wins.
local plotBounties = {}

-- Events folder reference
local eventsFolder = nil

-- ═══════════════════════════════════════════════════════════════════════════════
-- Bounty helpers
-- ═══════════════════════════════════════════════════════════════════════════════
local function getBounty(plotName)
	if not plotBounties[plotName] then
		plotBounties[plotName] = { amount = BOUNTY_BASE, defenseWins = 0 }
	end
	return plotBounties[plotName]
end

local function growBounty(plotName)
	local b = getBounty(plotName)
	b.defenseWins += 1
	b.amount = math.min(b.amount + BOUNTY_GROWTH, BOUNTY_MAX)
end

local function resetBounty(plotName)
	plotBounties[plotName] = { amount = BOUNTY_BASE, defenseWins = 0 }
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Find the plot owner Player from a plot model
-- ═══════════════════════════════════════════════════════════════════════════════
local function getPlotOwner(plotModel)
	local ownerUserId = plotModel:GetAttribute("OwnerUserId")
	if not ownerUserId then return nil end
	return Players:GetPlayerByUserId(ownerUserId)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Get a player's battle team as a list matching ArenaSystem format
-- FIX #20: Now uses PlayerDataManager.GetEffectiveStats for proper stat scaling,
-- preserves slotIndex for formation placement, and includes element/uid/variant.
-- @param player Player
-- @return table[] — array of creature entries with id, uid, slotIndex, level, etc.
-- ═══════════════════════════════════════════════════════════════════════════════
local function getPlayerBattleTeam(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.battleTeam then return {} end

	local team = {}
	for slotIndex, uid in pairs(data.battleTeam) do
		local sNum = tonumber(slotIndex)
		if sNum and uid and uid ~= "" then
			local su = tostring(uid)
			for _, entry in ipairs(data.inventory or {}) do
				if entry.uid and tostring(entry.uid) == su then
					local info = CreatureData.GetById(entry.id)
					if info then
						table.insert(team, {
							id = entry.id,
							uid = entry.uid,
							slotIndex = sNum,
							level = entry.level or 1,
							xp = entry.xp or 0,
							variant = entry.variant or "Normal",
							displayName = info.displayName or entry.id,
							element = info.element or "Fire",
							rarity = info.rarity or "Common",
						})
					end
					break
				end
			end
		end
		if #team >= MAX_BATTLE_TEAM_SIZE then break end
	end

	-- Sort by slotIndex so placement order is consistent
	table.sort(team, function(a, b) return a.slotIndex < b.slotIndex end)
	return team
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Get sorted BattlePoints from a folder
-- ═══════════════════════════════════════════════════════════════════════════════
local function getPointsSorted(folder)
	local pts = {}
	for _, child in ipairs(folder:GetChildren()) do
		if child:IsA("BasePart") then
			local n = child.Name:match("^BattlePoint(%d+)$")
			if n then table.insert(pts, { part = child, index = tonumber(n) }) end
		end
	end
	table.sort(pts, function(a, b) return a.index < b.index end)
	return pts
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Get the average center of a team's battle pads
-- ═══════════════════════════════════════════════════════════════════════════════
local function getTeamCenter(folder)
	if not folder then return nil end
	local pts = getPointsSorted(folder)
	if #pts == 0 then return nil end
	local sum = Vector3.zero
	for _, p in ipairs(pts) do sum = sum + p.part.Position end
	return sum / #pts
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Spawn a creature model on a BattlePoint
-- FIX #20: Now creates BillboardGui with name label, HP bar, and focus bar
-- matching ArenaSystem's spawnBattleCreature exactly.
-- @param creatureId     string
-- @param battlePoint    BasePart
-- @param team           string ("blue" or "red")
-- @param sizeMultiplier number
-- @param faceTowardPos  Vector3|nil
-- @param parentFolder   Instance
-- @param tag            string — CollectionService tag
-- @return Model|nil
-- ═══════════════════════════════════════════════════════════════════════════════
local function spawnBattleCreature(creatureId, battlePoint, team, sizeMultiplier, faceTowardPos, parentFolder, tag)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local rarityInfo = CreatureData.Rarities[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(180, 180, 180)

	local baseSize = 4 * (sizeMultiplier or 1)
	local teamColor = team == "blue" and Color3.fromRGB(60, 120, 255) or Color3.fromRGB(255, 70, 70)
	local spawnPos = battlePoint.Position + Vector3.new(0, baseSize / 2 + 1, 0)
	local battlePointTopY = battlePoint.Position.Y + (battlePoint.Size.Y * 0.5)

	local model = Instance.new("Model")
	model.Name = "GymArena_" .. info.id .. "_" .. team
	model:SetAttribute("Team", team)
	model:SetAttribute("CreatureId", creatureId)
	if tag and tag ~= "" then
		CollectionService:AddTag(model, tag)
	end

	local body, core
	local isCustomModel = false
	local options = { targetSize = baseSize, creatureId = creatureId }
	body, core, isCustomModel = CreatureModelLoader.LoadAndIntegrate(model, info.modelName, info.displayName, spawnPos, options)
	if body then
		core = core or model:FindFirstChild("Core")
	end

	if not body then
		body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(baseSize, baseSize, baseSize)
		body.Color = info.primaryColor
		body.Material = Enum.Material.Neon
		body.Anchored = true
		body.CanCollide = false
		body.CastShadow = true
		body.Position = spawnPos
		body.Parent = model

		core = Instance.new("Part")
		core.Name = "Core"
		core.Shape = Enum.PartType.Ball
		core.Size = Vector3.new(baseSize * 0.5, baseSize * 0.5, baseSize * 0.5)
		core.Color = rarityColor
		core.Material = Enum.Material.Neon
		core.Transparency = 0.25
		core.Anchored = true
		core.CanCollide = false
		core.CastShadow = false
		core.Position = spawnPos
		core.Parent = model
	end

	-- Team-colored ring at base
	local ring = Instance.new("Part")
	ring.Name = "TeamRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, baseSize * 1.8, baseSize * 1.8)
	ring.Color = teamColor
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.4
	ring.Anchored = true
	ring.CanCollide = false
	ring.CFrame = CFrame.new(battlePoint.Position + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model

	-- Light
	local light = Instance.new("PointLight")
	light.Color = info.primaryColor
	light.Brightness = 2
	light.Range = 14
	light.Parent = body

	-- Highlight (placeholder only; custom models show clean)
	if not isCustomModel then
		local hl = Instance.new("Highlight")
		hl.FillColor = rarityColor
		hl.FillTransparency = 0.75
		hl.OutlineColor = teamColor
		hl.OutlineTransparency = 0.1
		hl.Parent = model
	end

	-- FIX #20: Name + HP + Focus billboard (matching ArenaSystem exactly)
	local bb = Instance.new("BillboardGui")
	bb.Name = "InfoTag"
	bb.Adornee = body
	bb.Size = UDim2.new(0, 160, 0, 65)
	bb.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)
	bb.AlwaysOnTop = true
	bb.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "NameLabel"
	nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = info.displayName
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = bb

	local hpBar = Instance.new("Frame")
	hpBar.Name = "HPBarBG"
	hpBar.Size = UDim2.new(0.8, 0, 0.15, 0)
	hpBar.Position = UDim2.new(0.1, 0, 0.5, 0)
	hpBar.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
	hpBar.BorderSizePixel = 0
	hpBar.Parent = bb
	Instance.new("UICorner", hpBar).CornerRadius = UDim.new(0, 3)

	local hpFill = Instance.new("Frame")
	hpFill.Name = "HPFill"
	hpFill.Size = UDim2.new(1, 0, 1, 0)
	hpFill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
	hpFill.BorderSizePixel = 0
	hpFill.Parent = hpBar
	Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0, 3)

	local hpLabel = Instance.new("TextLabel")
	hpLabel.Name = "HPLabel"
	hpLabel.Size = UDim2.new(1, 0, 0.3, 0)
	hpLabel.Position = UDim2.new(0, 0, 0.7, 0)
	hpLabel.BackgroundTransparency = 1
	hpLabel.Text = info.health .. "/" .. info.health
	hpLabel.TextColor3 = Color3.fromRGB(200, 200, 200)
	hpLabel.TextScaled = true
	hpLabel.Font = Enum.Font.GothamMedium
	hpLabel.Parent = bb

	-- Focus bar (below HP)
	local focusBar = Instance.new("Frame")
	focusBar.Name = "FocusBarBG"
	focusBar.Size = UDim2.new(0.8, 0, 0.08, 0)
	focusBar.Position = UDim2.new(0.1, 0, 0.88, 0)
	focusBar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
	focusBar.BorderSizePixel = 0
	focusBar.Parent = bb
	Instance.new("UICorner", focusBar).CornerRadius = UDim.new(0, 2)

	local focusFill = Instance.new("Frame")
	focusFill.Name = "FocusFill"
	focusFill.Size = UDim2.new(0, 0, 1, 0)
	focusFill.BackgroundColor3 = Color3.fromRGB(255, 200, 80)
	focusFill.BorderSizePixel = 0
	focusFill.Parent = focusBar
	Instance.new("UICorner", focusFill).CornerRadius = UDim.new(0, 2)

	model.PrimaryPart = body
	model.Parent = parentFolder

	-- Place custom models so bottom sits on battle point (avoid clipping)
	if isCustomModel then
		local ok, bboxCf, bboxSize = pcall(function()
			return model:GetBoundingBox()
		end)
		if ok and bboxCf and bboxSize then
			local modelBottomY = bboxCf.Position.Y - bboxSize.Y * 0.5
			local lift = math.max(0, battlePointTopY - modelBottomY)
			if lift > 0 then
				model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
			end
		end
	end

	local rotOffset = CreatureData.GetModelRotationOffset(info) or CFrame.identity

	-- Billboard stud offset: ensure name tag stays at top of bounding box
	bb.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)

	-- Face toward enemy side on a flat XZ plane so models stay upright
	local pivotPos = model:GetPivot().Position
	local templateType = model:GetAttribute("TemplateType")
	local faceCf
	if faceTowardPos then
		if templateType == "Mesh" then
			faceCf = CFrame.new(pivotPos)
		else
			faceCf = CFrame.lookAt(pivotPos, Vector3.new(faceTowardPos.X, pivotPos.Y, faceTowardPos.Z))
		end
	else
		if templateType == "Mesh" then
			faceCf = CFrame.new(pivotPos)
		else
			local yaw = (team == "blue") and math.rad(180) or math.rad(-180)
			faceCf = CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0)
		end
	end
	model:PivotTo(faceCf * CFrame.Angles(FACING_X_CORRECTION, 0, 0) * rotOffset)

	CreatureAnimation.Setup(model, creatureId, "Idle")

	-- Idle bob
	task.spawn(function()
		local startY = body.Position.Y
		local coreY = core and core.Position.Y or startY
		local t = math.random() * math.pi * 2
		while model.Parent and body.Parent do
			local dt = RunService.Heartbeat:Wait()
			t = t + dt * 1.8 * math.pi
			local bob = math.sin(t) * 0.6
			body.Position = Vector3.new(body.Position.X, startY + bob, body.Position.Z)
			if core and core.Parent then
				core.Position = Vector3.new(core.Position.X, coreY + bob, core.Position.Z)
			end
		end
	end)

	return model
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- HP BAR UPDATE (matches ArenaSystem)
-- ═══════════════════════════════════════════════════════════════════════════════
local function updateHPBar(creatureData)
	if not creatureData.model or not creatureData.model.Parent then return end
	local bb = creatureData.model:FindFirstChild("InfoTag")
	if not bb then return end
	local fill = bb:FindFirstChild("HPBarBG") and bb.HPBarBG:FindFirstChild("HPFill")
	local label = bb:FindFirstChild("HPLabel")
	local pct = math.clamp(creatureData.hp / creatureData.maxHp, 0, 1)
	if fill then
		fill.Size = UDim2.new(pct, 0, 1, 0)
		if pct > 0.5 then
			fill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
		elseif pct > 0.25 then
			fill.BackgroundColor3 = Color3.fromRGB(220, 180, 40)
		else
			fill.BackgroundColor3 = Color3.fromRGB(220, 50, 50)
		end
	end
	if label then
		label.Text = math.max(0, math.floor(creatureData.hp)) .. "/" .. creatureData.maxHp
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- FOCUS BAR UPDATE (matches ArenaSystem)
-- ═══════════════════════════════════════════════════════════════════════════════
local function updateFocusBar(creatureData)
	if not creatureData.model or not creatureData.model.Parent then return end
	local bb = creatureData.model:FindFirstChild("InfoTag")
	if not bb then return end
	local focusBg = bb:FindFirstChild("FocusBarBG")
	if not focusBg then return end
	local fill = focusBg:FindFirstChild("FocusFill")
	if not fill then return end
	local pct = math.clamp((creatureData.focus or 0) / (creatureData.maxFocus or 100), 0, 1)
	fill.Size = UDim2.new(pct, 0, 1, 0)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ATTACK VISUAL (projectile + damage number — matches ArenaSystem)
-- ═══════════════════════════════════════════════════════════════════════════════
local function attackVisual(attackerData, defenderData, damage, arenaFolder)
	if not attackerData.model or not defenderData.model then return end
	local aBody = CreatureModelLoader.GetBodyPart(attackerData.model) or attackerData.model:FindFirstChild("Body")
	local dBody = CreatureModelLoader.GetBodyPart(defenderData.model) or defenderData.model:FindFirstChild("Body")
	if not aBody or not dBody then return end

	-- Projectile bolt
	local bolt = Instance.new("Part")
	bolt.Shape = Enum.PartType.Ball
	bolt.Size = Vector3.new(1.5, 1.5, 1.5)
	bolt.Color = aBody.Color
	bolt.Material = Enum.Material.Neon
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.Position = aBody.Position
	bolt.Parent = arenaFolder

	local boltLight = Instance.new("PointLight")
	boltLight.Color = bolt.Color
	boltLight.Brightness = 3
	boltLight.Range = 10
	boltLight.Parent = bolt

	task.spawn(function()
		local from = aBody.Position
		local to = dBody.Position
		local dist = (to - from).Magnitude
		local dur = math.clamp(dist / 80, 0.08, 0.3)
		local startT = tick()
		while tick() - startT < dur do
			local a = (tick() - startT) / dur
			bolt.Position = from:Lerp(to, a)
			RunService.Heartbeat:Wait()
		end

		-- Impact flash on target
		if dBody.Parent then
			local origColor = dBody.Color
			dBody.Color = Color3.fromRGB(255, 50, 50)
			task.wait(0.12)
			if dBody.Parent then dBody.Color = origColor end
		end

		bolt:Destroy()
	end)

	-- Damage number
	task.spawn(function()
		task.wait(0.15) -- slight delay for bolt travel
		if not dBody.Parent then return end
		local dmgPart = Instance.new("Part")
		dmgPart.Size = Vector3.new(0.1, 0.1, 0.1)
		dmgPart.Transparency = 1
		dmgPart.Anchored = true
		dmgPart.CanCollide = false
		dmgPart.Position = dBody.Position + Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))
		dmgPart.Parent = arenaFolder

		local dmgBb = Instance.new("BillboardGui")
		dmgBb.Size = UDim2.new(0, 70, 0, 28)
		dmgBb.Adornee = dmgPart
		dmgBb.AlwaysOnTop = true
		dmgBb.Parent = dmgPart

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "-" .. math.floor(damage)
		lbl.TextColor3 = Color3.fromRGB(255, 80, 60)
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextStrokeTransparency = 0.3
		lbl.Parent = dmgBb

		for i = 1, 25 do
			dmgPart.Position = dmgPart.Position + Vector3.new(0, 0.08, 0)
			lbl.TextTransparency = i / 25
			lbl.TextStrokeTransparency = 0.3 + (i / 25) * 0.7
			RunService.Heartbeat:Wait()
		end
		dmgPart:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SPECIAL ATTACK VISUAL (element-based particles — matches ArenaSystem)
-- ═══════════════════════════════════════════════════════════════════════════════
local function specialAttackVisual(attackerData, defenderData, element, damage, arenaFolder)
	if not attackerData.model or not defenderData.model then return end
	local aBody = CreatureModelLoader.GetBodyPart(attackerData.model) or attackerData.model:FindFirstChild("Body")
	local dBody = CreatureModelLoader.GetBodyPart(defenderData.model) or defenderData.model:FindFirstChild("Body")
	if not aBody or not dBody then return end

	local elemColor = ELEMENT_COLORS[element] or aBody.Color
	local fromPos = aBody.Position
	local toPos = dBody.Position

	local function makeOrb(pos, size, color, parent)
		local p = Instance.new("Part")
		p.Shape = Enum.PartType.Ball
		p.Size = Vector3.new(size, size, size)
		p.Color = color
		p.Material = Enum.Material.Neon
		p.Anchored = true
		p.CanCollide = false
		p.Position = pos
		p.Parent = parent or arenaFolder
		return p
	end

	-- Fire: Rising flame burst + projectile wave
	if element == "Fire" then
		task.spawn(function()
			for i = 1, 5 do
				local orb = makeOrb(fromPos + Vector3.new(math.random(-2, 2), 0, math.random(-2, 2)), 1.5 + i * 0.5, elemColor)
				local startY = orb.Position.Y
				for f = 1, 15 do
					if orb.Parent then orb.Position = Vector3.new(orb.Position.X, startY + f * 0.8, orb.Position.Z); orb.Transparency = f / 15 end
					RunService.Heartbeat:Wait()
				end
				orb:Destroy()
			end
			local fbolt = makeOrb(fromPos, 3, elemColor)
			local dur = 0.4
			local s = tick()
			while tick() - s < dur do
				fbolt.Position = fromPos:Lerp(toPos, (tick() - s) / dur)
				RunService.Heartbeat:Wait()
			end
			if dBody.Parent then local oc = dBody.Color; dBody.Color = Color3.fromRGB(255, 150, 50); task.wait(0.2); if dBody.Parent then dBody.Color = oc end end
			fbolt:Destroy()
		end)
	end

	-- Ice: Ice crystal grows, shoots, target gets frost
	if element == "Ice" then
		task.spawn(function()
			local crystal = Instance.new("Part")
			crystal.Shape = Enum.PartType.Cylinder
			crystal.Size = Vector3.new(1, 2, 2)
			crystal.Color = elemColor
			crystal.Material = Enum.Material.Ice
			crystal.Anchored = true
			crystal.CanCollide = false
			crystal.CFrame = CFrame.new(fromPos) * CFrame.Angles(0, 0, math.rad(90))
			crystal.Parent = arenaFolder
			for i = 1, 12 do
				crystal.Size = Vector3.new(1 + i * 0.3, 2 + i * 0.5, 2 + i * 0.5)
				RunService.Heartbeat:Wait()
			end
			local dur = 0.35
			local s = tick()
			while tick() - s < dur do
				crystal.CFrame = CFrame.new(fromPos:Lerp(toPos, (tick() - s) / dur)) * CFrame.Angles(0, 0, math.rad(90))
				RunService.Heartbeat:Wait()
			end
			crystal:Destroy()
			if dBody.Parent then
				local origC, origM = dBody.Color, dBody.Material
				dBody.Color = Color3.fromRGB(180, 220, 255)
				dBody.Material = Enum.Material.Ice
				task.wait(0.25)
				if dBody.Parent then dBody.Color = origC; dBody.Material = origM end
			end
		end)
	end

	-- Earth: Ground crack + stone spike projectile
	if element == "Earth" then
		task.spawn(function()
			local spike = Instance.new("Part")
			spike.Shape = Enum.PartType.Ball
			spike.Size = Vector3.new(2, 4, 2)
			spike.Color = elemColor
			spike.Material = Enum.Material.Slate
			spike.Anchored = true
			spike.CanCollide = false
			spike.Position = fromPos + Vector3.new(0, 2, 0)
			spike.Parent = arenaFolder
			for i = 1, 8 do spike.Size = spike.Size + Vector3.new(0.2, 0.4, 0.2); RunService.Heartbeat:Wait() end
			local dur = 0.4
			local s = tick()
			while tick() - s < dur do
				spike.Position = (fromPos + Vector3.new(0, 2, 0)):Lerp(toPos + Vector3.new(0, 2, 0), (tick() - s) / dur)
				RunService.Heartbeat:Wait()
			end
			if dBody.Parent then local oc = dBody.Color; dBody.Color = Color3.fromRGB(140, 120, 80); task.wait(0.15); if dBody.Parent then dBody.Color = oc end end
			spike:Destroy()
		end)
	end

	-- Wind: Swirling cyclone from attacker to target
	if element == "Wind" then
		task.spawn(function()
			local orbs = {}
			for i = 1, 8 do
				local o = makeOrb(fromPos + Vector3.new(math.cos(i * 0.8) * 2, 1, math.sin(i * 0.8) * 2), 1.2, elemColor)
				o.Transparency = 0.5
				table.insert(orbs, { part = o, angle = i * 0.8 })
			end
			local dur = 0.5
			local s = tick()
			while tick() - s < dur do
				local t = (tick() - s) / dur
				for _, orbData in ipairs(orbs) do
					local mid = fromPos:Lerp(toPos, t)
					orbData.angle = orbData.angle + 0.3
					orbData.part.Position = mid + Vector3.new(math.cos(orbData.angle) * 3, math.sin(orbData.angle * 2) * 1, math.sin(orbData.angle) * 3)
				end
				RunService.Heartbeat:Wait()
			end
			for _, orbData in ipairs(orbs) do orbData.part:Destroy() end
			if dBody.Parent then local oc = dBody.Color; dBody.Color = Color3.fromRGB(200, 255, 220); task.wait(0.1); if dBody.Parent then dBody.Color = oc end end
		end)
	end

	-- Shadow / Lightning / Water / Light / Psychic / others: Enhanced projectile
	if element == "Shadow" or element == "Lightning" or element == "Water" or element == "Light" or element == "Psychic" or not ELEMENT_COLORS[element] then
		task.spawn(function()
			local sBolt = makeOrb(fromPos, 3.5, elemColor)
			local sLight = Instance.new("PointLight")
			sLight.Color = elemColor
			sLight.Brightness = 5
			sLight.Range = 15
			sLight.Parent = sBolt
			local dur = 0.4
			local s = tick()
			while tick() - s < dur do
				sBolt.Position = fromPos:Lerp(toPos, (tick() - s) / dur)
				RunService.Heartbeat:Wait()
			end
			if dBody.Parent then local oc = dBody.Color; dBody.Color = elemColor; task.wait(0.15); if dBody.Parent then dBody.Color = oc end end
			sBolt:Destroy()
		end)
	end

	-- Damage number (same as normal attack, slightly larger + element colored)
	task.spawn(function()
		task.wait(0.35)
		if not dBody or not dBody.Parent then return end
		local dmgPart = Instance.new("Part")
		dmgPart.Size = Vector3.new(0.1, 0.1, 0.1)
		dmgPart.Transparency = 1
		dmgPart.Anchored = true
		dmgPart.CanCollide = false
		dmgPart.Position = dBody.Position + Vector3.new(math.random(-2, 2), 3, math.random(-2, 2))
		dmgPart.Parent = arenaFolder

		local dmgBb = Instance.new("BillboardGui")
		dmgBb.Size = UDim2.new(0, 90, 0, 36)
		dmgBb.Adornee = dmgPart
		dmgBb.AlwaysOnTop = true
		dmgBb.Parent = dmgPart

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "-" .. math.floor(damage) .. "!"
		lbl.TextColor3 = elemColor
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextStrokeTransparency = 0.2
		lbl.Parent = dmgBb

		for i = 1, 30 do
			dmgPart.Position = dmgPart.Position + Vector3.new(0, 0.1, 0)
			lbl.TextTransparency = i / 30
			lbl.TextStrokeTransparency = 0.2 + (i / 30) * 0.8
			RunService.Heartbeat:Wait()
		end
		dmgPart:Destroy()
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- DEATH VISUAL (shrink + fade — matches ArenaSystem)
-- ═══════════════════════════════════════════════════════════════════════════════
local function deathVisual(creatureData)
	if not creatureData.model or not creatureData.model.Parent then return end
	local body = CreatureModelLoader.GetBodyPart(creatureData.model) or creatureData.model:FindFirstChild("Body")
	if not body then return end

	task.spawn(function()
		for i = 1, 15 do
			if not body.Parent then return end
			local s = body.Size * 0.9
			body.Size = s
			body.Transparency = i / 15
			local coreP = creatureData.model and creatureData.model:FindFirstChild("Core")
			if coreP then coreP.Size = s * 0.5; coreP.Transparency = i / 15 end
			RunService.Heartbeat:Wait()
		end
		if body.Parent then body.Transparency = 1 end
	end)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- STATE BROADCAST (sends HP/focus/alive to participants for client HUD)
-- ═══════════════════════════════════════════════════════════════════════════════
local function broadcastGymState(owner, challenger, ownerCreatures, challengerCreatures, plotName)
	if not eventsFolder then return end
	local evt = eventsFolder:FindFirstChild("GymBattleStateUpdate")
	if not evt then return end

	local red = {}
	for _, c in ipairs(ownerCreatures) do
		table.insert(red, {
			team = "red",
			pointIndex = c.pointIndex,
			creatureId = c.creatureId,
			uid = c.uid,
			hp = c.hp,
			maxHp = c.maxHp,
			focus = c.focus or 0,
			maxFocus = c.maxFocus or (GameConfig.FocusMax or 100),
			alive = c.alive == true,
			attack = c.attack,
			speed = c.speed,
		})
	end

	local blue = {}
	for _, c in ipairs(challengerCreatures) do
		table.insert(blue, {
			team = "blue",
			pointIndex = c.pointIndex,
			creatureId = c.creatureId,
			uid = c.uid,
			hp = c.hp,
			maxHp = c.maxHp,
			focus = c.focus or 0,
			maxFocus = c.maxFocus or (GameConfig.FocusMax or 100),
			alive = c.alive == true,
			attack = c.attack,
			speed = c.speed,
		})
	end

	local payload = {
		red = red,
		blue = blue,
		plotName = plotName,
		t = os.clock(),
	}

	if owner and owner.Parent then evt:FireClient(owner, payload) end
	if challenger and challenger.Parent then evt:FireClient(challenger, payload) end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Spawn a team using formation-based placement (matches ArenaSystem)
-- FIX #20: Uses entry.slotIndex to place on matching BattlePoint, not sequential i.
-- @param team        table[]  — array from getPlayerBattleTeam
-- @param teamFolder  Folder   — RedTeam or BlueTeam containing BattlePoint1..9
-- @param teamName    string   — "red" or "blue"
-- @param enemyFolder Folder   — the opposing team folder (for facing direction)
-- @param tag         string   — CollectionService tag for cleanup
-- @return table[]    — spawned creature state (with .model reference)
-- ═══════════════════════════════════════════════════════════════════════════════
local function spawnTeam(team, teamFolder, teamName, enemyFolder, tag)
	local points = getPointsSorted(teamFolder)
	local faceTowardPos = getTeamCenter(enemyFolder)
	-- Build a map: pointIndex -> part for direct slot lookup
	local pointMap = {}
	for _, p in ipairs(points) do pointMap[p.index] = p.part end

	local spawned = {}

	for _, entry in ipairs(team) do
		local slotIdx = entry.slotIndex or 0
		-- Find the matching BattlePoint for this slot
		local targetPoint = pointMap[slotIdx]
		-- Fallback: if no matching point, use next available
		if not targetPoint then
			for _, p in ipairs(points) do
				local taken = false
				for _, pl in ipairs(spawned) do
					if pl.pointIndex == p.index then taken = true; break end
				end
				if not taken then targetPoint = p.part; slotIdx = p.index; break end
			end
		end
		if not targetPoint then break end -- no more points

		local info = CreatureData.GetById(entry.id)
		if info then
			local model = spawnBattleCreature(entry.id, targetPoint, teamName, 1, faceTowardPos, teamFolder, tag)
			if model then
				-- Use GetEffectiveStats so level + variant (Silver/Gold/Legend) apply
				local variant = entry.variant or "Normal"
				local stats = PlayerDataManager.GetEffectiveStats(entry.id, entry.level or 1, variant)
				local lvl = entry.level or 1
				local maxFocus = GameConfig.FocusMax or 100

				if stats then
					-- Update the billboard HP text with actual stats
					local bb = model:FindFirstChild("InfoTag")
					if bb then
						local hpLbl = bb:FindFirstChild("HPLabel")
						if hpLbl then
							hpLbl.Text = stats.health .. "/" .. stats.health
						end
					end

					table.insert(spawned, {
						model = model,
						creatureId = entry.id,
						uid = entry.uid or ("gym_" .. slotIdx),
						displayName = entry.displayName or info.displayName or entry.id,
						hp = stats.health,
						maxHp = stats.health,
						attack = stats.attack,
						defense = stats.defense,
						speed = stats.speed,
						level = lvl,
						alive = true,
						team = teamName,
						pointIndex = slotIdx,
						element = info.element or "Fire",
						-- Focus bar
						focus = 0,
						maxFocus = maxFocus,
						-- Status effects
						burnRounds = 0,
						frozen = false,
						dmgReductionRounds = 0,
					})
				end
			end
		end
	end

	return spawned
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Clear all tagged battle creatures
-- ═══════════════════════════════════════════════════════════════════════════════
local function clearGymCreatures(tag)
	for _, obj in ipairs(CollectionService:GetTagged(tag)) do
		pcall(function() obj:Destroy() end)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Helper: Notify a player via the standard notification system
-- ═══════════════════════════════════════════════════════════════════════════════
local function notifyClient(player, msg, level)
	if not eventsFolder then return end
	local evt = eventsFolder:FindFirstChild("ShowNotification")
	if evt then
		evt:FireClient(player, msg, level or "info", "arena")
	end
end

local function rejectClient(player, title, msg, level)
	if not player or not player.Parent then return end
	if not eventsFolder then
		notifyClient(player, msg or title, level or "error")
		return
	end

	local evt = eventsFolder:FindFirstChild("BaseGymReject")
	if evt then
		evt:FireClient(player, title or "Siegelord Arena unavailable", msg or "You cannot challenge this base gym right now.", level or "error")
		return
	end

	notifyClient(player, msg or title, level or "error")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- runGymBattle(plotModel, owner, challenger)
-- Isolated battle loop for a single Floor 4 arena. Runs on a spawned thread.
-- Does NOT touch ArenaSystem's global state — fully independent.
--
-- FIX #20: Battle loop now matches ArenaSystem exactly — per-creature turns
-- sorted by speed, attack/special animations, HP/focus bars, elemental effects,
-- burn/freeze/earth debuffs, death visuals, damage numbers, and state broadcasts.
--
-- @param plotModel  Model — the Plot model containing Floor4/BaseGym
-- @param owner      Player — the base owner (Red team)
-- @param challenger Player — the visiting challenger (Blue team)
-- ═══════════════════════════════════════════════════════════════════════════════
local function runGymBattle(plotModel, owner, challenger)
	local plotName = plotModel.Name
	local battleTag = GYM_TAG .. "_" .. plotName

	-- Get both teams
	local ownerTeam = getPlayerBattleTeam(owner)
	local challengerTeam = getPlayerBattleTeam(challenger)

	if #ownerTeam == 0 then
		rejectClient(challenger, "Opponent has no battle team", owner.Name .. " has no battle team set for their Siegelord Arena yet.", "error")
		return
	end
	if #challengerTeam == 0 then
		rejectClient(challenger, "Battle team required", "You need a battle team to challenge another player's Siegelord Arena.", "error")
		return
	end

	-- Find arena folders
	local floor4 = plotModel:FindFirstChild("Floor4")
	if not floor4 then return end
	local arena = floor4:FindFirstChild("BaseGym")
	if not arena then return end
	local ownerFolder = arena:FindFirstChild("RedTeam")
	local challengerFolder = arena:FindFirstChild("BlueTeam")
	if not ownerFolder or not challengerFolder then
		rejectClient(challenger, "Arena setup incomplete", "This Siegelord Arena is missing its battle pads. Try again later.", "error")
		return
	end

	-- Mark battle in progress (plot-level + per-player tracking)
	-- FIX #21: Also set OwnerUserId/ChallengerUserId so GymJumbotronClient
	-- can find the player characters for the live follow-camera feeds.
	activeBattles[plotName] = true
	plotModel:SetAttribute("GymBattleInProgress", true)
	plotModel:SetAttribute("GymOwnerUserId", owner.UserId)
	plotModel:SetAttribute("GymChallengerUserId", challenger.UserId)
	activeGymPlayers[owner.UserId] = plotName
	activeGymPlayers[challenger.UserId] = plotName

	-- Announce — fire prominent start banner to both participants
	local gymStartEvt = eventsFolder and eventsFolder:FindFirstChild("BaseGymStart")
	if gymStartEvt then
		gymStartEvt:FireClient(owner, owner.Name, challenger.Name, "defense")
		gymStartEvt:FireClient(challenger, owner.Name, challenger.Name, "challenge")
	end
	task.wait(2)

	-- Spawn teams (formation-based via slotIndex)
	local ownerCreatures = spawnTeam(ownerTeam, ownerFolder, "red", challengerFolder, battleTag)
	local challengerCreatures = spawnTeam(challengerTeam, challengerFolder, "blue", ownerFolder, battleTag)

	-- ── State tracking for broadcast throttle ───────────────────────────────
	local stateDirty = false
	local lastStateBroadcast = 0

	local function maybeBroadcast()
		if stateDirty and (os.clock() - lastStateBroadcast) >= STATE_BROADCAST_MIN_INTERVAL then
			lastStateBroadcast = os.clock()
			stateDirty = false
			broadcastGymState(owner, challenger, ownerCreatures, challengerCreatures, plotName)
		end
	end

	-- Send initial state snapshot
	stateDirty = true
	lastStateBroadcast = 0
	broadcastGymState(owner, challenger, ownerCreatures, challengerCreatures, plotName)

	-- ── Auto-battle loop (matches ArenaSystem per-creature turn order) ──────
	-- Combine all creatures and sort by speed (fastest acts first)
	local allCreatures = {}
	for _, c in ipairs(ownerCreatures) do table.insert(allCreatures, c) end
	for _, c in ipairs(challengerCreatures) do table.insert(allCreatures, c) end
	table.sort(allCreatures, function(a, b) return a.speed > b.speed end)

	local battleActive = true
	local round = 0

	while battleActive do
		round = round + 1

		-- Check win condition
		local ownerAliveCount = 0
		local challengerAliveCount = 0
		for _, c in ipairs(ownerCreatures) do if c.alive then ownerAliveCount += 1 end end
		for _, c in ipairs(challengerCreatures) do if c.alive then challengerAliveCount += 1 end end

		if ownerAliveCount == 0 or challengerAliveCount == 0 then break end

		-- Both players must still be in game
		if not owner.Parent or not challenger.Parent then break end

		-- Each creature attacks in speed order
		for _, attacker in ipairs(allCreatures) do
			if not attacker.alive or not battleActive then continue end

			-- Frozen: skip this turn
			if attacker.frozen then
				attacker.frozen = false
				task.wait(0.15)
				continue
			end

			-- Apply burn damage at start of turn
			if attacker.burnRounds and attacker.burnRounds > 0 then
				local burnDmg = math.max(1, math.floor(attacker.maxHp * (GameConfig.BurnDamagePerRound or 0.08)))
				attacker.hp = attacker.hp - burnDmg
				attacker.burnRounds = attacker.burnRounds - 1
				updateHPBar(attacker)
				stateDirty = true
				-- Small burn visual flash
				if attacker.model and attacker.model.Parent then
					local body = CreatureModelLoader.GetBodyPart(attacker.model) or attacker.model:FindFirstChild("Body")
					if body then
						local oc = body.Color
						body.Color = Color3.fromRGB(255, 100, 50)
						task.defer(function() task.wait(0.1) if body and body.Parent then body.Color = oc end end)
					end
				end
				if attacker.hp <= 0 then
					attacker.alive = false
					deathVisual(attacker)
				end
				maybeBroadcast()
				task.wait(0.2)
				if not attacker.alive then continue end
			end

			-- Pick target from opposite team (lowest HP)
			local targets = attacker.team == "red" and challengerCreatures or ownerCreatures
			local target = nil
			local lowestHP = math.huge
			for _, t in ipairs(targets) do
				if t.alive and t.hp < lowestHP then
					lowestHP = t.hp
					target = t
				end
			end

			if not target then continue end

			-- Damage calc: atk - def/3 with minimum of 1
			local dmg = math.max(1, attacker.attack - (target.defense or 0) / 3)
			-- Earth special: target takes reduced damage
			if target.dmgReductionRounds and target.dmgReductionRounds > 0 then
				dmg = dmg * (1 - (GameConfig.EarthDmgReduction or 0.25))
				target.dmgReductionRounds = target.dmgReductionRounds - 1
			end
			-- Elemental weakness multiplier
			local elemMult = CreatureData.GetElementalDamageMultiplier(attacker.element or "Fire", target.element or "Fire")
			if elemMult > 1 then
				dmg = dmg * (GameConfig.ElementalAdvantageMultiplier or elemMult)
			elseif elemMult < 1 then
				dmg = dmg * (GameConfig.ElementalDisadvantageMultiplier or elemMult)
			end
			-- Small random variance
			dmg = dmg * (0.85 + math.random() * 0.3)
			dmg = math.floor(math.max(1, dmg))

			local isSpecial = (attacker.focus or 0) >= (attacker.maxFocus or 100)
			local elem = attacker.element or "Fire"

			if isSpecial then
				-- SPECIAL ATTACK: reset focus, apply element effect, play slow animation
				attacker.focus = 0
				updateFocusBar(attacker)
				CreatureAnimation.PlayAnimation(attacker.model, "Special", attacker.creatureId)

				-- Apply element-specific debuffs (before damage)
				if elem == "Fire" then
					target.burnRounds = GameConfig.BurnDuration or 3
				elseif elem == "Ice" then
					target.frozen = true
				elseif elem == "Earth" then
					target.dmgReductionRounds = GameConfig.EarthDebuffDuration or 3
				elseif elem == "Wind" then
					target.focus = math.max(0, (target.focus or 0) - (GameConfig.WindFocusDrain or 50))
					updateFocusBar(target)
				elseif elem == "Water" then
					-- Water special: attacker gains HP
					local healPct = GameConfig.WaterHealPercent or 0.20
					local healAmt = math.floor((attacker.maxHp or attacker.hp) * healPct)
					attacker.hp = math.min(attacker.maxHp or attacker.hp, (attacker.hp or 0) + healAmt)
					updateHPBar(attacker)
				end

				specialAttackVisual(attacker, target, elem, dmg, arena)
				target.hp = target.hp - dmg
				updateHPBar(target)
				stateDirty = true
				maybeBroadcast()

				-- Slow the battle for special attack
				task.wait(GameConfig.SpecialAttackDuration or 2.5)
			else
				-- Normal attack
				CreatureAnimation.PlayAnimation(attacker.model, "Attack", attacker.creatureId)
				target.hp = target.hp - dmg
				attackVisual(attacker, target, dmg, arena)
				updateHPBar(target)

				-- Gain focus
				attacker.focus = math.min(attacker.maxFocus or 100, (attacker.focus or 0) + (GameConfig.FocusGainPerAttack or 25))
				updateFocusBar(attacker)
				stateDirty = true
				maybeBroadcast()

				task.wait(TICK_SPEED / math.max(1, #allCreatures / 3))
			end

			if target.hp <= 0 then
				target.alive = false
				deathVisual(target)
				stateDirty = true
				maybeBroadcast()
			end
		end

		-- Small pause between rounds
		task.wait(0.3)
	end

	-- ── Determine winner ─────────────────────────────────────────────────────
	local ownerAlive = 0
	local challengerAlive = 0
	for _, c in ipairs(ownerCreatures) do if c.alive then ownerAlive += 1 end end
	for _, c in ipairs(challengerCreatures) do if c.alive then challengerAlive += 1 end end

	local ownerWon = ownerAlive > challengerAlive
	local winner = ownerWon and owner or challenger
	local loser = ownerWon and challenger or owner

	-- Final state broadcast
	stateDirty = true
	lastStateBroadcast = 0
	broadcastGymState(owner, challenger, ownerCreatures, challengerCreatures, plotName)

	-- ── Bounty + Reward logic ───────────────────────────────────────────────
	local bountyData = getBounty(plotName)
	local currentBounty = bountyData.amount
	local winnerCoins = 0
	local loserCoins = 0
	local bountyPaid = 0
	local newBounty = currentBounty

	local coinsEvt = eventsFolder and eventsFolder:FindFirstChild("CoinsUpdate")

	if ownerWon then
		-- Owner defended: earns defense income + bounty grows
		winnerCoins = WIN_GOLD + OWNER_DEFENSE_PAY
		loserCoins = CHALLENGER_LOSE_PAY
		growBounty(plotName)
		newBounty = getBounty(plotName).amount
	else
		-- Challenger won: takes the bounty + flat win gold; bounty resets
		bountyPaid = currentBounty
		winnerCoins = WIN_GOLD + bountyPaid
		loserCoins = 0  -- owner loses bounty, no consolation
		resetBounty(plotName)
		newBounty = getBounty(plotName).amount
	end

	-- Pay winner
	if winner.Parent then
		local data = PlayerDataManager.GetData(winner)
		if data then
			data.coins = (data.coins or 0) + winnerCoins
			if coinsEvt then coinsEvt:FireClient(winner, data.coins) end
		end
	end
	-- Pay loser consolation (if any)
	if loserCoins > 0 and loser.Parent then
		local data = PlayerDataManager.GetData(loser)
		if data then
			data.coins = (data.coins or 0) + loserCoins
			if coinsEvt then coinsEvt:FireClient(loser, data.coins) end
		end
	end

	-- ── Fire completion screen event to both players ────────────────────────
	local resultEvt = eventsFolder and eventsFolder:FindFirstChild("BaseGymResult")
	if resultEvt then
		local resultData = {
			gym = true,
			gymName = owner.Name .. "'s Siegelord Arena",
			winner = winner.Name,
			loser = loser.Name,
			ownerName = owner.Name,
			challengerName = challenger.Name,
			ownerWon = ownerWon,
			bountyBefore = currentBounty,
			bountyAfter = newBounty,
			bountyPaid = bountyPaid,
			defenseWins = getBounty(plotName).defenseWins,
			winnerReward = {
				coins = winnerCoins,
				baseCoins = WIN_GOLD,
				bountyCoins = bountyPaid,
				defensePay = ownerWon and OWNER_DEFENSE_PAY or 0,
			},
			loserReward = loserCoins > 0 and {
				coins = loserCoins,
				consolation = true,
			} or nil,
			ownerAlive = ownerAlive,
			challengerAlive = challengerAlive,
		}
		if owner.Parent then resultEvt:FireClient(owner, resultData) end
		if challenger.Parent then resultEvt:FireClient(challenger, resultData) end
	end

	-- ── Cleanup ──────────────────────────────────────────────────────────────
	task.wait(3)
	clearGymCreatures(battleTag)
	activeBattles[plotName] = nil
	plotModel:SetAttribute("GymBattleInProgress", nil)
	plotModel:SetAttribute("GymOwnerUserId", nil)
	plotModel:SetAttribute("GymChallengerUserId", nil)
	activeGymPlayers[owner.UserId] = nil
	activeGymPlayers[challenger.UserId] = nil

	-- Set cooldown
	cooldowns[challenger.UserId .. "_" .. plotName] = tick()

	-- Refresh battle orbs on owner's Floor 2 BattlePoints (NOT a full PlaceCreatures —
	-- we only need to respawn the battle orbs, not all income/defense creatures)
	if BasePlacementSystem and BasePlacementSystem.RespawnBattleCreatures and owner.Parent then
		pcall(function() BasePlacementSystem.RespawnBattleCreatures(owner) end)
	end

	print("[GymBattle] " .. winner.Name .. " won gym battle on " .. plotName
		.. " | bounty: " .. currentBounty .. " -> " .. newBounty
		.. (bountyPaid > 0 and (" | bounty claimed: " .. bountyPaid) or ""))
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- setupPlotArena(plotModel)
-- Creates a ProximityPrompt on the GymCenter of Floor4/BaseGym for visitor challenges.
-- Called when Floor 4 becomes visible (on purchase or server start for owners).
--
-- @param plotModel Model — the Plot model
-- ═══════════════════════════════════════════════════════════════════════════════
local function setupPlotArena(plotModel)
	local floor4 = plotModel:FindFirstChild("Floor4")
	if not floor4 then return end
	local arena = floor4:FindFirstChild("BaseGym")
	if not arena then return end
	local center = arena:FindFirstChild("GymCenter")
	if not center or not center:IsA("BasePart") then return end

	-- Don't create duplicate prompts
	if center:FindFirstChildOfClass("ProximityPrompt") then return end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "GymBattlePrompt"
	prompt.ActionText = "Challenge Gym"
	prompt.ObjectText = "Siegelord Arena"
	prompt.HoldDuration = 0.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = center

	prompt.Triggered:Connect(function(challenger)
		local owner = getPlotOwner(plotModel)
		if not owner then
			rejectClient(challenger, "Arena unavailable", "The base owner could not be found for this Siegelord Arena.", "error")
			return
		end

		-- Can't challenge your own gym
		if challenger == owner then
			rejectClient(challenger, "Cannot challenge your own arena", "You can't challenge your own Siegelord Arena.", "info")
			return
		end

		-- FIX: Block gym battle if global Arena battle is active (mutual exclusion)
		if workspace:GetAttribute("ArenaBattleInProgress") then
			rejectClient(challenger, "Arena busy", "An arena battle is already in progress. Try the Siegelord Arena again after it ends.", "info")
			return
		end

		-- Check if battle already in progress on this plot
		if activeBattles[plotModel.Name] then
			rejectClient(challenger, "Siegelord Arena occupied", "A base gym battle is already happening here right now.", "info")
			return
		end

		-- Check cooldown
		local cdKey = challenger.UserId .. "_" .. plotModel.Name
		local lastBattle = cooldowns[cdKey]
		if lastBattle and (tick() - lastBattle) < COOLDOWN then
			local remaining = math.ceil(COOLDOWN - (tick() - lastBattle))
			rejectClient(challenger, "Gym cooldown", "You must wait " .. remaining .. "s before challenging this base gym again.", "info")
			return
		end

		-- Check challenger has a battle team
		local cTeam = getPlayerBattleTeam(challenger)
		if #cTeam == 0 then
			rejectClient(challenger, "Battle team required", "You need a battle team before you can challenge another player's base gym.", "error")
			return
		end

		-- Check owner has a battle team
		local oTeam = getPlayerBattleTeam(owner)
		if #oTeam == 0 then
			rejectClient(challenger, "Opponent has no battle team", owner.Name .. " has not set up a battle team for their base gym yet.", "error")
			return
		end

		-- Start the battle on a separate thread
		task.spawn(function()
			local ok, err = pcall(runGymBattle, plotModel, owner, challenger)
			if not ok then
				warn("[GymBattle] Error on " .. plotModel.Name .. ": " .. tostring(err))
				rejectClient(challenger, "Arena error", "The Siegelord Arena could not start right now. Please try again.", "error")
				activeBattles[plotModel.Name] = nil
				plotModel:SetAttribute("GymBattleInProgress", nil)
				activeGymPlayers[owner.UserId] = nil
				activeGymPlayers[challenger.UserId] = nil
				clearGymCreatures(GYM_TAG .. "_" .. plotModel.Name)
			end
		end)
	end)

	print("[GymBattle] Arena prompt set up on " .. plotModel.Name)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- ScanAllPlots()
-- Scans workspace.BasePlots for any plots that have Floor4/BaseGym and sets up
-- ProximityPrompts on them. Called during Init and can be called again when
-- a player purchases Floor 4.
-- ═══════════════════════════════════════════════════════════════════════════════
function GymBattleSystem.ScanAllPlots()
	local plotsFolder = Workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return end

	for _, plotModel in ipairs(plotsFolder:GetChildren()) do
		setupPlotArena(plotModel)
	end
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SetupPlot(plotModel)
-- Public API: set up a single plot's gym arena (called after floor purchase).
-- @param plotModel Model — the Plot model
-- ═══════════════════════════════════════════════════════════════════════════════
function GymBattleSystem.SetupPlot(plotModel)
	setupPlotArena(plotModel)
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- IsPlayerInGymBattle(player)
-- Public API: returns true if the given player is currently fighting in any
-- gym battle (as owner or challenger). Used by ArenaSystem to delay arena
-- rounds until involved players finish their gym battle.
--
-- @param player Player
-- @return boolean
-- ═══════════════════════════════════════════════════════════════════════════════
function GymBattleSystem.IsPlayerInGymBattle(player)
	return activeGymPlayers[player.UserId] ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- AnyGymBattleActive()
-- Public API: returns true if ANY gym battle is running on any plot.
-- @return boolean
-- ═══════════════════════════════════════════════════════════════════════════════
function GymBattleSystem.AnyGymBattleActive()
	return next(activeBattles) ~= nil
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- GetPlotBounty(plotName)
-- Public API: returns the current bounty amount for a plot's gym.
-- @param plotName string — e.g. "Plot1"
-- @return number — current bounty in coins
-- ═══════════════════════════════════════════════════════════════════════════════
function GymBattleSystem.GetPlotBounty(plotName)
	return getBounty(plotName).amount
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- Init(playerDataMgr, basePlacementSys)
-- Called from MainServer after BasePlacementSystem.
-- @param playerDataMgr   PlayerDataManager module
-- @param basePlacementSys BasePlacementSystem module
-- ═══════════════════════════════════════════════════════════════════════════════
function GymBattleSystem.Init(playerDataMgr, basePlacementSys)
	PlayerDataManager = playerDataMgr
	BasePlacementSystem = basePlacementSys

	eventsFolder = ReplicatedStorage:FindFirstChild("Events")

	-- Create GymBattleStateUpdate RemoteEvent if it doesn't exist
	if eventsFolder and not eventsFolder:FindFirstChild("GymBattleStateUpdate") then
		local evt = Instance.new("RemoteEvent")
		evt.Name = "GymBattleStateUpdate"
		evt.Parent = eventsFolder
	end

	-- Scan existing plots for Floor4 arenas
	GymBattleSystem.ScanAllPlots()

	print("[GymBattle] GymBattleSystem initialized")
end

return GymBattleSystem
