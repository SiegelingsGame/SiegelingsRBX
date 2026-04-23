-- WaterGymBattleSystem.lua - ServerScriptService (ModuleScript)
-- Separate gym battle runner for OceanBiome/WaterGym that does NOT share ArenaSystem state/round loop.

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

local WaterGymBattleSystem = {}

-- Config
local BATTLE_TICK_SPEED = 1.2
local MAX_BATTLE_TEAM_SIZE = 9
local MIN_BATTLE_TEAM_SIZE = 1
local BATTLE_CREATURE_TAG = "GymArenaCreature"
local FACING_X_CORRECTION = math.rad(0)

-- State (gym-only — fully independent from ArenaSystem)
local gymBattleInProgress = false
-- Per-gym cooldowns: playerCooldowns[cooldownKey][UserId] = tick() when cooldown expires
local playerCooldowns = {}

-- Current battle gym config (set at StartGymBattle from caller or Water defaults)
local currentGymConfig = nil

-- Battle context (set per battle)
local arenaFolder
local blueTeamFolder
local redTeamFolder
local arenaEvents = {}
local blueTeamCreatures = {}
local redTeamCreatures = {}
local currentKing -- the challenger player (blue)

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

local function getTeamCenter(folder)
	local pts = getPointsSorted(folder)
	if #pts == 0 then return nil end
	local sum = Vector3.zero
	for _, p in ipairs(pts) do sum = sum + p.part.Position end
	return sum / #pts
end

local function getPlayerBattleTeam(player)
	local data = PlayerDataManager and PlayerDataManager.GetData(player)
	if not data then return {} end
	local team = {}
	if data.battleTeam then
		for slotIndex, uid in pairs(data.battleTeam) do
			local sNum = tonumber(slotIndex)
			if sNum and uid then
				local su = tostring(uid)
				for _, entry in ipairs(data.inventory or {}) do
					if entry.uid and tostring(entry.uid) == su then
						table.insert(team, {
							id = entry.id,
							uid = entry.uid,
							slotIndex = sNum,
							level = entry.level or 1,
							xp = entry.xp or 0,
							variant = entry.variant or "Normal",
						})
						break
					end
				end
			end
			if #team >= MAX_BATTLE_TEAM_SIZE then break end
		end
	end
	table.sort(team, function(a, b) return (a.slotIndex or 0) < (b.slotIndex or 0) end)
	return team
end

-- For arena: team must be active and have enough creatures (checked by ArenaSystem).
-- For gym: only require a valid team size; inactive is allowed (arena-only check).
local function hasEligibleBattleTeam(player)
	local data = PlayerDataManager and PlayerDataManager.GetData(player)
	if not data or data.battleTeamEnabled == false then return false end
	return #getPlayerBattleTeam(player) >= (GameConfig.MinBattleTeamSize or MIN_BATTLE_TEAM_SIZE)
end

local function hasBattleTeamForGym(player)
	local data = PlayerDataManager and PlayerDataManager.GetData(player)
	if not data then return false end
	return #getPlayerBattleTeam(player) >= (GameConfig.MinBattleTeamSize or MIN_BATTLE_TEAM_SIZE)
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
	model.Name = "GymArena_" .. info.id .. "_" .. team
	model:SetAttribute("Team", team)
	model:SetAttribute("CreatureId", creatureId)
	CollectionService:AddTag(model, BATTLE_CREATURE_TAG)

	local body, core
	local isCustomModel = false

	local options = { targetSize = baseSize, creatureId = creatureId }
	body, core, isCustomModel = CreatureModelLoader.LoadAndIntegrate(model, info.modelName, info.displayName, spawnPos, options)
	if body then core = core or model:FindFirstChild("Core") end
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

	local light = Instance.new("PointLight")
	light.Color = info.primaryColor
	light.Brightness = 2
	light.Range = 14
	light.Parent = body

	if not isCustomModel then
		local hl = Instance.new("Highlight")
		hl.FillColor = rarityColor
		hl.FillTransparency = 0.75
		hl.OutlineColor = teamColor
		hl.OutlineTransparency = 0.1
		hl.Parent = model
	end

	local bb = Instance.new("BillboardGui")
	bb.Name = "InfoTag"
	bb.Adornee = body
	bb.Size = UDim2.new(0, 160, 0, 65)
	bb.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = GameConfig.ArenaSummaryShowDistance or 80  -- FIX #29: hide individual tags beyond summary distance
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

	if isCustomModel then
		local bboxCf, bboxSize = model:GetBoundingBox()
		local modelBottomY = bboxCf.Position.Y - bboxSize.Y * 0.5
		local lift = math.max(0, battlePointTopY - modelBottomY)
		if lift > 0 then
			model:PivotTo(model:GetPivot() + Vector3.new(0, lift, 0))
		end
	end

	local rotOffset = CreatureData.GetModelRotationOffset(info) or CFrame.identity
	-- Face on a flat XZ plane so arena models do not pitch upward.
	local pivotPos = model:GetPivot().Position
	local faceCf
	if faceTowardPos then
		local templateType = model:GetAttribute("TemplateType")
		if templateType == "Mesh" then
			faceCf = CFrame.new(pivotPos)
		else
			faceCf = CFrame.lookAt(pivotPos, Vector3.new(faceTowardPos.X, pivotPos.Y, faceTowardPos.Z))
		end
	else
		local templateType = model:GetAttribute("TemplateType")
		if templateType == "Mesh" then
			faceCf = CFrame.new(pivotPos)
		else
			local yaw = (team == "blue") and math.rad(180) or math.rad(-180)
			faceCf = CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0)
		end
	end
	model:PivotTo(faceCf * CFrame.Angles(FACING_X_CORRECTION, 0, 0) * rotOffset)

	CreatureAnimation.Setup(model, creatureId, "Idle")

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

local function attackVisual(attackerData, defenderData, damage)
	if not attackerData.model or not defenderData.model then return end
	local aBody = CreatureModelLoader.GetBodyPart(attackerData.model) or attackerData.model:FindFirstChild("Body")
	local dBody = CreatureModelLoader.GetBodyPart(defenderData.model) or defenderData.model:FindFirstChild("Body")
	if not aBody or not dBody then return end

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
		if dBody.Parent then
			local origColor = dBody.Color
			dBody.Color = Color3.fromRGB(255, 50, 50)
			task.wait(0.12)
			if dBody.Parent then dBody.Color = origColor end
		end
		bolt:Destroy()
	end)

	task.spawn(function()
		task.wait(0.15)
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
			local core = creatureData.model and creatureData.model:FindFirstChild("Core")
			if core then core.Size = s * 0.5; core.Transparency = i / 15 end
			RunService.Heartbeat:Wait()
		end
		if body.Parent then body.Transparency = 1 end
	end)
end

local function clearArena()
	if not arenaFolder then return end
	local function cleanFolder(folder)
		if not folder then return end
		for _, child in ipairs(folder:GetChildren()) do
			if child.Name:match("^BattlePoint") then
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

	for _, child in ipairs(arenaFolder:GetDescendants()) do
		if child:IsA("Model") and CollectionService:HasTag(child, BATTLE_CREATURE_TAG) then
			child:Destroy()
		end
	end

	blueTeamCreatures = {}
	redTeamCreatures = {}
end

-- statsPlayer: passed to GetEffectiveStats (player buffs). Use nil for AI / gym red team.
local function placeTeam(team, teamFolder, teamColor, sizeMultiplier, enemyFolder, statsPlayer)
	local points = getPointsSorted(teamFolder)
	local faceTowardPos = enemyFolder and getTeamCenter(enemyFolder)
	local pointMap = {}
	for _, p in ipairs(points) do pointMap[p.index] = p.part end

	local placed = {}
	for _, entry in ipairs(team) do
		local slotIdx = entry.slotIndex or 0
		local targetPoint = pointMap[slotIdx]
		if not targetPoint then
			for _, p in ipairs(points) do
				local taken = false
				for _, pl in ipairs(placed) do
					if pl.pointIndex == p.index then taken = true break end
				end
				if not taken then targetPoint = p.part; slotIdx = p.index; break end
			end
		end
		if not targetPoint then break end

		local info = CreatureData.GetById(entry.id)
		if info then
			local model = spawnBattleCreature(entry.id, targetPoint, teamColor, sizeMultiplier, faceTowardPos)
			if model then
				local variant = entry.variant or "Normal"
				local stats = PlayerDataManager.GetEffectiveStats(entry.id, entry.level or 1, variant, statsPlayer)
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
						focus = 0,
						maxFocus = maxFocus,
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

local function generateGymTeam(level, elements)
	level = level or (GameConfig.WaterGymCreatureLevel or 45)
	elements = elements or { "Water", "Ice", "Fire" }
	if #elements == 0 then elements = { "Water", "Poison" } end
	local team = {}
	for i = 1, 5 do
		local element = elements[(i - 1) % #elements + 1]
		local list = CreatureData.GetCreaturesByElement(element)
		if not list or #list == 0 then list = CreatureData.Creatures end
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
			table.insert(team, { id = id, uid = "gym_" .. i, level = level, xp = 0, variant = "Normal", slotIndex = i })
		end
	end
	return team
end

local function runBattle()
	-- Broadcast battle start
	if arenaEvents.BattleStart then
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.BattleStart:FireClient(p, currentKing and currentKing.Name or "?", "Gym Leader", #blueTeamCreatures, #redTeamCreatures)
		end
	end

	task.wait(2)

	local allCreatures = {}
	for _, c in ipairs(blueTeamCreatures) do table.insert(allCreatures, c) end
	for _, c in ipairs(redTeamCreatures) do table.insert(allCreatures, c) end
	table.sort(allCreatures, function(a, b) return a.speed > b.speed end)

	local battleInProgress = true
	while battleInProgress do
		local blueAlive = 0
		local redAlive = 0
		for _, c in ipairs(blueTeamCreatures) do if c.alive then blueAlive += 1 end end
		for _, c in ipairs(redTeamCreatures) do if c.alive then redAlive += 1 end end
		if blueAlive == 0 or redAlive == 0 then break end

		for _, attacker in ipairs(allCreatures) do
			if not attacker.alive or not battleInProgress then continue end

			if attacker.frozen then
				attacker.frozen = false
				task.wait(0.15)
				continue
			end

			if attacker.burnRounds and attacker.burnRounds > 0 then
				local burnDmg = math.max(1, math.floor(attacker.maxHp * (GameConfig.BurnDamagePerRound or 0.08)))
				attacker.hp -= burnDmg
				attacker.burnRounds -= 1
				updateHPBar(attacker)
				if attacker.hp <= 0 then
					attacker.alive = false
					deathVisual(attacker)
				end
				task.wait(0.2)
				if not attacker.alive then continue end
			end

			local targets = attacker.team == "blue" and redTeamCreatures or blueTeamCreatures
			local target
			local lowestHP = math.huge
			for _, t in ipairs(targets) do
				if t.alive and t.hp < lowestHP then
					lowestHP = t.hp
					target = t
				end
			end
			if not target then continue end

			local dmg = math.max(1, attacker.attack - target.defense / 3)
			local elemMult = CreatureData.GetElementalDamageMultiplier(attacker.element or "Fire", target.element or "Fire")
			if elemMult > 1 then
				dmg *= (GameConfig.ElementalAdvantageMultiplier or elemMult)
			elseif elemMult < 1 then
				dmg *= (GameConfig.ElementalDisadvantageMultiplier or elemMult)
			end
			dmg *= (0.85 + math.random() * 0.3)
			dmg = math.floor(math.max(1, dmg))

			local elem = attacker.element or "Fire"
			local isSpecial = (attacker.focus or 0) >= (attacker.maxFocus or 100)
			if isSpecial then
				attacker.focus = 0
				updateFocusBar(attacker)
				CreatureAnimation.PlayAnimation(attacker.model, "Special", attacker.creatureId)
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
					local healPct = GameConfig.WaterHealPercent or 0.20
					local healAmt = math.floor((attacker.maxHp or attacker.hp) * healPct)
					attacker.hp = math.min(attacker.maxHp or attacker.hp, (attacker.hp or 0) + healAmt)
					updateHPBar(attacker)
				end
				target.hp -= dmg
				updateHPBar(target)
				task.wait(GameConfig.SpecialAttackDuration or 2.5)
			else
				CreatureAnimation.PlayAnimation(attacker.model, "Attack", attacker.creatureId)
				target.hp -= dmg
				attackVisual(attacker, target, dmg)
				updateHPBar(target)
				attacker.focus = math.min(attacker.maxFocus or 100, (attacker.focus or 0) + (GameConfig.FocusGainPerAttack or 25))
				updateFocusBar(attacker)
				task.wait(BATTLE_TICK_SPEED / math.max(1, #allCreatures / 3))
			end

			if target.hp <= 0 then
				target.alive = false
				deathVisual(target)

				-- Kill XP only for the player side
				if attacker.team == "blue" and currentKing and currentKing.Parent and attacker.uid and not tostring(attacker.uid):match("^ai_") then
					pcall(function() PlayerDataManager.AddXP(currentKing, attacker.uid, GameConfig.BattleKillXP or 25) end)
					if PlayerDataManager.AddPlayerXP then
						pcall(function() PlayerDataManager.AddPlayerXP(currentKing, GameConfig.PlayerXP_ArenaKill or 10) end)
					end
				end

				if arenaEvents.BattleKill then
					local aInfo = CreatureData.GetById(attacker.creatureId)
					local dInfo = CreatureData.GetById(target.creatureId)
					for _, p in ipairs(Players:GetPlayers()) do
						arenaEvents.BattleKill:FireClient(p, aInfo and aInfo.displayName or "?", dInfo and dInfo.displayName or "?", attacker.team)
					end
				end
			end
		end

		task.wait(0.3)
	end

	local blueAlive = 0
	local redAlive = 0
	for _, c in ipairs(blueTeamCreatures) do if c.alive then blueAlive += 1 end end
	for _, c in ipairs(redTeamCreatures) do if c.alive then redAlive += 1 end end

	local winnerTeam = blueAlive > 0 and "blue" or "red"
	local winnerName = (winnerTeam == "blue" and currentKing and currentKing.Name) or "Gym Leader"

	if arenaEvents.BattleEnd then
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.BattleEnd:FireClient(p, winnerName or "?", winnerTeam, blueAlive, redAlive)
		end
	end

	-- Gym reward: only if player wins
	local winnerReward
	local loserReward
	if winnerTeam == "blue" and currentKing and currentKing.Parent then
		local gymReward = (currentGymConfig and currentGymConfig.winReward) or (GameConfig.WaterGymWinReward or 250)
		PlayerDataManager.AddCoins(currentKing, gymReward)
		winnerReward = { coins = gymReward }
		local winXP = (currentGymConfig and currentGymConfig.winXP) or (GameConfig.WaterGymWinXP or 75)
		if PlayerDataManager.AddPlayerXP then
			pcall(function() PlayerDataManager.AddPlayerXP(currentKing, winXP) end)
		end
		-- Zone door: gym pass (key) + SiegeKnight sigil for this outer biome
		if not currentGymConfig.skipZoneRewards then
			local zoneKey = (currentGymConfig and currentGymConfig.zoneKey) or "Ocean"
			if PlayerDataManager.AddZoneKeyFromGym then
				PlayerDataManager.AddZoneKeyFromGym(currentKing, zoneKey)
			end
			if PlayerDataManager.AddSigil then
				local hadSigil = PlayerDataManager.HasSigil(currentKing, zoneKey)
				PlayerDataManager.AddSigil(currentKing, zoneKey)
				-- Persist immediately so gym-win sigils survive disconnect before 120s auto-save.
				if PlayerDataManager.SavePlayer then
					pcall(function() PlayerDataManager.SavePlayer(currentKing) end)
				end
				if not hadSigil then
					local eventsFolder = ReplicatedStorage:FindFirstChild("Events")
					local sigilEvt = eventsFolder and eventsFolder:FindFirstChild("SigilEarned")
					if sigilEvt then
						sigilEvt:FireClient(currentKing, zoneKey)
					end
				end
			end
		end
	end

	if currentGymConfig and type(currentGymConfig.onGymBattleResolved) == "function" and currentKing then
		pcall(currentGymConfig.onGymBattleResolved, currentKing, winnerTeam == "blue")
	end

	if arenaEvents.ArenaReward then
		local gymName = (currentGymConfig and currentGymConfig.gymName) or "Water Gym"
		local payload = {
			gym = true,
			gymName = gymName,
			winner = winnerTeam == "blue" and (currentKing and currentKing.Name or "?") or "Gym Leader",
			loser = winnerTeam == "blue" and "Gym Leader" or (currentKing and currentKing.Name or "?"),
			winnerReward = winnerReward,
			loserReward = loserReward,
		}
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.ArenaReward:FireClient(p, payload)
		end
	end

	task.wait(3)
	clearArena()

	if BasePlacementSystem and currentKing and currentKing.Parent then
		pcall(function() BasePlacementSystem.RespawnBattleCreatures(currentKing) end)
	end
end

function WaterGymBattleSystem.Init(playerDataMgr, basePlacementSys)
	PlayerDataManager = playerDataMgr
	BasePlacementSystem = basePlacementSys

	local events = ReplicatedStorage:FindFirstChild("Events") or Instance.new("Folder")
	events.Name = "Events"
	events.Parent = ReplicatedStorage

	local function mkEvent(name)
		local e = events:FindFirstChild(name)
		if e then return e end
		e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = events
		return e
	end

	-- Gym-specific events so it doesn't collide with standard arena battles
	arenaEvents.ArenaAnnounce = mkEvent("GymArenaAnnounce")
	arenaEvents.ArenaReward = mkEvent("GymArenaReward")
	arenaEvents.BattleStart = mkEvent("GymBattleStart")
	arenaEvents.BattleEnd = mkEvent("GymBattleEnd")
	arenaEvents.BattleKill = mkEvent("GymBattleKill")
	arenaEvents.BattleTeamsPlaced = mkEvent("GymBattleTeamsPlaced")

	-- GetBattleTimers: client polls this to display arena + gym countdowns in the battle menu.
	local function mkFunc(name)
		local f = events:FindFirstChild(name)
		if not f then f = Instance.new("RemoteFunction"); f.Name = name; f.Parent = events end
		return f
	end
	local getBattleTimers = mkFunc("GetBattleTimers")
	getBattleTimers.OnServerInvoke = function(requestingPlayer)
		local arenaCountdown = workspace:GetAttribute("ArenaCountdown") or 0
		local arenaInProgress = workspace:GetAttribute("ArenaBattleInProgress") or false
		local gymInProgress = workspace:GetAttribute("GymBattleInProgress") or false
		local gymCooldown = WaterGymBattleSystem.GetCooldownRemaining(requestingPlayer)
		local arenaFighterBlueName = workspace:GetAttribute("ArenaFighterBlueName")
		local arenaFighterRedName = workspace:GetAttribute("ArenaFighterRedName")
		return {
			arenaCountdown = arenaCountdown,
			arenaBattleInProgress = arenaInProgress,
			gymBattleInProgress = gymInProgress,
			gymCooldownRemaining = gymCooldown,
			arenaFighterBlueName = arenaFighterBlueName,
			arenaFighterRedName = arenaFighterRedName,
		}
	end

	-- Initialize workspace attributes
	workspace:SetAttribute("GymBattleInProgress", false)

	-- Clean up cooldowns when players leave (per-gym and legacy)
	Players.PlayerRemoving:Connect(function(plr)
		playerCooldowns[plr.UserId] = nil
		for _, byKey in pairs(playerCooldowns) do
			if type(byKey) == "table" then byKey[plr.UserId] = nil end
		end
	end)

	print("[GymBattle] Initialized — cooldown " .. (GameConfig.WaterGymCooldown or 120) .. "s per player")
end

--- Get remaining cooldown seconds for a player (0 = ready). cooldownKey optional (default "WaterGym").
function WaterGymBattleSystem.GetCooldownRemaining(player, cooldownKey)
	if not player then return 0 end
	cooldownKey = cooldownKey or "WaterGym"
	local byKey = playerCooldowns[cooldownKey]
	local exp = byKey and byKey[player.UserId]
	if not exp then
		-- Legacy: single global cooldown (WaterGym only)
		exp = playerCooldowns[player.UserId]
	end
	if not exp or tick() >= exp then return 0 end
	return math.ceil(exp - tick())
end

-- Start a gym battle in the given gymFolder. config optional; when nil, uses Water Gym defaults.
-- config: { gymName, elements, level, winReward, winXP, cooldown, zoneKey, cooldownKey }
function WaterGymBattleSystem.StartGymBattle(player, gymFolder, config)
	if not player or not player.Parent then return false, "Invalid player" end
	if not gymFolder or not (gymFolder:IsA("Folder") or gymFolder:IsA("Model")) then return false, "Invalid gym folder" end
	if gymBattleInProgress then return false, "A gym battle is already in progress" end
	-- FIX: Mutual exclusion — can't start gym while arena battle is running
	if workspace:GetAttribute("ArenaBattleInProgress") then
		return false, "You cannot fight in a gym and arena at the same time. Wait for the arena battle to finish."
	end
	-- Default to Ocean/Water Gym config when config is nil (Water + Poison)
	currentGymConfig = config or {
		gymName = "Water Gym",
		elements = { "Water", "Poison" },
		level = GameConfig.WaterGymCreatureLevel or 45,
		winReward = GameConfig.WaterGymWinReward or 250,
		winXP = GameConfig.WaterGymWinXP or 75,
		cooldown = GameConfig.WaterGymCooldown or 120,
		zoneKey = "Ocean",
		cooldownKey = "WaterGym",
	}
	local cooldownKey = currentGymConfig.cooldownKey or "WaterGym"
	local remaining = WaterGymBattleSystem.GetCooldownRemaining(player, cooldownKey)
	if remaining > 0 then
		return false, "Gym cooldown: " .. remaining .. "s remaining."
	end
	if not hasBattleTeamForGym(player) then
		return false, "Cannot start gym without a battle team. Set one in your inventory (Battle tab)."
	end

	local gymBlue = gymFolder:FindFirstChild("BlueTeam")
	local gymRed = gymFolder:FindFirstChild("RedTeam")
	if not gymBlue or not gymRed then return false, "Gym arena missing BlueTeam or RedTeam" end

	gymBattleInProgress = true
	workspace:SetAttribute("GymBattleInProgress", true)
	arenaFolder = gymFolder
	blueTeamFolder = gymBlue
	redTeamFolder = gymRed
	currentKing = player

	-- Instance-based battle music: only the participant hears battle theme
	if player and player.Parent then player:SetAttribute("InBattleMusic", true) end

	-- Clear gym arena and base battle orbs for this player
	clearArena()
	if BasePlacementSystem then
		pcall(function() BasePlacementSystem.ClearBattleCreatures(player) end)
	end

	local gymName = currentGymConfig.gymName or "Water Gym"
	-- Announce (gym-only)
	if arenaEvents.ArenaAnnounce then
		arenaEvents.ArenaAnnounce:FireClient(player, (gymName):upper() .. "! Battle the Gym Leader's squad!")
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player then
				arenaEvents.ArenaAnnounce:FireClient(p, player.Name .. " is challenging the " .. gymName .. "!")
			end
		end
	end

	task.wait(2)
	clearArena()
	if BasePlacementSystem then pcall(function() BasePlacementSystem.ClearBattleCreatures(player) end) end

	local playerTeam = getPlayerBattleTeam(player)
	local level = currentGymConfig.level or (GameConfig.WaterGymCreatureLevel or 45)
	local gymTeam
	if type(currentGymConfig.opponentTeam) == "table" and #currentGymConfig.opponentTeam > 0 then
		gymTeam = currentGymConfig.opponentTeam
	else
		gymTeam = generateGymTeam(level, currentGymConfig.elements)
	end

	local redCenter = getTeamCenter(redTeamFolder)
	local blueCenter = getTeamCenter(blueTeamFolder)
	blueTeamCreatures = placeTeam(playerTeam, blueTeamFolder, "blue", 1, redTeamFolder, currentKing)
	redTeamCreatures = placeTeam(gymTeam, redTeamFolder, "red", 1, blueTeamFolder, nil)

	if arenaEvents.BattleTeamsPlaced then
		local blueData, redData = {}, {}
		for _, c in ipairs(blueTeamCreatures) do
			local info = CreatureData.GetById(c.creatureId)
			table.insert(blueData, {
				creatureId = c.creatureId,
				displayName = info and info.displayName or "?",
				rarity = info and info.rarity or "Common",
				hp = c.hp, maxHp = c.maxHp, pointIndex = c.pointIndex,
				primaryColor = info and {info.primaryColor.R * 255, info.primaryColor.G * 255, info.primaryColor.B * 255} or {180, 180, 180},
			})
		end
		for _, c in ipairs(redTeamCreatures) do
			local info = CreatureData.GetById(c.creatureId)
			table.insert(redData, {
				creatureId = c.creatureId,
				displayName = info and info.displayName or "?",
				rarity = info and info.rarity or "Common",
				hp = c.hp, maxHp = c.maxHp, pointIndex = c.pointIndex,
				primaryColor = info and {info.primaryColor.R * 255, info.primaryColor.G * 255, info.primaryColor.B * 255} or {180, 180, 180},
			})
		end
		for _, p in ipairs(Players:GetPlayers()) do
			arenaEvents.BattleTeamsPlaced:FireClient(p, blueData, redData, player.Name, "Gym Leader")
		end
	end

	task.wait(2)

	local ok, err = pcall(runBattle)
	if not ok then
		warn("[WaterGymBattle] runBattle error: " .. tostring(err))
		clearArena()
	end

	-- Set per-player cooldown for this gym type
	local ck = (currentGymConfig and currentGymConfig.cooldownKey) or "WaterGym"
	local cooldownDuration = (currentGymConfig and currentGymConfig.cooldown) or (GameConfig.WaterGymCooldown or 120)
	if not playerCooldowns[ck] then playerCooldowns[ck] = {} end
	playerCooldowns[ck][player.UserId] = tick() + cooldownDuration

	-- Clear battle music for the participant
	if currentKing and currentKing.Parent then currentKing:SetAttribute("InBattleMusic", nil) end

	-- Clear context
	currentGymConfig = nil
	currentKing = nil
	arenaFolder = nil
	blueTeamFolder = nil
	redTeamFolder = nil
	blueTeamCreatures = {}
	redTeamCreatures = {}
	gymBattleInProgress = false
	workspace:SetAttribute("GymBattleInProgress", false)

	return true
end

function WaterGymBattleSystem.IsBattleInProgress()
	return gymBattleInProgress
end

return WaterGymBattleSystem

