-- CaveGymSystem.lua - ServerScriptService (ModuleScript)
-- CaveBiome CaveGym: touch ArenaBase for [E] "Summon Gym". Requires battle team; pay entry fee; fight 5 high-level Shadow (and Earth) gym leader squad.
-- Structure: Biomes -> CaveBiome -> CaveGym -> ArenaBase, BlueTeam, RedTeam (same as Arena).

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)
local PlayerDataManager = nil
local GymBattleSystem = nil

local CaveGymSystem = {}

local caveGymFolder = nil
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
	if not caveGymFolder or not GymBattleSystem then return end

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
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, "You need " .. fee .. " coins to challenge the Cave Gym.") end
		return
	end
	PlayerDataManager.AddCoins(player, -fee)

	local config = {
		gymName = "Cave Gym",
		elements = { "Shadow", "Metal" },
		level = GameConfig.CaveGymCreatureLevel or 45,
		winReward = GameConfig.CaveGymWinReward or 250,
		winXP = GameConfig.CaveGymWinXP or 75,
		cooldown = GameConfig.CaveGymCooldown or 120,
		zoneKey = "Cave",
		cooldownKey = "CaveGym",
	}
	local ok, err = GymBattleSystem.StartGymBattle(player, caveGymFolder, config)
	if not ok then
		PlayerDataManager.AddCoins(player, fee)
		if gymEvents.GymReject then gymEvents.GymReject:FireClient(player, err or "Could not start gym battle.") end
	end
end

local function discoverGymFolder()
	local biomes = workspace:FindFirstChild("Biomes") or workspace:WaitForChild("Biomes", 15)
	local caveBiome = nil
	if biomes then
		caveBiome = biomes:FindFirstChild("CaveBiome") or biomes:FindFirstChild("CaveBiome_")
		if not caveBiome then
			caveBiome = biomes:WaitForChild("CaveBiome", 10) or biomes:FindFirstChild("CaveBiome_")
		end
	end
	if not caveBiome then
		caveBiome = workspace:FindFirstChild("CaveBiome") or workspace:FindFirstChild("CaveBiome_")
		if not caveBiome then
			caveBiome = workspace:WaitForChild("CaveBiome", 10) or workspace:FindFirstChild("CaveBiome_")
		end
	end
	if not caveBiome then
		warn("[CaveGym] CaveBiome folder not found in workspace or Biomes (waited 15s)")
		return nil, nil
	end

	local gym = caveBiome:FindFirstChild("CaveGym") or caveBiome:WaitForChild("CaveGym", 10)
	if not gym then
		warn("[CaveGym] CaveGym not found inside " .. caveBiome:GetFullName())
		return nil, nil
	end

	local basePart = getArenaBasePart(gym)
	if not basePart then
		local ab = gym:WaitForChild("ArenaBase", 5)
		if ab then basePart = getArenaBasePart(gym) end
	end
	return gym, basePart
end

function CaveGymSystem.Init(playerDataMgr)
	PlayerDataManager = playerDataMgr
	local GymModule = script.Parent:FindFirstChild("WaterGymBattleSystem")
	if GymModule then
		GymBattleSystem = require(GymModule)
	end
	if not GymBattleSystem then
		warn("[CaveGym] WaterGymBattleSystem not found - Cave gym battles disabled")
		return
	end

	promptRange = GameConfig.CaveGymPromptRange or 10
	entryFee = GameConfig.CaveGymEntryFee or 100

	local events = ReplicatedStorage:FindFirstChild("Events")
	if not events then events = Instance.new("Folder") events.Name = "Events" events.Parent = ReplicatedStorage end
	local function mkEvent(name)
		local e = events:FindFirstChild(name)
		if not e then e = Instance.new("RemoteEvent") e.Name = name e.Parent = events end
		return e
	end
	gymEvents.GymReject = mkEvent("GymReject")

	task.spawn(function()
		caveGymFolder, arenaBasePart = discoverGymFolder()
		if not caveGymFolder then
			warn("[CaveGym] Could not find CaveGym folder - gym prompt disabled")
			return
		end
		if not arenaBasePart then
			warn("[CaveGym] ArenaBase not found in " .. caveGymFolder:GetFullName() .. " (need a Part or Model named ArenaBase)")
			return
		end

		if not caveGymFolder:FindFirstChild("BlueTeam") or not caveGymFolder:FindFirstChild("RedTeam") then
			warn("[CaveGym] CaveGym must contain BlueTeam and RedTeam folders with BattlePoint1..9")
		end

		local existing = arenaBasePart:FindFirstChildOfClass("ProximityPrompt")
		local prompt = existing or Instance.new("ProximityPrompt")
		prompt.ActionText = "Summon Gym"
		prompt.ObjectText = "Cave Gym (" .. entryFee .. " coins)"
		prompt.MaxActivationDistance = promptRange
		prompt.HoldDuration = tonumber(GameConfig.HoldInteractionDuration) or 0.6
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.RequiresLineOfSight = false
		prompt.Enabled = true
		if not existing then
			prompt.Name = "CaveGymPrompt"
			prompt.Parent = arenaBasePart
		end
		prompt.Triggered:Connect(onGymPromptTriggered)

		print("[CaveGym] Initialized - ArenaBase [E] Summon Gym in " .. caveGymFolder:GetFullName() .. ", entry " .. entryFee .. " coins")
	end)
end

return CaveGymSystem
