-- PlayerHealthSystem.lua - ServerScriptService (ModuleScript)
-- Player health: initial setup. Regen only runs after PlayerHealthOutOfCombatDelay seconds
-- with no health decrease (damage, drowning, hazards — anything that lowers Humanoid.Health).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerScriptService = game:GetService("ServerScriptService")
local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local PlayerDataManager = require(ServerScriptService.PlayerDataManager)

local PlayerHealthSystem = {}

-- Per-player: tick() when Humanoid.Health last went down (regen allowed only after delay from this moment)
local lastHealthLossTime = {}

local REGEN_TICK = 0.1  -- how often to apply healing once the quiet period has passed
local lastRegenTick = 0

local function setupPlayerHealth(player, humanoid)
	local baseMaxHP = GameConfig.PlayerMaxHealth or 100
	local bonuses = PlayerDataManager.GetRebirthBonuses and PlayerDataManager.GetRebirthBonuses(player)
	local healthBonus = (bonuses and bonuses.healthBonus) or 0
	local maxHP = baseMaxHP + healthBonus
	humanoid.MaxHealth = maxHP
	humanoid.Health = maxHP

	-- Roblox may enable default humanoid health regen on some rigs; our rules are delay-gated only.
	pcall(function()
		humanoid.HealthRegenerationEnabled = false
	end)

	-- Any net decrease (TakeDamage, drowning server path, hazards) resets the quiet timer.
	local lastHP = maxHP
	humanoid.HealthChanged:Connect(function(newHP)
		if newHP < lastHP then
			lastHealthLossTime[player.UserId] = tick()
		end
		lastHP = newHP
	end)

	-- Must not use 0: (now - 0) >= delay would allow instant regen whenever HP < max.
	lastHealthLossTime[player.UserId] = tick()
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

		local lastLoss = lastHealthLossTime[player.UserId]
		if not lastLoss or (now - lastLoss) < delay then continue end

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
		lastHealthLossTime[player.UserId] = nil
	end)

end

return PlayerHealthSystem
