-- WaterGymSystem.lua - ServerScriptService (ModuleScript)
-- OceanBiome WaterGym: touch ArenaBase for [E] "Summon Gym". Requires battle team; pay entry fee; fight 5 high-level Water/Ice/Fire gym leader squad.
-- Structure: Biomes (or workspace) -> OceanBiome -> WaterGym -> ArenaBase (Part or Model), BlueTeam, RedTeam (same as Arena).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataManager = nil
local GymBattleSystem = nil
local BasePlacementSystem = nil

local WaterGymSystem = {}

local waterGymFolder = nil
local arenaBasePart = nil   -- Part we attach ProximityPrompt to
local promptRange = 10
local entryFee = 100
local gymEvents = {}

-- Get the part to attach ProximityPrompt to (ArenaBase can be a Part or a Model with PrimaryPart/parts)
local function getArenaBasePart(waterGym)
	local ab = waterGym:FindFirstChild("ArenaBase")
	if not ab then return nil end
	if ab:IsA("BasePart") then return ab end
	if ab:IsA("Model") then
		if ab.PrimaryPart then return ab.PrimaryPart end
		for _, c in ipairs(ab:GetDescendants()) do
			if c:IsA("BasePart") then return c end
		end
	end
	return nil
end

local function onGymPromptTriggered(player)
	if not player or not player.Parent then return end
	if not waterGymFolder or not GymBattleSystem then return end

	-- 1) Check battle team (GymBattleSystem.StartGymBattle will also check; we check first to avoid deducting then failing)
	local data = PlayerDataManager and PlayerDataManager.GetData(player)
	if not data or not data.battleTeam then
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, "Cannot start gym without a battle team. Set one in your inventory (Battle tab).") end
		return
	end
	local teamCount = 0
	for _, uid in pairs(data.battleTeam or {}) do
		if uid and uid ~= "" then teamCount = teamCount + 1 end
	end
	if teamCount < (GameConfig.MinBattleTeamSize or 1) then
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, "Cannot start gym without a battle team. Set at least one creature in your battle grid (Battle tab).") end
		return
	end

	-- 2) Check and deduct entry fee
	local fee = entryFee
	local coins = data.coins or 0
	if coins < fee then
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, "You need " .. fee .. " coins to challenge the Water Gym.") end
		return
	end
	PlayerDataManager.AddCoins(player, -fee)

	-- 3) Start gym battle (separate system; does NOT share standard ArenaSystem state)
	local ok, err = GymBattleSystem.StartGymBattle(player, waterGymFolder)
	if not ok then
		-- Refund on failure (e.g. battle already in progress)
		PlayerDataManager.AddCoins(player, fee)
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, err or "Could not start gym battle.") end
	end
end

-- FIX: Discover the gym folder using WaitForChild with timeouts so the prompt
-- is reliably created even when the workspace map loads after server scripts init.
-- Also searches multiple common naming patterns (OceanBiome, OceanGym, Ocean Gym).
local function discoverGymFolder()
	-- Try Biomes container first, then workspace root.
	-- WaitForChild with timeout handles late-loading map geometry.
	local biomes = workspace:FindFirstChild("Biomes") or workspace:WaitForChild("Biomes", 15)
	local oceanBiome = nil
	if biomes then
		oceanBiome = biomes:FindFirstChild("OceanBiome")
			or biomes:FindFirstChild("OceanGym")
			or biomes:WaitForChild("OceanBiome", 10)
	end
	if not oceanBiome then
		-- Fallback: OceanBiome/OceanGym directly in workspace
		oceanBiome = workspace:FindFirstChild("OceanBiome")
			or workspace:FindFirstChild("OceanGym")
			or workspace:WaitForChild("OceanBiome", 10)
	end
	if not oceanBiome then
		warn("[WaterGym] OceanBiome folder not found in workspace or Biomes (waited 15s)")
		return nil, nil
	end

	-- WaterGym folder (or Model) inside the biome
	local gym = oceanBiome:FindFirstChild("WaterGym")
		or oceanBiome:FindFirstChild("OceanGym")
		or oceanBiome:WaitForChild("WaterGym", 10)
	if not gym then
		warn("[WaterGym] WaterGym not found inside " .. oceanBiome:GetFullName())
		return nil, nil
	end

	-- ArenaBase part inside the gym
	local basePart = getArenaBasePart(gym)
	if not basePart then
		-- ArenaBase might load slightly after the folder; wait briefly
		local ab = gym:WaitForChild("ArenaBase", 5)
		if ab then basePart = getArenaBasePart(gym) end
	end
	return gym, basePart
end

function WaterGymSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr
	local GymModule = script.Parent:FindFirstChild("WaterGymBattleSystem")
	if GymModule then
		GymBattleSystem = require(GymModule)
	end
	local BaseModule = script.Parent:FindFirstChild("BasePlacementSystem")
	if BaseModule then
		pcall(function() BasePlacementSystem = require(BaseModule) end)
	end
	if GymBattleSystem and GymBattleSystem.Init then
		GymBattleSystem.Init(PlayerDataManager, BasePlacementSystem)
	end
	if not GymBattleSystem then
		warn("[WaterGym] WaterGymBattleSystem not found - gym battles disabled")
		return
	end

	promptRange = GameConfig.WaterGymPromptRange or 10
	entryFee = GameConfig.WaterGymEntryFee or 100

	-- Create GymReject event for client feedback (do this early so it exists
	-- even if gym discovery takes time or fails)
	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then events = Instance.new("Folder") events.Name = "Events" events.Parent = ReplicatedStorage end
	local function mkEvent(name)
		local e = events:FindFirstChild(name)
		if not e then e = Instance.new("RemoteEvent") e.Name = name e.Parent = events end
		return e
	end
	gymEvents.GymReject = mkEvent("GymReject")

	-- FIX: Run gym discovery in a spawn so MainServer init isn't blocked by the
	-- WaitForChild timeouts, but the prompt still gets created once the map loads.
	task.spawn(function()
		waterGymFolder, arenaBasePart = discoverGymFolder()
		if not waterGymFolder then
			warn("[WaterGym] Could not find WaterGym folder - gym prompt disabled")
			return
		end
		if not arenaBasePart then
			warn("[WaterGym] ArenaBase not found in " .. waterGymFolder:GetFullName() .. " (need a Part or Model named ArenaBase)")
			return
		end

		-- Ensure BlueTeam/RedTeam exist (same structure as main Arena)
		if not waterGymFolder:FindFirstChild("BlueTeam") or not waterGymFolder:FindFirstChild("RedTeam") then
			warn("[WaterGym] WaterGym must contain BlueTeam and RedTeam folders with BattlePoint1..9")
		end

		-- Add ProximityPrompt to ArenaBase
		local existing = arenaBasePart:FindFirstChildOfClass("ProximityPrompt")
		local prompt = existing or Instance.new("ProximityPrompt")
		prompt.ActionText = "Summon Gym"
		prompt.ObjectText = "Water Gym (" .. entryFee .. " coins)"
		prompt.MaxActivationDistance = promptRange
		prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
		if not existing then
			prompt.Name = "WaterGymPrompt"
			prompt.Parent = arenaBasePart
		end
		prompt.Triggered:Connect(onGymPromptTriggered)

		print("[WaterGym] Initialized - ArenaBase [E] Summon Gym in " .. waterGymFolder:GetFullName() .. ", entry " .. entryFee .. " coins")
	end)
end

return WaterGymSystem
