-- ZoneDoorSystem.lua - ServerScriptService (ModuleScript)
-- Zone doors for Ocean, Desert, Electric, Cave. Locked until player has 4 sigils (choose one door in Sigils UI)
-- or has a gym key for that zone. Prompt shows state; trigger fires client message when locked.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataManager = nil

local ZoneDoorSystem = {}

local PROMPT_RANGE = 12
local zoneDoors = {} -- zoneId -> { part = BasePart, prompt = ProximityPrompt }

local function getBiomeFolderForZone(zoneId)
	local biomes = workspace:FindFirstChild("Biomes")
	if not biomes then return nil end
	local folders = GameConfig.ZoneDoorBiomeFolders
	local name = folders and folders[zoneId]
	if name and biomes:FindFirstChild(name) then
		return biomes:FindFirstChild(name)
	end
	local aliases = GameConfig.ZoneDoorBiomeAliases and GameConfig.ZoneDoorBiomeAliases[zoneId]
	if aliases then
		for _, alias in ipairs(aliases) do
			local f = biomes:FindFirstChild(alias)
			if f then return f end
		end
	end
	-- Desert may map to VolcanicBiome if DesertBiome doesn't exist
	if zoneId == "Desert" and biomes:FindFirstChild("VolcanicBiome") then
		return biomes:FindFirstChild("VolcanicBiome")
	end
	return nil
end

local function getZoneDoorPart(folder)
	local door = folder:FindFirstChild("ZoneDoor")
	if not door then return nil end
	if door:IsA("BasePart") then return door end
	if door:IsA("Model") then
		if door.PrimaryPart then return door.PrimaryPart end
		for _, c in ipairs(door:GetDescendants()) do
			if c:IsA("BasePart") then return c end
		end
	end
	return nil
end

local function onZoneDoorTriggered(zoneId, player)
	if not player or not player:IsA("Player") or not player.Parent then return end
	if not PlayerDataManager then return end

	local unlocked = PlayerDataManager.IsDoorUnlocked(player, zoneId)
	local events = ReplicatedStorage:FindFirstChild("Events")
	local lockEvt = events and events:FindFirstChild("ZoneDoorLocked")

	if unlocked then
		-- Allow passage (no teleport); optional: fire ZoneDoorEntered for client effects
		return
	end

	-- Locked: send reason to client for toast/message
	local msg
	local data = PlayerDataManager.GetData(player)
	local sigilCount = PlayerDataManager.GetSigilCount(player)
	local firstOpened = data and (data.firstZoneDoorOpened or "")
	local hasKey = PlayerDataManager.HasZoneKey(player, zoneId)

	if sigilCount >= 4 and (not firstOpened or firstOpened == "") then
		msg = "You have 4 sigils! Open the Sigils tab in your Inventory to choose which zone door to unlock."
	elseif hasKey then
		msg = "You have a key for this zone. Open the Sigils tab to unlock this door."
	else
		msg = "Locked. Defeat the 4 boss sieglings to earn sigils, then open one zone door from the Sigils menu. Beat a zone's gym to earn a key for another."
	end

	if lockEvt then
		lockEvt:FireClient(player, zoneId, msg)
	end
end

function ZoneDoorSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr

	local zoneIds = GameConfig.ZoneDoorZoneIds or { "Ocean", "Desert", "Electric", "Cave" }
	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then
		events = Instance.new("Folder")
		events.Name = "Events"
		events.Parent = ReplicatedStorage
	end
	local function ensureEvent(name)
		local e = events:FindFirstChild(name)
		if not e then e = Instance.new("RemoteEvent") e.Name = name e.Parent = events end
		return e
	end
	ensureEvent("ZoneDoorLocked")

	task.spawn(function()
		local biomes = workspace:WaitForChild("Biomes", 20)
		if not biomes then
			warn("[ZoneDoorSystem] Workspace.Biomes not found - zone doors disabled")
			return
		end

		for _, zoneId in ipairs(zoneIds) do
			local folder = getBiomeFolderForZone(zoneId)
			if not folder then
				-- Optional: warn only for Ocean/Electric/Cave if Desert is optional
				if zoneId ~= "Desert" then
					warn("[ZoneDoorSystem] Biome folder for zone " .. tostring(zoneId) .. " not found")
				end
			else
				local part = getZoneDoorPart(folder)
				if not part then
					warn("[ZoneDoorSystem] ZoneDoor not found in " .. folder:GetFullName())
				else
					local existing = part:FindFirstChildOfClass("ProximityPrompt")
					local prompt = existing or Instance.new("ProximityPrompt")
					prompt.ActionText = "Zone Door"
					prompt.ObjectText = zoneId .. " Zone"
					prompt.MaxActivationDistance = PROMPT_RANGE
					prompt.HoldDuration = 0
					prompt.RequiresLineOfSight = false
					prompt.Enabled = true
					if not existing then
						prompt.Name = "ZoneDoorPrompt"
						prompt.Parent = part
					end
					prompt.Triggered:Connect(function(player)
						onZoneDoorTriggered(zoneId, player)
					end)
					zoneDoors[zoneId] = { part = part, prompt = prompt }
					print("[ZoneDoorSystem] " .. zoneId .. " ZoneDoor ready at " .. part:GetFullName())
				end
			end
		end
	end)
end

return ZoneDoorSystem
