-- ArenaSystem.lua - ServerScriptService (ModuleScript)
-- King of the Hill arena battle system.
--
-- Flow:
--   1. Every ROUND_INTERVAL seconds, pick the "King" (highest income player with a battle team)
--   2. Pick a random "Challenger" (another player with a battle team, or AI in dev mode)
--   3. Place both teams on Arena BattlePoints (Blue = king, Red = challenger)
--   4. Run auto-battle: creatures attack each other in turns based on speed
--   5. Loser's team returns to base. Winner stays and grows 5% (up to 300%)
--
-- Arena structure in Workspace:
--   Arena/
--     BlueTeam/
--       BattlePoint1..9
--     RedTeam/
--       BattlePoint1..9
--
-- Dev mode: set DEV_MODE = true to spawn AI challenger teams for solo testing

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(ReplicatedStorage.Modules.CreatureAnimation)

local PlayerDataManager
local BasePlacementSystem
local GymBattleSystem  -- Set via ArenaSystem.SetGymBattleSystem() after init

local ArenaSystem = {}

-- --------------------------------------
-- CONFIGURATION
-- --------------------------------------
local DEV_MODE = true              -- Set false for production (no AI challengers)
local ROUND_INTERVAL = 60          -- seconds between arena rounds
local BATTLE_TICK_SPEED = 1.2      -- seconds between combat ticks
local MAX_BATTLE_TEAM_SIZE = 9     -- max creatures per team (matches BattlePoints)
local MIN_BATTLE_TEAM_SIZE = 1     -- min to be eligible
local GROWTH_PER_WIN = 0.05        -- 5% size increase per win
local MAX_GROWTH = 3.0             -- 300% max size multiplier
local BATTLE_CREATURE_TAG = "ArenaCreature"
-- X rotation (degrees) to correct model tilt when facing enemy; tweak to fix upright stance (-90, 0, 90, 180, etc.)
local FACING_X_CORRECTION = math.rad(0)

-- REWARDS
local BASE_WIN_REWARD = 25              -- flat coin bonus per win
local BOUNTY_REWARD_PERCENT = 0.5       -- winner gets 50% of defeated team bounty value
local STREAK_BONUS_PERCENT = 0.10       -- +10% per streak level
local MAX_STREAK_BONUS = 1.0            -- max +100% from streak (10 wins)
local LOSER_CONSOLATION_PERCENT = 0.10  -- loser gets 10% of own team bounty value
local RARE_DROP_BASE_CHANCE = 0.05      -- 5% base chance for bonus creature drop
local RARE_DROP_STREAK_BONUS = 0.02     -- +2% per streak level
local MAX_RARE_DROP_CHANCE = 0.30       -- 30% cap

-- --------------------------------------
-- STATE
-- --------------------------------------
local arenaFolder = nil
local blueTeamFolder = nil
local redTeamFolder = nil

local currentKing = nil            -- Player object
local currentChallenger = nil      -- Player object (or nil for AI)
local battleInProgress = false
local kingWinStreak = 0

-- Active battle creature data
-- { model, creatureId, hp, maxHp, attack, defense, speed, alive, owner, team }
local blueTeamCreatures = {}
local redTeamCreatures = {}

-- Growth tracking per player [UserId] = multiplier
local growthMultipliers = {}

-- Gym battle state (set by WaterGymSystem / StartGymBattle)
local isGymBattle = false
local savedArenaFolder, savedBlueTeamFolder, savedRedTeamFolder

-- Events
local arenaEvents = {}
local arenaWatchTeleportWhitelist = {} -- [userId] = expiresAt (tick time)
local ARENA_WATCH_PROMPT_LEAD = 10

-- Live state broadcast (server -> clients)
local stateDirty = false
local lastStateBroadcast = 0
local STATE_BROADCAST_MIN_INTERVAL = 0.10 -- seconds; throttles event spam during combat

-- --------------------------------------
-- HELPERS
-- --------------------------------------

local function setArenaFighterAttributes(blueName, redName)
	workspace:SetAttribute("ArenaFighterBlueName", blueName)
	workspace:SetAttribute("ArenaFighterRedName", redName)
end

-- Instance-based battle music: set/clear per-player attribute so only
-- participants hear battle music (instead of the global workspace flag).
local battleMusicPlayers = {} -- Player[] currently flagged
local function clearBattleMusicForPlayers()
	for _, p in ipairs(battleMusicPlayers) do
		if p and p.Parent then
			p:SetAttribute("InBattleMusic", nil)
		end
	end
	table.clear(battleMusicPlayers)
end
local function setBattleMusicForPlayers(...)
	clearBattleMusicForPlayers()
	for _, p in ipairs({...}) do
		if p and p:IsA("Player") and p.Parent then
			p:SetAttribute("InBattleMusic", true)
			table.insert(battleMusicPlayers, p)
		end
	end
end

local function markArenaWatchTeleportEligible(player, durationSec)
	if not player then return end
	local dur = math.max(tonumber(durationSec) or 0, 0)
	arenaWatchTeleportWhitelist[player.UserId] = tick() + dur
end

local function clearArenaWatchTeleportEligibility()
	table.clear(arenaWatchTeleportWhitelist)
end

local function isArenaWatchTeleportEligible(player)
	if not player then return false end
	local expiresAt = arenaWatchTeleportWhitelist[player.UserId]
	if not expiresAt then return false end
	if tick() > expiresAt then
		arenaWatchTeleportWhitelist[player.UserId] = nil
		return false
	end
	return true
end

local function getArenaWatchTeleportCFrame()
	if not arenaFolder then return nil end

	local center = arenaFolder:FindFirstChild("ArenaCenter")
	if center and center:IsA("BasePart") then
		return center.CFrame + Vector3.new(0, 5, 0)
	end

	local points = {}
	for _, teamName in ipairs({"BlueTeam", "RedTeam"}) do
		local teamFolder = arenaFolder:FindFirstChild(teamName)
		if teamFolder then
			for _, child in ipairs(teamFolder:GetChildren()) do
				if child:IsA("BasePart") and child.Name:match("^BattlePoint%d+$") then
					table.insert(points, child.Position)
				end
			end
		end
	end

	if #points == 0 then return nil end
	local sum = Vector3.zero
	for _, pos in ipairs(points) do
		sum += pos
	end
	local centerPos = sum / #points
	return CFrame.new(centerPos + Vector3.new(0, 6, 0))
end

local function fireArenaWatchPrompt(king, challenger, countdownSec)
	if not arenaEvents.ArenaWatchPrompt then return end
	local payload = {
		kingName = king and king.Name or "King",
		challengerName = challenger and challenger.Name or "AI Challenger",
		countdown = tonumber(countdownSec) or ARENA_WATCH_PROMPT_LEAD,
	}
	if king and king.Parent then
		arenaEvents.ArenaWatchPrompt:FireClient(king, payload)
	end
	if challenger and challenger.Parent then
		arenaEvents.ArenaWatchPrompt:FireClient(challenger, payload)
	end
end

local function broadcastArenaState()
	if not arenaEvents.ArenaStateUpdate then return end
	if not battleInProgress then return end

	local blue = {}
	for _, c in ipairs(blueTeamCreatures) do
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

	local red = {}
	for _, c in ipairs(redTeamCreatures) do
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

	local payload = {
		blue = blue,
		red = red,
		t = os.clock(),
	}

	for _, p in ipairs(Players:GetPlayers()) do
		arenaEvents.ArenaStateUpdate:FireClient(p, payload)
	end
end

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

local function logBattlePointRotations(folder, teamLabel)
	local pts = getPointsSorted(folder)
	for _, entry in ipairs(pts) do
		local o = entry.part.Orientation
		print(string.format(
			"[Arena] %s BattlePoint%d rotation (X,Y,Z) = (%.2f, %.2f, %.2f)",
			teamLabel,
			entry.index,
			o.X,
			o.Y,
			o.Z
		))
	end
end

local function getPlayerIncome(player)
	local data = PlayerDataManager.GetData(player)
	if not data then return 0 end
	local total = 0
	for _, uid in ipairs(data.baseSlots or {}) do
		if not uid or uid == "" then continue end
		for _, entry in ipairs(data.inventory) do
			if entry.uid and tostring(entry.uid) == tostring(uid) then
				local info = CreatureData.GetById(entry.id)
				if info then total = total + info.baseIncome end
				break
			end
		end
	end
	return total
end

local function getPlayerBattleTeam(player)
	local data = PlayerDataManager.GetData(player)
	if not data then return {} end
	local team = {}

	-- Use explicit battleTeam grid assignments WITH slotIndex
	if data.battleTeam then
		for slotIndex, uid in pairs(data.battleTeam) do
			local sNum = tonumber(slotIndex)
			if sNum and uid then
				local su = tostring(uid)
				for _, entry in ipairs(data.inventory) do
					if entry.uid and tostring(entry.uid) == su then
						table.insert(team, { id = entry.id, uid = entry.uid, slotIndex = sNum, level = entry.level or 1, xp = entry.xp or 0, variant = entry.variant or "Normal" })
						break
					end
				end
			end
			if #team >= MAX_BATTLE_TEAM_SIZE then break end
		end
	end

	-- No fallback: only explicit data.battleTeam counts as a battle team.
	-- Battles start only when: (1) player vs AI with a set battle team, or
	-- (2) 2+ players with set battle teams (King of the Hill).

	-- Sort by slotIndex so placement order is consistent
	table.sort(team, function(a, b) return a.slotIndex < b.slotIndex end)
	return team
end

local function hasEligibleBattleTeam(player)
	local data = PlayerDataManager.GetData(player)
	if not data or data.battleTeamEnabled == false then return false end
	return #getPlayerBattleTeam(player) >= MIN_BATTLE_TEAM_SIZE
end

-- --------------------------------------
-- SPAWN BATTLE CREATURE ON POINT
-- Pulls custom model from CreatureModels when available, else placeholder orb.
-- --------------------------------------

local function getTeamCenter(folder)
	local pts = getPointsSorted(folder)
	if #pts == 0 then return nil end
	local sum = Vector3.zero
	for _, p in ipairs(pts) do sum = sum + p.part.Position end
	return sum / #pts
end

local function spawnBattleCreature(creatureId, battlePoint, team, sizeMultiplier, faceTowardPos)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local rarityInfo = CreatureData.Rarities[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(180, 180, 180)

	local baseSize = 4 * (sizeMultiplier or 1)
	local teamColor = team == "blue" and Color3.fromRGB(60, 120, 255) or Color3.fromRGB(255, 70, 70)
	local spawnPos = battlePoint.Position + Vector3.new(0, baseSize / 2 + 1, 0)
	local battlePointTopY = battlePoint.Position.Y + (battlePoint.Size.Y * 0.5)

	local model = Instance.new("Model")
	model.Name = "Arena_" .. info.id .. "_" .. team
	model:SetAttribute("Team", team)
	model:SetAttribute("CreatureId", creatureId)
	CollectionService:AddTag(model, BATTLE_CREATURE_TAG)

	local body, core
	local isCustomModel = false

	-- CreatureModelLoader: prefers Model type, then legacy mesh. Scale to match mesh.
	local options = { targetSize = baseSize, creatureId = creatureId }
	body, core, isCustomModel = CreatureModelLoader.LoadAndIntegrate(model, info.modelName, info.displayName, spawnPos, options)
	if body then core = core or model:FindFirstChild("Core") end
	if not body then
		-- Placeholder orb (no custom model found)
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

	-- Name + HP billboard (offset to top of bounding box so name isn't blocked)
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
	model.Parent = arenaFolder

	-- Place custom models so bottom sits on battle point (avoid clipping)
	if isCustomModel then
		local bboxCf, bboxSize = model:GetBoundingBox()
		local modelBottomY = bboxCf.Position.Y - bboxSize.Y * 0.5
		local lift = math.max(0, battlePointTopY - modelBottomY)
		if lift > 0 then
			model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
		end
	end

	-- Use same rotation as base BattlePoints (no flying/crawling special handling)
	local rotOffset = CreatureData.GetModelRotationOffset(info) or CFrame.identity

	-- Billboard stud offset: ensure name tag stays at top of bounding box (helper already used at creation)
	local bb = model:FindFirstChild("InfoTag")
	if bb then
		bb.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)
	end

	-- Face toward enemy side on a flat XZ plane so models stay upright.
	-- Mesh templates keep their native forward orientation.
	local pivotPos = model:GetPivot().Position
	local faceCf
	if faceTowardPos then
		local templateType = model:GetAttribute("TemplateType")
		if templateType == "Mesh" then
			faceCf = CFrame.new(pivotPos)  -- Mesh: no 90° Y rotation
		else
			faceCf = CFrame.lookAt(pivotPos, Vector3.new(faceTowardPos.X, pivotPos.Y, faceTowardPos.Z))
		end
	else
		local templateType = model:GetAttribute("TemplateType")
		if templateType == "Mesh" then
			faceCf = CFrame.new(pivotPos)  -- Mesh: no 90° Y rotation
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

-- --------------------------------------
-- HP BAR UPDATE
-- --------------------------------------

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

	-- Mark dirty for client HUD
	stateDirty = true
end

-- --------------------------------------
-- FOCUS BAR UPDATE
-- --------------------------------------

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

	-- Mark dirty for client HUD
	stateDirty = true
end

-- --------------------------------------
-- ATTACK VISUAL
-- --------------------------------------

local function attackVisual(attackerData, defenderData, damage)
	if not attackerData.model or not defenderData.model then return end
	local aBody = CreatureModelLoader.GetBodyPart(attackerData.model) or attackerData.model:FindFirstChild("Body")
	local dBody = CreatureModelLoader.GetBodyPart(defenderData.model) or defenderData.model:FindFirstChild("Body")
	if not aBody or not dBody then return end

	-- Projectile
	local bolt = Instance.new("Part")
	bolt.Shape = Enum.PartType.Ball
	bolt.Size = Vector3.new(1.5, 1.5, 1.5)
	bolt.Color = aBody.Color
	bolt.Material = Enum.Material.Neon
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.Position = aBody.Position
	bolt.Parent = arenaFolder

	local light = Instance.new("PointLight")
	light.Color = bolt.Color
	light.Brightness = 3
	light.Range = 10
	light.Parent = bolt

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

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 70, 0, 28)
		bb.Adornee = dmgPart
		bb.AlwaysOnTop = true
		bb.Parent = dmgPart

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "-" .. math.floor(damage)
		lbl.TextColor3 = Color3.fromRGB(255, 80, 60)
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextStrokeTransparency = 0.3
		lbl.Parent = bb

		for i = 1, 25 do
			dmgPart.Position = dmgPart.Position + Vector3.new(0, 0.08, 0)
			lbl.TextTransparency = i / 25
			lbl.TextStrokeTransparency = 0.3 + (i / 25) * 0.7
			RunService.Heartbeat:Wait()
		end
		dmgPart:Destroy()
	end)
end

-- --------------------------------------
-- SPECIAL ATTACK VISUAL
-- Slows battle, plays unique element animation, then applies damage number
-- --------------------------------------

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

local function specialAttackVisual(attackerData, defenderData, element, damage)
	if not attackerData.model or not defenderData.model then return end
	local aBody = CreatureModelLoader.GetBodyPart(attackerData.model) or attackerData.model:FindFirstChild("Body")
	local dBody = CreatureModelLoader.GetBodyPart(defenderData.model) or defenderData.model:FindFirstChild("Body")
	if not aBody or not dBody then return end

	local elemColor = ELEMENT_COLORS[element] or aBody.Color
	local fromPos = aBody.Position
	local toPos = dBody.Position

	-- Create elemental effect parts (per element)
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
			local bolt = makeOrb(fromPos, 3, elemColor)
			local dur = 0.4
			local s = tick()
			while tick() - s < dur do
				bolt.Position = fromPos:Lerp(toPos, (tick() - s) / dur)
				RunService.Heartbeat:Wait()
			end
			if dBody.Parent then local oc = dBody.Color; dBody.Color = Color3.fromRGB(255, 150, 50); task.wait(0.2); if dBody.Parent then dBody.Color = oc end end
			bolt:Destroy()
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
				for i, data in ipairs(orbs) do
					local mid = fromPos:Lerp(toPos, t)
					data.angle = data.angle + 0.3
					data.part.Position = mid + Vector3.new(math.cos(data.angle) * 3, math.sin(data.angle * 2) * 1, math.sin(data.angle) * 3)
				end
				RunService.Heartbeat:Wait()
			end
			for _, data in ipairs(orbs) do data.part:Destroy() end
			if dBody.Parent then local oc = dBody.Color; dBody.Color = Color3.fromRGB(200, 255, 220); task.wait(0.1); if dBody.Parent then dBody.Color = oc end end
		end)
	end

	-- Shadow / Lightning / Water / Light / Psychic: Generic enhanced projectile
	if element == "Shadow" or element == "Lightning" or element == "Water" or element == "Light" or element == "Psychic" or not ELEMENT_COLORS[element] then
		task.spawn(function()
			local bolt = makeOrb(fromPos, 3.5, elemColor)
			local light = Instance.new("PointLight")
			light.Color = elemColor
			light.Brightness = 5
			light.Range = 15
			light.Parent = bolt
			local dur = 0.4
			local s = tick()
			while tick() - s < dur do
				bolt.Position = fromPos:Lerp(toPos, (tick() - s) / dur)
				RunService.Heartbeat:Wait()
			end
			if dBody.Parent then local oc = dBody.Color; dBody.Color = elemColor; task.wait(0.15); if dBody.Parent then dBody.Color = oc end end
			bolt:Destroy()
		end)
	end

	-- Damage number (same as normal attack)
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

		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.new(0, 90, 0, 36)
		bb.Adornee = dmgPart
		bb.AlwaysOnTop = true
		bb.Parent = dmgPart

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "-" .. math.floor(damage) .. "!"
		lbl.TextColor3 = elemColor
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextStrokeTransparency = 0.2
		lbl.Parent = bb

		for i = 1, 30 do
			dmgPart.Position = dmgPart.Position + Vector3.new(0, 0.1, 0)
			lbl.TextTransparency = i / 30
			lbl.TextStrokeTransparency = 0.2 + (i / 30) * 0.8
			RunService.Heartbeat:Wait()
		end
		dmgPart:Destroy()
	end)
end

-- --------------------------------------
-- DEATH VISUAL
-- --------------------------------------

local function deathVisual(creatureData)
	if not creatureData.model or not creatureData.model.Parent then return end
	local body = CreatureModelLoader.GetBodyPart(creatureData.model) or creatureData.model:FindFirstChild("Body")
	if not body then return end

	task.spawn(function()
		-- Shrink + fade (visual only, cleanup handles destruction)
		for i = 1, 15 do
			if not body.Parent then return end
			local s = body.Size * 0.9
			body.Size = s
			body.Transparency = i / 15
			local core = creatureData.model and creatureData.model:FindFirstChild("Core")
			if core then core.Size = s * 0.5; core.Transparency = i / 15 end
			RunService.Heartbeat:Wait()
		end
		-- Make fully invisible but don't destroy (cleanup does that)
		if body.Parent then body.Transparency = 1 end
	end)

	-- Mark dirty for client HUD (alive -> false)
	stateDirty = true
end

-- --------------------------------------
-- CLEAR ARENA
-- --------------------------------------

local function clearArena()
	if not arenaFolder then return end

	-- Aggressively destroy everything in BlueTeam/RedTeam except BattlePoints
	local function cleanFolder(folder)
		if not folder then return end
		for _, child in ipairs(folder:GetChildren()) do
			-- Keep BattlePoint parts, destroy everything else
			if child.Name:match("^BattlePoint") then
				-- It's a battle point marker - keep it, but clean any children
				for _, sub in ipairs(child:GetChildren()) do
					if sub:IsA("Model") or (sub:IsA("Part") and sub.Name ~= child.Name) then
						sub:Destroy()
					end
				end
			else
				child:Destroy()
			end
		end
	end

	cleanFolder(blueTeamFolder)
	cleanFolder(redTeamFolder)

	-- Also destroy any tagged creatures anywhere in arena (safety net)
	for _, child in ipairs(arenaFolder:GetDescendants()) do
		if child:IsA("Model") and CollectionService:HasTag(child, BATTLE_CREATURE_TAG) then
			child:Destroy()
		end
	end

	blueTeamCreatures = {}
	redTeamCreatures = {}
end

-- --------------------------------------
-- PLACE TEAMS
-- --------------------------------------

local function placeTeam(team, teamFolder, teamColor, sizeMultiplier, enemyFolder)
	local points = getPointsSorted(teamFolder)
	local faceTowardPos = enemyFolder and getTeamCenter(enemyFolder)
	-- Build a map: pointIndex -> part for direct slot lookup
	local pointMap = {}
	for _, p in ipairs(points) do pointMap[p.index] = p.part end

	local placed = {}

	for _, entry in ipairs(team) do
		local slotIdx = entry.slotIndex or 0
		-- Find the matching BattlePoint for this slot
		local targetPoint = pointMap[slotIdx]
		-- Fallback: if no matching point, use next available
		if not targetPoint then
			for _, p in ipairs(points) do
				local taken = false
				for _, pl in ipairs(placed) do
					if pl.pointIndex == p.index then taken = true break end
				end
				if not taken then targetPoint = p.part; slotIdx = p.index; break end
			end
		end
		if not targetPoint then break end -- no more points

		local info = CreatureData.GetById(entry.id)
		if info then
			local model = spawnBattleCreature(entry.id, targetPoint, teamColor, sizeMultiplier, faceTowardPos)
			if model then
				-- Use GetEffectiveStats so level + variant (Silver/Gold/Legend) apply
				local variant = entry.variant or "Normal"
				local stats = PlayerDataManager.GetEffectiveStats(entry.id, entry.level or 1, variant)
				local lvl = entry.level or 1
				local maxFocus = GameConfig.FocusMax or 100
				if stats then
					table.insert(placed, {
						model = model,
						creatureId = entry.id,
						uid = entry.uid or ("ai_" .. slotIdx),
						hp = stats.health,
						maxHp = stats.health,
						attack = stats.attack,
						defense = stats.defense,
						speed = stats.speed,
						level = lvl,
						alive = true,
						team = teamColor,
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

	return placed
end

-- --------------------------------------
-- GENERATE AI TEAM (dev mode)
-- --------------------------------------

local function generateAITeam(size)
	local team = {}
	for i = 1, size do
		local id = CreatureData.GetRandomCreatureId()
		table.insert(team, { id = id, uid = "ai_" .. i })
	end
	return team
end

-- Gym leader squad: 5 high-level Water, Ice, Fire creatures (high tier = Rare+). Used by WaterGym.
local function generateGymTeam(level)
	level = level or (GameConfig.WaterGymCreatureLevel or 45)
	local elements = { "Water", "Ice", "Fire" }
	local team = {}
	local used = {}
	for i = 1, 5 do
		local element = elements[(i - 1) % 3 + 1]
		local list = CreatureData.GetCreaturesByElement(element)
		if not list or #list == 0 then
			list = CreatureData.Creatures
		end
		-- Prefer Rare, Epic, Legendary
		local candidates = {}
		for _, c in ipairs(list) do
			local r = CreatureData.RarityOrder[c.rarity]
			if r and r >= 3 then table.insert(candidates, c) end
		end
		if #candidates == 0 then
			for _, c in ipairs(list) do table.insert(candidates, c) end
		end
		local pick = candidates[math.random(1, #candidates)]
		local id = pick and pick.id or (CreatureData.Creatures[1] and CreatureData.Creatures[1].id)
		if id then
			table.insert(team, {
				id = id,
				uid = "gym_" .. i,
				level = level,
				xp = 0,
				variant = "Normal",
				slotIndex = i,
			})
		end
	end
	return team
end

-- --------------------------------------
-- REWARD SYSTEM
-- --------------------------------------

-- Calculate bounty value of a team (sum of capture costs)
local function calculateTeamBounty(creatures)
	local total = 0
	for _, c in ipairs(creatures) do
		local info = CreatureData.GetById(c.creatureId)
		if info then
			local rarity = CreatureData.Rarities[info.rarity]
			total = total + (rarity and rarity.captureCost or 10)
		end
	end
	return total
end

-- Roll for a bonus creature drop
local function rollBonusDrop(streak)
	local chance = math.min(MAX_RARE_DROP_CHANCE, RARE_DROP_BASE_CHANCE + RARE_DROP_STREAK_BONUS * (streak - 1))
	if math.random() > chance then return nil end

	-- Higher streaks = better rarity chances
	local roll = math.random(100)
	local rarity
	if streak >= 8 and roll <= 5 then
		rarity = "Legendary"
	elseif streak >= 5 and roll <= 15 then
		rarity = "Epic"
	elseif streak >= 3 and roll <= 35 then
		rarity = "Rare"
	elseif roll <= 60 then
		rarity = "Uncommon"
	else
		rarity = "Common"
	end

	-- Pick a random creature of that rarity
	local candidates = {}
	for _, creature in ipairs(CreatureData.Creatures) do
		if creature.rarity == rarity then
			table.insert(candidates, creature.id)
		end
	end
	if #candidates == 0 then return nil end
	return candidates[math.random(#candidates)], rarity
end

-- Pay out rewards to a player
local function payoutRewards(player, isWinner, teamBounty, enemyBounty, streak)
	if not player or not player.Parent then return nil end
	if not PlayerDataManager then return nil end

	local reward = {}

	if isWinner then
		-- Base reward
		local baseCoins = BASE_WIN_REWARD

		-- Bounty reward (% of defeated team's total rarity value)
		local bountyCoins = math.floor(enemyBounty * BOUNTY_REWARD_PERCENT)

		-- Streak multiplier
		local streakMultiplier = 1 + math.min(MAX_STREAK_BONUS, STREAK_BONUS_PERCENT * (streak - 1))
		local totalCoins = math.floor((baseCoins + bountyCoins) * streakMultiplier)

		-- Pay coins
		PlayerDataManager.AddCoins(player, totalCoins)
		reward.coins = totalCoins
		reward.baseCoins = baseCoins
		reward.bountyCoins = bountyCoins
		reward.streakMultiplier = streakMultiplier
		reward.streak = streak

		-- Update stats
		local d = PlayerDataManager.GetData(player)
		if d and d.stats then
			d.stats.arenaWins = (d.stats.arenaWins or 0) + 1
			d.stats.arenaWinStreak = (d.stats.arenaWinStreak or 0) + 1
			if d.stats.arenaWinStreak > (d.stats.arenaMaxStreak or 0) then
				d.stats.arenaMaxStreak = d.stats.arenaWinStreak
			end
		end
		if PlayerDataManager.NotifyAchievement then
			PlayerDataManager.NotifyAchievement("OnArenaWin", player, d and d.stats and d.stats.arenaWinStreak or 0)
		end

		-- Award player XP for arena win
		if PlayerDataManager.AddPlayerXP then
			local pLvl, pDidLvl = PlayerDataManager.AddPlayerXP(player, GameConfig.PlayerXP_ArenaWin or 50)
			if pDidLvl then
				local events = game.ReplicatedStorage:FindFirstChild("Events")
				local lvlEvt = events and events:FindFirstChild("PlayerLevelUp")
				if lvlEvt then lvlEvt:FireClient(player, pLvl) end
			end
		end

		-- Roll for bonus creature
		local dropId, dropRarity = rollBonusDrop(streak)
		if dropId then
			local uid = PlayerDataManager.AddCreature(player, dropId, nil, nil, nil, nil, { source = "arena_reward" })
			if uid then
				reward.bonusCreature = dropId
				reward.bonusRarity = dropRarity
				local dropInfo = CreatureData.GetById(dropId)
				reward.bonusName = dropInfo and dropInfo.displayName or dropId
			end
		end
	else
		-- Consolation: small % of own team bounty
		local consolation = math.max(5, math.floor(teamBounty * LOSER_CONSOLATION_PERCENT))
		PlayerDataManager.AddCoins(player, consolation)
		reward.coins = consolation
		reward.consolation = true

		-- Track loss + reset streak
		local d = PlayerDataManager.GetData(player)
		if d and d.stats then
			d.stats.arenaLosses = (d.stats.arenaLosses or 0) + 1
			d.stats.arenaWinStreak = 0
		end
	end

	-- Push updated coin balance to client
	local events = ReplicatedStorage:FindFirstChild("Events")
	local coinsEvt = events and events:FindFirstChild("CoinsUpdate")
	if coinsEvt then
		local d = PlayerDataManager.GetData(player)
		if d then coinsEvt:FireClient(player, d.coins) end
	end

	return reward
end

-- --------------------------------------
-- AUTO-BATTLE COMBAT LOOP
-- --------------------------------------

local function runBattle()
	battleInProgress = true

	-- Broadcast battle start
	if arenaEvents.BattleStart then
		local kingName = currentKing and currentKing.Name or "AI King"
		local challName = currentChallenger and currentChallenger.Name or "AI Challenger"
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.BattleStart:FireClient(p, kingName, challName, #blueTeamCreatures, #redTeamCreatures)
		end
	end

	task.wait(2) -- Pre-battle pause

	-- Ensure HUD receives a start snapshot
	stateDirty = true
	lastStateBroadcast = 0
	broadcastArenaState()

	-- Combine all creatures and sort by speed (fastest acts first)
	local allCreatures = {}
	for _, c in ipairs(blueTeamCreatures) do table.insert(allCreatures, c) end
	for _, c in ipairs(redTeamCreatures) do table.insert(allCreatures, c) end
	table.sort(allCreatures, function(a, b) return a.speed > b.speed end)

	local round = 0
	while battleInProgress do
		round = round + 1

		-- Check win condition
		local blueAlive = 0
		local redAlive = 0
		for _, c in ipairs(blueTeamCreatures) do if c.alive then blueAlive = blueAlive + 1 end end
		for _, c in ipairs(redTeamCreatures) do if c.alive then redAlive = redAlive + 1 end end

		if blueAlive == 0 or redAlive == 0 then break end

		-- Each creature attacks
		for _, attacker in ipairs(allCreatures) do
			if not attacker.alive or not battleInProgress then continue end

			-- Frozen: skip this turn
			if attacker.frozen then
				attacker.frozen = false
				task.wait(0.15) -- brief pause for "thaw" feel
				continue
			end

			-- Apply burn damage at start of turn
			if attacker.burnRounds and attacker.burnRounds > 0 then
				local burnDmg = math.max(1, math.floor(attacker.maxHp * (GameConfig.BurnDamagePerRound or 0.08)))
				attacker.hp = attacker.hp - burnDmg
				attacker.burnRounds = attacker.burnRounds - 1
				updateHPBar(attacker)
				-- Small burn visual (optional flash)
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
				if stateDirty and (os.clock() - lastStateBroadcast) >= STATE_BROADCAST_MIN_INTERVAL then
					lastStateBroadcast = os.clock()
					stateDirty = false
					broadcastArenaState()
				end
				task.wait(0.2)
				if not attacker.alive then continue end
			end

			-- Pick target from opposite team
			local targets = attacker.team == "blue" and redTeamCreatures or blueTeamCreatures
			local target = nil
			local lowestHP = math.huge
			for _, t in ipairs(targets) do
				if t.alive and t.hp < lowestHP then
					lowestHP = t.hp
					target = t
				end
			end

			if not target then continue end

			-- Check presence buff: is the creature's owner standing on the arena?
			local presenceBuff = 1.0
			local ownerPlayer = attacker.team == "blue" and currentKing or currentChallenger
			if ownerPlayer and ownerPlayer.Parent then
				local ok2, _ = pcall(function()
					local char = ownerPlayer.Character
					if not char then return end
					local root = char:FindFirstChild("HumanoidRootPart")
					if not root or not arenaFolder then return end
					local ac = arenaFolder:FindFirstChild("ArenaCenter")
					local checkPos
					if ac and ac:IsA("BasePart") then
						checkPos = ac.Position
					elseif ac and ac:IsA("Model") then
						local inner = ac:FindFirstChildWhichIsA("BasePart")
						checkPos = inner and inner.Position or ac:GetPivot().Position
					else
						checkPos = arenaFolder:GetPivot().Position
					end
					local dist = (root.Position * Vector3.new(1, 0, 1) - checkPos * Vector3.new(1, 0, 1)).Magnitude
					if dist < 50 then
						presenceBuff = 1.0 + GameConfig.ArenaPresenceBuff
					end
				end)
			end

			-- Damage calc: atk - def/3 with minimum of 1, with presence buff
			local dmg = math.max(1, attacker.attack - target.defense / 3)
			dmg = dmg * presenceBuff
			-- Earth special: target takes reduced damage
			if target.dmgReductionRounds and target.dmgReductionRounds > 0 then
				dmg = dmg * (1 - (GameConfig.EarthDmgReduction or 0.25))
				target.dmgReductionRounds = target.dmgReductionRounds - 1
			end
			-- Elemental weakness: Fire→Ice→Earth→Wind→Fire; Water/Electric/Light/Shadow per chart
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
					target.frozen = true -- skip next attack
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

				specialAttackVisual(attacker, target, elem, dmg)
				target.hp = target.hp - dmg
				updateHPBar(target)
				if stateDirty and (os.clock() - lastStateBroadcast) >= STATE_BROADCAST_MIN_INTERVAL then
					lastStateBroadcast = os.clock()
					stateDirty = false
					broadcastArenaState()
				end

				-- Slow the battle for special attack
				task.wait(GameConfig.SpecialAttackDuration or 2.5)
			else
				-- Normal attack
				CreatureAnimation.PlayAnimation(attacker.model, "Attack", attacker.creatureId)
				target.hp = target.hp - dmg
				attackVisual(attacker, target, dmg)
				updateHPBar(target)

				-- Gain focus
				attacker.focus = math.min(attacker.maxFocus or 100, (attacker.focus or 0) + (GameConfig.FocusGainPerAttack or 25))
				updateFocusBar(attacker)
				if stateDirty and (os.clock() - lastStateBroadcast) >= STATE_BROADCAST_MIN_INTERVAL then
					lastStateBroadcast = os.clock()
					stateDirty = false
					broadcastArenaState()
				end

				task.wait(BATTLE_TICK_SPEED / math.max(1, #allCreatures / 3))
			end

			if target.hp <= 0 then
				target.alive = false
				deathVisual(target)
				if stateDirty and (os.clock() - lastStateBroadcast) >= STATE_BROADCAST_MIN_INTERVAL then
					lastStateBroadcast = os.clock()
					stateDirty = false
					broadcastArenaState()
				end

				-- Award kill XP to the attacker's creature
				local attackerOwner = attacker.team == "blue" and currentKing or currentChallenger
				if attackerOwner and attackerOwner.Parent and attacker.uid and not attacker.uid:match("^ai_") then
					local newLvl, didLevel = PlayerDataManager.AddXP(attackerOwner, attacker.uid, GameConfig.BattleKillXP)
					if didLevel then
						print("[Arena] " .. attackerOwner.Name .. "'s creature leveled up to " .. newLvl .. "!")
					end
					-- Award player XP for arena kill
					if PlayerDataManager.AddPlayerXP then
						local pLvl, pDidLvl = PlayerDataManager.AddPlayerXP(attackerOwner, GameConfig.PlayerXP_ArenaKill or 10)
						if pDidLvl then
							local events = game.ReplicatedStorage:FindFirstChild("Events")
							local lvlEvt = events and events:FindFirstChild("PlayerLevelUp")
							if lvlEvt then lvlEvt:FireClient(attackerOwner, pLvl) end
						end
					end
				end

				-- Broadcast kill
				if arenaEvents.BattleKill then
					local aInfo = CreatureData.GetById(attacker.creatureId)
					local dInfo = CreatureData.GetById(target.creatureId)
					for _, p in ipairs(Players:GetPlayers()) do
						arenaEvents.BattleKill:FireClient(p,
							aInfo and aInfo.displayName or "?",
							dInfo and dInfo.displayName or "?",
							attacker.team)
					end
				end
			end
		end

		-- Small pause between rounds
		task.wait(0.3)
	end

	-- Determine winner
	local blueAlive = 0
	local redAlive = 0
	for _, c in ipairs(blueTeamCreatures) do if c.alive then blueAlive = blueAlive + 1 end end
	for _, c in ipairs(redTeamCreatures) do if c.alive then redAlive = redAlive + 1 end end

	local winnerTeam = blueAlive > 0 and "blue" or "red"
	local winnerPlayer = winnerTeam == "blue" and currentKing or currentChallenger
	local loserPlayer = winnerTeam == "blue" and currentChallenger or currentKing

	-- Broadcast result
	if arenaEvents.BattleEnd then
		local winName = winnerPlayer and winnerPlayer.Name or ("AI " .. (winnerTeam == "blue" and "King" or "Challenger"))
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.BattleEnd:FireClient(p, winName, winnerTeam, blueAlive, redAlive)
		end
	end

	-- Final snapshot for UI
	stateDirty = true
	lastStateBroadcast = 0
	broadcastArenaState()

	-- -- REWARDS --
	local loserCreatures = winnerTeam == "blue" and redTeamCreatures or blueTeamCreatures
	local winnerCreatures = winnerTeam == "blue" and blueTeamCreatures or redTeamCreatures
	local winnerBounty = calculateTeamBounty(winnerCreatures)
	local loserBounty = calculateTeamBounty(loserCreatures)

	-- Apply growth to winner's team creatures (skip for gym battles)
	if not isGymBattle and winnerPlayer then
		local userId = winnerPlayer.UserId
		growthMultipliers[userId] = math.min(MAX_GROWTH, (growthMultipliers[userId] or 1) + GROWTH_PER_WIN)
		kingWinStreak = kingWinStreak + 1

		-- Grow surviving winner creatures visually
		for _, c in ipairs(winnerCreatures) do
			if c.alive and c.model and c.model.Parent then
				local body = CreatureModelLoader.GetBodyPart(c.model) or c.model:FindFirstChild("Body")
				local core = c.model:FindFirstChild("Core")
				if body then
					local newSize = body.Size * (1 + GROWTH_PER_WIN)
					body.Size = newSize
					if core then core.Size = newSize * 0.5 end
				end
			end
		end
	end

	-- Reset loser's growth (skip for gym)
	if not isGymBattle and loserPlayer then
		growthMultipliers[loserPlayer.UserId] = 1
	end

	-- Pay rewards (gym uses fixed reward below)
	local winnerReward, loserReward
	if isGymBattle then
		winnerReward = nil
		loserReward = nil
		if winnerTeam == "blue" and currentKing and currentKing.Parent then
			local gymReward = GameConfig.WaterGymWinReward or 250
			PlayerDataManager.AddCoins(currentKing, gymReward)
			winnerReward = { coins = gymReward }
			if PlayerDataManager.AddPlayerXP then
				local pLvl, pDidLvl = PlayerDataManager.AddPlayerXP(currentKing, GameConfig.WaterGymWinXP or 75)
				if pDidLvl then
					local events = game.ReplicatedStorage:FindFirstChild("Events")
					local lvlEvt = events and events:FindFirstChild("PlayerLevelUp")
					if lvlEvt then lvlEvt:FireClient(currentKing, pLvl) end
				end
			end
		end
	else
		winnerReward = payoutRewards(winnerPlayer, true, winnerBounty, loserBounty, kingWinStreak)
		loserReward = payoutRewards(loserPlayer, false, loserBounty, winnerBounty, 0)
	end

	-- Award win XP: entire team splits a pool (skip for gym; gym gives player XP above)
	if not isGymBattle and winnerPlayer and winnerPlayer.Parent then
		local playerCreatures = {}
		for _, c in ipairs(winnerCreatures) do
			if c.uid and not c.uid:match("^ai_") then
				table.insert(playerCreatures, c)
			end
		end
		local teamSize = #playerCreatures
		if teamSize > 0 then
			local poolBase = GameConfig.ArenaWinXPPoolBase or 400
			local poolPerStreak = GameConfig.ArenaWinXPPoolPerStreak or 60
			-- kingWinStreak is already incremented; streak 1 = base only, streak 2+ = base + extra
			local totalPool = poolBase + (poolPerStreak * math.max(0, kingWinStreak - 1))
			local xpPerCreature = math.max(1, math.floor(totalPool / teamSize))  -- smaller team = more XP each
			for _, c in ipairs(playerCreatures) do
				PlayerDataManager.AddXP(winnerPlayer, c.uid, xpPerCreature)
			end
		end
	end

	-- Broadcast rewards to all players
	if arenaEvents.ArenaReward then
		local winName = winnerPlayer and winnerPlayer.Name or "AI"
		local loseName = loserPlayer and loserPlayer.Name or "AI"
		local payload = isGymBattle and {
			gym = true,
			winner = winName,
			loser = loseName,
			winnerReward = winnerReward,
			loserReward = loserReward,
		} or {
			winner = winName,
			loser = loseName,
			winnerReward = winnerReward,
			loserReward = loserReward,
			streak = kingWinStreak,
			winnerBounty = winnerBounty,
			loserBounty = loserBounty,
		}
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.ArenaReward:FireClient(p, payload)
		end
	end

	-- Log
	local rewardLog = winnerReward and ("+" .. winnerReward.coins .. " coins") or "no reward"
	if winnerReward and winnerReward.bonusCreature then
		rewardLog = rewardLog .. " + BONUS: " .. winnerReward.bonusName .. " (" .. winnerReward.bonusRarity .. ")"
	end
	print("[Arena] Rewards - Winner: " .. rewardLog .. " | Streak: " .. kingWinStreak)

	-- Clean up loser team after a pause
	task.wait(3)
	local loserCreatures = winnerTeam == "blue" and redTeamCreatures or blueTeamCreatures
	for _, c in ipairs(loserCreatures) do
		pcall(function() if c.model and c.model.Parent then c.model:Destroy() end end)
	end

	-- Clean up winner team too after another brief pause (they don't persist between rounds)
	task.wait(2)
	local winCreatures2 = winnerTeam == "blue" and blueTeamCreatures or redTeamCreatures
	for _, c in ipairs(winCreatures2) do
		pcall(function() if c.model and c.model.Parent then c.model:Destroy() end end)
	end

	-- Final safety: nuke everything left in arena
	clearArena()

	-- Update king (skip for gym battles)
	if not isGymBattle then
		if winnerTeam == "red" then
			-- Challenger becomes new king
			currentKing = currentChallenger
			kingWinStreak = 1  -- new king starts fresh at streak 1
		end
		currentChallenger = nil

		-- Validate king is still in game
		if currentKing and not currentKing.Parent then
			currentKing = nil
			kingWinStreak = 0
		end
	end

	-- Respawn loser's battle team back to their base BattlePoints
	if BasePlacementSystem then
		if loserPlayer and loserPlayer.Parent then
			pcall(function() BasePlacementSystem.RespawnBattleCreatures(loserPlayer) end)
		end
		-- Winner stays in arena, but we also respawn their base orbs
		-- so they're visible on the base when arena eventually clears
		if winnerPlayer and winnerPlayer.Parent then
			pcall(function() BasePlacementSystem.RespawnBattleCreatures(winnerPlayer) end)
		end
	end

	battleInProgress = false
	workspace:SetAttribute("ArenaBattleInProgress", false)
	setArenaFighterAttributes(nil, nil)
	clearBattleMusicForPlayers()
	clearArenaWatchTeleportEligibility()
	print("[Arena] Battle complete! Winner: " .. winnerTeam .. " | King streak: " .. kingWinStreak)
end

-- --------------------------------------
-- PICK KING & CHALLENGER
-- --------------------------------------

local function pickKing()
	local bestPlayer = nil
	local bestIncome = -1

	for _, player in ipairs(Players:GetPlayers()) do
		if hasEligibleBattleTeam(player) then
			local income = getPlayerIncome(player)
			if income > bestIncome then
				bestIncome = income
				bestPlayer = player
			end
		end
	end

	return bestPlayer
end

local function pickChallenger(king)
	local eligible = {}
	for _, player in ipairs(Players:GetPlayers()) do
		if player ~= king and hasEligibleBattleTeam(player) then
			table.insert(eligible, player)
		end
	end
	if #eligible == 0 then return nil end
	return eligible[math.random(1, #eligible)]
end

-- --------------------------------------
-- MAIN ROUND LOOP
-- --------------------------------------

local function startRound()
	if battleInProgress then return end

	-- Pick king
	local king = pickKing()
	if not king then
		print("[Arena] No eligible king - skipping round")
		return
	end

	currentKing = king

	-- Pick challenger
	local challenger = pickChallenger(king)

	if not challenger and not DEV_MODE then
		if arenaEvents.ArenaAnnounce then
			for _, p in ipairs(Players:GetPlayers()) do
				arenaEvents.ArenaAnnounce:FireClient(p, currentKing.Name .. " is the King! No suitable challengers found.")
			end
		end
		print("[Arena] No challenger available - skipping")
		return
	end

	currentChallenger = challenger

	-- LOCK: prevent any base refresh from re-placing battle creatures
	battleInProgress = true
	workspace:SetAttribute("ArenaBattleInProgress", true)
	setArenaFighterAttributes(king and king.Name or nil, challenger and challenger.Name or "AI Challenger")
	setBattleMusicForPlayers(king, challenger)

	-- Clear arena of any leftover models from previous round
	clearArena()

	-- Clear battle orbs from players' bases (they're going to arena now)
	if BasePlacementSystem then
		if king then
			pcall(function() BasePlacementSystem.ClearBattleCreatures(king) end)
		end
		if challenger then
			pcall(function() BasePlacementSystem.ClearBattleCreatures(challenger) end)
		end
	end

	-- Get teams
	local kingTeam = getPlayerBattleTeam(king)
	local challengerTeam
	local challengerName

	if challenger then
		challengerTeam = getPlayerBattleTeam(challenger)
		challengerName = challenger.Name
	else
		-- DEV MODE: generate random AI team of 5
		challengerTeam = generateAITeam(5)
		challengerName = "AI Challenger"
	end
	setArenaFighterAttributes(king and king.Name or nil, challengerName)

	-- Notify only selected arena players and allow quick spectate teleport.
	markArenaWatchTeleportEligible(king, ARENA_WATCH_PROMPT_LEAD + 25)
	if challenger then
		markArenaWatchTeleportEligible(challenger, ARENA_WATCH_PROMPT_LEAD + 25)
	end
	fireArenaWatchPrompt(king, challenger, ARENA_WATCH_PROMPT_LEAD)

	-- Targeted announce (no global ticker spam)
	if arenaEvents.ArenaAnnounce then
		if king and king.Parent then
			arenaEvents.ArenaAnnounce:FireClient(king, "ARENA BATTLE! " .. king.Name .. " (King) vs " .. challengerName .. "!")
		end
		if challenger and challenger.Parent then
			arenaEvents.ArenaAnnounce:FireClient(challenger, "ARENA BATTLE! " .. king.Name .. " (King) vs " .. challengerName .. "!")
		end
	end

	task.wait(ARENA_WATCH_PROMPT_LEAD) -- Pre-placement pause with watch prompt badge window

	-- Clear arena AGAIN right before placing (in case anything spawned during the 3s wait)
	clearArena()

	-- Re-clear base battle orbs (in case refreshPlayerBase ran during the wait)
	if BasePlacementSystem then
		if king then pcall(function() BasePlacementSystem.ClearBattleCreatures(king) end) end
		if challenger then pcall(function() BasePlacementSystem.ClearBattleCreatures(challenger) end) end
	end

	-- Place teams
	local kingGrowth = growthMultipliers[king.UserId] or 1
	blueTeamCreatures = placeTeam(kingTeam, blueTeamFolder, "blue", kingGrowth, redTeamFolder)
	redTeamCreatures = placeTeam(challengerTeam, redTeamFolder, "red", 1, blueTeamFolder)

	-- Broadcast team data for UI
	if arenaEvents.BattleTeamsPlaced then
		local blueData = {}
		for _, c in ipairs(blueTeamCreatures) do
			local info = CreatureData.GetById(c.creatureId)
			table.insert(blueData, {
				creatureId = c.creatureId,
				displayName = info and info.displayName or "?",
				rarity = info and info.rarity or "Common",
				hp = c.hp,
				maxHp = c.maxHp,
				focus = c.focus or 0,
				maxFocus = c.maxFocus or (GameConfig.FocusMax or 100),
				pointIndex = c.pointIndex,
				attack = c.attack,
				speed = c.speed,
				primaryColor = info and {info.primaryColor.R * 255, info.primaryColor.G * 255, info.primaryColor.B * 255} or {180, 180, 180},
			})
		end
		local redData = {}
		for _, c in ipairs(redTeamCreatures) do
			local info = CreatureData.GetById(c.creatureId)
			table.insert(redData, {
				creatureId = c.creatureId,
				displayName = info and info.displayName or "?",
				rarity = info and info.rarity or "Common",
				hp = c.hp,
				maxHp = c.maxHp,
				focus = c.focus or 0,
				maxFocus = c.maxFocus or (GameConfig.FocusMax or 100),
				pointIndex = c.pointIndex,
				attack = c.attack,
				speed = c.speed,
				primaryColor = info and {info.primaryColor.R * 255, info.primaryColor.G * 255, info.primaryColor.B * 255} or {180, 180, 180},
			})
		end
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.BattleTeamsPlaced:FireClient(p, blueData, redData, king.Name, challengerName)
		end
	end

	-- Initial state snapshot for UI (HP/SP start values)
	stateDirty = true
	lastStateBroadcast = 0
	broadcastArenaState()

	task.wait(2)

	-- Run battle (pcall ensures battleInProgress is reset even on error)
	local battleOk, battleErr = pcall(runBattle)
	if not battleOk then
		warn("[Arena] runBattle error: " .. tostring(battleErr))
		battleInProgress = false
		workspace:SetAttribute("ArenaBattleInProgress", false)
		setArenaFighterAttributes(nil, nil)
		clearBattleMusicForPlayers()
		clearArenaWatchTeleportEligibility()
		clearArena()
	end
end

-- --------------------------------------
-- GET BATTLE TEAM INFO (for UI)
-- --------------------------------------

function ArenaSystem.GetPlayerBattleTeam(player)
	return getPlayerBattleTeam(player)
end

function ArenaSystem.IsBattleInProgress()
	return battleInProgress
end

function ArenaSystem.GetKingName()
	return currentKing and currentKing.Name or nil
end

function ArenaSystem.GetKingStreak()
	return kingWinStreak
end

-- Start a single gym battle in the given arena folder (e.g. OceanBiome/WaterGym).
-- Player must have an eligible battle team. Entry fee is deducted by caller (WaterGymSystem).
-- Returns: success (boolean), errorMessage (string if not success)
function ArenaSystem.StartGymBattle(player, gymFolder)
	if not player or not player.Parent then return false, "Invalid player" end
	-- FIX: Accept both Folder and Model containers (gym area may be either in Studio)
	if not gymFolder or not (gymFolder:IsA("Folder") or gymFolder:IsA("Model")) then return false, "Invalid gym folder" end
	if battleInProgress then return false, "A battle is already in progress" end
	if not hasEligibleBattleTeam(player) then
		return false, "Cannot start this gym right now."
	end
	local gymBlue = gymFolder:FindFirstChild("BlueTeam")
	local gymRed = gymFolder:FindFirstChild("RedTeam")
	if not gymBlue or not gymRed then return false, "Gym arena missing BlueTeam or RedTeam" end

	-- Save current arena context
	savedArenaFolder = arenaFolder
	savedBlueTeamFolder = blueTeamFolder
	savedRedTeamFolder = redTeamFolder
	arenaFolder = gymFolder
	blueTeamFolder = gymBlue
	redTeamFolder = gymRed
	currentKing = player
	currentChallenger = nil
	isGymBattle = true
	battleInProgress = true
	workspace:SetAttribute("ArenaBattleInProgress", true)
	setBattleMusicForPlayers(player)

	-- Clear gym arena and player base battle orbs
	clearArena()
	if BasePlacementSystem then
		pcall(function() BasePlacementSystem.ClearBattleCreatures(player) end)
	end

	local playerTeam = getPlayerBattleTeam(player)
	local gymLevel = GameConfig.WaterGymCreatureLevel or 45
	local gymTeam = generateGymTeam(gymLevel)

	-- Announce
	if arenaEvents.ArenaAnnounce then
		arenaEvents.ArenaAnnounce:FireClient(player, "WATER GYM! Battle the Gym Leader's squad!")
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				arenaEvents.ArenaAnnounce:FireClient(p, player.Name .. " is challenging the Water Gym!")
			end
		end
	end
	task.wait(2)
	clearArena()
	if BasePlacementSystem then pcall(function() BasePlacementSystem.ClearBattleCreatures(player) end) end

	-- Place teams (player = blue, gym = red)
	local redCenter = getTeamCenter(redTeamFolder)
	local blueCenter = getTeamCenter(blueTeamFolder)
	blueTeamCreatures = placeTeam(playerTeam, blueTeamFolder, "blue", 1, redCenter)
	redTeamCreatures = placeTeam(gymTeam, redTeamFolder, "red", 1, blueCenter)

	if arenaEvents.BattleTeamsPlaced then
		local blueData, redData = {}, {}
		for _, c in ipairs(blueTeamCreatures) do
			local info = CreatureData.GetById(c.creatureId)
			table.insert(blueData, {
				creatureId = c.creatureId,
				displayName = info and info.displayName or "?",
				rarity = info and info.rarity or "Common",
				hp = c.hp, maxHp = c.maxHp,
				focus = c.focus or 0,
				maxFocus = c.maxFocus or (GameConfig.FocusMax or 100),
				pointIndex = c.pointIndex,
				attack = c.attack,
				speed = c.speed,
				primaryColor = info and {info.primaryColor.R*255, info.primaryColor.G*255, info.primaryColor.B*255} or {180,180,180},
			})
		end
		for _, c in ipairs(redTeamCreatures) do
			local info = CreatureData.GetById(c.creatureId)
			table.insert(redData, {
				creatureId = c.creatureId,
				displayName = info and info.displayName or "?",
				rarity = info and info.rarity or "Common",
				hp = c.hp, maxHp = c.maxHp,
				focus = c.focus or 0,
				maxFocus = c.maxFocus or (GameConfig.FocusMax or 100),
				pointIndex = c.pointIndex,
				attack = c.attack,
				speed = c.speed,
				primaryColor = info and {info.primaryColor.R*255, info.primaryColor.G*255, info.primaryColor.B*255} or {180,180,180},
			})
		end
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.BattleTeamsPlaced:FireClient(p, blueData, redData, player.Name, "Gym Leader")
		end
	end
	stateDirty = true
	lastStateBroadcast = 0
	broadcastArenaState()
	task.wait(2)

	local ok, err = pcall(runBattle)
	if not ok then
		warn("[Arena] Gym runBattle error: " .. tostring(err))
		battleInProgress = false
		workspace:SetAttribute("ArenaBattleInProgress", false)
		setArenaFighterAttributes(nil, nil)
		clearBattleMusicForPlayers()
		clearArena()
	end

	-- Restore main arena folders
	arenaFolder = savedArenaFolder
	blueTeamFolder = savedBlueTeamFolder
	redTeamFolder = savedRedTeamFolder
	isGymBattle = false
	-- currentKing/currentChallenger left as-is; main arena loop will overwrite when next round runs

	return true
end

-- --------------------------------------
-- INIT
-- --------------------------------------

function ArenaSystem.Init(playerDataMgr, basePlacementSys)
	PlayerDataManager = playerDataMgr
	BasePlacementSystem = basePlacementSys

	-- Find arena
	arenaFolder = workspace:FindFirstChild("Arena")
	if not arenaFolder then
		warn("[Arena] No Arena folder in Workspace!")
		return
	end
	blueTeamFolder = arenaFolder:FindFirstChild("BlueTeam")
	redTeamFolder = arenaFolder:FindFirstChild("RedTeam")
	if not blueTeamFolder or not redTeamFolder then
		warn("[Arena] BlueTeam or RedTeam folder missing in Arena!")
		return
	end
	if DEV_MODE then
		logBattlePointRotations(blueTeamFolder, "BlueTeam")
		logBattlePointRotations(redTeamFolder, "RedTeam")
	end

	-- Create arena events
	local events = ReplicatedStorage:WaitForChild("Events", 10)
	local function mkEvent(name)
		local existing = events:FindFirstChild(name)
		if existing then return existing end
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = events
		return e
	end
	local function mkFunc(name)
		local existing = events:FindFirstChild(name)
		if existing then return existing end
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = events
		return f
	end

	arenaEvents.ArenaAnnounce = mkEvent("ArenaAnnounce")
	arenaEvents.ArenaWatchPrompt = mkEvent("ArenaWatchPrompt")
	arenaEvents.ArenaWatchTeleportRequest = mkEvent("ArenaWatchTeleportRequest")
	arenaEvents.ArenaReward = mkEvent("ArenaReward")
	if arenaEvents.ArenaWatchTeleportRequest then
		arenaEvents.ArenaWatchTeleportRequest.OnServerEvent:Connect(function(requestingPlayer)
			if not requestingPlayer or not requestingPlayer.Parent then return end

			local isCurrentFighter = (currentKing == requestingPlayer) or (currentChallenger == requestingPlayer)
			if not isCurrentFighter and not isArenaWatchTeleportEligible(requestingPlayer) then
				if arenaEvents.ArenaAnnounce then
					arenaEvents.ArenaAnnounce:FireClient(requestingPlayer, "Your team is not queued for an arena battle right now.")
				end
				return
			end

			local targetCf = getArenaWatchTeleportCFrame()
			local character = requestingPlayer.Character
			if not targetCf or not character then
				if arenaEvents.ArenaAnnounce then
					arenaEvents.ArenaAnnounce:FireClient(requestingPlayer, "Arena teleport is unavailable right now.")
				end
				return
			end
			local hrp = character:FindFirstChild("HumanoidRootPart")
			local hum = character:FindFirstChildOfClass("Humanoid")
			if not hrp or not hum or hum.Health <= 0 then
				if arenaEvents.ArenaAnnounce then
					arenaEvents.ArenaAnnounce:FireClient(requestingPlayer, "You must be alive to teleport to the arena.")
				end
				return
			end

			hrp.CFrame = targetCf
		end)
	end

	arenaEvents.BattleStart = mkEvent("BattleStart")
	arenaEvents.BattleEnd = mkEvent("BattleEnd")
	arenaEvents.BattleKill = mkEvent("BattleKill")
	arenaEvents.BattleTeamsPlaced = mkEvent("BattleTeamsPlaced")
	arenaEvents.ArenaStateUpdate = mkEvent("ArenaStateUpdate")

	local getBattleInfo = mkFunc("GetBattleInfo")
	getBattleInfo.OnServerInvoke = function(requestingPlayer)
		local team = getPlayerBattleTeam(requestingPlayer)
		local teamData = {}
		for _, entry in ipairs(team) do
			local info = CreatureData.GetById(entry.id)
			if info then
				table.insert(teamData, {
					uid = entry.uid,
					creatureId = entry.id,
					displayName = info.displayName,
					rarity = info.rarity,
					health = info.health,
					attack = info.attack,
					defense = info.defense,
					speed = info.speed,
					primaryColor = {info.primaryColor.R * 255, info.primaryColor.G * 255, info.primaryColor.B * 255},
				})
			end
		end
		return {
			battleTeam = teamData,
			battleTeamSize = #teamData,
			maxTeamSize = MAX_BATTLE_TEAM_SIZE,
			kingName = currentKing and currentKing.Name or nil,
			kingStreak = kingWinStreak,
			battleInProgress = battleInProgress,
			devMode = DEV_MODE,
		}
	end

	-- Log setup
	local bluePoints = getPointsSorted(blueTeamFolder)
	local redPoints = getPointsSorted(redTeamFolder)
	print("[Arena] Blue: " .. #bluePoints .. " points, Red: " .. #redPoints .. " points")
	print("[Arena] DEV_MODE: " .. tostring(DEV_MODE))
	setArenaFighterAttributes(nil, nil)

	-- Main round loop
	task.spawn(function()
		task.wait(10) -- Initial startup delay
		while true do
			print("[Arena] Next round in " .. ROUND_INTERVAL .. "s...")

			-- Countdown announcements + ArenaCountdown attribute for client timer UI
			for countdown = ROUND_INTERVAL, 1, -1 do
				workspace:SetAttribute("ArenaCountdown", countdown)
				task.wait(1)
			end
			workspace:SetAttribute("ArenaCountdown", 0)

			-- FIX #20: Wait for any active gym battles to finish before starting
			-- arena round. If a player who would fight in the arena is in a gym
			-- battle, delay (don't skip) until it completes. Max 120s wait.
			if GymBattleSystem and GymBattleSystem.AnyGymBattleActive() then
				print("[Arena] Gym battle in progress — waiting for it to finish...")
				local gymWaitStart = tick()
				local GYM_WAIT_TIMEOUT = 120
				while GymBattleSystem.AnyGymBattleActive() do
					task.wait(1)
					if tick() - gymWaitStart > GYM_WAIT_TIMEOUT then
						warn("[Arena] Gym battle wait timed out after " .. GYM_WAIT_TIMEOUT .. "s — proceeding")
						break
					end
				end
				print("[Arena] Gym battle finished, starting arena round")
			end

			-- Run the round in a protected call so errors never stall the loop
			local ok, err = pcall(function()
				startRound()
			end)
			if not ok then
				warn("[Arena] startRound error: " .. tostring(err))
			end

			-- Safety: if battle somehow got stuck, force reset after timeout
			local waitStart = tick()
			while battleInProgress do
				task.wait(1)
				if tick() - waitStart > 120 then -- 2 min max battle time
					warn("[Arena] Battle stuck! Force resetting...")
					battleInProgress = false
					workspace:SetAttribute("ArenaBattleInProgress", false)
					setArenaFighterAttributes(nil, nil)
					clearBattleMusicForPlayers()
					clearArenaWatchTeleportEligibility()
					clearArena()
					break
				end
			end

			-- Validate king still exists
			if currentKing and not currentKing.Parent then
				currentKing = nil
				kingWinStreak = 0
			end
		end
	end)

	print("[Arena] Initialized - rounds every " .. ROUND_INTERVAL .. "s")
end

-- ═══════════════════════════════════════════════════════════════════════════════
-- SetGymBattleSystem(gymBattleSys)
-- Called from MainServer AFTER both ArenaSystem and GymBattleSystem are
-- initialized. Gives ArenaSystem a reference to GymBattleSystem so it can
-- check IsPlayerInGymBattle / AnyGymBattleActive before starting rounds.
--
-- @param gymBattleSys GymBattleSystem module
-- ═══════════════════════════════════════════════════════════════════════════════
function ArenaSystem.SetGymBattleSystem(gymBattleSys)
	GymBattleSystem = gymBattleSys
	print("[Arena] GymBattleSystem reference set for mutual exclusion")
end

return ArenaSystem
