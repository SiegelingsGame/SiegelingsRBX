-- PlayerHealthSystem.lua - ServerScriptService (ModuleScript)
-- Handles player health: initial setup and rapid regeneration after 5 seconds out of combat.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PlayerDataManager = require(ServerScriptService.PlayerDataManager)

local PlayerHealthSystem = {}

-- Per-player: last time damage was taken (for out-of-combat tracking)
local lastCombatTime = {}

local REGEN_TICK = 0.1  -- check regen every 0.1 sec
local lastRegenTick = 0

local function setupPlayerHealth(player, humanoid)
	local baseMaxHP = GameConfig.PlayerMaxHealth or 100
	local bonuses = PlayerDataManager.GetRebirthBonuses and PlayerDataManager.GetRebirthBonuses(player)
	local healthBonus = (bonuses and bonuses.healthBonus) or 0
	local maxHP = baseMaxHP + healthBonus
	humanoid.MaxHealth = maxHP
	humanoid.Health = maxHP

	-- Track damage taken for combat timer
	local lastHP = maxHP
	humanoid.HealthChanged:Connect(function(newHP)
		if newHP < lastHP then
			lastCombatTime[player.UserId] = tick()
		end
		lastHP = newHP
	end)

	lastCombatTime[player.UserId] = 0  -- start out of combat so regen can begin after 5 sec if damaged
end

local function tickRegen()
	local now = tick()
	if now - lastRegenTick < REGEN_TICK then return end
	lastRegenTick = now

	local delay = GameConfig.PlayerHealthOutOfCombatDelay or 5
	local regenPerSec = GameConfig.PlayerHealthRegenPerSecond or 100
	local healPerTick = regenPerSec * REGEN_TICK

	for _, player in ipairs(Players:GetPlayers()) do
		local char = player.Character
		if not char then continue end
		local humanoid = char:FindFirstChild("Humanoid")
		if not humanoid or humanoid.Health <= 0 then continue end

		-- Skip if invulnerable (e.g. BuffShop invuln buff)
		if humanoid:GetAttribute("Invulnerable") then continue end

		local maxHP = humanoid.MaxHealth
		if humanoid.Health >= maxHP then continue end

		local lastCombat = lastCombatTime[player.UserId] or 0
		if now - lastCombat < delay then continue end

		-- Out of combat: rapidly regenerate
		humanoid.Health = math.min(maxHP, humanoid.Health + healPerTick)
	end
end

function PlayerHealthSystem.Init()
	-- Setup new players and characters
	Players.PlayerAdded:Connect(function(player)
		player.CharacterAdded:Connect(function(char)
			local humanoid = char:WaitForChild("Humanoid", 10)
			if humanoid then
				setupPlayerHealth(player, humanoid)
			end
		end)
		-- Existing character (player rejoining)
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then setupPlayerHealth(player, humanoid) end
		end
	end)

	-- Handle players already in game
	for _, player in ipairs(Players:GetPlayers()) do
		if player.Character then
			local humanoid = player.Character:FindFirstChild("Humanoid")
			if humanoid then setupPlayerHealth(player, humanoid) end
		end
	end

	RunService.Heartbeat:Connect(tickRegen)

	Players.PlayerRemoving:Connect(function(player)
		lastCombatTime[player.UserId] = nil
	end)

end

return PlayerHealthSystem
