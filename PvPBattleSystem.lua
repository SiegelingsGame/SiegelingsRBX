-- PvPBattleSystem.lua - ServerScriptService (ModuleScript)
-- Player vs Player 1v1 battle: interact with a nearby player to spawn red/blue
-- battle points, your favorite monster vs theirs, winner gets gold.
--
-- Flow:
--   1. Player A fires RequestPvPBattle(B's UserId) when close to B
--   2. Server validates: both in game, within PvPInteractionRange, both have favorite creature
--   3. Spawn two battle points (red & blue) at a midpoint between them, facing each other
--   4. Spawn each player's favorite creature on their point; run 1v1 auto-battle (arena rules)
--   5. Winner gets gold, loser loses gold; favorite companion hidden until battle ends.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local CreatureAnimation = require(ReplicatedStorage.Modules.CreatureAnimation)

local PlayerDataManager
local FavoriteCreatureSystem
local PvPLeaderboardSystem  -- optional: records wins/losses for per-server PvP leaderboard

local PvPBattleSystem = {}

local BATTLE_CREATURE_TAG = "PvPCreature"
local INTERACTION_RANGE = GameConfig.PvPInteractionRange or 20
local WIN_GOLD = GameConfig.PvPWinGold or 10
local LOSER_GOLD_LOSS = GameConfig.PvPLoserGoldLoss or 10
local POINT_SPACING = GameConfig.PvPBattlePointSpacing or 16
local BATTLE_TICK = GameConfig.PvPBattleTickSpeed or 1.2
-- X rotation (degrees) to correct model tilt when facing enemy; tweak to fix upright stance (-90, 0, 90, 180, etc.)
local FACING_X_CORRECTION = math.rad(0)

local activeBattle = false
local pvpEvents = {}
-- Pending challenges: [targetUserId] = requesterUserId (who challenged whom)
local pendingChallenges = {}

-- --------------------------------------
-- HELPERS
-- --------------------------------------

local function getPlayerRoot(player)
	local char = player and player.Character
	if not char then return nil end
	return char:FindFirstChild("HumanoidRootPart")
end

local function distanceBetween(a, b)
	local ra, rb = getPlayerRoot(a), getPlayerRoot(b)
	if not ra or not rb then return math.huge end
	return (ra.Position - rb.Position).Magnitude
end

-- --------------------------------------
-- SPAWN PvP BATTLE CREATURE (mirrors Arena spawn, parent = battleFolder)
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

local function spawnPvPCreature(creatureId, battlePoint, team, parentFolder, sizeMultiplier, faceTowardPos)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local rarityInfo = CreatureData.Rarities[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(180, 180, 180)
	local baseSize = 4 * (sizeMultiplier or 1)
	local teamColor = team == "blue" and Color3.fromRGB(60, 120, 255) or Color3.fromRGB(255, 70, 70)
	local spawnPos = battlePoint.Position + Vector3.new(0, baseSize / 2 + 1, 0)
	local battlePointTopY = battlePoint.Position.Y + (battlePoint.Size.Y * 0.5)

	local model = Instance.new("Model")
	model.Name = "PvP_" .. info.id .. "_" .. team
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
		body = Instance.new("Part")
		body.Name = "Body"
		body.Shape = Enum.PartType.Ball
		body.Size = Vector3.new(baseSize, baseSize, baseSize)
		body.Color = info.primaryColor
		body.Material = Enum.Material.Neon
		body.Anchored = true
		body.CanCollide = false
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
	model.Parent = parentFolder

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

	-- Face toward enemy spawn (blue toward red, red toward blue)
	-- 90° Y rotation only for full models (TemplateType="Model"); mesh types need no yaw correction
	local pivotPos = model:GetPivot().Position
	local faceCf
	if faceTowardPos then
		faceCf = CFrame.lookAt(pivotPos, Vector3.new(faceTowardPos.X, pivotPos.Y, faceTowardPos.Z))
	else
		local templateType = model:GetAttribute("TemplateType")
		if templateType == "Mesh" then
			faceCf = CFrame.new(pivotPos)  -- Mesh: no 90° Y rotation
		else
			local yaw = (team == "blue") and math.rad(90) or math.rad(-90)
			faceCf = CFrame.new(pivotPos) * CFrame.Angles(0, yaw, 0)
		end
	end
	model:PivotTo(faceCf * CFrame.Angles(FACING_X_CORRECTION, 0, 0) * rotOffset)

	-- Billboard at top of bounding box so name isn't blocked (set after placement)
	local bb = model:FindFirstChild("InfoTag")
	if bb then
		bb.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)
	end

	CreatureAnimation.Setup(model, creatureId, "Idle")
	return model
end

-- Orient one combatant's model to face the other (flat XZ so they don't tilt)
local function orientModelToward(model, otherModel)
	if not model or not model.Parent or not otherModel or not otherModel.Parent then return end
	local body = CreatureModelLoader.GetBodyPart(model) or model:FindFirstChild("Body")
	local otherBody = CreatureModelLoader.GetBodyPart(otherModel) or otherModel:FindFirstChild("Body")
	if not body or not otherBody then return end
	local pos = model:GetPivot().Position
	local diff = otherBody.Position - pos
	local flat = Vector3.new(diff.X, 0, diff.Z)
	if flat.Magnitude < 0.01 then return end
	model:PivotTo(CFrame.lookAt(pos, pos + flat))
end

local function updateHPBar(cData)
	if not cData.model or not cData.model.Parent then return end
	local bb = cData.model:FindFirstChild("InfoTag")
	if not bb then return end
	local fill = bb:FindFirstChild("HPBarBG") and bb.HPBarBG:FindFirstChild("HPFill")
	local label = bb:FindFirstChild("HPLabel")
	local pct = math.clamp(cData.hp / cData.maxHp, 0, 1)
	if fill then
		fill.Size = UDim2.new(pct, 0, 1, 0)
		if pct > 0.5 then fill.BackgroundColor3 = Color3.fromRGB(50, 220, 80)
		elseif pct > 0.25 then fill.BackgroundColor3 = Color3.fromRGB(220, 180, 40)
		else fill.BackgroundColor3 = Color3.fromRGB(220, 50, 50) end
	end
	if label then label.Text = math.max(0, math.floor(cData.hp)) .. "/" .. cData.maxHp end
end

local function updateFocusBar(cData)
	if not cData.model or not cData.model.Parent then return end
	local bb = cData.model:FindFirstChild("InfoTag")
	if not bb then return end
	local focusBg = bb:FindFirstChild("FocusBarBG")
	if not focusBg then return end
	local fill = focusBg:FindFirstChild("FocusFill")
	if not fill then return end
	local pct = math.clamp((cData.focus or 0) / (cData.maxFocus or 100), 0, 1)
	fill.Size = UDim2.new(pct, 0, 1, 0)
end

local function attackVisual(attackerData, defenderData, damage, parentFolder)
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
	bolt.Parent = parentFolder

	task.spawn(function()
		local from, to = aBody.Position, dBody.Position
		local dur = math.clamp((to - from).Magnitude / 80, 0.08, 0.3)
		local startT = tick()
		while tick() - startT < dur do
			bolt.Position = from:Lerp(to, (tick() - startT) / dur)
			RunService.Heartbeat:Wait()
		end
		if dBody.Parent then
			local orig = dBody.Color
			dBody.Color = Color3.fromRGB(255, 50, 50)
			task.wait(0.12)
			if dBody.Parent then dBody.Color = orig end
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
		dmgPart.Parent = parentFolder

		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.new(0, 70, 0, 28)
		gui.Adornee = dmgPart
		gui.AlwaysOnTop = true
		gui.Parent = dmgPart

		local lbl = Instance.new("TextLabel")
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Text = "-" .. math.floor(damage)
		lbl.TextColor3 = Color3.fromRGB(255, 80, 60)
		lbl.Font = Enum.Font.GothamBlack
		lbl.TextScaled = true
		lbl.TextStrokeColor3 = Color3.new(0, 0, 0)
		lbl.TextStrokeTransparency = 0.3
		lbl.Parent = gui

		for i = 1, 25 do
			dmgPart.Position = dmgPart.Position + Vector3.new(0, 0.08, 0)
			lbl.TextTransparency = i / 25
			lbl.TextStrokeTransparency = 0.3 + (i / 25) * 0.7
			RunService.Heartbeat:Wait()
		end
		dmgPart:Destroy()
	end)
end

local function deathVisual(cData)
	if not cData.model or not cData.model.Parent then return end
	local body = CreatureModelLoader.GetBodyPart(cData.model) or cData.model:FindFirstChild("Body")
	if not body then return end
	task.spawn(function()
		for i = 1, 15 do
			if not body.Parent then return end
			body.Size = body.Size * 0.9
			body.Transparency = i / 15
			local core = cData.model:FindFirstChild("Core")
			if core then core.Size = core.Size * 0.9; core.Transparency = i / 15 end
			RunService.Heartbeat:Wait()
		end
		if body.Parent then body.Transparency = 1 end
	end)
end

-- --------------------------------------
-- RUN 1v1 BATTLE
-- --------------------------------------

local function run1v1Battle(battleFolder, blueData, redData, bluePlayer, redPlayer)
	local blue = blueData[1]
	local red = redData[1]
	if not blue or not red then return nil, nil end

	local allCreatures = { blue, red }
	table.sort(allCreatures, function(a, b) return a.speed > b.speed end)

	while true do
		local bAlive = blue.alive
		local rAlive = red.alive
		if not bAlive or not rAlive then break end

		for _, attacker in ipairs(allCreatures) do
			if not attacker.alive then continue end

			if attacker.frozen then
				attacker.frozen = false
				task.wait(0.15)
				continue
			end

			if attacker.burnRounds and attacker.burnRounds > 0 then
				local burnDmg = math.max(1, math.floor(attacker.maxHp * (GameConfig.BurnDamagePerRound or 0.08)))
				attacker.hp = attacker.hp - burnDmg
				attacker.burnRounds = attacker.burnRounds - 1
				updateHPBar(attacker)
				if attacker.hp <= 0 then
					attacker.alive = false
					deathVisual(attacker)
				end
				task.wait(0.2)
				if not attacker.alive then continue end
			end

			local target = (attacker.team == "blue") and red or blue
			if not target.alive then continue end

			local dmg = math.max(1, attacker.attack - target.defense / 3)
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
			dmg = dmg * (0.85 + math.random() * 0.3)
			dmg = math.floor(math.max(1, dmg))

			local isSpecial = (attacker.focus or 0) >= (attacker.maxFocus or 100)
			local elem = attacker.element or "Fire"

			if isSpecial then
				attacker.focus = 0
				updateFocusBar(attacker)
				CreatureAnimation.PlayAnimation(attacker.model, "Special", attacker.creatureId)
				if elem == "Fire" then target.burnRounds = GameConfig.BurnDuration or 3
				elseif elem == "Ice" then target.frozen = true
				elseif elem == "Earth" then target.dmgReductionRounds = GameConfig.EarthDebuffDuration or 3
				elseif elem == "Wind" then
					target.focus = math.max(0, (target.focus or 0) - (GameConfig.WindFocusDrain or 50))
					updateFocusBar(target)
				elseif elem == "Water" then
					local healPct = GameConfig.WaterHealPercent or 0.20
					local healAmt = math.floor((attacker.maxHp or attacker.hp) * healPct)
					attacker.hp = math.min(attacker.maxHp or attacker.hp, (attacker.hp or 0) + healAmt)
					updateHPBar(attacker)
				end
				target.hp = target.hp - dmg
				updateHPBar(target)
				attackVisual(attacker, target, dmg, battleFolder)
				task.wait(GameConfig.SpecialAttackDuration or 2.5)
			else
				CreatureAnimation.PlayAnimation(attacker.model, "Attack", attacker.creatureId)
				target.hp = target.hp - dmg
				attackVisual(attacker, target, dmg, battleFolder)
				updateHPBar(target)
				attacker.focus = math.min(attacker.maxFocus or 100, (attacker.focus or 0) + (GameConfig.FocusGainPerAttack or 25))
				updateFocusBar(attacker)
				task.wait(BATTLE_TICK)
			end

			if target.hp <= 0 then
				target.alive = false
				deathVisual(target)
				if PlayerDataManager.AddXP then
					local owner = attacker.team == "blue" and bluePlayer or redPlayer
					if owner and owner.Parent and attacker.uid then
						PlayerDataManager.AddXP(owner, attacker.uid, GameConfig.BattleKillXP or 25)
					end
				end
			end
		end
		task.wait(0.3)
	end

	local winnerTeam = blue.alive and "blue" or "red"
	local winnerPlayer = (winnerTeam == "blue") and bluePlayer or redPlayer
	local loserPlayer = (winnerTeam == "blue") and redPlayer or bluePlayer
	return winnerPlayer, loserPlayer
end

-- --------------------------------------
-- START PvP BATTLE
-- --------------------------------------

local function startPvPBattle(requester, target)
	if activeBattle then
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, "A PvP battle is already in progress.")
		end
		return
	end

	local reqRoot = getPlayerRoot(requester)
	local targRoot = getPlayerRoot(target)
	if not reqRoot or not targRoot then
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, "Could not find player positions.")
		end
		print("[PvP] Reject: could not find player positions (reqRoot=" .. tostring(reqRoot ~= nil) .. " targRoot=" .. tostring(targRoot ~= nil) .. ")")
		return
	end

	local dist = (reqRoot.Position - targRoot.Position).Magnitude
	if dist > INTERACTION_RANGE then
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, "Too far away! Get within " .. INTERACTION_RANGE .. " studs to challenge.")
		end
		print("[PvP] Reject: too far (dist=" .. math.floor(dist) .. ", need " .. INTERACTION_RANGE .. ")")
		return
	end

	local favReq = PlayerDataManager.GetFavorite(requester)
	local favTarg = PlayerDataManager.GetFavorite(target)
	if not favReq then
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, "You need a favorite creature to PvP! Set one in Inventory.")
		end
		print("[PvP] Reject: requester has no favorite")
		return
	end
	if not favTarg then
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, target.Name .. " has no favorite creature set.")
		end
		print("[PvP] Reject: target has no favorite")
		return
	end

	-- Arena battle in progress check (optional: block PvP during arena)
	local arenaInProgress = workspace:GetAttribute("ArenaBattleInProgress")
	if arenaInProgress then
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, "Wait for the arena battle to finish.")
		end
		print("[PvP] Reject: arena battle in progress")
		return
	end

	print("[PvP] Starting battle: " .. requester.Name .. " vs " .. target.Name)
	activeBattle = true

	-- Hide favorite companion from both players until battle ends
	if FavoriteCreatureSystem then
		pcall(function() FavoriteCreatureSystem.DespawnCompanion(requester) end)
		pcall(function() FavoriteCreatureSystem.DespawnCompanion(target) end)
	end

	-- Midpoint between players (XZ), same Y as ground between them
	local mid = (reqRoot.Position + targRoot.Position) * 0.5
	local dir = (targRoot.Position - reqRoot.Position) * Vector3.new(1, 0, 1)
	if dir.Magnitude < 0.1 then dir = Vector3.new(1, 0, 0) end
	dir = dir.Unit

	local half = POINT_SPACING * 0.5
	local bluePos = mid - dir * half
	local redPos = mid + dir * half

	local battleFolder = Instance.new("Folder")
	battleFolder.Name = "PvPBattle_" .. requester.UserId .. "_" .. target.UserId
	battleFolder.Parent = workspace

	local bluePoint = Instance.new("Part")
	bluePoint.Name = "BattlePoint1"
	bluePoint.Size = Vector3.new(6, 0.5, 6)
	bluePoint.Position = bluePos
	bluePoint.Anchored = true
	bluePoint.CanCollide = false
	bluePoint.Transparency = 1
	bluePoint.Parent = battleFolder

	local redPoint = Instance.new("Part")
	redPoint.Name = "BattlePoint1"
	redPoint.Size = Vector3.new(6, 0.5, 6)
	redPoint.Position = redPos
	redPoint.Anchored = true
	redPoint.CanCollide = false
	redPoint.Transparency = 1
	redPoint.Parent = battleFolder

	local infoReq = CreatureData.GetById(favReq.id)
	local infoTarg = CreatureData.GetById(favTarg.id)
	if not infoReq or not infoTarg then
		activeBattle = false
		battleFolder:Destroy()
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, "Invalid creature data.")
		end
		print("[PvP] Reject: invalid creature data")
		return
	end

	-- Use GetEffectiveStats so level, tier (variant), and rarity scale attack/def/health/speed
	local statsReq = PlayerDataManager.GetEffectiveStats and PlayerDataManager.GetEffectiveStats(favReq.id, favReq.level or 1, favReq.variant or "Normal", requester)
	local statsTarg = PlayerDataManager.GetEffectiveStats and PlayerDataManager.GetEffectiveStats(favTarg.id, favTarg.level or 1, favTarg.variant or "Normal", target)
	if not statsReq then
		statsReq = { health = infoReq.health, attack = infoReq.attack, defense = infoReq.defense, speed = infoReq.speed }
		local lvl = favReq.level or 1
		local mult = 1 + (GameConfig.StatGainPerLevel or 0.08) * (lvl - 1)
		statsReq.health = math.floor(statsReq.health * mult)
		statsReq.attack = math.floor(statsReq.attack * mult)
		statsReq.defense = math.floor(statsReq.defense * mult)
		statsReq.speed = math.floor(statsReq.speed * mult)
	end
	if not statsTarg then
		statsTarg = { health = infoTarg.health, attack = infoTarg.attack, defense = infoTarg.defense, speed = infoTarg.speed }
		local lvl = favTarg.level or 1
		local mult = 1 + (GameConfig.StatGainPerLevel or 0.08) * (lvl - 1)
		statsTarg.health = math.floor(statsTarg.health * mult)
		statsTarg.attack = math.floor(statsTarg.attack * mult)
		statsTarg.defense = math.floor(statsTarg.defense * mult)
		statsTarg.speed = math.floor(statsTarg.speed * mult)
	end

	local maxFocus = GameConfig.FocusMax or 100

	local blueEntry = {
		model = nil,
		creatureId = favReq.id,
		uid = favReq.uid,
		hp = statsReq.health,
		maxHp = statsReq.health,
		attack = statsReq.attack,
		defense = statsReq.defense,
		speed = statsReq.speed,
		level = favReq.level or 1,
		alive = true,
		team = "blue",
		element = infoReq.element or "Fire",
		focus = 0,
		maxFocus = maxFocus,
		burnRounds = 0,
		frozen = false,
		dmgReductionRounds = 0,
	}

	local redEntry = {
		model = nil,
		creatureId = favTarg.id,
		uid = favTarg.uid,
		hp = statsTarg.health,
		maxHp = statsTarg.health,
		attack = statsTarg.attack,
		defense = statsTarg.defense,
		speed = statsTarg.speed,
		level = favTarg.level or 1,
		alive = true,
		team = "red",
		element = infoTarg.element or "Fire",
		focus = 0,
		maxFocus = maxFocus,
		burnRounds = 0,
		frozen = false,
		dmgReductionRounds = 0,
	}

	blueEntry.model = spawnPvPCreature(favReq.id, bluePoint, "blue", battleFolder, 1, redPoint.Position)
	redEntry.model = spawnPvPCreature(favTarg.id, redPoint, "red", battleFolder, 1, bluePoint.Position)
	if not blueEntry.model or not redEntry.model then
		activeBattle = false
		battleFolder:Destroy()
		if FavoriteCreatureSystem then
			pcall(function() FavoriteCreatureSystem.SpawnCompanion(requester) end)
			pcall(function() FavoriteCreatureSystem.SpawnCompanion(target) end)
		end
		if pvpEvents.PvPBattleReject then
			pvpEvents.PvPBattleReject:FireClient(requester, "Failed to spawn creatures.")
		end
		print("[PvP] Reject: failed to spawn creatures")
		return
	end

	-- Notify TARGET that they're being challenged (so they always get a notice)
	if pvpEvents.PvPChallengeNotice then
		pvpEvents.PvPChallengeNotice:FireClient(target, requester.Name)
		print("[PvP] Fired PvPChallengeNotice -> " .. target.Name .. " (challenger: " .. requester.Name .. ")")
	end
	-- Notify both players that battle is starting
	if pvpEvents.PvPBattleStart then
		pvpEvents.PvPBattleStart:FireClient(requester, requester.Name, target.Name, target.UserId)
		pvpEvents.PvPBattleStart:FireClient(target, requester.Name, target.Name, requester.UserId)
		print("[PvP] Fired PvPBattleStart -> requester " .. requester.Name .. ", target " .. target.Name)
	end

	task.wait(2)

	local winnerPlayer, loserPlayer = run1v1Battle(battleFolder, { blueEntry }, { redEntry }, requester, target)

	-- Record for PvP leaderboard (per-server, resets on server restart)
	if (winnerPlayer or loserPlayer) and PvPLeaderboardSystem and PvPLeaderboardSystem.RecordPvPResult then
		PvPLeaderboardSystem.RecordPvPResult(winnerPlayer, loserPlayer)
	end

	-- Rewards
	if winnerPlayer and winnerPlayer.Parent then
		PlayerDataManager.AddCoins(winnerPlayer, WIN_GOLD)
		if PlayerDataManager.AddXP then
			PlayerDataManager.AddXP(winnerPlayer, winnerPlayer == requester and favReq.uid or favTarg.uid, GameConfig.BattleWinXP or 40)
		end
		local d = PlayerDataManager.GetData(winnerPlayer)
		if d then
			local ev = ReplicatedStorage:FindFirstChild("Events")
			local coinsEvt = ev and ev:FindFirstChild("CoinsUpdate")
			if coinsEvt then coinsEvt:FireClient(winnerPlayer, d.coins) end
		end
	end
	if loserPlayer and loserPlayer.Parent then
		PlayerDataManager.AddCoins(loserPlayer, -LOSER_GOLD_LOSS)
		local d = PlayerDataManager.GetData(loserPlayer)
		if d then
			local ev = ReplicatedStorage:FindFirstChild("Events")
			local coinsEvt = ev and ev:FindFirstChild("CoinsUpdate")
			if coinsEvt then coinsEvt:FireClient(loserPlayer, d.coins) end
		end
	end

	local winnerName = winnerPlayer and winnerPlayer.Name or "?"
	if pvpEvents.PvPBattleEnd then
		pvpEvents.PvPBattleEnd:FireClient(requester, winnerName, winnerPlayer == requester, WIN_GOLD, LOSER_GOLD_LOSS)
		pvpEvents.PvPBattleEnd:FireClient(target, winnerName, winnerPlayer == target, WIN_GOLD, LOSER_GOLD_LOSS)
	end

	-- Cleanup after a short delay
	task.wait(3)
	for _, child in ipairs(battleFolder:GetDescendants()) do
		if child:IsA("Model") and CollectionService:HasTag(child, BATTLE_CREATURE_TAG) then
			child:Destroy()
		end
	end
	battleFolder:Destroy()

	-- Winner: restore companion. Loser: put creature in faint state and show revive prompt (no companion until they pay)
	local coinCost = GameConfig.PvPReviveCoinCost or 25
	local gemCost = GameConfig.PvPReviveGemCost or 2
	if FavoriteCreatureSystem then
		pcall(function()
			if winnerPlayer and winnerPlayer.Parent and PlayerDataManager.GetFavorite(winnerPlayer) then
				FavoriteCreatureSystem.SpawnCompanion(winnerPlayer)
			end
		end)
		pcall(function()
			if loserPlayer and loserPlayer.Parent then
				FavoriteCreatureSystem.SetPvPFainted(loserPlayer, true)
				local loserFav = loserPlayer == requester and favReq or favTarg
				local loserInfo = loserFav and CreatureData.GetById(loserFav.id)
				local creatureName = (loserInfo and loserInfo.displayName) or "Creature"
				if pvpEvents.PvPRevivePrompt then
					pvpEvents.PvPRevivePrompt:FireClient(loserPlayer, creatureName, coinCost, gemCost)
				end
			end
		end)
	end

	activeBattle = false

	print("[PvP] Battle over. Winner: " .. winnerName .. " (+" .. WIN_GOLD .. " gold), loser -" .. LOSER_GOLD_LOSS .. " gold")
end

-- --------------------------------------
-- INIT & REMOTES
-- --------------------------------------

function PvPBattleSystem.Init(playerDataMgr, favoriteCreatureSys, leaderboardSys)
	PlayerDataManager = playerDataMgr
	FavoriteCreatureSystem = favoriteCreatureSys
	PvPLeaderboardSystem = leaderboardSys

	local events = ReplicatedStorage:WaitForChild("Events", 10)
	if not events then return end

	local function mkEvent(name)
		local existing = events:FindFirstChild(name)
		if existing then return existing end
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = events
		return e
	end

	pvpEvents.PvPBattleStart = mkEvent("PvPBattleStart")
	pvpEvents.PvPBattleEnd = mkEvent("PvPBattleEnd")
	pvpEvents.PvPBattleReject = mkEvent("PvPBattleReject")
	local pvpChallengeInvite = events:FindFirstChild("PvPChallengeInvite")
	local pvpAcceptChallenge = events:FindFirstChild("PvPAcceptChallenge")
	local pvpDeclineChallenge = events:FindFirstChild("PvPDeclineChallenge")

	local requestPvP = events:FindFirstChild("RequestPvPBattle")
	if not requestPvP then
		requestPvP = Instance.new("RemoteEvent")
		requestPvP.Name = "RequestPvPBattle"
		requestPvP.Parent = events
	end

	pvpEvents.PvPChallengeNotice = mkEvent("PvPChallengeNotice")
	pvpEvents.PvPRevivePrompt = mkEvent("PvPRevivePrompt")
	pvpEvents.PvPReviveSuccess = mkEvent("PvPReviveSuccess")

	local pvpReviveWith = events:FindFirstChild("PvPReviveWith")
	if not pvpReviveWith then
		pvpReviveWith = Instance.new("RemoteEvent")
		pvpReviveWith.Name = "PvPReviveWith"
		pvpReviveWith.Parent = events
	end
	pvpReviveWith.OnServerEvent:Connect(function(revivingPlayer, currency)
		if not revivingPlayer or not FavoriteCreatureSystem then return end
		if not FavoriteCreatureSystem.IsPvPFainted(revivingPlayer) then return end
		local coinCost = GameConfig.PvPReviveCoinCost or 25
		local gemCost = GameConfig.PvPReviveGemCost or 2
		if currency == "coins" then
			if not PlayerDataManager.SpendCoins(revivingPlayer, coinCost) then return end
			local ev = ReplicatedStorage:FindFirstChild("Events")
			local ce = ev and ev:FindFirstChild("CoinsUpdate")
			if ce then ce:FireClient(revivingPlayer, PlayerDataManager.GetCoins(revivingPlayer)) end
		elseif currency == "gems" then
			if not PlayerDataManager.SpendGems(revivingPlayer, gemCost) then return end
			local ev = ReplicatedStorage:FindFirstChild("Events")
			local ge = ev and ev:FindFirstChild("GemsUpdate")
			if ge then ge:FireClient(revivingPlayer, PlayerDataManager.GetGems(revivingPlayer)) end
		else
			return
		end
		FavoriteCreatureSystem.SetPvPFainted(revivingPlayer, false)
		FavoriteCreatureSystem.SpawnCompanion(revivingPlayer)
		if pvpEvents.PvPReviveSuccess then
			pvpEvents.PvPReviveSuccess:FireClient(revivingPlayer)
		end
	end)

	requestPvP.OnServerEvent:Connect(function(player, targetUserId)
		if not player or not targetUserId then
			print("[PvP] RequestPvPBattle: missing player or targetUserId")
			return
		end
		local target = Players:GetPlayerByUserId(targetUserId)
		print("[PvP] RequestPvPBattle from " .. player.Name .. " (" .. player.UserId .. ") -> targetUserId " .. tostring(targetUserId) .. " (resolved: " .. (target and target.Name or "nil") .. ")")
		if not target or target == player then
			if pvpEvents.PvPBattleReject then
				pvpEvents.PvPBattleReject:FireClient(player, "Invalid target.")
			end
			print("[PvP] Reject: invalid target")
			return
		end
		if activeBattle then
			if pvpEvents.PvPBattleReject then
				pvpEvents.PvPBattleReject:FireClient(player, "A PvP battle is already in progress.")
			end
			print("[PvP] Reject: battle already in progress")
			return
		end
		-- Store pending: target was challenged by player; send invite so target gets accept/decline prompt
		pendingChallenges[targetUserId] = player.UserId
		if pvpChallengeInvite then
			pvpChallengeInvite:FireClient(target, player.UserId, player.Name)
		end
	end)

	if pvpAcceptChallenge then
		pvpAcceptChallenge.OnServerEvent:Connect(function(player, requesterUserId)
			if not player or not requesterUserId then return end
			local requester = Players:GetPlayerByUserId(requesterUserId)
			if pendingChallenges[player.UserId] ~= requesterUserId or not requester or requester == player then
				if pvpEvents.PvPBattleReject then
					pvpEvents.PvPBattleReject:FireClient(player, "Challenge expired or invalid.")
				end
				pendingChallenges[player.UserId] = nil
				return
			end
			pendingChallenges[player.UserId] = nil
			task.spawn(function()
				startPvPBattle(requester, player)
			end)
		end)
	end

	if pvpDeclineChallenge then
		pvpDeclineChallenge.OnServerEvent:Connect(function(player, requesterUserId)
			if not player then return end
			pendingChallenges[player.UserId] = nil
			-- Optional: notify requester they were declined (could add PvPChallengeDeclined event)
		end)
	end

	print("[PvP] Initialized - challenge then confirm (like trade), winner +" .. WIN_GOLD .. " gold, loser -" .. LOSER_GOLD_LOSS .. " gold")
end

function PvPBattleSystem.IsBattleActive()
	return activeBattle
end

return PvPBattleSystem
