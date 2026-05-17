-- ZoneDoorSystem.lua - ServerScriptService (ModuleScript)
-- Zone doors for Ocean, Desert, Electric, Cave. Locked until player spends 4 inner boss Legendaries at the door.
-- Per-player collision: PhysicsService groups so only unlocked players can walk through their gate.

local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PlayerDataManager = nil

local ZoneDoorSystem = {}

local ZONE_IDS = GameConfig.ZoneDoorZoneIds or { "Ocean", "Desert", "Electric", "Cave" }
-- Session bookkeeping so we don't double-wire; also used for late-streamed parts
local gateZonesWired = {}
local gatePartsWired = {}
local function getPromptRange()
	return tonumber(GameConfig.ZoneDoorPromptRange) or 28
end
local function getZoneDoorPartNames()
	local t = GameConfig.ZoneDoorPartNames
	if type(t) == "table" and #t > 0 then
		return t
	end
	return { "ZoneDoor", "ZoneDoorTrigger", "GateTrigger", "BiomeGate" }
end

local collisionInitialized = false

local function zoneIndexFor(zoneId)
	for i, z in ipairs(ZONE_IDS) do
		if z == zoneId then
			return i - 1
		end
	end
	return nil
end

local function getUnlockBitmask(player)
	local bm = 0
	for i, zid in ipairs(ZONE_IDS) do
		if PlayerDataManager and PlayerDataManager.IsDoorUnlocked(player, zid) then
			bm = bit32.bor(bm, bit32.lshift(1, i - 1))
		end
	end
	return bm
end

local function registerCollisionGroups()
	if collisionInitialized then
		return
	end
	local ok, err = pcall(function()
		for i = 0, 3 do
			PhysicsService:RegisterCollisionGroup("ZD_" .. i)
		end
		for bm = 0, 15 do
			PhysicsService:RegisterCollisionGroup("ZDPlayer_" .. bm)
		end
		local function bitSet(bm, bitIndex)
			return bit32.band(bm, bit32.lshift(1, bitIndex)) ~= 0
		end
		for bm = 0, 15 do
			local pg = "ZDPlayer_" .. bm
			PhysicsService:CollisionGroupSetCollidable(pg, "Default", true)
			for doorIdx = 0, 3 do
				local collide = not bitSet(bm, doorIdx)
				PhysicsService:CollisionGroupSetCollidable(pg, "ZD_" .. doorIdx, collide)
			end
			for other = 0, 15 do
				PhysicsService:CollisionGroupSetCollidable(pg, "ZDPlayer_" .. other, true)
			end
		end
	end)
	if not ok then
		warn("[ZoneDoorSystem] Collision setup failed: " .. tostring(err))
		return
	end
	collisionInitialized = true
end

local function setAllBasePartsCollisionGroup(root, groupName)
	if root:IsA("BasePart") then
		root.CollisionGroup = groupName
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CollisionGroup = groupName
		end
	end
end

function ZoneDoorSystem.ApplyZoneDoorCollisionToCharacter(player)
	if not collisionInitialized or not player or not player.Parent then
		return
	end
	local char = player.Character
	if not char then
		return
	end
	local bm = getUnlockBitmask(player)
	local gName = "ZDPlayer_" .. bm
	setAllBasePartsCollisionGroup(char, gName)
end

local function hookCharacterCollision(player)
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("HumanoidRootPart", 15)
		task.defer(function()
			ZoneDoorSystem.ApplyZoneDoorCollisionToCharacter(player)
		end)
		char.DescendantAdded:Connect(function(inst)
			if inst:IsA("BasePart") then
				local bm = getUnlockBitmask(player)
				inst.CollisionGroup = "ZDPlayer_" .. bm
			end
		end)
	end)
	if player.Character then
		task.defer(function()
			ZoneDoorSystem.ApplyZoneDoorCollisionToCharacter(player)
		end)
	end
end

local function cleanupLegacyZoneDoorGuis(part)
	for _, name in ipairs({ "ZoneDoorInfoBoard", "ZoneDoorBoardAttach" }) do
		local x = part:FindFirstChild(name)
		if x then
			x:Destroy()
		end
	end
end

local function findBiomeFolder(biomes, folderName)
	if not folderName or folderName == "" then
		return nil
	end
	local direct = biomes:FindFirstChild(folderName)
	if direct and (direct:IsA("Folder") or direct:IsA("Model")) then
		return direct
	end
	-- Nested (e.g. Biomes > World > CaveBiome) or non-standard tree
	local deep = biomes:FindFirstChild(folderName, true)
	if deep and (deep:IsA("Folder") or deep:IsA("Model")) then
		return deep
	end
	return nil
end

local function getBiomeFolderForZone(zoneId, biomes)
	local folders = GameConfig.ZoneDoorBiomeFolders
	local name = folders and folders[zoneId]
	local f = name and findBiomeFolder(biomes, name)
	if f then
		return f
	end
	local aliases = GameConfig.ZoneDoorBiomeAliases and GameConfig.ZoneDoorBiomeAliases[zoneId]
	if aliases then
		for _, alias in ipairs(aliases) do
			f = findBiomeFolder(biomes, alias)
			if f then
				return f
			end
		end
	end
	if zoneId == "Desert" then
		f = findBiomeFolder(biomes, "VolcanicBiome")
		if f then
			return f
		end
	end
	return nil
end

-- Any depth under the biome folder; prefers first name in ZoneDoorPartNames order.
local function findZoneDoorInstance(folder)
	if not folder then
		return nil
	end
	for _, partName in ipairs(getZoneDoorPartNames()) do
		local door = folder:FindFirstChild(partName, true)
		if door and (door:IsA("BasePart") or door:IsA("Model")) then
			return door
		end
	end
	return nil
end

local function getPromptAnchorPart(door)
	if door:IsA("BasePart") then
		return door
	end
	if door:IsA("Model") then
		if door.PrimaryPart then
			return door.PrimaryPart
		end
		for _, c in ipairs(door:GetDescendants()) do
			if c:IsA("BasePart") then
				return c
			end
		end
	end
	return nil
end

local function getZoneDoorRootFromInstance(door)
	return door
end

local function onZoneDoorTriggered(zoneId, player)
	if not player or not player:IsA("Player") or not player.Parent then return end
	if not PlayerDataManager then return end
	if PlayerDataManager.IsDoorUnlocked(player, zoneId) then
		return
	end
end

local function wireZoneDoor(zoneId, doorInst, partForPrompt, promptRange)
	local zIdx = zoneIndexFor(zoneId)
	if zIdx ~= nil and collisionInitialized then
		local doorRoot = getZoneDoorRootFromInstance(doorInst)
		if doorRoot then
			setAllBasePartsCollisionGroup(doorRoot, "ZD_" .. zIdx)
		end
	end

	partForPrompt:SetAttribute("ZoneDoorZoneId", zoneId)

	-- Tall walls put the default prompt at the part center (high in the air). Anchor to bottom edge in object space.
	local att = partForPrompt:FindFirstChild("ZoneDoorPromptAnchor")
	if not att or not att:IsA("Attachment") then
		if att then
			att:Destroy()
		end
		att = Instance.new("Attachment")
		att.Name = "ZoneDoorPromptAnchor"
		att.Parent = partForPrompt
	end
	local sz = partForPrompt.Size
	local lift = math.clamp(sz.Y * 0.06, 2, 10)
	att.Position = Vector3.new(0, -sz.Y / 2 + lift, 0)

	for _, ch in ipairs(partForPrompt:GetChildren()) do
		if ch:IsA("ProximityPrompt") and ch.Name == "ZoneDoorPrompt" then
			ch:Destroy()
		end
	end
	local oldOnAtt = att:FindFirstChild("ZoneDoorPrompt")
	if oldOnAtt then
		oldOnAtt:Destroy()
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ZoneDoorPrompt"
	prompt.ActionText = "Open gate"
	do
		local ib = GameConfig.ZoneDoorInfoBoard
		local disp = (type(ib) == "table" and ib.ZoneTitles and ib.ZoneTitles[zoneId]) or zoneId
		prompt.ObjectText = tostring(disp) .. " gate"
	end
	prompt.MaxActivationDistance = promptRange
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Enabled = true
	local uiOff = GameConfig.ZoneDoorPromptUIOffset
	if typeof(uiOff) == "Vector2" then
		prompt.UIOffset = uiOff
	else
		prompt.UIOffset = Vector2.new(0, 12)
	end
	prompt.Parent = att

	prompt.Triggered:Connect(function(plr)
		onZoneDoorTriggered(zoneId, plr)
	end)
	cleanupLegacyZoneDoorGuis(partForPrompt)
	print("[ZoneDoorSystem] " .. zoneId .. " gate prompt on " .. att:GetFullName())
end

-- When ZoneDoorsDisabled: same door discovery as normal, but all blocking parts become walk-through.
local function makeZoneDoorPassable(zoneId, doorInst)
	local doorRoot = getZoneDoorRootFromInstance(doorInst)
	if not doorRoot then
		return
	end
	if doorRoot:IsA("BasePart") then
		doorRoot.CanCollide = false
	end
	for _, d in ipairs(doorRoot:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
		end
	end
	local path = doorRoot:GetFullName()
	print("[ZoneDoorSystem] " .. zoneId .. " gate passable (ZoneDoorsDisabled) at " .. path)
end

function ZoneDoorSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr
	local doorsDisabled = (GameConfig.ZoneDoorsDisabled == true)

	if not doorsDisabled then
		registerCollisionGroups()

		local events = ReplicatedStorage:FindFirstChild("Events")
		if not events then
			events = Instance.new("Folder")
			events.Name = "Events"
			events.Parent = ReplicatedStorage
		end
		local function ensureEvent(name)
			local e = events:FindFirstChild(name)
			if not e then
				e = Instance.new("RemoteEvent")
				e.Name = name
				e.Parent = events
			end
			return e
		end
		ensureEvent("ZoneDoorLocked")

		for _, plr in ipairs(Players:GetPlayers()) do
			hookCharacterCollision(plr)
		end
		Players.PlayerAdded:Connect(hookCharacterCollision)
	end

	local zoneIds = ZONE_IDS

	task.spawn(function()
		local biomes = workspace:WaitForChild("Biomes", 60)
		if not biomes then
			warn("[ZoneDoorSystem] Workspace.Biomes not found - zone doors disabled")
			return
		end

		local promptRange = getPromptRange()

		local function tryZoneDoor(zoneId, doorInst)
			-- One prompt per zone; first successful wire wins (see attribute-before-folder ordering below).
			if gateZonesWired[zoneId] then
				return false
			end
			local anchor = getPromptAnchorPart(doorInst)
			if not anchor then
				return false
			end
			if gatePartsWired[anchor] then
				return false
			end
			gatePartsWired[anchor] = true
			gateZonesWired[zoneId] = true
			if doorsDisabled then
				makeZoneDoorPassable(zoneId, doorInst)
			else
				wireZoneDoor(zoneId, doorInst, anchor, promptRange)
			end
			return true
		end

		-- Prefer explicit BaseParts with Attribute ZoneDoorZoneId (e.g. wide cave mouth) BEFORE named parts in the biome folder.
		-- Otherwise findZoneDoorInstance can wire a small/wrong part first and the attribute pass was skipped (gateZonesWired[zid]).
		for _, inst in ipairs(biomes:GetDescendants()) do
			if inst:IsA("BasePart") then
				local zid = inst:GetAttribute("ZoneDoorZoneId")
				if type(zid) == "string" and zid ~= "" then
					for _, zoneId in ipairs(zoneIds) do
						if zoneId == zid then
							tryZoneDoor(zoneId, inst)
							break
						end
					end
				end
			end
		end

		for _, zoneId in ipairs(zoneIds) do
			if gateZonesWired[zoneId] then
				-- Already wired from explicit ZoneDoorZoneId part(s).
			else
				local folder = getBiomeFolderForZone(zoneId, biomes)
				if not folder then
					if zoneId ~= "Desert" then
						warn(
							"[ZoneDoorSystem] No biome folder for "
								.. tostring(zoneId)
								.. " (check GameConfig.ZoneDoorBiomeFolders / ZoneDoorBiomeAliases vs workspace.Biomes)"
						)
					end
				else
					local doorInst = findZoneDoorInstance(folder)
					if not doorInst then
						warn(
							"[ZoneDoorSystem] No zone door part in "
								.. folder:GetFullName()
								.. ". Add a Part or Model named "
								.. table.concat(getZoneDoorPartNames(), ", ")
								.. " (anywhere under this folder), or any BasePart with Attribute ZoneDoorZoneId=\""
								.. zoneId
								.. "\""
						)
					else
						tryZoneDoor(zoneId, doorInst)
					end
				end
			end
		end

		biomes.DescendantAdded:Connect(function(inst)
			task.defer(function()
				if not inst:IsA("BasePart") then
					return
				end
				local zid = inst:GetAttribute("ZoneDoorZoneId")
				if type(zid) ~= "string" or zid == "" or gateZonesWired[zid] then
					return
				end
				for _, zoneId in ipairs(zoneIds) do
					if zoneId == zid and not gatePartsWired[inst] then
						tryZoneDoor(zoneId, inst)
						break
					end
				end
			end)
		end)

		if not doorsDisabled then
			for _, zoneId in ipairs(zoneIds) do
				if not gateZonesWired[zoneId] then
					warn(
						"[ZoneDoorSystem] Zone \""
							.. zoneId
							.. "\" has no gate prompt. Add a Part under the biome with Attribute ZoneDoorZoneId=\""
							.. zoneId
							.. "\" (size it across the opening; Transparent, CanCollide true)"
					)
				end
			end
		end
	end)
end

return ZoneDoorSystem
