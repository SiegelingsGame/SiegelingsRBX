-- BattleTeamSystem.lua - ServerScriptService (ModuleScript)
-- Manages battle team composition: up to 5 creatures placed on a 3x3 grid (9 BattlePoints).
-- Spawns visual orbs on BattlePoint parts in the player's plot.
-- Provides the foundation for moving teams into combat arenas.
--
-- IMPORTANT: BattlePoints are inside Floor2/BattleTeam/ (not at plot root).
-- getBattlePoints uses GetDescendants on the full plot to find them regardless of nesting.
--
-- NOTE: MainServer.lua is the primary handler for AssignToBattle/RemoveFromBattle events.
-- If MainServer already handles these remotes, this module's Init() event listeners
-- will be secondary. Avoid running both simultaneously to prevent double-handling.
--
-- Data model: player.battleTeam = { [slotIndex] = uid or nil }.
--   slotIndex 1-9 maps to BattlePoint1-9 (top-left to bottom-right)
--   max 5 of 9 slots can be filled..

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local CreatureData = require(ReplicatedStorage.Modules.CreatureData)
local CreatureModelLoader = require(ReplicatedStorage.Modules.CreatureModelLoader)
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PlayerDataManager

local BattleTeamSystem = {}

local BATTLE_TAG = "BattleTeamCreature"
local MAX_TEAM_SIZE = 5
local GRID_SIZE = 9

-- --------------------------------------
-- HELPERS
-- --------------------------------------

local function findPlotModel(plotId)
	local folder = Workspace:FindFirstChild("BasePlots")
	if not folder then return nil end
	return folder:FindFirstChild("Plot" .. plotId)
		or folder:FindFirstChild("Part" .. plotId)
end

-- FIX: BattleTeam folder is now INSIDE Floor2 (e.g. Plot1/Floor2/BattleTeam/BattlePoint1).
-- FindFirstChild("BattleTeam") on plotModel only checks DIRECT children, so it fails.
-- Solution: Always use GetDescendants on the entire plotModel to find BattlePoints
-- regardless of how deeply nested they are.
local function getBattlePoints(plotModel)
	local points = {}
	for _, child in ipairs(plotModel:GetDescendants()) do
		if child:IsA("BasePart") then
			local num = child.Name:match("^BattlePoint(%d+)$")
			if num then
				points[tonumber(num)] = child
			end
		end
	end
	return points
end

-- Count filled slots in battle team
-- FIX #10: Use pairs() to handle string keys from DataStore serialization.
local function countTeamMembers(battleTeam)
	local count = 0
	for _, uid in pairs(battleTeam) do
		if uid then count = count + 1 end
	end
	return count
end

-- Get creature IDs from battle team for synergy calculation
-- FIX #10: Use pairs() to handle string keys from DataStore serialization.
local function getTeamCreatureIds(battleTeam, inventory)
	local ids = {}
	local uidToId = {}
	for _, entry in ipairs(inventory) do
		if entry.uid then uidToId[tostring(entry.uid)] = entry.id end
	end
	for _, uid in pairs(battleTeam) do
		if uid and uidToId[tostring(uid)] then
			table.insert(ids, uidToId[tostring(uid)])
		end
	end
	return ids
end

-- --------------------------------------
-- SPAWN BATTLE CREATURE ORB
-- --------------------------------------

local function spawnBattleOrb(creatureId, battlePointPart, uid, slotIndex, plotModel)
	local info = CreatureData.GetById(creatureId)
	if not info then return nil end

	local rarityInfo = CreatureData.Rarities[info.rarity]
	local rarityColor = rarityInfo and rarityInfo.color or Color3.fromRGB(180, 180, 180)
	local elementInfo = CreatureData.Elements[info.element]
	local classInfo = CreatureData.Classes[info.class]
	local elementColor = elementInfo and elementInfo.color or Color3.fromRGB(200, 200, 200)

	local model = Instance.new("Model")
	model.Name = "Battle_" .. info.id .. "_" .. uid
	model:SetAttribute("UID", uid)
	model:SetAttribute("CreatureId", creatureId)
	model:SetAttribute("SlotIndex", slotIndex)
	model:SetAttribute("Element", info.element)
	model:SetAttribute("Class", info.class)
	CollectionService:AddTag(model, BATTLE_TAG)

	-- Position on top of the BattlePoint (avoids clipping through Floor 2)
	local bodySize = 6
	local battlePointTopY = battlePointPart.Position.Y + (battlePointPart.Size.Y * 0.5)
	local bodyCenterY = battlePointTopY + (bodySize * 0.5)

	-- Main body
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = Enum.PartType.Ball
	body.Size = Vector3.new(4.5, 4.5, 4.5)
	body.Color = info.primaryColor
	body.Material = Enum.Material.Neon
	body.Anchored = true
	body.CanCollide = false
	body.CastShadow = true
	body.Position = Vector3.new(battlePointPart.Position.X, bodyCenterY, battlePointPart.Position.Z)
	body.Parent = model

	-- Element-colored core
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(2.2, 2.2, 2.2)
	core.Color = elementColor
	core.Material = Enum.Material.Neon
	core.Transparency = 0.2
	core.Anchored = true
	core.CanCollide = false
	core.CastShadow = false
	core.Position = body.Position
	core.Parent = model

	-- Light
	local light = Instance.new("PointLight")
	light.Color = elementColor
	light.Brightness = 2.5
	light.Range = 14
	light.Parent = body

	-- Highlight
	local highlight = Instance.new("Highlight")
	highlight.FillColor = elementColor
	highlight.FillTransparency = 0.8
	highlight.OutlineColor = rarityColor
	highlight.OutlineTransparency = 0.3
	highlight.Parent = model

	-- Billboard: name + element/class (offset to top of bounding box so name isn't blocked)
	local billboard = Instance.new("BillboardGui")
	billboard.Adornee = body
	billboard.Size = UDim2.new(0, 180, 0, 60)
	billboard.StudsOffset = Vector3.new(0, CreatureModelLoader.GetBillboardStudsOffsetForTopOfModel(model, body), 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = model

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, 0, 0.45, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Text = info.displayName
	nameLabel.TextColor3 = Color3.new(1, 1, 1)
	nameLabel.TextScaled = true
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.Parent = billboard

	local traitLabel = Instance.new("TextLabel")
	traitLabel.Size = UDim2.new(1, 0, 0.3, 0)
	traitLabel.Position = UDim2.new(0, 0, 0.45, 0)
	traitLabel.BackgroundTransparency = 1
	traitLabel.Text = info.element .. " " .. info.class
	traitLabel.TextColor3 = elementColor
	traitLabel.TextScaled = true
	traitLabel.Font = Enum.Font.GothamMedium
	traitLabel.Parent = billboard

	local slotLabel = Instance.new("TextLabel")
	slotLabel.Size = UDim2.new(1, 0, 0.25, 0)
	slotLabel.Position = UDim2.new(0, 0, 0.75, 0)
	slotLabel.BackgroundTransparency = 1
	slotLabel.Text = "BATTLE [" .. slotIndex .. "]"
	slotLabel.TextColor3 = Color3.fromRGB(255, 200, 80)
	slotLabel.TextScaled = true
	slotLabel.Font = Enum.Font.GothamMedium
	slotLabel.Parent = billboard

	-- Ground ring (element color)
	local ring = Instance.new("Part")
	ring.Name = "BattleRing"
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.3, 6, 6)
	ring.Color = elementColor
	ring.Material = Enum.Material.Neon
	ring.Transparency = 0.5
	ring.Anchored = true
	ring.CanCollide = false
	ring.CastShadow = false
	ring.CFrame = CFrame.new(battlePointPart.Position.X, battlePointTopY + 0.2, battlePointPart.Position.Z)
		* CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model

	model.PrimaryPart = body
	model.Parent = plotModel

	-- Hover + rotation
	task.spawn(function()
		local startY = body.Position.Y
		local coreStartY = core.Position.Y
		local t = math.random() * math.pi * 2

		while model.Parent and body.Parent do
			local dt = RunService.Heartbeat:Wait()
			t = t + dt * 1.8 * math.pi * 2

			local bob = math.sin(t) * 0.6
			body.Position = Vector3.new(body.Position.X, startY + bob, body.Position.Z)
			if core.Parent then
				core.Position = Vector3.new(core.Position.X, coreStartY + bob, core.Position.Z)
				core.Transparency = 0.2 + math.sin(t * 2.5) * 0.15
			end
		end
	end)

	return model
end

-- --------------------------------------
-- CLEAR + PLACE
-- --------------------------------------

local function clearBattleCreatures(plotModel)
	for _, child in ipairs(plotModel:GetDescendants()) do
		if child:IsA("Model") and CollectionService:HasTag(child, BATTLE_TAG) then
			child:Destroy()
		end
	end
end

function BattleTeamSystem.PlaceTeam(player)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.plotId or data.plotId == 0 then return end
	if not data.battleTeam then return end

	local plotModel = findPlotModel(data.plotId)
	if not plotModel then return end

	clearBattleCreatures(plotModel)

	local battlePoints = getBattlePoints(plotModel)
	local placed = 0

	-- FIX #9/#10: Use pairs() to handle string keys from DataStore.
	-- Try tonumber(slotKey) for battlePoints lookup since points are stored with number keys.
	for slotKey, uid in pairs(data.battleTeam) do
		local slotIndex = tonumber(slotKey) or slotKey
		if uid and battlePoints[slotIndex] then
			local su = tostring(uid)
			for _, entry in ipairs(data.inventory) do
				if entry.uid and tostring(entry.uid) == su then
					spawnBattleOrb(entry.id, battlePoints[slotIndex], uid, slotIndex, plotModel)
					placed = placed + 1
					break
				end
			end
		end
	end

	print("[BattleTeam] " .. player.Name .. ": " .. placed .. "/" .. MAX_TEAM_SIZE .. " battle team placed")
end

-- --------------------------------------
-- TEAM MANAGEMENT
-- --------------------------------------

-- Assign a creature to a battle grid slot
function BattleTeamSystem.AssignToSlot(player, uid, slotIndex)
	local data = PlayerDataManager.GetData(player)
	if not data then return false, "No data" end

	if slotIndex < 1 or slotIndex > GRID_SIZE then return false, "Invalid slot" end

	-- Initialize battleTeam if missing
	if not data.battleTeam then
		data.battleTeam = {}
	end

	-- If uid is nil/empty, clear the slot
	if not uid or uid == "" then
		data.battleTeam[slotIndex] = nil
		return true, "Cleared"
	end

	-- Verify creature exists in inventory
	local su = tostring(uid or "")
	local found = false
	for _, entry in ipairs(data.inventory) do
		if entry.uid and tostring(entry.uid) == su then found = true break end
	end
	if not found then return false, "Not in inventory" end

	-- Check team size (if creature is new to the team)
	-- FIX #10: Use pairs() to handle string keys from DataStore.
	local alreadyOnTeam = false
	local currentSlot = nil
	for key, val in pairs(data.battleTeam) do
		if val and tostring(val) == su then
			alreadyOnTeam = true
			currentSlot = tonumber(key) or key
			break
		end
	end

	if not alreadyOnTeam and countTeamMembers(data.battleTeam) >= MAX_TEAM_SIZE then
		return false, "Team full (5/5)"
	end

	-- Remove from old slot if moving
	if currentSlot then
		data.battleTeam[currentSlot] = nil
	end

	-- Check if target slot is occupied (swap)
	local displaced = data.battleTeam[slotIndex]
	if displaced and currentSlot then
		-- Swap: put displaced into old slot
		data.battleTeam[currentSlot] = displaced
	end

	-- Place creature
	data.battleTeam[slotIndex] = uid
	return true, "Assigned"
end

-- Remove a creature from battle team entirely
-- FIX #10: Use pairs() to handle string keys from DataStore.
function BattleTeamSystem.RemoveFromTeam(player, uid)
	local data = PlayerDataManager.GetData(player)
	if not data or not data.battleTeam then return false end
	local su = tostring(uid or "")
	for key, val in pairs(data.battleTeam) do
		if val and tostring(val) == su then
			data.battleTeam[key] = nil
			return true
		end
	end
	return false
end

-- Get team data with synergy info for UI
function BattleTeamSystem.GetTeamData(player)
	local data = PlayerDataManager.GetData(player)
	if not data then return nil end

	local team = data.battleTeam or {}
	local teamCreatureIds = getTeamCreatureIds(team, data.inventory)
	local synergies, elementCounts, classCounts = CreatureData.CalculateSynergies(teamCreatureIds)

	-- Build slot info
	-- FIX #10: Use pairs() to handle string keys from DataStore.
	local slots = {}
	for key, uid in pairs(team) do
		local slotNum = tonumber(key) or key
		if uid then
			local creatureId = nil
			local su = tostring(uid)
			for _, entry in ipairs(data.inventory) do
				if entry.uid and tostring(entry.uid) == su then
					creatureId = entry.id
					break
				end
			end
			slots[slotNum] = {
				uid = uid,
				creatureId = creatureId,
			}
		end
	end

	return {
		slots = slots,
		teamSize = countTeamMembers(team),
		maxTeamSize = MAX_TEAM_SIZE,
		synergies = synergies,
		elementCounts = elementCounts,
		classCounts = classCounts,
	}
end

-- --------------------------------------
-- INIT
-- --------------------------------------

function BattleTeamSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr

	local events = ReplicatedStorage:WaitForChild("Events", 10)

	-- AssignToBattle: (uid, slotIndex) � place creature on grid
	local assignToBattle = events:FindFirstChild("AssignToBattle")
	if assignToBattle then
		assignToBattle.OnServerEvent:Connect(function(player, uid, slotIndex)
			local success, msg = BattleTeamSystem.AssignToSlot(player, uid, slotIndex)
			if success then
				BattleTeamSystem.PlaceTeam(player)
			else
				warn("[BattleTeam] " .. player.Name .. " assign failed: " .. msg)
			end
		end)
	end

	-- RemoveFromBattle: (uid) � remove from team
	local removeFromBattle = events:FindFirstChild("RemoveFromBattle")
	if removeFromBattle then
		removeFromBattle.OnServerEvent:Connect(function(player, uid)
			BattleTeamSystem.RemoveFromTeam(player, uid)
			BattleTeamSystem.PlaceTeam(player)
		end)
	end

	-- GetBattleTeam: returns team data + synergies
	local getBattleTeam = events:FindFirstChild("GetBattleTeam")
	if getBattleTeam then
		getBattleTeam.OnServerInvoke = function(player)
			return BattleTeamSystem.GetTeamData(player)
		end
	end

	-- Place teams on join
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Wait()
		task.wait(3)
		BattleTeamSystem.PlaceTeam(player)
	end)

	for _, p in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			task.wait(2)
			BattleTeamSystem.PlaceTeam(p)
		end)
	end

	-- Cleanup on leave
	Players.PlayerRemoving:Connect(function(player)
		local data = PlayerDataManager.GetData(player)
		if data and data.plotId and data.plotId > 0 then
			local plotModel = findPlotModel(data.plotId)
			if plotModel then clearBattleCreatures(plotModel) end
		end
	end)

	print("[BattleTeamSystem] Initialized � " .. MAX_TEAM_SIZE .. " max team, " .. GRID_SIZE .. " grid slots")
end

return BattleTeamSystem