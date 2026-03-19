-- AIRaidSystem.lua - ServerScriptService (ModuleScript)
-- Wild creature packs periodically raid a random active player base.
-- Raiders use CreatureSpawner + CreatureAI "raider" behavior (no duplicate HP/movement).
-- Defense turrets auto-target raiders via "WorldCreature" tag.
-- Raiders target BaseDefenseCreature first, then BaseIncomeCreature.
-- On attack, a dice roll can "free" a base creature (spawns it wild).

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local DayNightCycle = nil
pcall(function() DayNightCycle = require(ServerScriptService.DayNightCycle) end)

local PlayerDataManager
local BasePlacementSystem
local CreatureSpawner
local CreatureAI

local AIRaidSystem = {}

local RAIDER_TAG = "AIRaider"

local raidActive = false
local lastRaidTarget = nil

-- -- ATTACK EFFECT (red bolt from raider to target) --

local function raiderAttackEffect(raiderModel, targetModel)
	local fromBody = raiderModel and raiderModel:FindFirstChild("Body")
	local toBody = targetModel and targetModel:FindFirstChild("Body")
	if not fromBody or not toBody then return end
	task.spawn(function()
		local bolt = Instance.new("Part")
		bolt.Size = Vector3.new(1.5, 1.5, 1.5); bolt.Shape = Enum.PartType.Ball
		bolt.Color = Color3.fromRGB(255, 40, 40); bolt.Material = Enum.Material.Neon
		bolt.Anchored = true; bolt.CanCollide = false; bolt.CastShadow = false
		bolt.Parent = workspace
		local dur = 0.25; local s = tick()
		while tick() - s < dur do
			bolt.Position = fromBody.Position:Lerp(toBody.Position, (tick() - s) / dur)
			RunService.Heartbeat:Wait()
		end
		bolt.Transparency = 0.5; task.wait(0.08); bolt:Destroy()
	end)
end

-- -- FREE A CREATURE (remove from player data, spawn wild) --

local function freeCreature(player, uid, plotModel)
	local entry = PlayerDataManager.RemoveCreature(player, uid)
	if not entry then return end

	local info = CreatureData.GetById(entry.id)
	if not info then return end

	if CreatureSpawner and CreatureSpawner.SpawnSpecificCreature then
		local plotCenter = plotModel:FindFirstChild("PlotCenter")
		local center = plotCenter and plotCenter.Position or plotModel:GetPivot().Position
		local offset = Vector3.new(math.random(-20, 20), 0, math.random(-20, 20))
		local spawnPos = center + offset + Vector3.new(0, GameConfig.SpawnHeightOffset, 0)

		local wildModel = CreatureSpawner.SpawnSpecificCreature(entry.id, spawnPos)
		if wildModel then
			wildModel:SetAttribute("CreatureLevel", entry.level or 1)
			wildModel:SetAttribute("CreatureXP", entry.xp or 0)
			local nameGui = wildModel:FindFirstChildWhichIsA("BillboardGui", true)
			if nameGui then
				local nameLabel = nameGui:FindFirstChildWhichIsA("TextLabel")
				if nameLabel and (entry.level or 1) > 1 then
					nameLabel.Text = nameLabel.Text .. " Lv." .. (entry.level or 1)
				end
			end
		end
	end

	return entry
end

-- -- SPAWN RAIDER PACK --
-- Uses CreatureSpawner for model/billboard/bob/HP, then customizes for raid

-- Door = where Ramp meets PlotCenter (entrance); raiders path here instead of clipping through walls.
local function getRaidDoorPosition(plotModel)
	local plotCenter = plotModel:FindFirstChild("PlotCenter", true)
	local ramp = plotModel:FindFirstChild("Ramp", true)
	local centerPos
	if plotCenter then
		if plotCenter:IsA("BasePart") then
			centerPos = plotCenter.Position
		else
			local ok, pivot = pcall(function() return plotCenter:GetPivot().Position end)
			centerPos = (ok and pivot) or plotModel:GetPivot().Position
		end
	else
		centerPos = plotModel:GetPivot().Position
	end
	if not ramp or not ramp:IsA("BasePart") then
		return centerPos + Vector3.new(0, 4, 0)
	end
	-- Midpoint between Ramp and PlotCenter in XZ; Y from PlotCenter so door is at base level
	local rx, _, rz = ramp.Position.X, ramp.Position.Y, ramp.Position.Z
	local cx, cy, cz = centerPos.X, centerPos.Y, centerPos.Z
	local doorX, doorZ = (rx + cx) * 0.5, (rz + cz) * 0.5
	return Vector3.new(doorX, cy + 4, doorZ)
end

local function spawnRaiderPack(plotModel, count, target, raidData)
	local raiderModels = {}
	local plotCenter = plotModel:FindFirstChild("PlotCenter", true)
	local center = (plotCenter and plotCenter:IsA("BasePart") and plotCenter.Position) or plotModel:GetPivot().Position
	local raidDoor = getRaidDoorPosition(plotModel)

	local spawnRadius = GameConfig.DefenseAttackRange + 35 -- ~75 studs outside defense range

	local events = ReplicatedStorage:FindFirstChild("Events")

	for i = 1, count do
		local creatureId = CreatureData.GetRandomCreatureId()
		local info = CreatureData.GetById(creatureId)
		if not info then continue end

		local raiderLevel = math.random(2, 6)
		-- Use GetEffectiveStats so rank-based level scaling and rarity apply (variant = Normal for raiders)
		local raiderStats = (PlayerDataManager and PlayerDataManager.GetEffectiveStats) and PlayerDataManager.GetEffectiveStats(creatureId, raiderLevel, "Normal")
		local hp = raiderStats and math.floor(raiderStats.health * 0.90) or math.floor(info.health * (1 + GameConfig.StatGainPerLevel * (raiderLevel - 1)) * 0.90)

		local angle = (i / count) * math.pi * 2 + math.random() * 0.3
		local offset = Vector3.new(math.cos(angle) * spawnRadius, 0, math.sin(angle) * spawnRadius)
		local spawnPos = center + offset + Vector3.new(0, 4, 0)

		-- Use existing spawner (creates model, billboard, bob animation, HP bar, AI registration)
		local model = CreatureSpawner.SpawnSpecificCreature(creatureId, spawnPos)
		if not model then continue end

		-- Tag as raider
		CollectionService:AddTag(model, RAIDER_TAG)
		model:SetAttribute("RaiderLevel", raiderLevel)

		-- Red hostile highlight (replace the rarity highlight)
		local existingHL = model:FindFirstChildOfClass("Highlight")
		if existingHL then existingHL:Destroy() end
		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(255, 30, 30); hl.FillTransparency = 0.5
		hl.OutlineColor = Color3.fromRGB(255, 60, 60); hl.OutlineTransparency = 0
		hl.Parent = model

		-- Update billboard: add RAIDER label, red name color, show level
		local bb = model:FindFirstChild("NameTag")
		if bb then
			local nameLabel = bb:FindFirstChild("NameLabel")
			if nameLabel then
				nameLabel.Text = info.displayName .. " Lv." .. raiderLevel
				nameLabel.TextColor3 = Color3.fromRGB(255, 80, 60)
			end
			local behaviorLabel = bb:FindFirstChild("BehaviorLabel")
			if behaviorLabel then
				behaviorLabel.Text = "RAIDER"
				behaviorLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
				behaviorLabel.Font = Enum.Font.GothamBlack
			end
		end

		-- Make core red
		local core = model:FindFirstChild("Core")
		if core then core.Color = Color3.fromRGB(255, 40, 40) end

		-- Override CreatureAI state: raider behavior, scaled HP, attack effect only (free happens on defeat in runRaid)
		local aiState = CreatureAI.GetState(model)
		if aiState then
			aiState.hp = hp
			aiState.maxHp = hp
			aiState.behavior = "raider"
			aiState.state = "idle"
			aiState.raidCenter = center + Vector3.new(0, 4, 0)
			aiState.raidDoor = raidDoor -- path to door (Ramp/PlotCenter) before going to targets

			-- Attack callback: visual effect only. Raid only succeeds when raiders actually defeat (faint) a base creature (handled in OnCreatureFainted).
			aiState.onAttackHit = function(raiderModel, targetModel, damage)
				raiderAttackEffect(raiderModel, targetModel)
			end
		end

		-- Sync HP attribute for external systems
		model:SetAttribute("HP", hp)
		model:SetAttribute("MaxHP", hp)

		table.insert(raiderModels, model)
	end

	return raiderModels
end

-- -- RUN A RAID --

local function runRaid()
	if raidActive then return end
	-- AI raids only occur during the night cycle
	if DayNightCycle and DayNightCycle.IsNight and not DayNightCycle.IsNight() then
		return
	end

	local candidates = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local d = PlayerDataManager.GetData(p)
		if d and d.plotId and d.plotId > 0 then
			table.insert(candidates, p)
		end
	end
	if #candidates == 0 then return end

	-- Pick target, avoid same player twice in a row
	local target = candidates[math.random(#candidates)]
	if #candidates > 1 and target == lastRaidTarget then
		for _, c in ipairs(candidates) do
			if c ~= lastRaidTarget then target = c; break end
		end
	end
	lastRaidTarget = target

	local data = PlayerDataManager.GetData(target)
	if not data then return end

	local plotsFolder = workspace:FindFirstChild("BasePlots")
	if not plotsFolder then return end
	local plotModel = nil
	for _, child in ipairs(plotsFolder:GetChildren()) do
		if child.Name == ("Plot" .. data.plotId) or child.Name == ("Part" .. data.plotId) then
			plotModel = child; break
		end
	end
	if not plotModel then return end

	raidActive = true
	local packMin, packMax = GameConfig.AIRaidPackSize[1], GameConfig.AIRaidPackSize[2]
	local packSize = math.random(packMin, packMax)

	print("[AIRaid] Raiding " .. target.Name .. "'s base with " .. packSize .. " creatures!")

	-- Notify all players
	local events = ReplicatedStorage:FindFirstChild("Events")
	local raidAlert = events and events:FindFirstChild("AIRaidAlert")
	if raidAlert then
		for _, p in ipairs(Players:GetPlayers()) do
			raidAlert:FireClient(p, target.Name, packSize, "start")
		end
	end

	-- Shared raid state for callbacks
	local raidData = { creatureFreed = false }

	-- Spawn raider pack (CreatureAI handles all movement/combat)
	local raiderModels = spawnRaiderPack(plotModel, packSize, target, raidData)

	-- Raid only succeeds when raiders actually defeat (faint) a base creature — listen for that
	local faintedConn = nil
	if CreatureAI and CreatureAI.OnCreatureFainted then
		faintedConn = CreatureAI.OnCreatureFainted.Event:Connect(function(faintedModel, killerModel)
			if raidData.creatureFreed then return end
			if not faintedModel or not faintedModel.Parent then return end
			if not killerModel or not CollectionService:HasTag(killerModel, RAIDER_TAG) then return end
			local isDefense = CollectionService:HasTag(faintedModel, "BaseDefenseCreature")
			local isIncome = CollectionService:HasTag(faintedModel, "BaseIncomeCreature")
			if not isDefense and not isIncome then return end
			local uid = faintedModel:GetAttribute("UID")
			if not uid then return end
			local ownerUserId = faintedModel:GetAttribute("OwnerUserId")
			if not ownerUserId or Players:GetPlayerByUserId(ownerUserId) ~= target then return end

			local freed = freeCreature(target, uid, plotModel)
			if freed then
				local fInfo = CreatureData.GetById(freed.id)
				local fName = fInfo and fInfo.displayName or freed.id
				print("[AIRaid] Raid succeeded: raiders defeated " .. fName .. " (Lv." .. (freed.level or 1) .. ") - freed from " .. target.Name)
				raidData.creatureFreed = true
				local slotType = faintedModel:GetAttribute("SlotType")
				local slotIndex = faintedModel:GetAttribute("SlotIndex")
				if slotType and slotIndex and BasePlacementSystem and BasePlacementSystem.ClearCreatureAtSlot then
					BasePlacementSystem.ClearCreatureAtSlot(target, slotType, slotIndex)
				elseif faintedModel.Parent then
					faintedModel:Destroy()
				end
				local creatureFreedByRaid = events and events:FindFirstChild("CreatureFreedByRaid")
				if creatureFreedByRaid then
					creatureFreedByRaid:FireClient(target, fName, freed.level or 1)
				end
			end
		end)
	end

	local raidStart = tick()
	local raidDuration = GameConfig.AIRaidDuration

	-- Monitor loop: just check if raiders are alive and if a creature was freed
	while tick() - raidStart < raidDuration do
		task.wait(1)

		-- End early if a creature was freed
		if raidData.creatureFreed then
			print("[AIRaid] Creature freed - raid ending early!")
			break
		end

		-- Count living raiders
		local livingCount = 0
		for _, model in ipairs(raiderModels) do
			if model.Parent then
				local aiState = CreatureAI and CreatureAI.GetState(model)
				if aiState and aiState.state ~= "faint" then
					livingCount = livingCount + 1
				end
			end
		end
		if livingCount == 0 then
			print("[AIRaid] All raiders killed by defenses!")
			if PlayerDataManager and PlayerDataManager.NotifyAchievement then
				PlayerDataManager.NotifyAchievement("OnDefenseSuccess", target, "ai_raid")
			end
			break
		end
	end

	-- Despawn surviving raiders with fade-out effect
	for _, model in ipairs(raiderModels) do
		if model and model.Parent then
			local aiState = CreatureAI and CreatureAI.GetState(model)
			if aiState and aiState.state ~= "faint" then
				-- Fade out then remove
				task.spawn(function()
					local body = model:FindFirstChild("Body")
					if body then
						for i = 1, 10 do
							body.Size = body.Size * 0.85; body.Transparency = i / 10
							local core = model:FindFirstChild("Core")
							if core then core.Transparency = i / 10 end
							RunService.Heartbeat:Wait()
						end
					end
					if CreatureSpawner then
						CreatureSpawner.RemoveCreature(model)
					elseif model.Parent then
						model:Destroy()
					end
				end)
			else
				-- Already fainted, clean up after a delay
				task.delay(3, function()
					if CreatureSpawner then
						CreatureSpawner.RemoveCreature(model)
					elseif model and model.Parent then
						model:Destroy()
					end
				end)
			end
		end
	end

	-- Removed post-raid base refresh - it caused a disjointed "base reset" feeling
	-- (PlaceCreatures clears and respawns all models; prefer base stays as-is)

	if raidAlert then
		for _, p in ipairs(Players:GetPlayers()) do
			raidAlert:FireClient(p, target.Name, 0, "end")
		end
	end

	if faintedConn then faintedConn:Disconnect() end
	print("[AIRaid] Raid on " .. target.Name .. "'s base ended")
	raidActive = false
end

-- -- INIT --

function AIRaidSystem.Init(playerDataMgr, basePlacementRef, creatureSpawnerRef, creatureAIRef)
	PlayerDataManager = playerDataMgr
	BasePlacementSystem = basePlacementRef
	CreatureSpawner = creatureSpawnerRef
	CreatureAI = creatureAIRef

	task.spawn(function()
		task.wait(30) -- initial delay
		while true do
			task.wait(GameConfig.AIRaidInterval)
			local ok, err = pcall(runRaid)
			if not ok then warn("[AIRaid] Error: " .. tostring(err)) end
		end
	end)

	print("[AIRaidSystem] Initialized - raiders use CreatureAI 'raider' behavior")
end

return AIRaidSystem
