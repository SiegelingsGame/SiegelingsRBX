-- DesertGymSystem.lua - ServerScriptService (ModuleScript)
-- DesertBiome DesertGym: touch ArenaBase for [E] "Summon Gym". Requires battle team; pay entry fee; fight 5 high-level Fire + Earth gym leader squad.
-- Structure: Biomes -> DesertBiome -> DesertGym -> ArenaBase, BlueTeam, RedTeam (same as Arena).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataManager = nil
local GymBattleSystem = nil

local DesertGymSystem = {}

local desertGymFolder = nil
local arenaBasePart = nil
local promptRange = 10
local entryFee = 100
local gymEvents = {}

local function getArenaBasePart(gym)
	local ab = gym:FindFirstChild("ArenaBase")
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
	if not desertGymFolder or not GymBattleSystem then return end

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

	local fee = entryFee
	local coins = data.coins or 0
	if coins < fee then
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, "You need " .. fee .. " coins to challenge the Desert Gym.") end
		return
	end
	PlayerDataManager.AddCoins(player, -fee)

	local config = {
		gymName = "Desert Gym",
		elements = { "Psychic", "Undead" },
		level = GameConfig.DesertGymCreatureLevel or 45,
		winReward = GameConfig.DesertGymWinReward or 250,
		winXP = GameConfig.DesertGymWinXP or 75,
		cooldown = GameConfig.DesertGymCooldown or 120,
		zoneKey = "Desert",
		cooldownKey = "DesertGym",
	}
	local ok, err = GymBattleSystem.StartGymBattle(player, desertGymFolder, config)
	if not ok then
		PlayerDataManager.AddCoins(player, fee)
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, err or "Could not start gym battle.") end
	end
end

local function discoverGymFolder()
	local biomes = workspace:FindFirstChild("Biomes") or workspace:WaitForChild("Biomes", 15)
	local desertBiome = nil
	if biomes then
		desertBiome = biomes:FindFirstChild("DesertBiome") or biomes:WaitForChild("DesertBiome", 10)
	end
	if not desertBiome then
		desertBiome = workspace:FindFirstChild("DesertBiome") or workspace:WaitForChild("DesertBiome", 10)
	end
	if not desertBiome then
		warn("[DesertGym] DesertBiome folder not found in workspace or Biomes (waited 15s)")
		return nil, nil
	end

	local gym = desertBiome:FindFirstChild("DesertGym") or desertBiome:WaitForChild("DesertGym", 10)
	if not gym then
		warn("[DesertGym] DesertGym not found inside " .. desertBiome:GetFullName())
		return nil, nil
	end

	local basePart = getArenaBasePart(gym)
	if not basePart then
		local ab = gym:WaitForChild("ArenaBase", 5)
		if ab then basePart = getArenaBasePart(gym) end
	end
	return gym, basePart
end

function DesertGymSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr
	local GymModule = script.Parent:FindFirstChild("WaterGymBattleSystem")
	if GymModule then
		GymBattleSystem = require(GymModule)
	end
	if not GymBattleSystem then
		warn("[DesertGym] WaterGymBattleSystem not found - Desert gym battles disabled")
		return
	end

	promptRange = GameConfig.DesertGymPromptRange or 10
	entryFee = GameConfig.DesertGymEntryFee or 100

	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then events = Instance.new("Folder") events.Name = "Events" events.Parent = ReplicatedStorage end
	local function mkEvent(name)
		local e = events:FindFirstChild(name)
		if not e then e = Instance.new("RemoteEvent") e.Name = name e.Parent = events end
		return e
	end
	gymEvents.GymReject = mkEvent("GymReject")

	task.spawn(function()
		desertGymFolder, arenaBasePart = discoverGymFolder()
		if not desertGymFolder then
			warn("[DesertGym] Could not find DesertGym folder - gym prompt disabled")
			return
		end
		if not arenaBasePart then
			warn("[DesertGym] ArenaBase not found in " .. desertGymFolder:GetFullName() .. " (need a Part or Model named ArenaBase)")
			return
		end

		if not desertGymFolder:FindFirstChild("BlueTeam") or not desertGymFolder:FindFirstChild("RedTeam") then
			warn("[DesertGym] DesertGym must contain BlueTeam and RedTeam folders with BattlePoint1..9")
		end

		local existing = arenaBasePart:FindFirstChildOfClass("ProximityPrompt")
		local prompt = existing or Instance.new("ProximityPrompt")
		prompt.ActionText = "Summon Gym"
		prompt.ObjectText = "Desert Gym (" .. entryFee .. " coins)"
		prompt.MaxActivationDistance = promptRange
		prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
		if not existing then
			prompt.Name = "DesertGymPrompt"
			prompt.Parent = arenaBasePart
		end
		prompt.Triggered:Connect(onGymPromptTriggered)

		print("[DesertGym] Initialized - ArenaBase [E] Summon Gym in " .. desertGymFolder:GetFullName() .. ", entry " .. entryFee .. " coins")
	end)
end

return DesertGymSystem
