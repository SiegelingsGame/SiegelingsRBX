-- DungeonSpawner.lua - ServerScriptService (ModuleScript)
-- Periodically spawns a "dungeon" landmark at the map outskirts.
-- Dungeon contains 2-4 legendary creatures that can be fought and captured.
-- Despawns after DungeonDuration seconds.

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local CreatureSpawner
local DungeonSpawner = {}

local DUNGEON_TAG = "DungeonBlock"
local activeDungeon = nil

-- -- BUILD DUNGEON STRUCTURE --

local function createDungeonBlock(position)
	local model = Instance.new("Model")
	model.Name = "Dungeon_" .. math.random(1000, 9999)

	-- Main platform
	local platform = Instance.new("Part")
	platform.Name = "DungeonPlatform"; platform.Size = Vector3.new(30, 2, 30)
	platform.Position = position; platform.Anchored = true; platform.CanCollide = true
	platform.Color = Color3.fromRGB(25, 10, 40); platform.Material = Enum.Material.Basalt
	platform.Parent = model

	-- Pillars at corners
	for _, offset in ipairs({Vector3.new(13, 8, 13), Vector3.new(-13, 8, 13), Vector3.new(13, 8, -13), Vector3.new(-13, 8, -13)}) do
		local pillar = Instance.new("Part")
		pillar.Size = Vector3.new(3, 16, 3); pillar.Position = position + offset
		pillar.Anchored = true; pillar.CanCollide = true
		pillar.Color = Color3.fromRGB(40, 15, 60); pillar.Material = Enum.Material.Slate
		pillar.Parent = model

		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(180, 50, 255); light.Brightness = 3; light.Range = 20
		light.Parent = pillar
	end

	-- Beacon effect (tall glowing pillar so players can see from distance)
	local beacon = Instance.new("Part")
	beacon.Name = "Beacon"; beacon.Size = Vector3.new(2, 200, 2)
	beacon.Position = position + Vector3.new(0, 100, 0)
	beacon.Anchored = true; beacon.CanCollide = false
	beacon.Color = Color3.fromRGB(255, 180, 0); beacon.Material = Enum.Material.Neon
	beacon.Transparency = 0.6; beacon.Parent = model

	local beaconLight = Instance.new("PointLight")
	beaconLight.Color = Color3.fromRGB(255, 180, 0); beaconLight.Brightness = 5; beaconLight.Range = 60
	beaconLight.Parent = beacon

	-- Billboard label
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.new(0, 250, 0, 60); bb.StudsOffset = Vector3.new(0, 18, 0)
	bb.AlwaysOnTop = true; bb.Adornee = platform; bb.Parent = model

	local titleLbl = Instance.new("TextLabel")
	titleLbl.Size = UDim2.new(1, 0, 0.55, 0); titleLbl.BackgroundTransparency = 1
	titleLbl.Text = "LEGENDARY DUNGEON"
	titleLbl.TextColor3 = Color3.fromRGB(255, 184, 0)
	titleLbl.Font = Enum.Font.GothamBlack; titleLbl.TextScaled = true
	titleLbl.TextStrokeColor3 = Color3.new(0, 0, 0); titleLbl.TextStrokeTransparency = 0.2
	titleLbl.Parent = bb

	local timerLbl = Instance.new("TextLabel")
	timerLbl.Name = "TimerLbl"; timerLbl.Size = UDim2.new(1, 0, 0.35, 0)
	timerLbl.Position = UDim2.new(0, 0, 0.6, 0); timerLbl.BackgroundTransparency = 1
	timerLbl.TextColor3 = Color3.fromRGB(200, 160, 80)
	timerLbl.Font = Enum.Font.GothamBold; timerLbl.TextScaled = true
	timerLbl.Parent = bb

	CollectionService:AddTag(model, DUNGEON_TAG)
	model.PrimaryPart = platform
	model.Parent = Workspace

	return model
end

-- Collect all DungeonPoint parts from biomes (same structure as CreatureSpawner)
local function getAllDungeonPoints()
	local points = {}
	local biomesFolder = Workspace:FindFirstChild("Biomes")
	if not biomesFolder then return points end

	for _, biomeFolder in ipairs(biomesFolder:GetChildren()) do
		if biomeFolder:IsA("Folder") then
			for _, child in ipairs(biomeFolder:GetChildren()) do
				if child:IsA("BasePart") and (child.Name == "DungeonPoint" or child.Name == "DungeonPoint2") then
					table.insert(points, child)
				end
			end
		end
	end
	return points
end

-- -- SPAWN DUNGEON --

local function spawnDungeon()
	if activeDungeon then return end

	local spawnPos
	local dungeonPoints = getAllDungeonPoints()

	if #dungeonPoints > 0 then
		-- Spawn on top of a random DungeonPoint placed in the world
		local chosen = dungeonPoints[math.random(1, #dungeonPoints)]
		local pt = chosen.Position
		-- Raycast down from slightly above the point to find ground (exclude DungeonPoint so we hit floor)
		local rayOrigin = Vector3.new(pt.X, pt.Y + 20, pt.Z)
		local rayDir = Vector3.new(0, -150, 0)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { chosen }
		local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
		local groundY = result and result.Position.Y or pt.Y
		spawnPos = Vector3.new(pt.X, groundY + 1, pt.Z)
	else
		-- Fallback: random position at outskirts when no DungeonPoints exist
		local radius = GameConfig.DungeonSpawnRadius or 250
		local angle = math.random() * math.pi * 2
		local x = math.cos(angle) * radius
		local z = math.sin(angle) * radius

		local rayOrigin = Vector3.new(x, 500, z)
		local rayDir = Vector3.new(0, -600, 0)
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
		local groundY = result and result.Position.Y or 5
		spawnPos = Vector3.new(x, groundY + 1, z)
	end

	-- Create dungeon structure
	local dungeonModel = createDungeonBlock(spawnPos)
	activeDungeon = dungeonModel

	print("[Dungeon] Spawned at (" .. math.floor(spawnPos.X) .. ", " .. math.floor(spawnPos.Y) .. ", " .. math.floor(spawnPos.Z) .. ")")

	-- Spawn legendary creatures on the platform
	local minC, maxC = GameConfig.DungeonCreatureCount[1], GameConfig.DungeonCreatureCount[2]
	local creatureCount = math.random(minC, maxC)

	-- Get all legendary creature IDs
	local legendaryIds = {}
	for _, c in ipairs(CreatureData.Creatures) do
		if c.rarity == "Legendary" then table.insert(legendaryIds, c.id) end
	end
	-- Fallback to Epic if no legendaries
	if #legendaryIds == 0 then
		for _, c in ipairs(CreatureData.Creatures) do
			if c.rarity == "Epic" then table.insert(legendaryIds, c.id) end
		end
	end

	local spawnedCreatures = {}
	for i = 1, creatureCount do
		if #legendaryIds == 0 then break end
		local cid = legendaryIds[math.random(#legendaryIds)]
		local offset = Vector3.new(math.random(-10, 10), 3, math.random(-10, 10))
		local cPos = spawnPos + offset

		if CreatureSpawner and CreatureSpawner.SpawnSpecificCreature then
			local cModel = CreatureSpawner.SpawnSpecificCreature(cid, cPos)
			if cModel then
				-- Give dungeon creatures higher level
				local dungeonLevel = math.random(5, 8)
				cModel:SetAttribute("CreatureLevel", dungeonLevel)
				cModel:SetAttribute("CreatureXP", 0)
				-- Update name to show level
				local nameGui = cModel:FindFirstChildWhichIsA("BillboardGui", true)
				if nameGui then
					local nameLabel = nameGui:FindFirstChildWhichIsA("TextLabel")
					if nameLabel then
						nameLabel.Text = nameLabel.Text .. " Lv." .. dungeonLevel
					end
				end
				table.insert(spawnedCreatures, cModel)
			end
		end
	end

	-- Notify all players
	local events = ReplicatedStorage:FindFirstChild("Events")
	local dungeonEvt = events and events:FindFirstChild("DungeonSpawned")
	if dungeonEvt then
		for _, p in ipairs(Players:GetPlayers()) do
			dungeonEvt:FireClient(p, spawnPos, creatureCount, GameConfig.DungeonDuration)
		end
	end

	-- Countdown timer update
	task.spawn(function()
		local platform = dungeonModel:FindFirstChild("DungeonPlatform")
		local billboardGui = dungeonModel:FindFirstChildWhichIsA("BillboardGui", true)
		local timerLbl = billboardGui and billboardGui:FindFirstChild("TimerLbl")

		local remaining = GameConfig.DungeonDuration
		while remaining > 0 and dungeonModel.Parent do
			if timerLbl then
				timerLbl.Text = "Despawns in " .. remaining .. "s"
			end
			task.wait(1)
			remaining = remaining - 1
		end
	end)

	-- Wait for duration then despawn
	task.wait(GameConfig.DungeonDuration)

	-- Despawn dungeon creatures that weren't captured
	for _, cModel in ipairs(spawnedCreatures) do
		if cModel and cModel.Parent and not cModel:GetAttribute("Fainted") then
			if CreatureSpawner and CreatureSpawner.RemoveCreature then
				CreatureSpawner.RemoveCreature(cModel)
			elseif cModel.Parent then
				cModel:Destroy()
			end
		end
	end

	-- Despawn dungeon structure
	if dungeonModel and dungeonModel.Parent then
		-- Fade beacon
		local beacon = dungeonModel:FindFirstChild("Beacon")
		if beacon then
			task.spawn(function()
				for i = 1, 20 do
					beacon.Transparency = 0.6 + (i / 20) * 0.4
					RunService.Heartbeat:Wait()
				end
			end)
		end

		task.wait(1)
		dungeonModel:Destroy()
	end

	-- Notify despawn
	local despawnEvt = events and events:FindFirstChild("DungeonDespawned")
	if despawnEvt then
		for _, p in ipairs(Players:GetPlayers()) do
			despawnEvt:FireClient(p)
		end
	end

	activeDungeon = nil
	print("[Dungeon] Despawned (+" .. #spawnedCreatures .. " creatures removed)")
end

-- -- INIT --

function DungeonSpawner.Init(creatureSpawnerRef)
	if not (GameConfig.LegendaryDungeonsEnabled) then
		print("[DungeonSpawner] Disabled via GameConfig.LegendaryDungeonsEnabled")
		return
	end
	CreatureSpawner = creatureSpawnerRef

	task.spawn(function()
		task.wait(60) -- initial delay
		while true do
			local ok, err = pcall(spawnDungeon)
			if not ok then warn("[Dungeon] Error: " .. tostring(err)) end
			task.wait(GameConfig.DungeonSpawnInterval)
		end
	end)

	print("[DungeonSpawner] Initialized - dungeons every " .. GameConfig.DungeonSpawnInterval .. "s")
end

return DungeonSpawner