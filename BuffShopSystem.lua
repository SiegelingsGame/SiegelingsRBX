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
		-- -50% damage: use ForceField-like visuald
		local shield = Instance.new("ForceField")
		shield.Name = "BuffShield"
		shield.Visible = true
		shield.Parent = character
		task.delay(duration, function()
			if shield.Parent then
				shield:Destroy()
			end
		end)

	elseif buffId == "highjump" then
		if humanoid then
			-- Moon-like jump: 10x height (floaty, dramatic arc)
			local origHeight = humanoid.JumpHeight or 7.2
			humanoid.JumpHeight = origHeight * 10
			task.delay(duration, function()
				if humanoid and humanoid.Parent then
					humanoid.JumpHeight = origHeight
				end
			end)
		end

	elseif buffId == "speed" then
		if humanoid then
			local original = humanoid.WalkSpeed
			humanoid.WalkSpeed = original * 2
			task.delay(duration, function()
				if humanoid and humanoid.Parent then
					humanoid.WalkSpeed = original
				end
			end)
		end

	elseif buffId == "invuln" then
		-- Full invulnerability via ForceField
		local ff = Instance.new("ForceField")
		ff.Name = "BuffInvuln"
		ff.Visible = true
		ff.Parent = character
		-- Also store flag on humanoid
		if humanoid then
			humanoid:SetAttribute("Invulnerable", true)
			task.delay(duration, function()
				if ff.Parent then
					ff:Destroy()
				end
				if humanoid and humanoid.Parent then
					humanoid:SetAttribute("Invulnerable", false)
				end
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
		if humanoid then
			humanoid.NameDisplayDistance = 0
			humanoid.HealthDisplayDistance = 0
		end
		task.delay(duration, function()
			for part, orig in pairs(parts) do
				if part.Parent then
					part.Transparency = orig
				end
			end
			if humanoid and humanoid.Parent then
				humanoid.NameDisplayDistance = 100
				humanoid.HealthDisplayDistance = 100
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
			if capFail then
				capFail:FireClient(player, "No other players to swap with!")
			end
		end

	elseif buffId == "lowgrav" then
		if humanoid then
			local root = character:FindFirstChild("HumanoidRootPart")
			if root then
				local bf = Instance.new("BodyForce")
				bf.Name = "BuffLowGrav"
				bf.Force = Vector3.new(0, root.AssemblyMass * workspace.Gravity * 0.75, 0)
				bf.Parent = root
				task.delay(duration, function()
					if bf.Parent then
						bf:Destroy()
					end
				end)
			end
		end

	elseif buffId == "regen" then
		if humanoid then
			local conn
			conn = game:GetService("RunService").Heartbeat:Connect(function()
				if not humanoid.Parent or humanoid.Health <= 0 then
					conn:Disconnect()
					return
				end
				humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + 2 / 60)
			end)
			task.delay(duration, function()
				if conn then
					conn:Disconnect()
				end
			end)
		end

	elseif buffId == "doublejump" then
		if humanoid then
			humanoid:SetAttribute("BuffDoubleJump", true)
			task.delay(duration, function()
				if humanoid and humanoid.Parent then
					humanoid:SetAttribute("BuffDoubleJump", nil)
				end
			end)
		end

	elseif buffId == "glide" then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root then
			local bv = Instance.new("BodyVelocity")
			bv.Name = "BuffGlide"
			bv.MaxForce = Vector3.new(0, 0, 0)
			bv.Velocity = Vector3.new(0, 0, 0)
			bv.Parent = root
			local conn
			conn = game:GetService("RunService").Heartbeat:Connect(function()
				if not bv.Parent or not root.Parent then
					conn:Disconnect()
					return
				end
				local vel = root.AssemblyLinearVelocity
				if vel.Y < -10 then
					bv.MaxForce = Vector3.new(4000, 4000, 4000)
					bv.Velocity = Vector3.new(vel.X * 0.9, math.max(vel.Y, -12), vel.Z * 0.9)
				else
					bv.MaxForce = Vector3.new(0, 0, 0)
				end
			end)
			task.delay(duration, function()
				if conn then
					conn:Disconnect()
				end
				if bv.Parent then
					bv:Destroy()
				end
			end)
		end

	elseif buffId == "xpboost" then
		if humanoid then
			humanoid:SetAttribute("BuffXpBoost", true)
			task.delay(duration, function()
				if humanoid and humanoid.Parent then
					humanoid:SetAttribute("BuffXpBoost", nil)
				end
			end)
		end

	elseif buffId == "coinboost" then
		-- Passive: PlayerDataManager.HasBuff checks activeBuffs; no character change
		-- Buff is stored in PlayerDataManager; BaseIncomeSystem can check HasBuff

	elseif buffId == "haste" then
		if humanoid then
			local orig = humanoid.WalkSpeed
			humanoid.WalkSpeed = orig * 1.5
			task.delay(duration, function()
				if humanoid and humanoid.Parent then
					humanoid.WalkSpeed = orig
				end
			end)
		end

	elseif buffId == "giant" then
		local stored = {}
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and not d:IsA("Terrain") then
				stored[d] = d.Size
				d.Size = d.Size * 2
			end
		end
		task.delay(duration, function()
			for part, origSize in pairs(stored) do
				if part.Parent then
					part.Size = origSize
				end
			end
		end)

	elseif buffId == "glow" then
		local root = character:FindFirstChild("HumanoidRootPart")
		if root and not root:FindFirstChild("BuffGlow") then
			local pl = Instance.new("PointLight")
			pl.Name = "BuffGlow"
			pl.Brightness = 2
			pl.Range = 20
			pl.Color = Color3.fromRGB(255, 220, 150)
			pl.Parent = root
			task.delay(duration, function()
				if pl.Parent then
					pl:Destroy()
				end
			end)
		end

	elseif buffId == "antifall" then
		if humanoid then
			humanoid:SetAttribute("NoFallDamage", true)
			task.delay(duration, function()
				if humanoid and humanoid.Parent then
					humanoid:SetAttribute("NoFallDamage", nil)
				end
			end)
		end

	elseif buffId == "swimspeed" then
		if humanoid then
			local orig = humanoid.SwimSpeed or 16
			humanoid.SwimSpeed = orig * 3
			task.delay(duration, function()
				if humanoid and humanoid.Parent then
					humanoid.SwimSpeed = orig
				end
			end)
		end

	elseif buffId == "lucky" then
		-- Passive: CaptureSystem checks PlayerDataManager.HasBuff("lucky") for better odds
	end
end

-- Buffs that only affect data (no character effect to re-apply on respawn)
local PASSIVE_BUFF_IDS = { coinboost = true, lucky = true }
-- Instant one-shot buffs (no duration)
local INSTANT_BUFF_IDS = { swap = true }

-- Re-apply active buff effects when player gets a character (e.g. after respawn)
local function reapplyBuffsOnCharacter(player)
	local character = player.Character
	if not character then return end
	local activeBuffs = PlayerDataManager.GetActiveBuffs(player)
	local now = tick()
	for buffId, info in pairs(activeBuffs) do
		if PASSIVE_BUFF_IDS[buffId] or INSTANT_BUFF_IDS[buffId] then
			-- skip
		else
			local expiresAt = info and info.expiresAt
			if expiresAt and expiresAt > now then
				local remaining = expiresAt - now
				applyBuffEffect(player, buffId, remaining)
			end
		end
	end
end

-- Double-jump: Humanoid.Jumping + StateChanged
local function setupDoubleJump(player)
	player.CharacterAdded:Connect(function(char)
		local humanoid = char:WaitForChild("Humanoid", 10)
		if not humanoid then return end
		local jumpsLeft = 0
		humanoid.StateChanged:Connect(function(_, newState)
			if newState == Enum.HumanoidStateType.Landed or newState == Enum.HumanoidStateType.Running then
				jumpsLeft = (humanoid:GetAttribute("BuffDoubleJump") and 1) or 0
			end
		end)
		if humanoid:GetAttribute("BuffDoubleJump") and (humanoid:GetState() == Enum.HumanoidStateType.Landed or humanoid:GetState() == Enum.HumanoidStateType.Running) then
			jumpsLeft = 1
		end
		humanoid.Jumping:Connect(function()
			if humanoid:GetAttribute("BuffDoubleJump") and (humanoid:GetState() == Enum.HumanoidStateType.Freefall or humanoid:GetState() == Enum.HumanoidStateType.Flying) and jumpsLeft > 0 then
				jumpsLeft = 0
				local root = char:FindFirstChild("HumanoidRootPart")
				if root then
					local v = root.AssemblyLinearVelocity
					local jumpVel = math.sqrt(2 * workspace.Gravity * (humanoid.JumpHeight or 7.2))
					root.AssemblyLinearVelocity = Vector3.new(v.X, jumpVel, v.Z)
				end
			end
		end)
	end)
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

			-- Update coins/gems on client
			local d = PlayerDataManager.GetData(player)
			if d then
				local coinsEvt = events and events:FindFirstChild("CoinsUpdate")
				if coinsEvt then coinsEvt:FireClient(player, d.coins) end
				if currency == "gems" then
					local gemsEvt = events and events:FindFirstChild("GemsUpdate")
					if gemsEvt then gemsEvt:FireClient(player, PlayerDataManager.GetGems(player)) end
				end
			end

			print("[BuffShop] " .. player.Name .. " bought " .. buffId .. " with " .. currency)
			return true, "Activated!"
		end
	end

	for _, p in ipairs(Players:GetPlayers()) do setupDoubleJump(p) end
	Players.PlayerAdded:Connect(setupDoubleJump)

	-- Re-apply active buff effects when character spawns (fixes buffs not applying after respawn or when bought without character)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			reapplyBuffsOnCharacter(p)
		end)
		-- If they already have a character, apply now
		if p.Character then
			task.defer(function() reapplyBuffsOnCharacter(p) end)
		end
	end)
	-- Existing players already in game when Init runs
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			task.defer(function() reapplyBuffsOnCharacter(p) end)
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