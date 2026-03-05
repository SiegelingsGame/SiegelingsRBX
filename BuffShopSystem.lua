-- BuffShopSystem.lua - ServerScriptService (ModuleScript)
-- Handles buff purchases and applies effects to player characters.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GameConfig = require(ReplicatedStorage.Modules.GameConfig)

local BuffShopSystem = {}

local PlayerDataManager

-- Look up buff config by id
local function getBuffConfig(buffId)
	for _, item in ipairs(GameConfig.BuffShopItems) do
		if item.id == buffId then return item end
	end
	return nil
end

-- -- APPLY BUFF EFFECTS --

local function applyBuffEffect(player, buffId, duration)
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChild("Humanoid")

	if buffId == "shield" then
		-- -50% damage: use ForceField-like visual
		local shield = Instance.new("ForceField")
		shield.Name = "BuffShield"; shield.Visible = true; shield.Parent = character
		task.delay(duration, function()
			if shield.Parent then shield:Destroy() end
		end)

	elseif buffId == "highjump" then
		if humanoid then
			local original = humanoid.JumpPower
			humanoid.JumpPower = original * 3
			task.delay(duration, function()
				if humanoid and humanoid.Parent then humanoid.JumpPower = original end
			end)
		end

	elseif buffId == "speed" then
		if humanoid then
			local original = humanoid.WalkSpeed
			humanoid.WalkSpeed = original * 2
			task.delay(duration, function()
				if humanoid and humanoid.Parent then humanoid.WalkSpeed = original end
			end)
		end

	elseif buffId == "invuln" then
		-- Full invulnerability via ForceField
		local ff = Instance.new("ForceField")
		ff.Name = "BuffInvuln"; ff.Visible = true; ff.Parent = character
		-- Also store flag on humanoid
		if humanoid then
			humanoid:SetAttribute("Invulnerable", true)
			task.delay(duration, function()
				if ff.Parent then ff:Destroy() end
				if humanoid and humanoid.Parent then humanoid:SetAttribute("Invulnerable", false) end
			end)
		end

	elseif buffId == "invis" then
		-- Make character invisible
		local parts = {}
		for _, part in ipairs(character:GetDescendants()) do
			if part:IsA("BasePart") then
				parts[part] = part.Transparency
				part.Transparency = 1
			elseif part:IsA("Decal") or part:IsA("Texture") then
				parts[part] = part.Transparency
				part.Transparency = 1
			end
		end
		-- Hide name
		if humanoid then humanoid.NameDisplayDistance = 0; humanoid.HealthDisplayDistance = 0 end
		task.delay(duration, function()
			for part, orig in pairs(parts) do
				if part.Parent then part.Transparency = orig end
			end
			if humanoid and humanoid.Parent then
				humanoid.NameDisplayDistance = 100; humanoid.HealthDisplayDistance = 100
			end
		end)

	elseif buffId == "swap" then
		-- Instant teleport to random other player
		local others = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= player and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
				table.insert(others, p)
			end
		end
		if #others > 0 then
			local target = others[math.random(#others)]
			local targetRoot = target.Character.HumanoidRootPart
			local myRoot = character:FindFirstChild("HumanoidRootPart")
			if myRoot and targetRoot then
				local myPos = myRoot.CFrame
				local theirPos = targetRoot.CFrame
				myRoot.CFrame = theirPos
				targetRoot.CFrame = myPos

				-- Notify both
				local events = ReplicatedStorage:FindFirstChild("Events")
				local capFail = events and events:FindFirstChild("CaptureFail")
				if capFail then
					capFail:FireClient(player, "Swapped with " .. target.Name .. "!")
					capFail:FireClient(target, "" .. player.Name .. " swapped places with you!")
				end
			end
		else
			local events = ReplicatedStorage:FindFirstChild("Events")
			local capFail = events and events:FindFirstChild("CaptureFail")
			if capFail then capFail:FireClient(player, "No other players to swap with!") end
		end
	end
end

-- -- INIT --

function BuffShopSystem.Init(pdm)
	PlayerDataManager = pdm

	local events = ReplicatedStorage:FindFirstChild("Events")
	local buyBuffEvent = events and events:FindFirstChild("BuyBuff")

	if buyBuffEvent then
		buyBuffEvent.OnServerInvoke = function(player, buffId, currency)
			local config = getBuffConfig(buffId)
			if not config then return false, "Invalid buff" end

			-- Check if already active (skip for instant buffs like swap)
			if config.duration > 0 and PlayerDataManager.HasBuff(player, buffId) then
				return false, "Buff already active!"
			end

			-- Charge
			if currency == "coins" then
				if config.coinCost <= 0 then return false, "Not available for coins" end
				local d = PlayerDataManager.GetData(player)
				if not d or d.coins < config.coinCost then return false, "Not enough coins!" end
				PlayerDataManager.SpendCoins(player, config.coinCost)
			elseif currency == "gems" then
				if config.gemCost <= 0 then return false, "Not available for gems" end
				if not PlayerDataManager.SpendGems(player, config.gemCost) then
					return false, "Not enough gems!"
				end
			else
				return false, "Invalid currency"
			end

			-- Activate
			if config.duration > 0 then
				PlayerDataManager.ActivateBuff(player, buffId, config.duration)
			end

			-- Apply effect
			applyBuffEffect(player, buffId, config.duration)

			-- Update coins on client
			local d = PlayerDataManager.GetData(player)
			local coinsEvt = events and events:FindFirstChild("CoinsUpdate")
			if coinsEvt and d then coinsEvt:FireClient(player, d.coins) end

			print("[BuffShop] " .. player.Name .. " bought " .. buffId .. " with " .. currency)
			return true, "Activated!"
		end
	end

	-- Shield damage reduction: hook into Humanoid.HealthChanged
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function(char)
			local humanoid = char:WaitForChild("Humanoid", 10)
			if not humanoid then return end
			local lastHP = humanoid.MaxHealth
			humanoid.HealthChanged:Connect(function(newHP)
				-- Shield: halve damage taken
				if PlayerDataManager.HasBuff(p, "shield") and newHP < lastHP then
					local dmg = lastHP - newHP
					humanoid.Health = newHP + dmg * 0.5 -- restore half the damage
				end
				lastHP = newHP
			end)
		end)
	end)

	print("[BuffShopSystem] Initialized - " .. #GameConfig.BuffShopItems .. " buffs available")
end

return BuffShopSystem